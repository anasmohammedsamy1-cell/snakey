extends RefCounted
class_name ContenderAnimator
## Full-body procedural animator for the ORIGINAL 14-bone contender skeleton.
##
## Rig facts (inspected from contender.glb): Torso (pelvis+chest hub), Head,
## Arm_L/R (= shoulder->elbow), Hand_L/R (= forearm + glove), Leg_L/R (= hip->knee),
## Foot_L/R (= shin + shoe).  There are NO separate pelvis / ankle / wrist bones, so:
##   * knee / elbow come from the Foot / Hand bone,
##   * pelvis motion = Torso bone translation + rotation,
##   * the shoe pitches with the shin (heel->toe is done by rolling the contact point).
##
## Everything is solved in SKELETON space (character faces +Z, its left side is +X).
## Legs use a step-based gait: each foot is planted in WORLD space (no sliding),
## stepped when it drifts from its ideal spot, and solved with two-bone IK.
## The CharacterBody3D stays the only physics/authority object; this class only
## poses the visible skeleton, so it can never fight the gameplay physics.

const GameConstants := preload("res://scripts/game_constants.gd")

const L1_LEG := 0.2422
const L1_ARM := 0.2727
const GLOVE_LOCAL := Vector3(0.0, 0.177, 0.0)
const TORSO_Y := 0.9318
const RUN_SPEED := 7.5
const LIFT_TIME := GameConstants.GRAB_LIFT_TIME
const THROW_PREP := GameConstants.THROW_PREP_TIME
const THROW_TOTAL := GameConstants.THROW_TOTAL_TIME   # shared with RoundManager.THROW_RELEASE_DELAY
const FOLLOW_TIME := GameConstants.THROW_FOLLOW_TIME
const MAX_ARM_SCALE := 40.0         # rubber arm: enough Y-scale to reach the full punch / grab range
const CARRY_OVER := Vector3(0.0, 2.55, -0.10)   # holder-local victim body centre, overhead
const CARRY_BACK := Vector3(0.0, 2.30, 0.60)
const CARRY_FWD := Vector3(0.0, 2.00, -1.05)
const HIP_TO_FEET := 0.93

enum C {
	CROUCH, LEAN, TWIST, ROLL, SHIFT_X, SHIFT_Z, H_NOD, H_YAW, H_ROLL, AIR, DANGLE, TUMBLE, CARRIED,
	AL_DOWN, AL_FWD, AL_OUT, AL_ELB, AR_DOWN, AR_FWD, AR_OUT, AR_ELB, REACH_L, REACH_R, COUNT
}

# ---- inputs written by ContenderVisuals every frame -----------------------
var in_vel_w := Vector3.ZERO          # smoothed world velocity (platform removed)
var in_vy := 0.0
var in_grounded := true
var in_ground_y := 0.0
var in_platform_vel := Vector3.ZERO
var in_holding := 0
var in_held_by := 0
var in_phase := 0
var in_target_w := Vector3.ZERO       # victim world position while we hold someone
var in_has_target := false
var in_holder_lift := 0.0             # holder's lift progress (read from holder when we are carried)
var in_holder_throw := -1.0
var in_holder_pos_w := Vector3.ZERO
var in_holder_yaw := 0.0
var in_celebrating := false
var in_alive := true

# ---- outputs / debug ---------------------------------------------------------
var state: StringName = &"idle"
var ok := false
var lift_p := 0.0
var throw_t := -1.0                    # >=0 while a throw is playing
var follow_t := -1.0
var carry_sway := Vector3.ZERO

var sk: Skeleton3D
var _space: PhysicsDirectSpaceState3D
var _ray: PhysicsRayQueryParameters3D
var _to_w := Transform3D.IDENTITY
var _to_m := Transform3D.IDENTITY
var _vel_m := Vector3.ZERO
var _time := 0.0
var _id := {}
var _rest_b := {}
var _arm_o: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _leg_o: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _sole_h: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _sole_c: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _sole_t: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _tg := PackedFloat32Array()
var _cu := PackedFloat32Array()
var _rt: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]      # smoothed reach targets (skeleton space)
var _rt_in: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _smax: Array[float] = [1.0, 1.0]
var _k := 10.0

var _foot_w: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _sw_on: Array[bool] = [false, false]
var _sw_t: Array[float] = [0.0, 0.0]
var _sw_dur: Array[float] = [0.25, 0.25]
var _sw_from: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _sw_to_gy: Array[float] = [0.0, 0.0]
var _roll: Array[float] = [0.0, 0.0]
var _gait_ready := false
var _was_grounded := true
var _prev_vy := 0.0
var _land_amt := 0.0
var _hit_amt := 0.0
var _hit_dir := Vector3.ZERO
var _tumble_q := Quaternion.IDENTITY
var _tumble_w := Vector3.ZERO
var _tumbling := false
var _recover_t := 0.0
var _act: StringName = &""
var _act_t := 0.0
var _act_dur := 0.0
var _act_side := 0
var _act_target_m := Vector3.ZERO
var _act_has_target := false
var _act_two := false
var _next_side := 0
var _grab_hold_t := 0.0
var _lift_from_w := Vector3.ZERO
var _was_carry := false
var _dir_m := Vector3(0, 0, 1)
var _idle_t := 0.0
var _yaw_prev := 0.0
var _yaw_rate := 0.0
var _step_pulse := 0.0
var _out_mid: Vector3
var _out_end: Vector3
var _out_s := 1.0


