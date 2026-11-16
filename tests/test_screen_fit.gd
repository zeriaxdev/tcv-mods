extends SceneTree
# Settings > Display gets a native "Fill the screen" row. Flipping it switches
# between 16:9 with bars and filling, live, and saves the choice. The dub screen
# keeps its 1152x648 layout centered while only the background fills.

func _initialize(): call_deferred("run")


func settle(seconds: float) -> void:
	await create_timer(seconds).timeout


func run():
	var fit: Node = null
	for child in root.get_node("CommunityPacks").get_children():
		if child.get_script() != null and str(child.get_script().resource_path).ends_with("screen_fit.gd"): fit = child
	assert(fit != null, "screen_fit isn't running")
	var saved: String = fit.SETTINGS_PATH
	var had_file: bool = FileAccess.file_exists(saved)
	var before: String = FileAccess.get_file_as_string(saved) if had_file else ""

	var shell = load("res://scene/menu/_master/menu_master.tscn").instantiate()
	shell.stopgap_ignore_standard_instruction = true
	root.add_child(shell)
	shell.NewSlide("res://scene/menu/settings/menu_settings_cleaner.tscn", false)
	await settle(1.0)
	var rows: Array = shell.find_children("TcvFillScreen", "", true, false)
	assert(rows.size() == 1, "the Fill the screen row is missing or doubled")
	var check: CheckButton = rows[0].get_child(0)
	assert(rows[0].get_child(1).text == "Fill the screen")
	assert(check.button_pressed == fit.fill)

	check.button_pressed = false
	assert(root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_KEEP, "turning it off didn't bring back 16:9")
	assert(JSON.parse_string(FileAccess.get_file_as_string(saved)) == {"fill_screen": false})
	check.button_pressed = true
	assert(root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND, "turning it on didn't fill")
	assert(JSON.parse_string(FileAccess.get_file_as_string(saved)) == {"fill_screen": true})
	shell.queue_free()

	root.get_node("M").data.player.first_time = false
	var world = load("res://scene/singleton/world.tscn").instantiate()
	root.add_child(world)
	var folder: String = "user://game/packs_voice/"
	var pack: String = ""
	for name in DirAccess.get_directories_at(folder):
		if FileAccess.file_exists(folder.path_join(name).path_join("dub_video.ogv")): pack = folder.path_join(name) + "/"
	if pack.is_empty():
		print("SKIP: no dub pack in the test data folder for the dub screen check")
	else:
		root.get_node("Metro").gameplay_resource_dub_mode = load("res://common/niche/game_mode_resources/gameplay_resource_dub_mode.gd").new(pack)
		world.enter_dub_mode()
		await settle(5.0)
		var dub: Node = null
		for child in world.primary_capsule.get_children(): if child.has_node("Visuals"): dub = child
		assert(dub != null, "the dub screen didn't open")
		var visuals: Control = dub.get_node("Visuals")
		assert(visuals.size == Vector2(1152, 648), "the dub layout isn't 1152x648: %s" % visuals.size)
		var extra: Vector2 = (dub.get_viewport_rect().size - Vector2(1152, 648)) / 2.0
		assert(visuals.position.is_equal_approx(extra), "the dub layout isn't centered")
		assert(visuals.get_node("Scanlines").get_global_rect().size.is_equal_approx(dub.get_viewport_rect().size), "the background doesn't fill the screen")

	if had_file:
		var output := FileAccess.open(saved, FileAccess.WRITE)
		output.store_string(before)
		output.close()
	else:
		DirAccess.remove_absolute(saved)
	print("PASS: Fill the screen row, live switch and saved choice, dub layout centered with the background filling")
	quit()
