extends Node3D
class_name ContenderPoseRig
## Hidden animation target for the active ragdoll.
##
## A private Skeleton3D (no mesh) is animated by an AnimationTree blend tree:
##   base state machine -> lower/full body locomotion
##   upper state machine -> one-shot upper-body actions
##   Blend2 (filtered to Torso/Head/Arms/Hands) -> real upper/lower body blend
##
## The ragdoll reads target bone transforms from this skeleton and feeds them to
## joint motors.  Nothing here is rendered and nothing here moves the visible
## skeleton directly.

const BONE_ORDER := [
	"Torso", "Head", "Arm_L", "Hand_L", "Arm_R", "Hand_R",
	"Leg_L", "Foot_L", "Leg_R", "Foot_R",
]
const UPPER_BONES := ["Torso", "Head", "Arm_L", "Hand_L", "Arm_R", "Hand_R"]

const BASE_STATES := [
	"idle", "walk", "run", "sprint", "jump", "fall", "land", "stop",
	"turn", "stumble", "dash", "victory", "ragdoll", "recover",
]
const UPPER_STATES := ["empty", "punch", "grab", "throw", "hit", "held", "victory", "hug", "hold"]

# New upper-body action timers (seconds).  Used by the throw / punch / grab /
# hit sequences so the physical impulse arrives at the right moment.
const UPPER_TIMERS := {
	"punch": 0.18,       # wind-up
	"grab": 0.30,        # extend
	"throw": 0.58,       # wind-up + release at the peak
	"hit": 0.25,         # recoil
	"victory": 1.0,
	"hug": 0.9,
}
const CARRY_SPEED_LOW := 0.3
const CARRY_SPEED_HIGH := 0.58

const UPPER_ACTIONS := {
	"punch": 0.34,
	"grab": 0.38,
	"throw": 0.42,
	"hit": 0.34,
	"victory": 1.0,
	"hug": 0.6,
	"hold": 1.0,
}

var pose_ready := false
var charge := 0.0
var hold_pose := false
var hanging := false
var upper_action := ""
var upper_loop := false

var _source: Skeleton3D
var _target: Skeleton3D
var _anim_player: AnimationPlayer
var _tree: AnimationTree
var _base_playback: AnimationNodeStateMachinePlayback
var _upper_playback: AnimationNodeStateMachinePlayback
var _bone_id: Dictionary = {}
var _rest_q: Dictionary = {}
var _rest_basis: Dictionary = {}
var _rest_origin: Dictionary = {}
var _grip_offset := 0.22
var _time := 0.0
var _base_state := "idle"
var _base_speed := 0.0
var _carrying := false
var _carrying_speed := 0.0   # 0 = standing, higher = moving carrying
var _carry_load := 0.0       # normalized weight of the held character
var _sprinting := false       # extra lean for faster movement
var _carry_phase := "idle"    # idle / walk / run while carrying
var _carry_hand := "Hand_R"
var _reach_active := false
var _reach_target := Vector3.ZERO
var _reach_hand := "Hand_R"
var _upper_timer := 0.0
var _upper_duration := 0.0
var _upper_elapsed := 0.0
var _upper_looping := false
var _upper_release := true
var _upper_weight := 0.0
var _upper_hand := ""
var _ragging := false
var _recovering := false


func build(source: Skeleton3D) -> void:
	if pose_ready or source == null:
		return
	_source = source
	_build_target_skeleton()
	_build_animation_tree()
	pose_ready = true
	if _base_playback != null:
		_base_playback.start("idle")
	if _upper_playback != null:
		_upper_playback.start("empty")
	_set_upper_weight(0.0)


func _build_target_skeleton() -> void:
	_target = Skeleton3D.new()
	_target.name = "PoseSkeleton"
	for i in _source.get_bone_count():
		_target.add_bone(_source.get_bone_name(i))
	for i in _source.get_bone_count():
		_target.set_bone_parent(i, _source.get_bone_parent(i))
		_target.set_bone_rest(i, _source.get_bone_rest(i))
		var rest := _source.get_bone_rest(i)
		_target.set_bone_pose_position(i, rest.origin)
		_target.set_bone_pose_rotation(i, rest.basis.get_rotation_quaternion())
		_target.set_bone_pose_scale(i, rest.basis.get_scale())
	add_child(_target)
	# Match the rendered model, including the 180 degree presentation rotation.
	_target.global_transform = _source.global_transform

	for i in _target.get_bone_count():
		var n := _target.get_bone_name(i)
		_bone_id[n] = i
		var rest := _target.get_bone_rest(i)
		_rest_q[n] = rest.basis.get_rotation_quaternion()
		_rest_basis[n] = rest.basis
		_rest_origin[n] = rest.origin

	_anim_player = AnimationPlayer.new()
	_anim_player.name = "PoseAnimationPlayer"
	_anim_player.root_node = NodePath("..")
	add_child(_anim_player)
	var library := AnimationLibrary.new()
	for state in BASE_STATES:
		library.add_animation(state, _make_clip(state, state, _clip_length(state), true, false))
	for action in UPPER_STATES:
		if action == "empty":
			continue
		library.add_animation("up_" + action, _make_clip("up_" + action, action, _action_length(action), true, true))
	_anim_player.add_animation_library("", library)


