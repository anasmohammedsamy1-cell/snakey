extends Node
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
		print("[FLOW] PASS ", label)
	else:
		failures += 1
		print("[FLOW] FAIL ", label)
func run_test() -> void:
	GameManager.start_tutorial()
	await get_tree().create_timer(1.5).timeout
	var tutorial := get_tree().current_scene
	check(tutorial != null and tutorial.name == "Tutorial", "menu starts standalone tutorial")
	if tutorial != null and tutorial.name == "Tutorial":
		var buttons := tutorial.find_children("ExitTutorial", "Button", true, false)
		check(buttons.size() == 1, "exit button exists")
		if buttons.size() == 1:
			buttons[0].pressed.emit()
			await get_tree().create_timer(1.5).timeout
			check(get_tree().current_scene != null and get_tree().current_scene.scene_file_path == GameManager.SCENE_MAIN_MENU, "exit returns to main menu")
	print("[FLOW] finished with %d failure(s)" % failures)
	get_tree().quit(1 if failures else 0)
