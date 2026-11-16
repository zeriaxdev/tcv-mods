extends SceneTree
# Dub Mode keys: a key presses the button it stands for only while that button
# shows and is enabled, never behind Settings, and Settings > Keys can change
# and swap them.

func _initialize(): call_deferred("run")


func settle(seconds: float) -> void:
	await create_timer(seconds).timeout


func press(keycode: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	var up: InputEventKey = event.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame


func run():
	var keys: Node = null
	for child in root.get_node("CommunityPacks").get_children():
		if child.get_script() != null and str(child.get_script().resource_path).ends_with("dub_keys.gd"): keys = child
	assert(keys != null, "dub_keys isn't running")
	var saved: String = keys.SETTINGS_PATH
	var had_file: bool = FileAccess.file_exists(saved)
	var before: String = FileAccess.get_file_as_string(saved) if had_file else ""

	root.get_node("M").data.player.first_time = false
	var world = load("res://scene/singleton/world.tscn").instantiate()
	root.add_child(world)
	var folder: String = "user://game/packs_voice/"
	var pack: String = ""
	for name in DirAccess.get_directories_at(folder):
		if FileAccess.file_exists(folder.path_join(name).path_join("dub_video.ogv")): pack = folder.path_join(name) + "/"
	assert(not pack.is_empty(), "no dub pack in the test data folder")
	root.get_node("Metro").gameplay_resource_dub_mode = load("res://common/niche/game_mode_resources/gameplay_resource_dub_mode.gd").new(pack)
	world.enter_dub_mode()
	await settle(5.0)
	var dub: Node = null
	for child in world.primary_capsule.get_children(): if child.has_node("Visuals"): dub = child
	assert(dub != null, "the dub screen didn't open")

	var section: Node = dub.find_child("TcvKeys", true, false)
	assert(section != null, "no Keys section in Dub Mode settings")
	assert(section.get_child_count() == 2 + keys.ACTIONS.size())

	var watch: Node = dub.find_child("BtnWatch", true, false)
	var clicks: Array = [0]
	watch.button_clicked.connect(func(): clicks[0] += 1)
	await press(keys.keys["watch"])
	assert(clicks[0] == 0, "W pressed Watch while it was disabled")

	var begin: Node = dub.find_child("BtnBegin", true, false)
	var begun: Array = [0]
	begin.button_clicked.connect(func(): begun[0] += 1)
	dub.show_settings()
	await press(KEY_SPACE)
	assert(begun[0] == 0, "Space reached the dub screen behind Settings")
	dub.hide_settings()
	await press(KEY_SPACE)
	assert(begun[0] == 1, "Space didn't press Begin")

	keys.set_key("watch", KEY_SPACE)
	assert(keys.keys["watch"] == KEY_SPACE and keys.keys["record"] == KEY_W, "taking a used key should swap")
	assert(JSON.parse_string(FileAccess.get_file_as_string(saved))["watch"] == KEY_SPACE)
	var record_key: Node = section.get_child(2).get_child(0)
	record_key.click()
	assert(record_key.text == "Press a key")
	await press(KEY_R)
	assert(keys.keys["record"] == KEY_R and record_key.text == "R", "capturing a key didn't save it")

	if had_file:
		var output := FileAccess.open(saved, FileAccess.WRITE)
		output.store_string(before)
		output.close()
	else:
		DirAccess.remove_absolute(saved)
	print("PASS: Dub Mode keys press only showing, enabled buttons, not behind Settings, and can be changed")
	quit()
