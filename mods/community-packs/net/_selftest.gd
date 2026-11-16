extends Node
# dev tool, not shipped. register as the last autoload to compile every .gd.

class QueueTestNet:
	extends Node
	var online: bool = true
	func is_online() -> bool: return online
	func community_pack_library_changed() -> void: pass

class QueueTestInstaller:
	extends Node
	signal failed(message: String)
	var busy: bool = false
	func is_busy() -> bool: return busy
	func cancel() -> void:
		busy = false
		failed.emit("Download canceled.")
	func install(_mod: Dictionary, _file: Dictionary) -> void:
		busy = true

func _ready() -> void:
	var failures: Array[String] = []
	var total: int = 0
	var stack: Array[String] = ["res://"]

	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		for d: String in DirAccess.get_directories_at(dir_path):
			if d.begins_with("."):
				continue
			stack.append(dir_path.path_join(d))
		for f: String in DirAccess.get_files_at(dir_path):
			if not f.ends_with(".gd"):
				continue
			var p: String = dir_path.path_join(f)
			total += 1
			if load(p) == null:
				failures.append(p)

	print("SELFTEST | compiled %d scripts" % total)
	_run_community_pack_tests(failures)
	_run_download_queue_tests(failures)
	for f: String in failures:
		print("SELFTEST FAIL | %s" % f)
	print("SELFTEST | %d failure(s)" % failures.size())
	get_tree().quit()


