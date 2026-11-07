extends Node
## Renders real gameplay frames of the new full-body animation and checks invariants.
## Run (needs a display or xvfb):
##   xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/animation_visual_test.tscn
## Screenshots go to $ANIM_SHOTS (default user://anim_shots).

var _fails := 0
var _out := ""
var _cam: Camera3D
var _p: Node
var _bot: Node
var _rm: Node


func _ready() -> void:
	call_deferred("_start")


func _start() -> void:
	var placeholder := Node.new()
	get_tree().root.add_child(placeholder)
	get_tree().current_scene = placeholder
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	print("[ANIM] %s  %s" % ["PASS" if ok else "FAIL", msg])
	if not ok:
		_fails += 1


func _shot(tag: String, view := "side", dist := 5.0, height := 1.3, at := Vector3(0, 1.0, 0)) -> void:
	var c: Vector3 = _p.global_position + at
	var yaw: float = _p.visuals.rotation.y
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var off := right * dist
	if view == "front":
		off = fwd * dist
	elif view == "rear":
		off = -fwd * dist
	_cam.global_position = c + off + Vector3(0, height - 1.0, 0)
	_cam.look_at(c, Vector3.UP)
	_cam.current = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, tag])


func _process(_d: float) -> void:
	if _bot != null and is_instance_valid(_bot):
		_bot.bot_world_dir = Vector3.ZERO
		_bot._push_timer = 99.0


func _wait_until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await get_tree().process_frame
		t += get_process_delta_time()
	return false