func _build_animation_tree() -> void:
	_tree = AnimationTree.new()
	_tree.name = "PoseAnimationTree"
	add_child(_tree)
	_tree.anim_player = NodePath("../PoseAnimationPlayer")

	var root := AnimationNodeBlendTree.new()
	var base_sm := _make_state_machine(BASE_STATES, false)
	var upper_sm := _make_state_machine(UPPER_STATES, true)
	var base_scale := AnimationNodeTimeScale.new()
	var blend := AnimationNodeBlend2.new()
	blend.filter_enabled = true
	for bone in UPPER_BONES:
		blend.set_filter_path("PoseSkeleton:" + bone, true)
	root.add_node("base", base_sm)
	root.add_node("base_scale", base_scale)
	root.add_node("upper", upper_sm)
	root.add_node("blend", blend)
	root.connect_node("base_scale", 0, "base")
	root.connect_node("blend", 0, "base_scale")
	root.connect_node("blend", 1, "upper")
	root.connect_node("output", 0, "blend")
	_tree.tree_root = root
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_tree.active = true
	_base_playback = _tree.get("parameters/base/playback") as AnimationNodeStateMachinePlayback
	_upper_playback = _tree.get("parameters/upper/playback") as AnimationNodeStateMachinePlayback
	_set_upper_weight(0.0)


func _make_state_machine(states: Array, upper: bool) -> AnimationNodeStateMachine:
	var sm := AnimationNodeStateMachine.new()
	for i in states.size():
		var state: String = states[i]
		var node := AnimationNodeAnimation.new()
		node.animation = ("up_" + state) if upper else state
		sm.add_node(state, node, Vector2(i * 180.0, 0.0))
	# Direct travel is used by gameplay, but explicit transitions give the
	# AnimationTree a real, inspectable graph and smooth lower-body changes.
	for from in states:
		for to in states:
			if from == to:
				continue
			var tr := AnimationNodeStateMachineTransition.new()
			tr.xfade_time = 0.10 if upper else 0.14
			tr.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
			tr.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
			sm.add_transition(from, to, tr)
	return sm


# ---------------------------------------------------------------------------
# Target sampling

func advance(delta: float) -> void:
	if not pose_ready:
		return
	# CRITICAL FIX: keep the hidden pose skeleton co-located with the rendered
	# skeleton every tick.  Without this, every world-space bone computation
	# (IK reach, ragdoll motor targets) uses spawn-time coordinates.
	if _source != null:
		_target.global_transform = _source.global_transform
	_time += delta
	_update_upper(delta)
	_tree.advance(delta)
	_apply_overlays()


func _update_upper(delta: float) -> void:
	if not _upper_release:
		_upper_elapsed += delta
	if _upper_timer > 0.0:
		_upper_timer = maxf(0.0, _upper_timer - delta)
		if _upper_timer <= 0.0 and not _upper_looping:
			_upper_release = true
	var wanted := 0.0 if _upper_release else 1.0
	var rate := 9.0 if wanted > _upper_weight else 13.0
	_upper_weight = move_toward(_upper_weight, wanted, delta * rate)
	_set_upper_weight(_upper_weight)
	if _upper_release and _upper_weight <= 0.001 and _upper_playback != null:
		if upper_action != "":
			upper_action = ""
			_upper_playback.start("empty")


func _set_upper_weight(w: float) -> void:
	if _tree != null:
		_tree.set("parameters/blend/blend_amount", clampf(w, 0.0, 1.0))


func _apply_overlays() -> void:
	if charge > 0.01:
		_add_local_rot("Arm_R", Vector3.BACK, 0.65 * charge)
		_add_local_rot("Arm_L", Vector3.BACK, -0.25 * charge)
		_add_local_rot("Torso", Vector3.UP, -0.10 * charge)
		_add_local_rot("Torso", Vector3.RIGHT, -0.06 * charge)
	if hold_pose and not _carrying:
		_add_local_rot("Torso", Vector3.RIGHT, -0.03)
		_add_local_rot("Head", Vector3.RIGHT, 0.04)
	if hanging:
		_add_local_rot("Head", Vector3.RIGHT, 0.22)
		_add_local_rot("Torso", Vector3.RIGHT, -0.08)
	if _ragging:
		_add_local_rot("Head", Vector3.RIGHT, 0.10)
	if _recovering:
		_add_local_rot("Torso", Vector3.RIGHT, 0.08)
	if _carrying:
		# Load-dependent brace: the torso leans back a touch and the knees bend
		# while the real arm takes the weight overhead.
		var load := clampf(_carry_load, 0.0, 1.0)
		_add_local_rot("Torso", Vector3.RIGHT, -0.05 - 0.10 * _carrying_speed - 0.04 * load)
		_add_local_rot("Torso", Vector3.UP, 0.030 * sin(_time * 2.4) * _carrying_speed)
		_add_local_rot("Torso", Vector3.BACK, 0.025 * sin(_time * 1.8) * _carrying_speed)
		_add_local_rot("Head", Vector3.RIGHT, 0.03 + 0.02 * load)
		_add_local_rot("Leg_L", Vector3.RIGHT, 0.05 * load)
		_add_local_rot("Leg_R", Vector3.RIGHT, 0.05 * load)
	_apply_reach_target()


func _add_local_rot(bone: String, axis: Vector3, angle: float) -> void:
	if not _bone_id.has(bone) or absf(angle) < 0.0001:
		return
	var id: int = _bone_id[bone]
	var q := _target.get_bone_pose_rotation(id)
	q = (q * Quaternion(axis, angle)).normalized()
	_target.set_bone_pose_rotation(id, q)


