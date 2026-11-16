extends MenuBase

const GAME_BUTTON = preload("res://net/choicer_button.gd")
const STYLE = preload("res://net/choicer_style.gd")
# MenuBase page; menu_master owns the background, breadcrumb and return bar.

signal closed

const CATALOG_SCRIPT: Script = preload("res://net/gamebanana_client.gd")
const INSTALLER_SCRIPT: Script = preload("res://net/community_pack_installer.gd")

const BG: Color = Color("f5f8f8")
const SURFACE: Color = Color("f8ffff")
const SURFACE_2: Color = Color("e2f2f3")
const BORDER: Color = Color("a4c8ce")
const TEXT: Color = Color("17383e")
const MUTED: Color = Color("5c7d82")
const ACCENT: Color = Color("9fd5df")
const WARNING: Color = Color("ffe09c")
const SUCCESS: Color = Color("a6e4be")
const DANGER: Color = Color("ff9aa6")

var _catalog: Node
var _downloads: Node
var _image_http: HTTPRequest

var _page: int = 1
var _complete: bool = false
var _query: String = ""
var _view_queries: Dictionary = {}
var _records: Array[Dictionary] = []
var _selected: Dictionary = {}
var _detail: Dictionary = {}
var _loading_detail: bool = false

var _search: LineEdit
var _sort: OptionButton
var _rated: CheckButton
var _page_label: Label
var _list_status: Label
var _list: Tree
var _previous: GAME_BUTTON
var _next: GAME_BUTTON

var _preview: TextureRect
var _preview_placeholder: Label
var _detail_title: Label
var _detail_meta: Label
var _detail_description: Label
var _file_picker: OptionButton
var _install_status: Label
var _install_progress: ProgressBar
var _install_button: GAME_BUTTON
var _uninstall_button: GAME_BUTTON
var _open_button: GAME_BUTTON
var _installed_button: GAME_BUTTON
var _downloads_button: GAME_BUTTON
var _online_downloads_box: CheckButton
var _uninstall_dialog: ConfirmationDialog
var _pending_uninstall: Dictionary = {}
var _detail_content: VBoxContainer
var _detail_actions: HBoxContainer
var _view_mode: String = "browse"
var _nav_tabs: ButtonArray
var _search_tools: Control
var _paging: Control
var _mode_actions: HBoxContainer
var _selected_job: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = STYLE.make_theme()
	_build_ui()
	_catalog = CATALOG_SCRIPT.new()
	_catalog.page_loaded.connect(_on_page_loaded)
	_catalog.detail_loaded.connect(_on_detail_loaded)
	_catalog.request_failed.connect(_on_request_failed)
	add_child(_catalog)
	_downloads = CommunityPacks.downloads
	_downloads.changed.connect(_on_downloads_changed)
	_image_http = HTTPRequest.new()
	_image_http.use_threads = false
	_image_http.timeout = 12.0
	_image_http.body_size_limit = 12 * 1024 * 1024
	_image_http.request_completed.connect(_on_image_loaded)
	add_child(_image_http)
	_on_downloads_changed()
	_load_page()


func _fit_to_viewport() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


func _exit_tree() -> void:
	if is_instance_valid(_catalog): _catalog.cancel()
	if is_instance_valid(_image_http): _image_http.cancel_request()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"): return
	get_viewport().set_input_as_handled()
	closed.emit()


