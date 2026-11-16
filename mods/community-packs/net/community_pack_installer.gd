extends Node
# Downloads a GameBanana ZIP into a private staging area, validates its central
# directory before allocating decompressed data, extracts only inert pack
# assets, and moves each complete pack folder into its packs_* folder in one rename.

signal progress(received: int, total: int, status: String)
signal finished(result: Dictionary)
signal failed(message: String)

const DOWNLOAD_ROOT: String = "user://community_pack_downloads"
const REGISTRY_PATH: String = "user://community_pack_registry.json"
const MANIFEST_NAME: String = ".tcv-community-pack.json"
const NO_DUB_ROOT: String = "::missing-dub-root::"

const MAX_ARCHIVE_BYTES: int = 1024 * 1024 * 1024
const MAX_EXPANDED_BYTES: int = 4 * 1024 * 1024 * 1024
const MAX_FILE_BYTES: int = 768 * 1024 * 1024
const MAX_FILES: int = 4096
const FREE_SPACE_MARGIN: int = 256 * 1024 * 1024

const SAFE_EXTENSIONS: PackedStringArray = [
	"wav", "mp3", "ogg", "ogv",
	"ini", "cfg", "json", "txt", "md",
	"png", "jpg", "jpeg", "webp", "bmp",
]
const AUDIO_EXTENSIONS: PackedStringArray = ["wav", "mp3", "ogg"]

const STALL_TIMEOUT_MS: int = 60000
const MAX_REDIRECTS: int = 5

var _busy: bool = false
var _mod: Dictionary = {}
var _file: Dictionary = {}
var _download_path: String = ""

# The download runs on its own thread so its speed no longer depends on the frame
# rate (HTTPRequest without threads read ~16 KB per frame: 4.5 MB/s at 60 fps
# against 16 MB/s for curl). The client is non-blocking and checks _cancel_requested
# every pass, so cancel() never waits on a stalled server.
# ponytail: plain int/bool shared with the worker, written by one side each; add a
# Mutex if more state is ever shared.
var _thread: Thread
var _cancel_requested: bool = false
var _received: int = 0


func _ready() -> void:
	set_process(false)
	# Downloads never resume across launches, so an old partial file is a leftover.
	# Only files untouched for 10 minutes: a second running copy of the game (local
	# multiplayer testing) may be writing a fresh one right now.
	var now: int = int(Time.get_unix_time_from_system())
	if not DirAccess.dir_exists_absolute(DOWNLOAD_ROOT): return  # first launch: nothing to clean
	for leftover: String in DirAccess.get_files_at(DOWNLOAD_ROOT):
		var path: String = DOWNLOAD_ROOT.path_join(leftover)
		if (leftover.ends_with(".part") or leftover.ends_with(".converted.zip")) \
			and now - FileAccess.get_modified_time(path) > 600:
			DirAccess.remove_absolute(path)


func _process(_delta: float) -> void:
	if _thread != null and not _thread.is_alive():
		var outcome: Variant = _thread.wait_to_finish()
		_thread = null
		if not _busy:  # canceled: the partial file is ours to delete now the worker is gone
			_cleanup_download()
			set_process(false)
			return
		var result: Dictionary = outcome if outcome is Dictionary else {"error": "The download stopped unexpectedly."}
		if result.has("error"):
			_fail(str(result["error"]))
			return
		set_process(false)
		_finish_download()
		return
	if _busy: progress.emit(_received, int(_file.get("size", 0)), "Downloading from GameBanana...")


func is_busy() -> bool:
	return _busy


func cancel() -> void:
	if not _busy: return
	_cancel_requested = true
	_busy = false
	# _process joins the worker (it exits within a millisecond) and deletes the partial file.
	set_process(true)
	failed.emit("Download canceled.")


func _join_worker() -> void:
	if _thread == null: return
	_cancel_requested = true
	_thread.wait_to_finish()
	_thread = null
	_cleanup_download()


func _start_download(url: String, path: String) -> Error:
	_join_worker()
	_download_path = path
	_cancel_requested = false
	_received = 0
	_busy = true
	_thread = Thread.new()
	var error: Error = _thread.start(_download_worker.bind(url, ProjectSettings.globalize_path(path), MAX_ARCHIVE_BYTES, int(_file.get("size", 0))))
	if error != OK:
		_thread = null
		return error
	set_process(true)
	return OK


static func _split_url(url: String) -> Dictionary:
	var tls: bool = url.begins_with("https://")
	if not tls and not url.begins_with("http://"): return {}
	var scheme: String = "https://" if tls else "http://"
	var rest: String = url.substr(scheme.length())
	var slash: int = rest.find("/")
	var authority: String = rest if slash < 0 else rest.substr(0, slash)
	var path: String = "/" if slash < 0 else rest.substr(slash)
	var host: String = authority
	var port: int = 443 if tls else 80
	var colon: int = authority.rfind(":")
	if colon > 0:
		port = authority.substr(colon + 1).to_int()
		host = authority.substr(0, colon)
	if host.is_empty() or port <= 0: return {}
	return {"tls": tls, "host": host, "port": port, "path": path, "origin": scheme + authority}


# GameBanana's /dl link redirects to a random mirror, and some mirrors are slow:
# filecache35 served ~0.6 MB/s while filecache20 served 15-18 MB/s for the same
# file. If a connection is slow after a few seconds, ask /dl again for another
# mirror and resume where it stopped (the mirrors accept byte ranges).
const SLOW_MIRROR_BYTES_PER_SECOND: int = 2 * 1024 * 1024
const MIRROR_PROBE_MS: int = 3000
const MAX_MIRROR_SWITCHES: int = 8
const MIN_REMAINING_TO_SWITCH: int = 3 * 1024 * 1024