func build(skeleton: Skeleton3D) -> bool:
	sk = skeleton
	ok = false
	if sk == null:
		return false
	for n in ["Torso", "Head", "Arm_L", "Arm_R", "Hand_L", "Hand_R", "Leg_L", "Leg_R", "Foot_L", "Foot_R"]:
		var i := sk.find_bone(n)
		if i < 0:
			push_warning("ContenderAnimator: missing bone " + n)
			return false
		_id[n] = i
		_rest_b[n] = sk.get_bone_rest(i).basis
	for s in 2:
		var side := "L" if s == 0 else "R"
		var sx := 1.0 if s == 0 else -1.0
		_arm_o[s] = sk.get_bone_rest(_id["Arm_" + side]).origin
		_leg_o[s] = sk.get_bone_rest(_id["Leg_" + side]).origin
		var inv := sk.get_bone_global_rest(_id["Foot_" + side]).affine_inverse()
		_sole_h[s] = inv * Vector3(sx * 0.297, 0.008, -0.17)
		_sole_c[s] = inv * Vector3(sx * 0.297, 0.008, 0.073)
		_sole_t[s] = inv * Vector3(sx * 0.297, 0.008, 0.33)
	_tg.resize(C.COUNT)
	_cu.resize(C.COUNT)
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collision_mask = 1
	_defaults()
	for i in C.COUNT:
		_cu[i] = _tg[i]
	ok = true
	return true


# --------------------------------------------------------------------------
# Public triggers

func trigger_punch(target_w: Vector3, has_target: bool, charge: float) -> void:
	if in_holding != 0 and in_phase == 1:
		return
	_act_two = charge < 0.3
	_act = &"push" if _act_two else &"punch"
	_act_t = 0.0
	_act_dur = 0.46 if _act_two else 0.42
	_act_side = _next_side
	_next_side = 1 - _next_side
	# The controller always passes the charged hand target (even on a miss), so
	# the rubber arm visibly extends to the full attack range instead of the
	# short 1.4 m fallback pose.
	_act_has_target = has_target or target_w.length_squared() > 0.0001
	if _act_has_target:
		_act_target_m = _to_m * target_w


func trigger_grab(target_w: Vector3, has_target: bool) -> void:
	_act = &"grab"
	_act_t = 0.0
	_act_dur = GameConstants.GRAB_REACH_TIME
	_act_has_target = has_target or target_w.length_squared() > 0.0001
	if _act_has_target:
		_act_target_m = _to_m * target_w


func trigger_throw() -> void:
	if throw_t >= 0.0:
		return
	throw_t = 0.0
	follow_t = -1.0


func trigger_hit(dir_w: Vector3, strength: float) -> void:
	var d := _to_m.basis * Vector3(dir_w.x, 0.0, dir_w.z)
	if d.length_squared() > 0.0001:
		_hit_dir = d.normalized()
	_hit_amt = clampf(strength, 0.25, 1.4)
	if strength > 0.55:
		var axis := Vector3.UP.cross(_hit_dir)
		if axis.length_squared() > 0.0001:
			_tumble_w = axis.normalized() * (5.0 + 5.0 * clampf(strength, 0.0, 1.5))
			_tumbling = true
			_recover_t = 0.0


func on_grab_links(holding: int, held_by: int, phase: int) -> void:
	if holding != 0 and phase == 1 and not (in_holding != 0 and in_phase == 1):
		_lift_from_w = in_target_w
		lift_p = 0.0
	if holding == 0 and in_holding != 0 and throw_t >= 0.0:
		follow_t = 0.0     # host released: we were mid-throw -> follow through
		throw_t = -1.0
	in_holding = holding
	in_held_by = held_by
	in_phase = phase


func reset() -> void:
	_act = &""
	throw_t = -1.0
	follow_t = -1.0
	lift_p = 0.0
	_tumbling = false
	_hit_amt = 0.0
	_recover_t = 0.0
	_land_amt = 0.0
	_gait_ready = false
	_defaults()
	for i in C.COUNT:
		_cu[i] = _tg[i]


## World position of the victim's feet-origin while we carry / throw (read by the victim).
func get_carry_origin_w(origin_w: Vector3, yaw: float) -> Vector3:
	var b := Basis(Vector3.UP, yaw)
	var c := origin_w + b * _carry_offset()
	return c - Vector3(0.0, HIP_TO_FEET, 0.0)


func get_hand_world(side: int) -> Vector3:
	if not ok:
		return Vector3.ZERO
	var tg := _torso_g()
	var arm_b := tg.basis * Basis(sk.get_bone_pose_rotation(_id["Arm_" + ("L" if side == 0 else "R")]))
	var hand_b := arm_b * Basis(sk.get_bone_pose_rotation(_id["Hand_" + ("L" if side == 0 else "R")]))
	var sh := tg * _arm_o[side]
	var sc := sk.get_bone_pose_scale(_id["Arm_" + ("L" if side == 0 else "R")]).y
	return _to_w * (sh + arm_b * Vector3(0, L1_ARM * sc, 0) + hand_b * GLOVE_LOCAL)


func is_airborne_tumbling() -> bool:
	return _tumbling


# --------------------------------------------------------------------------
# Frame update

func update(dt: float) -> void:
	if not ok or not sk.is_inside_tree():
		return
	dt = clampf(dt, 0.0001, 0.05)
	_time += dt
	_to_w = sk.global_transform
	_to_m = _to_w.affine_inverse()
	_space = sk.get_world_3d().direct_space_state
	var vw := Vector3(in_vel_w.x, 0.0, in_vel_w.z)
	_vel_m = _to_m.basis * vw
	_yaw_rate = lerpf(_yaw_rate, wrapf(in_holder_yaw - _yaw_prev, -PI, PI) / dt, 1.0 - exp(-12.0 * dt))
	_yaw_prev = in_holder_yaw
	_land_hit_events(dt)
	_defaults()
	_k = 10.0
	_compute_targets(dt)
	for i in C.COUNT:
		var rate := _k
		if i == C.AIR:
			rate = 14.0
		_cu[i] = lerpf(_cu[i], _tg[i], 1.0 - exp(-rate * dt))
	for s in 2:
		_rt[s] = _rt[s].lerp(_rt_in[s], 1.0 - exp(-_k * 1.3 * dt))
	_gait(dt)
	_write_pose()


