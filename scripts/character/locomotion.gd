extends Node3D
class_name LocomotionController
## LocomotionController - Generates physical movement targets for the active ragdoll.

var rig: PhysicalPlayer

# Movement tuning
var walk_speed := 5.5
var run_speed := 9.0
var acceleration := 36.0
var deceleration := 42.0
var air_control := 0.45
var jump_impulse := 11.0
var gravity := 26.0
var max_fall_speed := 42.0
var dash_speed := 19.0
var dash_time := 0.35
var dash_cooldown := 1.5

# Runtime
var _move_vel := Vector3.ZERO
var _knockback := Vector3.ZERO
var _dash_timer := 0.0
var _dash_cd := 0.0
var _dash_dir := Vector3.ZERO
var _coyote := 0.0
var _jump_buffer := 0.0
var _stun := 0.0
var _was_on_floor := false
var facing_yaw := 0.0

var _footstep_timer := 0.12
var _footstep_variant := false

var _celebrating := false
var _push_timer := 0.0
var _aim_lock := 0.0


func update(delta: float) -> void:
	var on_floor := rig.grounded
	_push_timer = maxf(0.0, _push_timer - delta)
	_aim_lock = maxf(0.0, _aim_lock - delta)
	_stun = maxf(0.0, _stun - delta)

	if rig.grabbed_by != 0 and rig.grab_phase == 1:
		return
	if rig.grabbed_by != 0 and rig.grab_phase == 0:
		_simulate_pull(delta)
		return

	if on_floor:
		_coyote = 0.12
	else:
		_coyote = maxf(0.0, _coyote - delta)
	if rig.jump_requested:
		_jump_buffer = 0.15
		rig.jump_requested = false
	else:
		_jump_buffer = maxf(0.0, _jump_buffer - delta)

	var wish := _get_wish_direction()
	var mag := minf(wish.length(), 1.0)

	var carry_scale := 1.0
	if rig.grabbing_id != 0 and rig.grab_phase == 1:
		carry_scale = 0.7

	var control := 1.0 if _stun <= 0.0 else 0.25
	var target_vel := Vector3.ZERO
	if mag > 0.01:
		var speed := walk_speed
		if rig.state == "run":
			speed = run_speed
		target_vel = wish.normalized() * speed * mag * control * carry_scale

	var rate := acceleration if mag > 0.01 else deceleration
	if not on_floor:
		rate *= air_control
	_move_vel = _move_vel.move_toward(target_vel, rate * delta)

	if rig.dash_requested:
		rig.dash_requested = false
		_try_dash(wish)
	if _dash_timer > 0.0:
		_dash_timer -= delta
		_move_vel = _dash_dir * dash_speed

	if rig.grabbing_id != 0 and rig.is_local:
		if mag > 0.05:
			facing_yaw = atan2(-wish.x, -wish.z)
		else:
			facing_yaw = rig.cam_yaw
	elif mag > 0.05 and _aim_lock <= 0.0 and rig.grabbing_id == 0 and _dash_timer <= 0.0:
		facing_yaw = atan2(-wish.x, -wish.z)

	# Apply facing to torso body
	var current_quat := rig.torso_body.quaternion
	var current_yaw := current_quat.get_euler().y
	var target_yaw := facing_yaw
	var new_yaw := lerp_angle(current_yaw, target_yaw, 1.0 - exp(-14.0 * delta))
	rig.torso_body.quaternion = Quaternion(Vector3.UP, new_yaw)

	# Gravity
	if not on_floor:
		var g_scale := 1.0
		if _dash_timer > 0.0:
			g_scale = 0.25
		var vel := rig.torso_body.linear_velocity
		vel.y = maxf(vel.y - gravity * g_scale * delta, -max_fall_speed)
		rig.torso_body.linear_velocity = vel

	# Jump
	if _jump_buffer > 0.0 and (on_floor or _coyote > 0.0) and not _celebrating:
		rig.torso_body.apply_central_impulse(Vector3.UP * jump_impulse * rig.torso_body.mass)
		_jump_buffer = 0.0
		_coyote = 0.0
		rig.jump_requested = false
		if rig.is_local:
			rig.jump_performed.emit()

	# Being pulled in (phase 0)
	if rig.grabbed_by != 0 and rig.grab_phase == 0:
		var holder = null
		if rig.round_manager != null:
			holder = rig.round_manager.players.get(rig.grabbed_by)
		if holder == null or not is_instance_valid(holder) or not holder.is_alive:
			rig.grabbed_by = 0
			rig.grab_phase = 0
			return
		var to_holder: Vector3 = holder.global_position - rig.torso_body.global_position
		to_holder.y = 0.0
		if to_holder.length() > 0.5:
			_knockback = _knockback.lerp(to_holder.normalized() * 6.0, 1.0 - exp(-10.0 * delta))

	# Knockback
	var decay := 7.0 if on_floor else 2.2
	_knockback = _knockback.lerp(Vector3.ZERO, 1.0 - exp(-decay * delta))
	if _knockback.length() < 0.05:
		_knockback = Vector3.ZERO

	# Apply movement + knockback to torso
	var vel := rig.torso_body.linear_velocity
	vel.x = _move_vel.x + _knockback.x
	vel.z = _move_vel.z + _knockback.z
	rig.torso_body.linear_velocity = vel

	# Footsteps
	_update_footsteps(delta, on_floor)

	_was_on_floor = on_floor

	rig.dash_requested = false


