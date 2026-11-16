extends Node
# Session-long download queue. It lives under the Net autoload rather than the
# catalog screen, so closing the browser or entering an offline game does not
# tear down a large download.

signal changed

const INSTALLER_SCRIPT: Script = preload("res://net/community_pack_installer.gd")
const SETTINGS_PATH: String = "user://community_pack_settings.json"
# GameBanana limits each connection, not the whole computer: one download ran at
# 0.4-0.95 MB/s, four at once added up to 2.9 MB/s. Three keeps it to what a
# browser grabbing a few files looks like.
const MAX_PARALLEL: int = 3

var _net: Node
var _pool: Array[Node] = []
# installer -> job id, for the ones working right now
var _active: Dictionary = {}
var _canceling: Dictionary = {}
# job id -> [msec, bytes] of the last speed sample
var _speed_sample: Dictionary = {}
# the first slot. tests drive an installer directly through this.
var _installer: Node
var _jobs: Array[Dictionary] = []
var _last_online: bool = false
var _poll_elapsed: float = 0.0
var _last_progress_emit_msec: int = 0
var _allow_online_downloads: bool = false


func configure(net: Node) -> void:
	_net = net
	_last_online = _net.is_online()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	for slot: int in MAX_PARALLEL:
		var installer: Node = INSTALLER_SCRIPT.new()
		installer.progress.connect(_on_progress.bind(installer))
		installer.finished.connect(_on_finished.bind(installer))
		installer.failed.connect(_on_failed.bind(installer))
		add_child(installer)
		_pool.append(installer)
	_installer = _pool[0]


func _process(delta: float) -> void:
	_poll_elapsed += delta
	if _poll_elapsed < 0.5: return
	_poll_elapsed = 0.0
	var online: bool = _net != null and _net.is_online()
	if online != _last_online:
		_last_online = online
		changed.emit()
	if _active.size() < _pool.size() and (not online or _allow_online_downloads): _pump()


func allow_online_downloads() -> bool:
	return _allow_online_downloads


func set_allow_online_downloads(value: bool) -> void:
	if _allow_online_downloads == value: return
	_allow_online_downloads = value
	_save_settings()
	changed.emit()
	if value: _pump.call_deferred()


func enqueue(mod: Dictionary, file: Dictionary) -> String:
	var mod_id: int = int(mod.get("id", 0))
	var file_id: int = int(file.get("id", 0))
	if mod_id <= 0 or file_id <= 0: return ""
	var id: String = job_id(mod_id, file_id)
	var index: int = _job_index(id)
	if index >= 0:
		var state: String = str(_jobs[index].get("state", ""))
		if state in ["queued", "downloading", "verifying", "installing"]: return id
		_jobs.remove_at(index)
	_jobs.append({
		"id": id,
		"mod": mod.duplicate(true),
		"file": file.duplicate(true),
		"state": "queued",
		"received": 0,
		"total": int(file.get("size", 0)),
		"speed": 0.0,
		"status": "Queued",
		"error": "",
		"result": {},
	})
	changed.emit()
	_pump.call_deferred()
	return id


func cancel(id: String) -> void:
	var index: int = _job_index(id)
	if index < 0: return
	var installer: Node = _installer_for(id)
	if installer != null:
		if str(_jobs[index].get("state", "")) != "downloading": return
		_canceling[id] = true
		installer.cancel()
		return
	if str(_jobs[index].get("state", "")) == "queued":
		_jobs[index]["state"] = "canceled"
		_jobs[index]["status"] = "Canceled"
		changed.emit()


func dismiss(id: String) -> void:
	var index: int = _job_index(id)
	if index < 0: return
	if str(_jobs[index].get("state", "")) in ["finished", "failed", "canceled"]:
		_jobs.remove_at(index)
		changed.emit()


func dismiss_for_mod(mod_id: int) -> void:
	var removed: bool = false
	for index: int in range(_jobs.size() - 1, -1, -1):
		if int(_jobs[index].get("mod", {}).get("id", 0)) != mod_id: continue
		if str(_jobs[index].get("state", "")) not in ["finished", "failed", "canceled"]: continue
		_jobs.remove_at(index)
		removed = true
	if removed: changed.emit()


func retry(id: String) -> void:
	var record: Dictionary = get_job(id)
	if record.is_empty(): return
	if str(record.get("state", "")) not in ["failed", "canceled"]: return
	enqueue(record.get("mod", {}), record.get("file", {}))


func get_job(id: String) -> Dictionary:
	var index: int = _job_index(id)
	return _jobs[index].duplicate(true) if index >= 0 else {}


