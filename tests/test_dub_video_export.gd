extends SceneTree
## Renders a real saved dub through the Save Dub auto-export path.
## Usage: Godot --headless --path <patched-game> --script tests/test_dub_video_export.gd -- "<pack folder>" "<session folder>"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 2, "pass the pack folder and session folder")
	var button := Control.new()
	button.add_child(Label.new())
	root.add_child(button)
	var exporter: GDScript = load("res://net/dub_video_export.gd")
	assert(exporter.start(button, args[0] + "/", args[1], "Test export"))
	assert(button.get_child(0).text == "Saving video...")
	var waited := 0.0
	while button.get_child(0).text.begins_with("Saving video") and waited < 600.0:
		await create_timer(0.5).timeout
		waited += 0.5
	var label: String = button.get_child(0).text
	assert(label == exporter.OPEN_TEXT, "export ended with: " + label)
	assert(FileAccess.file_exists(exporter.last_video))
	assert(FileAccess.file_exists(exporter.last_video.get_basename() + ".wav"))
	print("PASS: Save Dub auto-export wrote ", exporter.last_video, " in ", waited, "s")
	# A failed export offers Retry video, and clicking it re-runs only the export.
	assert(exporter.start(button, args[0] + "/", "no such session", "Test export"))
	while button.get_child(0).text.begins_with("Saving video"): await create_timer(0.2).timeout
	assert(button.get_child(0).text == exporter.RETRY_TEXT, "failure shows: " + button.get_child(0).text)
	assert(exporter.open_from(button) and button.get_child(0).text.begins_with("Saving video"))
	while button.get_child(0).text.begins_with("Saving video"): await create_timer(0.2).timeout
	print("PASS: a failed export shows Retry video and retrying re-runs it")
	quit()
