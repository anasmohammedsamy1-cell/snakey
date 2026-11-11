extends Node3D

var parent_body: StaticBody3D
var child: RigidBody3D
var joint: Generic6DOFJoint3D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	parent_body = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.4, 0.4, 0.4)
	cs.shape = bs
	parent_body.add_child(cs)
	add_child(parent_body)
	parent_body.global_position = Vector3(0, 1, 0)

	child = RigidBody3D.new()
	child.mass = 1.0
	child.gravity_scale = 0.0
	child.can_sleep = false
	var cc := CollisionShape3D.new()
	var bc := BoxShape3D.new()
	bc.size = Vector3(0.2, 0.6, 0.2)
	cc.shape = bc
	child.add_child(cc)
	add_child(child)
	child.global_position = Vector3(0, 1, 0)

	joint = Generic6DOFJoint3D.new()
	add_child(joint)
	joint.global_position = Vector3(0, 1, 0)
	joint.node_a = joint.get_path_to(parent_body)
	joint.node_b = joint.get_path_to(child)
	for ai in 3:
		_set_flag(ai, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
		_set_param(ai, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -PI)
		_set_param(ai, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, PI)
		_set_param(ai, Generic6DOFJoint3D.PARAM_ANGULAR_DAMPING, 0.0)
		_set_flag(ai, Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, true)
		_set_param(ai, Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, 100.0)
		_set_param(ai, Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, 0.0)
	_set_param(0, Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, 2.0)
	await _wait(20)
	print("MOTOR +X after 20: rot=%s angvel=%s" % [child.rotation_degrees, child.angular_velocity])
	_set_param(0, Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, -2.0)
	await _wait(20)
	print("MOTOR -X after 40: rot=%s angvel=%s" % [child.rotation_degrees, child.angular_velocity])
	# Now test direct torque for comparison.
	child.angular_velocity = Vector3.ZERO
	child.rotation = Vector3.ZERO
	for i in 20:
		child.apply_torque(Vector3(2, 0, 0))
		await get_tree().physics_frame
	print("TORQUE +X after 20: rot=%s angvel=%s" % [child.rotation_degrees, child.angular_velocity])
	get_tree().quit()


func _set_param(axis: int, param: int, value: float) -> void:
	match axis:
		0: joint.set_param_x(param, value)
		1: joint.set_param_y(param, value)
		_: joint.set_param_z(param, value)


func _set_flag(axis: int, flag: int, value: bool) -> void:
	match axis:
		0: joint.set_flag_x(flag, value)
		1: joint.set_flag_y(flag, value)
		_: joint.set_flag_z(flag, value)


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame
