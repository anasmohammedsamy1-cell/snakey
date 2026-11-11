extends Node3D
## Floor hazards that change how players move: CONVEYOR belt, ICE patch, FAN (wind).
##
## No physics bodies are involved (nothing to get stuck on): every player asks the zones it is standing in
## through influence_at(), once per physics frame, and adds the result to its own movement. Each peer
## simulates only the players it owns, so the rule is the same one the hammers and bumpers already use.
##
## Local axes: +X is the "forward" direction of the belt / wind (rotate the node about Y to aim it),
## `size` = (length along X, width along Z). A fan blows from its origin along +X for `size.x` metres.

const Scenery := preload("res://scripts/scenery.gd")

enum Kind { CONVEYOR, ICE, FAN }

@export var kind: Kind = Kind.CONVEYOR
@export var size := Vector2(6.0, 3.0)
@export var strength := 3.2          # belt speed (m/s) or peak wind speed (m/s)
@export var color := Color(0.25, 0.27, 0.33)
@export var phase := 0.0             # fan: shifts the on/off rhythm so fans do not all blow together
@export var height := 3.0            # fan: how high the wind reaches above the floor

var round_manager: Node = null       # only used to keep the fans' on/off rhythm in step on every device
var _chevrons: Array[Node3D] = []
var _streaks: Array[MeshInstance3D] = []
var _blades: Node3D
var _t := 0.0


func _ready() -> void:
	add_to_group("floor_zones")
	match kind:
		Kind.CONVEYOR:
			_build_conveyor()
		Kind.ICE:
			_build_ice()
		Kind.FAN:
			_build_fan()


# ---------------------------------------------------------------------------
# Query (called by player_controller._query_zones)

## Returns {"ice": bool, "belt": Vector3, "wind": Vector3} contribution of this zone at a world position.
func influence_at(pos: Vector3, on_floor: bool, out: Dictionary = {}) -> Dictionary:
	out["ice"] = false
	out["belt"] = Vector3.ZERO
	out["wind"] = Vector3.ZERO
	var local := to_local(pos)
	if local.y < -0.6 or local.y > height + 1.0:
		return out
	match kind:
		Kind.ICE:
			if on_floor and absf(local.x) <= size.x * 0.5 and absf(local.z) <= size.y * 0.5 and local.y < 1.2:
				out["ice"] = true
		Kind.CONVEYOR:
			if on_floor and absf(local.x) <= size.x * 0.5 and absf(local.z) <= size.y * 0.5 and local.y < 1.2:
				out["belt"] = global_transform.basis.x.normalized() * strength
		Kind.FAN:
			if local.x >= 0.0 and local.x <= size.x and absf(local.z) <= size.y * 0.5 and local.y < height:
				var falloff := 1.0 - 0.65 * (local.x / maxf(size.x, 0.1))
				out["wind"] = global_transform.basis.x.normalized() * strength * falloff * wind_level()
	return out


## 0..1: fans blow in pulses (about 2.6 s on, 1.4 s off) so players can time a run through the wind.
func wind_level() -> float:
	var t := _clock() + phase
	var ph := fposmod(t, 4.0)
	if ph < 2.6:
		return 1.0
	if ph < 3.0:
		return 1.0 - (ph - 2.6) / 0.4
	if ph > 3.7:
		return (ph - 3.7) / 0.3
	return 0.0


func _clock() -> float:
	if round_manager != null and is_instance_valid(round_manager):
		return float(round_manager.get("elapsed"))
	return _t


# ---------------------------------------------------------------------------
# Visuals

func _process(delta: float) -> void:
	_t += delta
	match kind:
		Kind.CONVEYOR:
			var shift := fposmod(_t * strength * 0.9, 1.6)
			for i in _chevrons.size():
				var c := _chevrons[i]
				var x := -size.x * 0.5 + fposmod(float(i) * 1.6 + shift, size.x)
				c.position.x = x
		Kind.FAN:
			var lvl := wind_level()
			if _blades != null:
				_blades.rotation.x += delta * (3.0 + 22.0 * lvl)
			for i in _streaks.size():
				var s := _streaks[i]
				s.visible = lvl > 0.15
				var run := fposmod(_t * (6.0 + 5.0 * lvl) + float(i) * size.x / float(_streaks.size()), size.x)
				s.position.x = 0.9 + run * 0.9


