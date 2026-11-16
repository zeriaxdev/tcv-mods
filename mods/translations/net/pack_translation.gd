extends RefCounted
## Caption translations for dub packs, kept on this computer in
## user://translations/<pack folder>/<name>.txt, one file per imported translation,
## plus a `chosen` file naming the one Dub Mode shows. Nothing is written into the
## pack folder, so the pack stays the same file for file (online pack checks match).
##
## Script file, one line per captioned clip, sorted by file name:
##   12 | 01_intro.wav | Clark | Hello there.\nHow are you?
## Import matches lines by file name, and by number when a translator mangled the name.

const STYLE := preload("res://net/choicer_style.gd")
const BUTTON := preload("res://net/choicer_button.gd")
const ROOT := "user://translations/"


static func dir_for(pack: PackInfo) -> String:
	return ROOT + pack.folder_name.trim_suffix("/").validate_filename() + "/"


static func file_for(pack: PackInfo, name: String) -> String:
	return dir_for(pack) + name + ".txt"


## The clip's path inside its pack, like "01_intro.wav" or "act 2/05_door.wav".
static func clip_id(clip: OmniClip, pack: PackInfo) -> String:
	return clip.self_global_path.trim_prefix(pack.global_folder_path.trim_suffix("/") + "/")


static func _caption(clip: OmniClip) -> String:
	return clip.clip_caption.replace("\r\n", "\n").strip_edges()


## [[id, clip], ...] for every clip with a caption, in file name order.
static func _lines(clips: Array, pack: PackInfo) -> Array:
	var out := []
	for clip: OmniClip in clips:
		if _caption(clip) != "": out.append([clip_id(clip, pack), clip])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[0].naturalnocasecmp_to(b[0]) < 0)
	return out


static func _row(number: int, id: String, clip: OmniClip, caption: String) -> String:
	return "%d | %s | %s | %s\n" % [number, id, ", ".join(clip.dub_characters), caption.replace("\n", "\\n")]


static func script_text(clips: Array, pack: PackInfo) -> String:
	var text := "# Captions from \"%s\"\n" % pack.display_name
	text += "# Translate the caption at the end of each line. Leave the number, file name and character as they are.\n"
	text += "# \\n starts a new line inside a caption.\n\n"
	var number := 0
	for line: Array in _lines(clips, pack):
		number += 1
		text += _row(number, line[0], line[1], _caption(line[1]))
	return text


## { clip id: caption } from a script file. With ids given, a line whose file name
## is not one of them falls back to its number.
static func parse(text: String, ids: PackedStringArray = []) -> Dictionary:
	var out := {}
	var newline := RegEx.create_from_string("\\\\\\s*[nN]")  # \n, also "\ n" from translators
	for raw: String in text.replace("﻿", "").split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("#"): continue
		var parts := line.split("|", true, 3)
		if parts.size() < 4: continue
		var id := parts[1].strip_edges()
		if not ids.is_empty() and not ids.has(id):
			var number := parts[0].strip_edges().to_int()
			if number < 1 or number > ids.size(): continue
			id = ids[number - 1]
		var caption := newline.sub(parts[3].strip_edges(), "\n", true).strip_edges()
		if caption != "": out[id] = caption
	return out


# --- Saved translations ---

## Names of this pack's translations, in alphabetical order.
static func names(pack: PackInfo) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir_for(pack)): return out
	for file: String in DirAccess.get_files_at(dir_for(pack)):
		if file.get_extension() == "txt": out.append(file.get_basename())
	out.sort()
	return out


## The translation Dub Mode shows for this pack, or "" for the original captions.
static func chosen(pack: PackInfo) -> String:
	var name := FileAccess.get_file_as_string(dir_for(pack) + "chosen").strip_edges()
	return name if name != "" and FileAccess.file_exists(file_for(pack, name)) else ""


static func choose(pack: PackInfo, name: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir_for(pack))
	var file := FileAccess.open(dir_for(pack) + "chosen", FileAccess.WRITE)
	if file: file.store_string(name)


static func remove(pack: PackInfo, name: String) -> void:
	if chosen(pack) == name: choose(pack, "")
	DirAccess.remove_absolute(file_for(pack, name))


static func captions(pack: PackInfo, name: String) -> Dictionary:
	if name == "" or not FileAccess.file_exists(file_for(pack, name)): return {}
	return parse(FileAccess.get_file_as_string(file_for(pack, name)))


## Translated captions Dub Mode shows for this pack, by clip id.
static func saved(pack: PackInfo) -> Dictionary:
	return captions(pack, chosen(pack))


## A translation's name from the file it came from: "Backrooms suomi.txt" -> "suomi".
static func name_from(path: String, pack: PackInfo) -> String:
	var name := path.get_file().get_basename().strip_edges()
	if name.to_lower().begins_with(pack.display_name.to_lower()): name = name.substr(pack.display_name.length())
	if name.to_lower().ends_with(" script"): name = name.left(-7)
	name = name.strip_edges().lstrip("-_ ").rstrip("-_ ").validate_filename()
	return name if name != "" and name != "chosen" else "Translation"


## Saves the translated lines of `text` as this pack's translation `name` and
## chooses it. Returns how many captions it translates; 0 saves nothing.
static func import_text(text: String, clips: Array, pack: PackInfo, name: String) -> int:
	var lines := _lines(clips, pack)
	var ids := PackedStringArray(lines.map(func(line: Array) -> String: return line[0]))
	var found := parse(text, ids)
	var out := "# %s translation of \"%s\", imported %s\n\n" % [name, pack.display_name, Time.get_date_string_from_system()]
	var count := 0
	for i: int in lines.size():
		var caption: String = found.get(lines[i][0], "")
		if caption == "" or caption == _caption(lines[i][1]): continue  # missing or left untranslated
		out += _row(i + 1, lines[i][0], lines[i][1], caption)
		count += 1
	if count == 0: return 0
	DirAccess.make_dir_recursive_absolute(dir_for(pack))
	var file := FileAccess.open(file_for(pack, name), FileAccess.WRITE)
	if file == null: return 0
	file.store_string(out)
	file.close()
	choose(pack, name)
	return count


# --- Dub Mode ---

## Shows the clip's caption, translated when this pack has a translation for it,
## with the pack's original caption smaller underneath.
static func show_caption(label: Label, clip: OmniClip, pack: PackInfo) -> void:
	var translated: String = saved(pack).get(clip_id(clip, pack), "")
	var original: Label = label.get_node_or_null("Original")
	if original == null:
		original = Label.new()
		original.name = "Original"
		original.mouse_filter = Control.MOUSE_FILTER_IGNORE
		original.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		original.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		original.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		original.max_lines_visible = 3
		original.add_theme_font_size_override("font_size", maxi(12, roundi(label.get_theme_font_size("font_size") * 0.6)))
		original.modulate = Color(1, 1, 1, 0.6)
		label.add_child(original)
		original.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# Only while the label still shows this clip's translation: the game reuses
		# it for "... is dubbing this clip" and clears it between clips.
		label.draw.connect(func() -> void: original.visible = label.text != "" and label.text == original.get_meta("for", ""))
	label.text = translated if translated != "" else clip.clip_caption
	original.text = _caption(clip) if translated != "" else ""
	original.set_meta("for", translated)
	if translated == "":
		label.remove_theme_stylebox_override("normal")
		return
	var font := original.get_theme_font("font")
	var size := original.get_theme_font_size("font_size")
	var height := minf(font.get_multiline_string_size(original.text, HORIZONTAL_ALIGNMENT_CENTER, label.size.x, size).y, 3 * font.get_height(size))
	var room := StyleBoxEmpty.new()
	room.content_margin_bottom = height + 4  # the translation centers in the space above the original
	label.add_theme_stylebox_override("normal", room)


# --- Pack page ---

## Adds (or updates) the Translation button next to Start on the Dub Mode pack page.
static func add_button(start: Control, pack: PackInfo, clips: Array) -> void:
	var row := start.get_parent()
	var button: Control = row.get_node_or_null("BtnTranslation")
	if button == null:
		button = BUTTON.new()
		button.name = "BtnTranslation"
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(button)
		row.move_child(button, start.get_index() + 1)
		button.pressed.connect(func() -> void: open(button))
	button.set_meta("pack", pack)
	button.set_meta("clips", clips)
	button.text = _button_text(pack)
	button.disabled = _lines(clips, pack).is_empty()


static func _button_text(pack: PackInfo) -> String:
	return "Translation: " + chosen(pack) if chosen(pack) != "" else "Translation"


## The Translation window: pick which translation Dub Mode shows, export, import, remove.
static func open(button: Control) -> Control:
	var pack: PackInfo = button.get_meta("pack")
	var clips: Array = button.get_meta("clips")
	var layer := CanvasLayer.new()
	layer.layer = 140
	button.add_child(layer)
	var modal := Control.new()
	modal.theme = STYLE.make_theme()
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		modal.theme.set_color(state, "Label", Color.WHITE)
		modal.theme.set_color(state, "CheckBox", Color.WHITE)
	modal.theme.set_icon("radio_unchecked", "CheckBox", _radio(false))
	modal.theme.set_icon("radio_checked", "CheckBox", _radio(true))
	modal.size = button.get_viewport().get_visible_rect().size
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(modal)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.8)
	modal.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	modal.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	panel.custom_minimum_size.x = 640
	var fill := Panel.new()  # the panel art is see-through; keep the page behind it out of the way
	fill.add_theme_stylebox_override("panel", STYLE.box(Color("151719"), Color("151719"), 10))
	fill.show_behind_parent = true
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(fill)
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	STYLE.dark_panel(panel)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var title := Label.new()
	title.text = "TRANSLATION"
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = pack.display_name
	subtitle.modulate = Color(1, 1, 1, 0.7)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)
	column.add_child(HSeparator.new())

	var list := VBoxContainer.new()
	list.name = "List"
	list.add_theme_constant_override("separation", 6)
	column.add_child(list)
	var message := Label.new()
	message.name = "Message"
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_color_override("font_color", Color("ffd36a"))
	column.add_child(message)
	var refresh := func() -> void: _fill(list, button)
	refresh.call()

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)
	var export := BUTTON.new()
	export.text = "Export script"
	buttons.add_child(export)
	var import := BUTTON.new()
	import.text = "Import translation"
	buttons.add_child(import)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	var close := BUTTON.new()
	close.text = "Close"
	buttons.add_child(close)

	close.pressed.connect(func() -> void:
		button.text = _button_text(pack)
		layer.queue_free())
	export.pressed.connect(func() -> void:
		var name := (pack.display_name + " script.txt").validate_filename()
		_pick(modal, FileDialog.FILE_MODE_SAVE_FILE, name, _export.bind(message, pack, clips)))
	import.pressed.connect(func() -> void:
		_pick(modal, FileDialog.FILE_MODE_OPEN_FILE, "", _import.bind(message, refresh, pack, clips)))
	close.grab_focus.call_deferred()
	return modal


## A white ring, with a dot when picked: the default ones vanish on the dark panel.
static func _radio(picked: bool) -> ImageTexture:
	var image := Image.create_empty(22, 22, false, Image.FORMAT_RGBA8)
	for x: int in 22:
		for y: int in 22:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(11, 11))
			var a := clampf(1.5 - absf(d - 9.0), 0.0, 1.0) + (clampf(5.5 - d, 0.0, 1.0) if picked else 0.0)
			image.set_pixel(x, y, Color(1, 1, 1, minf(a, 1.0)))
	return ImageTexture.create_from_image(image)


## One row per translation plus "Original captions"; picking one is saved right away.
static func _fill(list: VBoxContainer, button: Control) -> void:
	var pack: PackInfo = button.get_meta("pack")
	var clips: Array = button.get_meta("clips")
	for child: Node in list.get_children(): child.queue_free()
	var group := ButtonGroup.new()
	var total := _lines(clips, pack).size()
	var current := chosen(pack)
	for name: String in [""] + Array(names(pack)):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		list.add_child(row)
		var pick := CheckBox.new()
		pick.button_group = group
		pick.text = name if name != "" else "Original captions"
		pick.button_pressed = name == current
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.toggled.connect(func(on: bool) -> void: if on: choose(pack, name))
		row.add_child(pick)
		if name == "": continue
		var count := Label.new()
		count.text = "%d of %d lines" % [captions(pack, name).size(), total]
		count.modulate = Color(1, 1, 1, 0.7)
		row.add_child(count)
		var drop := BUTTON.new()
		drop.use_small()
		drop.text = "Remove"
		drop.pressed.connect(func() -> void:
			remove(pack, name)
			_fill(list, button))
		row.add_child(drop)


static func _export(path: String, message: Label, pack: PackInfo, clips: Array) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		message.text = "Couldn't save there. Try another folder."
		return
	file.store_string(script_text(clips, pack))
	file.close()
	message.text = "Saved %s. Translate the captions, then import it here." % path.get_file()


static func _import(path: String, message: Label, refresh: Callable, pack: PackInfo, clips: Array) -> void:
	var name := name_from(path, pack)
	var count := import_text(FileAccess.get_file_as_string(path), clips, pack, name)
	if count == 0: message.text = "No translated captions for this pack in %s." % path.get_file()
	else: message.text = "Imported %s. Dub Mode now shows it." % name
	refresh.call()


static func _pick(parent: Node, mode: FileDialog.FileMode, file_name: String, done: Callable) -> void:
	var picker := FileDialog.new()
	picker.file_mode = mode
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.use_native_dialog = true
	picker.filters = PackedStringArray(["*.txt ; Text files"])
	picker.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if file_name != "": picker.current_file = file_name
	picker.file_selected.connect(func(path: String) -> void: picker.queue_free(); done.call(path))
	picker.canceled.connect(picker.queue_free)
	parent.add_child(picker)
	picker.popup_centered_ratio(0.6)
