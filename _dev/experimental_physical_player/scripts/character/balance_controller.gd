extends Node3D
class_name BalanceController
## BalanceController - Active balance correction and recovery from falls.
##
## Monitors torso orientation and applies corrective torques to keep the
## character upright.  When the character falls, it plans and executes a
## physically-simulated recovery to standing.

var rig: PhysicalPlayer

var _fall_t := 0.0
var _recover_state := "none"      # none, assess, plant_hands, lift_torso, stand, done
var _recover_timer := 0.0
var _down_side := "none"          # back, front, left, right


func update(delta: float) -> void:
	if rig.state == "ragdoll":
		_begin_ragdoll_recovery()
		return

	if rig.state == "recover":
		_update_recover(delta)
		return

	# Active balance while standing/walking
	if rig.grounded and rig.state in ["idle", "walk", "run", "dash"]:
		_apply_balance_torque(delta)


func _apply_balance_torque(delta: float) -> void:
	# Measure torso tilt
	var torso_up := rig.torso_body.global_transform.basis.y
	var tilt := Vector3.UP.dot(torso_up)
	var tilt_axis := Vector3.UP.cross(torso_up)

	# If significantly tilted, apply corrective torque
	if tilt < 0.92:
		var correction := tilt_axis * (1.0 - tilt) * 40.0
		correction = _clamp_vector(correction, rig.MAX_TORSO_TORQUE)
		rig.torso_body.apply_torque(correction)

	# Foot contact pressure - if one foot is lifting too much, adjust
	# (simplified: just apply yaw stabilization)
	var ang_vel := rig.torso_body.angular_velocity
	var damping := -ang_vel * 8.0
	rig.torso_body.apply_torque(damping)


func _begin_ragdoll_recovery() -> void:
	# Transition from ragdoll to recovery
	if rig.state == "ragdoll":
		rig.state = "recover"
		_recover_state = "assess"
		_recover_timer = 0.0
		_fall_t = 0.0


func _update_recover(delta: float) -> void:
	_recover_timer += delta

	match _recover_state:
		"assess":
			_assess_down_side()
			_recover_state = "plant_hands"
			_recover_timer = 0.0

		"plant_hands":
			# Bring hands down to support the body
			_plant_hands()
			if _recover_timer > 0.6:
				_recover_state = "lift_torso"
				_recover_timer = 0.0

		"lift_torso":
			# Push torso up using arms and legs
			_lift_torso()
			if _recover_timer > 1.2 or rig.grounded:
				_recover_state = "stand"
				_recover_timer = 0.0

		"stand":
			# Final stabilization
			_stand_straight()
			if _recover_timer > 0.8:
				_recover_state = "done"
				rig.state = "idle"


func _assess_down_side() -> void:
	# Determine which way the character is facing down
	var torso_up := rig.torso_body.global_transform.basis.y
	if torso_up.y < -0.5:
		_down_side = "back"
	elif torso_up.y > 0.5:
		_down_side = "front"
	else:
		_down_side = "side"


func _plant_hands() -> void:
	# Apply torque to bring hands toward ground for support
	var target_shoulder_l := Quaternion(Vector3.RIGHT, 1.0)
	var target_shoulder_r := Quaternion(Vector3.RIGHT, -1.0)
	# These are applied via pose_controller targets
	rig.pose_controller.target_shoulder_l = target_shoulder_l
	rig.pose_controller.target_shoulder_r = target_shoulder_r
	rig.pose_controller.target_elbow_l = -1.5
	rig.pose_controller.target_elbow_r = -1.5


func _lift_torso() -> void:
	# Apply upward impulse through torso and extend legs
	if rig.torso_body.linear_velocity.y < 2.0:
		rig.torso_body.apply_central_impulse(Vector3.UP * rig.torso_body.mass * 3.0)
	# Extend knees to push up
	rig.pose_controller.target_knee_l = -0.3
	rig.pose_controller.target_knee_r = -0.3


func _stand_straight() -> void:
	# Return to neutral standing pose
	rig.pose_controller.target_torso = Quaternion.IDENTITY
	rig.pose_controller.target_head = Quaternion.IDENTITY
	rig.pose_controller.target_shoulder_l = Quaternion.IDENTITY
	rig.pose_controller.target_shoulder_r = Quaternion.IDENTITY
	rig.pose_controller.target_hip_l = Quaternion.IDENTITY
	rig.pose_controller.target_hip_r = Quaternion.IDENTITY
	rig.pose_controller.target_knee_l = -0.2
	rig.pose_controller.target_knee_r = -0.2


func _clamp_vector(v: Vector3, max_mag: float) -> Vector3:
	if v.length() > max_mag:
		return v.normalized() * max_mag
	return v
