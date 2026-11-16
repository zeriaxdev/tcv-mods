extends Node
# Keyboard keys for Dub Mode, which is mouse only in the game. A key presses the
# on-screen button it stands for, but only when that button is showing and
# enabled, so a key can never do something a click couldn't. Changed in Dub
# Mode's own Settings panel, under Keys.

const SETTINGS_PATH: String = "user://tcv_keys.json"
const BUTTON := preload("res://net/choicer_button.gd")
# action -> [name in Settings, hint, default key, buttons it presses, first showing one wins]
const ACTIONS: Dictionary = {
	"record": ["Record", "[Start, record, stop recording]", KEY_SPACE, ["BtnBegin", "BtnRecord", "BtnStopRecord"]],
	"next": ["Next", "[Keep this take and go to the next clip]", KEY_ENTER, ["BtnNext"]],
	"hear": ["Hear again", "[Play the clip again, or stop it]", KEY_H, ["BtnHearAgain", "BtnStopListening"]],
	"watch": ["Watch", "[Watch your dub so far]", KEY_W, ["BtnWatch"]],
}

var keys: Dictionary = {}  # action -> physical keycode
var _dub: Control
var _capturing: String = ""
var _key_buttons: Dictionary = {}  # action -> button showing its key


func _ready() -> void:
	for action: String in ACTIONS: keys[action] = ACTIONS[action][2]
	if FileAccess.file_exists(SETTINGS_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
		if parsed is Dictionary:
			for action: String in keys: keys[action] = int(parsed.get(action, keys[action]))
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	var path: String = node.scene_file_path
	if path.ends_with("/dub_mode/main/dub_mode.tscn") or path.ends_with("/dub_mode/peripheral/dub_mode_freestyle.tscn"):
		node.ready.connect(func() -> void:
			_dub = node
			_add_section(), CONNECT_ONE_SHOT)


static func key_name(keycode: int) -> String:
	var label: int = DisplayServer.keyboard_get_label_from_physical(keycode) if DisplayServer.get_name() != "headless" else 0
	return OS.get_keycode_string(label if label != 0 else keycode)


func set_key(action: String, keycode: int) -> void:
	for other: String in keys:  # taking another action's key swaps them
		if other != action and keys[other] == keycode: keys[other] = keys[action]
	keys[action] = keycode
	var output: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(keys))
		output.close()
	_show_keys()


func _input(event: InputEvent) -> void:
	if _capturing.is_empty() or not (event is InputEventKey) or not event.pressed or event.echo: return
	get_viewport().set_input_as_handled()
	var action: String = _capturing
	_capturing = ""
	if event.physical_keycode != KEY_ESCAPE: set_key(action, event.physical_keycode)
	else: _show_keys()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo or not is_instance_valid(_dub) or not _dub.is_visible_in_tree(): return
	for name: String in ["Settings", "Exit"]:  # not behind an open panel
		var panel: CanvasItem = _dub.get_node_or_null(name)
		if panel != null and panel.visible: return
	if get_viewport().gui_get_focus_owner() is LineEdit: return
	for action: String in keys:
		if keys[action] != event.physical_keycode: continue
		for button_name: String in ACTIONS[action][3]:
			for button: Node in _dub.find_children(button_name, "", true, false):
				if button is ButtonCV and button.is_visible_in_tree() and button.enabled:
					get_viewport().set_input_as_handled()
					button.click()
					return


# Keys under Display in Dub Mode's Settings, made from the Display rows so it
# looks like the rest of the panel.
func _add_section() -> void:
	var block: Node = _dub.find_child("DisplaySettingsBlock", true, false)
	if block == null or block.get_parent().has_node("TcvKeys"): return
	var row_source: Node = block.get_node_or_null("VBoxContainer/HBoxContainer5")
	if row_source == null: return
	var section := VBoxContainer.new()
	section.name = "TcvKeys"
	section.add_child(HSeparator.new())
	var heading: Label = block.get_parent().get_node_or_null("Label3")
	heading = heading.duplicate() if heading != null else Label.new()
	heading.text = "Keys"
	section.add_child(heading)
	_key_buttons.clear()
	for action: String in ACTIONS:
		var row := HBoxContainer.new()
		var button := BUTTON.new()
		button.use_small()
		button.custom_minimum_size.x = 120
		button.focus_mode = Control.FOCUS_NONE  # Space and Enter must reach the capture, not press it again
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.pressed.connect(func() -> void:
			_capturing = action
			_show_keys())
		row.add_child(button)
		_key_buttons[action] = button
		for i: int in [1, 2]:
			var label: Label = row_source.get_child(i).duplicate()
			label.text = ACTIONS[action][i - 1]
			row.add_child(label)
		section.add_child(row)
	block.add_sibling(section)
	_show_keys()


func _show_keys() -> void:
	for action: String in _key_buttons:
		var button: Node = _key_buttons[action]
		if is_instance_valid(button): button.text = "Press a key" if action == _capturing else key_name(keys[action])
