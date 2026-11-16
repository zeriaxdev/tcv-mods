extends SceneTree
# Online (F9) from the main menu swaps the page inside the menu that's already
# open, like Community packs: no fade to black, no new menu (so the music keeps
# playing), and Back goes to the page it was opened from.

func _initialize(): call_deferred("run")


func settle(seconds: float) -> void:
	await create_timer(seconds).timeout


func run():
	var m = root.get_node("M")
	m.data.player.first_time = false
	var world = load("res://scene/singleton/world.tscn").instantiate()
	root.add_child(world)
	world.CreateMenu()
	await settle(4.0)
	var menu: Node = null
	for child in world.primary_capsule.get_children():
		if child.scene_file_path.contains("menu_master"): menu = child
	assert(menu != null, "no main menu")
	var slides: Node = menu.get_node("SlideCapsule")
	assert(slides.get_child(-1).scene_file_path.ends_with("menu_home.tscn"))

	root.get_node("Net").open_lobby()
	await process_frame
	assert(not world.blackout.visible, "the screen faded to black")
	await settle(0.5)
	assert(is_instance_valid(menu) and menu.get_parent() == world.primary_capsule, "the menu was rebuilt")
	assert(slides.get_child(-1).scene_file_path == "res://net/lobby.tscn", "the lobby isn't showing")

	menu._on_btn_back_button_clicked()
	await settle(0.5)
	assert(slides.get_child(-1).scene_file_path.ends_with("menu_home.tscn"), "Back didn't return to the main menu")
	print("PASS: Online opens in place, keeps the menu, and Back returns home")
	quit()
