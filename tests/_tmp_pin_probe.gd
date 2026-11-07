extends Node3D

var torso: RigidBody3D
var anchor: AnimatableBody3D
var joint: Generic6DOFJoint3D


func _ready() -> void:
	call_deferred("_start")


func _start() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(60.0, 0.5, 60.0)
	col.shape = shape
	col.position = Vector3(0, -0.25, 0)
	floor_body.add_child(col)
	add_child(floor_body)

	anchor = AnimatableBody3D.new()
	anchor.sync_to_physics = true
	anchor.collision_layer = 0
	anchor.collision_mask = 0
	anchor.position = Vector3(0, 1, 0)
	add_child(anchor)

	torso = RigidBody3D.new()
	torso.mass = 9.0
	torso.can_sleep = false
	torso.collision_layer = 8
	torso.collision_mask = 1
	var c := CapsuleShape3D.new()
	c.radius = 0.3
	c.height = 0.78
	var cs := CollisionShape3D.new()
	cs.shape = c
	torso.add_child(cs)
	torso.position = Vector3(0, 1, 0)
	add_child(torso)

	joint = Generic6DOFJoint3D.new()
	joint.position = Vector3(0, 1, 0)
	add_child(joint)
	joint.node_a = joint.get_path_to(anchor)
	joint.node_b = joint.get_path_to(torso)
	for ai in 3:
		match ai:
			0:
				joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
				joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -0.16)
				joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.16)
				joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_DAMPING, 1.0)
				joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, false)
			1:
				joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
				joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -0.16)
				joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.16)
				joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_DAMPING, 1.0)
				joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, false)
			_:
				joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
				joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -0.16)
				joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.16)
				joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_DAMPING, 1.0)
				joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, false)
	await _wait(5)
	print("LEASH after sync anchor=", anchor.global_position, " torso=", torso.global_position, " j=", joint.global_position)
	await _wait(30)
	print("LEASH settled anchor=", anchor.global_position, " torso=", torso.global_position, " dist=", torso.global_position.distance_to(anchor.global_position))
	for i in 60:
		anchor.global_position.x += 20.0 / 60.0
		await get_tree().physics_frame
		if i % 6 == 0:
			var ax := anchor.global_position
			var tx := torso.global_position
			print("LEASH f=%d anchor=%s torso=%s dist=%.3f off=%s" % [i, ax, tx, tx.distance_to(ax), tx - ax])
	print("LEASH final dist=", torso.global_position.distance_to(anchor.global_position))
	get_tree().quit()


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame
