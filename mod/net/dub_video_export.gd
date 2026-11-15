extends Node
## Renders a saved dub to MP4 in the background with the installed Choicer Voicer
## Exporter (exporter.py: centered mic takes, H.264 CRF 16, lossless WAV beside it).
## Lives on the scene root so leaving dub mode does not stop the export.

const OPEN_TEXT := "Open video"
const EXPORTERS := [
	"/Applications/Choicer Voicer Exporter.app/Contents/Resources/exporter.py",
	"~/Applications/Choicer Voicer Exporter.app/Contents/Resources/exporter.py",
]
const PYTHONS := ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]

static var last_video: String = ""

var button: Control
var pid: int = -1
var log_path: String
var video: String


static func _first_existing(paths: Array) -> String:
	for path: String in paths:
		path = path.replace("~", OS.get_environment("HOME"))
		if FileAccess.file_exists(path): return path
	return ""


## Starts the export; returns false (and says why on the button) when it cannot run.
static func start(save_button: Control, pack_path: String, session: String, title: String) -> bool:
	if OS.get_name() != "macOS": return false
	var script := _first_existing(EXPORTERS)
	var python := _first_existing(PYTHONS)
	if script.is_empty() or python.is_empty():
		_label(save_button, "No exporter")
		return false
	var folder := OS.get_environment("HOME").path_join("Movies/Choicer Voicer Exports")
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
	# sh only redirects output to the log; every value is passed as an argument, never spliced into the command.
	job.pid = OS.create_process("/bin/sh", ["-c", 'exec "$0" -u "$1" --export --pack "$2" --session "$3" --output "$4" > "$5" 2>&1',
		python, script, pack_path.trim_suffix("/"), session, output, job.log_path])
	if job.pid <= 0:
		job.free()
		_label(save_button, "Video failed")
		return false
	(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(job)
	_label(save_button, "Saving video...")
	return true


## Opens the finished video when the save button shows "Open video". Returns true if it did.
static func open_from(save_button: Control) -> bool:
	if not _label_is(save_button, OPEN_TEXT) or last_video.is_empty(): return false
	OS.shell_open(last_video)
	return true


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
		if is_instance_valid(button) and button.has_method("enable"): button.enable(true)
	else:
		push_warning("Dub video export failed: %s (log: %s)" % [event.get("message", "unknown error"), log_path])
		_label(button, "Video failed")
	queue_free()


## Last JSON event the exporter printed (it prints one JSON object per line).
func _latest_event() -> Dictionary:
	var file := FileAccess.open(log_path, FileAccess.READ)
	if file == null: return {}
	var latest: Dictionary = {}
	for line: String in file.get_as_text().split("\n", false):
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary: latest = parsed
	return latest
