extends Node3D

const VisualsScript := preload("res://scripts/character/contender_visuals.gd")

var visuals: Node3D
var rag: ContenderRagdoll
var carrier: Node3D


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

	carrier = Node3D.new()
	add_child(carrier)
	visuals = VisualsScript.new()
	carrier.add_child(visuals)
	rag = visuals.get_ragdoll()
	await _wait(180)
	print("LAG settled lag=%.3f pos=%s" % [rag.get_anchor_lag(), _torso()])
	# Simulate a punch knockback: move the authoritative carrier at 20 m/s for
	# 0.45 s, then stop and let the ragdoll catch up.
	var start := carrier.global_position
	for i in 27:
		carrier.global_position.x += 20.0 / 60.0
		await get_tree().physics_frame
		if i % 3 == 0:
			print("LAG move f=%d lag=%.3f torso=%s" % [i, rag.get_anchor_lag(), _torso()])
	print("LAG stopped lag=%.3f up=%.3f" % [rag.get_anchor_lag(), rag.get_uprightness()])
	for i in 30:
		await get_tree().physics_frame
		if i % 3 == 0:
			print("LAG settle f=%d lag=%.3f" % [i, rag.get_anchor_lag()])
	# Strong impact while the root is moving.
	rag.apply_impact(Vector3(20, 5, 0), rag.body["Torso"].global_position + Vector3.UP * 0.3, 1.0)
	print("LAG impact ragdoll=%s lag=%.3f" % [rag.is_ragdolled(), rag.get_anchor_lag()])
	for i in 60:
		carrier.global_position.x += 20.0 / 60.0
		await get_tree().physics_frame
		if i % 5 == 0:
			print("LAG hitmove f=%d lag=%.3f up=%.3f" % [i, rag.get_anchor_lag(), rag.get_uprightness()])
	print("LAG final lag=%.3f up=%.3f" % [rag.get_anchor_lag(), rag.get_uprightness()])
	get_tree().quit()


func _torso() -> Vector3:
	return rag.body["Torso"].global_position


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame
