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
	a1.rotation_track_insert_key(t1, 0.0, Quaternion(Vector3.RIGHT, deg_to_rad(0)))
	a1.rotation_track_insert_key(t1, 0.5, Quaternion(Vector3.RIGHT, deg_to_rad(60)))
	a1.rotation_track_insert_key(t1, 1.0, Quaternion(Vector3.RIGHT, deg_to_rad(0)))
	lib.add_animation("swing", a1)
	ap.add_animation_library("", lib)
	at = AnimationTree.new()
	at.name = "AnimationTree"
	add_child(at)
	at.anim_player = NodePath("../AnimationPlayer")
	var bt := AnimationNodeBlendTree.new()
	var anim := AnimationNodeAnimation.new()
	anim.animation = "swing"
	bt.add_node("anim", anim)
	bt.connect_node("output", 0, "anim")
	at.tree_root = bt
	at.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	at.active = true
	print("mode ok")

func _physics_process(delta: float) -> void:
	at.advance(delta)
	print("advance delta=", delta, " angle=", rad_to_deg(sk.get_bone_pose_rotation(1).get_angle()), " pos=", sk.get_bone_pose_position(1))
	if Engine.get_physics_frames() > 6:
		get_tree().quit()