func _land_hit_events(dt: float) -> void:
	if in_grounded and not _was_grounded:
		_land_amt = clampf(-_prev_vy / 15.0, 0.15, 1.0)
		if _tumbling:
			_tumbling = false
			_recover_t = 0.7
	_was_grounded = in_grounded
	_prev_vy = in_vy
	_land_amt = maxf(0.0, _land_amt - dt * 3.2)
	_hit_amt = maxf(0.0, _hit_amt - dt * 2.4)
	if _tumbling:
		var rate := _tumble_w.length()
		if rate > 0.001:
			_tumble_q = (Quaternion(_tumble_w / rate, rate * dt) * _tumble_q).normalized()
		_tumble_w = _tumble_w * exp(-0.35 * dt)
		if in_grounded:
			_tumbling = false
			_recover_t = 0.7
	elif _recover_t > 0.0:
		_recover_t = maxf(0.0, _recover_t - dt)
		_tumble_q = _tumble_q.slerp(Quaternion.IDENTITY, 1.0 - exp(-9.0 * dt))
	else:
		_tumble_q = Quaternion.IDENTITY
	if _act != &"":
		_act_t += dt
		if _act_t >= _act_dur:
			_act = &""
	if throw_t >= 0.0:
		throw_t += dt
		if in_holding == 0 and throw_t > 0.15:
			throw_t = -1.0
		elif throw_t > THROW_TOTAL + 0.25:
			throw_t = -1.0
	if follow_t >= 0.0:
		follow_t += dt
		if follow_t > FOLLOW_TIME:
			follow_t = -1.0
	if in_holding != 0 and in_phase == 1:
		lift_p = minf(1.0, lift_p + dt / LIFT_TIME)
	else:
		lift_p = maxf(0.0, lift_p - dt * 3.0)


func _defaults() -> void:
	for i in C.COUNT:
		_tg[i] = 0.0
	_tg[C.AL_DOWN] = 0.92
	_tg[C.AR_DOWN] = 0.92
	_tg[C.AL_FWD] = 0.02
	_tg[C.AR_FWD] = 0.02
	_tg[C.AL_OUT] = 0.26
	_tg[C.AR_OUT] = 0.26
	_tg[C.AL_ELB] = 0.2
	_tg[C.AR_ELB] = 0.2
	_smax[0] = 1.0
	_smax[1] = 1.0


func _carry_offset() -> Vector3:
	var e := lift_p * lift_p * (3.0 - 2.0 * lift_p)
	var base: Vector3
	var from_off := Vector3(0.0, 1.0, -0.9)
	if in_has_target or _lift_from_w != Vector3.ZERO:
		from_off = (_lift_from_w + Vector3(0.0, HIP_TO_FEET, 0.0) - in_holder_pos_w)
		from_off = Basis(Vector3.UP, in_holder_yaw).inverse() * from_off
		from_off.y = clampf(from_off.y, 0.5, 1.6)
		if from_off.length() > 2.6:
			from_off = from_off.normalized() * 2.6
	base = from_off.lerp(CARRY_OVER, e)
	var tt := throw_t
	if tt >= 0.0:
		if tt < THROW_PREP:
			var w := smoothstep(0.0, 1.0, tt / THROW_PREP)
			base = CARRY_OVER.lerp(CARRY_BACK, w)
		else:
			var u := clampf((tt - THROW_PREP) / (THROW_TOTAL - THROW_PREP), 0.0, 1.0)
			base = CARRY_BACK.lerp(CARRY_FWD, u * u * (3.0 - 2.0 * u) * 0.35 + u * 0.65)
	return base + carry_sway * e


# --------------------------------------------------------------------------
# Target generation (all state logic lives here)

