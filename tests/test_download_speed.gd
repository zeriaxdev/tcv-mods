extends SceneTree
## Downloads a real GameBanana pack through the installer worker at a capped 60 fps
## and checks the result against GameBanana's MD5 (so mirror switches that resume
## mid-file are proven byte-exact). Network-dependent.
## Usage: ... --script tests/test_download_speed.gd [-- <file id> <size> <md5>]
## Default: 66 MB "Maine's death" pack.

func _initialize(): call_deferred("check_speed")
func check_speed():
 var args := OS.get_cmdline_user_args()
 var url := "https://gamebanana.com/dl/%s" % (args[0] if args.size() > 0 else "1889549")
 var size := int(args[1]) if args.size() > 1 else 66414452
 var md5: String = args[2] if args.size() > 2 else ""
 Engine.max_fps = 60
 var installer = root.get_node("CommunityPacks").downloads._installer
 DirAccess.make_dir_recursive_absolute(installer.DOWNLOAD_ROOT)
 var path: String = installer.DOWNLOAD_ROOT.path_join("speed-test.part")
 installer._file = {"size": size}
 var started := Time.get_ticks_msec()
 assert(installer._start_download(url, path) == OK)
 installer.set_process(false) # this test joins the worker itself
 while installer._thread.is_alive() and Time.get_ticks_msec() - started < 300000:
  await process_frame
 installer._cancel_requested = true # never block forever on a hung worker
 var secs := (Time.get_ticks_msec() - started) / 1000.0
 var outcome = installer._thread.wait_to_finish()
 installer._thread = null
 installer._busy = false
 assert(outcome is Dictionary and not outcome.has("error"), "download failed: %s" % str(outcome))
 var got := FileAccess.open(path, FileAccess.READ).get_length()
 var actual_md5 := FileAccess.get_md5(path)
 DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
 assert(got == size, "got %d of %d bytes" % [got, size])
 assert(md5.is_empty() or actual_md5 == md5, "checksum mismatch: %s vs %s" % [actual_md5, md5])
 print("PASS: %d bytes%s in %.1f s = %.1f MB/s at 60 fps" % [got, ", MD5 matches" if not md5.is_empty() else "", secs, got / secs / 1e6])
 quit()
