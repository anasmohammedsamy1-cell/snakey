extends Node3D
class_name GrabController
## GrabController - Overhead carrying and physical throwing.

var rig: PhysicalPlayer

# Carry state
var _carry_joint: Generic6DOFJoint3D = null
var _carry_target: Node = null
var _carry_phase := 0      # 0 = none, 1 = lifting, 2 = carrying, 3 = throwing
var _lift_t := 0.0
var _throw_t := 0.0

# Carry tuning
var CARRY_HEIGHT := 2.55
var CARRY_FORWARD := 0.12
var CARRY_SIDE := 0.04
var LIFT_SPEED := 6.0
var THROW_FORCE := 15.0
var THROW_LIFT := 8.0


func update(delta: float) -> void:
	match _carry_phase:
		1:
			_update_lift(delta)
		2:
			_update_carry(delta)
		3:
			_update_throw(delta)


func set_target(_point: Vector3, _strength: float) -> void:
	pass


func confirm() -> void:
	if rig.grabbing_id == 0 or rig.round_manager == null:
		return
	var target = rig.round_manager.players.get(rig.grabbing_id)
	if target == null or not is_instance_valid(target):
		return
	_start_carry(target)


func release() -> void:
	_end_carry()


func finish_throw() -> void:
	_execute_throw()


func is_active() -> bool:
	return _carry_phase != 0


func set_tether(_point: Vector3, _strength: float) -> void:
	pass


func _start_carry(target: Node) -> void:
	_carry_target = target
	_carry_phase = 1
	_lift_t = 0.0
	var target_body: RigidBody3D = null
	if target.has_method("get_ragdoll"):
		target_body = target.get_ragdoll()
	if target_body != null:
		target_body.collision_layer = 0
		target_body.collision_mask = 0
		target_body.linear_velocity = Vector3.ZERO
		target_body.angular_velocity = Vector3.ZERO


func _update_lift(delta: float) -> void:
	_lift_t += delta
	if _carry_target == null or not is_instance_valid(_carry_target):
		_end_carry()
		return

	var target_body: RigidBody3D = null
	if _carry_target.has_method("get_ragdoll"):
		target_body = _carry_target.get_ragdoll()
	if target_body == null:
		_end_carry()
		return

	var overhead := rig.get_grab_overhead_position()
	var current := target_body.global_position
	var to_target := overhead - current
	var dist := to_target.length()

	if dist > 0.1:
		var move_dir := to_target.normalized()
		var lift_force := move_dir * LIFT_SPEED * target_body.mass * 8.0
		target_body.apply_central_force(lift_force)

	var target_rot := Quaternion(Vector3.UP, rig.facing_yaw + PI)
	target_body.quaternion = target_body.quaternion.slerp(target_rot, 1.0 - exp(-10.0 * delta))

	if dist < 0.3 and _carry_joint == null:
		_create_carry_joint(target_body)
		_carry_phase = 2


func _create_carry_joint(target_body: RigidBody3D) -> void:
	_carry_joint = Generic6DOFJoint3D.new()
	_carry_joint.name = "Joint_Carry"
	_carry_joint.node_a = rig.arm_r_lower.get_path()
	_carry_joint.node_b = target_body.get_path()
	_carry_joint.position_a = Vector3(0, 0.4, 0)
	_carry_joint.position_b = Vector3(0, 0, 0)
	_carry_joint.twist_enabled = true
	_carry_joint.twist_min = -0.8
	_carry_joint.twist_max = 0.8
	_carry_joint.swing_axis = Vector3(1, 0, 0)
	_carry_joint.swing_min = -0.8
	_carry_joint.swing_max = 0.8
	_carry_joint.limit_enabled = true
	_carry_joint.angular_limit_x = 0.8
	_carry_joint.angular_limit_y = 0.8
	_carry_joint.angular_limit_z = 0.6
	_carry_joint.angular_erp = 0.8
	_carry_joint.angular_stiffness = 60.0
	_carry_joint.angular_damping = 12.0
	var joints := rig.get_node_or_null("PhysicsJoints")
	if joints != null:
		joints.add_child(_carry_joint)


func _update_carry(delta: float) -> void:
	if _carry_target == null or not is_instance_valid(_carry_target):
		_end_carry()
		return

	var target_body: RigidBody3D = null
	if _carry_target.has_method("get_ragdoll"):
		target_body = _carry_target.get_ragdoll()
	if target_body == null or _carry_joint == null:
		_end_carry()
		return


func _update_throw(delta: float) -> void:
	_throw_t += delta
	if _throw_t > 0.3:
		_execute_throw()


func _execute_throw() -> void:
	if _carry_target == null or not is_instance_valid(_carry_target):
		_end_carry()
		return

	var target_body: RigidBody3D = null
	if _carry_target.has_method("get_ragdoll"):
		target_body = _carry_target.get_ragdoll()
	if target_body == null:
		_end_carry()
		return

	var dir := Vector3(-sin(rig.facing_yaw), 0.0, -cos(rig.facing_yaw))
	var arm_vel := rig.arm_r_lower.linear_velocity
	var throw_vel := dir * THROW_FORCE + Vector3.UP * THROW_LIFT + arm_vel * 0.35

	target_body.apply_central_impulse(throw_vel * target_body.mass)
	target_body.apply_torque_impulse(Vector3(randf() - 0.5, 0.8, randf() - 0.5) * 5.0)

	target_body.collision_layer = 2
	target_body.collision_mask = 3

	if rig.round_manager != null:
		rig.round_manager._deliver_push(_carry_target.peer_id, throw_vel * 1.5, 30.0, 12.0)

	_end_carry()


func _end_carry() -> void:
	if _carry_joint != null:
		var joints := rig.get_node_or_null("PhysicsJoints")
		if joints != null and is_instance_valid(_carry_joint):
			joints.remove_child(_carry_joint)
			_carry_joint.queue_free()
		_carry_joint = null

	if _carry_target != null and is_instance_valid(_carry_target):
		var target_body: RigidBody3D = null
		if _carry_target.has_method("get_ragdoll"):
			target_body = _carry_target.get_ragdoll()
		if target_body != null:
			target_body.collision_layer = 2
			target_body.collision_mask = 3

	_carry_target = null
	_carry_phase = 0
	_lift_t = 0.0
	_throw_t = 0.0
