extends RefCounted
## Caption translations for dub packs, kept on this computer in
## user://translations/<pack folder>/translation.txt. Nothing is written into the
## pack folder, so the pack stays the same file for file (online pack checks match).
##
## Script file, one line per captioned clip, sorted by file name:
##   12 | 01_intro.wav | Clark | Hello there.\nHow are you?
## Import matches lines by file name, and by number when a translator mangled the name.

const STYLE := preload("res://net/choicer_style.gd")
const BUTTON := preload("res://net/choicer_button.gd")
const ROOT := "user://translations/"


static func file_for(pack: PackInfo) -> String:
	return ROOT + pack.folder_name.trim_suffix("/").validate_filename() + "/translation.txt"


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


## Translated captions this pack has on this computer, by clip id.
static func saved(pack: PackInfo) -> Dictionary:
	if not FileAccess.file_exists(file_for(pack)): return {}
	return parse(FileAccess.get_file_as_string(file_for(pack)))


## Saves the translated lines of `text` for this pack. Returns how many captions
## it translates; 0 leaves any earlier translation as it was.
static func import_text(text: String, clips: Array, pack: PackInfo) -> int:
	var lines := _lines(clips, pack)
	var ids := PackedStringArray(lines.map(func(line: Array) -> String: return line[0]))
	var found := parse(text, ids)
	var out := "# Translation of \"%s\", imported %s\n\n" % [pack.display_name, Time.get_date_string_from_system()]
	var count := 0
	for i: int in lines.size():
		var caption: String = found.get(lines[i][0], "")
		if caption == "" or caption == _caption(lines[i][1]): continue  # missing or left untranslated
		out += _row(i + 1, lines[i][0], lines[i][1], caption)
		count += 1
	if count == 0: return 0
	DirAccess.make_dir_recursive_absolute(file_for(pack).get_base_dir())
	var file := FileAccess.open(file_for(pack), FileAccess.WRITE)
	if file == null: return 0
	file.store_string(out)
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
		button.text = "Translation"
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(button)
		row.move_child(button, start.get_index() + 1)
		button.pressed.connect(func() -> void: _open(button))
	button.set_meta("pack", pack)
	button.set_meta("clips", clips)
	button.disabled = _lines(clips, pack).is_empty()


static func _status(pack: PackInfo, clips: Array) -> String:
	var count := saved(pack).size()
	if count == 0: return "No translation yet.\nExport the script, translate the captions, then import it here."
	return "%d of %d captions translated." % [count, _lines(clips, pack).size()]


static func _open(button: Control) -> void:
	var pack: PackInfo = button.get_meta("pack")
	var clips: Array = button.get_meta("clips")
	var dialog := AcceptDialog.new()
	dialog.theme = STYLE.dialog_theme()
	dialog.borderless = true  # the window title bar would sit outside the white box
	dialog.ok_button_text = "Close"
	dialog.dialog_text = _status(pack, clips)
	# Each button goes to the left of the ones before it.
	var remove := dialog.add_button("Remove", false, "remove")
	dialog.add_button("Import translation", false, "import")
	dialog.add_button("Export script", false, "export")
	remove.disabled = not FileAccess.file_exists(file_for(pack))
	dialog.custom_action.connect(_on_action.bind(dialog, remove, pack, clips))
	dialog.visibility_changed.connect(func() -> void: if not dialog.visible: dialog.queue_free())
	button.add_child(dialog)
	dialog.popup_centered()


static func _on_action(action: StringName, dialog: AcceptDialog, remove: Button, pack: PackInfo, clips: Array) -> void:
	match action:
		"export":
			var name := (pack.display_name + " script.txt").validate_filename()
			_pick(dialog, FileDialog.FILE_MODE_SAVE_FILE, name, _export.bind(dialog, pack, clips))
		"import":
			_pick(dialog, FileDialog.FILE_MODE_OPEN_FILE, "", _import.bind(dialog, remove, pack, clips))
		"remove":
			DirAccess.remove_absolute(file_for(pack))
			remove.disabled = true
			dialog.dialog_text = "Translation removed. Dub Mode shows the original captions again."


static func _export(path: String, dialog: AcceptDialog, pack: PackInfo, clips: Array) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		dialog.dialog_text = "Couldn't save there. Try another folder."
		return
	file.store_string(script_text(clips, pack))
	file.close()
	dialog.dialog_text = "Saved %s.\nTranslate the captions, then come back and import it." % path.get_file()


static func _import(path: String, dialog: AcceptDialog, remove: Button, pack: PackInfo, clips: Array) -> void:
	var count := import_text(FileAccess.get_file_as_string(path), clips, pack)
	if count == 0: dialog.dialog_text = "No translated captions for this pack in %s." % path.get_file()
	else: dialog.dialog_text = "Imported. " + _status(pack, clips)
	remove.disabled = not FileAccess.file_exists(file_for(pack))


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