func _run_community_pack_tests(failures: Array[String]) -> void:
	var client: Script = load("res://net/gamebanana_client.gd")
	var installer: Script = load("res://net/community_pack_installer.gd")
	if client == null or installer == null:
		failures.append("community pack services did not compile")
		return

	var catalog_json: String = JSON.stringify({
		"_aMetadata": {"_nRecordCount": 2, "_bIsComplete": true},
		"_aRecords": [
			{"_idRow": 10, "_sName": "Dub pack", "_aRootCategory": {"_sName": "Dub Mode"}},
			{"_idRow": 11, "_sName": "Wrong category", "_aRootCategory": {"_sName": "Audio"}},
		],
	})
	var page: Dictionary = client.parse_page_json(catalog_json, 3, "Dub Mode")
	if int(page.get("page", 0)) != 3 or Array(page.get("records", [])).size() != 1:
		failures.append("GameBanana catalog normalization/category filtering")
	if Array(client.parse_page_json(catalog_json, 1, "").get("records", [])).size() != 2:
		failures.append("All pack types should keep every category")
	if (not client.build_page_url(1, "Generic_Newest", 0).contains("Generic_Game%5D=20674")
		or not client.build_page_url(1, "Generic_Newest", 32135).contains("Generic_Category%5D=32135")):
		failures.append("GameBanana category filter URL")
	var search_url: String = client.build_search_url("movie night", 2)
	if (search_url.contains("%%")
		or not search_url.contains("_sSearchString=movie%20night")
		or not search_url.contains("_csvFields=name%2Cdescription%2Cowner%2Ccredits")
		or not search_url.ends_with("_nPage=2")):
		failures.append("GameBanana search URL encoding")
	var api_error: String = client._http_error_message(400, JSON.stringify({
		"_sErrorCode": "INPUT_ERRORS",
		"_aErrorData": {"_sSearchString": {"_sErrorMessage": "Must be 2 characters or more"}},
	}))
	if not api_error.contains("Must be 2 characters or more"):
		failures.append("GameBanana API error details")

	var detail_json: String = JSON.stringify({
		"_idRow": 10,
		"_sName": "Dub pack",
		"_sText": "A <b>safe</b> description",
		"_aFiles": [{
			"_idRow": 99,
			"_sFile": "dub-pack.zip",
			"_sDownloadUrl": "https://gamebanana.com/dl/99",
			"_nFilesize": 1024,
			"_sMd5Checksum": "0123456789abcdef0123456789abcdef",
			"_sAnalysisState": "done",
			"_sAnalysisResult": "ok",
			"_sAvState": "done",
			"_sAvResult": "clean",
		}],
	})
	var detail: Dictionary = client.parse_detail_json(detail_json)
	var detail_files: Array = detail.get("files", [])
	if detail_files.size() != 1 or str(detail.get("description", "")) != "A safe description":
		failures.append("GameBanana detail/file normalization")
	elif not installer.installability_problem(detail_files[0]).is_empty():
		failures.append("clean GameBanana ZIP was not installable")
	if installer.installability_problem({"name": "pack.rar"}).contains("RAR"):
		failures.append("RAR archives should be accepted")
	if installer.installability_problem({"name": "pack.7z"}).contains("7z"):
		failures.append("7z archives should be accepted")
	if not installer.installability_problem({"name": "pack.tar.xz"}).contains("ZIP, RAR or 7z"):
		failures.append("unsupported archive guidance")
	var long_name: String = "A".repeat(100) + ".rar"
	var compact: String = load("res://net/community_pack_browser.gd")._compact_text(long_name, 40)
	if compact.length() > 40 or not compact.ends_with(".rar") or not compact.contains("…"):
		failures.append("community browser long-name compaction")

	for pair: Array in [["TvTime(Music & 2D sprites)", "TvTime(Music & 2D sprites)"],
			["Versão Brasileira", "Versão Brasileira"], ["a/b:c?", "a b c"], ["..", "Selftest"],
			["con", "con pack"], ["Flowery Player! ", "Flowery Player!"]]:
		if installer._clean_folder_name(pair[0], "Selftest") != pair[1]:
			failures.append("folder name %s became %s" % [pair[0], installer._clean_folder_name(pair[0], "Selftest")])
	for unsafe: String in ["../outside.wav", "/absolute.wav", "C:/drive.wav", "ok/../outside.wav"]:
		if installer._safe_relative_path(unsafe):
			failures.append("unsafe archive path accepted: %s" % unsafe)

	var zip_path: String = "user://community-pack-selftest.zip"
	if FileAccess.file_exists(zip_path): DirAccess.remove_absolute(zip_path)
	var packer: = ZIPPacker.new()
	var zip_error: Error = packer.open(zip_path)
	if zip_error == OK:
		# a creator's source video and something worse ride along: both must be
		# left out, and the pack must still install.
		for path: String in ["wrapper/dub_video.ogv", "wrapper/line.wav", "wrapper/line.ini",
				"wrapper/original video.mp4", "wrapper/run me.exe"]:
			packer.start_file(path)
			packer.write_file(PackedByteArray([1, 2, 3]))
			packer.close_file()
		packer.close()
		var indexed: Dictionary = installer.inspect_zip(zip_path)
		var entries: Array = indexed.get("entries", [])
		if indexed.has("error") or entries.size() != 5:
			failures.append("valid ZIP central directory inspection")
		else:
			var typed_entries: Array[Dictionary] = []
			for value: Variant in entries:
				if value is Dictionary: typed_entries.append(value)
			if installer._find_dub_root(typed_entries) != "wrapper":
				failures.append("dub root detection")
			var test_root: String = "user://community-pack-selftest-packs"
			var result: Dictionary = installer._validate_and_extract(
				zip_path,
				{"id": 2147483646, "name": "Selftest pack", "author": "Selftest"},
				{"id": 123, "name": "fixture.zip", "md5": FileAccess.get_md5(zip_path)},
				test_root,
				false)
			if result.has("error"):
				failures.append("validated ZIP extraction: %s" % str(result["error"]))
			else:
				var installed: String = str(result.get("path", ""))
				if (installed.get_base_dir() != test_root.path_join("packs_voice")
					or not FileAccess.file_exists(installed.path_join("dub_video.ogv"))):
					failures.append("validated ZIP was not moved into packs_voice")
				if (FileAccess.file_exists(installed.path_join("original video.mp4"))
					or FileAccess.file_exists(installed.path_join("run me.exe"))):
					failures.append("file types the game doesn't use were written to disk")
			_remove_test_root(test_root)
	else:
		failures.append("could not create ZIP self-test fixture")
	if FileAccess.file_exists(zip_path): DirAccess.remove_absolute(zip_path)
	_test_flat_pack_archive(installer, failures)
	_test_pack_types(installer, failures)
	_test_dub_without_video(installer, failures)

	if failures.is_empty(): print("SELFTEST PASS | community catalog and ZIP safety checks")


