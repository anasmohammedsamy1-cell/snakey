extends Node

func _ready() -> void:
	var g := Generic6DOFJoint3D.new()
	print("G set_param=", g.has_method("set_param"), " set_flag=", g.has_method("set_flag"))
	print("G set_param_x=", g.has_method("set_param_x"), " set_flag_x=", g.has_method("set_flag_x"))
	var sk := Skeleton3D.new()
	print("SK force_update_all_dirty_bones=", sk.has_method("force_update_all_dirty_bones"), " force_update_transform=", sk.has_method("force_update_transform"))
	print("AnimationMixer MANUAL=", AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL)
	get_tree().quit()
