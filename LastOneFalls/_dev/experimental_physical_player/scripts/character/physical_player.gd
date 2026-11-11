extends Node3D
class_name PhysicalPlayer
## PhysicalPlayer - BombSquad-style active ragdoll character controller.
##
## The actual articulated RigidBody3D rig drives movement.  The visual skeleton
## follows the physics bodies every physics frame.  No CharacterBody3D is used
## for locomotion; all movement comes from forces, impulses, and joint motors
## applied to the physical bodies.

const GameConstants := preload("res://scripts/game_constants.gd")
const AudioManager := preload("res://scripts/audio_manager.gd")

# ---------------------------------------------------------------------------
# Input actions
const ACTION_MOVE_LEFT := "move_left"
const ACTION_MOVE_RIGHT := "move_right"
const ACTION_MOVE_FORWARD := "move_forward"
const ACTION_MOVE_BACK := "move_back"
const ACTION_JUMP := "jump"
const ACTION_PUSH := "push"
const ACTION_DASH := "dash"

# ---------------------------------------------------------------------------
# Physical segment tuning
const MASS_TORSO := 12.0
const MASS_HEAD := 2.5
const MASS_ARM := 1.5
const MASS_HAND := 0.8
const MASS_LEG := 3.0
const MASS_FOOT := 1.2

const LINEAR_DAMP := 0.1
const ANGULAR_DAMP := 0.5

# PD controller gains
const PD_P := 40.0
const PD_D := 8.0
const MAX_TORSO_TORQUE := 60.0
const MAX_LIMB_TORQUE := 30.0

# Movement forces
const WALK_SPEED := 5.5
const RUN_SPEED := 9.0
const JUMP_IMPULSE := 11.0
const GRAVITY_SCALE := 1.2

# ---------------------------------------------------------------------------
# Exported / runtime state
var peer_id := 1
var player_name := "Player"
var color_index := 0
var is_bot := false
var is_local := false
var is_alive := true
var team := 0
var round_manager: Node = null

var move_input := Vector2.ZERO
var jump_requested := false
var push_requested := false
var dash_requested := false
var facing_yaw := 0.0
var cam_yaw := 0.0
var _push_charge := 0.0

var _physics_tick := 0.0
var _fixed_delta := 1.0 / 60.0

# Physics bodies
var torso_body: RigidBody3D
var head_body: RigidBody3D
var arm_l_upper: RigidBody3D
var arm_l_lower: RigidBody3D
var arm_r_upper: RigidBody3D
var arm_r_lower: RigidBody3D
var leg_l_upper: RigidBody3D
var leg_l_lower: RigidBody3D
var leg_r_upper: RigidBody3D
var leg_r_lower: RigidBody3D

# Joints
var joint_neck: Generic6DOFJoint3D
var joint_shoulder_l: Generic6DOFJoint3D
var joint_elbow_l: HingeJoint3D
var joint_shoulder_r: Generic6DOFJoint3D
var joint_elbow_r: HingeJoint3D
var joint_hip_l: Generic6DOFJoint3D
var joint_knee_l: HingeJoint3D
var joint_hip_r: Generic6DOFJoint3D
var joint_knee_r: HingeJoint3D

# Visual skeleton
var skeleton: Skeleton3D
var mesh_root: Node3D

# Controllers (set in _setup_controllers)
var locomotion: LocomotionController
var pose_controller: PoseController
var interaction: InteractionController
var grab_controller: GrabController
var balance_controller: BalanceController

# State
var state: String = "idle"
var grounded := false
var _stun := 0.0
var _dash_timer := 0.0
var _dash_cd := 0.0

# Grab state
var grabbing_id := 0
var grabbed_by := 0
var grab_phase := 0

# Multiplayer
var _sync_accum := 0.0
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_received := false

signal jump_performed
signal attack_performed


func _ready() -> void:
	add_to_group("players")
	is_local = (not is_bot) and is_multiplayer_authority()
	_build_rig()
	_setup_controllers()
	_reset_to_standing()


func _process(_delta: float) -> void:
	_gather_input()
	_update_camera(_delta)


func _physics_process(delta: float) -> void:
	if not is_alive:
		return
	_physics_tick += delta
	while _physics_tick >= _fixed_delta:
		_physics_tick -= _fixed_delta
		_fixed_simulate(_fixed_delta)
	_sync_visuals()


func _fixed_simulate(delta: float) -> void:
	_match_state(delta)

	locomotion.update(delta)
	pose_controller.apply_joint_control(delta)
	balance_controller.update(delta)
	interaction.update(delta)
	grab_controller.update(delta)

	torso_body.gravity_scale = GRAVITY_SCALE

	if state != "ragdoll" and state != "recover":
		torso_body.angular_velocity = torso_body.angular_velocity.lerp(Vector3.ZERO, 1.0 - exp(-10.0 * delta))


func _match_state(delta: float) -> void:
	var was_grounded := grounded
	grounded = _is_grounded()

	if grabbed_by != 0 and grab_phase == 1:
		state = "carried"
		return
	if grabbed_by != 0 and grab_phase == 0:
		state = "grabbed_pull"
		return
	if grabbing_id != 0 and grab_phase == 1:
		state = "carrying"
		return

	if not grounded:
		if torso_body.linear_velocity.y < -2.0:
			state = "fall"
		else:
			state = "jump"
		return

	if _dash_timer > 0.0:
		state = "dash"
		_dash_timer = maxf(0.0, _dash_timer - delta)
		return
	if _stun > 0.0:
		state = "hit"
		_stun = maxf(0.0, _stun - delta)
		return
	if move_input.length() > 0.1:
		state = "run" if _dash_timer > 0.0 else "walk"
	else:
		state = "idle"


func _is_grounded() -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var from := torso_body.global_position
	var to := from + Vector3.DOWN * 1.1
	var q := PhysicsRayQueryParameters3D.create(from, to, GameConstants.LAYER_WORLD)
	var result := space.intersect_ray(q)
	return not result.is_empty()


func _gather_input() -> void:
	var input := Vector2.ZERO
	input.x = Input.get_action_strength(ACTION_MOVE_RIGHT) - Input.get_action_strength(ACTION_MOVE_LEFT)
	input.y = Input.get_action_strength(ACTION_MOVE_BACK) - Input.get_action_strength(ACTION_MOVE_FORWARD)
	if input.length() > 1.0:
		input = input.normalized()
	move_input = input

	if Input.is_action_just_pressed(ACTION_JUMP):
		jump_requested = true
	if Input.is_action_just_pressed(ACTION_PUSH):
		push_requested = true
	if Input.is_action_just_pressed(ACTION_DASH):
		dash_requested = true


func _update_camera(delta: float) -> void:
	var cam_pivot := get_node_or_null("CameraPivot")
	if cam_pivot == null:
		return
	var target := torso_body.global_position + Vector3(0, 1.6, 0)
	cam_pivot.global_position = cam_pivot.global_position.lerp(target, 1.0 - exp(-12.0 * delta))
	cam_pivot.rotation.y = cam_yaw


func _setup_controllers() -> void:
	locomotion = LocomotionController.new()
	locomotion.name = "LocomotionController"
	add_child(locomotion)
	locomotion.rig = self

	pose_controller = PoseController.new()
	pose_controller.name = "PoseController"
	add_child(pose_controller)
	pose_controller.rig = self

	interaction = InteractionController.new()
	interaction.name = "InteractionController"
	add_child(interaction)
	interaction.rig = self

	grab_controller = GrabController.new()
	grab_controller.name = "GrabController"
	add_child(grab_controller)
	grab_controller.rig = self

	balance_controller = BalanceController.new()
	balance_controller.name = "BalanceController"
	add_child(balance_controller)
	balance_controller.rig = self


