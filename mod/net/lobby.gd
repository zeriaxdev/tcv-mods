extends MenuBase

const GAME_BUTTON = preload("res://net/choicer_button.gd")
const STYLE = preload("res://net/choicer_style.gd")

const ROW_HEIGHT: int = 34
# ENet drops a peer it cannot reach after 30s of its own accord. say something
# useful before that happens rather than letting the lobby sit there empty.
const JOIN_TIMEOUT: float = 12.0
var name_field: LineEdit
var address_field: LineEdit
var port_field: LineEdit
var host_button: GAME_BUTTON
var join_button: GAME_BUTTON
var start_button: GAME_BUTTON
var dub_button: GAME_BUTTON
var ready_button: CheckButton
var status_label: Label
var _mode_hint: Label
var warning_label: Label
var player_rows: VBoxContainer
var _tabs: ButtonArray
var _connection_body: VBoxContainer
var _roster_body: VBoxContainer
var _tab_title: Label
var _was_online := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	position = Vector2.ZERO
	size = get_viewport_rect().size
	theme = STYLE.make_theme()
	_build_ui()
	# deferred: these fire from inside the multiplayer poll, and rebuilding the
	# player list there takes the engine down with no error to show for it.
	Net.player_list_changed.connect(_refresh, CONNECT_DEFERRED)
	Net.connection_failed.connect(_on_error, CONNECT_DEFERRED)
	Net.connected_to_lobby.connect(_on_connected, CONNECT_DEFERRED)
	# a joiner turned away is the host's problem to hear about: the person it
	# happened to is looking at their own screen, not this one.
	Net.host_notice.connect(_on_host_notice, CONNECT_DEFERRED)
	Net.server_disconnected.connect(func() -> void: _on_error(
		"Lost the connection to the host. Either they closed the lobby, or the link between you dropped."))
	add_to_group("OnBack")
	_refresh()
	if Net.is_online():
		if Net.is_host(): _set_status("Lobby still open. Choose the next pack when everyone is ready.")
		else: _set_status("Connected. Waiting for the host to pick the next pack.")


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 58 if side in ["top", "bottom"] else 16)
	add_child(margin)
	var workspace := HBoxContainer.new()
	workspace.add_theme_constant_override("separation", 16)
	margin.add_child(workspace)
	_tabs = load("res://scene/module/button/button_array.tscn").instantiate()
	# Same beveled buttons and size as the game's Settings page selector.
	_tabs.large_buttons = false
	_tabs.columns = 1
	_tabs.custom_minimum_size.x = 224
	_tabs.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_tabs.add_theme_constant_override("v_separation", 12)
	for text: String in ["Connection", "Contestants"]:
		var tab := GAME_BUTTON.new()
		tab.text = text
		tab.use_small()
		tab.custom_minimum_size.y = 48
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tabs.add_child(tab)
	_tabs.selection.connect(_show_tab)
	workspace.add_child(_tabs)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	workspace.add_child(panel)
	STYLE.dark_panel(panel)
	var inset := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(inset)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.theme = STYLE.make_theme()
	body.theme.set_color("font_color", "Label", Color.WHITE)
	inset.add_child(body)
	_tab_title = Label.new()
	_tab_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_tab_title)
	body.add_child(HSeparator.new())
	_connection_body = VBoxContainer.new()
	_connection_body.add_theme_constant_override("separation", 16)
	body.add_child(_connection_body)
	var default_name: String = OS.get_environment("USERNAME")
	if default_name.is_empty(): default_name = OS.get_environment("USER")
	if default_name.is_empty(): default_name = "Player"
	name_field = _labeled_field(_connection_body, "Your name", default_name)
	address_field = _labeled_field(_connection_body, "Host address", "127.0.0.1")
	port_field = _labeled_field(_connection_body, "Port", str(Net.PORT))
	var connection_actions := HBoxContainer.new()
	connection_actions.add_theme_constant_override("separation", 12)
	_connection_body.add_child(connection_actions)
	host_button = GAME_BUTTON.new()
	host_button.custom_minimum_size = Vector2(152, 48)
	host_button.text = "Host"
	host_button.pressed.connect(_on_host)
	connection_actions.add_child(host_button)
	join_button = GAME_BUTTON.new()
	join_button.custom_minimum_size = Vector2(152, 48)
	join_button.text = "Join"
	join_button.pressed.connect(_on_join)
	connection_actions.add_child(join_button)
	_roster_body = VBoxContainer.new()
	_roster_body.add_theme_constant_override("separation", 16)
	body.add_child(_roster_body)
	player_rows = VBoxContainer.new()
	player_rows.custom_minimum_size.y = ROW_HEIGHT * Net.MAX_PLAYERS
	_roster_body.add_child(player_rows)
	ready_button = CheckButton.new()
	ready_button.text = "Ready"
	ready_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		ready_button.add_theme_color_override(state, Color.WHITE)
	ready_button.toggled.connect(func(on: bool): Net.set_ready(on))
	_roster_body.add_child(ready_button)
	var play_actions := HBoxContainer.new()
	play_actions.add_theme_constant_override("separation", 12)
	_roster_body.add_child(play_actions)
	start_button = GAME_BUTTON.new()
	start_button.custom_minimum_size = Vector2(152, 48)
	start_button.text = "Gameshow"
	start_button.pressed.connect(_on_start)
	play_actions.add_child(start_button)
	dub_button = GAME_BUTTON.new()
	dub_button.custom_minimum_size = Vector2(152, 48)
	dub_button.text = "Dub Mode"
	dub_button.pressed.connect(_on_start_dub)
	play_actions.add_child(dub_button)
	# Says why the mode buttons are gray instead of leaving them looking broken.
	_mode_hint = Label.new()
	_mode_hint.text = "The game modes unlock once another player joins."
	_mode_hint.modulate = Color(1, 1, 1, 0.7)
	_roster_body.add_child(_mode_hint)
	status_label = Label.new()
	status_label.text = "Not connected."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status_label)
	warning_label = Label.new()
	warning_label.add_theme_color_override("font_color", Color("ffe09c"))
	warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(warning_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(spacer)
	var build := Label.new()
	build.text = "Multiplayer %s • Protocol %d" % [Net.MOD_VERSION, Net.PROTOCOL_VERSION]
	build.add_theme_font_size_override("font_size", 14)
	build.add_theme_color_override("font_color", Color("cccccc"))
	build.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	body.add_child(build)
	_show_tab(0)


func _show_tab(index: int) -> void:
	_tabs.select_item(index)
	_tab_title.text = "Connection" if index == 0 else "Contestants"
	_connection_body.visible = index == 0
	_roster_body.visible = index == 1
	status_label.visible = index == 0 or not Net.is_online()


func _labeled_field(parent: Control, label_text: String, default_value: String) -> LineEdit:
	var row: = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	parent.add_child(row)

	var label: = Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 140
	row.add_child(label)

	var field: = LineEdit.new()
	field.text = default_value
	field.custom_minimum_size = Vector2(320, 36)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	return field




func _on_host() -> void:
	var err: Error = Net.host_game(name_field.text, Profile.contestant, int(port_field.text))
	if err == OK:
		# spell them out. "share your IP" is where most failed joins start.
		_set_status("Hosting on port %s. Your friends type one of these as the host address:\n%s" % [
			port_field.text, Net.addresses_to_give_out()])


func _on_join() -> void:
	var err: Error = Net.join_game(address_field.text, name_field.text, Profile.contestant, int(port_field.text))
	if err == OK:
		_set_status("Connecting to %s..." % address_field.text)
		_refresh()
		_watch_the_join()


func _on_connected() -> void:
	_set_status("Connected. Waiting for the host to send the lobby.")
	_refresh()


# the status line rather than the warning line: _refresh() rewrites the warning
# every time the roster moves, and a joiner being turned away moves it.
func _on_host_notice(text: String) -> void:
	_set_status(text)


# nothing has answered on the socket at all. Net handles the other case itself
# now -- reached them, they never answered the handshake -- and says so, because
# that one is a build difference rather than anything to do with the network.
# This used to cover both and blamed the network for both, which had people
# reopening ports that were fine.
func _watch_the_join() -> void:
	await get_tree().create_timer(JOIN_TIMEOUT).timeout
	if not is_inside_tree(): return
	if Net.is_host() or not Net.is_online() or Net.slot_count() > 0: return
	_set_status(("No answer from %s after %d seconds.\n"
		+ "Check they are hosting on port %s, and that the address you typed is the one "
		+ "their end shows. On Hamachi that is the IPv4 address next to their name.") % [
		address_field.text, int(JOIN_TIMEOUT), port_field.text])


func BackButtonPressed() -> void:
	Net.leave()


func _on_start() -> void:
	if not Net.is_host(): return
	if Net.slot_count() < 2:
		_set_status("Need at least two contestants to start.")
		return
	Net.apply_roster_to_metro()
	M.session_type = M.SESSION_TYPE.STANDARD
	M.world.CreateSameLobby([])


func _on_start_dub() -> void:
	if not Net.is_host(): return
	if Net.slot_count() < 2:
		_set_status("Need at least two players to split the clips.")
		return
	Net.apply_roster_to_metro()
	M.session_type = M.SESSION_TYPE.VIDEO_DUB
	M.world.return_to_dub_selection()


func _on_error(reason: String) -> void:
	_set_status(reason)
	_refresh()


func _set_status(text: String) -> void:
	if status_label: status_label.text = text




func _refresh() -> void:
	if not is_node_ready() or not is_inside_tree(): return
	Net.log_net("lobby refresh: %d player(s)" % Net.players.size())

	var online: bool = Net.is_online()
	if online and not _was_online: _show_tab(1)
	_was_online = online
	host_button.disabled = online
	join_button.disabled = online
	name_field.editable = not online
	address_field.editable = not online
	port_field.editable = not online
	# only once the host has actually put us in the roster. before that the tick
	# goes nowhere and it just looks broken.
	var seated: bool = online and Net.my_slot() >= 0
	ready_button.disabled = not seated
	ready_button.visible = seated
	if seated:
		ready_button.set_pressed_no_signal(
			bool(Net.players.get(Net.my_id(), {}).get("ready", false)))
	start_button.visible = Net.is_host()
	start_button.disabled = Net.slot_count() < 2
	dub_button.visible = Net.is_host()
	dub_button.disabled = Net.slot_count() < 2
	_mode_hint.visible = Net.is_host() and Net.slot_count() < 2

	for child: Node in player_rows.get_children():
		player_rows.remove_child(child)
		child.queue_free()

	for slot: int in Net.slot_count():
		var peer: int = Net.peer_for_slot(slot)
		var record: Dictionary = Net.players.get(peer, {})
		var row: = Label.new()
		var marks: PackedStringArray = []
		if peer == 1: marks.append("host")
		if peer == Net.my_id(): marks.append("you")
		if record.get("ready", false): marks.append("ready")
		var shown: String = str(record.get("name", "?")).substr(0, 28)
		row.text = "%d.  %s   [%s]" % [slot + 1, shown, ", ".join(marks)]
		row.clip_text = true
		player_rows.add_child(row)

	if online:
		var mismatched: PackedStringArray = Net.mismatched_players()
		if mismatched.is_empty(): warning_label.text = ""
		else:
			warning_label.text = ("Your voice pack libraries are not identical: %s.\n"
				+ "Standard mode only cares if the host picks clips from one of these packs. "
				+ "For Dub Mode, a missing selected pack is okay: enable experimental pack sharing, "
				+ "let everyone accept and verify it, then begin the dub.") % "; ".join(mismatched)