# a Dub Mode upload that lost its video must fail, not install as a voice pack.
# Afterwards no install may still count as writing to disk.
func _test_dub_without_video(installer: Script, failures: Array[String]) -> void:
	var zip_path: String = "user://community-pack-novideo-selftest.zip"
	var test_root: String = "user://community-pack-novideo-selftest-packs"
	var packer: = ZIPPacker.new()
	if packer.open(zip_path) != OK:
		failures.append("could not create no-video ZIP fixture")
		return
	for path: String in ["pack/line.wav", "pack/line2.wav"]:
		packer.start_file(path)
		packer.write_file(PackedByteArray([7, 8, 9]))
		packer.close_file()
	packer.close()
	var mod: Dictionary = {"id": 2147483640, "name": "No video", "author": "Selftest", "category": "Dub Mode"}
	var file: Dictionary = {"id": 124, "name": "novideo.zip", "md5": FileAccess.get_md5(zip_path)}
	var result: Dictionary = installer._validate_and_extract(zip_path, mod, file, test_root, false)
	if str(result.get("error", "")) != "The archive did not contain a complete dub pack.":
		failures.append("Dub Mode pack without video: %s" % str(result))
	mod["category"] = "Other/Misc"
	result = installer._validate_and_extract(zip_path, mod, file, test_root, false)
	if result.has("error") or str(result["packs"][0]["type"]) != "voice":
		failures.append("loose audio outside Dub Mode should stay a voice pack: %s" % str(result))
	if installer._staging_bytes != 0:
		failures.append("installs left %d bytes counted as in progress" % installer._staging_bytes)
	_remove_test_root(test_root)
	DirAccess.remove_absolute(zip_path)


func _test_flat_pack_archive(installer: Script, failures: Array[String]) -> void:
	var zip_path: String = "user://community-pack-flat-selftest.zip"
	var test_root: String = "user://community-pack-flat-selftest-packs"
	if FileAccess.file_exists(zip_path): DirAccess.remove_absolute(zip_path)
	var packer: = ZIPPacker.new()
	if packer.open(zip_path) != OK:
		failures.append("could not create flat ZIP self-test fixture")
		return
	for path: String in ["dub_video.ogv", "line.wav", "line.ini"]:
		packer.start_file(path)
		packer.write_file(PackedByteArray([4, 5, 6]))
		packer.close_file()
	packer.close()

	var indexed: Dictionary = installer.inspect_zip(zip_path)
	var entries: Array[Dictionary] = []
	for value: Variant in Array(indexed.get("entries", [])):
		if value is Dictionary: entries.append(value)
	if indexed.has("error") or installer._find_dub_root(entries) != "":
		failures.append("flat dub-pack ZIP detection")
	else:
		var result: Dictionary = installer._validate_and_extract(
			zip_path,
			{"id": 2147483645, "name": "Flat selftest pack", "author": "Selftest"},
			{"id": 124, "name": "flat-fixture.zip", "md5": FileAccess.get_md5(zip_path)},
			test_root,
			false)
		if result.has("error"):
			failures.append("flat ZIP installation: %s" % str(result["error"]))
		else:
			var installed: String = str(result.get("path", ""))
			var voice_root: String = test_root.path_join("packs_voice")
			if (installed.get_base_dir() != voice_root
				or not FileAccess.file_exists(installed.path_join("dub_video.ogv"))
				or FileAccess.file_exists(voice_root.path_join("dub_video.ogv"))):
				failures.append("flat ZIP files were not contained in their own pack folder")
			var listed: Array[Dictionary] = installer.installed_packs(test_root)
			if (listed.size() != 1 or str(listed[0].get("path", "")) != installed
				or int(listed[0].get("mod_id", 0)) != 2147483645
				or int(listed[0].get("installed_files", 0)) != 3
				or int(listed[0].get("installed_bytes", 0)) != 9
				or str(listed[0].get("type", "")) != "dub"):
				failures.append("installed community-pack library scan")
			var removed: Dictionary = installer._uninstall_path(
				2147483645, installed, voice_root, false)
			if removed.has("error") or DirAccess.dir_exists_absolute(installed):
				failures.append("guarded community-pack uninstall: %s" % str(removed))
	_remove_test_root(test_root)
	if FileAccess.file_exists(zip_path): DirAccess.remove_absolute(zip_path)