func _build_rig() -> void:
	var physics_rig := Node3D.new()
	physics_rig.name = "PhysicsRig"
	add_child(physics_rig)

	var joints := Node3D.new()
	joints.name = "PhysicsJoints"
	add_child(joints)

	var skel_root := Node3D.new()
	skel_root.name = "CharacterSkeleton"
	add_child(skel_root)

	var model_scene := preload("res://NewAssets/Model/contender.glb")
	var model_root := model_scene.instantiate() as Node3D
	if model_root == null:
		push_error("PhysicalPlayer: could not instantiate contender.glb")
		return
	model_root.name = "ContenderModel"
	model_root.rotation.y = PI
	skel_root.add_child(model_root)

	skeleton = model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		push_error("PhysicalPlayer: Skeleton3D missing from contender.glb")
		return
	skeleton.name = "CharacterSkeleton"

	# ------------------------------------------------------------------
	# Physics bodies
	# ------------------------------------------------------------------

	torso_body = _create_body("TorsoBody", MASS_TORSO, _make_capsule(0.45, 1.2))
	torso_body.position = Vector3(0, 2.75, 0)
	torso_body.linear_damp = LINEAR_DAMP
	torso_body.angular_damp = ANGULAR_DAMP
	physics_rig.add_child(torso_body)

	head_body = _create_body("HeadBody", MASS_HEAD, _make_capsule(0.3, 0.5))
	head_body.position = Vector3(0, 4.0, -0.1)
	head_body.linear_damp = LINEAR_DAMP
	head_body.angular_damp = 0.3
	physics_rig.add_child(head_body)

	arm_l_upper = _create_body("Arm_L_Upper", MASS_ARM, _make_capsule(0.2, 0.7))
	arm_l_upper.position = Vector3(1.27, 3.4, 0)
	arm_l_upper.linear_damp = LINEAR_DAMP
	arm_l_upper.angular_damp = ANGULAR_DAMP
	physics_rig.add_child(arm_l_upper)

	arm_l_lower = _create_body("Arm_L_Lower", MASS_HAND, _make_capsule(0.18, 0.8))
	arm_l_lower.position = Vector3(1.27, 4.2, 0)
	arm_l_lower.linear_damp = LINEAR_DAMP
	arm_l_lower.angular_damp = ANGULAR_DAMP
	physics_rig.add_child(arm_l_lower)

	arm_r_upper = _create_body("Arm_R_Upper", MASS_ARM, _make_capsule(0.2, 0.7))
	arm_r_upper.position = Vector3(-1.27, 3.4, 0)
	arm_r_upper.linear_damp = LINEAR_DAMP
	arm_r_upper.angular_damp = ANGULAR_DAMP
	physics_rig.add_child(arm_r_upper)

	arm_r_lower = _create_body("Arm_R_Lower", MASS_HAND, _make_capsule(0.18, 0.8))
	arm_r_lower.position = Vector3(-1.27, 4.2, 0)
	arm_r_lower.linear_damp = LINEAR_DAMP
	arm_r_lower.angular_damp = ANGULAR_DAMP
	physics_rig.add_child(arm_r_lower)

	leg_l_upper = _create_body("Leg_L_Upper", MASS_LEG, _make_capsule(0.3, 0.9))
	leg_l_upper.position = Vector3(0.69, 1.87, 0)
	leg_l_upper.linear_damp = LINEAR_DAMP
	leg_l_upper.angular_damp = ANGULAR_DAMP
	physics_rig.add_child(leg_l_upper)

	leg_l_lower = _create_body("Leg_L_Lower", MASS_FOOT, _make_capsule(0.28, 0.9))
	leg_l_lower.position = Vector3(0.69, 0.95, 0)
	leg_l_lower.linear_damp = LINEAR_DAMP
	leg_l_lower.angular_damp = ANGULAR_DAMP
	physics_rig.add_child(leg_l_lower)

	leg_r_upper = _create_body("Leg_R_Upper", MASS_LEG, _make_capsule(0.3, 0.9))
	leg_r_upper.position = Vector3(-0.69, 1.87, 0)
	leg_r_upper.linear_damp = LINEAR_DAMP
	leg_r_upper.angular_damp = ANGULAR_DAMP
	physics_rig.add_child(leg_r_upper)

	leg_r_lower = _create_body("Leg_R_Lower", MASS_FOOT, _make_capsule(0.28, 0.9))
	leg_r_lower.position = Vector3(-0.69, 0.95, 0)
	leg_r_lower.linear_damp = LINEAR_DAMP
	leg_r_lower.angular_damp = ANGULAR_DAMP
	physics_rig.add_child(leg_r_lower)

	# ------------------------------------------------------------------
	# Joints
	# ------------------------------------------------------------------

	joint_neck = _make_6dof_joint("Joint_Neck", torso_body, head_body, 50.0, 10.0)
	joint_neck.position = torso_body.global_position + Vector3(0, 0.6, 0)
	joints.add_child(joint_neck)

	joint_shoulder_l = _make_6dof_joint("Joint_Shoulder_L", torso_body, arm_l_upper, 40.0, 8.0)
	joint_shoulder_l.position = torso_body.global_position + Vector3(0.6, 0.65, 0)
	joints.add_child(joint_shoulder_l)

	joint_elbow_l = _make_hinge_joint("Joint_Elbow_L", arm_l_upper, arm_l_lower)
	joint_elbow_l.position = arm_l_upper.global_position + Vector3(0, 0.35, 0)
	joints.add_child(joint_elbow_l)

	joint_shoulder_r = _make_6dof_joint("Joint_Shoulder_R", torso_body, arm_r_upper, 40.0, 8.0)
	joint_shoulder_r.position = torso_body.global_position + Vector3(-0.6, 0.65, 0)
	joints.add_child(joint_shoulder_r)

	joint_elbow_r = _make_hinge_joint("Joint_Elbow_R", arm_r_upper, arm_r_lower)
	joint_elbow_r.position = arm_r_upper.global_position + Vector3(0, 0.35, 0)
	joints.add_child(joint_elbow_r)

	joint_hip_l = _make_6dof_joint("Joint_Hip_L", torso_body, leg_l_upper, 45.0, 9.0)
	joint_hip_l.position = torso_body.global_position + Vector3(0.4, -0.6, 0)
	joints.add_child(joint_hip_l)

	joint_knee_l = _make_hinge_joint("Joint_Knee_L", leg_l_upper, leg_l_lower)
	joint_knee_l.position = leg_l_upper.global_position + Vector3(0, -0.45, 0)
	joints.add_child(joint_knee_l)

	joint_hip_r = _make_6dof_joint("Joint_Hip_R", torso_body, leg_r_upper, 45.0, 9.0)
	joint_hip_r.position = torso_body.global_position + Vector3(-0.4, -0.6, 0)
	joints.add_child(joint_hip_r)

	joint_knee_r = _make_hinge_joint("Joint_Knee_R", leg_r_upper, leg_r_lower)
	joint_knee_r.position = leg_r_upper.global_position + Vector3(0, -0.45, 0)
	joints.add_child(joint_knee_r)

	# ------------------------------------------------------------------
	# Camera
	# ------------------------------------------------------------------
	var cam_pivot := Node3D.new()
	cam_pivot.name = "CameraPivot"
	cam_pivot.position = Vector3(0, 1.6, 0)
	add_child(cam_pivot)

	var spring_arm := SpringArm3D.new()
	spring_arm.name = "SpringArm3D"
	spring_arm.spring_length = 6.0
	spring_arm.collision_mask = 1
	cam_pivot.add_child(spring_arm)

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 70
	spring_arm.add_child(cam)


