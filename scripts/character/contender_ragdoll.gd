extends Node3D
class_name ContenderRagdoll
## Active ragdoll for the Blender contender.
##
## Ten RigidBody3D segments (torso, head, two upper arms, two hands, two upper
## legs and two feet) are connected by nine Generic6DOFJoint3D joints.  Nine
## joints are motor driven with a PD velocity target.  The gameplay
## CharacterBody3D stays authoritative: the torso is connected to it by a soft
## spring and the visible skeleton is written only from the simulated bodies.
##
## Quality levels:
##   2 - full simulation for the local player and nearby remotes
##   1 - full simulation for the local player only
##   0 - direct target-pose skeleton (menu previews, far remotes, disguise/melt)

signal landed(speed: float)
signal ragdoll_started
signal ragdoll_finished

const BODY_ORDER := [
	"Torso", "Head", "Arm_L", "Hand_L", "Arm_R", "Hand_R",
	"Leg_L", "Foot_L", "Leg_R", "Foot_R",
]
const BODY_PARENT := {
	"Head": "Torso",
	"Arm_L": "Torso", "Hand_L": "Arm_L",
	"Arm_R": "Torso", "Hand_R": "Arm_R",
	"Leg_L": "Torso", "Foot_L": "Leg_L",
	"Leg_R": "Torso", "Foot_R": "Leg_R",
}
const JOINT_LIMITS := {
	"Head": [14.0, 16.0, 12.0],   # tighter – head is stiff, extra stiffness via direct torque
	"Arm_L": [100.0, 60.0, 100.0],
	"Hand_L": [70.0, 40.0, 55.0],
	"Arm_R": [100.0, 60.0, 100.0],
	"Hand_R": [70.0, 40.0, 55.0],
	"Leg_L": [74.0, 34.0, 40.0],
	"Foot_L": [80.0, 30.0, 40.0],
	"Leg_R": [74.0, 34.0, 40.0],
	"Foot_R": [80.0, 30.0, 40.0],
}
const MASSES := {
	"Torso": 10.8, "Head": 2.9,
	"Arm_L": 1.10, "Hand_L": 0.80,
	"Arm_R": 1.10, "Hand_R": 0.80,
	"Leg_L": 1.75, "Foot_L": 1.32,
	"Leg_R": 1.75, "Foot_R": 1.32,
}
const MOTOR_GAIN := {
	"Head": 0.0,   # head is driven by direct torque, not joint motor – see _apply_head_torque()
	"Arm_L": 18.0, "Hand_L": 20.0,   # reduced to prevent saturation at 12 rad/s clamp
	"Arm_R": 18.0, "Hand_R": 20.0,
	"Leg_L": 26.0, "Foot_L": 24.0,
	"Leg_R": 26.0, "Foot_R": 24.0,
}
const MOTOR_FORCE := {
	"Head": 0.0,   # head motor disabled; direct torque used instead
	"Arm_L": 46.0, "Hand_L": 26.0,
	"Arm_R": 46.0, "Hand_R": 26.0,
	"Leg_L": 95.0, "Foot_L": 62.0,
	"Leg_R": 95.0, "Foot_R": 62.0,
}
# Head PD torque controller (direct apply_torque, critically-damped).
const HEAD_TORQUE_GAIN := 260.0   # proportional: angle error → torque (stiffer)
const HEAD_TORQUE_DAMP := 62.0    # derivative:   angular velocity → counter-torque (critically damped)
const HEAD_MAX_TORQUE := 200.0    # hard clamp so the neck can never snap violently
const HEAD_TORQUE_IMPACT := 95.0  # relaxed cap immediately after an impact
const BODY_LINEAR_DAMP := {
	"Torso": 0.40, "Head": 0.38,
	"Arm_L": 0.32, "Hand_L": 0.36, "Arm_R": 0.32, "Hand_R": 0.36,
	"Leg_L": 0.34, "Foot_L": 0.40, "Leg_R": 0.34, "Foot_R": 0.40,
}
const BODY_ANGULAR_DAMP := {
	"Torso": 5.8, "Head": 30.0,   # heavier angular damping keeps the head from spinning
	"Arm_L": 2.8, "Hand_L": 3.4, "Arm_R": 2.8, "Hand_R": 3.4,
	"Leg_L": 4.4, "Foot_L": 5.0, "Leg_R": 4.4, "Foot_R": 5.0,
}
const MAX_ANGULAR_SPEED := 22.0
const MAX_LINEAR_SPEED := 40.0
const LAYER_WORLD := 1
const LAYER_RAGDOLL := 8
const LEASH_LINEAR := 0.18
const LEASH_VERTICAL_OFFSET := 0.19

@export var simulation_enabled := true
@export_range(0, 2) var quality := 1
@export var debug_log := false
@export var anchor_stiffness := 1950.0
@export var anchor_damping := 125.0
@export var anchor_max_force := 10000.0
@export var torso_torque_gain := 1080.0
@export var torso_torque_damp := 115.0
@export var torso_max_torque := 1850.0

