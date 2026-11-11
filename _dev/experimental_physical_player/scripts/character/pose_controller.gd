extends Node3D
class_name PoseController
## PoseController - Procedural pose targets + PD joint control.

var rig: PhysicalPlayer

# Target joint orientations (quaternions in local space relative to parent body)
var target_torso := Quaternion.IDENTITY
var target_head := Quaternion.IDENTITY
var target_shoulder_l := Quaternion.IDENTITY
var target_elbow_l := 0.0          # hinge angle
var target_shoulder_r := Quaternion.IDENTITY
var target_elbow_r := 0.0
var target_hip_l := Quaternion.IDENTITY
var target_knee_l := 0.0
var target_hip_r := Quaternion.IDENTITY
var target_knee_r := 0.0

# State-driven pose blending
var _blend_speed := 8.0
var _idle_breath_t := 0.0
var _walk_cycle_t := 0.0
var _run_cycle_t := 0.0


func _ready() -> void:
	pass


func apply_joint_control(delta: float) -> void:
	_generate_targets(delta)

	_apply_torso_pd(delta)
	_apply_head_pd(delta)
	_apply_shoulder_l_pd(delta)
	_apply_elbow_l_pd(delta)
	_apply_shoulder_r_pd(delta)
	_apply_elbow_r_pd(delta)
	_apply_hip_l_pd(delta)
	_apply_knee_l_pd(delta)
	_apply_hip_r_pd(delta)
	_apply_knee_r_pd(delta)


func _generate_targets(delta: float) -> void:
	target_torso = Quaternion.IDENTITY
	target_head = Quaternion.IDENTITY
	target_shoulder_l = Quaternion.IDENTITY
	target_elbow_l = -0.3
	target_shoulder_r = Quaternion.IDENTITY
	target_elbow_r = -0.3
	target_hip_l = Quaternion.IDENTITY
	target_knee_l = -0.2
	target_hip_r = Quaternion.IDENTITY
	target_knee_r = -0.2

	match rig.state:
		"idle":
			_apply_idle_pose(delta)
		"walk":
			_apply_walk_pose(delta)
		"run":
			_apply_run_pose(delta)
		"jump":
			_apply_jump_pose()
		"fall":
			_apply_fall_pose()
		"dash":
			_apply_dash_pose()
		"hit":
			_apply_hit_pose()
		"ragdoll":
			pass
		"recover":
			_apply_recover_pose(delta)
		"carrying":
			_apply_carrying_pose(delta)
		"carried":
			_apply_carried_pose(delta)
		"grabbed_pull":
			_apply_grabbed_pull_pose(delta)
		"punch":
			_apply_punch_pose(delta)
		"throw":
			_apply_throw_pose(delta)


func _apply_idle_pose(delta: float) -> void:
	_idle_breath_t += delta
	var breath := sin(_idle_breath_t * 3.0) * 0.03
	target_torso = Quaternion(Vector3.RIGHT, breath)
	target_head = Quaternion(Vector3.RIGHT, sin(_idle_breath_t * 2.0) * 0.05)
	target_shoulder_l = Quaternion(Vector3.FORWARD, 0.2)
	target_shoulder_r = Quaternion(Vector3.FORWARD, -0.2)


func _apply_walk_pose(delta: float) -> void:
	_walk_cycle_t += delta * 4.0
	var cycle := sin(_walk_cycle_t)
	var hip_swing := cycle * 0.5
	var knee_bend: float = abs(cycle) * 0.8

	target_hip_l = Quaternion(Vector3.RIGHT, hip_swing)
	target_hip_r = Quaternion(Vector3.RIGHT, -hip_swing)
	target_knee_l = -knee_bend
	target_knee_r = -knee_bend

	target_shoulder_l = Quaternion(Vector3.FORWARD, -cycle * 0.4)
	target_shoulder_r = Quaternion(Vector3.FORWARD, cycle * 0.4)

	target_torso = Quaternion(Vector3.UP, cycle * 0.1)