func _create_body(name: String, mass: float, shape: CollisionShape3D) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = name
	body.mass = mass
	body.collision_layer = 2
	body.collision_mask = 3
	body.can_sleep = false
	body.gravity_scale = GRAVITY_SCALE
	body.add_child(shape)
	return body


func _make_capsule(radius: float, height: float) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = height
	shape.shape = capsule
	return shape


func _make_box(x: float, y: float, z: float) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(x, y, z)
	shape.shape = box
	return shape


func _make_6dof_joint(name: String, a: RigidBody3D, b: RigidBody3D,
		stiffness: float, damping: float) -> Generic6DOFJoint3D:
	var j := Generic6DOFJoint3D.new()
	j.name = name
	j.node_a = a.get_path()
	j.node_b = b.get_path()
	return j


func _make_hinge_joint(name: String, a: RigidBody3D, b: RigidBody3D) -> HingeJoint3D:
	var j := HingeJoint3D.new()
	j.name = name
	j.node_a = a.get_path()
	j.node_b = b.get_path()
	return j


func _reset_to_standing() -> void:
	torso_body.global_position = Vector3(0, 3.5, 0)
	torso_body.linear_velocity = Vector3.ZERO
	torso_body.angular_velocity = Vector3.ZERO
	torso_body.quaternion = Quaternion.IDENTITY

	head_body.global_position = Vector3(0, 4.0, -0.1)
	head_body.quaternion = Quaternion.IDENTITY

	arm_l_upper.global_position = Vector3(1.27, 3.4, 0)
	arm_l_upper.quaternion = Quaternion.IDENTITY
	arm_l_lower.global_position = Vector3(1.27, 4.2, 0)
	arm_l_lower.quaternion = Quaternion.IDENTITY

	arm_r_upper.global_position = Vector3(-1.27, 3.4, 0)
	arm_r_upper.quaternion = Quaternion.IDENTITY
	arm_r_lower.global_position = Vector3(-1.27, 4.2, 0)
	arm_r_lower.quaternion = Quaternion.IDENTITY

	leg_l_upper.global_position = Vector3(0.69, 1.87, 0)
	leg_l_upper.quaternion = Quaternion.IDENTITY
	leg_l_lower.global_position = Vector3(0.69, 0.95, 0)
	leg_l_lower.quaternion = Quaternion.IDENTITY

	leg_r_upper.global_position = Vector3(-0.69, 1.87, 0)
	leg_r_upper.quaternion = Quaternion.IDENTITY
	leg_r_lower.global_position = Vector3(-0.69, 0.95, 0)
	leg_r_lower.quaternion = Quaternion.IDENTITY


