extends AnimatableBody3D
## Moving platform that shuttles between two points. Driven by the shared round
## clock so all peers agree on its position. sync_to_physics makes the physics
## server compute the platform velocity, so CharacterBody3D riders are carried
## smoothly (no random launches into the air).

const Scenery := preload("res://scripts/scenery.gd")

@export var point_a := Vector3.ZERO
@export var point_b := Vector3(0, 0, 5)
@export var period := 6.0
@export var platform_size := Vector3(3.0, 0.5, 3.0)
@export var color := Color(0.62, 0.36, 0.95)
@export var phase := 0.0

var round_manager: Node = null
var _local_time := 0.0

@onready var shape: CollisionShape3D = $CollisionShape3D
@onready var mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	add_to_group("obstacles")
	sync_to_physics = true
	collision_layer = 1
	collision_mask = 0
	var box := BoxShape3D.new()
	box.size = platform_size
	shape.shape = box
	mesh.mesh = Scenery.box(platform_size)
	mesh.material_override = Scenery.mat(color, 0.6)
	# Light rim on top for readability
	var rim := Scenery.mesh_instance(Scenery.box(Vector3(platform_size.x * 1.02, 0.08, platform_size.z * 1.02)), Scenery.mat(Color(1, 1, 1), 0.5), Vector3(0, platform_size.y * 0.5, 0), false)
	add_child(rim)
	# Arrow marks (small boxes) showing it moves
	var arrow := Scenery.mesh_instance(Scenery.box(Vector3(platform_size.x * 0.5, 0.02, 0.25)), Scenery.mat(color.darkened(0.35), 0.6), Vector3(0, platform_size.y * 0.5 + 0.05, 0), false)
	add_child(arrow)
	global_position = point_a


func configure(a: Vector3, b: Vector3, p_period: float, p_color: Color, p_phase := 0.0) -> void:
	point_a = a
	point_b = b
	period = p_period
	color = p_color
	phase = p_phase


func _clock() -> float:
	if round_manager != null:
		return float(round_manager.elapsed)
	return _local_time


func _physics_process(delta: float) -> void:
	_local_time += delta
	var k := 0.5 - 0.5 * cos((_clock() / maxf(period, 0.1) + phase) * TAU)
	global_position = point_a.lerp(point_b, k)