func _grab_throw_scenarios(a: ContenderAnimator) -> void:
	_p.global_position = Vector3(5.0, 0.2, 6.0)
	_p.face_direction(Vector3(0, 0, -1))
	await _wait(0.4)
	var fwd := Vector3(-sin(_p.facing_yaw), 0, -cos(_p.facing_yaw))
	_bot.set_physics_process(true)
	_bot.global_position = _p.global_position + fwd * 2.8
	_bot.face_direction(-fwd)
	await _wait(0.3)
	var victim_start: Vector3 = _bot.global_position
	_p.arm_mode = 1
	_p._push_charge = 0.2
	_p.push_requested = true
	await _wait(0.12)
	_check(a.state in [&"grab", &"lift"], "grab/lift state while reaching (%s)" % a.state)
	await _shot("06_grab_reach_side", "side", 6.0, 1.4)
	await _shot("06_grab_reach_front", "front", 5.0, 1.4)
	var ok1: bool = await _wait_until(func(): return _p.grabbing_id != 0 and _p.grab_phase == 1, 3.0)
	_check(ok1, "grab reached carry phase")
	if not ok1:
		return
	var vic_prev: Vector3 = _bot.global_position
	var max_jump := 0.0
	var shot_a := false
	var shot_b := false
	while a.lift_p < 0.999:
		await get_tree().physics_frame
		max_jump = maxf(max_jump, _bot.global_position.distance_to(vic_prev))
		vic_prev = _bot.global_position
		if not shot_a and a.lift_p > 0.3:
			shot_a = true
			_check(a.state == &"lift", "lift state (%s)" % a.state)
			await _shot("07_lift_a_side", "side", 6.0, 1.6)
			await _shot("07_lift_a_front", "front", 5.0, 1.6)
		if not shot_b and a.lift_p > 0.65:
			shot_b = true
			await _shot("07_lift_b_side", "side", 6.0, 1.8)
			await _shot("07_lift_b_front", "front", 6.0, 1.8)
	_check(max_jump < 0.55, "victim never teleports while lifting (max step %.2f m)" % max_jump)
	await _wait_until(func(): return a.lift_p >= 0.999, 2.0)
	await _wait(0.15)
	_check(a.state == &"carry", "carry state (%s)" % a.state)
	var head_y: float = _p.global_position.y + 2.1
	var body_y: float = _bot.global_position.y + 0.93
	_check(body_y > head_y + 0.15, "victim body is above the carrier's head (%.2f vs %.2f)" % [body_y, head_y])
	await _shot("08_carry_side", "side", 6.0, 1.8)
	await _shot("08_carry_front", "front", 6.0, 1.8)
	await _shot("08_carry_rear", "rear", 6.0, 1.8)
	# throw
	_p.arm_mode = 0
	_p._push_charge = 0.7
	_p.push_requested = true
	await _wait(0.08)
	_check(a.state == &"throw_prepare", "throw_prepare (%s)" % a.state)
	await _shot("09_throw_prep_side", "side", 6.0, 1.8)
	await _wait(0.12)
	await _shot("09_throw_thrust_side", "side", 6.0, 1.6)
	var released: bool = await _wait_until(func(): return _p.grabbing_id == 0, 1.5)
	_check(released, "host released the victim at the end of the throw")
	await _wait(0.05)
	_check(a.state == &"throw_followthrough", "throw_followthrough (%s)" % a.state)
	await _shot("10_followthrough_side", "side", 7.0, 1.6)
	await _wait(0.25)
	var v: Vector3 = _bot.velocity
	_check(v.length() > 6.0, "victim has real throw velocity (%.1f m/s)" % v.length())
	_check(_bot.visuals.animator.state == &"ragdoll" or _bot.visuals.animator.state == &"hit", "victim tumbles in flight (%s)" % _bot.visuals.animator.state)
	await _shot("11_victim_flight", "side", 9.0, 2.5, _bot.global_position - _p.global_position + Vector3(0, 1, 0))
	await _wait(2.0)
	_check(a.state in [&"idle", &"recover", &"walk"], "thrower returns to normal (%s)" % a.state)


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _run() -> void:
	_out = OS.get_environment("ANIM_SHOTS")
	if _out == "":
		_out = ProjectSettings.globalize_path("user://anim_shots")
	DirAccess.make_dir_recursive_absolute(_out)
	SettingsManager.apply_preset(SettingsManager.PRESET_HIGH)
	GameManager.start_practice()
	await _wait(1.0)
	var arena := get_tree().current_scene
	_rm = arena.get_node_or_null("RoundManager")
	_p = _rm.local_player if _rm != null else null
	if _p == null:
		_check(false, "player spawned")
		get_tree().quit(1)
		return
	_check(true, "player spawned")
	_cam = Camera3D.new()
	_cam.fov = 55.0
	get_tree().root.add_child(_cam)
	# calm everything else down: freeze bots, keep them out of the way
	for id in _rm.players:
		var o = _rm.players[id]
		if o != _p:
			_bot = o
			o.set_physics_process(false)
			o.global_position = _p.global_position + Vector3(0, 0, -30)
	var a: ContenderAnimator = _p.visuals.animator
	_check(a != null and a.ok, "animator built on original skeleton")
	await _wait(2.5)
	_check(a.state == &"idle", "idle state (%s)" % a.state)
	await _shot("01_idle_side")
	await _shot("01_idle_front", "front")

	# --- walking / running ---
	_p.global_position = Vector3(5.0, 0.2, 10.5)
	_p.face_direction(Vector3(0, 0, -1))
	Input.action_press("move_forward", 0.4)
	await _wait(0.9)
	_check(a.state == &"walk", "walk state (%s)" % a.state)
	var max_err := 0.0
	var max_slide := 0.0
	var prev_w: Array = [a._foot_w[0], a._foot_w[1]]
	var prev_sw: Array = [false, false]
	var measured := 0
	for k in 30:
		await get_tree().process_frame
		for i in 2:
			var side := "L" if i == 0 else "R"
			var rl: float = a._roll[i]
			var sole: Vector3 = a._sole_c[i].lerp(a._sole_h[i], -rl) if rl < 0.0 else a._sole_c[i].lerp(a._sole_t[i], rl)
			# compare in the animator's own (last-updated) skeleton space so slow test frames cannot skew it
			var actual: Vector3 = a.sk.get_bone_global_pose(a._id["Foot_" + side]) * sole
			var plant_m: Vector3 = a._to_m * a._foot_w[i]
			if not a._sw_on[i] and not prev_sw[i]:
				# planted foot: it must stay put in the world while the body walks over it...
				max_slide = maxf(max_slide, Vector2(a._foot_w[i].x - prev_w[i].x, a._foot_w[i].z - prev_w[i].z).length())
				# ...and the real shoe must be where the plant says it is
				if absf(a._roll[i]) < 0.35:
					var e := Vector2(actual.x - plant_m.x, actual.z - plant_m.z).length()
					max_err = maxf(max_err, e)
					measured += 1
			prev_w[i] = a._foot_w[i]
			prev_sw[i] = a._sw_on[i]
	_check(max_slide < 0.02, "planted feet do not slide (max drift per frame %.3f m)" % max_slide)
	_check(measured > 5 and max_err < 0.2, "real shoe sits on the planted foot target (max error %.2f m over %d samples)" % [max_err, measured])
	await _shot("02_walk_side")
	await _wait(0.07)
	await _shot("02_walk_side_b")
	await _shot("02_walk_front", "front")
	await _shot("02_walk_rear", "rear")
	Input.action_release("move_forward")
	_p.global_position = Vector3(5.0, 0.2, 9.5)
	_p.face_direction(Vector3(0, 0, -1))
	Input.action_press("move_forward", 1.0)
	await _wait(0.8)
	_check(a.state == &"run", "run state (%s)" % a.state)
	await _shot("03_run_side")
	await _wait(0.06)
	await _shot("03_run_side_b")
	await _shot("03_run_front", "front")
	Input.action_release("move_forward")
	await _wait(0.12)
	await _shot("04_stop_side")
	await _wait(0.9)
	_check(a.state == &"idle" or a.state == &"turn", "returns to idle (%s)" % a.state)

	# --- jump / land ---
	Input.action_press("jump")
	await _wait(0.1)
	Input.action_release("jump")
	await _wait(0.2)
	await _shot("05_jump_side")
	await _wait(0.35)
	await _shot("05_fall_side")
	await _wait(0.3)
	await _shot("05_land_side")

	await _grab_throw_scenarios(a)
	print("[ANIM] finished with %d failure(s)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
