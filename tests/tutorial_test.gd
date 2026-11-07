extends Node
const TutorialScene := preload("res://scenes/tutorial.tscn")
var failures := 0
func _ready() -> void:
	call_deferred("run_test")
func check(ok: bool, label: String) -> void:
	if ok:
		print("[TUTORIAL] PASS ", label)
	else:
		failures += 1
		print("[TUTORIAL] FAIL ", label)
func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
func run_test() -> void:
	var tutorial = TutorialScene.instantiate()
	get_tree().root.add_child(tutorial)
	await wait(0.6)
	check(tutorial.step == 0 and tutorial.player.touch_controls != null, "tutorial starts with real player and touch controls")
	Input.action_press("jump")
	await wait(0.12)
	Input.action_release("jump")
	await wait(0.1)
	check(tutorial.step == 0, "jump cannot skip movement step")
	Input.action_press("move_forward")
	await wait(1.2)
	Input.action_release("move_forward")
	await wait(0.2)
	check(tutorial.step == 1, "moving advances to jump")
	await wait(0.7)
	Input.action_press("jump")
	await wait(0.15)
	Input.action_release("jump")
	await wait(0.15)
	check(tutorial.step == 2, "successful jump advances to push")
	Input.action_press("push")
	await wait(0.2)
	Input.action_release("push")
	await wait(0.2)
	check(tutorial.step == 3, "accepted push completes tutorial")
	check(tutorial._message.text == GameManager.t("tutorial_complete"), "completion feedback visible")
	tutorial.queue_free()
	await get_tree().process_frame
	var ar = preload("res://scripts/locale.gd").t("tutorial_move", "ar")
	check(ar.contains("حرّك"), "Arabic tutorial text exists")
	print("[TUTORIAL] finished with %d failure(s)" % failures)
	get_tree().quit(1 if failures else 0)
