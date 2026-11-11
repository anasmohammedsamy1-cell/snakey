extends Node
## Automated single-process smoke test (practice mode, menus, lobby host/leave,
## settings, profile). Runs headless, prints [SMOKE] lines, exits 1 on failure.
##
##   godot --headless --path . res://tests/smoke_test.tscn

var _failures := 0


func _ready() -> void:
	call_deferred("_start")


func _start() -> void:
	# Detach from the "current scene" slot so scene changes don't free the runner.
	var placeholder := Node.new()
	placeholder.name = "TestPlaceholder"
	get_tree().root.add_child(placeholder)
	get_tree().current_scene = placeholder
	print("[SMOKE] start")
	await _run()
	print("[SMOKE] finished with %d failure(s)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Freezes everything that could push the test player around (bots, hammers, sweeper)
## so the input/cooldown/tile checks below are deterministic.
func _isolate_player(player: Node) -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if p != player:
			p.process_mode = Node.PROCESS_MODE_DISABLED
			p.global_position = Vector3(0, -60, 0)
	for o in get_tree().get_nodes_in_group("obstacles"):
		if not o.is_in_group("arena_crumble_tiles"):
			o.process_mode = Node.PROCESS_MODE_DISABLED


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[SMOKE] PASS  " + label)
	else:
		_failures += 1
		print("[SMOKE] FAIL  " + label)


func _run() -> void:
	await _wait(0.5)
	_check(SettingsManager.get_setting("camera_distance") != null, "settings loaded")
	_check(AudioServer.get_bus_index("SFX") >= 0 and AudioServer.get_bus_index("Music") >= 0, "audio buses created")

	# ---------------- Practice round
	GameManager.start_practice()
	await _wait(4.5)
	var arena := get_tree().current_scene
	_check(arena != null and arena.name == "Arena", "arena loaded")
	if arena == null or arena.name != "Arena":
		return
	var rm: Node = arena.get_node("RoundManager")
	var player: Node = rm.local_player
	_check(player != null, "local player spawned")
	_check(get_tree().get_nodes_in_group("players").size() == 4, "1 player + 3 bots spawned")
	_check(rm.state == 2, "round reached PLAYING (state=%d)" % rm.state)
	# v5: the floor is built from concentric tiers (Sudden Death drops them one by one), and the
	# obstacles stand on the tier they belong to, so they fall away with their own piece of floor.
	var obstacles: Node = arena.get_node("Obstacles")
	var tiers := 0
	var core: Node = null
	for child in obstacles.get_children():
		if str(child.name).begins_with("FloorTier"):
			tiers += 1
			core = child
	_check(tiers >= 3, "floor is built from at least 3 tiers (tiers=%d)" % tiers)
	_check(core != null and core.get_child_count() > 0, "the solid core tier exists and holds collision")
	_check(get_tree().get_nodes_in_group("arena_crumble_tiles").size() >= tiers,
		"every tier except the core can collapse")

	# Arena-event state is host-controlled and resettable.
	rm._apply_arena_event(1, 9.0)
	_check(rm.current_event == 1 and is_equal_approx(rm.event_remaining, 9.0), "arena event state applies")
	rm._apply_arena_event(0, 0.0)
	_check(rm.current_event == 0, "arena event clears cleanly")

	_isolate_player(player)
	var before: Vector3 = player.global_position
	Input.action_press("move_forward")
	await _wait(1.0)
	Input.action_release("move_forward")
	_check(before.distance_to(player.global_position) > 1.0, "keyboard movement moves the player")

	Input.action_press("jump")
	await _wait(0.1)
	Input.action_release("jump")
	await _wait(0.15)
	_check(player.velocity.y > 0.0 or not player.is_on_floor(), "jump works")
	await _wait(1.0)

	player.global_position = Vector3(0, 1.0, 0)
	player.velocity = Vector3.ZERO
	player._push_timer = 0.0
	await _wait(0.5)
	Input.action_press("push")
	await _wait(0.1)
	Input.action_release("push")
	await _wait(0.1)   # the release is processed on the next physics frame
	_check(player._push_timer > 0.0, "push triggers cooldown")
	player.apply_knockback(Vector3(8, 4, 0))
	_check(player._stun > 0.0, "knockback applies stun")
	await _wait(1.2)

	# NEW (written without an engine available - run to confirm): dash + rubber arm bookkeeping
	player._dash_cd = 0.0
	Input.action_press("dash")
	await _wait(0.1)
	Input.action_release("dash")
	_check(player._dash_cd > 0.0, "dash starts its cooldown")
	await _wait(0.5)
	player.arm_mode = 1
	player._push_timer = 0.0
	Input.action_press("push")
	await _wait(0.1)
	Input.action_release("push")
	await _wait(0.1)   # the release is processed on the next physics frame
	_check(int(rm.stats[player.peer_id]["attacks"]) >= 1, "host counted the grab attempt (miss or hit)")
	_check(player._push_timer > 0.0, "grab attempt consumes cooldown even on a miss")
	await _wait(2.0)
	player.arm_mode = 0

	# Falling tile
	player.global_position = Vector3(14.5, 1.0, 0.0)
	player.velocity = Vector3.ZERO
	await _wait(2.5)
	var tile: Node = obstacles.find_child("RingTile0", true, false)
	_check(tile.state != 0, "falling tile triggered by player contact (state=%d)" % tile.state)

	# Fall + practice respawn
	player.global_position = Vector3(0, -20, 0)
	await _wait(0.4)
	_check(not player.is_alive, "fall below arena detected")
	await _wait(2.5)
	_check(player.is_alive, "practice respawn after falling")
	_check(rm.falls.get(player.peer_id, 0) == 1, "fall counted")

	# Pause + settings overlay
	var hud: Node = arena.hud
	hud._toggle_pause(true)
	await _wait(0.3)
	_check(get_tree().paused, "practice pause freezes the tree")
	hud._open_settings()
	await _wait(0.4)
	_check(hud._settings_overlay != null, "settings overlay opened from pause")
	SettingsManager.apply_preset(0)
	SettingsManager.apply_preset(2)
	SettingsManager.set_setting("camera_distance", 8.0)
	_check(is_equal_approx(player.spring_arm.spring_length, 8.0), "camera distance setting applied live")
	SettingsManager.set_setting("camera_distance", 6.0)
	hud._toggle_pause(false)
	await _wait(0.3)
	_check(not get_tree().paused, "resume unpauses")

	# End of round
	rm.elapsed = rm.round_duration - 0.2
	await _wait(3.5)
	_check(rm.state == 3, "round ended on timer")
	_check(hud._results != null, "results screen shown")

	GameManager.leave_match()
	await _wait(2.0)
	_check(get_tree().current_scene.name == "MainMenu", "back to main menu")

	# ---------------- Lobby (host only)
	GameManager.go_to_lobby()
	await _wait(2.0)
	_check(get_tree().current_scene.name == "Lobby", "lobby loaded")
	var err: String = NetworkManager.host_game(24570)
	_check(err == "", "host_game succeeds: " + err)
	_check(NetworkManager.online and NetworkManager.is_host, "network session is online as host")
	_check(not NetworkManager.can_start(), "cannot start with a single player")
	await _wait(0.5)
	NetworkManager.leave()
	_check(not NetworkManager.online, "leave() closes the session")
	_check(NetworkManager.join_game("not an ip", 24570) != "", "invalid IP rejected")
	_check(NetworkManager.join_game("192.168.1.2", 80) != "", "invalid port rejected")

	# ---------------- Profile validation
	SaveManager.coins = 500                      # a name change after the first one costs coins
	SaveManager.set_profile("  Smoke Tester XXL  ", 3)
	_check(SaveManager.player_name == "Smoke Tester X", "long names are trimmed (got '%s')" % SaveManager.player_name)
	SaveManager.set_profile("   ", 1)
	_check(SaveManager.player_name == "Player", "empty names fall back to 'Player'")
	SaveManager.reset_defaults()

	GameManager.go_to_main_menu()
	await _wait(1.5)
