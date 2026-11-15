extends MenuBase

const GAME_BUTTON = preload("res://net/choicer_button.gd")
const STYLE = preload("res://net/choicer_style.gd")

const ROW_HEIGHT: int = 34
# ENet drops a peer it cannot reach after 30s of its own accord. say something
# useful before that happens rather than letting the lobby sit there empty.
const JOIN_TIMEOUT: float = 12.0
const REPO_URL: String = "https://github.com/zeriaxdev/tcv-mods"
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
var player_rows: Tree
var _tabs: ButtonArray
var _choice: ButtonArray
var _host_view: VBoxContainer
var _join_view: VBoxContainer
var _show_addresses: CheckButton
var _address_rows: VBoxContainer
var _connection_body: HBoxContainer
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
		_show_tab(1)
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
	body.add_theme_constant_override("separation", 12)
	body.theme = STYLE.make_theme()
	body.theme.set_color("font_color", "Label", Color.WHITE)
	inset.add_child(body)
	_tab_title = Label.new()
	_tab_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_tab_title)
	body.add_child(HSeparator.new())
	_build_connection(body)
	_build_roster(body)
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
	var build := LinkButton.new()
	build.text = "tcv-mods %s" % Net.MOD_VERSION
	build.tooltip_text = "Open the tcv-mods page on GitHub"
	build.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
	# the menus run on ui_accept, and a button holding focus eats the first press.
	build.focus_mode = Control.FOCUS_NONE
	build.size_flags_horizontal = Control.SIZE_SHRINK_END
	build.add_theme_font_size_override("font_size", 14)
	build.add_theme_color_override("font_color", Color("cccccc"))
	for state: String in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		build.add_theme_color_override(state, Color.WHITE)
	build.pressed.connect(func() -> void: OS.shell_open(REPO_URL))
	body.add_child(build)
	_show_tab(0)


# Host a game / Join a game, as two of the big cards from the game's own Play
# screen, with whatever the chosen one needs to the right of them.
func _build_connection(body: Control) -> void:
	_connection_body = HBoxContainer.new()
	_connection_body.add_theme_constant_override("separation", 24)
	body.add_child(_connection_body)
	_choice = load("res://scene/module/button/button_array.tscn").instantiate()
	_choice.columns = 1
	_choice.custom_minimum_size.x = 260
	_choice.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_choice.add_theme_constant_override("v_separation", 16)
	for text: String in ["Host a game", "Join a game"]:
		var card := GAME_BUTTON.new()
		card.text = text
		# the Play screen's Singleplayer / Local Multiplayer captions
		card.caption.add_theme_font_override("font", load("res://graphic/font/DuruSans-Regular.ttf"))
		card.caption.add_theme_font_size_override("font_size", 24)
		card.custom_minimum_size.y = 104
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_choice.add_child(card)
	_choice.selection.connect(_show_choice)
	_connection_body.add_child(_choice)

	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 12)
	_connection_body.add_child(details)
	var default_name: String = OS.get_environment("USERNAME")
	if default_name.is_empty(): default_name = OS.get_environment("USER")
	if default_name.is_empty(): default_name = "Player"
	name_field = _labeled_field(details, "Your name", default_name)

	_host_view = VBoxContainer.new()
	_host_view.add_theme_constant_override("separation", 8)
	details.add_child(_host_view)
	var share_row := HBoxContainer.new()
	share_row.add_theme_constant_override("separation", 12)
	_host_view.add_child(share_row)
	var share := Label.new()
	share.text = "Friends join with one of your addresses."
	share_row.add_child(share)
	# hidden unless asked for: people stream this screen.
	_show_addresses = _check_button("Show")
	_show_addresses.toggled.connect(func(_on: bool) -> void: _fill_addresses())
	share_row.add_child(_show_addresses)
	_address_rows = VBoxContainer.new()
	_address_rows.add_theme_constant_override("separation", 6)
	_host_view.add_child(_address_rows)
	_fill_addresses()
	host_button = GAME_BUTTON.new()
	host_button.custom_minimum_size = Vector2(152, 48)
	host_button.text = "Open lobby"
	host_button.pressed.connect(_on_host)
	_host_view.add_child(_padded(host_button))

	_join_view = VBoxContainer.new()
	_join_view.add_theme_constant_override("separation", 8)
	details.add_child(_join_view)
	address_field = _labeled_field(_join_view, "Host address", "127.0.0.1")
	join_button = GAME_BUTTON.new()
	join_button.custom_minimum_size = Vector2(152, 48)
	join_button.text = "Join"
	join_button.pressed.connect(_on_join)
	_join_view.add_child(_padded(join_button))

	var advanced := _check_button("Advanced")
	details.add_child(advanced)
	var port_row := VBoxContainer.new()
	port_row.visible = false
	details.add_child(port_row)
	port_field = _labeled_field(port_row, "Port", str(Net.PORT))
	advanced.toggled.connect(func(on: bool) -> void: port_row.visible = on)
	_show_choice(0)


func _build_roster(body: Control) -> void:
	_roster_body = VBoxContainer.new()
	_roster_body.add_theme_constant_override("separation", 12)
	body.add_child(_roster_body)
	# the pack list's light panel and the game's own two-column checkmark list
	# from the Customize page, so the ready tick is the game's own checkbox.
	var list_panel := PanelContainer.new()
	list_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	STYLE.pack_list_panel(list_panel)
	_roster_body.add_child(list_panel)
	var list_margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		list_margin.add_theme_constant_override("margin_" + side, 14)
	list_panel.add_child(list_margin)
	player_rows = Tree.new()
	var native := STYLE.scene_properties("res://scene/menu/customize/menu_customize.tscn",
		"Border/Main/PackListings/List/MarginContainer/TreeCheckmarks")
	for property: String in native:
		if property.begins_with("theme_override"): player_rows.set(property, native[property])
	player_rows.columns = 3
	player_rows.set_column_expand(0, false)
	player_rows.set_column_expand(2, false)
	player_rows.set_column_custom_minimum_width(2, 80)
	player_rows.hide_root = true
	player_rows.focus_mode = Control.FOCUS_NONE
	player_rows.scroll_vertical_enabled = false
	player_rows.custom_minimum_size.y = ROW_HEIGHT * Net.MAX_PLAYERS
	list_margin.add_child(player_rows)
	ready_button = _check_button("Ready")
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


func _show_tab(index: int) -> void:
	_tabs.select_item(index)
	_tab_title.text = "Connection" if index == 0 else "Contestants"
	_connection_body.visible = index == 0
	_roster_body.visible = index == 1
	status_label.visible = index == 0 or not Net.is_online()


func _show_choice(index: int) -> void:
	_choice.select_item(index)
	_host_view.visible = index == 0
	_join_view.visible = index == 1


# masked until Show is ticked. Copy works either way, so the address can go
# straight into a message without ever being on screen.
func _fill_addresses() -> void:
	for child: Node in _address_rows.get_children():
		_address_rows.remove_child(child)
		child.queue_free()
	var addresses: PackedStringArray = Net.addresses_to_give_out()
	if addresses.is_empty():
		var none := Label.new()
		none.text = "No network address found on this computer."
		_address_rows.add_child(none)
		return
	for address: String in addresses:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_address_rows.add_child(row)
		var copy := GAME_BUTTON.new()
		copy.text = "Copy"
		copy.use_small()
		copy.custom_minimum_size.y = 36
		copy.pressed.connect(func() -> void:
			DisplayServer.clipboard_set(address)
			copy.text = "Copied"
			await get_tree().create_timer(1.5).timeout
			if is_instance_valid(copy): copy.text = "Copy")
		row.add_child(copy)
		var shown := Label.new()
		shown.text = address if _show_addresses.button_pressed else "•••.•••.•••.•••"
		shown.custom_minimum_size.x = 150
		row.add_child(shown)
		var hint := Label.new()
		hint.text = Net.address_hint(address)
		hint.add_theme_color_override("font_color", Color("cccccc"))
		row.add_child(hint)


func _check_button(text: String) -> CheckButton:
	var check := CheckButton.new()
	check.text = text
	check.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	check.focus_mode = Control.FOCUS_NONE
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		check.add_theme_color_override(state, Color.WHITE)
	return check


# a ButtonCV stretches to whatever its row is; this keeps it its own size.
func _padded(button: Control) -> Control:
	var row := HBoxContainer.new()
	row.add_child(button)
	return row


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
	field.custom_minimum_size = Vector2(300, 36)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	return field


func _on_host() -> void:
	var err: Error = Net.host_game(name_field.text, Profile.contestant, int(port_field.text))
	if err == OK:
		# not the addresses themselves: this line is on screen whatever Show says.
		_set_status("Lobby open on port %s. Send a friend one of the addresses above." % port_field.text)


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
	# the host stays put: the addresses they need to send out are on this tab.
	if online and not _was_online and not Net.is_host(): _show_tab(1)
	_was_online = online
	_choice.enabled = not online
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

	player_rows.clear()
	var root: TreeItem = player_rows.create_item()
	for slot: int in Net.slot_count():
		var peer: int = Net.peer_for_slot(slot)
		var record: Dictionary = Net.players.get(peer, {})
		var row: TreeItem = player_rows.create_item(root)
		row.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		row.set_checked(0, bool(record.get("ready", false)))
		row.set_tooltip_text(0, "Ready" if record.get("ready", false) else "Not ready")
		var shown: String = str(record.get("name", "?")).substr(0, 28)
		if peer == Net.my_id(): shown += " (you)"
		row.set_text(1, "%d.  %s" % [slot + 1, shown])
		row.set_text(2, "Host" if peer == 1 else "")
		row.set_text_alignment(2, HORIZONTAL_ALIGNMENT_RIGHT)
		for column: int in 3: row.set_selectable(column, false)
	if Net.slot_count() == 0:
		var empty: TreeItem = player_rows.create_item(root)
		empty.set_text(1, "Nobody here yet. Host or join a game first.")
		for column: int in 3: empty.set_selectable(column, false)

	if online:
		var mismatched: PackedStringArray = Net.mismatched_players()
		if mismatched.is_empty(): warning_label.text = ""
		else:
			warning_label.text = ("Your voice pack libraries are not identical: %s.\n"
				+ "Standard mode only cares if the host picks clips from one of these packs. "
				+ "For Dub Mode, a missing selected pack is okay: enable experimental pack sharing, "
				+ "let everyone accept and verify it, then begin the dub.") % "; ".join(mismatched)
