extends SceneTree
## Category dropdown in the Community Packs browser, against live GameBanana,
## and the Installed packs list grouping a multi-folder install into one row.
func _initialize():
	create_timer(60).timeout.connect(func(): print("FAIL: timed out"); quit(1))
	call_deferred("check")

func wait_for_page(browser) -> void:
	var started: int = Time.get_ticks_msec()
	await process_frame
	while browser._catalog.is_busy() and Time.get_ticks_msec() - started < 20000: await process_frame
	await process_frame

func check():
	root.size = Vector2i(1152, 648)
	var shell = load("res://scene/menu/_master/menu_master.tscn").instantiate()
	shell.stopgap_ignore_standard_instruction = true
	root.add_child(shell)
	shell.NewSlide("res://net/community_pack_browser.tscn", false)
	await process_frame
	var browser = shell.get_node("SlideCapsule").get_child(0)
	var category: OptionButton = browser._category
	assert(category.item_count == 8 and category.get_item_text(0) == "All pack types")
	assert(category.get_parent() == browser._sort.get_parent(), "category sits with the sort dropdown")
	await wait_for_page(browser)
	assert(not browser._records.is_empty(), "All pack types loaded nothing: %s" % browser._list_status.text)
	# the filter column grew for the new dropdown: nothing may overlap
	await process_frame
	var slot: Control = browser._rated.get_parent().get_parent()
	assert(browser._rated.get_global_rect().end.y <= slot.get_global_rect().end.y + 0.5, "Content-rated spills out of its slot")
	assert(category.get_global_rect().end.y < browser._sort.get_global_rect().position.y)

	for index: int in [3, 4, 6]:  # Players, Menus, Judges
		category.select(index)
		category.item_selected.emit(index)
		await wait_for_page(browser)
		var wanted: String = browser.CATALOG_SCRIPT.CATEGORIES[index]["name"]
		assert(not browser._records.is_empty(), "%s loaded nothing: %s" % [wanted, browser._list_status.text])
		for record: Dictionary in browser._records:
			assert(record["category"] == wanted, "%s list has a %s pack" % [wanted, record["category"]])
		print("OK  %s: %s, first is %s" % [category.get_item_text(index), browser._list_status.text, browser._records[0]["name"]])
	category.select(3)
	category.item_selected.emit(3)
	await wait_for_page(browser)
	browser._search.text = "mario"
	browser._on_search_submitted("mario")
	await wait_for_page(browser)
	assert(not browser._records.is_empty(), "no Players found for mario")
	for record: Dictionary in browser._records: assert(record["category"] == "Players")
	print("OK  search inside Players: %d results" % browser._records.size())

	# a two-player archive is one row in Installed packs
	var installer: GDScript = load("res://net/community_pack_installer.gd")
	var zip_path: String = "user://category-test.zip"
	var packer := ZIPPacker.new()
	assert(packer.open(zip_path) == OK)
	for path: String in ["Category Test A/config_player.json", "Category Test B/config_player.json"]:
		packer.start_file(path)
		packer.write_file("{}".to_utf8_buffer())
		packer.close_file()
	packer.close()
	var mod_id: int = 990777
	var result: Dictionary = installer._validate_and_extract(zip_path,
		{"id": mod_id, "name": "Category test players", "author": "test"},
		{"id": 1, "name": "category-test.zip", "md5": FileAccess.get_md5(zip_path)}, installer.type_roots(), true)
	DirAccess.remove_absolute(zip_path)
	assert(not result.has("error"), str(result))
	browser._show_installed()
	assert(not category.visible, "category dropdown only belongs on Browse")
	var row: TreeItem = null
	var item: TreeItem = browser._list.get_root().get_first_child()
	while item != null:
		if item.get_text(0) == "Category test players":
			assert(row == null, "the install is listed twice")
			row = item
		item = item.get_next()
	assert(row != null and row.get_tooltip_text(0) == "2 players", "row: %s" % (row.get_tooltip_text(0) if row else "missing"))
	row.select(0)
	await process_frame
	var text: String = browser._detail_description.text
	assert(text.begins_with("2 players\n") and text.contains("packs_player/Category Test A")
		and text.contains("packs_player/Category Test B"), text)
	var removed: Dictionary = installer.uninstall(mod_id)
	assert(not removed.has("error") and Array(removed["paths"]).size() == 2, str(removed))
	print("OK  Installed packs: one row, \"%s\"" % browser._detail_description.text.replace("\n", " | "))
	assert(browser._guide_button.visible and browser._guide_type == "player")

	# Guide opens Modpack Guides on the Player Packs page, Back returns here
	browser.menu_data.back_path = "res://scene/menu/home/menu_home.tscn"
	browser.menu_data.assume_path = false
	browser._guide_button.pressed.emit()
	await process_frame
	await process_frame
	var guide = shell.get_node("SlideCapsule").get_child(-1)
	assert(guide.scene_file_path.ends_with("menu_guide_packs.tscn"), guide.scene_file_path)
	assert(guide.current_page_index == 4 and guide.pages.get_child(4).visible)
	assert(guide.get_node("Border/HBoxContainer/ArrayPageSelection").selected == 4)
	shell.new_slide_from_data()
	await process_frame
	var back = shell.get_node("SlideCapsule").get_child(-1)
	assert(back.scene_file_path.ends_with("community_pack_browser.tscn"), back.scene_file_path)
	assert(back.menu_data.back_path == "res://scene/menu/home/menu_home.tscn", "Back from the browser lost its way home")
	print("OK  Guide opens Player Packs and comes back to the browser")
	shell.free()
	print("PASS: category dropdown filters browse and search, Installed packs groups a submission")
	quit()
