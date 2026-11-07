extends Node3D
## Rotating hammer / sweeper. The pose is a deterministic function of the round
## clock (round_manager.elapsed), so every peer sees the same motion without
## per-frame network traffic. The hammer head is an Area3D that knocks players
## away; each peer applies the hit to the players it has authority over.

const Scenery := preload("res://scripts/scenery.gd")

@export var arm_length := 3.0
@export var rotation_speed := 1.4          # rad/s, negative reverses
@export var head_height := 1.0
@export var head_size := Vector3(0.9, 0.8, 1.5)
@export var double_sided := false
@export var color := Color(0.95, 0.27, 0.27)
@export var start_angle := 0.0
@export var knockback := 11.0
@export var pole_height := 3.4
@export var hit_cooldown := 0.7

var round_manager: Node = null
var _recent: Dictionary = {}
var _local_time := 0.0
var _hit_particles: CPUParticles3D

@onready var pivot: Node3D = $Pivot
@onready var hit_area: Area3D = $Pivot/HitArea
@onready var hit_shape: CollisionShape3D = $Pivot/HitArea/HitShape


func _ready() -> void:
	add_to_group("obstacles")
	hit_area.collision_layer = 0
	hit_area.collision_mask = 2
	hit_area.monitorable = false
	_build()


func configure(p_arm_length: float, p_speed: float, p_head_height: float, p_color: Color, p_double := false, p_start := 0.0, p_head_size := Vector3(0.9, 0.8, 1.5)) -> void:
	arm_length = p_arm_length
	rotation_speed = p_speed
	head_height = p_head_height
	color = p_color
	double_sided = p_double
	start_angle = p_start
	head_size = p_head_size


func _build() -> void:
	var dark := Scenery.mat(Color(0.25, 0.22, 0.35), 0.6)
	var head_mat := Scenery.mat(color, 0.5)
	var stripe := Scenery.mat(Color(1, 1, 1), 0.5)

	# Static pole
	var pole := Scenery.mesh_instance(Scenery.cylinder(0.22, 0.3, pole_height, 12), dark, Vector3(0, pole_height * 0.5, 0))
	add_child(pole)
	var cap := Scenery.mesh_instance(Scenery.sphere(0.35, 12, 6), Scenery.mat(color.lightened(0.3), 0.5), Vector3(0, pole_height, 0))
	add_child(cap)
	var base := Scenery.mesh_instance(Scenery.cylinder(0.6, 0.7, 0.25, 16), dark, Vector3(0, 0.12, 0))
	add_child(base)

	# Rotating arm(s) + head(s)
	var sides := [1.0]
	if double_sided:
		sides = [1.0, -1.0]
	var first := true
	for side in sides:
		var s := float(side)
		var arm := Scenery.mesh_instance(Scenery.box(Vector3(arm_length, 0.2, 0.2)), dark, Vector3(arm_length * 0.5 * s, head_height, 0))
		pivot.add_child(arm)
		var head := Scenery.mesh_instance(Scenery.box(head_size), head_mat, Vector3(arm_length * s, head_height, 0))
		pivot.add_child(head)
		var band := Scenery.mesh_instance(Scenery.box(Vector3(head_size.x * 0.3, head_size.y * 1.04, head_size.z * 1.04)), stripe, Vector3(arm_length * s, head_height, 0))
		pivot.add_child(band)
		var marker := Node3D.new()
		marker.position = Vector3(arm_length * s, head_height, 0)
		marker.add_to_group("hazards")
		pivot.add_child(marker)
		var shape_node: CollisionShape3D
		if first:
			shape_node = hit_shape
			first = false
		else:
			shape_node = CollisionShape3D.new()
			hit_area.add_child(shape_node)
		var box := BoxShape3D.new()
		box.size = head_size * 1.05
		shape_node.shape = box
		shape_node.position = Vector3(arm_length * s, head_height, 0)

	_hit_particles = CPUParticles3D.new()
	_hit_particles.emitting = false
	_hit_particles.one_shot = true
	_hit_particles.amount = 4 if int(SettingsManager.get_setting("graphics_preset")) == SettingsManager.PRESET_LOW else 12
	_hit_particles.lifetime = 0.5
	_hit_particles.explosiveness = 1.0
	_hit_particles.spread = 180.0
	_hit_particles.initial_velocity_min = 2.0
	_hit_particles.initial_velocity_max = 5.0
	_hit_particles.gravity = Vector3(0, -6, 0)
	_hit_particles.scale_amount_min = 0.4
	_hit_particles.scale_amount_max = 0.9
	var pm := SphereMesh.new()
	pm.radius = 0.12
	pm.height = 0.24
	pm.radial_segments = Scenery.detail_segments(6)
	pm.rings = Scenery.detail_rings(3)
	pm.material = Scenery.mat(Color(1.0, 0.9, 0.3), 0.5, true)
	_hit_particles.mesh = pm
	add_child(_hit_particles)


func _clock() -> float:
	if round_manager != null:
		return float(round_manager.elapsed)
	return _local_time


func _physics_process(delta: float) -> void:
	_local_time += delta
	pivot.rotation.y = start_angle + _clock() * rotation_speed
	var now := Time.get_ticks_msec() / 1000.0
	for body in hit_area.get_overlapping_bodies():
		if not body.is_in_group("players"):
			continue
		if not body.is_multiplayer_authority() or not body.is_alive:
			continue
		var key := body.get_instance_id()
		if now - float(_recent.get(key, -10.0)) < hit_cooldown:
			continue
		_recent[key] = now
		_hit(body)


func _hit(body: Node3D) -> void:
	var rel := body.global_position - global_position
	rel.y = 0.0
	if rel.length() < 0.01:
		rel = Vector3(1, 0, 0)
	var radial := rel.normalized()
	var tangent := Vector3(radial.z, 0.0, -radial.x) * signf(rotation_speed)
	var speed_factor := clampf(absf(rotation_speed) * arm_length / 4.0, 0.7, 1.6)
	var impulse := (tangent * knockback + radial * knockback * 0.35) * speed_factor + Vector3.UP * 4.5
	body.apply_knockback(impulse)
	AudioManager.play_environment("hit", 0.08, 0.0 if body.is_local else -8.0)
	if body.is_local:
		GameManager.vibrate(70)
	if _hit_particles != null and bool(SettingsManager.get_setting("effects")):
		_hit_particles.global_position = body.global_position + Vector3(0, 1.0, 0)
		_hit_particles.restart()
