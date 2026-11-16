extends SceneTree
# Picking a menu theme in Customize calls UpdatePalette on the "ButtonBase"
# group. Our buttons have to be in it, or they keep the old theme's colors
# until the game restarts.

func _initialize(): call_deferred("run")


func run():
	var button = load("res://net/choicer_button.gd").new()
	button.text = "Online (F9)"
	root.add_child(button)
	await process_frame
	assert(button.is_in_group("ButtonBase"), "our button isn't in the game's ButtonBase group")
	var m = root.get_node("M")
	var original = m.button_profile_standard
	var themed = original.duplicate(true)
	m.button_profile_standard = themed
	call_group("ButtonBase", "UpdatePalette")
	assert(button.profile == themed, "the theme change didn't reach our button")
	m.button_profile_standard = original
	call_group("ButtonBase", "UpdatePalette")
	print("PASS: our buttons follow a menu theme change without a restart")
	quit()