func get_jobs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for record: Dictionary in _jobs: out.append(record.duplicate(true))
	return out


func job_for(mod_id: int, file_id: int) -> Dictionary:
	return get_job(job_id(mod_id, file_id))


func active_count() -> int:
	var total: int = 0
	for record: Dictionary in _jobs:
		if str(record.get("state", "")) in ["queued", "downloading", "verifying", "installing"]:
			total += 1
	return total


func is_busy() -> bool:
	return active_count() > 0


static func job_id(mod_id: int, file_id: int) -> String:
	return "%d:%d" % [mod_id, file_id]


func _pump() -> void:
	if _net != null and _net.is_online() and not _allow_online_downloads: return
	for installer: Node in _pool:
		if _active.has(installer) or installer.is_busy(): continue
		var index: int = -1
		for candidate: int in _jobs.size():
			if str(_jobs[candidate].get("state", "")) == "queued":
				index = candidate
				break
		if index < 0: return
		var id: String = str(_jobs[index]["id"])
		_active[installer] = id
		_canceling.erase(id)
		_speed_sample.erase(id)
		_jobs[index]["state"] = "downloading"
		_jobs[index]["status"] = "Waiting for GameBanana..."
		_jobs[index]["speed"] = 0.0
		changed.emit()
		installer.install(_jobs[index]["mod"], _jobs[index]["file"])


func _installer_for(id: String) -> Node:
	for installer: Node in _active:
		if _active[installer] == id: return installer
	return null


func _on_progress(received: int, total: int, status: String, installer: Node) -> void:
	var id: String = str(_active.get(installer, ""))
	var index: int = _job_index(id)
	if index < 0: return
	var previous_state: String = str(_jobs[index].get("state", ""))
	_jobs[index]["received"] = received
	_jobs[index]["total"] = total
	_jobs[index]["status"] = status
	var lower: String = status.to_lower()
	if lower.contains("verifying"): _jobs[index]["state"] = "verifying"
	elif lower.contains("installing") or lower.contains("checking"):
		_jobs[index]["state"] = "installing"
	else: _jobs[index]["state"] = "downloading"
	var now: int = Time.get_ticks_msec()
	_sample_speed(index, id, received, now)
	if (str(_jobs[index].get("state", "")) != previous_state
		or now - _last_progress_emit_msec >= 100 or received >= total):
		_last_progress_emit_msec = now
		changed.emit()


# once a second, smoothed, so the number doesn't jump around with every chunk.
func _sample_speed(index: int, id: String, received: int, now: int) -> void:
	var sample: Array = _speed_sample.get(id, [])
	if sample.is_empty() or received < int(sample[1]):
		_speed_sample[id] = [now, received]
		return
	var elapsed: int = now - int(sample[0])
	if elapsed < 1000: return
	var rate: float = float(received - int(sample[1])) * 1000.0 / elapsed
	var previous: float = float(_jobs[index].get("speed", 0.0))
	_jobs[index]["speed"] = rate if previous <= 0.0 else previous * 0.6 + rate * 0.4
	_speed_sample[id] = [now, received]


func _on_finished(result: Dictionary, installer: Node) -> void:
	var id: String = str(_active.get(installer, ""))
	_active.erase(installer)
	_canceling.erase(id)
	_speed_sample.erase(id)
	var index: int = _job_index(id)
	if index >= 0:
		_jobs[index]["state"] = "finished"
		_jobs[index]["status"] = "Installed"
		_jobs[index]["received"] = int(_jobs[index].get("total", 0))
		_jobs[index]["result"] = result.duplicate(true)
	if _net != null: _net.community_pack_library_changed()
	changed.emit()
	_pump.call_deferred()


func _on_failed(message: String, installer: Node) -> void:
	var id: String = str(_active.get(installer, ""))
	var canceled: bool = _canceling.has(id)
	_active.erase(installer)
	_canceling.erase(id)
	_speed_sample.erase(id)
	var index: int = _job_index(id)
	if index >= 0:
		_jobs[index]["state"] = "canceled" if canceled else "failed"
		_jobs[index]["status"] = "Canceled" if canceled else "Download failed"
		_jobs[index]["error"] = "" if canceled else message
	changed.emit()
	_pump.call_deferred()


func _job_index(id: String) -> int:
	for index: int in _jobs.size():
		if str(_jobs[index].get("id", "")) == id: return index
	return -1


func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH): return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if parsed is Dictionary:
		_allow_online_downloads = bool(parsed.get("allow_online_downloads", false))


func _save_settings() -> void:
	var output: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if output == null: return
	output.store_string(JSON.stringify({"allow_online_downloads": _allow_online_downloads}, "  "))
	output.close()
