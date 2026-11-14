extends SceneTree
class BusyCatalog extends Node:
 var busy := true
 var requested := 0
 func is_busy(): return busy
 func cancel(): busy = false
 func fetch_detail(id): requested = id
func _initialize(): call_deferred("repro")
func repro():
 var browser = load("res://net/community_pack_browser.tscn").instantiate()
 root.add_child(browser)
 await process_frame
 browser._catalog.cancel()
 browser._catalog.free()
 var fake := BusyCatalog.new()
 browser.add_child(fake)
 browser._catalog = fake
 browser._selected = {"id":1,"name":"Old pack"}
 browser._select_record({"id":2,"name":"New selected pack","author":"Test"})
 if int(browser._selected.get("id",0)) != 2:
  print("FAIL: selecting a new row while details load leaves the previous pack selected")
  quit(1)
  return
 if fake.requested != 2:
  print("FAIL: replacement detail request not started")
  quit(1)
  return
 print("PASS: selection cancels old detail and loads the new pack")
 browser.free()
 quit()
