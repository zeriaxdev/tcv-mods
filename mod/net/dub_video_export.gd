extends Node
## Renders a saved dub to MP4 in the background with the installed Choicer Voicer
## Exporter (exporter.py: centered mic takes, H.264 CRF 16, lossless WAV beside it).
## Lives on the scene root so leaving dub mode does not stop the export.

const OPEN_TEXT := "Open video"
const RETRY_TEXT := "Retry video"
const MAC_PYTHONS := ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]

static var last_video: String = ""
static var _last_args: Array = []  # [pack_path, session, title] of the latest export, for Retry video

var button: Control
var pid: int = -1
var log_path: String
var video: String


static func _first_existing(paths: Array) -> String:
	for path: String in paths:
		if path.begins_with("~/"): path = OS.get_environment("HOME") + path.substr(1)
		if FileAccess.file_exists(path): return path
	return ""


## The installers put exporter.py next to the game (Windows, Linux) or inside the
## built app (macOS); the standalone Mac Exporter app is a fallback.
static func _exporter_script() -> String:
	var exe_dir := OS.get_executable_path().get_base_dir()
	return _first_existing([
		exe_dir.path_join("exporter.py"),
		exe_dir.path_join("../Resources/exporter.py").simplify_path(),
		"/Applications/Choicer Voicer Exporter.app/Contents/Resources/exporter.py",
		"~/Applications/Choicer Voicer Exporter.app/Contents/Resources/exporter.py",
	])


static func _python() -> String:
	var found: Array = []
	match OS.get_name():
		"macOS":
			return _first_existing(MAC_PYTHONS)
		"Windows":
			for name: String in ["py", "python"]:  # py = the python.org launcher
				if OS.execute("where", [name], found) == 0: return name
			return ""
		_:
			return "python3" if OS.execute("which", ["python3"], found) == 0 else ""


## Starts the export; returns false (and says why on the button) when it cannot run.
static func start(save_button: Control, pack_path: String, session: String, title: String) -> bool:
	_last_args = [pack_path, session, title]
	var script := _exporter_script()
	var python := _python()
	if script.is_empty() or python.is_empty():
		_label(save_button, "No exporter" if script.is_empty() else "Needs Python")
		return false
	var videos := OS.get_system_dir(OS.SYSTEM_DIR_MOVIES)  # Movies on macOS, Videos elsewhere
	if videos.is_empty(): videos = OS.get_environment("HOME").path_join("Videos")
	var folder := videos.path_join("Choicer Voicer Exports")
	DirAccess.make_dir_recursive_absolute(folder)
	var base := folder.path_join(("%s — %s" % [title, session]).validate_filename())
	var output := base + ".mp4"
	var n := 2
	while FileAccess.file_exists(output) or FileAccess.file_exists(output.get_basename() + ".wav"):
		output = "%s (%d).mp4" % [base, n]
		n += 1
	var job: Node = load("res://net/dub_video_export.gd").new()
	job.button = save_button
	job.video = output
	job.log_path = ProjectSettings.globalize_path("user://dub_video_export_%d.log" % Time.get_ticks_usec())
	# No shell: every value is its own argument, and the exporter writes its progress to --events.
	job.pid = OS.create_process(python, ["-u", script, "--export", "--pack", pack_path.trim_suffix("/"),
		"--session", session, "--output", output, "--events", job.log_path])
	if job.pid <= 0:
		job.free()
		_label(save_button, "Video failed")
		return false
	(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(job)
	_label(save_button, "Saving video...")
	return true


## Handles a click on the save button after an export: opens the finished video, or
## retries a failed export from the already-saved takes. Returns true if it handled the click.
static func open_from(save_button: Control) -> bool:
	if _label_is(save_button, OPEN_TEXT) and not last_video.is_empty():
		OS.shell_open(last_video)
		return true
	if _label_is(save_button, RETRY_TEXT) and _last_args.size() == 3:
		if save_button.has_method("enable"): save_button.enable(false)
		start(save_button, _last_args[0], _last_args[1], _last_args[2])
		return true
	return false


static func _label(target: Control, text: String) -> void:
	if is_instance_valid(target) and target.get_child_count() > 0: target.get_child(0).text = text


static func _label_is(target: Control, text: String) -> bool:
	return is_instance_valid(target) and target.get_child_count() > 0 and target.get_child(0).text == text


func _ready() -> void:
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.autostart = true
	timer.timeout.connect(_poll)
	add_child(timer)


var _fill: Control


## Fills the gray (disabled) save button with its own blue look from left to right:
## a copy of the button in the enabled palette, clipped to the export percentage.
func _show_fill(fraction: float) -> void:
	if not is_instance_valid(button): return
	if not is_instance_valid(_fill):
		_fill = Control.new()
		_fill.clip_contents = true
		_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var copy: Control = button.duplicate(Node.DUPLICATE_SCRIPTS)
		if button.material: copy.material = button.material.duplicate()  # own palette, not the gray one
		copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
		copy.set_anchors_preset(Control.PRESET_TOP_LEFT)
		copy.position = Vector2.ZERO
		copy.size = button.size
		_fill.add_child(copy)
		button.add_child(_fill)  # after the label, so get_child(0) stays the button's label
		if copy.has_method("enable"): copy.enable(true)
	_fill.size = Vector2(button.size.x * clampf(fraction, 0.0, 1.0), button.size.y)
	var copy_label: Node = _fill.get_child(0).get_child(0) if _fill.get_child(0).get_child_count() > 0 else null
	if copy_label is Label: copy_label.text = button.get_child(0).text


func _poll() -> void:
	var event := _latest_event()
	if event.get("type") == "progress":
		var fraction := float(event.get("fraction", 0.0))
		_label(button, "Saving video %d%%" % int(fraction * 100.0))
		_show_fill(fraction)
	if OS.is_process_running(pid): return
	if is_instance_valid(_fill): _fill.queue_free()
	event = _latest_event()
	if event.get("type") == "result" and FileAccess.file_exists(video):
		last_video = video
		_label(button, OPEN_TEXT)
		DirAccess.remove_absolute(log_path)  # failure logs are kept for diagnosis
	else:
		push_warning("Dub video export failed: %s (log: %s)" % [event.get("message", "unknown error"), log_path])
		_label(button, RETRY_TEXT)  # the takes are saved; a click re-runs only the export
	if is_instance_valid(button) and button.has_method("enable"): button.enable(true)
	queue_free()


## Last JSON event the exporter printed (it prints one JSON object per line).
func _latest_event() -> Dictionary:
	var file := FileAccess.open(log_path, FileAccess.READ)
	if file == null: return {}
	var latest: Dictionary = {}
	for line: String in file.get_as_text().split("\n", false):
		if not line.begins_with("{"): continue  # Python/FFmpeg noise; avoids JSON errors in the game log
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary: latest = parsed
	return latest
