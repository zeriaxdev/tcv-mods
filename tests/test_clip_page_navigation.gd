extends SceneTree
# The clip pages' breadcrumb and Back button. Offline, the breadcrumb must
# follow the player count every visit (it used to stick on the first one).
# Online, it reads Main Menu > Online > mode, and Back returns to the Online
# menu instead of loading an empty path and leaving a blank screen.
const CLIPS := "res://scenes/nav_specific/clip_selector_menus/clip_selection_standard.tscn"


func _initialize(): call_deferred("run")


func settle(n := 6):
	for i in n: await process_frame


func run():
	var shell = load("res://scene/menu/_master/menu_master.tscn").instantiate()
	shell.stopgap_ignore_standard_instruction = true
	root.add_child(shell)
	var slides: Node = shell.get_node("SlideCapsule")
	var metro = root.get_node("Metro")
	var net = root.get_node("Net")
	root.get_node("M").session_type = root.get_node("M").SESSION_TYPE.STANDARD

	metro.current_players.resize(1)
	shell.NewSlide(CLIPS, false)
	await settle()
	assert(slides.get_child(-1).menu_data.slide_hint == PackedStringArray(["Main Menu", "Player Count", "Solo", "Standard"]))
	metro.current_players.resize(2)
	shell.NewSlide(CLIPS, false)
	await settle()
	assert(slides.get_child(-1).menu_data.slide_hint.has("Group"), "the breadcrumb kept Solo from the first visit")

	assert(net.host_game("Host", "", 7698) == OK)
	shell.NewSlide("res://net/lobby.tscn", false)
	await settle(20)
	slides.get_child(-1)._come_back_here()
	shell.NewSlide(CLIPS, false)
	await settle()
	assert(slides.get_child(-1).menu_data.slide_hint == PackedStringArray(["Main Menu", "Online", "Standard"]))
	shell._on_btn_back_button_clicked()
	await settle(20)
	assert(slides.get_child_count() > 0 and slides.get_child(-1).scene_file_path == "res://net/lobby.tscn", "Back didn't return to the Online menu")
	net.leave()
	print("PASS: clip page breadcrumb follows the player count, and Back goes to the Online menu")
	quit()