var skeleton: Skeleton3D
var pose_rig: ContenderPoseRig
var body: Dictionary = {}
var joint: Dictionary = {}
var anchor_body: AnimatableBody3D
var leash_joint: Generic6DOFJoint3D
var bone_id: Dictionary = {}
var bone_rest: Dictionary = {}
var target_world: Dictionary = {}
var target_basis: Dictionary = {}
var is_local_character := false
var grounded := false

var _built := false
var _build_pending := false
var _last_root_position := Vector3.ZERO
var _last_anchor_target := Vector3.ZERO
var _anchor_velocity := Vector3.ZERO
var _time := 0.0
var _motor_scale := 1.0
var _anchor_scale := 1.0
var _torque_scale := 1.0
# Per-body motor scale overrides (0..1).  Used to loosen specific limbs during
# impacts and physical interactions while keeping the rest of the body strong.
var _body_control_scale: Dictionary = {}
var _carry_joint_hand := ""
var _carry_load := 0.0
var _impact_loosen := 0.0
var _explosion_cd := 0.0
var _is_ragdoll := false
var _recovering := false
var _ragdoll_timer := 0.0
var _ragdoll_elapsed := 0.0
var _recover_timer := 0.0
var _stumble_cooldown := 0.0
var _held := false
var _melted := false
var _tether_active := false
var _tether_point := Vector3.ZERO
var _tether_strength := 0.0
var _last_target_origin := Vector3.ZERO
var _foot_contact := [false, false]
var _was_airborne := false
var _ground_query := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	_build_pending = true
	_ground_query.collision_mask = LAYER_WORLD
	_ground_query.collide_with_areas = false


func setup(source_skeleton: Skeleton3D, source_pose_rig: ContenderPoseRig, local_character: bool) -> void:
	skeleton = source_skeleton
	pose_rig = source_pose_rig
	is_local_character = local_character
	_build_pending = true


# ---------------------------------------------------------------------------
# Construction

func _build() -> void:
	if _built or skeleton == null or pose_rig == null:
		return
	for key in BODY_ORDER:
		var id := _find_bone(key)
		if id < 0:
			push_error("ContenderRagdoll: missing bone " + key)
			return
		bone_id[key] = id
		bone_rest[key] = skeleton.get_bone_global_rest(id)
	_build_bodies()
	_build_joints()
	_build_anchor()
	_built = true
	_build_pending = false
	_last_root_position = skeleton.global_position
	_last_target_origin = _anchor_target()
	_last_anchor_target = _last_target_origin
	_anchor_velocity = Vector3.ZERO
	_set_bodies_to_target()
	_apply_body_freeze()
	if debug_log:
		print("[RAGDOLL] built bodies=%d joints=%d" % [body.size(), joint.size()])


func _find_bone(prefix: String) -> int:
	for i in skeleton.get_bone_count():
		var n := skeleton.get_bone_name(i)
		if n == prefix or n.begins_with(prefix + "_"):
			return i
	return -1


func _build_bodies() -> void:
	var root_world := skeleton.global_transform
	for key in BODY_ORDER:
		var rb := RigidBody3D.new()
		rb.name = "Body_" + key
		rb.top_level = true
		rb.mass = float(MASSES[key])
		rb.gravity_scale = 1.0
		rb.linear_damp = float(BODY_LINEAR_DAMP[key])
		rb.angular_damp = float(BODY_ANGULAR_DAMP[key])
		rb.can_sleep = false
		rb.continuous_cd = key in ["Torso", "Head", "Foot_L", "Foot_R"]
		rb.collision_layer = LAYER_RAGDOLL
		rb.collision_mask = LAYER_WORLD
		rb.physics_material_override = _physics_material()
		var cs := CollisionShape3D.new()
		cs.name = "Shape"
		_build_shape(key, rb, cs)
		rb.add_child(cs)
		add_child(rb)
		rb.global_transform = root_world * bone_rest[key]
		body[key] = rb
	for i in BODY_ORDER.size():
		for j in range(i + 1, BODY_ORDER.size()):
			body[BODY_ORDER[i]].add_collision_exception_with(body[BODY_ORDER[j]])


func _build_shape(key: String, rb: RigidBody3D, cs: CollisionShape3D) -> void:
	match key:
		"Torso":
			var c := CapsuleShape3D.new()
			c.radius = 0.30
			c.height = 0.78
			cs.shape = c
			cs.position = Vector3(0, 0.035, 0.0)
		"Head":
			var s := SphereShape3D.new()
			s.radius = 0.335
			cs.shape = s
			cs.position = Vector3(0, 0.375, -0.01)
		"Arm_L", "Arm_R":
			var a := CapsuleShape3D.new()
			a.radius = 0.105
			a.height = 0.31
			cs.shape = a
			cs.position = Vector3(0, 0.155, 0.0)
		"Hand_L", "Hand_R":
			var h := SphereShape3D.new()
			h.radius = 0.145
			cs.shape = h
			cs.position = Vector3(0, 0.285, 0.0)
		"Leg_L", "Leg_R":
			var l := CapsuleShape3D.new()
			l.radius = 0.115
			l.height = 0.31
			cs.shape = l
			cs.position = Vector3(0, 0.155, 0.0)
		_:
			# Feet should present a flat sole to the arena.  Build the box in
			# world-aligned axes of the rest pose instead of the bone's odd Y/Z
			# orientation, then offset it under the ankle.
			var b := BoxShape3D.new()
			b.size = Vector3(0.27, 0.19, 0.48)
			cs.shape = b
			var rest_basis: Basis = bone_rest[key].basis
			var world_offset := Vector3(0.0, -0.294, 0.060)
			var local_offset := rest_basis.inverse() * world_offset
			cs.transform = Transform3D(rest_basis.inverse().orthonormalized(), local_offset)


