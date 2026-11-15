extends SceneTree
class FakeQueue extends Node:
 func get_jobs() -> Array[Dictionary]:
  return [{"id":"one","mod":{"name":"Alpha pack","author":"First"},"file":{"name":"alpha.zip"},"state":"finished"},{"id":"two","mod":{"name":"Beta pack","author":"Second"},"file":{"name":"beta.zip"},"state":"failed"}]
func _initialize():
 create_timer(12).timeout.connect(func(): quit(1))
 call_deferred("check_ui")
func check_ui():
 root.size = Vector2i(1152,648)
 var shell = load("res://scene/menu/_master/menu_master.tscn").instantiate()
 shell.stopgap_ignore_standard_instruction = true
 root.add_child(shell)
 shell.NewSlide("res://net/community_pack_browser.tscn",false)
 await process_frame
 var browser = shell.get_node("SlideCapsule").get_child(0)
 browser._catalog.cancel()
 var original_queue = browser._downloads
 var fake = FakeQueue.new()
 browser._downloads = fake
 browser._show_downloads()
 assert(browser._search_tools.visible)
 browser._search.text = "BETA"
 browser._search.text_changed.emit("BETA")
 assert(browser._list.get_root().get_child_count() == 1)
 assert(browser._list.get_root().get_first_child().get_text(0) == "Beta pack")
 browser._search.text = "missing"
 browser._search.text_changed.emit("missing")
 assert(browser._list.get_root().get_first_child().get_text(0) == "No matching downloads")
 browser._show_installed()
 assert(browser._search_tools.visible)
 browser._search.text = "zz-no-such-pack"
 browser._search.text_changed.emit("zz-no-such-pack")
 assert(browser._list.get_root().get_first_child().get_text(0) == "No matching packs")
 browser._show_downloads()
 assert(browser._search.text == "missing")
 assert(not browser._nav_tabs.large_buttons)
 for tab in browser._nav_tabs.get_children():
  if tab.has_method("GradHover"): assert(tab.custom_minimum_size.y == 48 and tab.button_type == tab.BUTTONTYPE.SMALL and tab.size_flags_horizontal == Control.SIZE_EXPAND_FILL)
 browser._downloads = original_queue
 fake.free()
 shell.free()
 print("PASS: larger native tabs, case-insensitive local searches and per-tab search memory")
 quit()