func _sync_visuals() -> void:
	if skeleton == null:
		return

	var torso_bone := skeleton.find_bone("Torso")
	if torso_bone >= 0:
		skeleton.set_bone_global_pose(torso_bone, torso_body.global_transform)

	var head_bone := skeleton.find_bone("Head")
	if head_bone >= 0:
		skeleton.set_bone_global_pose(head_bone, head_body.global_transform)

	var arm_l_bone := skeleton.find_bone("Arm_L")
	if arm_l_bone >= 0:
		skeleton.set_bone_global_pose(arm_l_bone, arm_l_upper.global_transform)
	var hand_l_bone := skeleton.find_bone("Hand_L")
	if hand_l_bone >= 0:
		skeleton.set_bone_global_pose(hand_l_bone, arm_l_lower.global_transform)

	var arm_r_bone := skeleton.find_bone("Arm_R")
	if arm_r_bone >= 0:
		skeleton.set_bone_global_pose(arm_r_bone, arm_r_upper.global_transform)
	var hand_r_bone := skeleton.find_bone("Hand_R")
	if hand_r_bone >= 0:
		skeleton.set_bone_global_pose(hand_r_bone, arm_r_lower.global_transform)

	var leg_l_bone := skeleton.find_bone("Leg_L")
	if leg_l_bone >= 0:
		skeleton.set_bone_global_pose(leg_l_bone, leg_l_upper.global_transform)
	var foot_l_bone := skeleton.find_bone("Foot_L")
	if foot_l_bone >= 0:
		skeleton.set_bone_global_pose(foot_l_bone, leg_l_lower.global_transform)

	var leg_r_bone := skeleton.find_bone("Leg_R")
	if leg_r_bone >= 0:
		skeleton.set_bone_global_pose(leg_r_bone, leg_r_upper.global_transform)
	var foot_r_bone := skeleton.find_bone("Foot_R")
	if foot_r_bone >= 0:
		skeleton.set_bone_global_pose(foot_r_bone, leg_r_lower.global_transform)


# ---------------------------------------------------------------------------
# Public API

func setup(id: int, pname: String, color_idx: int, bot: bool) -> void:
	peer_id = id
	player_name = pname
	color_index = color_idx
	is_bot = bot
	name = "P%d" % id
	set_multiplayer_authority(1 if bot else id)


func set_move_speed(_value: float) -> void:
	pass


func set_local_character(value: bool) -> void:
	is_local = value


func set_quality(_level: int) -> void:
	pass


func set_team_ring(_color: Color) -> void:
	pass


func set_disguise(_prop_id: int) -> void:
	pass


func clear_disguise() -> void:
	pass


