extends SceneTree
## Pack translations: export a script, import a machine-translated copy, show both
## captions in Dub Mode, and never touch the pack folder.
## Usage: Godot --headless --path <patched-game> --script res://test_tmp/test_translations.gd

var T
const PACK := "user://test_translation_pack/"


func _wav(path: String) -> void:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 8000
	var data := PackedByteArray()
	data.resize(1600)
	wav.data = data
	wav.save_to_wav(path)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)


func _pack_fingerprint() -> String:
	var out := ""
	for dir: String in [PACK]:
		for name: String in DirAccess.get_files_at(dir): out += name + FileAccess.get_md5(dir + name)
	return out


func _initialize() -> void: call_deferred("run")


func run() -> void:
	T = load("res://net/pack_translation.gd")
	DirAccess.make_dir_recursive_absolute(PACK)
	_wav(PACK + "01_intro.wav")
	_write(PACK + "01_intro.ini", "[data]\ncaption=\"Hello there.\\nHow are you?\"\ndub_timestamps=[1.0]\ndub_characters=[\"Clark\"]\n")
	_wav(PACK + "02_reply.wav")
	_write(PACK + "02_reply.ini", "[data]\ncaption=\"You're late | again.\"\ndub_timestamps=[2.0]\ndub_characters=[\"Lois\"]\n")
	_wav(PACK + "03_quiet.wav")
	_write(PACK + "03_quiet.ini", "[data]\ncaption=\"Not translated.\"\ndub_timestamps=[3.0]\ndub_characters=[\"Clark\"]\n")
	_wav(PACK + "05_door.wav")
	_write(PACK + "05_door.txt", "Knock knock.")  # plain-text caption
	_write(PACK + "05_door.ini", "[data]\ndub_timestamps=[4.0]\n")
	var before := _pack_fingerprint()

	var pack = load("res://common/data/pack_info.gd").new(root.get_node("M").CLIP_USES.DUB)
	pack.generate_from_target_pack_folder(ProjectSettings.globalize_path(PACK))
	var collection = load("res://common/data/omni_clip_collection.gd").new()
	collection.generate_from_pack_info(pack, false, false)
	var clips: Array = collection.data
	assert(clips.size() == 4, "loaded %d clips" % clips.size())
	DirAccess.remove_absolute(T.file_for(pack))

	var script: String = T.script_text(clips, pack)
	print(script)
	assert(script.contains("1 | 01_intro.wav | Clark | Hello there.\\nHow are you?\n"))
	assert(script.contains("2 | 02_reply.wav | Lois | You're late | again.\n"))
	assert(script.contains("4 | 05_door.wav |  | Knock knock.\n"))
	print("PASS: export lists every captioned clip with number, file name and character")

	# What a machine translator hands back: header translated, one file name
	# translated too, "\n" spaced out, one line left in English.
	var translated: String = script.replace("# Captions from", "# Tekstitykset kohteesta")
	translated = translated.replace("Hello there.\\nHow are you?", "Hei siellä.\\ nMitä kuuluu?")
	translated = translated.replace("02_reply.wav | Lois | You're late | again.", "02_vastaus.wav | Lois | Myöhässä | taas.")
	translated = translated.replace("Knock knock.", "Koputus.")
	assert(T.import_text("﻿" + translated.replace("\n", "\r\n"), clips, pack) == 3)
	var saved: Dictionary = T.saved(pack)
	assert(saved == {"01_intro.wav": "Hei siellä.\nMitä kuuluu?", "02_reply.wav": "Myöhässä | taas.", "05_door.wav": "Koputus."}, str(saved))
	assert(T.import_text("nothing useful", clips, pack) == 0 and T.saved(pack).size() == 3, "an empty import keeps the old one")
	assert(T.file_for(pack).begins_with("user://translations/test_translation_pack/"), T.file_for(pack))
	assert(_pack_fingerprint() == before, "the pack folder changed")
	print("PASS: import matches by file name, falls back to the number, and leaves the pack alone")

	var label := Label.new()
	label.size = Vector2(800, 120)
	root.add_child(label)
	var by_name := {}
	for clip in clips: by_name[clip.file_name] = clip
	T.show_caption(label, by_name["01_intro.wav"], pack)
	var original: Label = label.get_node("Original")
	assert(label.text == "Hei siellä.\nMitä kuuluu?" and original.text == "Hello there.\nHow are you?")
	assert(label.get_theme_stylebox("normal").content_margin_bottom > 10, "room left for the original")
	await process_frame
	await process_frame
	assert(original.visible)
	label.text = "Clark is dubbing this clip..."
	await process_frame
	await process_frame
	assert(not original.visible, "original hides when the game reuses the label")
	T.show_caption(label, by_name["03_quiet.wav"], pack)
	assert(label.text == "Not translated." and original.text == "")
	assert(not label.has_theme_stylebox_override("normal"))
	print("PASS: Dub Mode shows the translation with the original under it, or just the original")

	var row := HBoxContainer.new()
	var start := Control.new()
	row.add_child(start)
	row.add_child(Control.new())
	root.add_child(row)
	T.add_button(start, pack, clips)
	T.add_button(start, pack, clips)
	assert(row.get_child_count() == 3 and row.get_child(1).name == "BtnTranslation")
	assert(T._status(pack, clips) == "3 of 4 captions translated.")
	print("PASS: one Translation button next to Start")

	DirAccess.remove_absolute(T.file_for(pack))
	for dir: String in [PACK]:
		for name: String in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir + name)
		DirAccess.remove_absolute(dir)
	quit()