func _build_ui() -> void:

	var margin: = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 58 if side in ["top", "bottom"] else 16)
	add_child(margin)

	var main: = VBoxContainer.new()
	main.add_theme_constant_override("separation", 16)
	margin.add_child(main)

	var workspace := HBoxContainer.new()
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_theme_constant_override("separation", 16)
	main.add_child(workspace)
	var navigation := VBoxContainer.new()
	navigation.custom_minimum_size.x = 224
	navigation.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	navigation.add_theme_constant_override("separation", 12)
	workspace.add_child(navigation)
	_nav_tabs = load("res://scene/module/button/button_array.tscn").instantiate()
	# Same beveled buttons and size as the game's Settings page selector.
	_nav_tabs.large_buttons = false
	_nav_tabs.columns = 1
	_nav_tabs.add_theme_constant_override("v_separation", 12)
	var browse := _button("Browse packs", false)
	browse.pressed.connect(_show_browse)
	_installed_button = _button("Installed packs", false)
	_installed_button.pressed.connect(_show_installed)
	_downloads_button = _button("Downloads", false)
	_downloads_button.pressed.connect(_show_downloads)
	for tab: GAME_BUTTON in [browse, _installed_button, _downloads_button]:
		tab.use_small()
		tab.custom_minimum_size.y = 48
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL # fill the 224px column; text changes reset min width
		_nav_tabs.add_child(tab)
	navigation.add_child(_nav_tabs)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	workspace.add_child(content)
	var tools: = HBoxContainer.new()
	_search_tools = tools
	tools.add_theme_constant_override("separation", 10)
	var search_row := Control.new()
	search_row.custom_minimum_size.y = 40
	content.add_child(search_row)
	tools.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	search_row.add_child(tools)
	_search = LineEdit.new()
	_search.placeholder_text = "Search packs"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.custom_minimum_size.y = 40
	_search.text_submitted.connect(_on_search_submitted)
	_search.text_changed.connect(func(text: String) -> void:
		if _view_mode != "browse": _on_search_submitted(text))
	tools.add_child(_search)
	var search_button: GAME_BUTTON = _button("Search", true)
	search_button.pressed.connect(func() -> void: _on_search_submitted(_search.text))
	tools.add_child(search_button)
	var filter_slot := Control.new()
	filter_slot.custom_minimum_size.y = 92
	navigation.add_child(filter_slot)
	var browse_filters := VBoxContainer.new()
	browse_filters.add_theme_constant_override("separation", 12)
	browse_filters.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	filter_slot.add_child(browse_filters)
	_sort = OptionButton.new()
	_sort.add_item("Newest")
	_sort.set_item_metadata(0, "Generic_Newest")
	_sort.add_item("Recently updated")
	_sort.set_item_metadata(1, "Generic_LatestModified")
	_sort.add_item("Most downloaded")
	_sort.set_item_metadata(2, "Generic_MostDownloaded")
	_sort.add_item("Most liked")
	_sort.set_item_metadata(3, "Generic_MostLiked")
	_sort.tooltip_text = "Sorting applies while browsing. Searches are ordered by relevance."
	_sort.item_selected.connect(func(_index: int) -> void:
		_page = 1
		_load_page())
	browse_filters.add_child(_sort)
	_rated = CheckButton.new()
	_rated.text = "Content-rated"
	_rated.tooltip_text = "Content-rated packs are hidden by default."
	_rated.toggled.connect(func(_on: bool) -> void: _render_list())
	browse_filters.add_child(_rated)
	_online_downloads_box = CheckButton.new()
	_online_downloads_box.text = "Download online"
	_online_downloads_box.tooltip_text = "Allow new downloads during online multiplayer."
	_online_downloads_box.visible = false
	_online_downloads_box.toggled.connect(func(on: bool): _downloads.set_allow_online_downloads(on))
	filter_slot.add_child(_online_downloads_box)
	var refresh: GAME_BUTTON = _button("Refresh", false)
	refresh.pressed.connect(_refresh_view)
	navigation.add_child(refresh)

	var split: = HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 356
	content.add_child(split)

	var left_panel: = PanelContainer.new()
	left_panel.custom_minimum_size.x = 356
	left_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	STYLE.pack_list_panel(left_panel)
	split.add_child(left_panel)
	var left_margin: = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		left_margin.add_theme_constant_override("margin_" + side, 14)
	left_panel.add_child(left_margin)
	var left: = VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left_margin.add_child(left)
	_list_status = Label.new()
	_list_status.add_theme_color_override("font_color", MUTED)
	left.add_child(_list_status)
	_list = Tree.new()
	var native_properties := STYLE.scene_properties("res://scene/menu/customize/menu_customize.tscn", "Border/Main/PackListings/List/MarginContainer/Tree")
	for property: String in native_properties:
		if property.begins_with("theme_override") or property in ["allow_reselect", "auto_tooltip"]:
			_list.set(property, native_properties[property])
	_list.add_theme_stylebox_override("selected", _selection_box())
	_list.add_theme_stylebox_override("selected_focus", _selection_box())
	_list.hide_root = true
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_list_selected)
	left.add_child(_list)
	var paging: = HBoxContainer.new()
	_paging = paging
	paging.alignment = BoxContainer.ALIGNMENT_CENTER
	paging.add_theme_constant_override("separation", 10)
	left.add_child(paging)
	_previous = _button("Previous", false)
	_previous.pressed.connect(func() -> void:
		if _page > 1:
			_page -= 1
			_load_page())
	paging.add_child(_previous)
	_page_label = Label.new()
	_page_label.custom_minimum_size.x = 100
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	paging.add_child(_page_label)
	_next = _button("Next", false)
	_next.pressed.connect(func() -> void:
		if not _complete:
			_page += 1
			_load_page())
	paging.add_child(_next)

	var right_panel: = PanelContainer.new()
	right_panel.custom_minimum_size.x = 300
	right_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	STYLE.dark_panel(right_panel)
	split.add_child(right_panel)
	var right_margin: = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		right_margin.add_theme_constant_override("margin_" + side, 18)
	right_panel.add_child(right_margin)
	var detail_column := VBoxContainer.new()
	right_margin.add_child(detail_column)
	var detail_scroll: = ScrollContainer.new()
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_column.add_child(detail_scroll)
	var detail: = VBoxContainer.new()
	_detail_content = detail
	detail.visible = false
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 10)
	detail_scroll.add_child(detail)
	var preview_panel: = PanelContainer.new()
	preview_panel.custom_minimum_size = Vector2(240, 150)
	preview_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	detail.add_child(preview_panel)
	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_panel.add_child(_preview)
	_preview_placeholder = Label.new()
	_preview_placeholder.text = "SELECT A PACK TO PREVIEW"
	_preview_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_preview_placeholder.add_theme_font_size_override("font_size", 13)
	_preview_placeholder.add_theme_color_override("font_color", MUTED)
	preview_panel.add_child(_preview_placeholder)
	_detail_title = Label.new()
	_detail_title.text = ""
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_title.add_theme_font_size_override("font_size", 24)
	_detail_title.add_theme_color_override("font_color", Color.WHITE)
	detail.add_child(_detail_title)
	_detail_meta = Label.new()
	_detail_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_meta.add_theme_color_override("font_color", Color("cccccc"))
	detail.add_child(_detail_meta)
	_detail_description = Label.new()
	_detail_description.text = ""
	_detail_description.add_theme_color_override("font_color", Color.WHITE)
	_detail_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_detail_description)
	var file_label: = Label.new()
	file_label.text = "Download file"
	file_label.add_theme_font_size_override("font_size", 14)
	file_label.add_theme_color_override("font_color", MUTED)
	file_label.visible = false
	detail.add_child(file_label)
	_file_picker = OptionButton.new()
	# GameBanana filenames are untrusted layout input too. OptionButton normally
	# makes its minimum width equal to its longest item, so one essay-length name
	# can push the entire split view beyond the viewport.
	_file_picker.fit_to_longest_item = false
	_file_picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_file_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_file_picker.disabled = true
	_file_picker.item_selected.connect(func(_index: int) -> void: _refresh_install_action())
	detail.add_child(_file_picker)
	_install_progress = ProgressBar.new()
	_install_progress.visible = false
	_install_progress.show_percentage = true
	detail.add_child(_install_progress)
	_install_status = Label.new()
	_install_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_install_status.add_theme_color_override("font_color", Color("cccccc"))
	detail.add_child(_install_status)
	var detail_buttons: = HBoxContainer.new()
	_detail_actions = detail_buttons
	detail_buttons.visible = false
	detail_buttons.add_theme_constant_override("separation", 8)
	detail_column.add_child(detail_buttons)
	_mode_actions = HBoxContainer.new()
	detail_column.add_child(_mode_actions)
	_install_button = _button("Install", true)
	_install_button.disabled = true
	_install_button.pressed.connect(_on_install_pressed)
	detail_buttons.add_child(_install_button)
	_uninstall_button = _button("Uninstall", false)
	_uninstall_button.visible = false
	_uninstall_button.pressed.connect(_on_uninstall_pressed)
	detail_buttons.add_child(_uninstall_button)
	_open_button = _button("GameBanana", false)
	_open_button.disabled = true
	_open_button.pressed.connect(func() -> void:
		var url: String = str(_selected.get("profile_url", ""))
		if url.begins_with("https://gamebanana.com/"): OS.shell_open(url))
	detail_buttons.add_child(_open_button)
	var caution: = Label.new()
	caution.text = ("Downloads are community content. ZIP, RAR and 7z archives are staged and checked before installation, "
		+ "but only install packs from creators you trust.")
	caution.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caution.add_theme_color_override("font_color", WARNING)
	caution.visible = false
	detail.add_child(caution)

	_uninstall_dialog = ConfirmationDialog.new()
	_uninstall_dialog.theme = STYLE.dialog_theme()
	_uninstall_dialog.dialog_autowrap = true
	_uninstall_dialog.title = "Uninstall community pack?"
	_uninstall_dialog.confirmed.connect(_confirm_uninstall)
	add_child(_uninstall_dialog)