# Runs on the worker thread. Returns {} on success or {"error": message}.
func _download_worker(url: String, path: String, limit: int, total: int = 0) -> Dictionary:
	var out: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if out == null: return {"error": "Could not write the download file."}
	var switches: int = 0
	# some files live on one mirror only, and /dl keeps sending us back to it.
	# a mirror that was already slow once is kept the second time.
	var slow_hosts: Dictionary = {}
	while true:
		var result: Dictionary = _download_attempt(url, out, limit, total, switches < MAX_MIRROR_SWITCHES, slow_hosts)
		if result.get("switch_mirror", false):
			switches += 1
			slow_hosts[str(result.get("host", ""))] = true
			continue
		out.close()
		return result
	return {}


func _download_attempt(url: String, out: FileAccess, limit: int, total: int, may_switch: bool, slow_hosts: Dictionary = {}) -> Dictionary:
	var headers: PackedStringArray = [
		"Accept: application/octet-stream",
		"User-Agent: TCV-Multiplayer/%s" % str(CommunityPacks.VERSION),
	]
	if _received > 0: headers.append("Range: bytes=%d-" % _received)  # resume on the new mirror
	var body_started: int = -1
	var connection_bytes: int = 0
	var probed: bool = false
	for _hop: int in MAX_REDIRECTS + 1:
		var target: Dictionary = _split_url(url)
		if target.is_empty(): return {"error": "The download URL is not valid."}
		var client: = HTTPClient.new()
		client.blocking_mode_enabled = false
		client.read_chunk_size = 256 * 1024
		var tls: TLSOptions = TLSOptions.client() if target["tls"] else null
		if client.connect_to_host(target["host"], target["port"], tls) != OK:
			return {"error": "Could not connect to GameBanana."}
		var requested: bool = false
		var checked: bool = false
		var last_activity: int = Time.get_ticks_msec()
		while true:
			if _cancel_requested:
				client.close()
				return {"canceled": true}
			if Time.get_ticks_msec() - last_activity > STALL_TIMEOUT_MS:
				client.close()
				return {"error": "The download stalled for a minute and was stopped."}
			client.poll()
			var status: int = client.get_status()
			if status in [HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CANT_CONNECT,
				HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR]:
				return {"error": "The connection to GameBanana failed (status %d)." % status}
			if status == HTTPClient.STATUS_CONNECTED and not requested:
				if client.request(HTTPClient.METHOD_GET, target["path"], headers) != OK:
					return {"error": "Could not send the download request."}
				requested = true
				continue
			if requested and not checked and client.has_response():
				checked = true
				var code: int = client.get_response_code()
				if code in [301, 302, 303, 307, 308]:
					var location: String = ""
					var response_headers: Dictionary = client.get_response_headers_as_dictionary()
					for key: Variant in response_headers:
						if str(key).to_lower() == "location": location = str(response_headers[key])
					client.close()
					if location.is_empty(): return {"error": "GameBanana sent a redirect without a target."}
					url = location if location.contains("://") else str(target["origin"]) + location
					break
				if code < 200 or code >= 300:
					client.close()
					return {"error": "GameBanana returned HTTP %d for the archive." % code}
				if code == 200 and _received > 0:  # this mirror ignored the range: start over
					out.seek(0)
					_received = 0
			if status == HTTPClient.STATUS_BODY:
				if body_started < 0: body_started = Time.get_ticks_msec()
				var chunk: PackedByteArray = client.read_response_body_chunk()
				if chunk.is_empty():
					OS.delay_usec(1000)
				else:
					out.store_buffer(chunk)
					_received += chunk.size()
					connection_bytes += chunk.size()
					last_activity = Time.get_ticks_msec()
					if _received > limit:
						client.close()
						return {"error": "This archive is larger than the 1 GB safety limit."}
				var elapsed: int = Time.get_ticks_msec() - body_started
				if may_switch and not probed and elapsed >= MIRROR_PROBE_MS:
					probed = true
					var remaining: int = (total - _received) if total > 0 else limit
					var speed: int = connection_bytes * 1000 / elapsed
					var slow: bool = speed < SLOW_MIRROR_BYTES_PER_SECOND and remaining > MIN_REMAINING_TO_SWITCH
					var again: bool = slow_hosts.has(target["host"])
					print("Community pack download: %s at %.1f MB/s%s" % [target["host"], speed / 1e6,
						", trying another mirror" if slow and not again else ", keeping it, it's the one GameBanana keeps giving" if slow else ""])
					if slow and not again:
						client.close()
						return {"switch_mirror": true, "host": target["host"]}
				continue
			if checked and status in [HTTPClient.STATUS_CONNECTED, HTTPClient.STATUS_DISCONNECTED]:
				client.close()
				return {}
			OS.delay_usec(1000)
	return {"error": "GameBanana redirected too many times."}


func install(mod: Dictionary, file: Dictionary) -> void:
	if _busy: return
	var problem: String = installability_problem(file)
	if not problem.is_empty():
		failed.emit(problem)
		return
	var existing: String = installed_path(int(mod.get("id", 0)))
	if not existing.is_empty():
		finished.emit({"path": existing, "already_installed": true})
		return
	_mod = mod.duplicate(true)
	_file = file.duplicate(true)
	if DirAccess.make_dir_recursive_absolute(DOWNLOAD_ROOT) != OK:
		failed.emit("Could not create the community-pack download folder.")
		return
	_join_worker()
	var path: String = DOWNLOAD_ROOT.path_join("%d.%s.part" % [int(file["id"]), str(file.get("name", "")).get_extension().to_lower()])
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	progress.emit(0, int(file.get("size", 0)), "Connecting to GameBanana...")
	var error: Error = _start_download(str(file["url"]), path)
	if error != OK:
		_fail("Could not start the download (%s)." % error_string(error))


