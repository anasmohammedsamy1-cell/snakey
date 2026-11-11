extends Node
const PORT := 24640
var role := "host"
var failures := 0
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	role = args[0] if args.size() else "host"
	call_deferred("run_test")
func check(ok: bool, label: String) -> void:
	if ok: print("[COLOR:%s] PASS %s" % [role, label])
	else:
		failures += 1
		print("[COLOR:%s] FAIL %s" % [role, label])
func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
func wait_for(fn: Callable, seconds: float) -> bool:
	for i in int(seconds * 10):
		if fn.call(): return true
		await wait(0.1)
	return fn.call()
func run_test() -> void:
	var dummy := Node.new()
	get_tree().root.add_child(dummy)
	get_tree().current_scene = dummy
	if role == "host":
		SaveManager.color_index = 8
		SaveManager.detail_color_index = -1          # classic metal
		check(NetworkManager.host_game(PORT, "Color Test", 3) == "", "host starts with mint")
		var ready := await wait_for(func() -> bool: return NetworkManager.can_start(), 12.0)
		check(ready, "client joined and ready")
		var client_id := 0
		for id in NetworkManager.players:
			if int(id) != 1: client_id = int(id)
		check(client_id != 0 and NetworkManager.players.has(client_id) and int(NetworkManager.players[client_id]["color"]) == 9, "host receives client's gold color")
		check(client_id != 0 and int(NetworkManager.players[client_id].get("detail", -1)) == 5, "host receives client's grape detail color")
		NetworkManager.start_match()
		await wait(5.0)
		var arena = get_tree().current_scene
		check(arena != null and arena.name == "Arena", "host loads arena")
		if arena != null and arena.name == "Arena":
			check(arena.round_manager.players.has(client_id) and int(arena.round_manager.players[client_id].color_index) == 9, "remote player remains gold in match")
			check(arena.round_manager.players.has(client_id) and int(arena.round_manager.players[client_id].detail_color_index) == 5, "remote player keeps grape detail color in match")
		await wait(2.0)
	else:
		SaveManager.color_index = 9
		SaveManager.detail_color_index = 5             # grape screws & gaps
		await wait(1.0)
		check(NetworkManager.join_game("127.0.0.1", PORT) == "", "client starts joining with gold")
		var joined := await wait_for(func() -> bool: return NetworkManager.players.size() >= 2 and not NetworkManager.is_busy(), 12.0)
		check(joined, "client accepted")
		if joined:
			check(int(NetworkManager.players[1]["color"]) == 8, "client receives host's mint color")
			NetworkManager.set_ready(true)
		var loaded := await wait_for(func() -> bool: return get_tree().current_scene != null and get_tree().current_scene.name == "Arena", 15.0)
		check(loaded, "client loads arena")
		if loaded:
			await wait(3.5)
			check(int(get_tree().current_scene.round_manager.players[1].color_index) == 8, "host remains mint in client match")
			await wait(3.0)
	NetworkManager.leave()
	print("[COLOR:%s] finished with %d failure(s)" % [role, failures])
	get_tree().quit(1 if failures else 0)