func _get_wish_direction() -> Vector3:
	var input := Vector2.ZERO
	input.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input.y = Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")

	var cam_pivot := rig.get_node_or_null("CameraPivot")
	if cam_pivot != null:
		var forward: Vector3 = -cam_pivot.global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right: Vector3 = cam_pivot.global_transform.basis.x
		right.y = 0.0
		right = right.normalized()
		return right * input.x + forward * (-input.y)
	return Vector3.ZERO


func _try_dash(wish: Vector3) -> void:
	if _dash_cd > 0.0 or _celebrating or _stun > 0.3 or _dash_timer > 0.0:
		return
	var d := Vector3(wish.x, 0.0, wish.z)
	if d.length() < 0.15:
		d = Vector3(-sin(facing_yaw), 0.0, -cos(facing_yaw))
	_dash_dir = d.normalized()
	facing_yaw = atan2(-_dash_dir.x, -_dash_dir.z)
	_dash_timer = dash_time
	_dash_cd = dash_cooldown
	if rig.grabbed_by != 0:
		rig.round_manager.request_escape(rig)


func _simulate_pull(delta: float) -> void:
	var holder = null
	if rig.round_manager != null:
		holder = rig.round_manager.players.get(rig.grabbed_by)
	if holder == null or not is_instance_valid(holder) or not holder.is_alive:
		rig.grabbed_by = 0
		rig.grab_phase = 0
		return
	var to_holder: Vector3 = holder.global_position - rig.torso_body.global_position
	to_holder.y = 0.0
	if to_holder.length() > 0.5:
		_knockback = _knockback.lerp(to_holder.normalized() * 6.0, 1.0 - exp(-10.0 * delta))


func _update_footsteps(delta: float, grounded: bool) -> void:
	if not grounded or (not rig.is_local and not rig.is_bot) or _celebrating:
		_footstep_timer = minf(_footstep_timer, 0.10)
		return
	var horizontal_speed := Vector2(rig.torso_body.linear_velocity.x, rig.torso_body.linear_velocity.z).length()
	if horizontal_speed < 1.35:
		_footstep_timer = minf(_footstep_timer, 0.10)
		return
	_footstep_timer -= delta
	if _footstep_timer <= 0.0:
		var step_name := "footstep_a" if not _footstep_variant else "footstep_b"
		_footstep_variant = not _footstep_variant
		AudioManager.play_character(step_name, 0.025, -5.0)
		_footstep_timer = clampf(0.43 - horizontal_speed * 0.012, 0.28, 0.42)


func apply_knockback(impulse: Vector3, max_horizontal := 22.0, max_upward := 8.0) -> void:
	if not rig.is_alive:
		return
	_knockback += Vector3(impulse.x, 0.0, impulse.z)
	var h := Vector2(_knockback.x, _knockback.z)
	if h.length() > max_horizontal:
		h = h.normalized() * max_horizontal
		_knockback = Vector3(h.x, 0.0, h.y)
	var vel := rig.torso_body.linear_velocity
	vel.y = maxf(vel.y, 0.0) + clampf(impulse.y, 0.0, max_upward)
	rig.torso_body.linear_velocity = vel
	_stun = 0.4
