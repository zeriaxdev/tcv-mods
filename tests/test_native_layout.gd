extends SceneTree
func _initialize(): call_deferred("check_layout")
func check_layout():
 root.size = Vector2i(1152, 648)
 var shell = load("res://scene/menu/_master/menu_master.tscn").instantiate()
 shell.stopgap_ignore_standard_instruction = true
 root.add_child(shell)
 shell.NewSlide("res://net/community_pack_browser.tscn", false)
 await process_frame
 await process_frame
 var browser = shell.get_node("SlideCapsule").get_child(0)
 browser._catalog.cancel()
 browser._selected = {"id":42,"name":"A very long pack title for testing the narrow supported layout"}
 browser._on_detail_loaded({"id":42,"name":browser._selected.name,"author":"Test","files":[{"id":1,"name":"a-long-pack-file.zip","size":100}]})
 await process_frame
 await process_frame
 for control in [browser._list, browser._install_button, browser._open_button, browser._rated, browser._sort]:
  var rect = control.get_global_rect()
  assert(rect.position.x >= 0 and rect.end.x <= 1153, "%s overflows horizontally: %s" % [control,rect])
  assert(rect.position.y >= 48 and rect.end.y <= 592, "%s overlaps the menu bars: %s" % [control,rect])
 browser._request_uninstall({"mod_id":42,"name":"A long pack title that must wrap inside the uninstall confirmation"})
 await process_frame
 assert(browser._uninstall_dialog.size.x <= 1152)
 browser._uninstall_dialog.hide()
 shell.NewSlide("res://net/lobby.tscn", false)
 await process_frame
 await process_frame
 var lobby = shell.get_node("SlideCapsule").get_child(0)
 for tab in [0, 1]:
  lobby._show_tab(tab)
  await process_frame
  await process_frame
  for control in [lobby.name_field,lobby.host_button,lobby._address_rows,lobby.player_rows,lobby.ready_button,lobby.status_label]:
   if not control.is_visible_in_tree(): continue
   var rect = control.get_global_rect()
   assert(rect.end.x <= 1153 and rect.end.y <= 592, "Online content overflow: %s %s" % [control,rect])
 print("1152x648 menu bounds and dialog checks passed")
 shell.free()
 quit()
