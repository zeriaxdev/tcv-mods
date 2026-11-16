extends Node
# "Fill the screen" in Settings > Display. The game is laid out for a 16:9
# screen and adds black bars on any other shape (a Mac is 16:10). Filling lets
# its anchored layouts grow instead. On by default on macOS.

const SETTINGS_PATH: String = "user://tcv_screen.json"
const BASE: Vector2 = Vector2(1152, 648)

var fill: bool = OS.get_name() == "macOS"
var _dub: Control


func _ready() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
		if parsed is Dictionary: fill = bool(parsed.get("fill_screen", fill))
	_apply()
	get_tree().node_added.connect(_on_node_added)
	get_tree().root.size_changed.connect(_fit_dub_screen)


func set_fill(value: bool) -> void:
	fill = value
	var output: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify({"fill_screen": fill}))
		output.close()
	_apply()


func _apply() -> void:
	get_tree().root.content_scale_aspect = (
		Window.CONTENT_SCALE_ASPECT_EXPAND if fill else Window.CONTENT_SCALE_ASPECT_KEEP)
	_fit_dub_screen()


func _on_node_added(node: Node) -> void:
	var path: String = node.scene_file_path
	if path.ends_with("/display_settings_block.tscn"):
		node.ready.connect(_add_toggle.bind(node), CONNECT_ONE_SHOT)
	elif path.ends_with("/dub_mode/main/dub_mode.tscn"):
		node.ready.connect(func() -> void:
			_dub = node
			_fit_dub_screen(), CONNECT_ONE_SHOT)


# a copy of the game's own "Center window on resize" row, so it looks native.
func _add_toggle(block: Node) -> void:
	var source: Node = block.get_node_or_null("VBoxContainer/HBoxContainer5")
	if source == null or source.get_parent().has_node("TcvFillScreen"): return
	var row: Node = source.duplicate()
	row.name = "TcvFillScreen"
	var check: CheckButton = row.get_child(0)
	check.unique_name_in_owner = false
	for connection: Dictionary in check.toggled.get_connections():
		check.toggled.disconnect(connection.callable)
	check.set_pressed_no_signal(fill)
	check.toggled.connect(set_fill)
	row.get_child(1).text = "Fill the screen"
	row.get_child(2).text = "[No black bars on screens that aren't 16:9, like a Mac's]"
	source.add_sibling(row)


# the dub screen places some parts from the top and some from the bottom of a
# 1152x648 screen, so extra height pulled the caption into the waveform. Keep
# the whole layout in that box, centered, and let only the background reach
# the screen edges. At 16:9 this changes nothing.
func _fit_dub_screen() -> void:
	if not is_instance_valid(_dub) or not _dub.is_inside_tree(): return
	var visuals: Control = _dub.get_node_or_null("Visuals")
	if visuals == null: return
	var extra: Vector2 = (_dub.get_viewport_rect().size - BASE) / 2.0
	visuals.set_anchors_preset(Control.PRESET_CENTER)
	visuals.offset_left = -BASE.x / 2.0
	visuals.offset_right = BASE.x / 2.0
	visuals.offset_top = -BASE.y / 2.0
	visuals.offset_bottom = BASE.y / 2.0
	var background: Control = visuals.get_node_or_null("Scanlines")
	if background == null: return
	background.offset_left = -extra.x
	background.offset_right = extra.x
	background.offset_top = -extra.y
	background.offset_bottom = extra.y