func _apply_run_pose(delta: float) -> void:
	_run_cycle_t += delta * 7.0
	var cycle := sin(_run_cycle_t)
	var hip_swing := cycle * 0.9
	var knee_bend: float = abs(cycle) * 1.2

	target_hip_l = Quaternion(Vector3.RIGHT, hip_swing)
	target_hip_r = Quaternion(Vector3.RIGHT, -hip_swing)
	target_knee_l = -knee_bend
	target_knee_r = -knee_bend

	target_shoulder_l = Quaternion(Vector3.FORWARD, -cycle * 0.8)
	target_shoulder_r = Quaternion(Vector3.FORWARD, cycle * 0.8)

	target_torso = Quaternion(Vector3.RIGHT, 0.3 + cycle * 0.1)


func _apply_jump_pose() -> void:
	target_hip_l = Quaternion(Vector3.RIGHT, -0.2)
	target_hip_r = Quaternion(Vector3.RIGHT, 0.2)
	target_knee_l = -0.1
	target_knee_r = -0.1
	target_shoulder_l = Quaternion(Vector3.FORWARD, -0.8)
	target_shoulder_r = Quaternion(Vector3.FORWARD, 0.8)


func _apply_fall_pose() -> void:
	target_hip_l = Quaternion(Vector3.RIGHT, 0.3)
	target_hip_r = Quaternion(Vector3.RIGHT, -0.3)
	target_knee_l = -0.4
	target_knee_r = -0.4
	target_shoulder_l = Quaternion(Vector3.FORWARD, -0.4)
	target_shoulder_r = Quaternion(Vector3.FORWARD, 0.4)


func _apply_dash_pose() -> void:
	target_torso = Quaternion(Vector3.RIGHT, 0.6)
	target_shoulder_l = Quaternion(Vector3.FORWARD, -0.6)
	target_shoulder_r = Quaternion(Vector3.FORWARD, 0.6)
	target_hip_l = Quaternion(Vector3.RIGHT, 0.2)
	target_hip_r = Quaternion(Vector3.RIGHT, -0.2)


func _apply_hit_pose() -> void:
	target_shoulder_l = Quaternion(Vector3.FORWARD, 0.8)
	target_shoulder_r = Quaternion(Vector3.FORWARD, -0.8)
	target_elbow_l = -1.5
	target_elbow_r = -1.5


func _apply_recover_pose(delta: float) -> void:
	target_torso = Quaternion.IDENTITY
	target_head = Quaternion.IDENTITY
	target_shoulder_l = Quaternion.IDENTITY
	target_shoulder_r = Quaternion.IDENTITY
	target_hip_l = Quaternion.IDENTITY
	target_hip_r = Quaternion.IDENTITY
	target_knee_l = -0.2
	target_knee_r = -0.2


func _apply_carrying_pose(delta: float) -> void:
	target_shoulder_l = Quaternion(Vector3.RIGHT, 1.4)
	target_shoulder_r = Quaternion(Vector3.RIGHT, 0.2)
	target_elbow_l = -0.4
	target_elbow_r = -1.2
	target_torso = Quaternion(Vector3.RIGHT, -0.15)


func _apply_carried_pose(delta: float) -> void:
	target_shoulder_l = Quaternion.IDENTITY
	target_shoulder_r = Quaternion.IDENTITY
	target_elbow_l = -0.5
	target_elbow_r = -0.5
	target_hip_l = Quaternion(Vector3.RIGHT, 0.3)
	target_hip_r = Quaternion(Vector3.RIGHT, -0.3)
	target_knee_l = -1.0
	target_knee_r = -1.0


func _apply_grabbed_pull_pose(delta: float) -> void:
	target_torso = Quaternion.IDENTITY
	target_shoulder_l = Quaternion(Vector3.FORWARD, 0.5)
	target_shoulder_r = Quaternion(Vector3.FORWARD, -0.5)


func _apply_punch_pose(delta: float) -> void:
	target_shoulder_r = Quaternion(Vector3.RIGHT, 0.4)
	target_shoulder_r = target_shoulder_r * Quaternion(Vector3.FORWARD, 0.8)
	target_elbow_r = -1.8
	target_torso = Quaternion(Vector3.UP, 0.3)


func _apply_throw_pose(delta: float) -> void:
	target_shoulder_r = Quaternion(Vector3.RIGHT, 0.2)
	target_shoulder_r = target_shoulder_r * Quaternion(Vector3.FORWARD, 1.0)
	target_elbow_r = -0.2
	target_torso = Quaternion(Vector3.UP, 0.4)


# ---------------------------------------------------------------------------
# PD joint torque application

