extends StaticBody3D
## Crumbling floor tile. A detector Area3D above the tile notices players;
## the HOST decides when a tile is triggered and tells everyone (reliable RPC),
## so all peers see the same tiles fall. Tiles reset automatically because the
## arena scene is reloaded for every round.

const Scenery := preload("res://scripts/scenery.gd")

enum TileState { IDLE, WARNING, FALLING, GONE }

@export var tile_size := Vector3(2.6, 0.4, 2.6)
@export var color := Color(0.2, 0.85, 0.95)
@export var warning_time := 0.7

var state: int = TileState.IDLE
var _timer := 0.0
var _base_pos := Vector3.ZERO
var _mat: Material            # ShaderMaterial on MEDIUM/HIGH, StandardMaterial3D on LOW
var _shader_mat: ShaderMaterial

@onready var shape: CollisionShape3D = $CollisionShape3D
@onready var mesh: MeshInstance3D = $Mesh
@onready var detector: Area3D = $Detector
@onready var detector_shape: CollisionShape3D = $Detector/DetectorShape


func _ready() -> void:
	add_to_group("obstacles")
	add_to_group("arena_crumble_tiles")
	collision_layer = 1
	collision_mask = 0
	var box := BoxShape3D.new()
	box.size = tile_size
	shape.shape = box
	mesh.mesh = Scenery.box(tile_size)
	# Each tile keeps its own copy: it mutates the material every frame while warning/falling.
	_mat = Scenery.dup_material(Scenery.floor_mat(color, 0.7, maxf(tile_size.x, 0.5)))
	if _mat is ShaderMaterial:
		_shader_mat = _mat as ShaderMaterial
	mesh.material_override = _mat
	var dbox := BoxShape3D.new()
	dbox.size = Vector3(tile_size.x * 0.95, 0.7, tile_size.z * 0.95)
	detector_shape.shape = dbox
	detector_shape.position = Vector3(0, tile_size.y * 0.5 + 0.35, 0)
	detector.collision_layer = 0
	detector.collision_mask = 2
	detector.monitorable = false
	detector.body_entered.connect(_on_body_entered)
	_base_pos = position


func configure(p_size: Vector3, p_color: Color) -> void:
	tile_size = p_size
	color = p_color


func _on_body_entered(body: Node) -> void:
	if state != TileState.IDLE:
		return
	if not body.is_in_group("players"):
		return
	if not multiplayer.is_server():
		return
	trigger()
	if NetworkManager.online:
		_rpc_trigger.rpc()


@rpc("authority", "call_remote", "reliable")
func _rpc_trigger() -> void:
	trigger()


func can_be_event_triggered() -> bool:
	return state == TileState.IDLE and is_inside_tree()


func trigger() -> void:
	if state != TileState.IDLE:
		return
	state = TileState.WARNING
	_timer = warning_time
	AudioManager.play_environment("crack", 0.1, -8.0)


func _process(delta: float) -> void:
	match state:
		TileState.WARNING:
			_timer -= delta
			mesh.position = Vector3(randf_range(-0.04, 0.04), 0.0, randf_range(-0.04, 0.04))
			_flash(0.5 + 0.5 * sin(_timer * 40.0))
			if _timer <= 0.0:
				_start_fall()
		TileState.FALLING:
			_timer += delta
			position = _base_pos + Vector3(0.0, -_timer * _timer * 7.0, 0.0)
			rotation.x += delta * 0.9
			_fade_out()
			if _timer > 1.6:
				state = TileState.GONE
				visible = false
		_:
			pass


## Warning flash: a white pulse on the tile. Works on both material backends
## (shader "flash" uniform on MEDIUM/HIGH, albedo lerp on LOW).
func _flash(amount: float) -> void:
	var a := clampf(amount, 0.0, 1.0)
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("flash", a)
	elif _mat is StandardMaterial3D:
		(_mat as StandardMaterial3D).albedo_color = color.lerp(Color.WHITE, a)


## Falling: shader tiles burn white-hot and cool as they sink; on LOW the alpha
## fades out exactly as before.
func _fade_out() -> void:
	var a := clampf(1.5 - _timer, 0.0, 1.0)
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("flash", a)
	elif _mat is StandardMaterial3D:
		(_mat as StandardMaterial3D).albedo_color = Color(color.r, color.g, color.b, a)


func _start_fall() -> void:
	state = TileState.FALLING
	_timer = 0.0
	shape.set_deferred("disabled", true)
	detector.set_deferred("monitoring", false)
	mesh.position = Vector3.ZERO
	if _mat is StandardMaterial3D:
		var std := _mat as StandardMaterial3D
		std.albedo_color = color
		std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		# Shader path: the tile flashes white-hot the moment it breaks.
		_flash(1.0)
