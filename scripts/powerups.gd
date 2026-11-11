extends Node
## Floor power-ups: SPEED STAR, SPRING BOOTS, BUBBLE SHIELD, GIANT FIST, MAGNET.
## Host-authoritative: the host decides when/where an item spawns and who collected it; every peer mirrors it
## through reliable RPCs. A player's own peer detects the touch and asks the host (so a laggy client is never
## cheated out of an item it clearly touched), the host validates and broadcasts the result.
## The effect itself lives in PlayerController (apply_powerup), because movement is owner-authoritative.

const GameConstants := preload("res://scripts/game_constants.gd")
const Scenery := preload("res://scripts/scenery.gd")
const ITEM_GLOW_SHADER := preload("res://assets/shaders/item_glow.gdshader")

const MAX_ACTIVE := 3
const SPAWN_MIN := 6.0
const SPAWN_MAX := 10.0
const ITEM_TTL := 16.0
const PICKUP_RADIUS := 1.35

const TYPES := [
	{"key": "pu_speed", "color": Color(1.0, 0.85, 0.12), "duration": 8.0},
	{"key": "pu_boots", "color": Color(0.35, 0.95, 0.4), "duration": 10.0},
	{"key": "pu_shield", "color": Color(0.3, 0.85, 1.0), "duration": 12.0},
	{"key": "pu_fist", "color": Color(1.0, 0.45, 0.15), "duration": 20.0},
	{"key": "pu_magnet", "color": Color(0.9, 0.25, 0.9), "duration": 9.0},
]
const MAGNET_TYPE := 4
const MAGNET_ITEM_RANGE := 8.0      # power-ups within this distance fly to the magnet carrier
const MAGNET_ITEM_SPEED := 7.0

var rm: Node
var _enabled := false
var _items: Dictionary = {}          # id -> {"node": Node3D, "type": int, "base_y": float, "ttl": float}
var _asked: Dictionary = {}          # id -> msec of the last request (spam guard)
var _next_id := 1
var _spawn_timer := 5.0
var _clock := 0.0
var _fist: Dictionary = {}           # host only: player id -> expiry (seconds) of the GIANT FIST (next punch x2.2)


func setup(round_manager: Node) -> void:
	rm = round_manager
	var kind := int(rm.arena.map_info.get("kind", 0))
	_enabled = kind == 0 and rm.mode != GameConstants.MODE_HIDE and rm.mode != GameConstants.MODE_TRAMPOLINE
	_spawn_timer = randf_range(SPAWN_MIN, SPAWN_MAX)


func _physics_process(delta: float) -> void:
	if not _enabled or rm == null or int(rm.state) != 2:       # 2 = State.PLAYING
		return
	_clock += delta
	if rm.is_host:
		_host_tick(delta)
	_local_pickup_check()


func _process(delta: float) -> void:
	_pull_items_to_magnets(delta)
	for id in _items:
		var it: Dictionary = _items[id]
		var n: Node3D = it["node"]
		if is_instance_valid(n):
			n.rotation.y += delta * 2.2
			n.position.y = float(it["base_y"]) + sin(_clock * 3.0 + float(id)) * 0.12


## A player holding the MAGNET draws nearby power-ups toward them (every peer moves its own copy of the item;
## the host still decides who collected it, so a small difference in position between peers is harmless).
func _pull_items_to_magnets(delta: float) -> void:
	if _items.is_empty() or rm == null:
		return
	for p in rm.players.values():
		if not is_instance_valid(p) or not p.is_alive or int(p.get("_pu_type")) != MAGNET_TYPE or float(p.get("_pu_time")) <= 0.0:
			continue
		var goal: Vector3 = p.global_position + Vector3(0.0, 0.9, 0.0)
		for id in _items:
			var n: Node3D = _items[id]["node"]
			if not is_instance_valid(n):
				continue
			var d := n.global_position.distance_to(goal)
			if d > MAGNET_ITEM_RANGE or d < 0.3:
				continue
			n.global_position = n.global_position.move_toward(goal, MAGNET_ITEM_SPEED * delta)
			_items[id]["base_y"] = n.position.y     # the bobbing animation keeps working from the new height


# ---------------------------------------------------------------------------
# Host: spawning and expiry

func _host_tick(delta: float) -> void:
	for id in _items.keys():
		_items[id]["ttl"] = float(_items[id]["ttl"]) - delta
		if float(_items[id]["ttl"]) <= 0.0:
			_remove_item(int(id))
			if NetworkManager.online:
				_rpc_despawn.rpc(int(id))
	_spawn_timer -= delta
	if _spawn_timer > 0.0 or _items.size() >= MAX_ACTIVE:
		return
	_spawn_timer = randf_range(SPAWN_MIN, SPAWN_MAX)
	var pos: Variant = _pick_position()
	if pos == null:
		return
	var type := randi() % TYPES.size()
	var id := _next_id
	_next_id += 1
	_add_item(id, type, pos)
	if NetworkManager.online:
		_rpc_spawn.rpc(id, type, pos)


func _pick_position() -> Variant:
	var radius := float(rm.arena.map_info.get("bot_radius", 6.0)) * 0.7
	var space: PhysicsDirectSpaceState3D = rm.arena.get_world_3d().direct_space_state
	for attempt in 8:
		var a := randf() * TAU
		var r := sqrt(randf()) * radius
		var x := cos(a) * r
		var z := sin(a) * r
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 8.0, z), Vector3(x, -3.0, z), 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var p: Vector3 = hit["position"]
		if p.y > 1.0:
			continue                                   # on top of a pole or a hazard: unreachable
		return p + Vector3(0.0, 0.9, 0.0)
	return null


