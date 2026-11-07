extends Node
const Constants = preload("res://scripts/game_constants.gd")
var failures := 0
func _ready() -> void:
	reparent.call_deferred(get_tree().root)
	await get_tree().process_frame
	await get_tree().process_frame
	var dummy := Node.new()
	get_tree().root.add_child(dummy)
	get_tree().current_scene = dummy
	call_deferred("run_test")
func check(ok: bool, label: String) -> void:
	if ok: print("[ROUND-PROGRESS] PASS ", label)
	else:
		failures += 1
		print("[ROUND-PROGRESS] FAIL ", label)
func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
func run_test() -> void:
	# Run under an isolated XDG_DATA_HOME.
	SaveManager.matches_played = 2
	SaveManager.rounds_won = 0
	SaveManager.color_index = 0
	SaveManager.save_profile()
	var cfg: Dictionary = GameManager.default_cfg()
	cfg["bots"] = 1
	GameManager.start_solo(cfg, false)
	await wait(4.5)
	var arena = get_tree().current_scene
	check(arena != null and arena.name == "Arena", "solo match starts")
	if arena == null or arena.name != "Arena":
		get_tree().quit(1)
		return
	var rm = arena.round_manager
	for p in get_tree().get_nodes_in_group("players"):
		p.process_mode = Node.PROCESS_MODE_DISABLED
	rm._end_round("draw")
	check(SaveManager.matches_played == 3 and SaveManager.is_color_unlocked(8), "finished match unlocks third-match reward")
	check(SaveManager.rounds_won == 0 and not SaveManager.is_color_unlocked(9), "draw is not a win")
	await wait(2.3)
	check(arena.hud._results != null, "results screen appears")
	if arena.hud._results != null:
		var labels: Array = arena.hud._results.find_children("*", "Label", true, false)
		var found := false
		for label in labels:
			if label.text.contains(Constants.get_color_name(8)):
				found = true
		check(found, "results screen announces newly unlocked color")
	GameManager.start_solo(cfg, true)
	await wait(4.5)
	arena = get_tree().current_scene
	rm = arena.round_manager
	rm._end_round("time_up")
	check(SaveManager.matches_played == 3 and SaveManager.rounds_won == 0, "practice does not increment progress")
	GameManager.start_solo(cfg, false)
	await wait(4.5)
	arena = get_tree().current_scene
	rm = arena.round_manager
	for p in get_tree().get_nodes_in_group("players"):
		p.process_mode = Node.PROCESS_MODE_DISABLED
	rm._eliminate(100, 2)
	rm._end_round("last_standing")
	check(SaveManager.matches_played == 4 and SaveManager.rounds_won == 1 and SaveManager.is_color_unlocked(9), "actual round win unlocks gold")
	print("[ROUND-PROGRESS] finished with %d failure(s)" % failures)
	get_tree().quit(1 if failures else 0)