func _compute_targets(dt: float) -> void:
	var spd := Vector2(_vel_m.x, _vel_m.z).length()
	var sn := clampf(spd / RUN_SPEED, 0.0, 1.0)
	if spd > 0.4:
		_dir_m = Vector3(_vel_m.x, 0.0, _vel_m.z) / spd
	var fwd_v := _vel_m.z
	var lat_v := _vel_m.x
	var grounded := in_grounded
	_idle_t += dt
	var st: StringName = &"idle"

	# ----- baseline locomotion ------------------------------------------------
	_tg[C.AIR] = 0.0 if grounded else 1.0
	var lean := clampf(fwd_v * 0.052, -0.22, 0.42)
	var roll := clampf(-lat_v * 0.030, -0.22, 0.22)
	var phase_lr := 0.0
	var fp := [0.0, 0.0]
	if _gait_ready:
		for i in 2:
			var m := _to_m * _foot_w[i]
			var rel := Vector3(m.x, 0.0, m.z) - Vector3((0.22 if i == 0 else -0.22), 0.0, 0.05)
			fp[i] = clampf(rel.dot(_dir_m) / maxf(0.25 + 0.3 * sn, 0.01), -1.0, 1.0)
		phase_lr = (fp[0] - fp[1]) * 0.5
	var amp := lerpf(0.0, 0.95, clampf(spd / 3.0, 0.0, 1.0))
	amp = lerpf(amp, 1.15, sn * sn)
	var moving := spd > 0.5 and grounded
	_tg[C.LEAN] = lean + 0.012 * sin(_idle_t * 1.9)
	_tg[C.ROLL] = roll + 0.02 * sin(_idle_t * 0.7)
	_tg[C.TWIST] = -0.16 * phase_lr * clampf(spd / 3.5, 0.0, 1.0) + 0.02 * sin(_idle_t * 0.45)
	_tg[C.SHIFT_X] = 0.012 * sin(_idle_t * 0.9)
	_tg[C.CROUCH] = 0.035 + 0.07 * sn
	_tg[C.H_NOD] = 0.01 + sin(_idle_t * 1.5) * 0.02 - 0.05 * sn
	_tg[C.H_YAW] = sin(_idle_t * 0.55) * 0.05
	_tg[C.H_ROLL] = sin(_idle_t * 0.7) * 0.02
	_tg[C.AL_DOWN] = 0.92 - 0.14 * sn
	_tg[C.AR_DOWN] = _tg[C.AL_DOWN]
	_tg[C.AL_FWD] = clampf(-fp[1] * amp, -1.2, 1.2) + 0.03 * sin(_idle_t * 1.1)
	_tg[C.AR_FWD] = clampf(-fp[0] * amp, -1.2, 1.2) - 0.03 * sin(_idle_t * 1.1)
	_tg[C.AL_ELB] = 0.2 + 0.6 * sn + 0.03 * sin(_idle_t * 1.9)
	_tg[C.AR_ELB] = _tg[C.AL_ELB]
	_tg[C.AL_OUT] = 0.26 + 0.05 * (1.0 - sn)
	_tg[C.AR_OUT] = _tg[C.AL_OUT]
	if moving:
		if sn > 0.62:
			st = &"run"
		else:
			st = &"walk"
		if absf(lat_v) > absf(fwd_v) * 1.2:
			st = &"strafe"
		elif fwd_v < -0.6 * spd and spd > 0.8:
			st = &"backward_walk"
	elif grounded:
		st = &"idle"
	# turning in place: stepping handled by gait, add lean/arm counter-twist for readability
	if grounded and spd < 1.5 and absf(_yaw_rate) > 1.2:
		st = &"turn"
		_tg[C.LEAN] += 0.05
		_tg[C.ROLL] += clampf(_yaw_rate * 0.03, -0.12, 0.12)
		_tg[C.TWIST] += clampf(-_yaw_rate * 0.04, -0.2, 0.2)
	_step_pulse = maxf(0.0, _step_pulse - dt)

	if grounded and spd > 11.0:
		st = &"dash"
		_tg[C.LEAN] = 0.6
		_tg[C.CROUCH] = 0.14
		_tg[C.AL_FWD] = -0.9
		_tg[C.AR_FWD] = -0.9
		_tg[C.AL_DOWN] = 0.6
		_tg[C.AR_DOWN] = 0.6
		_tg[C.H_NOD] = -0.2
		_k = 16.0

	if not grounded:
		_tg[C.CROUCH] = 0.0
		if in_vy > 0.8:
			st = &"jump"
			_tg[C.LEAN] = 0.1
			_tg[C.AL_DOWN] = -0.1
			_tg[C.AR_DOWN] = -0.1
			_tg[C.AL_OUT] = 0.55
			_tg[C.AR_OUT] = 0.55
			_tg[C.AL_FWD] = 0.3
			_tg[C.AR_FWD] = 0.3
			_tg[C.AL_ELB] = 0.3
			_tg[C.AR_ELB] = 0.3
		else:
			st = &"fall"
			_tg[C.LEAN] = -0.04 + sin(_time * 7.0) * 0.05
			_tg[C.ROLL] = sin(_time * 6.0) * 0.07
			_tg[C.AL_DOWN] = 0.1
			_tg[C.AR_DOWN] = 0.1
			_tg[C.AL_OUT] = 0.85
			_tg[C.AR_OUT] = 0.85
			_tg[C.AL_FWD] = 0.1 + sin(_time * 9.0) * 0.35
			_tg[C.AR_FWD] = 0.1 - sin(_time * 9.0) * 0.35
	if _land_amt > 0.01:
		_tg[C.CROUCH] += 0.26 * _land_amt
		_tg[C.LEAN] += 0.30 * _land_amt
		_tg[C.AL_OUT] += 0.3 * _land_amt
		_tg[C.AR_OUT] += 0.3 * _land_amt
		_tg[C.AL_DOWN] -= 0.2 * _land_amt
		_tg[C.AR_DOWN] -= 0.2 * _land_amt
		_tg[C.H_NOD] -= 0.12 * _land_amt
		if _land_amt > 0.25 and st != &"dash":
			st = &"land"

	if in_celebrating and grounded:
		st = &"victory"
		var bounce := absf(sin(_time * 7.0))
		_tg[C.CROUCH] = 0.03 + 0.10 * (1.0 - bounce)
		_tg[C.LEAN] = -0.05
		_tg[C.AL_DOWN] = -0.6 + sin(_time * 8.0) * 0.12
		_tg[C.AR_DOWN] = -0.6 - sin(_time * 8.0) * 0.12
		_tg[C.AL_OUT] = 0.5
		_tg[C.AR_OUT] = 0.5
		_tg[C.AL_ELB] = 0.3
		_tg[C.AR_ELB] = 0.3
		_tg[C.H_NOD] = -0.1
		_tg[C.H_ROLL] = sin(_time * 3.0) * 0.12
		_tg[C.TWIST] = sin(_time * 3.5) * 0.15

	# ----- victim side: being pulled / carried ---------------------------------
	_tg[C.REACH_L] = 0.0
	_tg[C.REACH_R] = 0.0
	if in_held_by != 0 and in_phase == 1:
		st = &"carried"
		_tg[C.CARRIED] = clampf(in_holder_lift, 0.0, 1.0)
		_tg[C.DANGLE] = 0.92
		_tg[C.AIR] = 1.0
		_tg[C.CROUCH] = 0.0
		_tg[C.LEAN] = 0.0
		_tg[C.ROLL] = 0.0
		_tg[C.TWIST] = 0.0
		_tg[C.SHIFT_X] = 0.0
		_tg[C.H_NOD] = -0.55 * in_holder_lift + sin(_time * 3.0) * 0.12
		_tg[C.H_ROLL] = sin(_time * 2.3) * 0.2
		_k = 9.0
	elif in_held_by != 0:
		st = &"grabbed_pull"
		_tg[C.LEAN] = -0.30 + sin(_time * 14.0) * 0.07
		_tg[C.CROUCH] = 0.10
		_tg[C.AL_DOWN] = 0.15
		_tg[C.AR_DOWN] = 0.15
		_tg[C.AL_FWD] = 0.9 + sin(_time * 12.0) * 0.3
		_tg[C.AR_FWD] = 0.9 - sin(_time * 12.0) * 0.3
		_tg[C.H_NOD] = -0.25
		_k = 16.0
	elif _tumbling or _recover_t > 0.0:
		_tg[C.TUMBLE] = 1.0 if _tumbling else clampf(_recover_t / 0.7, 0.0, 1.0)
		_tg[C.DANGLE] = 0.8 if _tumbling else 0.0
		_tg[C.AIR] = 1.0 if _tumbling else 0.0
		st = &"ragdoll" if _tumbling else &"recover"
		if _tumbling:
			_tg[C.CROUCH] = 0.0
			_tg[C.H_NOD] = sin(_time * 11.0) * 0.4
			_tg[C.AL_FWD] = sin(_time * 13.0) * 0.9
			_tg[C.AR_FWD] = -sin(_time * 12.0) * 0.9
		else:
			_tg[C.CROUCH] = 0.22 * clampf(_recover_t / 0.7, 0.0, 1.0)
			_tg[C.LEAN] += 0.35 * clampf(_recover_t / 0.7, 0.0, 1.0)
			_tg[C.AL_OUT] = 0.6
			_tg[C.AR_OUT] = 0.6
		_k = 14.0
	elif _hit_amt > 0.05:
		st = &"hit"
		var h := _hit_amt
		_tg[C.LEAN] = clampf(_hit_dir.z * 0.55 * h, -0.55, 0.55)
		_tg[C.ROLL] = clampf(-_hit_dir.x * 0.45 * h, -0.45, 0.45)
		_tg[C.TWIST] = 0.25 * h * sin(_time * 30.0)
		_tg[C.AL_OUT] = 0.7
		_tg[C.AR_OUT] = 0.7
		_tg[C.AL_DOWN] = 0.3
		_tg[C.AR_DOWN] = 0.3
		_tg[C.AL_FWD] = 0.5 * h
		_tg[C.AR_FWD] = 0.5 * h
		_tg[C.H_NOD] = -0.45 * h * signf(_hit_dir.z + 0.001)
		_tg[C.H_ROLL] = 0.3 * h * sin(_time * 33.0)
		_tg[C.CROUCH] += 0.08 * h
		_k = 22.0

	# ----- holder side: grab reach / lift / carry / throw ----------------------
	var carrying := in_holding != 0 and in_phase == 1
	var pulling := in_holding != 0 and in_phase == 0
	if in_held_by == 0 and not _tumbling:
		if carrying or follow_t >= 0.0:
			_holder_targets(st, sn)
			st = _holder_state
		elif pulling and in_has_target:
			st = &"grab"
			_reach_both(in_target_w + Vector3(0, 1.0, 0), 0.45, MAX_ARM_SCALE)
			var toward := _to_m * in_target_w
			_tg[C.LEAN] = 0.34
			_tg[C.CROUCH] = 0.16
			_tg[C.SHIFT_Z] = 0.05
			_tg[C.AL_DOWN] = 0.2
			_tg[C.AR_DOWN] = 0.2
			_tg[C.H_NOD] = 0.12
			_tg[C.TWIST] += clampf(toward.x * 0.05, -0.2, 0.2)
			_k = 16.0
		elif _act != &"":
			st = _action_targets(st)

	_tg[C.SHIFT_X] += 0.0
	state = st