static func installability_problem(file: Dictionary) -> String:
	var name: String = str(file.get("name", ""))
	var extension: String = name.get_extension().to_lower()
	if extension not in ["zip", "rar", "7z"]:
		return "This file isn't a ZIP, RAR or 7z archive, so it can't be installed from here."
	var size: int = int(file.get("size", 0))
	if size <= 0: return "GameBanana did not report a valid file size."
	if size > MAX_ARCHIVE_BYTES: return "This archive is larger than the 1 GB safety limit."
	var url: String = str(file.get("url", ""))
	if not url.begins_with("https://gamebanana.com/dl/"):
		return "The download URL did not come from GameBanana."
	var md5: String = str(file.get("md5", "")).to_lower()
	if md5.length() != 32 or not _is_hex(md5):
		return "GameBanana did not provide a usable checksum for this file."
	if str(file.get("analysis_state", "")) != "done" or str(file.get("analysis_result", "")) != "ok":
		return "GameBanana has not finished approving this archive."
	if str(file.get("av_state", "")) != "done" or str(file.get("av_result", "")) != "clean":
		return "GameBanana has not marked this archive clean."
	if bool(file.get("archived", false)): return "This GameBanana file has been archived."
	return ""


func _finish_download() -> void:
	if not _busy: return
	var expected_size: int = int(_file.get("size", 0))
	var actual_size: int = _file_size(_download_path)
	if actual_size != expected_size:
		_fail("The archive was incomplete: expected %s, received %s." % [
			_format_bytes(expected_size), _format_bytes(actual_size)])
		return
	progress.emit(actual_size, expected_size, "Verifying the archive checksum...")
	var actual_md5: String = FileAccess.get_md5(_download_path).to_lower()
	if actual_md5 != str(_file.get("md5", "")).to_lower():
		_fail("The downloaded archive failed its checksum. It was not installed.")
		return

	progress.emit(actual_size, expected_size, "Checking and installing the pack...")
	var thread: = Thread.new()
	# Resolve the game autoload on the main thread. The worker only receives
	# immutable paths and then sticks to its own FileAccess/DirAccess instances.
	var error: Error = thread.start(
		_validate_and_extract.bind(_download_path, _mod, _file, type_roots(), true))
	if error != OK:
		_fail("Could not start archive validation (%s)." % error_string(error))
		return
	while thread.is_alive(): await get_tree().process_frame
	var extracted_value: Variant = thread.wait_to_finish()
	if not extracted_value is Dictionary:
		_fail("Archive validation stopped unexpectedly.")
		return
	var extracted: Dictionary = extracted_value
	if extracted.has("error"):
		_fail(str(extracted["error"]))
		return
	_busy = false
	_cleanup_download()
	progress.emit(expected_size, expected_size, "Installed.")
	finished.emit(extracted)


func _fail(message: String) -> void:
	push_warning("Community pack %s failed: %s" % [str(_file.get("name", "download")), message])  # lands in the game log
	_busy = false
	set_process(false)
	_join_worker()
	_cleanup_download()
	failed.emit(message)


func _cleanup_download() -> void:
	if (_download_path.begins_with(DOWNLOAD_ROOT + "/")
		and FileAccess.file_exists(_download_path)):
		DirAccess.remove_absolute(_download_path)
	_download_path = ""


# roots: type -> pack folder, from type_roots(). A String is a stand-in game
# folder (tests): its packs_* subfolders are used.
static func _validate_and_extract(
	archive: String, mod: Dictionary, file: Dictionary, roots: Variant = "",
	use_registry: bool = true
) -> Dictionary:
	if not (archive.get_file().contains(".rar") or archive.get_file().contains(".7z")):
		return _validate_and_extract_zip(archive, mod, file, roots, use_registry)
	# RAR and 7z: the system's bsdtar (macOS /usr/bin/tar, Windows tar.exe) rewrites it as a
	# ZIP without extracting anything, then the normal ZIP checks decide what installs.
	# ponytail: no timeout on tar; a RAR bomb costs CPU time here, but the ZIP checks
	# still refuse oversized contents before anything is written to packs_voice.
	var converted: String = archive.get_basename() + ".converted.zip"
	var tar: String = "/usr/bin/tar" if OS.get_name() == "macOS" else "tar"
	var output: Array = []
	var code: int = OS.execute(tar, ["-c", "-f", ProjectSettings.globalize_path(converted), "--format", "zip",
		"@" + ProjectSettings.globalize_path(archive)], output, true)
	if code != 0 or not FileAccess.file_exists(converted):
		if FileAccess.file_exists(converted): DirAccess.remove_absolute(converted)
		return {"error": "This archive could not be read (%s)." % ("".join(output).strip_edges().left(160) if not output.is_empty() else "tar exit %d" % code)}
	var result: Dictionary = _validate_and_extract_zip(converted, mod, file, roots, use_registry)
	DirAccess.remove_absolute(converted)
	return result


# Every Customize pack type. The archive's contents decide the type, not its
# GameBanana category: Compilation Packs and Other/Misc mix them, and one player
# ZIP can hold seven players.
const TYPE_FOLDERS: Dictionary = {
	"dub": "packs_voice", "voice": "packs_voice", "menu": "packs_menu",
	"player": "packs_player", "studio": "packs_studio", "judges": "packs_judges",
	"host": "packs_host", "chatter": "packs_chatter",
}
const TYPE_NAMES: Dictionary = {
	"dub": ["Dub Mode pack", "Dub Mode packs"], "voice": ["voice pack", "voice packs"],
	"menu": ["menu", "menus"], "player": ["player", "players"], "studio": ["studio", "studios"],
	"judges": ["judges pack", "judges packs"], "host": ["host", "hosts"],
	"chatter": ["chatter pack", "chatter packs"],
}
# archives laid out like the game folder: packs_player/<name>/... (one creator
# wrote packs_voices)
const GAME_FOLDER_TYPES: Dictionary = {
	"packs_voice": "voice", "packs_voices": "voice", "packs_menu": "menu",
	"packs_player": "player", "packs_studio": "studio", "packs_judges": "judges",
	"packs_host": "host", "packs_chatter": "chatter",
}
# a folder holding one of these is that type's pack. Every Player, Menu, Host and
# Judges pack checked on GameBanana had its config file. Image names like
# player.png or host.png are left out: they are also plausible voice clip names.
const MARKERS: Dictionary = {
	"config_menu.json": "menu", "config_player.json": "player",
	"config_judges.json": "judges", "config_host.json": "host",
	"config_studio.json": "studio", "config_chatter.ini": "chatter",
	"config_chatter.cfg": "chatter", "model.glb": "studio",
	"judge1.png": "judges", "judge1.jpg": "judges",
	"music_menu": "menu", "music_studio": "studio",  # with any audio extension
}
# 3D studio models: only GLB, which is self-contained, and only in studio packs.
const STUDIO_EXTENSIONS: PackedStringArray = ["glb"]


