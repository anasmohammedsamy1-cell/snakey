extends Node
# Autoload "Net": ENet host/join over LAN / hotspot. The host runs the whole simulation,
# clients only send their direction and receive full state snapshots (30/s).

signal lobby_changed
signal join_failed
signal disconnected
signal peer_left(index: int)

const PORT := 7777

var online := false
var is_host := false
var in_game := false
var peers: Array = []     # peer ids in player order (0 = player left mid-game)
var my_index := 0
var cfg := {}
var notice := ""
var game: Node = null     # set by game.gd


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(_on_conn_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)


func local_ips() -> Array:
	var out := []
	for a in IP.get_local_addresses():
		if a.count(".") != 3:
			continue
		var ok: bool = a.begins_with("192.168.") or a.begins_with("10.")
		if a.begins_with("172."):
			var second := int(a.split(".")[1])
			ok = second >= 16 and second <= 31
		if ok:
			out.append(a)
	return out


func host_game() -> bool:
	leave()
	var p := ENetMultiplayerPeer.new()
	if p.create_server(PORT, 3) != OK:
		notice = "Could not start server (port %d busy?)" % PORT
		return false
	multiplayer.multiplayer_peer = p
	online = true
	is_host = true
	in_game = false
	my_index = 0
	peers = [1]
	lobby_changed.emit()
	return true


func join_game(ip: String) -> bool:
	leave()
	var p := ENetMultiplayerPeer.new()
	if p.create_client(ip, PORT) != OK:
		notice = "Invalid address"
		return false
	multiplayer.multiplayer_peer = p
	online = true
	is_host = false
	in_game = false
	return true


func leave() -> void:
	if online and multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	if online:
		multiplayer.multiplayer_peer = null
	online = false
	is_host = false
	in_game = false
	peers = []
	game = null


func start_game() -> void:
	if not is_host or peers.size() < 2:
		return
	rpc_start.rpc({"rounds": Game.rounds_to_win, "wrap": Game.wrap})


# ---------- connection events ----------

func _on_peer_connected(id: int) -> void:
	if not is_host:
		return
	if in_game or peers.size() >= 4:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	peers.append(id)
	rpc_lobby.rpc(peers)
	lobby_changed.emit()


func _on_peer_disconnected(id: int) -> void:
	if not is_host:
		return
	var idx := peers.find(id)
	if idx < 0:
		return
	if in_game:
		peers[idx] = 0
		peer_left.emit(idx)
	else:
		peers.remove_at(idx)
		rpc_lobby.rpc(peers)
		lobby_changed.emit()


func _on_conn_failed() -> void:
	notice = "Could not connect - check the IP and that both devices are on the same hotspot/Wi-Fi"
	leave()
	join_failed.emit()


func _on_server_gone() -> void:
	notice = "Disconnected from host"
	leave()
	disconnected.emit()


# ---------- RPCs ----------

@rpc("authority", "call_remote", "reliable")
func rpc_lobby(list: Array) -> void:
	peers = list
	my_index = peers.find(multiplayer.get_unique_id())
	lobby_changed.emit()


@rpc("authority", "call_local", "reliable")
func rpc_start(c: Dictionary) -> void:
	cfg = c
	in_game = true
	get_tree().change_scene_to_file("res://scenes/game.tscn")


@rpc("authority", "call_remote", "unreliable_ordered")
func rpc_state(d: Dictionary) -> void:
	if game and game.has_method("apply_state"):
		game.apply_state(d)


@rpc("any_peer", "call_remote", "reliable")
func rpc_dir(d: Vector2i) -> void:
	if not is_host or game == null:
		return
	var idx := peers.find(multiplayer.get_remote_sender_id())
	if idx >= 0:
		game._set_dir(idx, d)