func _slab(sz: Vector3, col: Color, pos: Vector3, rough := 0.6, alpha := 1.0) -> MeshInstance3D:
	var mi := Scenery.mesh_instance(Scenery.box(sz), Scenery.mat(col, rough, false, alpha), pos, false)
	add_child(mi)
	return mi


func _build_conveyor() -> void:
	_slab(Vector3(size.x, 0.06, size.y), color, Vector3(0, 0.03, 0))
	for side in [-1.0, 1.0]:
		_slab(Vector3(size.x, 0.1, 0.18), Color(1.0, 0.8, 0.1), Vector3(0, 0.05, side * (size.y * 0.5 - 0.09)))
	var count := int(ceil(size.x / 1.6)) + 1
	var mat := Scenery.mat(Color(1.0, 0.85, 0.15), 0.4, true)
	for i in count:
		var chev := Node3D.new()
		chev.position = Vector3(0, 0.075, 0)
		for sgn in [-1.0, 1.0]:
			var arm := Scenery.mesh_instance(Scenery.box(Vector3(0.62, 0.02, 0.14)), mat, Vector3(-0.15, 0, sgn * 0.17), false)
			arm.rotation_degrees.y = 36.4 * sgn
			chev.add_child(arm)
		add_child(chev)
		_chevrons.append(chev)


func _build_ice() -> void:
	var m := Scenery.dup_material(Scenery.mat(Color(0.62, 0.9, 1.0), 0.08, false, 0.88)) as StandardMaterial3D
	m.metallic = 0.35
	add_child(Scenery.mesh_instance(Scenery.box(Vector3(size.x, 0.05, size.y)), m, Vector3(0, 0.025, 0), false))
	var line := Scenery.mat(Color(1, 1, 1), 0.3, true, 0.7)
	for i in 4:
		var l := Scenery.mesh_instance(Scenery.box(Vector3(size.x * (0.25 + 0.1 * float(i % 2)), 0.01, 0.05)), line,
				Vector3(-size.x * 0.2 + float(i) * size.x * 0.12, 0.056, -size.y * 0.3 + float(i) * size.y * 0.2), false)
		l.rotation_degrees.y = 18.0 + 11.0 * float(i)
		add_child(l)


func _build_fan() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.7, 1.3, 1.9)
	shape.shape = box
	shape.position = Vector3(-0.05, 0.65, 0)
	body.add_child(shape)
	add_child(body)
	add_child(Scenery.mesh_instance(Scenery.box(Vector3(0.7, 0.2, 1.3)), Scenery.mat(Color(0.3, 0.32, 0.4), 0.7), Vector3(-0.05, 0.1, 0)))
	add_child(Scenery.mesh_instance(Scenery.cylinder(0.12, 0.2, 0.9, 8), Scenery.mat(Color(0.3, 0.32, 0.4), 0.7), Vector3(-0.05, 0.6, 0)))
	var ring := Scenery.mesh_instance(Scenery.torus(0.78, 0.95, 24, 8), Scenery.mat(Color(0.85, 0.2, 0.2), 0.45), Vector3(0, 1.15, 0))
	ring.rotation_degrees.z = 90.0
	add_child(ring)
	_blades = Node3D.new()
	_blades.position = Vector3(0, 1.15, 0)
	add_child(_blades)
	var bm := Scenery.mat(Color(0.92, 0.92, 0.97), 0.5)
	for i in 3:
		var blade := Scenery.mesh_instance(Scenery.box(Vector3(0.05, 0.78, 0.26)), bm, Vector3(0, 0.4, 0), false)
		var pivot := Node3D.new()
		pivot.rotation_degrees.x = float(i) * 120.0
		pivot.add_child(blade)
		_blades.add_child(pivot)
	var sm := Scenery.mat(Color(1, 1, 1), 0.3, true, 0.35)
	for i in 5:
		var st := Scenery.mesh_instance(Scenery.box(Vector3(1.1, 0.04, 0.06)), sm, Vector3(1.0, 0.5 + 0.38 * float(i), (float(i % 3) - 1.0) * size.y * 0.28), false)
		add_child(st)
		_streaks.append(st)