# ---------------------------------------------------------------------------
# Public control

func set_locomotion(state_name: String, speed := 0.0, limp := false) -> void:
	_base_speed = clampf(speed, 0.0, 1.0)
	var wanted := state_name
	if _carrying:
		wanted = "run" if _carrying_speed > CARRY_SPEED_HIGH else ("walk" if _carrying_speed > CARRY_SPEED_LOW else "idle")
	elif wanted == "run" and _base_speed > 0.93:
		# The gameplay has no separate sprint button: holding full speed is the
		# sprint state, with a stronger lean and faster cycle.
		wanted = "sprint"
	if limp and state_name not in ["jump", "fall", "land", "dash"]:
		wanted = "ragdoll"
	if not _bone_id.has("Torso"):
		return
	if wanted != _base_state:
		_base_state = wanted
		if _base_playback != null:
			_base_playback.start(wanted)
	var cycle_scale := 1.0
	if wanted == "walk":
		cycle_scale = lerpf(0.62, 1.25, clampf(_base_speed / 0.55, 0.0, 1.0))
	elif wanted == "run":
		cycle_scale = lerpf(0.85, 1.45, clampf((_base_speed - 0.55) / 0.38, 0.0, 1.0))
	elif wanted == "sprint":
		cycle_scale = lerpf(1.15, 1.55, clampf((_base_speed - 0.93) / 0.07, 0.0, 1.0))
	if _carrying:
		cycle_scale *= 0.86
	if _tree != null:
		_tree.set("parameters/base_scale/scale", cycle_scale)


func set_carrying(active: bool, speed := 0.0, hand := "Hand_R", load := 1.0) -> void:
	_carrying = active
	_carrying_speed = clampf(speed, 0.0, 1.0)
	_carry_load = clampf(load, 0.0, 1.0) if active else 0.0
	_carry_phase = "run" if _carrying_speed > CARRY_SPEED_HIGH else ("walk" if _carrying_speed > CARRY_SPEED_LOW else "idle")
	if hand in ["Hand_L", "Hand_R"]:
		_carry_hand = hand


func choose_reach_hand(world_point: Vector3) -> String:
	if not pose_ready:
		return "Hand_R"
	if _carrying:
		return _carry_hand
	# Score the actual current wrist positions, not the rest pose.  The hand on
	# the target's side wins, and a hand that is already raised keeps a small
	# preference so the arm does not flip sides mid-reach.
	var world := _target.global_transform
	var left := world * _target.get_bone_global_pose(_bone_id["Hand_L"]).origin
	var right := world * _target.get_bone_global_pose(_bone_id["Hand_R"]).origin
	var left_score := left.distance_squared_to(world_point)
	var right_score := right.distance_squared_to(world_point)
	if _reach_active and _reach_hand == "Hand_L":
		left_score *= 0.8
	elif _reach_active and _reach_hand == "Hand_R":
		right_score *= 0.8
	return "Hand_L" if left_score < right_score else "Hand_R"


func set_reach_target(world_point: Vector3, hand := "Hand_R") -> void:
	if hand not in ["Hand_L", "Hand_R"]:
		return
	_reach_target = world_point
	_reach_hand = hand
	_reach_active = true


func clear_reach_target() -> void:
	_reach_active = false


func get_reach_hand() -> String:
	return _reach_hand if _reach_active else _carry_hand


func is_reaching() -> bool:
	return _reach_active


func get_carry_hand() -> String:
	return _carry_hand


func get_upper_progress() -> float:
	if _upper_duration <= 0.001:
		return 0.0
	return clampf(_upper_elapsed / _upper_duration, 0.0, 1.0)


## Two-bone reach: shoulder + elbow solve toward the target and the real glove
## (not the wrist) is the end effector.  The target is clamped to the real arm
## length, so the model never stretches or teleports toward a distant target.
func _apply_reach_target() -> void:
	if not _reach_active:
		return
	var side := "L" if _reach_hand == "Hand_L" else "R"
	var arm_name := "Arm_" + side
	var hand_name := "Hand_" + side
	var torso_name := "Torso"
	if not _bone_id.has(arm_name) or not _bone_id.has(hand_name) or not _bone_id.has(torso_name):
		return
	var arm_id: int = _bone_id[arm_name]
	var hand_id: int = _bone_id[hand_name]
	var world := _target.global_transform
	var torso_pose := _target.get_bone_global_pose(_bone_id[torso_name])
	var shoulder := world * _target.get_bone_global_pose(arm_id).origin
	var to_target := _reach_target - shoulder
	if to_target.length_squared() < 0.0001:
		return
	var torso_basis := world.basis * torso_pose.basis
	var dir_local: Vector3 = (torso_basis.inverse() * to_target.normalized()).normalized()
	var hand_rest: Vector3 = _rest_origin[hand_name]
	var arm_rest: Vector3 = _rest_origin[arm_name]
	var arm_len: float = (hand_rest - arm_rest).length()
	var hand_len: float = _grip_offset
	var max_reach: float = (arm_len + hand_len) * (1.28 if _carrying else 1.0)
	var dist := clampf(to_target.length(), 0.03, max_reach)
	# Elbow bends toward the character's front (+Z local).
	var bend := Vector3(0.0, 0.0, 1.0) - dir_local * dir_local.z
	if bend.length_squared() < 0.0001:
		bend = Vector3(0.0, 1.0, 0.0) - dir_local * dir_local.y
	if bend.length_squared() < 0.0001:
		bend = Vector3(1.0, 0.0, 0.0) - dir_local * dir_local.x
	bend = bend.normalized()
	if _carrying and dir_local.y > 0.1:
		bend = (bend + Vector3(0.0, 0.35, 0.8)).normalized()
	var cos_shoulder := clampf((arm_len * arm_len + dist * dist - hand_len * hand_len) / (2.0 * arm_len * dist), -1.0, 1.0)
	var shoulder_angle := acos(cos_shoulder)
	var axis := dir_local.cross(bend)
	var upper_dir := dir_local
	if axis.length_squared() > 0.0001:
		upper_dir = dir_local.rotated(axis.normalized(), shoulder_angle).normalized()
	var forearm_dir: Vector3 = dir_local * dist - upper_dir * arm_len
	if forearm_dir.length_squared() < 0.0001:
		forearm_dir = dir_local
	forearm_dir = forearm_dir.normalized()
	var arm_q := _aim_offset(arm_name, upper_dir)
	var arm_basis: Basis = _rest_basis[arm_name] * Basis(arm_q)
	var hand_parent_dir: Vector3 = (arm_basis.inverse() * forearm_dir).normalized()
	var hand_q := _aim_offset(hand_name, hand_parent_dir)
	_target.set_bone_pose_rotation(arm_id, arm_q)
	_target.set_bone_pose_rotation(hand_id, hand_q)