static func type_roots(base: String = "") -> Dictionary:
	var roots: Dictionary = {}
	if base.is_empty():
		roots = {
			"dub": FileManager.MODPACKS_VOICE, "voice": FileManager.MODPACKS_VOICE,
			"menu": FileManager.MODPACKS_MENU, "player": FileManager.MODPACKS_PLAYER,
			"studio": FileManager.MODPACKS_STUDIO, "judges": FileManager.MODPACKS_JUDGES,
			"host": FileManager.MODPACKS_HOST, "chatter": FileManager.MODPACKS_CHATTER,
		}
	else:
		for type: String in TYPE_FOLDERS:
			roots[type] = base.trim_suffix("/").path_join(TYPE_FOLDERS[type])
	for type: String in roots:
		roots[type] = str(roots[type]).replace("\\", "/").trim_suffix("/")
	return roots


static func _roots_from(value: Variant) -> Dictionary:
	if value is Dictionary and not value.is_empty(): return value
	return type_roots(str(value) if value is String else "")


static func _marker_type(path: String) -> String:
	var name: String = path.get_file().to_lower()
	if MARKERS.has(name): return MARKERS[name]
	if AUDIO_EXTENSIONS.has(name.get_extension()) and MARKERS.has(name.get_basename()):
		return MARKERS[name.get_basename()]
	return ""


static func _dir_of(path: String) -> String:
	var dir: String = path.get_base_dir()
	return "" if dir == "." else dir


# the deepest pack folder this file belongs to, or NO_DUB_ROOT for none.
static func _owner(path: String, packs: Dictionary) -> String:
	var best: String = NO_DUB_ROOT
	for root: String in packs:
		if ((root.is_empty() or path.begins_with(root + "/"))
			and (best == NO_DUB_ROOT or root.length() > best.length())):
			best = root
	return best


# archive folder -> type, for every pack in the archive.
static func find_packs(entries: Array[Dictionary]) -> Dictionary:
	var files: PackedStringArray = []
	for entry: Dictionary in entries:
		var path: String = str(entry.get("path", ""))
		if not bool(entry.get("directory", false)) and not _junk_path(path): files.append(path)
	var packs: Dictionary = {}
	for path: String in files:
		var parts: PackedStringArray = path.split("/")
		for i: int in range(parts.size() - 2):  # needs packs_x/<name>/<file>
			var type: String = GAME_FOLDER_TYPES.get(parts[i].to_lower(), "")
			if type.is_empty(): continue
			packs["/".join(parts.slice(0, i + 2))] = type
			break
	if packs.is_empty():
		for config_pass: bool in [true, false]:  # a config file outranks a model or music file beside it
			for path: String in files:
				var type: String = _marker_type(path)
				if type.is_empty() or path.get_file().to_lower().begins_with("config_") != config_pass: continue
				if not packs.has(_dir_of(path)): packs[_dir_of(path)] = type
		for path: String in files:
			if path.get_file().to_lower() == "dub_video.ogv" and _owner(path, packs) == NO_DUB_ROOT:
				packs[_dir_of(path)] = "dub"
		if packs.is_empty():
			var dub_root: String = _find_dub_root(entries)  # older rule: any .ogv beside the most audio
			if dub_root != NO_DUB_ROOT: packs[dub_root] = "dub"
		# whatever audio is left is a voice pack, rooted where all of it meets
		var common: Variant = null
		for path: String in files:
			if not AUDIO_EXTENSIONS.has(path.get_extension().to_lower()): continue
			if _owner(path, packs) != NO_DUB_ROOT: continue
			var dir: String = _dir_of(path)
			if common == null: common = dir
			while not (str(common).is_empty() or dir == common or dir.begins_with(str(common) + "/")):
				common = _dir_of(str(common))
		if common != null: packs[str(common)] = "voice"
	for root: String in packs:  # a voice folder with its video is a dub pack
		if packs[root] != "voice": continue
		for path: String in files:
			if _dir_of(path) == root and path.get_extension().to_lower() == "ogv": packs[root] = "dub"
	return packs


