extends SceneTree
func _initialize(): call_deferred("repro")
func repro():
 var client = load("res://net/gamebanana_client.gd").new()
 root.add_child(client)
 var observed := [false]
 client.page_loaded.connect(func(_payload): observed[0] = true)
 client.detail_loaded.connect(func(_payload): observed[0] = true)
 client.request_failed.connect(func(_message): observed[0] = true)
 client.cancel()
 client._on_request_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), '{"_aRecords":[],"_aMetadata":{}}'.to_utf8_buffer())
 if observed[0]:
  print("FAIL: a canceled request still changes browser state")
  quit(1)
  return
 print("PASS: canceled request result ignored")
 client.free()
 quit()