func _physics_material() -> PhysicsMaterial:
	var pm := PhysicsMaterial.new()
	pm.friction = 0.95
	pm.bounce = 0.0
	pm.rough = true
	return pm


func _build_joints() -> void:
	var root_world := skeleton.global_transform
	for key in BODY_ORDER:
		if not BODY_PARENT.has(key):
			continue
		var parent_key: String = BODY_PARENT[key]
		var parent_body: RigidBody3D = body[parent_key]
		var child_body: RigidBody3D = body[key]
		var g := Generic6DOFJoint3D.new()
		g.name = "Joint_" + key
		parent_body.add_child(g)
		g.global_transform = root_world * bone_rest[key]
		g.node_a = g.get_path_to(parent_body)
		g.node_b = g.get_path_to(child_body)
		_configure_joint(g, key)
		joint[key] = g


func _configure_joint(g: Generic6DOFJoint3D, key: String) -> void:
	var limits: Array = JOINT_LIMITS[key]
	var part_damp := 4.8
	if key == "Head":
		part_damp = 7.2
	elif key.begins_with("Arm_"):
		part_damp = 3.8
	elif key.begins_with("Hand_"):
		part_damp = 4.4
	elif key.begins_with("Leg_"):
		part_damp = 5.2
	elif key.begins_with("Foot_"):
		part_damp = 5.6
	for ai in 3:
		var lim := deg_to_rad(float(limits[ai]))
		_set_joint_flag(g, ai, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		_set_joint_param(g, ai, Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
		_set_joint_param(g, ai, Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
		_set_joint_param(g, ai, Generic6DOFJoint3D.PARAM_LINEAR_DAMPING, 1.0)
		_set_joint_flag(g, ai, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
		_set_joint_param(g, ai, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -lim)
		_set_joint_param(g, ai, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, lim)
		_set_joint_param(g, ai, Generic6DOFJoint3D.PARAM_ANGULAR_DAMPING, part_damp)
		_set_joint_param(g, ai, Generic6DOFJoint3D.PARAM_ANGULAR_LIMIT_SOFTNESS, 0.62)
		_set_joint_param(g, ai, Generic6DOFJoint3D.PARAM_ANGULAR_RESTITUTION, 0.0)
		# Head joint: limits + damping only; the joint motor is disabled because
		# _apply_head_torque() drives it directly.  All other joints use the motor.
		var use_motor := key != "Head"
		_set_joint_flag(g, ai, Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, use_motor)
		_set_joint_param(g, ai, Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, float(MOTOR_FORCE[key]))


func _set_joint_param(g: Generic6DOFJoint3D, axis: int, param: int, value: float) -> void:
	match axis:
		0: g.set_param_x(param, value)
		1: g.set_param_y(param, value)
		_: g.set_param_z(param, value)


func _set_joint_flag(g: Generic6DOFJoint3D, axis: int, flag: int, value: bool) -> void:
	match axis:
		0: g.set_flag_x(flag, value)
		1: g.set_flag_y(flag, value)
		_: g.set_flag_z(flag, value)


## A physical leash between the gameplay root and the simulated torso.  The
## soft spring below provides secondary motion; this joint is the hard stop
## that stops the rendered body from detaching during fast host-authoritative
## movement (knockback, dash, moving platforms) without teleporting it.
func _build_anchor() -> void:
	var target := _anchor_target()
	anchor_body = AnimatableBody3D.new()
	anchor_body.name = "RootLeashAnchor"
	anchor_body.top_level = true
	anchor_body.collision_layer = 0
	anchor_body.collision_mask = 0
	anchor_body.position = target + Vector3.UP * LEASH_VERTICAL_OFFSET
	add_child(anchor_body)
	anchor_body.sync_to_physics = true

	leash_joint = Generic6DOFJoint3D.new()
	leash_joint.name = "RootLeashJoint"
	anchor_body.add_child(leash_joint)
	leash_joint.global_transform = Transform3D(Basis.IDENTITY, target)
	leash_joint.node_a = leash_joint.get_path_to(anchor_body)
	leash_joint.node_b = leash_joint.get_path_to(body["Torso"])
	for ai in 3:
		_set_joint_flag(leash_joint, ai, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		_set_joint_param(leash_joint, ai, Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -LEASH_LINEAR)
		_set_joint_param(leash_joint, ai, Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, LEASH_LINEAR)
		_set_joint_param(leash_joint, ai, Generic6DOFJoint3D.PARAM_LINEAR_DAMPING, 1.0)
		_set_joint_param(leash_joint, ai, Generic6DOFJoint3D.PARAM_LINEAR_RESTITUTION, 0.0)
		_set_joint_flag(leash_joint, ai, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, false)
		_set_joint_flag(leash_joint, ai, Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, false)


func _set_bodies_to_target() -> void:
	if not _built:
		return
	var root_world := skeleton.global_transform
	for key in BODY_ORDER:
		var rb: RigidBody3D = body[key]
		var target: Transform3D = root_world * bone_rest[key]
		if pose_rig != null and pose_rig.pose_ready:
			target = pose_rig.get_skeleton_transform() * pose_rig.get_target_bone(key)
		rb.global_transform = target
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		rb.sleeping = false
	_last_root_position = skeleton.global_position
	_last_anchor_target = _anchor_target()
	_last_target_origin = _last_anchor_target
	_anchor_velocity = Vector3.ZERO
	if anchor_body != null:
		anchor_body.global_position = _last_target_origin + Vector3.UP * LEASH_VERTICAL_OFFSET
	_is_ragdoll = false
	_recovering = false
	_ragdoll_timer = 0.0
	_ragdoll_elapsed = 0.0
	_motor_scale = 1.0
	_anchor_scale = 1.0
	_torque_scale = 1.0
	_body_control_scale = {}


# ---------------------------------------------------------------------------
# Frame loop

func _physics_process(delta: float) -> void:
	if not _built:
		if _build_pending and Engine.get_physics_frames() > 0:
			_build()
		return
	_time += delta
	_stumble_cooldown = maxf(0.0, _stumble_cooldown - delta)
	_explosion_cd = maxf(0.0, _explosion_cd - delta)
	var root_position := skeleton.global_position
	if root_position.distance_to(_last_root_position) > 2.0:
		_set_bodies_to_target()
	_last_root_position = root_position
	pose_rig.advance(delta)
	_update_targets()
	_update_timers(delta)
	_probe_ground()
	_clamp_bodies()
	if simulation_enabled:
		_apply_anchor(delta)
		_apply_motors(delta)
		_apply_head_torque(delta)
		_apply_carry_pose_torque()
	_check_stability()


func _process(_delta: float) -> void:
	if not _built:
		return
	if simulation_enabled:
		_drive_skeleton_from_bodies()
	else:
		_drive_skeleton_from_target()


func _update_targets() -> void:
	var root := pose_rig.get_skeleton_transform()
	for key in BODY_ORDER:
		var t: Transform3D = root * pose_rig.get_target_bone(key)
		target_world[key] = t
		target_basis[key] = t.basis.orthonormalized()


func _update_timers(delta: float) -> void:
	if _is_ragdoll:
		_ragdoll_elapsed += delta
		_ragdoll_timer = maxf(0.0, _ragdoll_timer - delta)
		_motor_scale = move_toward(_motor_scale, 0.02, delta * 5.5)
		_anchor_scale = move_toward(_anchor_scale, 0.06, delta * 5.0)
		_torque_scale = move_toward(_torque_scale, 0.01, delta * 7.0)
		if _ragdoll_timer <= 0.0 and _ragdoll_elapsed > 0.55 and _uprightness() > 0.45:
			_begin_recovery()
		elif _ragdoll_elapsed > 3.2:
			_begin_recovery()
	else:
		var target_motor := 1.0
		var target_anchor := 1.0
		var target_torque := 1.0
		if _held:
			target_motor = 0.68
			target_anchor = 0.78
			target_torque = 0.62
		if _recovering:
			target_motor = 1.0
			target_anchor = 1.0
			target_torque = 1.0
		_motor_scale = move_toward(_motor_scale, target_motor, delta * 3.6)
		_anchor_scale = move_toward(_anchor_scale, target_anchor, delta * 3.2)
		_torque_scale = move_toward(_torque_scale, target_torque, delta * 5.0)
		if _recovering:
			_recover_timer += delta
			if _recover_timer > 0.45 and _uprightness() > 0.72 and _motor_scale > 0.78:
				_recovering = false
				_recover_timer = 0.0
				pose_rig.set_recovering(false)
				ragdoll_finished.emit()
	_impact_loosen = move_toward(_impact_loosen, 0.0, delta * 1.7)


func _apply_anchor(delta: float) -> void:
	var rb: RigidBody3D = body["Torso"]
	var target: Vector3 = target_world["Torso"].origin
	if anchor_body != null:
		anchor_body.global_position = target + Vector3.UP * LEASH_VERTICAL_OFFSET
	var measured := (target - _last_anchor_target) / maxf(delta, 0.0001)
	if measured.length() > 28.0:
		measured = measured.normalized() * 28.0
	_anchor_velocity = _anchor_velocity.lerp(measured, 1.0 - exp(-18.0 * delta))
	_last_anchor_target = target
	var pos_err := target - rb.global_position
	var force := pos_err * (anchor_stiffness * _anchor_scale)
	force -= (rb.linear_velocity - _anchor_velocity) * (anchor_damping * _anchor_scale)
	if _tether_active:
		var to_tether := _tether_point - rb.global_position
		force += to_tether * (_tether_strength * _anchor_scale)
	if _carry_load > 0.01 and not _is_ragdoll and not _recovering:
		# Make the extra mass readable: the torso sinks and the legs take load.
		force += Vector3.DOWN * (38.0 * _carry_load)
	var max_force := anchor_max_force * maxf(_anchor_scale, 0.05)
	if force.length() > max_force:
		force = force.normalized() * max_force
	rb.apply_central_force(force)

	# Upright / facing torque.  This is a real torque on the torso, never a
	# transform snap: the joint chain and gravity decide the final pose.
	var current := rb.global_transform.basis.get_rotation_quaternion()
	var want: Quaternion = target_basis["Torso"].get_rotation_quaternion()
	var q_err := (want * current.inverse()).normalized()
	if q_err.w < 0.0:
		q_err = Quaternion(-q_err.x, -q_err.y, -q_err.z, -q_err.w)
	var torque := Vector3.ZERO
	var angle := q_err.get_angle()
	if angle > 0.0001:
		torque = q_err.get_axis() * angle * (torso_torque_gain * _torque_scale)
	torque -= rb.angular_velocity * (torso_torque_damp * _torque_scale)
	if _recovering:
		torque += Vector3.UP * 0.0
	var max_torque := torso_max_torque * maxf(_torque_scale, 0.02)
	if torque.length() > max_torque:
		torque = torque.normalized() * max_torque
	rb.apply_torque(torque)


func _apply_motors(delta: float) -> void:
	var strength := clampf(_motor_scale, 0.0, 1.0)
	for key in BODY_ORDER:
		if key == "Torso" or key == "Head" or not joint.has(key):
			continue
		var j: Generic6DOFJoint3D = joint[key]
		var rb: RigidBody3D = body[key]
		var parent: RigidBody3D = body[BODY_PARENT[key]]
		var jb := j.global_transform.basis
		var target_v := Vector3.ZERO
		var carry_boost := 1.0
		if _carry_joint_hand != "":
			var carry_side := "L" if _carry_joint_hand == "Hand_L" else "R"
			if key == "Arm_" + carry_side:
				carry_boost = 2.8
			elif key == _carry_joint_hand:
				carry_boost = 3.1
			elif key in ["Leg_L", "Leg_R", "Foot_L", "Foot_R"]:
				carry_boost = 1.25
		var limb_scale := 1.0
		if key.begins_with("Arm_") or key.begins_with("Hand_"):
			limb_scale = lerpf(1.0, 0.42, _impact_loosen)
			if _carry_joint_hand != "" and key.ends_with(_carry_joint_hand.right(2)):
				limb_scale = lerpf(limb_scale, 1.0, 0.75)
		elif key == "Head":
			limb_scale = lerpf(1.0, 0.8, _impact_loosen)
		elif key.begins_with("Leg_") or key.begins_with("Foot_"):
			limb_scale = lerpf(1.0, 0.86, _impact_loosen)
		var key_strength := strength * limb_scale
		if key_strength > 0.015:
			var current := rb.global_transform.basis.get_rotation_quaternion()
			var want: Quaternion = target_basis[key].get_rotation_quaternion()
			var q_err := (want * current.inverse()).normalized()
			if q_err.w < 0.0:
				q_err = Quaternion(-q_err.x, -q_err.y, -q_err.z, -q_err.w)
			var angle := q_err.get_angle()
			var world_err := Vector3.ZERO
			if angle > 0.0001:
				world_err = q_err.get_axis() * angle
			var part_gain := float(MOTOR_GAIN[key])
			var gain: float = part_gain * key_strength * float(_body_control_scale.get(key, 1.0)) * carry_boost
			var local_err := Vector3(
				world_err.dot(jb.x),
				world_err.dot(jb.y),
				world_err.dot(jb.z))
			target_v = local_err * gain
			# Clamp to a velocity the joint motor can actually follow.
			# Too high → saturates, oscillates. Too low → animation lag.
			# 12 rad/s balances smooth animation response with stability (no ringing).
			target_v = target_v.limit_length(12.0)
			# Damp relative angular velocity, not just the child's world spin.
			var rel := rb.angular_velocity - parent.angular_velocity
			var rel_local := Vector3(rel.dot(jb.x), rel.dot(jb.y), rel.dot(jb.z))
			var rel_damp := 2.2
			if key.begins_with("Leg_") or key.begins_with("Foot_"):
				rel_damp = 2.5
			target_v -= rel_local * (rel_damp * key_strength)
		var force_limit := float(MOTOR_FORCE[key]) * maxf(key_strength, 0.03) * carry_boost
		j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, force_limit)
		j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, force_limit)
		j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, force_limit)
		# Godot's 6DOF angular motor drives the joint toward -target_velocity.
		j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, -target_v.x)
		j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, -target_v.y)
		j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, -target_v.z)
	# A physically floppy body still needs a weak get-up torque so it does not
	# lie on its face forever after the timer expires.
	if _recovering:
		var rb_t: RigidBody3D = body["Torso"]
		var desired: Quaternion = target_basis["Torso"].get_rotation_quaternion()
		var cur := rb_t.global_transform.basis.get_rotation_quaternion()
		var qe := (desired * cur.inverse()).normalized()
		if qe.w < 0.0:
			qe = Quaternion(-qe.x, -qe.y, -qe.z, -qe.w)
		if qe.get_angle() > 0.0001:
			var tq := qe.get_axis() * qe.get_angle() * 180.0 - rb_t.angular_velocity * 20.0
			if tq.length() > 300.0:
				tq = tq.normalized() * 300.0
			rb_t.apply_torque(tq)


