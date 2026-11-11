extends StaticBody3D
## One tier ("layer") of an arena floor.
## The floor is built from concentric tiers by MapBuilder (scripts/map_builder.gd). Sudden Death
## drops the outer tiers first, so the safe area really shrinks and the survivors are forced
## together. Same host-authority flow as falling_tile.gd: the host calls trigger() locally and
## then _rpc_trigger.rpc(), so every peer runs the same sequence and nothing desyncs.

const WARN_TIME := 0.55          # crack + shake window before the collision is removed
const FALL_TIME := 1.15          # how long the plate takes to fall out of view
const FALL_DEPTH := 18.0

@export var layer_index := 0     # 0 = outermost tier of the floor

var dropped := false
var _state := 0                  # 0 idle, 1 warning, 2 falling
var _t := 0.0


func _ready() -> void:
	add_to_group("obstacles")
	add_to_group("arena_crumble_tiles")
	collision_layer = 1
	collision_mask = 0
	set_process(false)


## Higher rank = collapsed first. Tiers always go before loose crumbling tiles,
## and the outermost tier goes before the ones inside it.
func collapse_rank() -> float:
	return 1.0e9 - float(layer_index)


func can_be_event_triggered() -> bool:
	return not dropped and is_inside_tree()


func trigger() -> void:
	if not can_be_event_triggered():
		return
	dropped = true
	_state = 1
	_t = 0.0
	AudioManager.play_environment("crack", 0.08, -2.0)
	set_process(true)


@rpc("authority", "call_remote", "reliable")
func _rpc_trigger() -> void:
	if dropped:
		return
	dropped = true
	_state = 1
	_t = 0.0
	AudioManager.play_environment("crack", 0.08, -7.0)
	set_process(true)


func _process(delta: float) -> void:
	if _state == 1:
		_t += delta
		if _t >= WARN_TIME:
			_state = 2
			_t = 0.0
			_disable_collision(self)
			AudioManager.play_environment("fall", 0.12, -9.0)
	elif _state == 2:
		_t += delta
		var k := clampf(_t / FALL_TIME, 0.0, 1.0)
		position.y = -FALL_DEPTH * k * k
		if k >= 1.0:
			set_process(false)
			queue_free()


## Everything standing on this tier falls with it: the floor shapes, and any obstacle that was
## parented here (hammers, bumpers). Recursive because the obstacles are ordinary child nodes.
func _disable_collision(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).set_deferred("disabled", true)
		elif child is CollisionObject3D:
			(child as CollisionObject3D).set_deferred("collision_layer", 0)
		elif child is Node:
			_disable_collision(child)
