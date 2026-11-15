extends RefCounted

static func box(color: Color, border: Color = Color("618c96"), radius: int = 12) -> StyleBoxFlat:
 var s := StyleBoxFlat.new()
 s.bg_color = color
 s.border_color = border
 s.set_border_width_all(2)
 s.set_corner_radius_all(radius)
 s.content_margin_left = 14
 s.content_margin_right = 14
 s.content_margin_top = 8
 s.content_margin_bottom = 8
 return s

static func make_theme() -> Theme:
 var t := Theme.new()
 t.default_font = load("res://graphic/font/DuruSans-Regular.ttf")
 t.default_font_size = 18
 var ink := Color.BLACK
 for kind: String in ["Label", "Button", "LineEdit", "OptionButton", "CheckBox", "CheckButton"]:
  t.set_color("font_color", kind, ink)
  t.set_color("font_hover_color", kind, ink)
  t.set_color("font_pressed_color", kind, ink)
  t.set_color("font_hover_pressed_color", kind, ink)
  t.set_color("font_focus_color", kind, ink)
  t.set_color("font_disabled_color", kind, Color("747474"))
 for kind: String in ["Button", "OptionButton", "LineEdit"]:
  t.set_font("font", kind, t.default_font)
 for kind: String in ["LineEdit", "OptionButton"]:
  for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
   t.set_color(state, kind, Color.WHITE)
 t.set_color("font_placeholder_color", "LineEdit", Color("aaaaaa"))
 t.set_color("caret_color", "LineEdit", Color.WHITE)
 for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
  t.set_stylebox(state, "CheckBox", StyleBoxEmpty.new())
 return t

static func background() -> Control:
 var bg: Control = load("res://scene/background/modular_background.tscn").instantiate()
 bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
 return bg

static func scene_panel(parent: Control, scene_path: String, node_path: String) -> void:
 var art := ColorRect.new()
 art.material = scene_properties(scene_path, node_path)["material"].duplicate()
 art.mouse_filter = Control.MOUSE_FILTER_IGNORE
 art.show_behind_parent = true
 parent.add_child(art)
 art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var resize: Callable = func(): art.material.set_shader_parameter("node_size", parent.size)
 parent.resized.connect(resize)
 resize.call_deferred()

static func dark_panel(parent: Control) -> void:
 scene_panel(parent, "res://scene/menu/settings/menu_settings_cleaner.tscn", "Border/ColorRect")

static func pack_list_panel(parent: Control) -> void:
 scene_panel(parent, "res://scene/menu/customize/menu_customize.tscn", "Border/Main/PackListings/List")

static func dialog_theme() -> Theme:
 var t := make_theme()
 t.set_stylebox("panel", "AcceptDialog", box(Color.WHITE, Color("888888"), 8))
 t.set_stylebox("embedded_border", "Window", box(Color.WHITE, Color("888888"), 8))
 t.set_color("title_color", "Window", Color.BLACK)
 for state: String in ["normal", "hover", "pressed", "disabled"]:
  t.set_stylebox(state, "Button", box(Color("c1e6eb") if state != "disabled" else Color("dddddd")))
 return t

static func scene_properties(scene_path: String, node_path: String) -> Dictionary:
 var state: SceneState = load(scene_path).get_state()
 for i: int in state.get_node_count():
  if str(state.get_node_path(i)).trim_prefix("./") != node_path: continue
  var properties := {}
  for j: int in state.get_node_property_count(i):
   properties[str(state.get_node_property_name(i, j))] = state.get_node_property_value(i, j)
  return properties
 return {}