@rpc("authority", "call_remote", "reliable")
func _rpc_spawn(id: int, type: int, pos: Vector3) -> void:
	_add_item(id, type, pos)


@rpc("authority", "call_remote", "reliable")
func _rpc_despawn(id: int) -> void:
	_remove_item(id)


# ---------------------------------------------------------------------------
# Collecting

func _local_pickup_check() -> void:
	if _items.is_empty():
		return
	var now := Time.get_ticks_msec()
	for id in _items.keys():
		if now - int(_asked.get(id, -10000)) < 600:
			continue
		var n: Node3D = _items[id]["node"]
		if not is_instance_valid(n):
			continue
		for p in rm.players.values():
			if not is_instance_valid(p) or not p.is_alive or not p.is_multiplayer_authority():
				continue
			if p.global_position.distance_to(n.global_position - Vector3(0, 0.6, 0)) > PICKUP_RADIUS:
				continue
			_asked[id] = now
			if rm.is_host:
				_host_collect(int(id), int(p.peer_id))
			else:
				_rpc_request_collect.rpc_id(1, int(id), int(p.peer_id))
			break


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_collect(id: int, pid: int) -> void:
	if not multiplayer.is_server():
		return
	var p: Node = rm.players.get(pid)
	if p == null or p.get_multiplayer_authority() != multiplayer.get_remote_sender_id():
		return                                         # a peer may only collect for the players it owns
	_host_collect(id, pid)


func _host_collect(id: int, pid: int) -> void:
	if not _items.has(id):
		return
	var p: Node = rm.players.get(pid)
	if p == null or not is_instance_valid(p) or not p.is_alive:
		return
	var type := int(_items[id]["type"])
	_fist.erase(pid)
	if type == 3:
		_fist[pid] = Time.get_ticks_msec() / 1000.0 + float(TYPES[3]["duration"])
	_apply_collected(id, pid, type)
	if NetworkManager.online:
		_rpc_collected.rpc(id, pid, type)


@rpc("authority", "call_remote", "reliable")
func _rpc_collected(id: int, pid: int, type: int) -> void:
	_apply_collected(id, pid, type)


func _apply_collected(id: int, pid: int, type: int) -> void:
	_remove_item(id)
	var p: Node = rm.players.get(pid)
	if p != null and is_instance_valid(p) and p.has_method("apply_powerup"):
		p.apply_powerup(type, float(TYPES[clampi(type, 0, TYPES.size() - 1)]["duration"]))
	AudioManager.play_environment("pickup", 0.05, -4.0)


## Host: strength multiplier for this player's next punch. The GIANT FIST is spent by the hit.
func consume_fist(pid: int) -> float:
	if not _fist.has(pid):
		return 1.0
	var alive_until := float(_fist[pid])
	_fist.erase(pid)
	if Time.get_ticks_msec() / 1000.0 > alive_until:
		return 1.0
	shield_used(pid)                                   # same "drop the aura everywhere" message
	var p: Node = rm.players.get(pid)
	if p != null and is_instance_valid(p) and p.has_method("clear_powerup"):
		p.clear_powerup()                              # the RPC is call_remote: clear the host copy too
	return 2.2


## A shield absorbed a hit: tell everybody to drop the bubble.
func shield_used(pid: int) -> void:
	if NetworkManager.online:
		_rpc_shield_used.rpc(pid)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_shield_used(pid: int) -> void:
	var p: Node = rm.players.get(pid)
	if p != null and is_instance_valid(p) and p.has_method("clear_powerup"):
		p.clear_powerup()


# ---------------------------------------------------------------------------
# Item visuals (same on every peer)

func _add_item(id: int, type: int, pos: Vector3) -> void:
	type = clampi(type, 0, TYPES.size() - 1)
	var def: Dictionary = TYPES[type]
	var col: Color = def["color"]
	var node := Node3D.new()
	node.name = "Pickup%d" % id
	rm.arena.add_child(node)
	node.global_position = pos

	# Glowing core sphere with shader emission
	var core := MeshInstance3D.new()
	core.mesh = Scenery.sphere(0.34, 12, 6)
	var core_mat := ShaderMaterial.new()
	core_mat.shader = ITEM_GLOW_SHADER
	core_mat.set_shader_parameter("glow_color", Color(col.r, col.g, col.b, 0.85))
	core_mat.set_shader_parameter("pulse_speed", 5.0)
	core_mat.set_shader_parameter("emission_strength", 5.0)
	core.material_override = core_mat
	node.add_child(core)

	# Glowing ring torus with shader emission
	var ring := MeshInstance3D.new()
	ring.mesh = Scenery.torus(0.5, 0.62, 20, 8)
	var ring_mat := ShaderMaterial.new()
	ring_mat.shader = ITEM_GLOW_SHADER
	ring_mat.set_shader_parameter("glow_color", Color(col.r, col.g, col.b, 0.55))
	ring_mat.set_shader_parameter("pulse_speed", 3.0)
	ring_mat.set_shader_parameter("emission_strength", 3.0)
	ring.material_override = ring_mat
	ring.rotation.x = PI * 0.5
	node.add_child(ring)
	var label := Label3D.new()
	label.text = GameManager.t(str(def["key"]))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.pixel_size = 0.01
	label.outline_size = 10
	label.modulate = Color(1, 1, 1)
	label.no_depth_test = true
	label.position = Vector3(0, 0.95, 0)
	node.add_child(label)
	_items[id] = {"node": node, "type": type, "base_y": node.position.y, "ttl": ITEM_TTL}


func _remove_item(id: int) -> void:
	if not _items.has(id):
		return
	var n: Node3D = _items[id]["node"]
	if is_instance_valid(n):
		n.queue_free()
	_items.erase(id)
	_asked.erase(id)
