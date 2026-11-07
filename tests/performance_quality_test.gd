extends Node
## Validates low-quality construction and switching, not actual frame rate.
var failures := 0
func _ready() -> void:
	reparent.call_deferred(get_tree().root)
	await get_tree().process_frame
	await get_tree().process_frame
	var placeholder := Node.new()
	get_tree().root.add_child(placeholder)
	get_tree().current_scene = placeholder
	call_deferred("run_test")
func check(ok: bool, label: String) -> void:
	if ok:
		print("[PERF] PASS ", label)
	else:
		failures += 1
		print("[PERF] FAIL ", label)
func run_test() -> void:
	var saved: Dictionary = SettingsManager.settings.duplicate(true)
	SettingsManager.apply_preset(SettingsManager.PRESET_LOW)
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child(menu)
	await get_tree().process_frame
	check(menu._bg != null and menu._bg.texture != null, "menu uses the new background artwork")
	check(menu._menu_buttons.size() == 9, "menu keeps all nine actions available")
	check(not menu._ambient_enabled, "low menu keeps ambient animation disabled")
	SettingsManager.apply_preset(SettingsManager.PRESET_HIGH)
	await get_tree().process_frame
	check(menu._ambient_enabled, "high menu enables ambient animation")
	SettingsManager.apply_preset(SettingsManager.PRESET_LOW)
	await get_tree().process_frame
	check(not menu._ambient_enabled, "switch back to low stops ambient animation")
	menu.free()
	GameManager.start_practice()
	await get_tree().create_timer(4.5).timeout
	var arena = get_tree().current_scene
	check(arena != null and arena.name == "Arena", "practice arena loads with low preset")
	if arena != null and arena.name == "Arena":
		check(arena._poof == null and arena._splash == null and arena._confetti == null, "effects nodes not allocated while disabled")
		var player = arena.round_manager.local_player
		check(player != null and player.land_particles == null, "player particles not allocated when effects disabled")
		SettingsManager.set_setting("effects", true, false)
		check(arena._poof != null and arena._splash != null and arena._confetti != null, "enabling effects builds arena particles")
		if player != null:
			player._on_landed()
			check(player.land_particles != null, "enabling effects creates player particles when needed")
	SettingsManager.settings = saved
	SettingsManager.apply_all()
	SettingsManager.save_settings()
	print("[PERF] finished with %d failure(s)" % failures)
	get_tree().quit(1 if failures else 0)