static func _validate_and_extract_zip(
	archive: String, mod: Dictionary, file: Dictionary, roots_value: Variant = "",
	use_registry: bool = true
) -> Dictionary:
	var indexed: Dictionary = inspect_zip(archive)
	if indexed.has("error"): return indexed
	var entries: Array[Dictionary] = []
	for value: Variant in Array(indexed.get("entries", [])):
		if value is Dictionary: entries.append(value)
	var found: Dictionary = find_packs(entries)
	if found.is_empty():
		for entry: Dictionary in entries:  # a patcher, a build or source code: someone's mod of the game itself
			if ["exe", "bat", "xdelta", "vcdiff", "pck", "dll", "gd", "py", "sh", "command"].has(str(entry.get("path", "")).get_extension().to_lower()):
				return {"error": "This is a mod for the game itself, not a pack. Get it from its GameBanana page."}
		return {"error": "No pack the game can use was found in this archive."}
	# a Dub Mode upload without its video is a broken dub pack, not a voice pack
	if str(mod.get("category", "")) == "Dub Mode" and not found.values().has("dub"):
		return {"error": "The archive did not contain a complete dub pack."}

	var mod_id: int = int(mod.get("id", 0))
	var registry: Dictionary = load_registry() if use_registry else {}
	var registered: Dictionary = _as_dictionary(registry.get(str(mod_id), {}))
	var registered_path: String = str(registered.get("path", ""))
	if not registered_path.is_empty() and DirAccess.dir_exists_absolute(registered_path):
		return {"path": registered_path, "already_installed": true}

	# archive folder -> {type, files, bytes, audio, video, seen}
	var plans: Dictionary = {}
	for root: String in found:
		plans[root] = {"type": found[root], "files": [], "bytes": 0, "audio": 0, "video": 0, "seen": {}}
	var total: int = 0
	for entry: Dictionary in entries:
		if bool(entry.get("directory", false)): continue
		var path: String = str(entry["path"])
		if _junk_path(path): continue
		var root: String = _owner(path, plans)
		if root == NO_DUB_ROOT: continue  # not part of any pack, like a readme beside the packs
		var plan: Dictionary = plans[root]
		if not root.is_empty(): path = path.substr(root.length() + 1)
		if _junk_path(path): continue
		if not _safe_relative_path(path):
			return {"error": "The archive contains an unsafe path: %s" % path}
		var ext: String = path.get_extension().to_lower()
		# anything the game can't use (a creator's source .mp4, a .psd, an .exe)
		# is left in the archive and never written to disk, instead of refusing
		# a pack that is fine without it.
		if not SAFE_EXTENSIONS.has(ext) and not (plan["type"] == "studio" and STUDIO_EXTENSIONS.has(ext)):
			print("Community pack install: skipped %s, the game doesn't use .%s files" % [path, ext])
			continue
		var key: String = path.to_lower()
		if plan["seen"].has(key): return {"error": "The archive writes the same path twice: %s" % path}
		plan["seen"][key] = true
		var size: int = int(entry["size"])
		if size > MAX_FILE_BYTES:
			return {"error": "%s is larger than the per-file safety limit." % path}
		total += size
		if total > MAX_EXPANDED_BYTES:
			return {"error": "The extracted pack would exceed the 4 GB safety limit."}
		if AUDIO_EXTENSIONS.has(ext): plan["audio"] += 1
		if ext == "ogv": plan["video"] += 1
		plan["bytes"] += size
		var selected: Dictionary = entry.duplicate()
		selected["output_path"] = path
		plan["files"].append(selected)

	var ready: Array[String] = []
	var dub_problem: bool = false
	for root: String in plans:
		var plan: Dictionary = plans[root]
		var complete: bool = not plan["files"].is_empty()
		match str(plan["type"]):
			"dub":
				complete = complete and plan["audio"] > 0 and plan["video"] > 0
				dub_problem = dub_problem or not complete
			"voice", "chatter": complete = complete and plan["audio"] > 0
		if complete: ready.append(root)
	if ready.is_empty():
		if dub_problem: return {"error": "The archive did not contain a complete dub pack."}
		return {"error": "No pack the game can use was found in this archive."}
	ready.sort()

	var roots: Dictionary = _roots_from(roots_value)
	var reserved: Dictionary = {}
	for root: String in ready:
		var plan: Dictionary = plans[root]
		var type_root: String = str(roots[plan["type"]])
		if DirAccess.make_dir_recursive_absolute(type_root) != OK:
			return {"error": "Could not create the game's %s folder." % type_root.get_file()}
		# Dub packs keep their GameBanana name and tag. Everything else keeps the
		# creator's folder name, which is the name Customize shows.
		var mod_name: String = str(mod.get("name", "Pack"))
		var folder_name: String
		if plan["type"] == "dub":
			folder_name = _safe_folder_name(mod_name if ready.size() == 1 else root.get_file(), mod_id)
		else:
			folder_name = _clean_folder_name(root.get_file() if not root.is_empty() else mod_name, mod_name)
		var destination: String = type_root.path_join(folder_name)
		var suffix: int = 2
		while DirAccess.dir_exists_absolute(destination) or reserved.has(destination.to_lower()):
			destination = type_root.path_join("%s (%d)" % [folder_name, suffix])
			suffix += 1
		reserved[destination.to_lower()] = true
		plan["destination"] = destination
		plan["staging_root"] = type_root.path_join(".tcv-community-staging")
	var first_root: DirAccess = DirAccess.open(str(plans[ready[0]]["destination"]).get_base_dir())
	var free: int = first_root.get_space_left() if first_root != null else 0
	# count the other installs still being written too, or three big packs that
	# each fit alone can fill the disk together.
	# ponytail: one total for every drive; per drive if packs ever span several
	_registry_lock.lock()
	var short: bool = free > 0 and free < total + _staging_bytes + FREE_SPACE_MARGIN
	if not short: _staging_bytes += total
	_registry_lock.unlock()
	if short: return {"error": "Not enough disk space to install this pack."}

	# Stage beside each final pack. user:// may be on C: while the game and its
	# external packs live on another drive; a rename across those volumes is not
	# atomic and normally fails outright on Windows.
	var zip: = ZIPReader.new()
	var open_error: Error = zip.open(archive)
	if open_error != OK:
		_release_staging(total)
		return {"error": "Godot could not open this ZIP (%s)." % error_string(open_error)}
	var problem: String = ""
	for index: int in ready.size():
		problem = _stage_pack(zip, plans[ready[index]], mod, file, index)
		if not problem.is_empty(): break
	zip.close()
	var moved: Array[String] = []
	if problem.is_empty():
		for root: String in ready:
			var plan: Dictionary = plans[root]
			var move_error: Error = DirAccess.rename_absolute(plan["staging"], plan["destination"])
			if move_error != OK:
				problem = "Could not move the verified pack into %s (%s)." % [
					str(plan["destination"]).get_base_dir().get_file(), error_string(move_error)]
				break
			moved.append(plan["destination"])
	for root: String in ready:
		var plan: Dictionary = plans[root]
		if not problem.is_empty() and plan.has("staging"): _remove_tree(plan["staging"], plan["staging_root"])
		# only removes it when empty: another install may be staging there right now
		DirAccess.remove_absolute(plan["staging_root"])
	_release_staging(total)  # written or removed by now, so free space counts it
	if not problem.is_empty():  # all or nothing
		for path: String in moved: _remove_installed_tree(path, path)
		return {"error": problem}

	var installed: Array[Dictionary] = []
	var file_count: int = 0
	for root: String in ready:
		installed.append({"type": plans[root]["type"], "path": plans[root]["destination"]})
		file_count += plans[root]["files"].size()
	var result: Dictionary = {
		"path": moved[0], "paths": moved, "packs": installed, "files": file_count, "bytes": total}
	if not use_registry: return result
	_registry_lock.lock()
	registry = load_registry()  # fresh: another install may have finished meanwhile
	# two files of the same mod installing at once both pass the check above; keep
	# the other one's folders too, so Uninstall still finds them.
	var paths: Array[String] = moved.duplicate()
	for path: Variant in Array(_as_dictionary(registry.get(str(mod_id), {})).get("paths", [])):
		if not paths.has(str(path)) and DirAccess.dir_exists_absolute(str(path)): paths.append(str(path))
	registry[str(mod_id)] = {
		"path": moved[0],
		"paths": paths,
		"file_id": int(file.get("id", 0)),
		"md5": str(file.get("md5", "")),
		"name": str(mod.get("name", "Pack")),
	}
	var saved: bool = save_registry(registry)
	_registry_lock.unlock()
	if not saved:
		# Installation is still complete; the embedded manifests let a later run
		# rediscover it even if this convenience index could not be written.
		result["warning"] = "Installed, but could not update the local pack index."
	return result


