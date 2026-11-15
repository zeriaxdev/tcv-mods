extends SceneTree
func _initialize(): call_deferred("check_ui")
func settle():
 await process_frame
 await process_frame
 await process_frame
func check_ui():
 root.size = Vector2i(1152,648)
 var shell = load("res://scene/menu/_master/menu_master.tscn").instantiate()
 shell.stopgap_ignore_standard_instruction = true
 root.add_child(shell)
 shell.NewSlide("res://net/community_pack_browser.tscn",false)
 await settle()
 var browser = shell.get_node("SlideCapsule").get_child(0)
 browser._catalog.cancel()
 var panels = browser._list.get_parent().get_parent().get_parent()
 var initial = [panels.get_global_rect(),panels.get_parent().get_global_rect()]
 for mode in ["installed","downloads","browse"]:
  browser._set_view(mode)
  await settle()
  var actual = [panels.get_global_rect(),panels.get_parent().get_global_rect()]
  assert(actual == initial, "%s moves panels: %s -> %s" % [mode,initial,actual])
 print("PASS: tab switches preserve both panel rectangles")
 shell.free()
 quit()