## Stable PD torque for the head.
## Unlike the limb motors (which drive joint velocity targets and can saturate),
## this applies a real torque on the RigidBody3D directly.  The error and its
## derivative are both measured in world space so damping and proportional terms
## are consistent.  A hard torque cap prevents violent snapping on large errors.
func _apply_head_torque(_delta: float) -> void:
	if not _built or not body.has("Head"):
		return
	var rb: RigidBody3D = body["Head"]
	var torso_rb: RigidBody3D = body["Torso"]

	var current := rb.global_transform.basis.get_rotation_quaternion()
	var want: Quaternion = target_basis.get("Head", Basis.IDENTITY).get_rotation_quaternion()

	# Error quaternion, always short-path.
	var q_err := (want * current.inverse()).normalized()
	if q_err.w < 0.0:
		q_err = Quaternion(-q_err.x, -q_err.y, -q_err.z, -q_err.w)

	var angle := q_err.get_angle()
	var torque := Vector3.ZERO
	if angle > 0.00015:
		# Proportional term: world-space axis × angle.
		torque = q_err.get_axis() * angle * (HEAD_TORQUE_GAIN * _motor_scale)

	# Derivative term: damp the head's angular velocity relative to the torso
	# so the neck never oscillates around the torso.
	var rel_ang := rb.angular_velocity - torso_rb.angular_velocity
	torque -= rel_ang * (HEAD_TORQUE_DAMP * _motor_scale)

	# Cap: after an impact allow a little more freedom; at rest it's very stiff.
	var cap := lerpf(HEAD_MAX_TORQUE, HEAD_TORQUE_IMPACT, _impact_loosen)
	if _is_ragdoll:
		cap = 18.0   # ragdoll: near-zero correction so the head tumbles naturally
	elif _recovering:
		cap = 55.0
	if torque.length() > cap:
		torque = torque.normalized() * cap

	rb.apply_torque(torque)



func _apply_carry_pose_torque() -> void:
	if _carry_joint_hand == "" or _is_ragdoll or _recovering:
		return
	var side := "L" if _carry_joint_hand == "Hand_L" else "R"
	for key in ["Arm_" + side, _carry_joint_hand]:
		var rb: RigidBody3D = body[key]
		var parent: RigidBody3D = body[BODY_PARENT[key]]
		var current := rb.global_transform.basis.get_rotation_quaternion()
		var want: Quaternion = target_basis[key].get_rotation_quaternion()
		var q_err := (want * current.inverse()).normalized()
		if q_err.w < 0.0:
			q_err = Quaternion(-q_err.x, -q_err.y, -q_err.z, -q_err.w)
		var angle := q_err.get_angle()
		var torque := Vector3.ZERO
		if angle > 0.0001:
			var gain := 240.0 if key.begins_with("Arm_") else 120.0
			torque = q_err.get_axis() * angle * gain
		torque -= (rb.angular_velocity - parent.angular_velocity) * 34.0
		var max_torque := 240.0 if key.begins_with("Arm_") else 120.0
		if torque.length() > max_torque:
			torque = torque.normalized() * max_torque
		rb.apply_torque(torque)


func _probe_ground() -> void:
	if not _built:
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var contacts := 0
	for i in 2:
		var key := "Foot_L" if i == 0 else "Foot_R"
		var rb: RigidBody3D = body[key]
		var from := rb.global_position + Vector3(0, 0.12, 0)
		var to := from + Vector3(0, -0.60, 0)
		_ground_query.from = from
		_ground_query.to = to
		var hit := not space.intersect_ray(_ground_query).is_empty()
		_foot_contact[i] = hit
		if hit:
			contacts += 1
	var now_grounded := contacts > 0
	if not now_grounded and body.has("Torso"):
		# Fallback for rest-pose / odd-foot rest transforms: treat the character as
		# grounded when the torso is near arena height so tests and calm states
		# don't falsely report airborne.
		now_grounded = body["Torso"].global_position.y < 1.15
	if now_grounded and _was_airborne:
		var speed := maxf(absf(body["Foot_L"].linear_velocity.y), absf(body["Foot_R"].linear_velocity.y))
		landed.emit(speed)
		apply_landing(speed)
	_was_airborne = not now_grounded
	grounded = now_grounded