# Extracts one pack into its own staging folder. Returns an error message, or "".
static func _stage_pack(zip: ZIPReader, plan: Dictionary, mod: Dictionary, file: Dictionary, index: int) -> String:
	var staging_root: String = plan["staging_root"]
	if DirAccess.make_dir_recursive_absolute(staging_root) != OK:
		return "Could not create the community-pack staging folder."
	var staging: String = staging_root.path_join(
		"%d-%d-%d" % [int(mod.get("id", 0)), Time.get_ticks_usec(), index])
	if DirAccess.make_dir_recursive_absolute(staging) != OK:
		return "Could not create a temporary installation folder."
	plan["staging"] = staging
	for entry: Dictionary in plan["files"]:
		var output_path: String = staging.path_join(str(entry["output_path"]))
		if DirAccess.make_dir_recursive_absolute(output_path.get_base_dir()) != OK:
			return "Could not create a folder while extracting the pack."
		var bytes: PackedByteArray = zip.read_file(str(entry["zip_path"]))
		if bytes.size() != int(entry["size"]):
			return "The ZIP entry %s did not extract to its declared size." % str(entry["output_path"])
		var output: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
		if output == null: return "Could not write %s." % str(entry["output_path"])
		output.store_buffer(bytes)
		output.close()
	var manifest: Dictionary = {
		"schema": 1,
		"provider": "gamebanana",
		"type": str(plan["type"]),
		"mod_id": int(mod.get("id", 0)),
		"file_id": int(file.get("id", 0)),
		"name": str(mod.get("name", "Pack")),
		"author": str(mod.get("author", "Unknown creator")),
		"profile_url": str(mod.get("profile_url", "")),
		"archive_name": str(file.get("name", "")),
		"archive_md5": str(file.get("md5", "")),
		"installed_files": plan["files"].size(),
		"installed_bytes": int(plan["bytes"]),
		"installed_unix": int(Time.get_unix_time_from_system()),
	}
	var manifest_file: FileAccess = FileAccess.open(staging.path_join(MANIFEST_NAME), FileAccess.WRITE)
	if manifest_file == null: return "Could not write the installed-pack manifest."
	manifest_file.store_string(JSON.stringify(manifest, "  "))
	manifest_file.close()
	return ""


static func inspect_zip(path: String) -> Dictionary:
	var input: FileAccess = FileAccess.open(path, FileAccess.READ)
	if input == null: return {"error": "Could not open the downloaded archive."}
	var length: int = input.get_length()
	if length < 22 or length > MAX_ARCHIVE_BYTES:
		input.close()
		return {"error": "The downloaded ZIP has an invalid size."}
	var tail_size: int = mini(length, 65557)
	input.seek(length - tail_size)
	var tail: PackedByteArray = input.get_buffer(tail_size)
	var eocd: int = -1
	for i: int in range(tail.size() - 22, -1, -1):
		if tail.decode_u32(i) == 0x06054b50:
			eocd = i
			break
	if eocd < 0:
		input.close()
		return {"error": "The archive has no readable ZIP directory."}
	var entry_count: int = tail.decode_u16(eocd + 10)
	var directory_size: int = tail.decode_u32(eocd + 12)
	var directory_offset: int = tail.decode_u32(eocd + 16)
	if (entry_count == 0xffff or directory_size == 0xffffffff or directory_offset == 0xffffffff
		or entry_count <= 0 or entry_count > MAX_FILES
		or directory_offset < 0 or directory_size < 0
		or directory_offset + directory_size > length):
		input.close()
		return {"error": "ZIP64 or an invalid archive directory is not supported."}
	input.seek(directory_offset)
	var entries: Array[Dictionary] = []
	var expanded: int = 0
	for _index: int in entry_count:
		var header: PackedByteArray = input.get_buffer(46)
		if header.size() != 46 or header.decode_u32(0) != 0x02014b50:
			input.close()
			return {"error": "The ZIP directory is corrupt."}
		var flags: int = header.decode_u16(8)
		var method: int = header.decode_u16(10)
		var compressed: int = header.decode_u32(20)
		var size: int = header.decode_u32(24)
		var name_length: int = header.decode_u16(28)
		var extra_length: int = header.decode_u16(30)
		var comment_length: int = header.decode_u16(32)
		var external_attributes: int = header.decode_u32(38)
		if (compressed == 0xffffffff or size == 0xffffffff or name_length <= 0
			or name_length > 4096 or extra_length > 65535 or comment_length > 65535):
			input.close()
			return {"error": "The ZIP uses unsupported ZIP64 entry metadata."}
		var name_bytes: PackedByteArray = input.get_buffer(name_length)
		if name_bytes.size() != name_length:
			input.close()
			return {"error": "A ZIP filename is truncated."}
		input.seek(input.get_position() + extra_length + comment_length)
		var zip_path: String = name_bytes.get_string_from_utf8()
		var normalized: String = zip_path.replace("\\", "/").trim_prefix("./")
		var directory: bool = normalized.ends_with("/")
		var unix_type: int = (external_attributes >> 16) & 0xf000
		if unix_type == 0xa000:
			input.close()
			return {"error": "The archive contains a symbolic link, which is not allowed."}
		if (flags & 1) != 0:
			input.close()
			return {"error": "Password-protected ZIP entries are not supported."}
		if not directory and method != 0 and method != 8:
			input.close()
			return {"error": "The ZIP uses an unsupported compression method."}
		if not directory:
			if size > MAX_FILE_BYTES:
				input.close()
				return {"error": "%s is too large to extract safely." % normalized}
			expanded += size
			if expanded > MAX_EXPANDED_BYTES:
				input.close()
				return {"error": "The archive expands beyond the 4 GB safety limit."}
			if size > 16 * 1024 * 1024 and (compressed <= 0 or size / compressed > 200):
				input.close()
				return {"error": "%s has an unsafe compression ratio." % normalized}
		entries.append({
			"zip_path": zip_path,
			"path": normalized.trim_suffix("/"),
			"directory": directory,
			"size": size,
			"compressed": compressed,
		})
	input.close()
	return {"entries": entries, "expanded_bytes": expanded}


