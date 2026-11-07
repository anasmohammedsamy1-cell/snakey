extends Node

func _ready() -> void:
	var inst: Node3D = load("res://NewAssets/Model/contender.glb").instantiate()
	add_child(inst)
	var sk := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	var idx := {}
	for i in sk.get_bone_count():
		idx[sk.get_bone_name(i)] = i

	print("rest hand L=", sk.get_bone_global_pose(idx["Hand_L"]).origin, " foot L=", sk.get_bone_global_pose(idx["Foot_L"]).origin)
	# Arm local X negative, expected lower
	_rot(sk, idx["Arm_L"], Vector3.RIGHT, -1.2)
	print("armL X-1.2 hand=", sk.get_bone_global_pose(idx["Hand_L"]).origin)
	_rot(sk, idx["Arm_L"], Vector3.RIGHT, 0.0)
	_rot(sk, idx["Arm_L"], Vector3.BACK, 0.8)
	print("armL Z+0.8 hand=", sk.get_bone_global_pose(idx["Hand_L"]).origin)
	_rot(sk, idx["Arm_L"], Vector3.BACK, 0.0)
	_rot(sk, idx["Arm_L"], Vector3.BACK, -0.8)
	print("armL Z-0.8 hand=", sk.get_bone_global_pose(idx["Hand_L"]).origin)
	_rot(sk, idx["Arm_L"], Vector3.BACK, 0.0)
	# Right arm
	_rot(sk, idx["Arm_R"], Vector3.RIGHT, -1.2)
	print("armR X-1.2 hand=", sk.get_bone_global_pose(idx["Hand_R"]).origin)
	_rot(sk, idx["Arm_R"], Vector3.RIGHT, 0.0)
	_rot(sk, idx["Arm_R"], Vector3.BACK, 0.8)
	print("armR Z+0.8 hand=", sk.get_bone_global_pose(idx["Hand_R"]).origin)
	_rot(sk, idx["Arm_R"], Vector3.BACK, 0.0)
	_rot(sk, idx["Arm_R"], Vector3.BACK, -0.8)
	print("armR Z-0.8 hand=", sk.get_bone_global_pose(idx["Hand_R"]).origin)
	_rot(sk, idx["Arm_R"], Vector3.BACK, 0.0)
	# Leg
	_rot(sk, idx["Leg_L"], Vector3.RIGHT, 0.8)
	print("legL X+0.8 foot=", sk.get_bone_global_pose(idx["Foot_L"]).origin)
	_rot(sk, idx["Leg_L"], Vector3.RIGHT, -0.8)
	print("legL X-0.8 foot=", sk.get_bone_global_pose(idx["Foot_L"]).origin)
	_rot(sk, idx["Leg_L"], Vector3.RIGHT, 0.0)
	_rot(sk, idx["Leg_R"], Vector3.RIGHT, 0.8)
	print("legR X+0.8 foot=", sk.get_bone_global_pose(idx["Foot_R"]).origin)
	_rot(sk, idx["Leg_R"], Vector3.RIGHT, 0.0)
	# foot pitch
	_rot(sk, idx["Foot_L"], Vector3.RIGHT, 0.4)
	print("footL X+0.4 toe-ish joint=", sk.get_bone_global_pose(idx["Foot_L"]).origin)
	get_tree().quit()

func _rot(sk: Skeleton3D, id: int, axis: Vector3, angle: float) -> void:
	var rest_q := sk.get_bone_rest(id).basis.get_rotation_quaternion()
	sk.set_bone_pose_rotation(id, rest_q * Quaternion(axis, angle))