func set_grab_state(holding_id: int, phase: int) -> void:
	grabbing_id = holding_id
	grab_phase = phase


func set_grab_target(_point: Vector3, _strength: float) -> void:
	grab_controller.set_target(_point, _strength)


func clear_grab_tether() -> void:
	grab_controller.clear_tether()


func confirm_grab() -> void:
	grab_controller.confirm()


func release_arm() -> void:
	grab_controller.release()


func finish_throw() -> void:
	grab_controller.finish_throw()


func apply_impact(impulse: Vector3, world_point: Vector3 = Vector3.ZERO, strength: float = 1.0) -> void:
	if world_point == Vector3.ZERO:
		world_point = torso_body.global_position + Vector3(0, 1.0, 0)
	torso_body.apply_impulse(impulse * strength, world_point - torso_body.global_position)
	_stun = 0.4 * strength
	state = "hit"


func apply_spin(axis: Vector3, strength: float) -> void:
	torso_body.apply_torque_impulse(axis.normalized() * strength * 5.0)


func reset_visual_state() -> void:
	state = "idle"
	_stun = 0.0
	_dash_timer = 0.0
	_dash_cd = 0.0
	_reset_to_standing()


func set_held(_value: bool) -> void:
	pass


func set_grab_tether(_point: Vector3, _strength: float) -> void:
	grab_controller.set_tether(_point, _strength)


func get_grab_hand_transform() -> Transform3D:
	return arm_r_lower.global_transform


func get_grab_overhead_position() -> Vector3:
	var forward := Vector3(-sin(facing_yaw), 0.0, -cos(facing_yaw))
	var right := Vector3(cos(facing_yaw), 0.0, -sin(facing_yaw))
	return torso_body.global_position + forward * 0.12 + Vector3.UP * 2.55 + right * 0.04


func get_grab_hand_name() -> String:
	return "Hand_R"


func get_net_anim() -> int:
	return 0


func apply_net_anim(_anim: int) -> void:
	pass


func get_ragdoll() -> RigidBody3D:
	return torso_body


func get_visible_skeleton() -> Skeleton3D:
	return skeleton


func is_dashing() -> bool:
	return _dash_timer > 0.0


func is_arm_active() -> bool:
	return grab_controller.is_active()


func set_hanging(_value: bool) -> void:
	pass


# ---------------------------------------------------------------------------
# Compatibility API (matches round_manager.gd expectations)

func set_team_info(team_id: int, is_team_mode: bool, role: int) -> void:
	team = team_id


func face_direction(direction: Vector3) -> void:
	if direction.length() > 0.01:
		facing_yaw = atan2(-direction.x, -direction.z)
		torso_body.quaternion = Quaternion(Vector3.UP, facing_yaw)


func set_grab_links(holding: int, held_by: int, phase: int) -> void:
	grabbing_id = holding
	grabbed_by = held_by
	grab_phase = phase


## Property: velocity (maps to torso_body.linear_velocity)
func set_velocity(v: Vector3) -> void:
	torso_body.linear_velocity = v


func get_velocity() -> Vector3:
	return torso_body.linear_velocity


func is_on_floor() -> bool:
	return grounded


func apply_knockback(impulse: Vector3, max_horizontal := 22.0, max_upward := 8.0) -> void:
	if not is_alive:
		return
	locomotion.apply_knockback(impulse, max_horizontal, max_upward)


func get_slide_collision_count() -> int:
	return 0


func get_slide_collision(_index: int) -> Object:
	return null


## Compatibility: round_manager accesses .visuals for rotation and methods
## We expose the skeleton node as "visuals" for backward compatibility
func _get_visuals() -> Node:
	return skeleton if skeleton != null else self


## Compatibility: round_manager accesses .collision_shape for disable/enable
## We use torso_body's collision shape
var collision_shape: CollisionShape3D:
	get:
		if torso_body.get_child_count() > 0:
			return torso_body.get_child(0) as CollisionShape3D
		return null


# ---------------------------------------------------------------------------
# Network sync (called by round_manager)

func _sync_state(_pos: Vector3, _yaw: float, _anim: int, _vel: Vector3) -> void:
	_net_pos = _pos
	_net_yaw = _yaw
	_net_received = true