# Every Customize type, laid out the ways real GameBanana archives are.
func _test_pack_types(installer: Script, failures: Array[String]) -> void:
	var cases: Array[Dictionary] = [
		{"what": "menu pack", "files": ["Frutiger/config_menu.json", "Frutiger/background.png",
			"Frutiger/music_menu.ogg", "Frutiger/video.ogv", "Frutiger/model.glb", "note.txt"],
			"want": {"packs_menu/Frutiger": ["config_menu.json", "background.png", "music_menu.ogg", "video.ogv"]},
			"absent": ["packs_menu/Frutiger/model.glb", "packs_menu/note.txt"]},
		{"what": "two players in one archive", "files": ["(SM) Mario/config_player.json",
			"(SM) Mario/player.png", "(SM) Mario/jump.wav", "(SM) Luigi/config_player.json"],
			"want": {"packs_player/(SM) Mario": ["config_player.json", "player.png", "jump.wav"],
				"packs_player/(SM) Luigi": ["config_player.json"]}},
		{"what": "host two folders down", "files": ["CAVEMAN MOD/Caveman/config_host.json",
			"CAVEMAN MOD/Caveman/host.png"],
			"want": {"packs_host/Caveman": ["config_host.json", "host.png"]}},
		{"what": "judges at the archive top", "files": ["config_judges.json", "judge1.png", "scoreblip1.mp3"],
			"want": {"packs_judges/Type selftest": ["config_judges.json", "judge1.png", "scoreblip1.mp3"]}},
		{"what": "studio with its 3D model", "files": ["TV/config_studio.json", "TV/model.glb",
			"TV/screen.ogv", "TV/music_studio.mp3"],
			"want": {"packs_studio/TV": ["config_studio.json", "model.glb", "screen.ogv", "music_studio.mp3"]}},
		{"what": "chatter pack", "files": ["Chat/config_chatter.ini", "Chat/hello.wav"],
			"want": {"packs_chatter/Chat": ["config_chatter.ini", "hello.wav"]}},
		{"what": "voice pack with sub-folders", "files": ["JJK/Gojo/a.mp3", "JJK/Gojo/a.png",
			"JJK/Sukuna/b.mp3", "JJK/b.txt"],
			"want": {"packs_voice/JJK": ["Gojo/a.mp3", "Gojo/a.png", "Sukuna/b.mp3", "b.txt"]}},
		{"what": "compilation laid out like the game folder", "files": [
			"packs_host/Tenna/config_host.json", "packs_voices/Family/clip.mp3",
			"packs_player/Kris/config_player.json", "packs_voice/Movie/dub_video.ogv",
			"packs_voice/Movie/line.wav", "packs_menu/TV Time/config_menu.json", "packs_menu/stray.png",
			"packs_studio/TV/model.glb"],
			"want": {"packs_host/Tenna": ["config_host.json"], "packs_voice/Family": ["clip.mp3"],
				"packs_player/Kris": ["config_player.json"], "packs_voice/Movie [GB-{id}]": ["dub_video.ogv", "line.wav"],
				"packs_menu/TV Time": ["config_menu.json"], "packs_studio/TV": ["model.glb"]},
			"absent": ["packs_menu/stray.png"],
			"types": {"packs_voice/Family": "voice", "packs_voice/Movie [GB-{id}]": "dub", "packs_studio/TV": "studio"}},
		{"what": "code mod", "files": ["mod/net/lobby.gd", "README.md", "Install.bat"],
			"error": "This is a mod for the game itself"},
		{"what": "exe patcher", "files": ["Mod/Install_Mod.bat", "Mod/patch/xdelta3.exe", "Mod/patch/game.xdelta"],
			"error": "This is a mod for the game itself"},
		{"what": "chatter pack without audio", "files": ["Chat/config_chatter.ini", "Chat/readme.txt"],
			"error": "No pack the game can use"},
	]
	var zip_path: String = "user://community-pack-types-selftest.zip"
	var test_root: String = "user://community-pack-types-selftest"
	var mod_id: int = 2147483600
	for case: Dictionary in cases:
		mod_id += 1
		_remove_test_root(test_root)
		if FileAccess.file_exists(zip_path): DirAccess.remove_absolute(zip_path)
		var packer: = ZIPPacker.new()
		if packer.open(zip_path) != OK:
			failures.append("could not create the %s fixture" % case["what"])
			continue
		for path: String in case["files"]:
			packer.start_file(path)
			packer.write_file(PackedByteArray([7, 8, 9]))
			packer.close_file()
		packer.close()
		var result: Dictionary = installer._validate_and_extract(zip_path,
			{"id": mod_id, "name": "Type selftest", "author": "Selftest"},
			{"id": 1, "name": "types.zip", "md5": FileAccess.get_md5(zip_path)}, test_root, false)
		if case.has("error"):
			if not str(result.get("error", "")).contains(str(case["error"])):
				failures.append("%s: wanted an error, got %s" % [case["what"], str(result)])
			continue
		if result.has("error"):
			failures.append("%s: %s" % [case["what"], str(result["error"])])
			continue
		var want: Dictionary = {}  # dub packs carry their GameBanana id
		for folder: String in case["want"]: want[folder.replace("{id}", str(mod_id))] = case["want"][folder]
		if Array(result.get("paths", [])).size() != want.size():
			failures.append("%s: installed %s" % [case["what"], str(result.get("paths", []))])
		for folder: String in want:
			for name: String in want[folder]:
				if not FileAccess.file_exists(test_root.path_join(folder).path_join(name)):
					failures.append("%s: %s/%s is missing" % [case["what"], folder, name])
		for path: String in case.get("absent", []):
			if FileAccess.file_exists(test_root.path_join(path)):
				failures.append("%s: %s should not be installed" % [case["what"], path])
		var listed: Array[Dictionary] = installer.installed_packs(test_root)
		if listed.size() != want.size():
			failures.append("%s: Installed packs lists %d folders" % [case["what"], listed.size()])
		var types: Dictionary = {}
		for folder: String in case.get("types", {}): types[folder.replace("{id}", str(mod_id))] = case["types"][folder]
		for pack: Dictionary in listed:
			var key: String = "%s/%s" % [str(pack.get("root", "")).get_file(), pack.get("folder", "")]
			if types.has(key) and str(pack.get("type", "")) != types[key]:
				failures.append("%s: %s is a %s, wanted %s" % [case["what"], key, pack.get("type", ""), types[key]])
			var removed: Dictionary = installer._uninstall_path(mod_id, str(pack["path"]), str(pack["root"]), false)
			if removed.has("error"): failures.append("%s: uninstall %s" % [case["what"], str(removed)])
		if not installer.installed_packs(test_root).is_empty():
			failures.append("%s: uninstall left folders behind" % case["what"])
	_remove_test_root(test_root)
	if FileAccess.file_exists(zip_path): DirAccess.remove_absolute(zip_path)


