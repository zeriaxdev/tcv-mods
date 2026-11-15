extends SceneTree
func _initialize(): call_deferred("check_cancel")
func check_cancel():
 var installer = root.get_node("CommunityPacks").downloads._installer
 var server = TCPServer.new()
 assert(server.listen(0,"127.0.0.1") == OK)
 var port = server.get_local_port()
 DirAccess.make_dir_recursive_absolute(installer.DOWNLOAD_ROOT)
 assert(installer._start_download("http://127.0.0.1:%d/slow" % port, installer.DOWNLOAD_ROOT.path_join("cancel-test.part")) == OK)
 var peer: StreamPeerTCP
 for i in 120:
  if server.is_connection_available():
   peer = server.take_connection()
   break
  await process_frame
 assert(peer != null)
 peer.put_data("HTTP/1.1 200 OK\r\nContent-Length: 100000000\r\nConnection: close\r\n\r\nstart".to_utf8_buffer())
 await create_timer(0.15).timeout
 var started = Time.get_ticks_msec()
 installer.cancel()
 var elapsed = Time.get_ticks_msec() - started
 assert(elapsed < 100, "Cancel blocked for %d ms" % elapsed)
 assert(not installer.is_busy())
 for i in 30: await process_frame
 assert(installer._thread == null, "worker was not joined after cancel")
 assert(not FileAccess.file_exists(installer.DOWNLOAD_ROOT.path_join("cancel-test.part")), "partial file left behind")
 assert(root.get_node("CommunityPacks").downloads._active_id == "")
 peer.disconnect_from_host()
 server.stop()
 print("PASS: cancel returned in %d ms with a stalled server, worker joined, partial file removed" % elapsed)
 quit()
