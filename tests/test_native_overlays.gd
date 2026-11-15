extends SceneTree
func _initialize(): call_deferred("check_ui")
func check_panel(panel):
 var shader = load("res://net/choicer_style.gd").scene_properties("res://scene/menu/settings/menu_settings_cleaner.tscn", "Border/ColorRect")["material"].shader
 var found = false
 for child in panel.get_children():
  if child is ColorRect and child.material != null:
   assert(child.material.shader == shader)
   found = true
 assert(found, "Missing original game panel material")
func check_ui():
 root.size = Vector2i(1152,648)
 var picker = load("res://net/dub_character_picker.gd").new()
 picker.characters = PackedStringArray(["First character", "Second character"])
 root.add_child(picker)
 await process_frame
 await process_frame
 assert(picker.auto_button.has_method("GradHover"))
 assert(picker.begin_button.has_method("GradHover"))
 assert(picker.theme.default_font.resource_path.ends_with("DuruSans-Regular.ttf"))
 assert(picker.auto_button.caption.get_theme_font("font").resource_path.ends_with("Waukegan LDO.ttf"))
 for box in picker._boxes.values():
  assert(box is CheckButton)
  assert(box.get_theme_color("font_hover_pressed_color") == Color.WHITE)
 var panel = picker.get_child(1).get_child(0)
 check_panel(panel)
 assert(panel.get_global_rect().end.y <= 591)
 var pack = root.get_node("Net/PackSync")
 pack._show_host_error("A long pack-transfer error must wrap inside the game's panel. ".repeat(12))
 await process_frame
 await process_frame
 assert(pack._primary.has_method("GradHover"))
 assert(pack._secondary.has_method("GradHover"))
 assert(pack._force_download_box is CheckButton)
 assert(pack._force_download_box.get_theme_color("font_hover_pressed_color") == Color.WHITE)
 check_panel(pack._panel)
 for control in [pack._panel, pack._secondary]:
  var rect = control.get_global_rect()
  assert(rect.position.x >= 58 and rect.end.x <= 1095, "Horizontal overflow: %s" % rect)
  assert(rect.position.y >= 58 and rect.end.y <= 591, "Vertical overflow: %s" % rect)
 pack._primary.text = "Enable experimental sharing"
 pack._primary.visible = true
 pack._progress.visible = true
 pack._warning_box.visible = true
 pack._warning.text = "Download only packs you trust. ".repeat(30)
 pack._roster_box.visible = true
 pack._roster.text = "Player: waiting for acceptance\n".repeat(20)
 await process_frame
 await process_frame
 assert(pack._secondary.get_global_rect().end.y <= 591)
 # Role selection and transfer confirmation must still require explicit actions.
 assert(not pack._test_auto_accept)
 assert(not pack._test_auto_begin)
 assert(pack._primary.pressed.is_connected(pack._on_primary))
 assert(pack._secondary.pressed.is_connected(pack._on_secondary))
 picker.free()
 print("Original panel shaders, fonts, ButtonCV actions, toggles, consent and 1152x648 overlay bounds passed")
 quit()