static func _find_dub_root(entries: Array[Dictionary]) -> String:
	var best: String = NO_DUB_ROOT
	var best_audio: int = -1
	for entry: Dictionary in entries:
		if bool(entry.get("directory", false)): continue
		var path: String = str(entry.get("path", ""))
		if path.get_extension().to_lower() != "ogv": continue
		var candidate: String = path.get_base_dir()
		if candidate == ".": candidate = ""
		var audio: int = 0
		for other: Dictionary in entries:
			if bool(other.get("directory", false)): continue
			var other_path: String = str(other.get("path", ""))
			if not candidate.is_empty() and not other_path.begins_with(candidate + "/"): continue
			if AUDIO_EXTENSIONS.has(other_path.get_extension().to_lower()): audio += 1
		if audio > best_audio or (audio == best_audio and candidate.length() > best.length()):
			best = candidate
			best_audio = audio
	return best if best_audio > 0 else NO_DUB_ROOT


static func installed_path(mod_id: int) -> String:
	var paths: PackedStringArray = installed_paths(mod_id)
	return paths[0] if not paths.is_empty() else ""


static func installed_paths(mod_id: int) -> PackedStringArray:
	var found: PackedStringArray = []
	if mod_id <= 0: return found
	var registry: Dictionary = load_registry()
	var record: Dictionary = _as_dictionary(registry.get(str(mod_id), {}))
	var listed: Array = record.get("paths", [record.get("path", "")]) if not record.is_empty() else []
	for value: Variant in listed:
		if not str(value).is_empty() and DirAccess.dir_exists_absolute(str(value)): found.append(str(value))
	if not found.is_empty(): return found
	# The per-pack manifests are authoritative. Rebuild the convenience index if
	# it was deleted or an installed folder was moved within its packs folder.
	var first: Dictionary = {}
	for pack: Dictionary in installed_packs():
		if int(pack.get("mod_id", 0)) != mod_id: continue
		found.append(str(pack["path"]))
		if first.is_empty(): first = pack
	if found.is_empty(): return found
	_registry_lock.lock()
	registry = load_registry()
	registry[str(mod_id)] = {
		"path": found[0],
		"paths": Array(found),
		"file_id": int(first.get("file_id", 0)),
		"md5": str(first.get("archive_md5", "")),
		"name": str(first.get("name", found[0].get_file())),
	}
	save_registry(registry)
	_registry_lock.unlock()
	return found


# One record per installed pack folder, of every type. Packs installed before
# types existed have no "type" and are Dub Mode packs.
static func installed_packs(roots_override: Variant = "") -> Array[Dictionary]:
	var roots: Dictionary = _roots_from(roots_override)
	var packs: Array[Dictionary] = []
	var scanned: Dictionary = {}
	for type: String in roots:
		var type_root: String = str(roots[type])
		if scanned.has(type_root): continue
		scanned[type_root] = true
		var parent: DirAccess = DirAccess.open(type_root)
		if parent == null: continue
		parent.include_hidden = true
		for folder: String in parent.get_directories():
			if parent.is_link(folder): continue
			var path: String = type_root.path_join(folder)
			var manifest_path: String = path.path_join(MANIFEST_NAME)
			if not FileAccess.file_exists(manifest_path): continue
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
			if (not parsed is Dictionary or str(parsed.get("provider", "")) != "gamebanana"
				or int(parsed.get("mod_id", 0)) <= 0):
				continue
			var record: Dictionary = parsed.duplicate(true)
			record["path"] = path
			record["folder"] = folder
			record["root"] = type_root
			if not TYPE_FOLDERS.has(str(record.get("type", ""))): record["type"] = "dub"
			packs.append(record)
	packs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", ""))) < 0)
	return packs


# Removes every folder this installer placed for the submission.
static func uninstall(mod_id: int, exact_path: String = "") -> Dictionary:
	var roots: Array = type_roots().values()
	var paths: PackedStringArray = []
	for pack: Dictionary in installed_packs():
		if int(pack.get("mod_id", 0)) == mod_id: paths.append(str(pack["path"]))
	var exact: String = exact_path.replace("\\", "/").trim_suffix("/")
	if not exact.is_empty() and not paths.has(exact): paths.append(exact)
	if paths.is_empty(): return {"error": "This community pack is not installed."}
	for path: String in paths:
		if not roots.has(path.get_base_dir()):
			return {"error": "The installed pack is outside the game's pack folders and was not removed."}
	for path: String in paths:
		var removed: Dictionary = _uninstall_path(mod_id, path, path.get_base_dir(), false)
		if removed.has("error"): return removed
	_registry_lock.lock()
	var registry: Dictionary = load_registry()
	registry.erase(str(mod_id))
	save_registry(registry)
	_registry_lock.unlock()
	return {"path": paths[0], "paths": paths}


