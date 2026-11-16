extends SceneTree
## Installs a real GameBanana RAR or 7z through the same validator as ZIPs, into a temp voice folder.
## Usage: Godot --headless --path <patched-game> --script tests/test_rar_install.gd -- /path/to/pack.rar (or .7z)
func _initialize(): call_deferred("check_rar")
func check_rar():
 var source: String = OS.get_cmdline_user_args()[0]
 var installer: GDScript = load("res://net/community_pack_installer.gd")
 var ext: String = source.get_extension().to_lower()
 DirAccess.make_dir_recursive_absolute(installer.DOWNLOAD_ROOT)
 var archive: String = installer.DOWNLOAD_ROOT.path_join("999999.%s.part" % ext)
 assert(DirAccess.copy_absolute(source, ProjectSettings.globalize_path(archive)) == OK)
 var voice_root: String = OS.get_cache_dir().path_join("tcv-rar-test-%d" % Time.get_ticks_msec())
 DirAccess.make_dir_recursive_absolute(voice_root)
 var result: Dictionary = installer._validate_and_extract(archive, {"id": 999999, "name": "RAR test pack"}, {"id": 999999, "name": "pack." + ext}, voice_root, false)
 DirAccess.remove_absolute(ProjectSettings.globalize_path(archive))
 assert(not result.has("error"), "%s install failed: %s" % [ext, str(result.get("error"))])
 var installed: String = str(result.get("path", ""))
 assert(FileAccess.file_exists(installed.path_join("dub_video.ogv")), "no dub_video.ogv in %s" % installed)
 assert(not FileAccess.file_exists(ProjectSettings.globalize_path(installer.DOWNLOAD_ROOT.path_join("999999.%s.converted.zip" % ext))), "converted zip left behind")
 var files := DirAccess.get_files_at(installed)
 OS.move_to_trash(voice_root)
 print("PASS: %s installed %d files to %s" % [ext, files.size(), installed.get_file()])
 quit()
