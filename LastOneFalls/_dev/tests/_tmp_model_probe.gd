extends Node

func _ready() -> void:
	var scene: PackedScene = load("res://NewAssets/Model/contender.glb")
	var inst := scene.instantiate()
	add_child(inst)
	var sk := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	print("SKEL global=", sk.global_transform)
	print("SKEL bones=", sk.get_bone_count())
	for i in sk.get_bone_count():
		print("BONE %d %s parent=%d rest=%s global_rest=%s" % [i, sk.get_bone_name(i), sk.get_bone_parent(i), sk.get_bone_rest(i), sk.get_bone_global_rest(i)])
	for c in inst.find_children("*", "MeshInstance3D", true, false):
		print("MESH ", c.get_path(), " aabb=", c.get_aabb(), " xform=", c.global_transform)
	for c in inst.find_children("*", "AnimationPlayer", true, false):
		print("ANIMPLAYER ", c.get_path(), " anims=", c.get_animation_list())
	get_tree().quit()
