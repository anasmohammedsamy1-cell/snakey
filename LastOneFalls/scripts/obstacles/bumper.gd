extends Node3D
## Solid bouncy bumper post. Players cannot walk through it, and touching it knocks them away.
## Same authority rule as the rotating hammer: each peer applies the hit to the players it owns.

const Scenery := preload("res://scripts/scenery.gd")

@export var radius := 0.75
@export var height := 1.2
@export var color := Color(1.0, 0.42, 0.72)
@export var knockback := 13.0
@export var hit_cooldown := 0.5

var _recent: Dictionary = {}
var _area: Area3D


func _ready() -> void:
	add_to_group("obstacles")
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	shape.shape = cyl
	shape.position.y = height * 0.5
	body.add_child(shape)
	add_child(body)
	add_child(Scenery.mesh_instance(Scenery.cylinder(radius, radius * 1.1, height, 14), Scenery.mat(color, 0.4), Vector3(0, height * 0.5, 0)))
	add_child(Scenery.mesh_instance(Scenery.cylinder(radius * 0.7, radius * 0.7, 0.12, 14), Scenery.mat(Color(1, 1, 1), 0.4), Vector3(0, height + 0.06, 0), false))
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var ashape := CollisionShape3D.new()
	var acyl := CylinderShape3D.new()
	acyl.radius = radius + 0.35
	acyl.height = height + 0.8
	ashape.shape = acyl
	ashape.position.y = (height + 0.8) * 0.5
	_area.add_child(ashape)
	add_child(_area)


func _physics_process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for body in _area.get_overlapping_bodies():
		if not body.is_in_group("players"):
			continue
		if not body.is_multiplayer_authority() or not body.is_alive:
			continue
		var key := body.get_instance_id()
		if now - float(_recent.get(key, -10.0)) < hit_cooldown:
			continue
		_recent[key] = now
		var rel: Vector3 = body.global_position - global_position
		rel.y = 0.0
		if rel.length() < 0.01:
			rel = Vector3(1, 0, 0)
		body.apply_knockback(rel.normalized() * knockback + Vector3.UP * 3.0)
		AudioManager.play_environment("hit", 0.08, -4.0 if body.is_local else -10.0)
