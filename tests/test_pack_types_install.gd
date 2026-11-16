extends SceneTree
## Installs real GameBanana archives through the browser's installer into this
## project's game folder, checks each pack lands in the folder for its type and
## shows up on the Customize page, then uninstalls them.
## Usage: Godot --headless --path <patched-game> --script res://test_tmp/test_pack_types_install.gd -- type=/path/pack.zip ...
## type is what the archive must install: menu, player, judges, host, studio, voice, dub, or several joined by +.
## none means the archive must be refused.
func _initialize(): call_deferred("check")

func check():
	var installer: GDScript = load("res://net/community_pack_installer.gd")
	var roots: Dictionary = installer.type_roots()
	var customize: Node = load("res://scene/menu/customize/menu_customize.tscn").instantiate()
	root.add_child(customize)
	await process_frame
	var personalizers: Dictionary = {"menu": M.PERSONALIZER.MENU, "player": M.PERSONALIZER.CONTESTANT,
		"studio": M.PERSONALIZER.STUDIO, "judges": M.PERSONALIZER.JUDGES, "host": M.PERSONALIZER.HOST}
	var failures: int = 0
	var mod_id: int = 990000
	DirAccess.make_dir_recursive_absolute(installer.DOWNLOAD_ROOT)
	for arg: String in OS.get_cmdline_user_args():
		mod_id += 1
		var want: PackedStringArray = arg.get_slice("=", 0).split("+")
		var source: String = arg.substr(arg.find("=") + 1)
		var ext: String = source.get_extension().to_lower()
		var archive: String = installer.DOWNLOAD_ROOT.path_join("%d.%s.part" % [mod_id, ext])
		DirAccess.copy_absolute(source, ProjectSettings.globalize_path(archive))
		var result: Dictionary = installer._validate_and_extract(archive,
			{"id": mod_id, "name": source.get_file().get_basename(), "author": "test"},
			{"id": mod_id, "name": source.get_file(), "md5": FileAccess.get_md5(archive)}, roots, true)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(archive))
		if result.has("error") or want[0] == "none":
			if want[0] != "none" or not result.has("error"):
				failures += 1
				print("FAIL %s: %s" % [source.get_file(), result.get("error", "should have been refused")])
			else: print("OK  %s refused: %s" % [source.get_file(), result["error"]])
			continue
		var got: Dictionary = {}
		var lines: PackedStringArray = []
		for pack: Dictionary in result["packs"]:
			var type: String = pack["type"]
			var path: String = pack["path"]
			got[type] = true
			if path.get_base_dir() != str(roots[type]):
				print("FAIL %s: %s pack went to %s" % [source.get_file(), type, path])
				failures += 1
			var shown: String = "folder"
			if personalizers.has(type):
				customize.setup_tree_from(personalizers[type])
				shown = "missing from Customize"
				var item: TreeItem = customize.tree.get_root().get_first_child()
				while item != null:
					if item.get_text(0) == path.get_file(): shown = "in Customize"
					if item.get_text(0).begins_with("."):
						print("FAIL %s: Customize lists %s" % [source.get_file(), item.get_text(0)])
						failures += 1
					item = item.get_next()
				if shown != "in Customize": failures += 1
			lines.append("%s %s (%d files, %s)" % [type, path.get_base_dir().get_file().path_join(path.get_file()),
				DirAccess.get_files_at(path).size(), shown])
		for type: String in want:
			if not got.has(type):
				print("FAIL %s: no %s pack installed, got %s" % [source.get_file(), type, got.keys()])
				failures += 1
		print("%s %s -> %d packs\n    %s" % ["OK " if failures == 0 else "...", source.get_file(), result["packs"].size(), "\n    ".join(lines)])
		var removed: Dictionary = installer.uninstall(mod_id)
		if removed.has("error") or not installer.installed_paths(mod_id).is_empty():
			print("FAIL %s: uninstall %s" % [source.get_file(), removed])
			failures += 1
	print("PACK TYPES | %d failure(s)" % failures)
	quit()
