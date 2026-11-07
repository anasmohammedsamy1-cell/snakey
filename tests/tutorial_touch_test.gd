extends Node
const TutorialScene := preload("res://scenes/tutorial.tscn")
var failures := 0
func _ready() -> void:
	call_deferred("run_test")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("[TOUCH] FAIL ", label)
	else:
		print("[TOUCH] PASS ", label)
func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
func touch(index: int, pos: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = pos
	event.pressed = pressed
	get_viewport().push_input(event, true)
func drag(index: int, pos: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = pos
	event.relative = relative
	get_viewport().push_input(event, true)
func run_test() -> void:
	var tutorial = TutorialScene.instantiate()
	get_tree().root.add_child(tutorial)
	await wait(0.5)
	var control = tutorial.touch_controls
	var joy: Vector2 = control._joy_rest
	touch(0, joy, true)
	await wait(0.1)
	drag(0, joy + Vector2(0, -75), Vector2(0, -75))
	await wait(1.1)
	touch(0, joy + Vector2(0, -75), false)
	await wait(0.4)
	check(tutorial.step == 1, "touch joystick advances movement")
	var jump: Vector2 = control._jump_center
	touch(1, jump, true)
	await wait(0.12)
	touch(1, jump, false)
	await wait(0.15)
	check(tutorial.step == 2, "touch jump advances lesson")
	var push: Vector2 = control._push_center
	touch(2, push, true)
	await wait(0.16)
	touch(2, push, false)
	await wait(0.2)
	check(tutorial.step == 3, "touch push release completes lesson")
	var overlay := Button.new()
	overlay.position = Vector2(control.size.x * 0.7, control.size.y * 0.5)
	overlay.size = Vector2(120, 70)
	tutorial.touch_controls.get_parent().add_child(overlay)
	control.input_exclusion_controls.append(overlay)
	await get_tree().process_frame
	var button_pos := overlay.position + Vector2(20, 20)
	touch(3, button_pos, true)
	await wait(0.1)
	check(control._cam_touch == -1 and control._joy_touch == -1, "excluded overlay touch not captured by camera or joystick")
	touch(3, button_pos, false)
	print("[TOUCH] finished with %d failure(s)" % failures)
	get_tree().quit(1 if failures else 0)
