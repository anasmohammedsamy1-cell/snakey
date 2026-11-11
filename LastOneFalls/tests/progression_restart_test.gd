extends Node
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var role := args[0] if args.size() else "read"
	if role == "write":
		SaveManager.matches_played = 2
		SaveManager.rounds_won = 0
		SaveManager.color_index = 0
		SaveManager.record_match(true)
		SaveManager.set_profile("Restart", 9)
		print("[RESTART] wrote profile")
		get_tree().quit(0)
	else:
		var ok := SaveManager.matches_played == 3 and SaveManager.rounds_won == 1 and SaveManager.color_index == 9 and SaveManager.player_name == "Restart"
		print("[RESTART] %s profile loaded in fresh process" % ("PASS" if ok else "FAIL"))
		get_tree().quit(0 if ok else 1)
