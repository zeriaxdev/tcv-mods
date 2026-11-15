extends SceneTree
# dev only: a fake extra player for trying the Online menu on one computer.
# Runs on the test project (its own data folder, ChoicerVoicerTests), joins a
# lobby and stays until you press Ctrl+C. It has no microphone, so it's for the
# lobby and pack sharing only: a real round would wait for its lines.
#
#   TCV_BOT_NAME      Bot        name in the lobby
#   TCV_BOT_HOST      127.0.0.1  where the lobby is
#   TCV_BOT_PORT      7654
#   TCV_BOT_READY     1          0 = stays not ready
#   TCV_BOT_PACKS     accept     answer to Dub Mode pack sharing: accept, decline or ignore
#   TCV_BOT_MY_PACKS  (unset)    1 = copy your packs first so the libraries match,
#                                0 = start with no packs. Unset leaves the bot's packs as they are.

func _initialize(): call_deferred("run")


func setting(key: String, default: String) -> String:
	var value: String = OS.get_environment(key)
	return default if value.is_empty() else value


func run():
	var net = root.get_node("Net")
	var bot_name: String = setting("TCV_BOT_NAME", "Bot")
	var host: String = setting("TCV_BOT_HOST", "127.0.0.1")
	var port: int = int(setting("TCV_BOT_PORT", str(net.PORT)))
	var answer: String = setting("TCV_BOT_PACKS", "accept")
	if not ["accept", "decline", "ignore"].has(answer):
		print("BOT: TCV_BOT_PACKS must be accept, decline or ignore")
		quit(1)
		return
	if OS.has_environment("TCV_BOT_MY_PACKS") and not set_up_packs(net, OS.get_environment("TCV_BOT_MY_PACKS") == "1"):
		quit(1)
		return
	var sync = net.get_node("PackSync")
	if answer == "accept": sync.enable_test_automation(true, false)

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
	while net.is_online():
		if sync._client_state != last_state:
			last_state = sync._client_state
			print("BOT: pack sharing: %s" % last_state)
		if answer == "decline" and last_state == "offered": sync.decline_download()
		await process_frame
	print("BOT: the lobby closed.")
	quit()


# the bot's packs live in the test data folder. "Yours" are cloned in (APFS
# clones on macOS, so they take no extra space) and never written to.
func set_up_packs(net: Node, copy_mine: bool) -> bool:
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
