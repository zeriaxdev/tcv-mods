extends SceneTree
## Downloads a real 66 MB GameBanana pack through the installer worker at a capped
## 60 fps. Before the threaded worker this took ~15 s (4.5 MB/s); network-dependent.
const URL := "https://gamebanana.com/dl/1889549"
const SIZE := 66414452

func _initialize(): call_deferred("check_speed")
func check_speed():
 Engine.max_fps = 60
 var installer = root.get_node("CommunityPacks").downloads._installer
 DirAccess.make_dir_recursive_absolute(installer.DOWNLOAD_ROOT)
 var path: String = installer.DOWNLOAD_ROOT.path_join("speed-test.part")
 installer._file = {"size": SIZE}
 var started := Time.get_ticks_msec()
 assert(installer._start_download(URL, path) == OK)
 installer.set_process(false) # this test joins the worker itself
 while installer._thread.is_alive() and Time.get_ticks_msec() - started < 120000:
  await process_frame
 var secs := (Time.get_ticks_msec() - started) / 1000.0
 var outcome = installer._thread.wait_to_finish()
 installer._thread = null
 installer._busy = false
 assert(outcome is Dictionary and not outcome.has("error"), "download failed: %s" % str(outcome))
 var got := FileAccess.open(path, FileAccess.READ).get_length()
 DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
 assert(got == SIZE, "got %d of %d bytes" % [got, SIZE])
 print("PASS: %d bytes via redirect in %.1f s = %.1f MB/s at 60 fps" % [got, secs, got / secs / 1e6])
 quit()