# a stand-in game folder: its packs_* folders, their staging folders, then itself.
func _remove_test_root(test_root: String) -> void:
	if not DirAccess.dir_exists_absolute(test_root): return
	var dir: DirAccess = DirAccess.open(test_root)
	dir.include_hidden = true
	for child: String in dir.get_directories(): _remove_test_tree(test_root.path_join(child), test_root)
	for child: String in dir.get_files(): DirAccess.remove_absolute(test_root.path_join(child))
	DirAccess.remove_absolute(test_root)


func _remove_test_tree(path: String, allowed_root: String) -> void:
	var prefix: String = allowed_root.trim_suffix("/") + "/"
	if (path.is_empty() or not path.begins_with(prefix)
		or not DirAccess.dir_exists_absolute(path)):
		return
	var dir: DirAccess = DirAccess.open(path)
	if dir == null: return
	dir.include_hidden = true
	for child: String in dir.get_directories():
		_remove_test_tree(path.path_join(child), allowed_root)
	for child: String in dir.get_files(): DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)


func _run_download_queue_tests(failures: Array[String]) -> void:
	var queue_script: Script = load("res://net/community_pack_queue.gd")
	if queue_script == null:
		failures.append("community download queue did not compile")
		return
	var fake_net: = QueueTestNet.new()
	var queue: Node = queue_script.new()
	add_child(fake_net)
	queue.configure(fake_net)
	add_child(queue)
	queue.set_allow_online_downloads(false)
	var mod: Dictionary = {"id": 42, "name": "Queue test"}
	var invalid_file: Dictionary = {"id": 7, "name": "not-a-zip.rar", "size": 100}
	var id: String = queue.enqueue(mod, invalid_file)
	if str(queue.get_job(id).get("state", "")) != "queued":
		failures.append("download queue did not retain an online job")
	queue.cancel(id)
	if str(queue.get_job(id).get("state", "")) != "canceled":
		failures.append("queued download cancellation")
	queue.retry(id)
	if str(queue.get_job(id).get("state", "")) != "queued":
		failures.append("canceled download retry")
	var real_pool: Array[Node] = queue.get("_pool")
	var fake_installer: = QueueTestInstaller.new()
	fake_installer.failed.connect(Callable(queue, "_on_failed").bind(fake_installer))
	queue.add_child(fake_installer)
	var one_fake: Array[Node] = [fake_installer]
	queue.set("_pool", one_fake)
	queue.get("_active")[fake_installer] = id
	var jobs: Array = queue.get("_jobs")
	jobs[0]["state"] = "downloading"
	fake_installer.busy = true
	queue.cancel(id)
	if (str(queue.get_job(id).get("state", "")) != "canceled"
		or queue.active_count() != 0):
		failures.append("active download cancellation did not release the queue")
	queue.dismiss(id)
	if not queue.get_job(id).is_empty(): failures.append("terminal download dismissal")
	fake_installer.queue_free()

	# three at once, the fourth waits its turn
	var fakes: Array[Node] = []
	for slot: int in 3:
		var fake: = QueueTestInstaller.new()
		queue.add_child(fake)
		fakes.append(fake)
	queue.set("_pool", fakes)
	fake_net.online = false
	var parallel_ids: Array[String] = []
	for n: int in 4:
		parallel_ids.append(queue.enqueue({"id": 60 + n, "name": "Parallel %d" % n}, {"id": 70 + n, "name": "p.zip", "size": 100}))
	queue._pump()
	var states: Array = parallel_ids.map(func(job: String) -> String: return str(queue.get_job(job).get("state", "")))
	if states.count("downloading") != 3 or states.count("queued") != 1:
		failures.append("parallel downloads: wanted 3 downloading and 1 queued, got %s" % str(states))
	queue.set("_active", {})
	for job: String in parallel_ids:
		var jobs_now: Array = queue.get("_jobs")
		for record: Dictionary in jobs_now: if record["id"] == job: record["state"] = "failed"
		queue.dismiss(job)
	for fake: Node in fakes: fake.queue_free()
	fake_net.online = true
	queue.set("_pool", real_pool)

	fake_net.online = false
	var failed_id: String = queue.enqueue({"id": 43, "name": "Bad archive"}, invalid_file)
	queue._pump()
	if (str(queue.get_job(failed_id).get("state", "")) != "failed"
		or queue.active_count() != 0):
		failures.append("failed download did not release the queue")
	queue.dismiss(failed_id)
	fake_net.online = true
	queue.set_allow_online_downloads(true)
	var online_id: String = queue.enqueue(
		{"id": 44, "name": "Online opt-in"},
		{"id": 8, "name": "still-not-a-zip.rar", "size": 100})
	queue._pump()
	if str(queue.get_job(online_id).get("state", "")) != "failed":
		failures.append("online download opt-in did not release a queued job")
	queue.set_allow_online_downloads(false)
	queue.queue_free()
	fake_net.queue_free()