func _load_page(force: bool = false) -> void:
	if not is_instance_valid(_catalog): return
	_catalog.cancel()
	_clear_detail()
	_loading_detail = false
	_set_list_busy(true)
	_records.clear()
	_render_list()
	if _query.is_empty():
		_catalog.fetch_page(_page, str(_sort.get_item_metadata(_sort.selected)), force)
	else:
		_catalog.search(_query, _page, "best_match", force)


func _set_list_busy(busy: bool) -> void:
	_search.editable = not busy
	_sort.disabled = busy or not _query.is_empty()
	_previous.disabled = busy or _page <= 1
	_next.disabled = busy or _complete
	if busy: _list_status.text = "Loading from GameBanana..."


func _on_page_loaded(payload: Dictionary) -> void:
	if _view_mode != "browse": return
	_loading_detail = false
	_page = int(payload.get("page", _page))
	_complete = bool(payload.get("complete", false))
	_records.clear()
	for value: Variant in Array(payload.get("records", [])):
		if value is Dictionary: _records.append(value)
	_set_list_busy(false)
	_page_label.text = "Page %d" % _page
	_previous.disabled = _page <= 1
	_next.disabled = _complete
	var total: int = int(payload.get("total", 0))
	_list_status.text = "%s%d dub pack%s" % [
		"About " if not _complete else "", total, "" if total == 1 else "s"]
	_render_list()