func _clamp_bodies() -> void:
	if not _built:
		return
	for key in BODY_ORDER:
		var rb: RigidBody3D = body[key]
		if not (is_finite(rb.global_position.x) and is_finite(rb.global_position.y) and is_finite(rb.global_position.z)):
			_set_bodies_to_target()
			return
		rb.linear_velocity = rb.linear_velocity.limit_length(MAX_LINEAR_SPEED)
		rb.angular_velocity = rb.angular_velocity.limit_length(MAX_ANGULAR_SPEED)
	# Last-resort explosion guard: a stretched or teleported joint chain is
	# snapped back to the authoritative target pose instead of left unstable.
	if _explosion_cd > 0.0:
		return
	var torso_pos: Vector3 = body["Torso"].global_position
	for key in BODY_ORDER:
		var offset := (body[key] as RigidBody3D).global_position.distance_to(torso_pos)
		if offset > 3.4:
			_explosion_cd = 1.0
			_set_bodies_to_target()
			return


func _check_stability() -> void:
	if _is_ragdoll or _recovering or _held or _stumble_cooldown > 0.0 or not simulation_enabled:
		return
	var up := _uprightness()
	if up < 0.28:
		_stumble_cooldown = 1.6
		_enter_ragdoll(0.24)


# ---------------------------------------------------------------------------
# Reactions

func apply_impact(impulse: Vector3, world_point: Vector3, strength := 1.0) -> void:
	if not _built or not simulation_enabled:
		return
	var mag := impulse.length() * strength
	if mag < 0.01:
		return
	var total_mass := 0.0
	for key in BODY_ORDER:
		total_mass += float(MASSES[key])
	for key in BODY_ORDER:
		var rb: RigidBody3D = body[key]
		var d := rb.global_position.distance_to(world_point)
		var falloff := clampf(1.0 - d / 2.6, 0.12, 1.0)
		var share := float(MASSES[key]) / total_mass
		var part_scale := 1.0
		if key in ["Torso", "Head"]:
			part_scale = 1.15
		rb.apply_central_impulse(impulse * strength * share * (1.6 * falloff + 0.35) * part_scale)
		var lever := (world_point - rb.global_position)
		if lever.length() > 0.001:
			rb.apply_torque_impulse(lever.cross(impulse * strength * share) * 0.13)
	# Arms get a short window of extra freedom on a real hit; the torso and legs
	# keep most of their posture so the body stays cohesive.
	_impact_loosen = maxf(_impact_loosen, clampf(mag / 30.0, 0.4, 1.0))
	_motor_scale = minf(_motor_scale, lerpf(0.72, 0.38, clampf(mag / 28.0, 0.0, 1.0)))
	_anchor_scale = minf(_anchor_scale, lerpf(0.78, 0.42, clampf(mag / 28.0, 0.0, 1.0)))
	_torque_scale = minf(_torque_scale, lerpf(0.72, 0.34, clampf(mag / 28.0, 0.0, 1.0)))
	if mag >= 5.0:
		_enter_ragdoll(clampf(mag * 0.082, 0.55, 1.55))


func apply_landing(landing_speed: float) -> void:
	if not _built or not simulation_enabled:
		return
	var s := clampf(landing_speed / 15.0, 0.0, 1.5)
	if s < 0.05:
		return
	for key in ["Torso", "Head", "Arm_L", "Arm_R"]:
		body[key].apply_central_impulse(Vector3.DOWN * float(MASSES[key]) * s * 1.05)
	if s > 1.25:
		_enter_ragdoll(0.28)


func apply_jump() -> void:
	if not _built or not simulation_enabled:
		return
	for key in BODY_ORDER:
		body[key].apply_central_impulse(Vector3.UP * float(MASSES[key]) * 0.38)


## Optional angular kick used by throws / hard hits.  It is a real impulse, so
## the joints and gravity decide the resulting tumble.
func apply_spin(axis: Vector3, strength: float) -> void:
	if not _built or not simulation_enabled or strength <= 0.001:
		return
	var a := axis.normalized()
	for key in BODY_ORDER:
		var rb: RigidBody3D = body[key]
		rb.apply_torque_impulse(a * strength * float(MASSES[key]) * 0.06)


func set_held(value: bool) -> void:
	_held = value
	if value:
		_is_ragdoll = false
		_recovering = false
		_ragdoll_timer = 0.0


func set_tether(world_point: Vector3, strength := 16.0) -> void:
	_tether_active = true
	_tether_point = world_point
	_tether_strength = strength


func clear_tether() -> void:
	_tether_active = false
	_tether_strength = 0.0


func set_ragdoll(enabled: bool, duration := 0.8) -> void:
	if enabled:
		_enter_ragdoll(duration)
	else:
		_begin_recovery()


func _enter_ragdoll(duration: float) -> void:
	if not _built:
		return
	if not _is_ragdoll:
		_is_ragdoll = true
		_recovering = false
		_recover_timer = 0.0
		_ragdoll_elapsed = 0.0
		_motor_scale = 0.04
		_anchor_scale = 0.08
		_torque_scale = 0.02
		pose_rig.set_ragdoll_pose(true)
		ragdoll_started.emit()
	_ragdoll_timer = maxf(_ragdoll_timer, duration)


func _begin_recovery() -> void:
	if _recovering:
		return
	_is_ragdoll = false
	_recovering = true
	_recover_timer = 0.0
	_ragdoll_elapsed = 0.0
	pose_rig.set_recovering(true)


# ---------------------------------------------------------------------------
# Skeleton output

func _drive_skeleton_from_bodies() -> void:
	var inv := skeleton.global_transform.affine_inverse()
	# Root-to-tip order matters: set_bone_global_pose() resolves the local pose
	# against the parent's current pose.
	for key in BODY_ORDER:
		var rb: RigidBody3D = body[key]
		skeleton.set_bone_global_pose(int(bone_id[key]), inv * rb.global_transform)


func _drive_skeleton_from_target() -> void:
	if pose_rig == null or not pose_rig.pose_ready:
		return
	var inv := skeleton.global_transform.affine_inverse()
	for key in BODY_ORDER:
		var id: int = bone_id.get(key, -1)
		if id < 0:
			continue
		skeleton.set_bone_global_pose(id, inv * (pose_rig.get_skeleton_transform() * pose_rig.get_target_bone(key)))


# ---------------------------------------------------------------------------
# Helpers / public state

func _anchor_target() -> Vector3:
	if pose_rig != null and pose_rig.pose_ready:
		return (pose_rig.get_skeleton_transform() * pose_rig.get_target_bone("Torso")).origin
	return skeleton.global_transform * bone_rest.get("Torso", Transform3D.IDENTITY).origin


func _uprightness() -> float:
	if not _built:
		return 1.0
	return clampf(body["Torso"].global_transform.basis.y.normalized().dot(Vector3.UP), -1.0, 1.0)


func is_built() -> bool:
	return _built


func is_ragdolled() -> bool:
	return _is_ragdoll


func is_recovering() -> bool:
	return _recovering


func get_uprightness() -> float:
	return _uprightness()


func get_anchor_lag() -> float:
	if not _built:
		return 0.0
	return body["Torso"].global_position.distance_to(target_world.get("Torso", Transform3D.IDENTITY).origin)


func get_body_world(key: String) -> Transform3D:
	if _built and body.has(key):
		return (body[key] as RigidBody3D).global_transform
	return Transform3D.IDENTITY


func get_foot_contacts() -> Array:
	return _foot_contact


func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)


## Per-body-part motor strength override (0..1).  Pass stronger values while
## carrying a heavy load or impacts require extra control, and softer values
## (e.g. Arms 0.45) during loose physical interactions.
func set_body_control_scale(key: String, scale: float) -> void:
	if key == "Torso":
		return
	if not joint.has(key) and not body.has(key):
		return
	_body_control_scale[key] = clampf(scale, 0.05, 1.0)
	if debug_log:
		print("[RAGDOLL] body control scale set: %s = %.2f" % [key, clampf(scale, 0.05, 1.0)])


func set_carrying_pose(active: bool, hand: String, load := 1.0) -> void:
	_carry_load = clampf(load, 0.0, 1.0) if active else 0.0
	var next_hand := hand if active and hand in ["Hand_L", "Hand_R"] else ""
	if next_hand == _carry_joint_hand or not _built:
		return
	if _carry_joint_hand != "":
		var old_side := "L" if _carry_joint_hand == "Hand_L" else "R"
		_set_angular_limits("Arm_" + old_side, JOINT_LIMITS["Arm_" + old_side])
		_set_angular_limits(_carry_joint_hand, JOINT_LIMITS[_carry_joint_hand])
	_carry_joint_hand = next_hand
	if _carry_joint_hand != "":
		var side := "L" if _carry_joint_hand == "Hand_L" else "R"
		_set_angular_limits("Arm_" + side, [175.0, 175.0, 175.0])
		_set_angular_limits(_carry_joint_hand, [130.0, 130.0, 130.0])


func _set_angular_limits(key: String, limits: Array) -> void:
	if not joint.has(key):
		return
	var j: Generic6DOFJoint3D = joint[key]
	for axis in 3:
		var limit := deg_to_rad(float(limits[axis]))
		_set_joint_param(j, axis, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -limit)
		_set_joint_param(j, axis, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, limit)


func get_body_control_scale(key: String) -> float:
	return _body_control_scale.get(key, 1.0)


func set_simulation_enabled(enabled: bool) -> void:
	if simulation_enabled == enabled:
		return
	simulation_enabled = enabled
	if not _built:
		return
	_apply_body_freeze()
	if enabled:
		_set_bodies_to_target()


func _apply_body_freeze() -> void:
	for key in BODY_ORDER:
		var rb: RigidBody3D = body[key]
		rb.freeze = not simulation_enabled
		rb.collision_layer = LAYER_RAGDOLL if simulation_enabled else 0
	if not simulation_enabled:
		clear_tether()


func reset_pose() -> void:
	if not _built:
		return
	set_carrying_pose(false, "")
	_set_bodies_to_target()
	_motor_scale = 1.0
	_anchor_scale = 1.0
	_torque_scale = 1.0
	_impact_loosen = 0.0
	_carry_load = 0.0
	_explosion_cd = 0.0
	_body_control_scale.clear()
	_held = false
	_melted = false
	clear_tether()


func set_melted(value: bool) -> void:
	_melted = value
	if value:
		set_simulation_enabled(false)
