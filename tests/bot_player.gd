extends SceneTree
# dev only: a fake extra player for trying the Online menu on one computer.
# Runs on the test project (its own data folder, ChoicerVoicerTests), joins a
# lobby and stays until you press Ctrl+C. In Dub Mode it claims characters,
# goes through the lines in order like everyone else and sends a short tone as
# its take for each of its lines. It has no game window, so Gameshow rounds
# would wait for it.
#
#   TCV_BOT_NAME          Bot        name in the lobby
#   TCV_BOT_HOST          127.0.0.1  where the lobby is
#   TCV_BOT_PORT          7654
#   TCV_BOT_READY         1          0 = stays not ready
#   TCV_BOT_PACKS         accept     answer to Dub Mode pack sharing: accept, decline or ignore
#   TCV_BOT_MY_PACKS      (unset)    1 = copy your packs first so the libraries match,
#                                    0 = start with no packs. Unset leaves the bot's packs as they are.
#   TCV_BOT_CHARACTERS    (unset)    characters to claim in Dub Mode, comma separated, or "all".
#                                    Unset claims none, so it only gets the lines nobody picked.
#   TCV_BOT_TAKE_SECONDS  3          how long each take is, and how long it "records" before sending

var net: Node
var metro: Node


func _initialize(): call_deferred("run")


func setting(key: String, default: String) -> String:
	var value: String = OS.get_environment(key)
	return default if value.is_empty() else value


func run():
	net = root.get_node("Net")
	metro = root.get_node("Metro")
	var bot_name: String = setting("TCV_BOT_NAME", "Bot")
	var host: String = setting("TCV_BOT_HOST", "127.0.0.1")
	var port: int = int(setting("TCV_BOT_PORT", str(net.PORT)))
	var answer: String = setting("TCV_BOT_PACKS", "accept")
	if not ["accept", "decline", "ignore"].has(answer):
		print("BOT: TCV_BOT_PACKS must be accept, decline or ignore")
		quit(1)
		return
	if OS.has_environment("TCV_BOT_MY_PACKS") and not set_up_packs(OS.get_environment("TCV_BOT_MY_PACKS") == "1"):
		quit(1)
		return
	var sync = net.get_node("PackSync")
	if answer == "accept": sync.enable_test_automation(true, false)
	net.dub_begin.connect(dub)

	if net.join_game(host, bot_name, "", port) != OK:
		print("BOT: couldn't start joining %s:%d" % [host, port])
		quit(1)
		return
	var deadline: int = Time.get_ticks_msec() + 15000
	while net.my_slot() < 0 and Time.get_ticks_msec() < deadline: await process_frame
	if net.my_slot() < 0:
		print("BOT: no seat after 15 s. Is a lobby open on %s:%d?" % [host, port])
		quit(1)
		return
	if setting("TCV_BOT_READY", "1") == "1": net.set_ready(true)
	print("BOT: %s joined %s:%d (ready=%s, pack sharing=%s, %d packs). Ctrl+C to stop." % [
		bot_name, host, port, setting("TCV_BOT_READY", "1") == "1", answer, net.voice_pack_manifest().size()])
	var last_state: String = ""
	var last_pack: Variant = metro.gameplay_resource_dub_mode
	while net.is_online():
		if sync._client_state != last_state:
			last_state = sync._client_state
			print("BOT: pack sharing: %s" % last_state)
		if answer == "decline" and last_state == "offered": sync.decline_download()
		# Net loads the dub pack on its own when the host starts; claim once it has.
		if metro.gameplay_resource_dub_mode != last_pack:
			last_pack = metro.gameplay_resource_dub_mode
			if last_pack != null: claim_characters(last_pack)
		await process_frame
	print("BOT: the lobby closed.")
	quit()


func claim_characters(pack) -> void:
	var all: PackedStringArray = []
	for clip in pack.omni_clip_array.data:
		for character: String in clip.dub_characters:
			if not character.is_empty() and not all.has(character): all.append(character)
	var wanted: String = setting("TCV_BOT_CHARACTERS", "")
	var mine: PackedStringArray = []
	for character: String in all:
		if wanted == "all" or Array(wanted.split(",")).map(func(s: String) -> String: return s.strip_edges()).has(character):
			mine.append(character)
	net.set_my_dub_characters(mine)
	print("BOT: dub pack loaded with %d lines. Characters: %s. Claimed: %s" % [
		pack.omni_clip_array.data.size(), ", ".join(all), ", ".join(mine) if not mine.is_empty() else "none"])


# the same order everyone else goes in: wait for the line in front, record our own.
func dub() -> void:
	net.take_pending_dub_begin()
	var owners: PackedInt32Array = net.dub_clip_owners
	var me: int = net.my_slot()
	var seconds: float = float(setting("TCV_BOT_TAKE_SECONDS", "3"))
	print("BOT: dub started, %d of %d lines are mine" % [Array(owners).count(me), owners.size()])
	for i: int in owners.size():
		if not net.is_online(): return
		if owners[i] == me:
			print("BOT: line %d is mine, recording for %.0f s" % [i + 1, seconds])
			await create_timer(seconds).timeout
			await net.submit_performance(i, fake_analysis(), fake_take(seconds))
			print("BOT: sent line %d" % (i + 1))
		else:
			print("BOT: waiting for %s on line %d" % [net.player_name_for_slot(owners[i]), i + 1])
			await net.await_performance(i, owners[i])
	net.report_dub_finished()
	print("BOT: all lines done")


# a quiet 220 Hz tone, so the bot's lines are audible when everyone watches.
func fake_take(seconds: float) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 44100
	var samples: int = int(seconds * wav.mix_rate)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i: int in samples:
		data.encode_s16(i * 2, int(3000.0 * sin(TAU * 220.0 * i / wav.mix_rate)))
	wav.data = data
	return wav


# the six level/pitch curves a real take carries. made up, so the bot's score means nothing.
func fake_analysis() -> Dictionary:
	var curve := PackedByteArray()
	for i: int in 64: curve.append(96 + (i * 7) % 64)
	return {"va": curve, "vm": curve, "vp": curve, "pa": curve, "pm": curve, "pp": curve}


# the bot's packs live in the test data folder. "Yours" are cloned in (APFS
# clones on macOS, so they take no extra space) and never written to.
func set_up_packs(copy_mine: bool) -> bool:
	var bot_packs: String = ProjectSettings.globalize_path("user://game/packs_voice").trim_suffix("/")
	if not bot_packs.contains("/ChoicerVoicerTests/"):
		print("BOT: refusing to touch %s, it isn't the test data folder" % bot_packs)
		return false
	if DirAccess.dir_exists_absolute(bot_packs) and OS.move_to_trash(bot_packs) != OK:
		print("BOT: couldn't clear the bot's old packs at %s" % bot_packs)
		return false
	if copy_mine:
		var my_packs: String = bot_packs.replace("/ChoicerVoicerTests/", "/ChoicerVoicer/")
		var flags: String = "-cR" if OS.get_name() == "macOS" else "-R"
		if OS.execute("cp", [flags, my_packs, bot_packs]) != 0:
			print("BOT: couldn't copy your packs from %s" % my_packs)
			return false
	else:
		DirAccess.make_dir_recursive_absolute(bot_packs)
	net._manifest_cache = {}
	return true