var _holder_state: StringName = &"carry"


func _holder_targets(_st: StringName, sn: float) -> void:
	var p := lift_p
	var e := p * p * (3.0 - 2.0 * p)
	_holder_state = &"carry"
	var c_w := _carry_center_w()
	for i in 2:
		var sx := 1.0 if i == 0 else -1.0
		var upright := Vector3(sx * 0.42, 0.0, 0.0)
		var lying := Vector3(sx * 0.33, -0.43, 0.0)
		var off := upright.lerp(lying, clampf(e, 0.0, 1.0))
		# offsets are expressed in skeleton space (left = +X), centre comes from the carry path
		_rt_in[i] = _to_m * c_w + off
		_smax[i] = MAX_ARM_SCALE
	_tg[C.REACH_L] = 1.0
	_tg[C.REACH_R] = 1.0
	var load := 0.5 + 0.5 * e
	if follow_t >= 0.0:
		_holder_state = &"throw_followthrough"
		var f := clampf(follow_t / FOLLOW_TIME, 0.0, 1.0)
		var fw := 1.0 - f
		_tg[C.REACH_L] = fw
		_tg[C.REACH_R] = fw
		_rt_in[0] = Vector3(0.28, 1.45, 1.1)
		_rt_in[1] = Vector3(-0.28, 1.45, 1.1)
		_smax[0] = MAX_ARM_SCALE
		_smax[1] = MAX_ARM_SCALE
		_tg[C.LEAN] = 0.38 * fw
		_tg[C.CROUCH] = 0.14 * fw
		_tg[C.SHIFT_Z] = 0.12 * fw
		_tg[C.TWIST] = 0.25 * fw
		_tg[C.AL_DOWN] = 0.5
		_tg[C.AR_DOWN] = 0.5
		_k = 13.0
		return
	if throw_t >= 0.0:
		var tt := throw_t
		if tt < THROW_PREP:
			var w := smoothstep(0.0, 1.0, tt / THROW_PREP)
			_holder_state = &"throw_prepare"
			_tg[C.LEAN] = -0.42 * w
			_tg[C.CROUCH] = 0.22 * w
			_tg[C.TWIST] = 0.30 * w
			_tg[C.SHIFT_Z] = 0.10 * w
			_k = 14.0
		else:
			var u := clampf((tt - THROW_PREP) / (THROW_TOTAL - THROW_PREP), 0.0, 1.0)
			_holder_state = &"throw_release"
			_tg[C.LEAN] = lerpf(-0.42, 0.40, u)
			_tg[C.CROUCH] = lerpf(0.22, -0.02, u)
			_tg[C.TWIST] = lerpf(0.30, -0.35, u)
			_tg[C.SHIFT_Z] = lerpf(0.10, -0.12, u)
			_tg[C.AIR] = 0.0
			_k = 26.0
		return
	if p < 0.999:
		_holder_state = &"lift"
		_tg[C.CROUCH] = 0.26 * (1.0 - e) + 0.05
		_tg[C.LEAN] = 0.36 * (1.0 - e) - 0.10 * e
		_tg[C.SHIFT_Z] = 0.08 * (1.0 - e)
		_tg[C.H_NOD] = -0.2 * e
		_k = 13.0
	else:
		# carry: lean back and bend the knees to counter the load, sway with the weight
		_tg[C.CROUCH] = 0.06 + 0.03 * sin(_time * 5.0) * sn
		_tg[C.LEAN] = -0.13 + 0.05 * sn
		_tg[C.TWIST] = 0.03 * sin(_time * 2.2) * sn
		_tg[C.ROLL] = 0.03 * sin(_time * 1.7)
		_tg[C.H_NOD] = -0.2
		_k = 11.0
	_tg[C.AL_DOWN] = 0.2
	_tg[C.AR_DOWN] = 0.2