static func _uninstall_path(
	mod_id: int, installed: String, type_root_value: String, update_registry: bool
) -> Dictionary:
	var path: String = installed.replace("\\", "/").trim_suffix("/")
	var type_root: String = type_root_value.replace("\\", "/").trim_suffix("/")
	# Only a direct child created by this installer can be removed. Never turn a
	# registry entry or edited manifest into a recursive delete outside the pack
	# library.
	if path.get_base_dir() != type_root:
		return {"error": "The installed pack is outside the game's pack folders and was not removed."}
	var parent: DirAccess = DirAccess.open(type_root)
	if parent == null or parent.is_link(path.get_file()):
		return {"error": "The installed pack folder is not safe to remove automatically."}
	var manifest_path: String = path.path_join(MANIFEST_NAME)
	if not FileAccess.file_exists(manifest_path):
		return {"error": "This folder has no community-pack manifest, so it was not removed."}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if (not parsed is Dictionary or str(parsed.get("provider", "")) != "gamebanana"
		or int(parsed.get("mod_id", 0)) != mod_id):
		return {"error": "The community-pack manifest did not match; nothing was removed."}
	if not _remove_installed_tree(path, path):
		return {"error": "Could not completely remove the installed pack."}
	if update_registry:
		_registry_lock.lock()
		var registry: Dictionary = load_registry()
		registry.erase(str(mod_id))
		save_registry(registry)
		_registry_lock.unlock()
	return {"path": path}


# up to three installs can finish at once on their own threads, and the browser
# reads this from the main thread. Godot's Mutex is recursive, so the
# read-edit-save spots above hold it across both calls.
static var _registry_lock: Mutex = Mutex.new()
static var _staging_bytes: int = 0  # bytes other installs are writing right now


static func _release_staging(bytes: int) -> void:
	_registry_lock.lock()
	_staging_bytes -= bytes
	_registry_lock.unlock()


static func load_registry() -> Dictionary:
	_registry_lock.lock()
	var text: String = FileAccess.get_file_as_string(REGISTRY_PATH) if FileAccess.file_exists(REGISTRY_PATH) else ""
	_registry_lock.unlock()
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
	return parsed if parsed is Dictionary else {}


static func save_registry(registry: Dictionary) -> bool:
	_registry_lock.lock()
	var output: FileAccess = FileAccess.open(REGISTRY_PATH, FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(registry, "  "))
		output.close()
	_registry_lock.unlock()
	return output != null


static func _safe_relative_path(path: String) -> bool:
	if (path.is_empty() or path.length() > 512 or path.begins_with("/")
		or path.contains(String.chr(0))):
		return false
	if path.length() >= 2 and path.substr(1, 1) == ":": return false
	for part: String in path.replace("\\", "/").split("/", false):
		if part.is_empty() or part == "." or part == "..": return false
	return true


static func _junk_path(path: String) -> bool:
	var lower: String = path.to_lower()
	return (lower.begins_with("__macosx/") or lower.ends_with("/.ds_store")
		or lower == ".ds_store" or lower.ends_with("/thumbs.db") or lower == "thumbs.db"
		or lower.ends_with("/desktop.ini") or lower == "desktop.ini")


# keeps a creator's folder name as written ("TvTime(Music & 2D sprites)",
# "Versão Brasileira"), dropping only what Windows or macOS can't store.
static func _clean_folder_name(value: String, fallback: String = "Pack") -> String:
	var out: String = ""
	for i: int in value.length():
		var c: String = value.substr(i, 1)
		if c.unicode_at(0) < 32 or "<>:\"/\\|?*".contains(c): c = " "
		if c == " " and (out.is_empty() or out.ends_with(" ")): continue
		out += c
	out = out.substr(0, 80).strip_edges().rstrip(". ")
	if out.to_upper().get_basename() in ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4",
		"COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6",
		"LPT7", "LPT8", "LPT9"]:
		out += " pack"
	if out.is_empty() and fallback != value: return _clean_folder_name(fallback, "Pack")
	return out if not out.is_empty() else "Pack"


static func _safe_folder_name(value: String, mod_id: int) -> String:
	return "%s [GB-%d]" % [_clean_folder_name(value, "Dub pack"), mod_id]


static func _remove_tree(path: String, staging_root: String) -> void:
	if not path.begins_with(staging_root + "/") or not DirAccess.dir_exists_absolute(path): return
	var dir: DirAccess = DirAccess.open(path)
	if dir == null: return
	dir.include_hidden = true
	for child: String in dir.get_directories(): _remove_tree(path.path_join(child), staging_root)
	for child: String in dir.get_files(): DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)


static func _remove_installed_tree(path: String, allowed_root: String) -> bool:
	if (path != allowed_root and not path.begins_with(allowed_root + "/")):
		return false
	var dir: DirAccess = DirAccess.open(path)
	if dir == null: return false
	dir.include_hidden = true
	for child: String in dir.get_directories():
		var child_path: String = path.path_join(child)
		if dir.is_link(child):
			if DirAccess.remove_absolute(child_path) != OK: return false
		elif not _remove_installed_tree(child_path, allowed_root): return false
	for child: String in dir.get_files():
		if DirAccess.remove_absolute(path.path_join(child)) != OK: return false
	dir = null
	return DirAccess.remove_absolute(path) == OK


static func _file_size(path: String) -> int:
	var input: FileAccess = FileAccess.open(path, FileAccess.READ)
	if input == null: return -1
	var size: int = input.get_length()
	input.close()
	return size


static func _is_hex(value: String) -> bool:
	for i: int in value.length():
		if not "0123456789abcdef".contains(value.substr(i, 1).to_lower()): return false
	return true


static func _as_dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _format_bytes(bytes: int) -> String:
	if bytes >= 1024 * 1024 * 1024: return "%.2f GB" % (float(bytes) / 1073741824.0)
	if bytes >= 1024 * 1024: return "%.1f MB" % (float(bytes) / 1048576.0)
	if bytes >= 1024: return "%.1f KB" % (float(bytes) / 1024.0)
	return "%d bytes" % bytes