func play_upper(action: String, loop := false, duration := -1.0) -> void:
	if not pose_ready or not UPPER_ACTIONS.has(action):
		return
	upper_action = action
	upper_loop = loop
	_upper_looping = loop
	_upper_duration = (duration if duration > 0.0 else float(UPPER_ACTIONS[action]))
	_upper_timer = 0.0 if loop else _upper_duration
	_upper_elapsed = 0.0
	_upper_release = false
	if _upper_playback != null:
		_upper_playback.start(action)
	_set_upper_weight(1.0)
	_upper_weight = 1.0


func stop_upper() -> void:
	if not pose_ready:
		return
	upper_loop = false
	_upper_looping = false
	_upper_timer = 0.0
	_upper_elapsed = 0.0
	_upper_duration = 0.0
	_upper_release = true


func set_charge(value: float) -> void:
	charge = clampf(value, 0.0, 1.0)


func set_hold_pose(value: bool) -> void:
	hold_pose = value


func set_hanging(value: bool) -> void:
	hanging = value


func set_ragdoll_pose(value: bool) -> void:
	_ragging = value
	_recovering = false


func set_recovering(value: bool) -> void:
	_recovering = value
	_ragging = false


func get_target_bone(key: String) -> Transform3D:
	if not pose_ready or not _bone_id.has(key):
		return Transform3D.IDENTITY
	return _target.get_bone_global_pose(_bone_id[key])


func get_skeleton_transform() -> Transform3D:
	return _target.global_transform if pose_ready else Transform3D.IDENTITY


func get_target_skeleton() -> Skeleton3D:
	return _target


# ---------------------------------------------------------------------------
# Clips and procedural pose

func _clip_length(state: String) -> float:
	match state:
		"idle": return 2.4
		"walk": return 0.84
		"run": return 0.58
		"sprint": return 0.48
		"jump": return 0.62
		"fall": return 0.72
		"land": return 0.34
		"stop": return 0.30
		"turn": return 0.32
		"stumble": return 0.52
		"dash": return 0.24
		"victory": return 1.2
		"ragdoll": return 0.9
		_: return 0.8


func _action_length(action: String) -> float:
	return float(UPPER_ACTIONS.get(action, 0.4))


func _make_clip(_clip_name: String, state_name: String, length: float, loop: bool, upper: bool) -> Animation:
	var anim := Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var bones: Array = UPPER_BONES if upper else BONE_ORDER
	var samples := 24 if loop else 14
	for bone in bones:
		if not _rest_q.has(bone):
			continue
		var track := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(track, NodePath("PoseSkeleton:" + bone))
		var prev := Quaternion.IDENTITY
		for s in samples + 1:
			var t := length * float(s) / float(samples)
			var offsets := _pose_offsets(state_name, t, length)
			var off: Quaternion = offsets.get(bone, Quaternion.IDENTITY)
			var q: Quaternion = (_rest_q[bone] * off).normalized()
			if s > 0 and q.dot(prev) < 0.0:
				q = Quaternion(-q.x, -q.y, -q.z, -q.w)
			prev = q
			anim.rotation_track_insert_key(track, t, q)
	return anim