func _carry_center_w() -> Vector3:
	return in_holder_pos_w + Basis(Vector3.UP, in_holder_yaw) * _carry_offset()


func _reach_both(world_pt: Vector3, weight: float, smax: float) -> void:
	var c := _to_m * world_pt
	_rt_in[0] = c + Vector3(0.3, 0.0, 0.0)
	_rt_in[1] = c + Vector3(-0.3, 0.0, 0.0)
	_tg[C.REACH_L] = 1.0
	_tg[C.REACH_R] = 1.0
	_smax[0] = smax
	_smax[1] = smax


func _action_targets(st: StringName) -> StringName:
	var p := clampf(_act_t / maxf(_act_dur, 0.01), 0.0, 1.0)
	var s := 1.0 if _act_side == 0 else -1.0
	var wind := smoothstep(0.0, 0.28, p) * (1.0 - smoothstep(0.28, 0.42, p))
	var strike := smoothstep(0.26, 0.46, p) * (1.0 - smoothstep(0.62, 1.0, p))
	match _act:
		&"punch":
			st = &"punch"
			_tg[C.TWIST] = s * (0.5 * wind - 0.55 * strike)
			_tg[C.LEAN] = 0.14 + 0.32 * strike - 0.12 * wind
			_tg[C.CROUCH] = 0.08 + 0.08 * strike
			_tg[C.SHIFT_Z] = 0.12 * strike - 0.05 * wind
			var tm := _act_target_m if _act_has_target else Vector3(s * 0.15, 1.15, 1.4)
			var back := Vector3(s * 0.45, 1.1, -0.35)
			var idx := _act_side
			var tgt := back.lerp(tm, strike)
			_rt_in[idx] = tgt
			_smax[idx] = MAX_ARM_SCALE
			_tg[C.REACH_L + idx] = clampf(wind * 0.9 + strike, 0.0, 1.0)
			var oth := C.AR_FWD if idx == 0 else C.AL_FWD
			_tg[oth] = -0.5 * strike + 0.4 * wind
			_k = 26.0 if strike > 0.1 else 18.0
		&"push":
			st = &"push"
			_tg[C.LEAN] = 0.12 + 0.38 * strike - 0.1 * wind
			_tg[C.CROUCH] = 0.12 + 0.07 * strike
			_tg[C.SHIFT_Z] = 0.16 * strike - 0.05 * wind
			_tg[C.TWIST] = 0.15 * sin(p * PI * 2.0) * s
			var tm2 := _act_target_m if _act_has_target else Vector3(0.0, 1.1, 1.3)
			var back2 := Vector3(0.0, 1.1, 0.25)
			var tgt2 := back2.lerp(tm2, strike)
			_rt_in[0] = tgt2 + Vector3(0.28, 0.0, 0.0)
			_rt_in[1] = tgt2 + Vector3(-0.28, 0.0, 0.0)
			_smax[0] = MAX_ARM_SCALE
			_smax[1] = MAX_ARM_SCALE
			_tg[C.REACH_L] = clampf(wind * 0.8 + strike, 0.0, 1.0)
			_tg[C.REACH_R] = _tg[C.REACH_L]
			_k = 24.0 if strike > 0.1 else 16.0
		&"grab":
			st = &"grab"
			var r := smoothstep(0.0, 0.4, p) * (1.0 - smoothstep(0.75, 1.0, p))
			var tm3 := _act_target_m + Vector3(0, 1.0, 0) if _act_has_target else Vector3(0.0, 1.0, 1.4)
			_rt_in[0] = tm3 + Vector3(0.3, 0.0, 0.0)
			_rt_in[1] = tm3 + Vector3(-0.3, 0.0, 0.0)
			_smax[0] = MAX_ARM_SCALE
			_smax[1] = MAX_ARM_SCALE
			_tg[C.REACH_L] = r
			_tg[C.REACH_R] = r
			_tg[C.LEAN] = 0.1 + 0.28 * r
			_tg[C.CROUCH] = 0.05 + 0.12 * r
			_tg[C.H_NOD] = 0.1 * r
			_k = 18.0
	return st


# --------------------------------------------------------------------------
# Legs: step-based gait with planted feet

func _ground_at(w: Vector3) -> float:
	if _space == null:
		return in_ground_y
	_ray.from = Vector3(w.x, in_ground_y + 0.7, w.z)
	_ray.to = Vector3(w.x, in_ground_y - 0.8, w.z)
	var r := _space.intersect_ray(_ray)
	if r.is_empty():
		return in_ground_y
	return (r["position"] as Vector3).y


func _ideal_m(i: int, sn: float) -> Vector3:
	var sx := 1.0 if i == 0 else -1.0
	var lead := 0.10 + 0.06 * sn
	var v := Vector3(_vel_m.x, 0.0, _vel_m.z) * lead
	if v.length() > 0.40:
		v = v.normalized() * 0.40          # the cartoon legs are short: never plan a step beyond reach
	return Vector3(sx * (0.22 + 0.03 * sn), 0.0, 0.05) + v


func _swing_target(i: int, sn: float, dur: float) -> Vector3:
	var extra := Vector3(_vel_m.x, 0.0, _vel_m.z) * dur * 0.5
	if extra.length() > 0.18:
		extra = extra.normalized() * 0.18
	var t := _ideal_m(i, sn) + extra
	var hip := Vector2(_leg_o[i].x, _leg_o[i].z)
	var d := Vector2(t.x, t.z) - hip
	if d.length() > 0.52:
		d = d.normalized() * 0.52
		t.x = hip.x + d.x
		t.z = hip.y + d.y
	return t


func _gait(dt: float) -> void:
	var spd := Vector2(_vel_m.x, _vel_m.z).length()
	var sn := clampf(spd / RUN_SPEED, 0.0, 1.0)
	var gy := in_ground_y
	if not _gait_ready or not in_grounded or _tumbling:
		for i in 2:
			var im := _ideal_m(i, sn)
			_foot_w[i] = _to_w * im
			_foot_w[i].y = gy
			_sw_on[i] = false
			_sw_t[i] = 0.0
		_gait_ready = in_grounded and not _tumbling
		return
	var thr := lerpf(0.20, 0.34, sn)
	var dur := lerpf(0.30, 0.13, sn)
	var lift := lerpf(0.07, 0.24, sn)
	for i in 2:
		_foot_w[i] += in_platform_vel * dt
	var best := -1
	var best_d := 0.0
	for i in 2:
		if _sw_on[i]:
			continue
		var cur := _to_m * _foot_w[i]
		var d := Vector3(cur.x, 0.0, cur.z) - Vector3(_ideal_m(i, sn).x, 0.0, _ideal_m(i, sn).z)
		var dl := d.length()
		var other := 1 - i
		var other_free := (not _sw_on[other]) or _sw_t[other] > 0.55
		if dl > thr and other_free and dl > best_d:
			best = i
			best_d = dl
	if best >= 0:
		_sw_on[best] = true
		_sw_t[best] = 0.0
		_sw_dur[best] = dur
		_sw_from[best] = _foot_w[best]
		var tm := _swing_target(best, sn, dur)
		_sw_to_gy[best] = _ground_at(_to_w * tm)
		if spd < 1.0:
			_step_pulse = 0.25
	var swing_sum := 0.0
	var swing_side := 0.0
	for i in 2:
		if _sw_on[i]:
			_sw_t[i] += dt / maxf(_sw_dur[i], 0.05)
			var t := minf(_sw_t[i], 1.0)
			var e := t * t * (3.0 - 2.0 * t)
			var tm2 := _swing_target(i, sn, _sw_dur[i])
			var tw := _to_w * tm2
			tw.y = _sw_to_gy[i]
			var pos := _sw_from[i].lerp(tw, e)
			pos.y = lerpf(_sw_from[i].y, _sw_to_gy[i], e) + lift * sin(PI * t)
			_foot_w[i] = pos
			_roll[i] = lerpf(_roll[i], -0.4, 1.0 - exp(-12.0 * dt))
			swing_sum += sin(PI * t)
			swing_side = (1.0 if i == 0 else -1.0)
			if t >= 1.0:
				_sw_on[i] = false
				_foot_w[i] = tw
		else:
			# heel -> toe roll through the stance phase
			var cur2 := _to_m * _foot_w[i]
			var rel := (Vector3(cur2.x, 0.0, cur2.z) - Vector3(_ideal_m(i, sn).x, 0.0, _ideal_m(i, sn).z)).dot(_dir_m if spd > 0.5 else Vector3(0, 0, 1))
			var target_roll := clampf(-rel / maxf(thr, 0.1), -1.0, 1.0) * clampf(spd / 2.0, 0.0, 1.0)
			_roll[i] = lerpf(_roll[i], target_roll, 1.0 - exp(-14.0 * dt))
	# pelvis IK: lower the hips just enough that every planted foot stays reachable
	var need := 0.0
	for i in 2:
		if _sw_on[i]:
			continue
		var m := _to_m * _foot_w[i]
		var dx := m.x - (_cu[C.SHIFT_X] + _leg_o[i].x)
		var dz := m.z - (_cu[C.SHIFT_Z] + _leg_o[i].z)
		var dxz2 := dx * dx + dz * dz
		var dy := sqrt(maxf(0.60 * 0.60 - dxz2, 0.02))
		var hip_allowed := m.y + 0.01 + dy
		need = maxf(need, (TORSO_Y + _leg_o[i].y) - hip_allowed)
	_tg[C.CROUCH] = maxf(_tg[C.CROUCH], need)
	# pelvis vault + weight transfer over the stance foot
	_tg[C.CROUCH] -= 0.035 * swing_sum * (0.4 + sn)
	_tg[C.SHIFT_X] += -swing_side * (0.035 + 0.02 * sn) * swing_sum
	_cu[C.CROUCH] = lerpf(_cu[C.CROUCH], _tg[C.CROUCH], 1.0 - exp(-14.0 * dt))
	_cu[C.SHIFT_X] = lerpf(_cu[C.SHIFT_X], _tg[C.SHIFT_X], 1.0 - exp(-14.0 * dt))


# --------------------------------------------------------------------------
# Pose writing

func _torso_g() -> Transform3D:
	var tb := _torso_basis()
	var py := TORSO_Y - _cu[C.CROUCH]
	var pos := Vector3(_cu[C.SHIFT_X], py, _cu[C.SHIFT_Z])
	return Transform3D(tb, pos)


func _torso_basis() -> Basis:
	var q := Quaternion(Vector3.UP, _cu[C.TWIST]) * Quaternion(Vector3.RIGHT, _cu[C.LEAN]) * Quaternion(Vector3.BACK, _cu[C.ROLL])
	var ext := Quaternion.IDENTITY
	if _cu[C.TUMBLE] > 0.001:
		ext = Quaternion.IDENTITY.slerp(_tumble_q, clampf(_cu[C.TUMBLE], 0.0, 1.0))
	if _cu[C.CARRIED] > 0.001:
		var lay := Quaternion(Vector3.UP, -PI * 0.5) * Quaternion(Vector3.RIGHT, -PI * 0.5)
		ext = Quaternion.IDENTITY.slerp(lay, clampf(_cu[C.CARRIED], 0.0, 1.0)) * ext
	return Basis((ext * q).normalized())


func _arc(a: Vector3, b: Vector3) -> Quaternion:
	var d := a.dot(b)
	if d < -0.9999:
		var ax := a.cross(Vector3.UP)
		if ax.length_squared() < 0.001:
			ax = a.cross(Vector3.RIGHT)
		return Quaternion(ax.normalized(), PI)
	var c := a.cross(b)
	return Quaternion(c.x, c.y, c.z, 1.0 + d).normalized()


func _aim(parent_b: Basis, rest_b: Basis, dir_g: Vector3, local_vec: Vector3) -> Basis:
	var g0 := parent_b * rest_b
	var u := (g0 * local_vec).normalized()
	return Basis(_arc(u, dir_g.normalized())) * g0


func _solve(root: Vector3, target: Vector3, l1: float, l2: float, pole: Vector3, smax: float) -> void:
	var to := target - root
	var d := to.length()
	var dir := to / d if d > 0.0001 else Vector3.DOWN
	var s := 1.0
	if d > l1 + l2 and smax > 1.0:
		s = minf((d - l2) / l1, smax)
	var L1 := l1 * s
	var dd := clampf(d, absf(L1 - l2) + 0.002, L1 + l2 - 0.002)
	var a := (L1 * L1 - l2 * l2 + dd * dd) / (2.0 * dd)
	var h := sqrt(maxf(L1 * L1 - a * a, 0.0))
	var perp := pole - dir * dir.dot(pole)
	if perp.length_squared() < 0.000001:
		perp = dir.cross(Vector3.UP)
		if perp.length_squared() < 0.000001:
			perp = dir.cross(Vector3.RIGHT)
	perp = perp.normalized()
	_out_mid = root + dir * a + perp * h
	_out_end = root + dir * dd
	_out_s = s


func _set_local(id: int, parent_b: Basis, g: Basis) -> void:
	sk.set_bone_pose_rotation(id, (parent_b.inverse() * g).orthonormalized().get_rotation_quaternion())


func _write_pose() -> void:
	var tg := _torso_g()
	var tb := tg.basis
	sk.set_bone_pose_position(_id["Torso"], tg.origin)
	sk.set_bone_pose_rotation(_id["Torso"], tb.get_rotation_quaternion())
	# head: keep it level against torso sway/lean, then add look offsets
	var hq := Quaternion(Vector3.RIGHT, _cu[C.H_NOD]) * Quaternion(Vector3.UP, _cu[C.H_YAW]) * Quaternion(Vector3.BACK, _cu[C.H_ROLL])
	var stab := Quaternion.IDENTITY.slerp(tb.get_rotation_quaternion().inverse(), 0.55 * (1.0 - clampf(_cu[C.TUMBLE] + _cu[C.CARRIED], 0.0, 1.0)))
	sk.set_bone_pose_rotation(_id["Head"], (stab * hq).normalized())

	var down := Vector3.DOWN
	var dang := _cu[C.DANGLE]
	for i in 2:
		var sx := 1.0 if i == 0 else -1.0
		var side := "L" if i == 0 else "R"
		# ---------------- arm ----------------
		var o := C.AL_DOWN if i == 0 else C.AR_DOWN
		var desired := Vector3(sx * _cu[o + 2], -_cu[o], _cu[o + 1]).normalized()
		var up_dir := tb * desired
		var fore := tb * desired.rotated(Vector3.RIGHT, -_cu[o + 3]).normalized()
		var sway := Vector3(sin(_time * 3.1 + i * 1.7) * 0.25, 0.0, cos(_time * 2.3 + i) * 0.25)
		if dang > 0.001:
			var dd := (down + Vector3(sx * 0.12, 0.0, 0.0) + sway).normalized()
			up_dir = up_dir.lerp(dd, dang).normalized()
			fore = fore.lerp((down + sway * 1.4).normalized(), dang).normalized()
		var shoulder := tg * _arm_o[i]
		var scale_y := 1.0
		var rw := _cu[C.REACH_L + i]
		if rw > 0.002:
			var pole := tb * Vector3(sx * 0.35, -0.2, 0.9)
			_solve(shoulder, _rt[i], L1_ARM, GLOVE_LOCAL.y, pole, _smax[i])
			var u2 := (_out_mid - shoulder).normalized()
			var f2 := (_out_end - _out_mid).normalized()
			up_dir = up_dir.lerp(u2, rw).normalized()
			fore = fore.lerp(f2, rw).normalized()
			scale_y = lerpf(1.0, _out_s, rw)
		var arm_g := _aim(tb, _rest_b["Arm_" + side], up_dir, Vector3.UP)
		_set_local(_id["Arm_" + side], tb, arm_g)
		sk.set_bone_pose_scale(_id["Arm_" + side], Vector3(1.0, scale_y, 1.0))
		var hand_g := _aim(arm_g, _rest_b["Hand_" + side], fore, GLOVE_LOCAL.normalized())
		_set_local(_id["Hand_" + side], arm_g, hand_g)
		sk.set_bone_pose_scale(_id["Hand_" + side], Vector3(1.0, 1.0 / maxf(scale_y, 0.01), 1.0))

		# ---------------- leg ----------------
		var hip := tg * _leg_o[i]
		var rl := _roll[i]
		var sole: Vector3
		if rl < 0.0:
			sole = _sole_c[i].lerp(_sole_h[i], -rl)
		else:
			sole = _sole_c[i].lerp(_sole_t[i], rl)
		var foot_m := _to_m * _foot_w[i]
		var tgt := foot_m
		var air := _cu[C.AIR]
		if air > 0.001:
			var adir := tb * Vector3(sx * 0.10, -1.0, 0.18 * sx * sin(_time * 8.0 + i * 3.0) + (0.25 if i == 0 else -0.05)).normalized()
			if dang > 0.001:
				adir = adir.lerp((down + Vector3(sx * 0.1, 0.0, 0.0) + sway * 0.8).normalized(), dang).normalized()
			var reach := lerpf(0.60, 0.50, absf(sin(_time * 5.0 + i * 2.0)) * (1.0 - _cu[C.TUMBLE]) + _cu[C.TUMBLE] * 0.5)
			tgt = foot_m.lerp(hip + adir * reach, air)
		_solve(hip, tgt, L1_LEG, sole.length(), tb * Vector3(sx * 0.12, 0.0, 1.0), 1.0)
		var lu := (_out_mid - hip).normalized()
		var ll := (_out_end - _out_mid).normalized()
		var leg_g := _aim(tb, _rest_b["Leg_" + side], lu, Vector3.UP)
		_set_local(_id["Leg_" + side], tb, leg_g)
		var foot_g := _aim(leg_g, _rest_b["Foot_" + side], ll, sole.normalized())
		_set_local(_id["Foot_" + side], leg_g, foot_g)
