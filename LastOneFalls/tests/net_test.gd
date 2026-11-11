extends Node
## Two-process LAN multiplayer test over a real ENet connection.
## Terminal 1:  godot --headless --path . res://tests/net_test.tscn -- host
## Terminal 2:  godot --headless --path . res://tests/net_test.tscn -- join 127.0.0.1
##   (or "-- join discover" to find the room through LAN discovery instead of an IP)
## Each process prints [NET:role] lines and exits with code 1 on failure.

const PORT := 24599

var role := "host"
var address := "127.0.0.1"
var _failures := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		role = args[0]
	if args.size() > 1:
		address = args[1]
	call_deferred("_start")


func _start() -> void:
	# Detach from the "current scene" slot so scene changes don't free the runner.
	var placeholder := Node.new()
	placeholder.name = "TestPlaceholder"
	get_tree().root.add_child(placeholder)
	get_tree().current_scene = placeholder
	print("[NET:%s] start" % role)
	if role == "host":
		await _run_host()
	else:
		await _run_client()
	print("[NET:%s] finished with %d failure(s)" % [role, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[NET:%s] PASS  %s" % [role, label])
	else:
		_failures += 1
		print("[NET:%s] FAIL  %s" % [role, label])


func _scene_name() -> String:
	var s := get_tree().current_scene
	return s.name if s != null else ""


func _wait_until(predicate: Callable, timeout: float) -> bool:
	var waited := 0.0
	while waited < timeout:
		if predicate.call():
			return true
		await _wait(0.25)
		waited += 0.25
	return predicate.call()


# ---------------------------------------------------------------------------

func _run_host() -> void:
	await _wait(0.5)
	GameManager.go_to_lobby()
	await _wait(1.5)
	var err: String = NetworkManager.host_game(PORT)
	_check(err == "", "host_game: " + err)
	var ok := await _wait_until(func() -> bool: return NetworkManager.players.size() >= 2, 30.0)
	_check(ok, "client registered in the lobby (players=%d)" % NetworkManager.players.size())
	ok = await _wait_until(func() -> bool: return NetworkManager.can_start(), 10.0)
	_check(ok, "client toggled ready -> host can start")
	NetworkManager.start_match()
	await _wait(5.0)
	_check(_scene_name() == "Arena", "host arena loaded")
	if _scene_name() != "Arena":
		return
	var rm: Node = get_tree().current_scene.get_node("RoundManager")
	_check(rm.players.size() == 2, "two players spawned on host")
	_check(rm.state == 2, "round PLAYING on host (state=%d)" % rm.state)
	var client_id := 0
	for id in rm.players.keys():
		if int(id) != 1:
			client_id = int(id)
	var puppet: Node = rm.players.get(client_id)
	_check(puppet != null and not puppet.is_multiplayer_authority(), "client player is a remote puppet on host")
	await _wait(2.0)
	_check(puppet != null and puppet._net_received, "host receives position updates from client")
	# Host-validated push delivered to the client's own simulation
	var me: Node = rm.local_player
	if puppet != null:
		me.global_position = puppet.global_position + Vector3(1.0, 0, 0)
		await _wait(0.3)
		rm._server_push(1, client_id, Vector3(-1, 0, 0))
	# The client teleports itself below the arena -> host must eliminate it and end the round
	ok = await _wait_until(func() -> bool: return rm.state == 3, 20.0)
	_check(ok, "round ended after the client fell (state=%d)" % rm.state)
	_check(int(rm.ranks.get(1, 0)) == 1, "host ranked 1st")
	_check(NetworkManager.get_score(1) == 3, "host awarded 3 points (score=%d)" % NetworkManager.get_score(1))
	await _wait(2.5)
	NetworkManager.return_to_lobby()
	await _wait(2.0)
	_check(_scene_name() == "Lobby", "host returned to lobby")
	await _wait(2.5)
	NetworkManager.leave()
	_check(not NetworkManager.online, "host closed the session")


func _run_client() -> void:
	await _wait(3.0)
	GameManager.go_to_lobby()
	await _wait(1.5)
	var err := ""
	if address == "discover":
		# No IP typed: find the room through UDP discovery (loopback target) and join it with one call.
		NetworkManager.discovery.extra_targets = ["127.0.0.1"]
		NetworkManager.discovery.start_browsing()
		var found := await _wait_until(func() -> bool: return not NetworkManager.discovery.rooms.is_empty(), 15.0)
		_check(found, "room discovered automatically")
		if not found:
			return
		var room: Dictionary = NetworkManager.discovery.get_room_list()[0]
		NetworkManager.discovery.stop()
		NetworkManager.join_room(room)
	else:
		err = NetworkManager.join_game(address, PORT)
	_check(err == "", "join: " + err)
	var ok := await _wait_until(func() -> bool: return NetworkManager.online and NetworkManager.players.size() >= 2, 20.0)
	_check(ok, "client sees both players in the lobby (players=%d)" % NetworkManager.players.size())
	NetworkManager.set_ready(true)
	ok = await _wait_until(func() -> bool: return _scene_name() == "Arena", 25.0)
	_check(ok, "client arena loaded when host started the match")
	if not ok:
		return
	await _wait(3.5)
	var rm: Node = get_tree().current_scene.get_node("RoundManager")
	_check(rm.state == 2, "client mirrored PLAYING state (state=%d)" % rm.state)
	_check(rm.players.size() == 2, "two players spawned on client")
	var me: Node = rm.local_player
	_check(me != null and me.is_multiplayer_authority(), "client controls its own player")
	Input.action_press("move_forward")
	await _wait(1.5)
	Input.action_release("move_forward")
	var host_puppet: Node = rm.players.get(1)
	_check(host_puppet != null and host_puppet._net_received, "client receives host position updates")
	var got_push := false
	var waited := 0.0
	while waited < 7.0:
		if me._knockback.length() > 0.1 or me._stun > 0.0:
			got_push = true
			break
		await _wait(0.1)
		waited += 0.1
	_check(got_push, "host-validated push reached the client")
	me.global_position = Vector3(me.global_position.x, -14.0, me.global_position.z)
	ok = await _wait_until(func() -> bool: return rm.state == 3, 20.0)
	_check(ok, "client received round end (state=%d)" % rm.state)
	_check(not me.is_alive, "client player eliminated after falling")
	ok = await _wait_until(func() -> bool: return _scene_name() == "Lobby", 20.0)
	_check(ok, "client returned to lobby with the host")
	ok = await _wait_until(func() -> bool: return not NetworkManager.online, 15.0)
	_check(ok, "client handled host leaving (session closed)")
