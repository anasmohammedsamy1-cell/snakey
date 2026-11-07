extends Node
const Constants = preload("res://scripts/game_constants.gd")
var failures := 0
func _ready() -> void:
	call_deferred("run_test")
func check(ok: bool, label: String) -> void:
	if ok: print("[PROGRESS] PASS ", label)
	else:
		failures += 1
		print("[PROGRESS] FAIL ", label)
func run_test() -> void:
	# Run with an isolated XDG_DATA_HOME; this test deliberately writes profile.cfg.
	var legacy := ConfigFile.new()
	legacy.set_value("profile", "name", "Legacy")
	legacy.set_value("profile", "color", 6)
	legacy.set_value("stats", "matches", 2)
	legacy.set_value("stats", "wins", 0)
	check(legacy.save(SaveManager.PROFILE_PATH) == OK, "create legacy profile")
	SaveManager.load_profile()
	check(SaveManager.player_name == "Legacy" and SaveManager.color_index == 6 and SaveManager.matches_played == 2, "legacy profile loads without losing data")
	check(not SaveManager.is_color_unlocked(8) and not SaveManager.is_color_unlocked(9), "rewards locked before targets")
	SaveManager.set_profile("Legacy", 8)
	check(SaveManager.color_index == 6, "cannot equip locked reward")
	var menu = load("res://scenes/ui/customization_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	check(menu._color_grid.get_node("Color8").disabled and menu._color_grid.get_node("Color9").disabled, "locked swatches disabled in customization")
	menu.queue_free()
	await get_tree().process_frame
	SaveManager.record_match(false)
	check(SaveManager.matches_played == 3 and SaveManager.is_color_unlocked(8) and SaveManager.last_unlocked_colors.has(8), "third completed match unlocks mint")
	check(not SaveManager.is_color_unlocked(9), "loss does not unlock win color")
	SaveManager.set_profile("Legacy", 8)
	SaveManager.load_profile()
	check(SaveManager.color_index == 8 and SaveManager.matches_played == 3 and SaveManager.player_name == "Legacy", "unlocked selection and stats survive reload")
	SaveManager.record_match(true)
	check(SaveManager.rounds_won == 1 and SaveManager.is_color_unlocked(9) and SaveManager.last_unlocked_colors.has(9), "first win unlocks gold")
	SaveManager.set_profile("Legacy", 9)
	SaveManager.load_profile()
	check(SaveManager.color_index == 9 and SaveManager.rounds_won == 1, "win reward survives reload")
	menu = load("res://scenes/ui/customization_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	check(not menu._color_grid.get_node("Color8").disabled and not menu._color_grid.get_node("Color9").disabled, "unlocked colors selectable in customization")
	menu._select_color(8)
	check(menu._selected_color == 8, "unlocked color previews")
	menu.queue_free()
	await get_tree().process_frame
	SaveManager.reset_defaults()
	check(SaveManager.matches_played == 4 and SaveManager.rounds_won == 1 and SaveManager.is_color_unlocked(8) and SaveManager.is_color_unlocked(9), "reset appearance preserves achievements")
	SettingsManager.settings["language"] = "ar"
	check(Constants.get_color_name(8) == "أخضر النعناع", "reward name localized in Arabic")
	print("[PROGRESS] finished with %d failure(s)" % failures)
	get_tree().quit(1 if failures else 0)