func _pose_offsets(state_name: String, t: float, length: float) -> Dictionary:
	var o: Dictionary = {}
	for bone in BONE_ORDER:
		o[bone] = Quaternion.IDENTITY
	var phase := TAU * t / maxf(length, 0.001)

	# Pose parameters.  Limbs are authored as real directions in torso space so
	# the mirrored left/right rest bones never receive the same Euler sign.
	var lean := 0.02
	var twist := 0.0
	var roll := 0.0
	var head_nod := 0.01
	var head_yaw := 0.0
	var head_roll := 0.0
	var head_local := false
	var arm_l := {"down": 0.92, "fwd": 0.02, "out": 0.26, "elbow": 0.20}
	var arm_r := {"down": 0.92, "fwd": 0.02, "out": 0.26, "elbow": 0.20}
	var leg_l := {"fwd": 0.0, "out": 0.05, "knee": 0.05}
	var leg_r := {"fwd": 0.0, "out": 0.05, "knee": 0.05}

	match state_name:
		"walk":
			var sw := sin(phase)
			var lift_l := maxf(0.0, cos(phase))
			var lift_r := maxf(0.0, cos(phase + PI))
			leg_l["fwd"] = 0.72 * sw
			leg_r["fwd"] = -0.72 * sw
			leg_l["knee"] = 0.10 + 0.58 * lift_l
			leg_r["knee"] = 0.10 + 0.58 * lift_r
			leg_l["out"] = 0.06
			leg_r["out"] = 0.06
			# Arms oppose the legs, hang down and keep a soft elbow.
			arm_l["fwd"] = -0.46 * sw
			arm_r["fwd"] = 0.46 * sw
			arm_l["down"] = 0.95
			arm_r["down"] = 0.95
			arm_l["elbow"] = 0.16 + 0.12 * absf(sw)
			arm_r["elbow"] = 0.16 + 0.12 * absf(sw)
			lean = 0.10 + 0.025 * absf(cos(phase))
			twist = -0.10 * sw
			roll = 0.050 * sw
			head_nod = 0.012 + 0.010 * absf(cos(phase))
			head_yaw = 0.020 * sin(phase * 0.5)
			head_roll = -0.015 * sw
		"run":
			var sw := sin(phase)
			var lift_l := maxf(0.0, cos(phase))
			var lift_r := maxf(0.0, cos(phase + PI))
			leg_l["fwd"] = 1.00 * sw
			leg_r["fwd"] = -1.00 * sw
			leg_l["knee"] = 0.16 + 0.95 * lift_l
			leg_r["knee"] = 0.16 + 0.95 * lift_r
			leg_l["out"] = 0.08
			leg_r["out"] = 0.08
			arm_l["fwd"] = -0.82 * sw
			arm_r["fwd"] = 0.82 * sw
			arm_l["down"] = 0.82
			arm_r["down"] = 0.82
			arm_l["elbow"] = 0.52 + 0.20 * absf(sw)
			arm_r["elbow"] = 0.52 + 0.20 * absf(sw)
			lean = 0.34 + 0.045 * absf(cos(phase))
			twist = -0.17 * sw
			roll = 0.060 * sw
			head_nod = -0.025
			head_yaw = 0.025 * sin(phase * 0.5)
			head_roll = -0.018 * sw
		"sprint":
			var sw := sin(phase)
			var lift_l := maxf(0.0, cos(phase))
			var lift_r := maxf(0.0, cos(phase + PI))
			leg_l["fwd"] = 1.16 * sw
			leg_r["fwd"] = -1.16 * sw
			leg_l["knee"] = 0.20 + 1.15 * lift_l
			leg_r["knee"] = 0.20 + 1.15 * lift_r
			leg_l["out"] = 0.09
			leg_r["out"] = 0.09
			arm_l["fwd"] = -1.02 * sw
			arm_r["fwd"] = 1.02 * sw
			arm_l["down"] = 0.72
			arm_r["down"] = 0.72
			arm_l["elbow"] = 0.70 + 0.22 * absf(sw)
			arm_r["elbow"] = 0.70 + 0.22 * absf(sw)
			lean = 0.46 + 0.055 * absf(cos(phase))
			twist = -0.23 * sw
			roll = 0.072 * sw
			head_nod = -0.035
			head_roll = -0.022 * sw
		"jump":
			lean = 0.16
			leg_l["fwd"] = -0.12
			leg_r["fwd"] = 0.12
			leg_l["knee"] = 0.62
			leg_r["knee"] = 0.48
			arm_l["down"] = -0.15
			arm_r["down"] = -0.15
			arm_l["out"] = 0.55
			arm_r["out"] = 0.55
			arm_l["fwd"] = 0.35
			arm_r["fwd"] = 0.35
			arm_l["elbow"] = 0.16
			arm_r["elbow"] = 0.16
			head_nod = 0.05
		"fall":
			lean = -0.06 + sin(t * 7.0) * 0.03
			leg_l["fwd"] = -0.18 + sin(t * 6.0) * 0.10
			leg_r["fwd"] = 0.18 - sin(t * 6.0) * 0.10
			leg_l["knee"] = 0.38
			leg_r["knee"] = 0.38
			arm_l["down"] = 0.18
			arm_r["down"] = 0.18
			arm_l["out"] = 0.80
			arm_r["out"] = 0.80
			arm_l["fwd"] = 0.12
			arm_r["fwd"] = 0.12
			arm_l["elbow"] = 0.16
			arm_r["elbow"] = 0.16
			head_nod = -0.06
			head_roll = sin(t * 7.0) * 0.06
		"land":
			var p := clampf(t / maxf(length, 0.001), 0.0, 1.0)
			var squash := sin(p * PI)
			lean = 0.24 * squash
			leg_l["knee"] = 0.78 * squash
			leg_r["knee"] = 0.78 * squash
			leg_l["out"] = 0.08
			leg_r["out"] = 0.08
			arm_l["down"] = 0.78 - 0.18 * squash
			arm_r["down"] = 0.78 - 0.18 * squash
			arm_l["out"] = 0.34 + 0.25 * squash
			arm_r["out"] = 0.34 + 0.25 * squash
			arm_l["fwd"] = -0.18 * squash
			arm_r["fwd"] = -0.18 * squash
			arm_l["elbow"] = 0.25
			arm_r["elbow"] = 0.25
			head_nod = -0.07 * squash
		"stop":
			var p := clampf(t / maxf(length, 0.001), 0.0, 1.0)
			var brace := sin(p * PI)
			lean = 0.18 * brace
			leg_l["knee"] = 0.38 * brace
			leg_r["knee"] = 0.30 * brace
			arm_l["down"] = 0.72
			arm_r["down"] = 0.72
			arm_l["out"] = 0.40
			arm_r["out"] = 0.40
			arm_l["fwd"] = 0.35 * brace
			arm_r["fwd"] = 0.35 * brace
			head_nod = -0.04 * brace
		"turn":
			var p := clampf(t / maxf(length, 0.001), 0.0, 1.0)
			var sw := sin(p * PI)
			lean = 0.10 * sw
			twist = 0.22 * sw
			roll = 0.12 * sw
			leg_l["knee"] = 0.22 * sw
			leg_r["knee"] = 0.30 * sw
			leg_l["out"] = 0.10
			leg_r["out"] = 0.02
			arm_l["out"] = 0.55
			arm_r["out"] = 0.55
			arm_l["fwd"] = -0.28 * sw
			arm_r["fwd"] = 0.28 * sw
			head_roll = 0.05 * sw
		"stumble":
			var p := clampf(t / maxf(length, 0.001), 0.0, 1.0)
			var flail := sin(p * PI)
			lean = 0.26 * flail
			roll = sin(t * 22.0) * 0.10 * flail
			twist = 0.14 * flail
			leg_l["fwd"] = -0.22 * flail
			leg_r["fwd"] = 0.20 * flail
			leg_l["knee"] = 0.50 * flail
			leg_r["knee"] = 0.32 * flail
			arm_l["out"] = 0.75
			arm_r["out"] = 0.75
			arm_l["fwd"] = -0.35 * flail
			arm_r["fwd"] = 0.30 * flail
			arm_l["down"] = 0.42
			arm_r["down"] = 0.42
			head_nod = -0.10 * flail
			head_roll = sin(t * 19.0) * 0.12 * flail
		"dash":
			lean = 0.55
			twist = 0.12
			leg_l["fwd"] = -0.55
			leg_r["fwd"] = 0.50
			leg_l["knee"] = 0.35
			leg_r["knee"] = 0.18
			arm_l["fwd"] = -0.80
			arm_r["fwd"] = -0.80
			arm_l["down"] = 0.68
			arm_r["down"] = 0.68
			arm_l["out"] = 0.32
			arm_r["out"] = 0.32
			head_nod = -0.08
		"victory":
			var bounce := absf(sin(t * 7.0))
			lean = -0.05 + bounce * 0.05
			leg_l["knee"] = 0.10 + 0.18 * bounce
			leg_r["knee"] = 0.10 + 0.18 * bounce
			arm_l["down"] = -0.55 + sin(t * 8.0) * 0.08
			arm_r["down"] = -0.55 - sin(t * 8.0) * 0.08
			arm_l["out"] = 0.45
			arm_r["out"] = 0.45
			arm_l["fwd"] = 0.08
			arm_r["fwd"] = 0.08
			arm_l["elbow"] = 0.28
			arm_r["elbow"] = 0.28
			head_nod = -0.08 + sin(t * 4.0) * 0.06
			head_roll = sin(t * 3.0) * 0.08
		"ragdoll":
			lean = 0.12 + sin(t * 2.3) * 0.05
			leg_l["fwd"] = -0.30 + sin(t * 2.2) * 0.20
			leg_r["fwd"] = 0.30 - sin(t * 2.0) * 0.20
			leg_l["knee"] = 0.55
			leg_r["knee"] = 0.45
			arm_l["down"] = 0.65
			arm_r["down"] = 0.65
			arm_l["out"] = 0.45
			arm_r["out"] = 0.45
			arm_l["fwd"] = 0.35 + sin(t * 2.1) * 0.20
			arm_r["fwd"] = 0.35 + sin(t * 2.4) * 0.20
			head_nod = 0.20
			head_roll = sin(t * 1.7) * 0.15
			head_local = true
		"recover":
			lean = 0.22
			leg_l["knee"] = 0.55
			leg_r["knee"] = 0.45
			arm_l["down"] = 0.78
			arm_r["down"] = 0.78
			arm_l["out"] = 0.40
			arm_r["out"] = 0.40
			arm_l["fwd"] = 0.35
			arm_r["fwd"] = 0.35
			head_nod = 0.16
			head_local = true
		"punch":
			var p := clampf(t / maxf(length, 0.001), 0.0, 1.0)
			var thrust := sin(clampf(p * 1.25, 0.0, 1.0) * PI)
			lean = 0.10 + 0.20 * thrust
			twist = 0.32 * thrust
			roll = 0.04 * thrust
			arm_r["down"] = 0.15
			arm_r["out"] = 0.12
			arm_r["fwd"] = 1.10 * thrust
			arm_r["elbow"] = 0.08
			arm_l["down"] = 0.78
			arm_l["out"] = 0.28
			arm_l["fwd"] = -0.45 * thrust
			arm_l["elbow"] = 0.40
			leg_l["fwd"] = -0.10 * thrust
			leg_r["fwd"] = 0.08 * thrust
			leg_l["knee"] = 0.15 * thrust
			leg_r["knee"] = 0.10 * thrust
			head_nod = 0.01 + 0.03 * thrust
		"grab":
			var reach := sin(clampf(t / maxf(length * 0.75, 0.001), 0.0, 1.0) * PI * 0.5)
			lean = 0.08 + 0.12 * reach
			twist = 0.04 * reach
			arm_l["down"] = 0.16
			arm_r["down"] = 0.16
			arm_l["out"] = 0.20
			arm_r["out"] = 0.20
			arm_l["fwd"] = 0.95 * reach
			arm_r["fwd"] = 0.95 * reach
			arm_l["elbow"] = 0.10
			arm_r["elbow"] = 0.10
			leg_l["fwd"] = -0.12
			leg_r["fwd"] = 0.06
			leg_l["knee"] = 0.16
			leg_r["knee"] = 0.12
			head_nod = 0.06
		"throw":
			var p := clampf(t / maxf(length, 0.001), 0.0, 1.0)
			var swing := smoothstep(0.28, 0.72, p)
			var wind := smoothstep(0.0, 0.30, p)
			var release_follow := smoothstep(0.58, 1.0, p)
			lean = lerpf(lerpf(-0.10 * wind, 0.24, swing), 0.10, release_follow)
			twist = lerpf(lerpf(-0.18, 0.28, swing), 0.12, release_follow)
			roll = -0.04 * wind
			arm_l["down"] = lerpf(lerpf(-0.85, 0.08, swing), 0.22, release_follow)
			arm_r["down"] = lerpf(lerpf(-0.85, 0.08, swing), 0.22, release_follow)
			arm_l["fwd"] = lerpf(lerpf(-0.25, 1.12, swing), 0.70, release_follow)
			arm_r["fwd"] = lerpf(lerpf(-0.25, 1.12, swing), 0.70, release_follow)
			arm_l["out"] = 0.30
			arm_r["out"] = 0.30
			arm_l["elbow"] = lerpf(lerpf(0.42, 0.06, swing), 0.18, release_follow)
			arm_r["elbow"] = lerpf(lerpf(0.42, 0.06, swing), 0.18, release_follow)
			leg_l["fwd"] = -0.18 * swing
			leg_r["fwd"] = 0.16 * swing
			leg_l["knee"] = 0.20 + 0.22 * wind
			leg_r["knee"] = 0.16 + 0.16 * wind
			head_nod = lerpf(-0.10, 0.05, swing)
		"hit":
			var p := clampf(t / maxf(length, 0.001), 0.0, 1.0)
			var hit := sin(p * PI)
			lean = -0.32 * hit
			twist = 0.24 * hit
			roll = sin(t * 34.0) * 0.10 * hit
			arm_l["down"] = 0.55
			arm_r["down"] = 0.55
			arm_l["out"] = 0.60
			arm_r["out"] = 0.60
			arm_l["fwd"] = 0.45 * hit
			arm_r["fwd"] = -0.35 * hit
			arm_l["elbow"] = 0.35
			arm_r["elbow"] = 0.35
			leg_l["fwd"] = 0.18 * hit
			leg_r["fwd"] = -0.14 * hit
			leg_l["knee"] = 0.28 * hit
			leg_r["knee"] = 0.22 * hit
			head_nod = -0.42 * hit
			head_roll = sin(t * 37.0) * 0.20 * hit
			head_local = true
		"held":
			# Limp, dangling pose for the player being carried.
			lean = -0.06 + sin(t * 5.0) * 0.06
			twist = sin(t * 4.0) * 0.10
			arm_l["down"] = 1.0
			arm_r["down"] = 1.0
			arm_l["out"] = 0.20
			arm_r["out"] = 0.20
			arm_l["fwd"] = 0.10 + sin(t * 11.0) * 0.20
			arm_r["fwd"] = 0.10 - sin(t * 11.0) * 0.20
			arm_l["elbow"] = 0.18
			arm_r["elbow"] = 0.18
			leg_l["fwd"] = -0.18 + sin(t * 8.0) * 0.18
			leg_r["fwd"] = 0.18 - sin(t * 8.0) * 0.18
			leg_l["knee"] = 0.35
			leg_r["knee"] = 0.35
			head_nod = 0.20
			head_roll = sin(t * 6.0) * 0.12
			head_local = true
		"hug":
			var p := clampf(t / maxf(length, 0.001), 0.0, 1.0)
			var squeeze := 1.0 + sin(t * 15.0) * 0.08
			lean = 0.16
			arm_l["down"] = 0.30
			arm_r["down"] = 0.30
			arm_l["out"] = 0.15
			arm_r["out"] = 0.15
			arm_l["fwd"] = 0.95 * squeeze
			arm_r["fwd"] = 0.95 * squeeze
			arm_l["elbow"] = 0.35
			arm_r["elbow"] = 0.35
			leg_l["knee"] = 0.10
			leg_r["knee"] = 0.08
			head_nod = 0.10
		"hold":
			lean = -0.05
			arm_l["down"] = -0.45
			arm_r["down"] = -0.45
			arm_l["out"] = 0.28
			arm_r["out"] = 0.28
			arm_l["fwd"] = 0.30
			arm_r["fwd"] = 0.30
			arm_l["elbow"] = 0.15
			arm_r["elbow"] = 0.15
			leg_l["knee"] = 0.16
			leg_r["knee"] = 0.16
			head_nod = 0.02
		_:
			var breath := sin(phase)
			lean = 0.02 + breath * 0.012
			roll = sin(phase * 0.63) * 0.020
			twist = sin(phase * 0.41) * 0.018
			arm_l["down"] = 0.92 + breath * 0.015
			arm_r["down"] = 0.92 - breath * 0.010
			arm_l["out"] = 0.26
			arm_r["out"] = 0.26
			arm_l["fwd"] = 0.02 + sin(phase * 0.9) * 0.05
			arm_r["fwd"] = 0.02 - sin(phase * 0.9) * 0.05
			arm_l["elbow"] = 0.20 + breath * 0.025
			arm_r["elbow"] = 0.20 - breath * 0.025
			leg_l["knee"] = 0.05 + breath * 0.015
			leg_r["knee"] = 0.05 - breath * 0.015
			head_nod = 0.01 + sin(phase + 0.6) * 0.025
			head_yaw = sin(phase * 0.55) * 0.03
			head_roll = sin(phase * 0.7) * 0.02

	var torso_q := Quaternion(Vector3.RIGHT, lean) * Quaternion(Vector3.UP, twist) * Quaternion(Vector3.BACK, roll)
	o["Torso"] = torso_q.normalized()

	var head_q := Quaternion(Vector3.RIGHT, head_nod) * Quaternion(Vector3.UP, head_yaw) * Quaternion(Vector3.BACK, head_roll)
	if head_local:
		o["Head"] = head_q.normalized()
	else:
		# Keep the heavy dome level in world space.  The local counter-rotation
		# is what stops the head from being dragged around by torso sway.
		o["Head"] = (torso_q.inverse() * head_q).normalized()

	var chain_l := _arm_chain("L", arm_l["down"], arm_l["fwd"], arm_l["out"], arm_l["elbow"])
	var chain_r := _arm_chain("R", arm_r["down"], arm_r["fwd"], arm_r["out"], arm_r["elbow"])
	o["Arm_L"] = chain_l[0]
	o["Hand_L"] = chain_l[1]
	o["Arm_R"] = chain_r[0]
	o["Hand_R"] = chain_r[1]

	var leg_chain_l := _leg_chain("L", leg_l["fwd"], leg_l["out"], leg_l["knee"])
	var leg_chain_r := _leg_chain("R", leg_r["fwd"], leg_r["out"], leg_r["knee"])
	o["Leg_L"] = leg_chain_l[0]
	o["Foot_L"] = leg_chain_l[1]
	o["Leg_R"] = leg_chain_r[0]
	o["Foot_R"] = leg_chain_r[1]
	return o


