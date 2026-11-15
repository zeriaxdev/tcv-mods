extends Node
# Optional multiplayer bridge: the catalog can run without the Net autoload.
const VERSION := "0.1.0"
var downloads: Node
var _entry: Control

func _ready() -> void:
 downloads = preload("res://net/community_pack_queue.gd").new()
 downloads.configure(self)
 add_child(downloads)
 var layer := CanvasLayer.new()
 layer.layer = 128
 add_child(layer)
 _entry = preload("res://net/choicer_button.gd").new()
 _entry.text = "Community packs"
 _entry.focus_mode = Control.FOCUS_NONE
 _entry.pressed.connect(open_browser)
 layer.add_child(_entry)
 var timer := Timer.new()
 timer.wait_time = 0.4
 timer.timeout.connect(_update_entry)
 add_child(timer)
 timer.start()
 _update_entry()

func is_online() -> bool:
 var net := get_tree().root.get_node_or_null("Net")
 return net != null and net.is_online()

func community_pack_library_changed() -> void:
 var net := get_tree().root.get_node_or_null("Net")
 if net != null: net.community_pack_library_changed()

func open_browser() -> void:
 var menu := _menu()
 if menu == null: return
 var slides: Node = menu.get_node("SlideCapsule")
 var previous: String = slides.get_child(0).scene_file_path if slides.get_child_count() else "res://scene/menu/home/menu_home.tscn"
 if previous.ends_with("community_pack_browser.tscn"): return
 menu.NewSlide("res://net/community_pack_browser.tscn", false)
 var page: Node = slides.get_child(-1)
 page.menu_data = page.menu_data.duplicate()
 page.menu_data.back_path = previous
 page.menu_data.assume_path = false
 page.closed.connect(menu.new_slide_from_data)

func _menu() -> Node:
 var world := get_tree().root.get_node_or_null("World")
 if world == null or world.blackout.visible: return null
 for menu: Node in world.primary_capsule.get_children():
  if menu.scene_file_path.contains("menu_master"): return menu
 return null

func _update_entry() -> void:
 _entry.hide()
 if get_tree().root.has_node("Net"): return
 var menu := _menu()
 if menu == null: return
 var slides: Node = menu.get_node("SlideCapsule")
 if slides.get_child_count() == 0: return
 if not slides.get_child(0).scene_file_path.ends_with("menu_home.tscn"): return
 _entry.show()
 _entry.size = _entry.get_combined_minimum_size()
 _entry.position = Vector2(get_viewport().get_visible_rect().size.x - _entry.size.x - 28, 92)