func _render_list() -> void:
	if _view_mode != "browse": return
	_list.clear()
	var root_item := _list.create_item()
	for record: Dictionary in _records:
		if bool(record.get("content_rated", false)) and not _rated.button_pressed: continue
		var item := _list.create_item(root_item)
		item.set_text(0, str(record.get("name", "Dub pack")))
		item.set_tooltip_text(0, "by %s • %s" % [record.get("author", "Unknown"), record.get("subcategory", "Dub Mode")])
		item.set_metadata(0, record)
		if int(record.get("id", -1)) == int(_selected.get("id", -2)): item.select(0)
	if root_item.get_child_count() == 0:
		var item := _list.create_item(root_item)
		item.set_text(0, "No matching packs")
		item.set_selectable(0, false)


func _select_record(record: Dictionary) -> void:
	_catalog.cancel()
	_loading_detail = true
	_file_picker.show()
	_detail_content.visible = true
	_detail_actions.visible = true
	_selected = record.duplicate(true)
	_detail.clear()
	_preview.texture = null
	_preview_placeholder.visible = true
	_detail_title.text = str(record.get("name", "Dub pack"))
	_detail_meta.text = "by %s" % str(record.get("author", "Unknown creator"))
	_detail_description.text = "Loading description and download files..."
	_file_picker.clear()
	_file_picker.disabled = true
	_install_status.text = ""
	_install_button.disabled = true
	_open_button.disabled = false
	_catalog.fetch_detail(int(record.get("id", 0)))
	_load_preview(str(record.get("image_url", "")))


func _on_detail_loaded(detail: Dictionary) -> void:
	if _view_mode != "browse": return
	_loading_detail = false
	if int(detail.get("id", 0)) != int(_selected.get("id", 0)): return
	for key: Variant in _selected:
		if not detail.has(key) or str(detail.get(key, "")).is_empty(): detail[key] = _selected[key]
	_detail = detail
	_detail_title.text = str(detail.get("name", "Dub pack"))
	var parts: PackedStringArray = ["by %s" % str(detail.get("author", "Unknown creator"))]
	if not str(detail.get("subcategory", "")).is_empty(): parts.append(str(detail["subcategory"]))
	if not str(detail.get("version", "")).is_empty(): parts.append("version %s" % str(detail["version"]))
	if bool(detail.get("content_rated", false)): parts.append("CONTENT-RATED")
	_detail_meta.text = "  •  ".join(parts)
	_detail_meta.add_theme_color_override(
		"font_color", WARNING if bool(detail.get("content_rated", false)) else Color("cccccc"))
	var description: String = str(detail.get("description", ""))
	_detail_description.text = description if not description.is_empty() else "No description was provided."
	_file_picker.clear()
	for file_value: Variant in Array(detail.get("files", [])):
		if not file_value is Dictionary: continue
		var file: Dictionary = file_value
		var full_name: String = str(file["name"])
		_file_picker.add_item("%s  —  %s" % [
			_compact_text(full_name, 62), _format_bytes(int(file["size"]))])
		var item_index: int = _file_picker.item_count - 1
		_file_picker.set_item_metadata(item_index, file)
		_file_picker.get_popup().set_item_tooltip(item_index, full_name)
	_file_picker.disabled = _file_picker.item_count == 0
	if _file_picker.item_count > 0:
		var first_zip: int = 0
		for i: int in _file_picker.item_count:
			var candidate: Dictionary = _file_picker.get_item_metadata(i)
			if str(candidate.get("name", "")).get_extension().to_lower() == "zip":
				first_zip = i
				break
		_file_picker.select(first_zip)
	_refresh_install_action()


func _selected_file() -> Dictionary:
	if _file_picker.item_count == 0 or _file_picker.selected < 0: return {}
	var value: Variant = _file_picker.get_item_metadata(_file_picker.selected)
	return value if value is Dictionary else {}