## Rotation offset that aims a bone's local +Y down a direction expressed in its
## parent's space.  Using directions instead of raw Euler signs keeps the
## mirrored arms/legs symmetrical.
func _aim_offset(bone: String, desired_parent_dir: Vector3) -> Quaternion:
	if not _rest_basis.has(bone):
		return Quaternion.IDENTITY
	if desired_parent_dir.length_squared() < 0.000001:
		return Quaternion.IDENTITY
	var local_dir: Vector3 = (_rest_basis[bone].inverse() * desired_parent_dir.normalized()).normalized()
	return Quaternion(Vector3.UP, local_dir).normalized()


## Returns [upper-arm offset, forearm/hand offset] for one arm.
func _arm_chain(side: String, down: float, fwd: float, out: float, elbow: float) -> Array:
	var s := 1.0 if side == "L" else -1.0
	var desired := Vector3(s * out, -down, fwd)
	if desired.length_squared() < 0.000001:
		desired = Vector3(s, 0.0, 0.0)
	desired = desired.normalized()
	var arm_bone := "Arm_" + side
	var hand_bone := "Hand_" + side
	var arm_q := _aim_offset(arm_bone, desired)
	if not _rest_basis.has(arm_bone) or not _rest_basis.has(hand_bone):
		return [arm_q, Quaternion.IDENTITY]
	var arm_basis: Basis = _rest_basis[arm_bone] * Basis(arm_q)
	# The elbow folds the forearm toward the character's front (+Z).
	var forearm := desired.rotated(Vector3.RIGHT, -elbow).normalized()
	var hand_parent_dir: Vector3 = (arm_basis.inverse() * forearm).normalized()
	var hand_q := _aim_offset(hand_bone, hand_parent_dir)
	return [arm_q, hand_q]


## Returns [thigh offset, lower-leg/foot offset] for one leg.
func _leg_chain(side: String, fwd: float, out: float, knee: float) -> Array:
	var s := 1.0 if side == "L" else -1.0
	var desired := Vector3(s * out, -1.0, fwd).normalized()
	var leg_bone := "Leg_" + side
	var foot_bone := "Foot_" + side
	var leg_q := _aim_offset(leg_bone, desired)
	if not _rest_basis.has(leg_bone) or not _rest_basis.has(foot_bone):
		return [leg_q, Quaternion.IDENTITY]
	var leg_basis: Basis = _rest_basis[leg_bone] * Basis(leg_q)
	# Positive knee bends the heel backwards; the shoe follows the shin.
	var shin := desired.rotated(Vector3.RIGHT, knee).normalized()
	var foot_parent_dir: Vector3 = (leg_basis.inverse() * shin).normalized()
	var foot_q := _aim_offset(foot_bone, foot_parent_dir)
	return [leg_q, foot_q]
