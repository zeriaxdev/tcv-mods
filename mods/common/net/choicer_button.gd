extends ButtonCV

signal pressed
var caption := Label.new()
var text: String = "":
 set(value):
  text = value
  caption.text = value
  custom_minimum_size.x = maxf(88, caption.get_theme_font("font").get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, caption.get_theme_font_size("font_size")).x + 32)
var disabled: bool = false:
 set(value):
  disabled = value
  enabled = not value
  if is_inside_tree(): enable(enabled)

func _init() -> void:
 var source: Control = load("res://scene/module/button/button_cv.tscn").instantiate()
 material = source.material.duplicate()
 source.free()
 custom_minimum_size.y = 40
 # the game's own buttons join this from their scene file. picking a menu theme
 # calls UpdatePalette on the group, so without it ours kept the old colors
 # until a restart.
 add_to_group("ButtonBase")
 focus_mode = Control.FOCUS_ALL
 add_child(caption)
 caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
 caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
 caption.add_theme_font_override("font", load("res://graphic/font/Waukegan LDO.ttf"))
 caption.add_theme_font_size_override("font_size", 20)
 resized.connect(func(): material.set_shader_parameter("node_size", size))
 button_clicked.connect(func(): pressed.emit())
 visibility_changed.connect(func(): mouse_within_button = false)

func _input(event: InputEvent) -> void:
 if not is_visible_in_tree(): return
 super._input(event)
 if has_focus() and enabled and event.is_action_pressed("ui_accept"):
  get_viewport().set_input_as_handled()
  click()

func use_small() -> void:
 var source: Control = load("res://scene/module/button/button_cv_small.tscn").instantiate()
 material = source.material.duplicate()
 source.free()
 button_type = BUTTONTYPE.SMALL
 caption.add_theme_font_override("font", load("res://graphic/font/DuruSans-Regular.ttf"))
 caption.add_theme_font_size_override("font_size", 18)
 custom_minimum_size.y = 44
 text = text
 if is_node_ready(): UpdatePalette()
