extends Control
# Online lobby: host a game or join one by IP (same hotspot / Wi-Fi).

var box: VBoxContainer
var ip_edit: LineEdit
var start_btn: Button


func _ready() -> void:
	Net.leave()
	var bg := ColorRect.new()
	bg.color = Color("#0b1220")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	Net.lobby_changed.connect(_show_room)
	Net.join_failed.connect(_show_home)
	Net.disconnected.connect(_show_home)
	_show_home()


func _clear() -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _show_home() -> void:
	_clear()
	box.add_child(Game.make_label("ONLINE", 72))
	box.add_child(Game.make_label("Both devices on the same hotspot / Wi-Fi", 26))
	if Net.notice != "":
		var n := Game.make_label(Net.notice, 26)
		n.add_theme_color_override("font_color", Color("#fb7185"))
		box.add_child(n)
		Net.notice = ""
	box.add_child(Game.make_button("HOST GAME", _host))
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "Host IP, e.g. 192.168.43.1"
	ip_edit.text = Game.last_ip
	ip_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	ip_edit.custom_minimum_size = Vector2(560, 70)
	ip_edit.add_theme_font_size_override("font_size", 32)
	box.add_child(ip_edit)
	box.add_child(Game.make_button("JOIN", _join))
	box.add_child(Game.make_button("BACK", _back))


func _show_room() -> void:
	_clear()
	box.add_child(Game.make_label("LOBBY", 72))
	if Net.is_host:
		var ips := Net.local_ips()
		var t := "Friends join with IP: %s  (port %d)" % [", ".join(ips) if ips.size() > 0 else "unknown - check Wi-Fi/hotspot", Net.PORT]
		box.add_child(Game.make_label(t, 28))
	var names := ""
	for i in Net.peers.size():
		names += "%s%s%s\n" % [Game.NAMES[i], " (host)" if i == 0 else "", " - you" if i == Net.my_index else ""]
	var l := Game.make_label(names, 36)
	box.add_child(l)
	if Net.is_host:
		start_btn = Game.make_button("START", Net.start_game)
		start_btn.disabled = Net.peers.size() < 2
		box.add_child(start_btn)
		box.add_child(Game.make_label("Speed and rounds come from your Settings", 22))
	else:
		box.add_child(Game.make_label("Waiting for the host to start...", 30))
	box.add_child(Game.make_button("LEAVE", _leave))


func _host() -> void:
	if Net.host_game():
		_show_room()
	else:
		_show_home()


func _join() -> void:
	var ip := ip_edit.text.strip_edges()
	if ip.is_empty():
		return
	Game.last_ip = ip
	Game.save_settings()
	if Net.join_game(ip):
		_clear()
		box.add_child(Game.make_label("Connecting to %s ..." % ip, 40))
		box.add_child(Game.make_button("CANCEL", _leave))
	else:
		_show_home()


func _leave() -> void:
	Net.leave()
	_show_home()


func _back() -> void:
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
