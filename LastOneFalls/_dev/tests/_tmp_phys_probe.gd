extends Node3D
## Temporary engine probe: verifies PhysicalBone3D behaviour in this Godot build.

var sk: Skeleton3D
var sim: PhysicalBoneSimulator3D
var bones: Dictionary = {}
var carrier: Node3D


func _ready() -> void:
	carrier = self
	var ps: PackedScene = load("res://NewAssets/Model/contender.glb")
	var model: Node = ps.instantiate()
	add_child(model)
	sk = model.find_child("Skeleton3D", true, false) as Skeleton3D
	sim = PhysicalBoneSimulator3D.new()
	sim.name = "Sim"
	sk.add_child(sim)
	for i in sk.get_bone_count():
		var bn := sk.get_bone_name(i)
		if bn.begins_with("Eye") or bn.begins_with("Jaw") or bn.begins_with("Root"):
			continue
		var pb := PhysicalBone3D.new()
		pb.name = "PB_" + bn
		pb.set("bone_name", bn)
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_6DOF
		pb.mass = 2.0
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.09
		cap.height = 0.3
		cs.shape = cap
		pb.add_child(cs)
		sim.add_child(pb)
		bones[bn] = pb
		print("PROBE bone=", bn, " bone_name=", pb.get("bone_name"), " bone_id=", pb.get_bone_id(), " simulate=", pb.get_simulate_physics(), " active=", sim.active, " rid=", pb.get_rid())
	print("PROBE started bones=", bones.size())
	sim.physical_bones_start_simulation()
	print("PROBE after start simulating=", sim.is_simulating_physics(), " torso_sim=", bones["Torso_2"].is_simulating_physics(), " bone_id=", bones["Torso_2"].get_bone_id())
	await _wait(30)
	await get_tree().process_frame
	await get_tree().process_frame
	print("PROBE T0 torso_world=", bones["Torso_2"].global_position, " torso_bone=", sk.get_bone_global_pose(1).origin, " sim_pose=", sim.get_bone_global_pose(1).origin, " sim_bones=", sim.get_bone_count(), " sim_has=", sim.get_physical_bone(1) != null, " carrier=", carrier.global_position)
	for i in sk.get_bone_count():
		if sk.get_bone_name(i).begins_with("Torso"):
			print("PROBE torso_pose=", sk.get_bone_pose(i), " global=", sk.get_bone_global_pose(i))
	# Move the carrier (the character root) 2 m sideways.
	carrier.global_position += Vector3(2, 0, 0)
	await _wait(30)
	await get_tree().process_frame
	await get_tree().process_frame
	print("PROBE T1 torso_world=", bones["Torso_2"].global_position, " torso_bone=", sk.get_bone_global_pose(1).origin, " torso_pose=", sk.get_bone_pose(1).origin, " carrier=", carrier.global_position)
	# Apply a torque to the torso for 30 frames.
	for i in 30:
		PhysicsServer3D.body_apply_torque(bones["Torso_2"].get_rid(), Vector3(0, 0, 60))
		await get_tree().physics_frame
	print("PROBE T2 torso_rot=", bones["Torso_2"].global_rotation_degrees, " bone_rot=", sk.get_bone_global_pose(1).basis.get_rotation_quaternion())
	sim.physical_bones_stop_simulation()
	await _wait(2)
	print("PROBE stopped torso_world=", bones["Torso_2"].global_position)
	get_tree().quit(0)


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame
