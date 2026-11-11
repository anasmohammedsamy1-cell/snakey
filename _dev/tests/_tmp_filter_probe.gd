extends Node

var sk: Skeleton3D
var ap: AnimationPlayer
var at: AnimationTree

func _ready() -> void:
	sk = Skeleton3D.new()
	sk.name = "Skeleton3D"
	add_child(sk)
	sk.add_bone("Root")
	sk.add_bone("A")
	sk.set_bone_parent(1, 0)
	sk.set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3.ZERO))
	sk.add_bone("B")
	sk.set_bone_parent(2, 1)
	sk.set_bone_rest(2, Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)))
	ap = AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	add_child(ap)
	ap.root_node = NodePath("..")

	var lib := AnimationLibrary.new()
	var a1 := Animation.new()
	a1.length = 1.0
	a1.loop_mode = Animation.LOOP_LINEAR
	var t1 := a1.add_track(Animation.TYPE_ROTATION_3D)
	a1.track_set_path(t1, NodePath("Skeleton3D:A"))
	a1.rotation_track_insert_key(t1, 0.0, Quaternion(Vector3.RIGHT, deg_to_rad(60)))
	a1.rotation_track_insert_key(t1, 1.0, Quaternion(Vector3.RIGHT, deg_to_rad(60)))
	var t2 := a1.add_track(Animation.TYPE_ROTATION_3D)
	a1.track_set_path(t2, NodePath("Skeleton3D:B"))
	a1.rotation_track_insert_key(t2, 0.0, Quaternion(Vector3.RIGHT, deg_to_rad(10)))
	a1.rotation_track_insert_key(t2, 1.0, Quaternion(Vector3.RIGHT, deg_to_rad(10)))
	lib.add_animation("lower", a1)
	var a2 := Animation.new()
	a2.length = 1.0
	a2.loop_mode = Animation.LOOP_LINEAR
	var t3 := a2.add_track(Animation.TYPE_ROTATION_3D)
	a2.track_set_path(t3, NodePath("Skeleton3D:A"))
	a2.rotation_track_insert_key(t3, 0.0, Quaternion(Vector3.RIGHT, deg_to_rad(90)))
	a2.rotation_track_insert_key(t3, 1.0, Quaternion(Vector3.RIGHT, deg_to_rad(90)))
	var t4 := a2.add_track(Animation.TYPE_ROTATION_3D)
	a2.track_set_path(t4, NodePath("Skeleton3D:B"))
	a2.rotation_track_insert_key(t4, 0.0, Quaternion(Vector3.RIGHT, deg_to_rad(20)))
	a2.rotation_track_insert_key(t4, 1.0, Quaternion(Vector3.RIGHT, deg_to_rad(20)))
	lib.add_animation("upper", a2)
	ap.add_animation_library("", lib)

	at = AnimationTree.new()
	at.name = "AnimationTree"
	add_child(at)
	at.anim_player = NodePath("../AnimationPlayer")
	var bt := AnimationNodeBlendTree.new()
	var lower := AnimationNodeAnimation.new()
	lower.animation = "lower"
	var upper := AnimationNodeAnimation.new()
	upper.animation = "upper"
	var blend := AnimationNodeBlend2.new()
	blend.filter_enabled = true
	blend.set_filter_path("Skeleton3D:A", true)
	blend.set_filter_path("Skeleton3D:B", false)
	bt.add_node("lower", lower)
	bt.add_node("upper", upper)
	bt.add_node("blend", blend)
	bt.connect_node("blend", 0, "lower")
	bt.connect_node("blend", 1, "upper")
	bt.connect_node("output", 0, "blend")
	at.tree_root = bt
	at.active = true
	at.set("parameters/blend/blend_amount", 1.0)
	print("ready filter A=", blend.is_path_filtered("Skeleton3D:A"), " B=", blend.is_path_filtered("Skeleton3D:B"), " enabled=", blend.is_filter_enabled())

func _process(_delta: float) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var qa := sk.get_bone_pose_rotation(1)
	var qb := sk.get_bone_pose_rotation(2)
	print("A angle=", rad_to_deg(qa.get_angle()), " expected 60 (filter off) or 90 (blended)")
	print("B angle=", rad_to_deg(qb.get_angle()), " expected 20 (blended)")
	get_tree().quit()