func _refresh_install_action() -> void:
	if _view_mode != "browse": return
	if not is_instance_valid(_downloads): return
	if _selected.is_empty() or _loading_detail:
		_install_button.disabled = true
		_install_status.text = ""
		return
	var mod_id: int = int(_detail.get("id", 0))
	var installed: String = INSTALLER_SCRIPT.installed_path(mod_id)
	_uninstall_button.visible = not installed.is_empty()
	_uninstall_button.disabled = CommunityPacks.is_online() or _mod_has_active_job(mod_id)
	if not installed.is_empty():
		_install_button.text = "Installed"
		_install_button.disabled = true
		_install_progress.visible = false
		_install_status.text = "Installed in %s" % installed
		if _mod_has_active_job(mod_id):
			_install_status.text += "\nA download for this submission is still active."
		_install_status.add_theme_color_override("font_color", SUCCESS)
		return
	var file: Dictionary = _selected_file()
	if file.is_empty():
		_install_button.text = "Install pack"
		_install_button.disabled = true
		_install_progress.visible = false
		_install_status.text = "This submission has no downloadable files."
		return
	var job: Dictionary = _downloads.job_for(mod_id, int(file.get("id", 0)))
	var state: String = str(job.get("state", ""))
	if state in ["queued", "downloading", "verifying", "installing"]:
		_install_button.text = "View downloads"
		_install_button.disabled = false
		_install_progress.visible = true
		_install_progress.max_value = maxi(1, int(job.get("total", file.get("size", 0))))
		_install_progress.value = clampi(
			int(job.get("received", 0)), 0, int(_install_progress.max_value))
		var status: String = str(job.get("status", "Queued"))
		if state == "queued" and CommunityPacks.is_online() and not _downloads.allow_online_downloads():
			status = "Queued — waiting until you leave online multiplayer."
		_install_status.text = status
		_install_status.add_theme_color_override("font_color", Color("cccccc"))
		return
	if state in ["failed", "canceled"]:
		_install_progress.visible = false
		_install_button.text = "Retry download"
		_install_button.disabled = false
		_install_status.text = str(job.get(
			"error", "Canceled" if state == "canceled" else "Download failed"))
		if _install_status.text.is_empty(): _install_status.text = "Canceled"
		_install_status.add_theme_color_override("font_color", DANGER if state == "failed" else Color("cccccc"))
		return
	var problem: String = INSTALLER_SCRIPT.installability_problem(file)
	_install_progress.visible = false
	_install_button.text = "Download"
	_install_button.disabled = not problem.is_empty()
	if not problem.is_empty():
		_install_status.text = problem
		_install_status.add_theme_color_override("font_color", DANGER)
	elif CommunityPacks.is_online() and not _downloads.allow_online_downloads():
		_install_status.text = "This will wait in the queue until you leave online multiplayer."
		_install_status.add_theme_color_override("font_color", WARNING)
	elif CommunityPacks.is_online():
		_install_status.text = "Ready to queue online. Large downloads may increase multiplayer latency."
		_install_status.add_theme_color_override("font_color", WARNING)
	else:
		_install_status.text = ""
		_install_status.add_theme_color_override("font_color", Color("cccccc"))


func _on_install_pressed() -> void:
	var file: Dictionary = _selected_file()
	if file.is_empty() or _detail.is_empty(): return
	var existing: Dictionary = _downloads.job_for(
		int(_detail.get("id", 0)), int(file.get("id", 0)))
	if str(existing.get("state", "")) in ["queued", "downloading", "verifying", "installing"]:
		_show_downloads()
		return
	_downloads.enqueue(_detail, file)
	_refresh_install_action()


func _on_downloads_changed() -> void:
	if not is_instance_valid(_downloads_button): return
	if is_instance_valid(_online_downloads_box):
		_online_downloads_box.set_pressed_no_signal(_downloads.allow_online_downloads())
	var active: int = _downloads.active_count()
	_downloads_button.text = "Downloads (%d)" % active if active > 0 else "Downloads"
	if _view_mode == "downloads":
		_render_downloads()
		return
	# the download bar belongs to the Browse page. on Installed packs it landed on
	# whatever pack was open, showing someone else's download as 0%.
	if _view_mode != "browse": return
	if not _update_selected_active_download(): _refresh_install_action()


func _update_selected_active_download() -> bool:
	var file: Dictionary = _selected_file()
	if file.is_empty() or _detail.is_empty(): return false
	var job: Dictionary = _downloads.job_for(
		int(_detail.get("id", 0)), int(file.get("id", 0)))
	var state: String = str(job.get("state", ""))
	if state not in ["queued", "downloading", "verifying", "installing"]: return false
	_install_button.text = "View downloads"
	_install_button.disabled = false
	_install_progress.visible = true
	_install_progress.max_value = maxi(1, int(job.get("total", file.get("size", 0))))
	_install_progress.value = clampi(int(job.get("received", 0)), 0, int(_install_progress.max_value))
	_install_status.text = str(job.get("status", "Queued"))
	if state == "queued" and CommunityPacks.is_online() and not _downloads.allow_online_downloads():
		_install_status.text = "Queued — waiting until you leave online multiplayer."
	_install_status.add_theme_color_override("font_color", Color("cccccc"))
	return true


