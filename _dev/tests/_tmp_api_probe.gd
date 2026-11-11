extends Node

func _ready() -> void:
	var bt := AnimationNodeBlendTree.new()
	for m in bt.get_method_list():
		if "connect" in m.name or "node" in m.name or "param" in m.name:
			print("BT ", m.name, " args=", m.args)
	var b := AnimationNodeBlend2.new()
	for m in b.get_method_list():
		if "filter" in m.name:
			print("BLEND ", m.name, " args=", m.args)
	get_tree().quit()
