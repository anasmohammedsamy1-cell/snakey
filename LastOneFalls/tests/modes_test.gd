extends Node
## Starts every map in every game mode (solo, with bots) for a few seconds and loads every scene.
## Fails on any bad state; script errors show up in the engine output.
## Run: godot --headless --path . res://tests/modes_test.tscn

var _fails := 0

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _check(ok: bool, label: String) -> void:
	if ok:
		print("[MODES] PASS  " + label)
	else:
		print("[MODES] FAIL  " + label)
		_fails += 1

func _ready() -> void:
	# Live under the root window so scene changes (which free the current scene) cannot free this test.
	reparent.call_deferred(get_tree().root)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = null
	await _wait(0.5)
	var scene_list := [] if OS.get_environment("MODES_SKIP_SCENES") == "1" else ["res://scenes/main_menu.tscn", "res://scenes/lobby.tscn", "res://scenes/ui/settings_menu.tscn",
			"res://scenes/ui/customization_menu.tscn", "res://scenes/ui/results_screen.tscn"]
	for path in scene_list:
		var ps := load(path) as PackedScene
		_check(ps != null, "loads " + path)
		if ps != null:
			var inst := ps.instantiate()
			add_child(inst)
			await _wait(0.4)
			_check(is_instance_valid(inst), "runs " + path)
			inst.queue_free()
			get_tree().paused = false
	for combo in [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [1, 0], [1, 2], [2, 5], [2, 6], [0, 12], [2, 13], [2, 14], [2, 15]]:
		var cfg: Dictionary = GameManager.default_cfg()
		cfg["mode"] = combo[0]
		cfg["map"] = combo[1]
		cfg["bots"] = 4
		cfg["round_time"] = 30.0
		print("[MODES] starting ", combo)
		GameManager.start_solo(cfg, false)
		await _wait(5.0)
		var arena := get_tree().current_scene
		var ok := arena != null and arena.name == "Arena"
		_check(ok, "mode %d map %d: arena loaded" % [combo[0], combo[1]])
		if ok:
			var rm = arena.get_node("RoundManager")
			_check(int(rm.state) == 2, "mode %d map %d: round PLAYING (state=%d)" % [combo[0], combo[1], int(rm.state)])
			_check(get_tree().get_nodes_in_group("players").size() >= 2, "mode %d map %d: players spawned" % [combo[0], combo[1]])
	print("[MODES] finished with %d failure(s)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
