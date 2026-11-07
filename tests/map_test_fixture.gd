extends Node3D
var obstacles_root: Node3D
var decor_root: Node3D
var round_manager: Node = null

func _init() -> void:
	obstacles_root = Node3D.new()
	decor_root = Node3D.new()
	add_child(obstacles_root)
	add_child(decor_root)