func _apply_torso_pd(delta: float) -> void:
	var current := rig.torso_body.quaternion
	var error := _quat_diff(target_torso, current)
	var ang_vel := rig.torso_body.angular_velocity
	var torque := error * rig.PD_P - ang_vel * rig.PD_D
	torque = _clamp_vector(torque, rig.MAX_TORSO_TORQUE)
	rig.torso_body.apply_torque(torque)


func _apply_head_pd(delta: float) -> void:
	var current := rig.head_body.quaternion
	var error := _quat_diff(target_head, current)
	var ang_vel := rig.head_body.angular_velocity
	var torque := error * 30.0 - ang_vel * 6.0
	torque = _clamp_vector(torque, 20.0)
	rig.head_body.apply_torque(torque)


func _apply_shoulder_l_pd(delta: float) -> void:
	var current := rig.arm_l_upper.quaternion
	var error := _quat_diff(target_shoulder_l, current)
	var ang_vel := rig.arm_l_upper.angular_velocity
	var torque := error * rig.PD_P - ang_vel * rig.PD_D
	torque = _clamp_vector(torque, rig.MAX_LIMB_TORQUE)
	rig.arm_l_upper.apply_torque(torque)


func _apply_elbow_l_pd(delta: float) -> void:
	var target: float = target_elbow_l
	var torque := target * 15.0
	torque = clampf(torque, -rig.MAX_LIMB_TORQUE, rig.MAX_LIMB_TORQUE)
	rig.arm_l_lower.apply_torque(Vector3(0, 0, torque))


func _apply_shoulder_r_pd(delta: float) -> void:
	var current := rig.arm_r_upper.quaternion
	var error := _quat_diff(target_shoulder_r, current)
	var ang_vel := rig.arm_r_upper.angular_velocity
	var torque := error * rig.PD_P - ang_vel * rig.PD_D
	torque = _clamp_vector(torque, rig.MAX_LIMB_TORQUE)
	rig.arm_r_upper.apply_torque(torque)


func _apply_elbow_r_pd(delta: float) -> void:
	var target: float = target_elbow_r
	var torque := target * 15.0
	torque = clampf(torque, -rig.MAX_LIMB_TORQUE, rig.MAX_LIMB_TORQUE)
	rig.arm_r_lower.apply_torque(Vector3(0, 0, torque))


func _apply_hip_l_pd(delta: float) -> void:
	var current := rig.leg_l_upper.quaternion
	var error := _quat_diff(target_hip_l, current)
	var ang_vel := rig.leg_l_upper.angular_velocity
	var torque := error * rig.PD_P - ang_vel * rig.PD_D
	torque = _clamp_vector(torque, rig.MAX_LIMB_TORQUE)
	rig.leg_l_upper.apply_torque(torque)


func _apply_knee_l_pd(delta: float) -> void:
	var target: float = target_knee_l
	var torque := target * 20.0
	torque = clampf(torque, -rig.MAX_LIMB_TORQUE, rig.MAX_LIMB_TORQUE)
	rig.leg_l_lower.apply_torque(Vector3(0, 0, torque))


func _apply_hip_r_pd(delta: float) -> void:
	var current := rig.leg_r_upper.quaternion
	var error := _quat_diff(target_hip_r, current)
	var ang_vel := rig.leg_r_upper.angular_velocity
	var torque := error * rig.PD_P - ang_vel * rig.PD_D
	torque = _clamp_vector(torque, rig.MAX_LIMB_TORQUE)
	rig.leg_r_upper.apply_torque(torque)


func _apply_knee_r_pd(delta: float) -> void:
	var target: float = target_knee_r
	var torque := target * 20.0
	torque = clampf(torque, -rig.MAX_LIMB_TORQUE, rig.MAX_LIMB_TORQUE)
	rig.leg_r_lower.apply_torque(Vector3(0, 0, torque))


# ---------------------------------------------------------------------------
# Helpers

func _quat_diff(target: Quaternion, current: Quaternion) -> Vector3:
	var diff := target * current.inverse()
	var axis := diff.get_axis()
	var angle := diff.get_angle()
	return axis * angle


func _clamp_vector(v: Vector3, max_mag: float) -> Vector3:
	if v.length() > max_mag:
		return v.normalized() * max_mag
	return v
