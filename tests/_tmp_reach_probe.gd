extends Node3D

const VisualsScript := preload("res://scripts/character/contender_visuals.gd")

var v


func _ready() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(30, 0.5, 30)
	col.shape = shape
	col.position = Vector3(0, -0.25, 0)
	floor_body.add_child(col)
	add_child(floor_body)
	v = VisualsScript.new()
	add_child(v)
	call_deferred("_run")


func _run() -> void:
	for i in 60:
		await get_tree().physics_frame
	v.set_grab_state(123, 1)
	for i in 20:
		await get_tree().physics_frame
	print("PROBE carry_hand=", v.pose_rig.get_carry_hand(), " reach=", v.pose_rig.is_reaching(),
		" target=", v.pose_rig._reach_target, " global=", v.global_position)
	print("PROBE bones arm=", v.pose_rig.get_target_bone("Arm_R").origin,
		" hand=", v.pose_rig.get_target_bone("Hand_R").origin,
		" grip=", v.get_grab_hand_transform().origin)
	print("PROBE torso_pose=", v.pose_rig.get_target_bone("Torso").basis)
	var sk: Skeleton3D = v.pose_rig.get_target_skeleton()
	var arm_id: int = sk.find_bone("Arm_R")
	var hand_id: int = sk.find_bone("Hand_R")
	var torso_id: int = sk.find_bone("Torso")
	var world: Transform3D = sk.global_transform
	var torso_basis: Basis = world.basis * sk.get_bone_global_pose(torso_id).basis
	var shoulder: Vector3 = world * sk.get_bone_global_pose(arm_id).origin
	var to_target: Vector3 = v.pose_rig._reach_target - shoulder
	print("PROBE shoulder=", shoulder, " to_target=", to_target, " local=", (torso_basis.inverse() * to_target.normalized()),
		" arm_local_pose=", sk.get_bone_pose_rotation(arm_id))
	print("PROBE rest_basis=", v.pose_rig._rest_basis["Arm_R"])
	print("PROBE aim=", v.pose_rig._aim_offset("Arm_R", Vector3(0.433568,0.820387,0.372807)))
	print("PROBE arm_global=", sk.get_bone_global_pose(arm_id).basis, " globalY=", sk.get_bone_global_pose(arm_id).basis * Vector3.UP)
	print("PROBE hand_rest=", sk.get_bone_rest(hand_id), " parent=", sk.get_bone_parent(hand_id))
	get_tree().quit()