func _set_view(mode: String) -> void:
	_view_queries[_view_mode] = _search.text
	_catalog.cancel()
	_image_http.cancel_request()
	_loading_detail = false
	_view_mode = mode
	_nav_tabs.select_item(["browse", "installed", "downloads"].find(mode))
	_search_tools.show()
	_search.set_block_signals(true)
	_search.text = str(_view_queries.get(mode, ""))
	_search.set_block_signals(false)
	_search.placeholder_text = "Search packs" if mode == "browse" else "Search " + mode
	_search.editable = true
	_paging.visible = mode == "browse"
	_sort.visible = mode == "browse"
	_rated.visible = mode == "browse"
	_online_downloads_box.visible = mode == "downloads"
	_detail_content.hide()
	_detail_actions.hide()
	_mode_actions.hide()
	_preview.get_parent().visible = mode == "browse"
	_file_picker.visible = mode == "browse"
	_install_button.visible = mode == "browse"
	_uninstall_button.hide()
	_install_progress.hide()
	_selected_job = ""
	_list.clear()


func _on_search_submitted(text: String) -> void:
	match _view_mode:
		"installed": _render_installed()
		"downloads": _render_downloads()
		_:
			_query = text.strip_edges()
			_page = 1
			_load_page()


func _show_browse() -> void:
	_set_view("browse")
	_load_page()


func _show_downloads() -> void:
	_set_view("downloads")
	_render_downloads()


func _show_installed() -> void:
	_set_view("installed")
	_render_installed()


func _refresh_view() -> void:
	match _view_mode:
		"installed": _render_installed()
		"downloads": _render_downloads()
		_: _load_page(true)


func _on_list_selected() -> void:
	var item := _list.get_selected()
	if item == null: return
	var record: Dictionary = item.get_metadata(0)
	match _view_mode:
		"installed": _show_installed_detail(record)
		"downloads": _show_download_detail(record)
		_: _select_record(record)


func _render_installed() -> void:
	if _view_mode != "installed": return
	_list.clear()
	var root_item := _list.create_item()
	var packs: Array[Dictionary] = INSTALLER_SCRIPT.installed_packs()
	var total := packs.size()
	var query := _search.text.strip_edges().to_lower()
	if not query.is_empty():
		packs = packs.filter(func(pack: Dictionary): return ("%s %s %s" % [pack.get("name", ""), pack.get("author", ""), pack.get("folder", "")]).to_lower().contains(query))
	_list_status.text = "Installed packs (%d)" % packs.size() if query.is_empty() else "Installed packs (%d of %d)" % [packs.size(), total]
	for pack: Dictionary in packs:
		var item := _list.create_item(root_item)
		item.set_text(0, str(pack.get("name", pack.get("folder", "Dub pack"))))
		item.set_metadata(0, pack)
	if packs.is_empty():
		var item := _list.create_item(root_item)
		item.set_text(0, "No matching packs" if not query.is_empty() else "No browser-installed packs")
		item.set_selectable(0, false)


func _show_installed_detail(pack: Dictionary) -> void:
	_detail = {"id": pack.get("mod_id", 0), "name": pack.get("name", "Dub pack")}
	_selected = {"profile_url": pack.get("profile_url", "")}
	_detail_content.show()
	_detail_actions.show()
	_detail_title.text = str(pack.get("name", "Dub pack"))
	_detail_meta.text = "by %s • %s" % [pack.get("author", "Unknown"), _format_bytes(int(pack.get("installed_bytes", 0)))]
	_detail_description.text = "Folder: %s" % pack.get("folder", "")
	_install_status.text = "Leave online play before uninstalling." if CommunityPacks.is_online() else ""
	_uninstall_button.show()
	_uninstall_button.disabled = CommunityPacks.is_online() or _mod_has_active_job(int(pack.get("mod_id", 0)))
	_open_button.disabled = not str(pack.get("profile_url", "")).begins_with("https://gamebanana.com/")


func _render_downloads() -> void:
	if _view_mode != "downloads": return
	_list.set_block_signals(true)
	_list.clear()
	var root_item := _list.create_item()
	var jobs: Array[Dictionary] = _downloads.get_jobs()
	var total := jobs.size()
	var query := _search.text.strip_edges().to_lower()
	if not query.is_empty():
		jobs = jobs.filter(func(job: Dictionary): return ("%s %s %s %s" % [job.get("mod", {}).get("name", ""), job.get("mod", {}).get("author", ""), job.get("file", {}).get("name", ""), job.get("state", "")]).to_lower().contains(query))
	_list_status.text = "Downloads (%d)" % jobs.size() if query.is_empty() else "Downloads (%d of %d)" % [jobs.size(), total]
	for job: Dictionary in jobs:
		var item := _list.create_item(root_item)
		var mod: Dictionary = job.get("mod", {})
		item.set_text(0, str(mod.get("name", "Dub pack")))
		var size: int = int(job.get("total", 0))
		item.set_icon(0, _status_icon(str(job.get("state", "")),
			float(job.get("received", 0)) / size if size > 0 else 0.0))
		item.set_icon_max_width(0, STATUS_ICON_SIZE)
		item.set_metadata(0, job)
		if str(job.get("id", "")) == _selected_job:
			item.select(0)
			_show_download_detail(job)
	if jobs.is_empty():
		var item := _list.create_item(root_item)
		item.set_text(0, "No matching downloads" if not query.is_empty() else "No downloads")
		item.set_selectable(0, false)
	_list.set_block_signals(false)


const STATUS_ICON_SIZE: int = 22


# drawn here at twice the size: an empty ring while queued, a ring filling up
# clockwise while it downloads, a tick when it's installed, a cross if it failed.
static func _status_icon(state: String, fraction: float) -> ImageTexture:
	var n: int = STATUS_ICON_SIZE * 2
	var image := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var center := Vector2(n, n) / 2.0
	var radius: float = n / 2.0 - 2.0
	var disc: Color = {"finished": Color("3f9a5c"), "failed": Color("d0505c"), "canceled": Color("9aa5a8")}.get(state, Color(0, 0, 0, 0))
	var ring: Color = Color("9aa5a8") if state == "queued" else Color("3a9fb3")
	if state in ["verifying", "installing"]: fraction = 1.0
	for y: int in n:
		for x: int in n:
			var p := Vector2(x + 0.5, y + 0.5) - center
			var d: float = p.length()
			var color := Color(0, 0, 0, 0)
			if disc.a > 0.0:
				if d <= radius: color = disc
			elif absf(d - (radius - 1.5)) <= 1.5:
				color = ring
			elif d <= radius - 5.0 and state != "queued" and fposmod(atan2(p.x, -p.y), TAU) <= fraction * TAU:
				color = ring
			image.set_pixel(x, y, color)
	var marks: Array = []
	if state == "finished": marks = [[Vector2(0.29, 0.52), Vector2(0.44, 0.67)], [Vector2(0.44, 0.67), Vector2(0.72, 0.36)]]
	elif state in ["failed", "canceled"]: marks = [[Vector2(0.34, 0.34), Vector2(0.66, 0.66)], [Vector2(0.66, 0.34), Vector2(0.34, 0.66)]]
	for mark: Array in marks:
		var a: Vector2 = mark[0] * n
		var b: Vector2 = mark[1] * n
		for y: int in n:
			for x: int in n:
				var p := Vector2(x + 0.5, y + 0.5)
				var t: float = clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
				if p.distance_to(a + (b - a) * t) <= n * 0.05: image.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(image)


func _show_download_detail(job: Dictionary) -> void:
	_selected_job = str(job.get("id", ""))
	var mod: Dictionary = job.get("mod", {})
	var file: Dictionary = job.get("file", {})
	_detail_content.show()
	_detail_title.text = str(mod.get("name", "Dub pack"))
	_detail_meta.text = str(file.get("name", "ZIP"))
	_detail_description.text = str(job.get("status", job.get("state", "Queued")))
	_install_status.text = str(job.get("error", ""))
	var state: String = str(job.get("state", ""))
	_install_progress.visible = state in ["downloading", "verifying", "installing"]
	_install_progress.max_value = maxi(1, int(job.get("total", 0)))
	_install_progress.value = int(job.get("received", 0))
	for child: Node in _mode_actions.get_children():
		_mode_actions.remove_child(child)
		child.queue_free()
	_mode_actions.show()
	if state in ["queued", "downloading"]:
		var cancel := _button("Cancel", false)
		cancel.pressed.connect(_downloads.cancel.bind(_selected_job))
		_mode_actions.add_child(cancel)
	elif state in ["failed", "canceled", "finished"]:
		if state != "finished":
			var retry := _button("Retry", false)
			retry.pressed.connect(_downloads.retry.bind(_selected_job))
			_mode_actions.add_child(retry)
		var dismiss := _button("Dismiss", false)
		dismiss.pressed.connect(_dismiss_job.bind(_selected_job))
		_mode_actions.add_child(dismiss)


func _dismiss_job(id: String) -> void:
	_selected_job = ""
	_detail_content.hide()
	_mode_actions.hide()
	_downloads.dismiss(id)


func _mod_has_active_job(mod_id: int) -> bool:
	if mod_id <= 0: return false
	for job: Dictionary in _downloads.get_jobs():
		var mod: Dictionary = job.get("mod", {})
		if (int(mod.get("id", 0)) == mod_id
			and str(job.get("state", "")) in ["queued", "downloading", "verifying", "installing"]):
			return true
	return false


func _open_gamebanana(url: String) -> void:
	if url.begins_with("https://gamebanana.com/"): OS.shell_open(url)


func _on_uninstall_pressed() -> void:
	var mod_id: int = int(_detail.get("id", 0))
	if mod_id <= 0 or CommunityPacks.is_online() or _mod_has_active_job(mod_id): return
	_request_uninstall({
		"mod_id": mod_id,
		"name": str(_detail.get("name", "Dub pack")),
		"path": INSTALLER_SCRIPT.installed_path(mod_id),
	})


func _request_uninstall(pack: Dictionary) -> void:
	var mod_id: int = int(pack.get("mod_id", 0))
	if mod_id <= 0 or CommunityPacks.is_online() or _mod_has_active_job(mod_id): return
	_pending_uninstall = pack.duplicate(true)
	_uninstall_dialog.dialog_text = ("Remove '%s' and all files this installer placed in its pack folder?\n\n"
		+ "Manually installed packs are never removed by this button.") % str(
			pack.get("name", "Dub pack"))
	_uninstall_dialog.popup_centered(Vector2i(560, 190))


func _confirm_uninstall() -> void:
	var pack: Dictionary = _pending_uninstall.duplicate(true)
	_pending_uninstall.clear()
	var mod_id: int = int(pack.get("mod_id", 0))
	if mod_id <= 0 or CommunityPacks.is_online() or _mod_has_active_job(mod_id): return
	var result: Dictionary = INSTALLER_SCRIPT.uninstall(mod_id, str(pack.get("path", "")))
	if result.has("error"):
		var message: String = str(result["error"])
		if int(_detail.get("id", 0)) == mod_id:
			_install_status.text = message
			_install_status.add_theme_color_override("font_color", DANGER)
		return
	_downloads.dismiss_for_mod(mod_id)
	CommunityPacks.community_pack_library_changed()
	if int(_detail.get("id", 0)) == mod_id:
		_refresh_install_action()
		_install_status.text = "Uninstalled %s." % str(pack.get("name", "community pack"))
		_install_status.add_theme_color_override("font_color", SUCCESS)
	if _view_mode == "installed":
		_detail_content.hide()
		_detail_actions.hide()
		_render_installed()


func _on_request_failed(message: String) -> void:
	if _view_mode != "browse": return
	_set_list_busy(false)
	if _loading_detail:
		_loading_detail = false
		_file_picker.hide()
		_detail_description.text = message
		_install_status.text = "You can still open the submission on GameBanana."
		_install_status.add_theme_color_override("font_color", DANGER)
	else:
		_list_status.text = message


func _load_preview(url: String) -> void:
	_image_http.cancel_request()
	_preview_placeholder.visible = true
	if not url.begins_with("https://images.gamebanana.com/"):
		_preview_placeholder.text = "NO PREVIEW PROVIDED"
		return
	_preview_placeholder.text = "LOADING PREVIEW..."
	var error: Error = _image_http.request(
		url, ["User-Agent: TCV-Multiplayer/%s" % str(CommunityPacks.VERSION)])
	if error != OK: _preview_placeholder.text = "PREVIEW UNAVAILABLE"


func _on_image_loaded(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_preview_placeholder.text = "PREVIEW UNAVAILABLE"
		return
	var image: = Image.new()
	var error: Error = image.load_webp_from_buffer(body)
	if error != OK: error = image.load_jpg_from_buffer(body)
	if error != OK: error = image.load_png_from_buffer(body)
	if error == OK:
		_preview.texture = ImageTexture.create_from_image(image)
		_preview_placeholder.visible = false
	else:
		_preview_placeholder.text = "PREVIEW UNAVAILABLE"


static func _button(text: String, _primary: bool) -> GAME_BUTTON:
	var button := GAME_BUTTON.new()
	button.text = text
	return button


static func _box(color: Color, radius: int, border: Color, width: int) -> StyleBoxFlat:
	var box: = StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.border_width_left = width
	box.border_width_right = width
	box.border_width_top = width
	box.border_width_bottom = width
	box.border_color = border
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box


static func _format_bytes(bytes: int) -> String:
	if bytes >= 1024 * 1024 * 1024: return "%.2f GB" % (float(bytes) / 1073741824.0)
	if bytes >= 1024 * 1024: return "%.1f MB" % (float(bytes) / 1048576.0)
	if bytes >= 1024: return "%.1f KB" % (float(bytes) / 1024.0)
	return "%d bytes" % bytes


static func _compact_text(value: String, limit: int) -> String:
	if value.length() <= limit: return value
	if limit < 8: return value.left(maxi(1, limit - 1)) + "…"
	# Keep the tail because archive extensions and numbered variants tend to live
	# there, while still putting most of the useful title at the front.
	var tail: int = mini(14, limit / 4)
	return value.left(limit - tail - 1) + "…" + value.right(tail)

func _clear_detail() -> void:
	_selected.clear()
	_detail.clear()
	_image_http.cancel_request()
	_detail_content.hide()
	_detail_actions.hide()
	_install_progress.hide()
	_install_status.text = ""

static func _selection_box() -> StyleBox:
	var properties := STYLE.scene_properties("res://scene/menu/customize/menu_customize.tscn", "Border/Main/PackListings/List/MarginContainer/VoicePackTree")
	var native_theme: Theme = properties["theme"]
	return native_theme.get_stylebox("selected_focus", "Tree")
