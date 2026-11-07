extends RefCounted
## Builds the geometry of every map into the arena node.
## build() returns a Dictionary describing the map:
##   spawns        : Array[Vector3]         spawn points (arena maps, group 0)
##   spawn_groups  : Array[Array]           houses: [hider spawns, seeker spawns]
##   bot_radius    : float                  bots try to stay inside this radius (arena maps)
##   bot_min_radius: float                  ... and outside this one (donut)
##   cam_radius    : float                  spectator camera orbit radius
##   cam_height    : float
##   kind          : 0 arena, 1 house, 2 trampoline arena
##   rooms / graph : houses only, used by hide-and-seek bots for navigation
## Usage: const MapBuilder := preload("res://scripts/map_builder.gd")

const GameConstants := preload("res://scripts/game_constants.gd")
const Scenery := preload("res://scripts/scenery.gd")
const PropsLib := preload("res://scripts/props.gd")
const HammerScene := preload("res://scenes/obstacles/rotating_hammer.tscn")
const PlatformScene := preload("res://scenes/obstacles/moving_platform.tscn")
const TileScene := preload("res://scenes/obstacles/falling_tile.tscn")

const MAP_CLOUD := 0
const MAP_RING := 1
const MAP_TILES := 2
const MAP_ISLANDS := 3
const MAP_DONUT := 4
const MAP_VILLA := 5
const MAP_FLAT := 6
const MAP_BOUNCE_DOME := 7
const MAP_NEON_SPRINGS := 8
const MAP_CANDY_CLOUD := 9
const MAP_SKY_BOUNCE := 10
const MAP_PINBALL_BOUNCE := 11
const MAP_TWISTER := 12
const MAP_SCHOOL := 13
const MAP_WAREHOUSE := 14
const MAP_MUSEUM := 15


static func build(map_id: int, arena: Node3D) -> Dictionary:
	match map_id:
		MAP_TWISTER:
			return _build_twister(arena)
		MAP_RING:
			return _build_ring(arena)
		MAP_TILES:
			return _build_tiles(arena)
		MAP_ISLANDS:
			return _build_islands(arena)
		MAP_DONUT:
			return _build_donut(arena)
		MAP_VILLA:
			return _build_house(arena, 4, 3, 8.0, 8.0, 7771, 0)
		MAP_FLAT:
			return _build_house(arena, 3, 2, 7.0, 7.0, 4242, 1)
		MAP_SCHOOL:
			return _build_school(arena)
		MAP_WAREHOUSE:
			return _build_house(arena, 3, 3, 9.0, 9.0, 1802, 3)
		MAP_MUSEUM:
			return _build_house(arena, 4, 2, 9.0, 9.0, 1803, 4)
		MAP_BOUNCE_DOME:
			return _build_trampoline(arena, 0)
		MAP_NEON_SPRINGS:
			return _build_trampoline(arena, 1)
		MAP_CANDY_CLOUD:
			return _build_trampoline(arena, 2)
		MAP_SKY_BOUNCE:
			return _build_trampoline(arena, 3)
		MAP_PINBALL_BOUNCE:
			return _build_trampoline(arena, 4)
		_:
			return _build_cloud(arena)


# ---------------------------------------------------------------------------
# Shared helpers

static func _ring_spawns(count: int, radius: float, offset := 0.0, y := 0.6) -> Array:
	var out: Array = []
	for i in count:
		var a := float(i) * TAU / float(count) + offset
		out.append(Vector3(cos(a) * radius, y, sin(a) * radius))
	return out


static func _static_disc(arena: Node3D, radius: float, color: Color, side: Color, pos := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 1.0
	shape.shape = cyl
	shape.position.y = -0.5
	body.add_child(shape)
	body.add_child(Scenery.mesh_instance(Scenery.cylinder(radius, radius - 0.4, 1.0, 48), Scenery.mat(color, 0.7), Vector3(0, -0.5, 0)))
	body.add_child(Scenery.mesh_instance(Scenery.cylinder(radius - 0.4, radius * 0.18, radius * 0.55, 24), Scenery.mat(side, 0.9), Vector3(0, -1.0 - radius * 0.275, 0)))
	var rim := MeshInstance3D.new()
	var torus := Scenery.torus(radius - 0.4, radius + 0.1, 48, 8)
	rim.mesh = torus
	rim.material_override = Scenery.mat(Color(1, 1, 1), 0.5)
	rim.position.y = -0.05
	body.add_child(rim)
	arena.add_child(body)
	return body


static func _checker_tiles(parent: Node3D, radius: float, cell: float) -> void:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var tile := BoxMesh.new()
	tile.size = Vector3(cell * 0.95, 0.16, cell * 0.95)
	var tmat := StandardMaterial3D.new()
	tmat.vertex_color_use_as_albedo = true
	tmat.roughness = 0.65
	tmat.rim_enabled = not _is_low_quality()
	tmat.rim = 0.2 if not _is_low_quality() else 0.0
	tile.material = tmat
	mm.mesh = tile
	var transforms: Array = []
	var colors: Array = []
	var n := int(ceil(radius / cell)) + 1
	for ix in range(-n, n + 1):
		for iz in range(-n, n + 1):
			var pos := Vector3(float(ix) * cell, -0.06, float(iz) * cell)
			if Vector2(pos.x, pos.z).length() + cell * 0.7 > radius:
				continue
			transforms.append(Transform3D(Basis.IDENTITY, pos))
			var ring := int(Vector2(pos.x, pos.z).length() / (cell * 1.6))
			colors.append(GameConstants.ARENA_PALETTE[(ring + absi(ix + iz)) % GameConstants.ARENA_PALETTE.size()])
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
	mmi.multimesh = mm
	parent.add_child(mmi)


static func _sweeper(arena: Node3D, pos: Vector3, arm: float, speed: float, color: Color, height := 0.55) -> void:
	var s := HammerScene.instantiate()
	s.configure(arm, speed, height, color, true, 0.0, Vector3(1.2, 0.5, 0.8))
	s.pole_height = 2.2
	s.knockback = 9.0
	s.round_manager = arena.round_manager
	s.position = pos
	arena.obstacles_root.add_child(s)


static func _hammer(arena: Node3D, pos: Vector3, arm: float, speed: float, color: Color, phase := 0.0) -> void:
	var h := HammerScene.instantiate()
	h.configure(arm, speed, 1.0, color, false, phase)
	h.round_manager = arena.round_manager
	h.position = pos
	arena.obstacles_root.add_child(h)


static func _crumble_ring(arena: Node3D, count: int, radius: float, tile_size: Vector3) -> void:
	for i in count:
		var a := float(i) * TAU / float(count)
		var tile := TileScene.instantiate()
		tile.name = "Tile%d" % i
		tile.configure(tile_size, GameConstants.ARENA_PALETTE[i % GameConstants.ARENA_PALETTE.size()])
		tile.position = Vector3(cos(a) * radius, -0.2, sin(a) * radius)
		tile.rotation.y = -a
		arena.obstacles_root.add_child(tile)


static func _is_low_quality() -> bool:
	return int(SettingsManager.get_setting("graphics_preset")) == SettingsManager.PRESET_LOW


static func _sky_decor(arena: Node3D, sea_y := -30.0) -> void:
	if _is_low_quality():
		# Weak phones: one small cloud field + the cloud sea only (no far islands, no second field).
		Scenery.build_cloud_field(arena.decor_root, 5, 28.0, 70.0, -14.0, -4.0, 4242)
		Scenery.build_cloud_sea(arena.decor_root, sea_y, 160.0)
		return
	Scenery.build_cloud_field(arena.decor_root, 26, 28.0, 70.0, -14.0, -4.0, 4242)
	Scenery.build_cloud_field(arena.decor_root, 12, 40.0, 90.0, 8.0, 20.0, 777)
	Scenery.build_cloud_sea(arena.decor_root, sea_y, 160.0)
	Scenery.build_distant_islands(arena.decor_root)


static func _balloons(arena: Node3D, ring_radius: float) -> void:
	if _is_low_quality():
		return
	var balloon_colors := [Color(1.0, 0.42, 0.72), Color(1.0, 0.85, 0.12), Color(0.2, 0.85, 0.95), Color(0.45, 0.9, 0.3)]
	for i in 6:
		var a := float(i) * TAU / 6.0 + 0.3
		var pos := Vector3(cos(a) * ring_radius, 4.0 + float(i % 3) * 1.5, sin(a) * ring_radius)
		var balloon := Scenery.mesh_instance(Scenery.sphere(1.1, 14, 8), Scenery.mat(balloon_colors[i % balloon_colors.size()], 0.35), pos, false)
		balloon.scale = Vector3(1.0, 1.2, 1.0)
		arena.decor_root.add_child(balloon)
		var string_mesh := Scenery.mesh_instance(Scenery.cylinder(0.02, 0.02, 3.0, 4), Scenery.mat(Color(1, 1, 1), 0.9, true), pos + Vector3(0, -2.6, 0), false)
		arena.decor_root.add_child(string_mesh)


# ---------------------------------------------------------------------------
# MAP 0: Cloud Arena (large) - the original arena: sweeper, 3 hammers, crumbling ring, bridges

static func _build_cloud(arena: Node3D) -> Dictionary:
	var radius := 13.0
	var body := _static_disc(arena, radius, Color(1.0, 0.6, 0.2), Color(0.5, 0.35, 0.7))
	body.name = "MainPlatform"
	_checker_tiles(body, radius, 2.0)
	body.add_child(Scenery.mesh_instance(Scenery.cylinder(1.6, 1.6, 0.2, 32), Scenery.mat(Color(1, 1, 1), 0.5), Vector3(0, -0.05, 0)))

	var sweeper := HammerScene.instantiate()
	sweeper.name = "CenterSweeper"
	sweeper.configure(4.0, 1.05, 0.55, Color(1.0, 0.56, 0.16), true, 0.0, Vector3(1.2, 0.5, 0.8))
	sweeper.pole_height = 2.2
	sweeper.knockback = 9.0
	sweeper.round_manager = arena.round_manager
	arena.obstacles_root.add_child(sweeper)

	var speeds := [1.3, -1.6, 1.9]
	var colors := [Color(0.95, 0.27, 0.27), Color(0.62, 0.36, 0.95), Color(0.2, 0.85, 0.95)]
	for i in 3:
		var a := float(i) * TAU / 3.0 + PI / 2.0
		var hammer := HammerScene.instantiate()
		hammer.name = "Hammer%d" % i
		hammer.configure(3.0, speeds[i], 1.0, colors[i], false, float(i) * 2.1)
		hammer.round_manager = arena.round_manager
		hammer.position = Vector3(cos(a) * 9.0, 0.0, sin(a) * 9.0)
		arena.obstacles_root.add_child(hammer)

	_crumble_ring(arena, 32, 14.5, Vector3(2.75, 0.4, 2.8))

	var island_colors := [Color(0.45, 0.9, 0.3), Color(1.0, 0.42, 0.72)]
	for i in 2:
		var sign_x := 1.0 if i == 0 else -1.0
		var island := Scenery.build_island(arena, Vector3(26.0 * sign_x, 0.0, 0.0), 3.6, island_colors[i], Color(1.0, 0.6, 0.2), true)
		island.name = "Island%d" % i
		island.add_child(Scenery.mesh_instance(Scenery.cylinder(0.25, 0.3, 3.5, 10), Scenery.mat(Color(1, 1, 1), 0.6), Vector3(0, 1.75, -2.2)))
		island.add_child(Scenery.mesh_instance(Scenery.box(Vector3(1.2, 0.7, 0.05)), Scenery.mat(island_colors[i].lightened(0.2), 0.6), Vector3(0.6, 3.1, -2.2)))
		var platform := PlatformScene.instantiate()
		platform.name = "Bridge%d" % i
		platform.configure(Vector3(18.0 * sign_x, -0.25, 0.0), Vector3(21.0 * sign_x, -0.25, 0.0), 6.0, Color(0.62, 0.36, 0.95), 0.5 * float(i))
		platform.round_manager = arena.round_manager
		arena.obstacles_root.add_child(platform)

	_sky_decor(arena)
	_balloons(arena, 20.0)
	return {
		"kind": 0, "spawns": _ring_spawns(12, 5.2, TAU / 24.0), "bot_radius": 11.0, "bot_min_radius": 0.0,
		"cam_radius": 24.0, "cam_height": 15.0,
	}


# ---------------------------------------------------------------------------
# MAP 1: Mini Ring (small) - one tight platform, a fast sweeper, crumbling rim

# MAP 12: Twister Arena — safe central spawns and opposing sweepers.
static func _build_twister(arena: Node3D) -> Dictionary:
	var radius := 14.0
	var body := _static_disc(arena, radius, Color(0.18, 0.72, 0.72), Color(0.22, 0.27, 0.56))
	body.name = "MainPlatform"
	_checker_tiles(body, radius, 2.0)
	_sweeper(arena, Vector3(-6.0, 0, 0), 3.2, 1.1, Color(1.0, 0.38, 0.23), 0.55)
	_sweeper(arena, Vector3(6.0, 0, 0), 3.2, -1.1, Color(0.62, 0.36, 0.95), 0.55)
	_hammer(arena, Vector3(0, 0, 10.0), 2.0, 1.3, Color(1.0, 0.8, 0.2), 0.0)
	_hammer(arena, Vector3(0, 0, -10.0), 2.0, -1.3, Color(1.0, 0.8, 0.2), 1.5)
	_crumble_ring(arena, 28, 15.5, Vector3(2.9, 0.4, 2.9))
	_sky_decor(arena)
	_balloons(arena, 21.0)
	return {
		"kind": 0, "spawns": _ring_spawns(12, 3.0, TAU / 24.0), "bot_radius": 12.0, "bot_min_radius": 0.0,
		"cam_radius": 25.0, "cam_height": 16.0,
	}


static func _build_ring(arena: Node3D) -> Dictionary:
	var radius := 8.0
	var body := _static_disc(arena, radius, Color(0.2, 0.75, 0.9), Color(0.35, 0.3, 0.6))
	body.name = "MainPlatform"
	_checker_tiles(body, radius, 2.0)
	_sweeper(arena, Vector3.ZERO, 3.2, 1.5, Color(1.0, 0.45, 0.2), 0.55)
	_hammer(arena, Vector3(5.6, 0, 0), 1.9, -1.8, Color(0.95, 0.27, 0.27), 0.0)
	_hammer(arena, Vector3(-5.6, 0, 0), 1.9, 1.8, Color(0.62, 0.36, 0.95), 1.5)
	_crumble_ring(arena, 22, 9.6, Vector3(2.9, 0.4, 2.9))
	_sky_decor(arena)
	_balloons(arena, 16.0)
	# Spawns avoid the two hammer poles (at +/-x): use the top and bottom arcs.
	var spawns: Array = []
	for i in 12:
		var a := float(i) * TAU / 12.0 + TAU / 24.0
		var r := 4.6 if i % 2 == 0 else 3.6
		var p := Vector3(cos(a) * r, 0.6, sin(a) * r)
		if absf(p.z) < 1.4 and absf(p.x) > 3.0:
			p.z = 2.2 * (1.0 if p.z >= 0.0 else -1.0)
		spawns.append(p)
	return {
		"kind": 0, "spawns": spawns, "bot_radius": 7.0, "bot_min_radius": 0.0,
		"cam_radius": 18.0, "cam_height": 12.0,
	}


# ---------------------------------------------------------------------------
# MAP 2: Tile Rush (large) - a big field of crumbling tiles around a solid centre

static func _build_tiles(arena: Node3D) -> Dictionary:
	var cell := 3.2
	var n := 4        # grid -4..4 => 9 x 9
	var center_body := StaticBody3D.new()
	center_body.name = "MainPlatform"
	center_body.collision_layer = 1
	center_body.collision_mask = 0
	var cshape := CollisionShape3D.new()
	var cbox := BoxShape3D.new()
	cbox.size = Vector3(cell * 3.0, 1.0, cell * 3.0)
	cshape.shape = cbox
	cshape.position.y = -0.5
	center_body.add_child(cshape)
	center_body.add_child(Scenery.mesh_instance(Scenery.box(Vector3(cell * 3.0, 1.0, cell * 3.0)), Scenery.mat(Color(1.0, 0.6, 0.2), 0.7), Vector3(0, -0.5, 0)))
	for ix in range(-1, 2):
		for iz in range(-1, 2):
			var c: Color = GameConstants.ARENA_PALETTE[(absi(ix) * 2 + absi(iz) + 1) % GameConstants.ARENA_PALETTE.size()]
			center_body.add_child(Scenery.mesh_instance(Scenery.box(Vector3(cell * 0.94, 0.14, cell * 0.94)), Scenery.mat(c, 0.6), Vector3(float(ix) * cell, 0.0, float(iz) * cell), false))
	arena.add_child(center_body)
	var idx := 0
	for ix in range(-n, n + 1):
		for iz in range(-n, n + 1):
			if absi(ix) <= 1 and absi(iz) <= 1:
				continue
			var tile := TileScene.instantiate()
			tile.name = "Tile%d" % idx
			idx += 1
			tile.configure(Vector3(cell - 0.18, 0.4, cell - 0.18), GameConstants.ARENA_PALETTE[(absi(ix) + absi(iz)) % GameConstants.ARENA_PALETTE.size()])
			tile.position = Vector3(float(ix) * cell, -0.2, float(iz) * cell)
			arena.obstacles_root.add_child(tile)
	_sweeper(arena, Vector3.ZERO, 3.3, 1.35, Color(0.95, 0.27, 0.27), 0.55)
	_sky_decor(arena)
	_balloons(arena, 24.0)
	return {
		"kind": 0, "spawns": _ring_spawns(12, 4.3, TAU / 24.0), "bot_radius": 12.5, "bot_min_radius": 0.0,
		"cam_radius": 30.0, "cam_height": 20.0,
	}


# ---------------------------------------------------------------------------
# MAP 3: Island Hop (medium) - a centre island with four satellite islands reached by shuttle bridges

static func _build_islands(arena: Node3D) -> Dictionary:
	var body := _static_disc(arena, 6.0, Color(0.45, 0.9, 0.3), Color(0.55, 0.4, 0.75))
	body.name = "MainPlatform"
	_checker_tiles(body, 6.0, 2.0)
	_sweeper(arena, Vector3.ZERO, 2.6, 1.7, Color(1.0, 0.56, 0.16), 0.55)
	var island_colors := [Color(1.0, 0.42, 0.72), Color(0.2, 0.85, 0.95), Color(1.0, 0.85, 0.12), Color(0.62, 0.36, 0.95)]
	for i in 4:
		var a := float(i) * TAU / 4.0 + PI / 4.0
		var dir := Vector3(cos(a), 0.0, sin(a))
		var island := Scenery.build_island(arena, dir * 19.0, 3.6, island_colors[i], Color(1.0, 0.6, 0.2), true)
		island.name = "Island%d" % i
		island.add_child(Scenery.mesh_instance(Scenery.cylinder(0.25, 0.3, 3.0, 10), Scenery.mat(Color(1, 1, 1), 0.6), Vector3(0, 1.5, 0)))
		island.add_child(Scenery.mesh_instance(Scenery.sphere(0.5, 12, 6), Scenery.mat(island_colors[i].lightened(0.3), 0.5), Vector3(0, 3.1, 0)))
		var platform := PlatformScene.instantiate()
		platform.name = "Bridge%d" % i
		platform.configure(dir * 7.8 + Vector3(0, -0.25, 0), dir * 15.0 + Vector3(0, -0.25, 0), 5.0 + float(i) * 0.6, Color(0.62, 0.36, 0.95), 0.25 * float(i))
		platform.round_manager = arena.round_manager
		arena.obstacles_root.add_child(platform)
	_sky_decor(arena)
	_balloons(arena, 26.0)
	return {
		"kind": 0, "spawns": _ring_spawns(12, 3.9, TAU / 24.0), "bot_radius": 5.0, "bot_min_radius": 0.0,
		"cam_radius": 26.0, "cam_height": 17.0,
	}


# ---------------------------------------------------------------------------
# MAP 4: Hammer Donut (small) - a ring-shaped track with a void in the middle

static func _build_donut(arena: Node3D) -> Dictionary:
	var mid := 9.0
	var width := 6.0
	var segs := 30
	var body := StaticBody3D.new()
	body.name = "MainPlatform"
	body.collision_layer = 1
	body.collision_mask = 0
	var seg_len := TAU * mid / float(segs) * 1.12
	for i in segs:
		var a := float(i) * TAU / float(segs)
		var pos := Vector3(cos(a) * mid, -0.5, sin(a) * mid)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(width, 1.0, seg_len)
		shape.shape = box
		shape.position = pos
		shape.rotation.y = -a
		body.add_child(shape)
		var c: Color = GameConstants.ARENA_PALETTE[i % GameConstants.ARENA_PALETTE.size()]
		var slab := Scenery.mesh_instance(Scenery.box(Vector3(width, 1.0, seg_len)), Scenery.mat(Color(1.0, 0.6, 0.2), 0.7), pos)
		slab.rotation.y = -a
		body.add_child(slab)
		var top := Scenery.mesh_instance(Scenery.box(Vector3(width - 0.5, 0.14, seg_len * 0.92)), Scenery.mat(c, 0.6), Vector3(pos.x, 0.0, pos.z), false)
		top.rotation.y = -a
		body.add_child(top)
	# Rocky underside ring
	body.add_child(Scenery.mesh_instance(Scenery.cylinder(mid + width * 0.45, mid + width * 0.25, 1.4, 40), Scenery.mat(Color(0.5, 0.35, 0.7), 0.9), Vector3(0, -1.6, 0), false))
	arena.add_child(body)
	_hammer(arena, Vector3(0, 0, mid), 2.4, 1.7, Color(0.95, 0.27, 0.27), 0.0)
	_hammer(arena, Vector3(0, 0, -mid), 2.4, -2.0, Color(0.2, 0.85, 0.95), 1.0)
	# A tall decorative pillar in the void
	arena.decor_root.add_child(Scenery.mesh_instance(Scenery.cylinder(0.6, 1.2, 14.0, 12), Scenery.mat(Color(0.62, 0.36, 0.95), 0.7), Vector3(0, -7.0, 0)))
	_sky_decor(arena)
	_balloons(arena, 19.0)
	var spawns: Array = []
	for deg in [-50, -30, -10, 10, 30, 50, 130, 150, 170, 190, 210, 230]:
		var a := deg_to_rad(float(deg))
		spawns.append(Vector3(cos(a) * mid, 0.6, sin(a) * mid))
	return {
		"kind": 0, "spawns": spawns, "bot_radius": 11.0, "bot_min_radius": 6.8,
		"cam_radius": 22.0, "cam_height": 15.0,
	}


# ---------------------------------------------------------------------------
# HOUSES (hide and seek): a grid of rooms with doorways, furniture and free hiding spots

static func _wall(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.add_child(Scenery.mesh_instance(Scenery.box(size), Scenery.mat(color, 0.85), Vector3.ZERO))
	parent.add_child(body)


## Wall segment along X (horizontal=true) or along Z, optionally with a doorway in the middle.
static func _wall_with_door(parent: Node3D, center: Vector3, length: float, horizontal: bool, door: bool, height: float, thick: float, color: Color) -> void:
	var door_w := 1.9
	var door_h := 2.35
	if not door:
		var size := Vector3(length, height, thick) if horizontal else Vector3(thick, height, length)
		_wall(parent, size, center + Vector3(0, height * 0.5, 0), color)
		return
	var side := (length - door_w) * 0.5
	var off := door_w * 0.5 + side * 0.5
	if horizontal:
		_wall(parent, Vector3(side, height, thick), center + Vector3(-off, height * 0.5, 0), color)
		_wall(parent, Vector3(side, height, thick), center + Vector3(off, height * 0.5, 0), color)
		_wall(parent, Vector3(door_w, height - door_h, thick), center + Vector3(0, door_h + (height - door_h) * 0.5, 0), color)
	else:
		_wall(parent, Vector3(thick, height, side), center + Vector3(0, height * 0.5, -off), color)
		_wall(parent, Vector3(thick, height, side), center + Vector3(0, height * 0.5, off), color)
		_wall(parent, Vector3(thick, height - door_h, door_w), center + Vector3(0, door_h + (height - door_h) * 0.5, 0), color)


# ---------------------------------------------------------------------------
# TRAMPOLINE ARENAS: large spring floor + satellite bounce pads. The floor
# bodies carry a metadata impulse consumed by the owning player's controller.

static func _make_trampoline_surface(parent: Node3D, name_text: String, pos: Vector3,
		radius: float, color: Color, bounce_strength: float, rim_color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name_text
	body.position = pos
	body.collision_layer = GameConstants.LAYER_WORLD
	body.collision_mask = 0
	body.add_to_group("trampoline_surfaces")
	body.set_meta("bounce_strength", bounce_strength)
	var collision := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = 0.48
	collision.shape = cylinder
	collision.position.y = -0.24
	body.add_child(collision)
	body.add_child(Scenery.mesh_instance(Scenery.cylinder(radius, radius, 0.48, 48), Scenery.mat(rim_color, 0.55), Vector3(0, -0.24, 0)))
	body.add_child(Scenery.mesh_instance(Scenery.cylinder(radius - 0.12, radius - 0.12, 0.12, 48), Scenery.mat(color, 0.38), Vector3(0, 0.015, 0), false))
	var center := MeshInstance3D.new()
	var torus := Scenery.torus(radius * 0.72, radius * 0.78, 36, 8)
	center.mesh = torus
	center.material_override = Scenery.mat(Color.WHITE, 0.35, true)
	center.position.y = 0.09
	body.add_child(center)
	parent.add_child(body)
	return body


static func _build_trampoline(arena: Node3D, style: int) -> Dictionary:
	var palettes := [
		[Color(0.12, 0.82, 0.95), Color(0.22, 0.35, 0.92), Color(0.95, 0.36, 0.72)],
		[Color(0.12, 0.95, 0.82), Color(0.16, 0.18, 0.42), Color(0.72, 0.28, 1.0)],
		[Color(1.0, 0.48, 0.72), Color(0.55, 0.28, 0.92), Color(1.0, 0.82, 0.22)],
		[Color(0.42, 0.92, 0.55), Color(0.18, 0.55, 0.95), Color(0.95, 0.78, 0.3)],
		[Color(1.0, 0.48, 0.2), Color(0.24, 0.22, 0.42), Color(0.25, 0.88, 0.95)],
	]
	var palette: Array = palettes[posmod(style, palettes.size())]
	var main_radius: float = [12.0, 11.0, 12.8, 11.8, 10.8][posmod(style, 5)]
	var bounce: float = [15.5, 16.5, 15.0, 17.0, 17.5][posmod(style, 5)]
	_make_trampoline_surface(arena, "MainTrampoline", Vector3.ZERO, main_radius, palette[0], bounce, palette[1])

	# Five secondary pads create risky routes and aerial combat opportunities.
	var pad_count := 5 if style == 4 else 4
	for i in pad_count:
		var angle := TAU * float(i) / float(pad_count) + float(style) * 0.19
		var radius: float = main_radius + 5.2 + (1.0 if style == 3 and i % 2 == 0 else 0.0)
		var pad_pos := Vector3(cos(angle) * radius, -0.35, sin(angle) * radius)
		var pad_radius := 2.6 if style != 4 else 2.9
		_make_trampoline_surface(arena, "SpringPad%d" % i, pad_pos, pad_radius, palette[2] if i % 2 == 0 else palette[0], bounce + 1.0, palette[1])
		var pillar := MeshInstance3D.new()
		pillar.mesh = Scenery.cylinder(0.35, 0.55, 5.0, 12)
		pillar.material_override = Scenery.mat(palette[1].darkened(0.18), 0.7)
		pillar.position = pad_pos + Vector3(0, -3.0, 0)
		arena.decor_root.add_child(pillar)

	# Floating decorative hoops frame the arena without adding physics load.
	for i in 3:
		var hoop := MeshInstance3D.new()
		var torus := Scenery.torus(15.0 + float(i) * 2.0, 15.18 + float(i) * 2.0, 48, 8)
		hoop.mesh = torus
		hoop.material_override = Scenery.mat(palette[i % palette.size()], 0.45, true, 0.62)
		hoop.position = Vector3(0, 8.0 + float(i) * 2.1, 0)
		hoop.rotation.x = deg_to_rad(70.0 + float(i) * 12.0)
		arena.decor_root.add_child(hoop)

	_sky_decor(arena)
	_balloons(arena, 28.0)
	return {
		"kind": 2,
		"spawns": _ring_spawns(12, minf(main_radius * 0.58, 7.0), TAU / 24.0, 0.65),
		"bot_radius": main_radius - 1.0,
		"bot_min_radius": 0.0,
		"cam_radius": main_radius * 2.7,
		"cam_height": 25.0,
	}

## School: one long open corridor with eight purpose-specific rooms, rather
## than the house generator's maze. Collision and bot graph share the doors.
static func _build_school(arena: Node3D) -> Dictionary:
	var school := Node3D.new()
	school.name = "School"
	arena.add_child(school)
	var wall_color := Color(0.94, 0.88, 0.70)
	var floor := StaticBody3D.new()
	floor.name = "SchoolFloor"
	floor.collision_layer = 1
	floor.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(32.0, 1.0, 24.0)
	floor_shape.shape = floor_box
	floor_shape.position.y = -0.5
	floor.add_child(floor_shape)
	floor.add_child(Scenery.mesh_instance(Scenery.box(Vector3(32, 1, 24)), Scenery.mat(Color(0.70, 0.77, 0.70), 0.9), Vector3(0, -0.5, 0), false))
	school.add_child(floor)
	# Four boundary walls and classroom partitions. The corridor stays open.
	_wall_with_door(school, Vector3(0, 0, -12), 32.3, true, false, 3.2, 0.3, wall_color)
	_wall_with_door(school, Vector3(0, 0, 12), 32.3, true, false, 3.2, 0.3, wall_color)
	_wall_with_door(school, Vector3(-16, 0, 0), 24.3, false, false, 3.2, 0.3, wall_color)
	_wall_with_door(school, Vector3(16, 0, 0), 24.3, false, false, 3.2, 0.3, wall_color)
	for x in [-8.0, 0.0, 8.0]:
		_wall_with_door(school, Vector3(x, 0, -8), 8.0, false, false, 3.2, 0.3, wall_color)
		_wall_with_door(school, Vector3(x, 0, 8), 8.0, false, false, 3.2, 0.3, wall_color)
	var rooms: Array = []
	var graph: Dictionary = {}
	# Intermediate corridor waypoints prevent diagonal paths clipping door frames.
	for col in 4:
		var cx := -12.0 + float(col) * 8.0
		rooms.append({"center": Vector3(cx, 0.6, 0), "type": "corridor", "spots": []})
		graph[col] = []
	for col in 3:
		var crossing := Vector3(-8.0 + float(col) * 8.0, 0.6, 0)
		graph[col].append({"to": col + 1, "door": crossing})
		graph[col + 1].append({"to": col, "door": crossing})
	var hider_spawns: Array = []
	var kinds := ["classroom", "classroom", "library", "office", "cafeteria", "art", "storage", "classroom"]
	var palettes := [Color(0.65, 0.82, 0.73), Color(0.72, 0.81, 0.91), Color(0.76, 0.67, 0.56), Color(0.83, 0.77, 0.64), Color(0.95, 0.78, 0.56), Color(0.79, 0.69, 0.88), Color(0.65, 0.68, 0.69), Color(0.72, 0.83, 0.71)]
	# Existing recognizable props preserve the disguise game's visual language.
	var furniture := [[17, 1], [17, 10], [10, 10], [17, 11], [3, 7], [3, 13], [15, 15], [17, 1]]
	for row in 2:
		var z := -8.0 if row == 0 else 8.0
		var door_z := -4.0 if row == 0 else 4.0
		for col in 4:
			var n := row * 4 + col
			var x := -12.0 + float(col) * 8.0
			var center := Vector3(x, 0.6, z)
			var door := Vector3(x, 0.6, door_z)
			_wall_with_door(school, Vector3(x, 0, door_z), 8.0, true, true, 3.2, 0.3, wall_color)
			school.add_child(Scenery.mesh_instance(Scenery.box(Vector3(7.7, 0.05, 7.7)), Scenery.mat(palettes[n], 0.9), Vector3(x, 0.025, z), false))
			# A chalkboard gives classrooms and the art room a visible identity.
			# It is visual-only and stays clear of the playable paths.
			if kinds[n] == "classroom" or kinds[n] == "art":
				var board_z := z + (-3.82 if row == 0 else 3.82)
				school.add_child(Scenery.mesh_instance(Scenery.box(Vector3(3.2, 1.1, 0.06)), Scenery.mat(Color(0.12, 0.28, 0.23), 0.9), Vector3(x, 1.9, board_z), false))
			# Two corners contain furniture, the other two are unobstructed hiding spots.
			_place_furniture(school, furniture[n][0], Vector3(x - 2.25, 0, z - 2.25), 0.0)
			_place_furniture(school, furniture[n][1], Vector3(x + 2.25, 0, z - 2.25), 0.0)
			var spots := [Vector3(x - 2.25, 0.6, z + 2.0), Vector3(x + 2.25, 0.6, z + 2.0)]
			var idx := rooms.size()
			rooms.append({"center": center, "type": kinds[n], "spots": spots})
			graph[idx] = [{"to": col, "door": door}]
			graph[col].append({"to": idx, "door": door})
			hider_spawns.append(spots[0])
			hider_spawns.append(spots[1])
			# Coloured board above the doorway marks each kind of room without extra collision.
			if not _is_low_quality():
				school.add_child(Scenery.mesh_instance(Scenery.box(Vector3(2.0, 0.35, 0.06)), Scenery.mat(palettes[n].darkened(0.35), 0.8), Vector3(x, 2.65, door_z + (0.17 if row == 0 else -0.17)), false))
	var seeker_spawns: Array = []
	for i in 8:
		seeker_spawns.append(Vector3(-2.1 + float(i % 4) * 1.4, 0.6, -0.8 + float(i / 4) * 1.6))
	Scenery.build_cloud_field(arena.decor_root, 4 if _is_low_quality() else 12, 40.0, 90.0, 18.0, 30.0, 1801)
	return {"kind": 1, "spawns": hider_spawns, "spawn_groups": [hider_spawns, seeker_spawns], "rooms": rooms, "graph": graph, "bot_radius": 0.0, "bot_min_radius": 0.0, "cam_radius": 30.0, "cam_height": 24.0}


static func _build_house(arena: Node3D, cols: int, rows: int, rw: float, rd: float, seed_value: int, style: int = 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var house := Node3D.new()
	house.name = "House"
	arena.add_child(house)
	var total_w := float(cols) * rw
	var total_d := float(rows) * rd
	var origin := Vector3(-total_w * 0.5, 0.0, -total_d * 0.5)
	var wall_h := 3.2
	var thick := 0.3
	var wall_palette := [Color(0.97, 0.88, 0.76), Color(0.78, 0.86, 0.94), Color(0.95, 0.88, 0.62), Color(0.58, 0.62, 0.66), Color(0.83, 0.78, 0.93)]
	var wall_color: Color = wall_palette[clampi(style, 0, 4)]

	# Hand-authored topology families, always connected. Each theme has different
	# door placement; graph entries below use these same doors for bot pathing.
	var room_count := cols * rows
	var door_h: Dictionary = {}
	var door_v: Dictionary = {}
	if style == 0 or style == 3:
		# Open rows with alternating cross-links; warehouse gets extra passages.
		for z in rows:
			for x in range(cols - 1):
				_open_door(door_h, door_v, Vector2i(x, z), Vector2i(x + 1, z))
		for z in range(rows - 1):
			var x := (cols - 1) if z % 2 == 0 else 0
			_open_door(door_h, door_v, Vector2i(x, z), Vector2i(x, z + 1))
			if style == 3:
				_open_door(door_h, door_v, Vector2i(cols / 2, z), Vector2i(cols / 2, z + 1))
	else:
		# Open columns, linked by a central spine. The school has extra links;
		# the museum alternates links to produce a different gallery circuit.
		for x in cols:
			for z in range(rows - 1):
				_open_door(door_h, door_v, Vector2i(x, z), Vector2i(x, z + 1))
		for x in range(cols - 1):
			var z := 0 if style == 1 else (x % rows if style == 4 else rows / 2)
			_open_door(door_h, door_v, Vector2i(x, z), Vector2i(x + 1, z))
			if style == 2 and x % 2 == 0:
				_open_door(door_h, door_v, Vector2i(x, 0), Vector2i(x + 1, 0))

	# ---- Room types (room 0 is the entrance hall where the seekers wait)
	var type_cycle := ["living", "bedroom", "kitchen", "bathroom", "office", "bedroom", "storage", "living", "bathroom", "kitchen", "bedroom", "office"]
	if style == 1:
		type_cycle = ["living", "kitchen", "bathroom", "bedroom", "office", "bedroom"]
	elif style == 2:
		type_cycle = ["office", "office", "office", "storage", "office", "bathroom", "office", "living"]
	elif style == 3:
		type_cycle = ["storage", "storage", "office", "storage", "storage", "storage", "bathroom"]
	elif style == 4:
		type_cycle = ["living", "living", "office", "storage", "living", "office", "living"]
	var floor_colors := {
		"living": Color(0.86, 0.72, 0.5), "bedroom": Color(0.72, 0.62, 0.86), "kitchen": Color(0.9, 0.9, 0.78),
		"bathroom": Color(0.6, 0.85, 0.92), "office": Color(0.7, 0.82, 0.66), "storage": Color(0.78, 0.7, 0.62),
	}

	# ---- Ground + floors
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	ground.collision_mask = 0
	var gshape := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(total_w + 40.0, 1.0, total_d + 40.0)
	gshape.shape = gbox
	gshape.position.y = -0.55
	ground.add_child(gshape)
	ground.add_child(Scenery.mesh_instance(Scenery.box(Vector3(total_w + 40.0, 1.0, total_d + 40.0)), Scenery.mat(Color(0.45, 0.78, 0.38), 0.95), Vector3(0, -0.55, 0), false))
	house.add_child(ground)

	var rooms: Array = []
	var graph: Dictionary = {}
	var ri := 0
	for rz in rows:
		for rx in cols:
			var center := origin + Vector3((float(rx) + 0.5) * rw, 0.0, (float(rz) + 0.5) * rd)
			var rtype: String = str(type_cycle[ri % type_cycle.size()])
			var fcol: Color = floor_colors[rtype]
			if style == 2:
				fcol = Color(0.76, 0.84, 0.72) if ri % 2 == 0 else Color(0.87, 0.80, 0.62)
			elif style == 3:
				fcol = Color(0.48, 0.53, 0.58) if ri % 2 == 0 else Color(0.64, 0.58, 0.46)
			elif style == 4:
				fcol = Color(0.76, 0.65, 0.82) if ri % 2 == 0 else Color(0.85, 0.73, 0.59)
			house.add_child(Scenery.mesh_instance(Scenery.box(Vector3(rw - 0.1, 0.06, rd - 0.1)), Scenery.mat(fcol, 0.8), center + Vector3(0, 0.0, 0), false))
			# Rug in the middle
			house.add_child(Scenery.mesh_instance(Scenery.box(Vector3(rw * 0.35, 0.02, rd * 0.35)), Scenery.mat(fcol.darkened(0.2), 0.95), center + Vector3(0, 0.04, 0), false))
			rooms.append({"center": center + Vector3(0, 0.6, 0), "type": rtype, "spots": [], "x": rx, "z": rz})
			graph[ri] = []
			ri += 1

	# ---- Walls: outer frame
	for rx in cols:
		var cx := origin.x + (float(rx) + 0.5) * rw
		_wall_with_door(house, Vector3(cx, 0, origin.z), rw + thick, true, false, wall_h, thick, wall_color)
		_wall_with_door(house, Vector3(cx, 0, origin.z + total_d), rw + thick, true, false, wall_h, thick, wall_color)
	for rz in rows:
		var cz := origin.z + (float(rz) + 0.5) * rd
		_wall_with_door(house, Vector3(origin.x, 0, cz), rd + thick, false, false, wall_h, thick, wall_color)
		_wall_with_door(house, Vector3(origin.x + total_w, 0, cz), rd + thick, false, false, wall_h, thick, wall_color)

	# ---- Walls: inner edges (east and south edge of every room) + navigation graph
	for rz in rows:
		for rx in cols:
			var idx := rz * cols + rx
			var rc: Vector3 = rooms[idx]["center"]
			if rx < cols - 1:
				var has_door := door_h.has("%d,%d" % [rx, rz])
				var wc := Vector3(rc.x + rw * 0.5, 0, rc.z)
				_wall_with_door(house, wc, rd + thick, false, has_door, wall_h, thick, wall_color)
				if has_door:
					var other := rz * cols + rx + 1
					graph[idx].append({"to": other, "door": Vector3(wc.x, 0.6, wc.z)})
					graph[other].append({"to": idx, "door": Vector3(wc.x, 0.6, wc.z)})
			if rz < rows - 1:
				var has_door2 := door_v.has("%d,%d" % [rx, rz])
				var wc2 := Vector3(rc.x, 0, rc.z + rd * 0.5)
				_wall_with_door(house, wc2, rw + thick, true, has_door2, wall_h, thick, wall_color)
				if has_door2:
					var other2 := (rz + 1) * cols + rx
					graph[idx].append({"to": other2, "door": Vector3(wc2.x, 0.6, wc2.z)})
					graph[other2].append({"to": idx, "door": Vector3(wc2.x, 0.6, wc2.z)})

	# ---- Furniture and free hiding spots (never on the cross-shaped walking lanes)
	for i in rooms.size():
		var room: Dictionary = rooms[i]
		var rc2: Vector3 = room["center"]
		var rtype2: String = room["type"]
		var inset_x := rw * 0.5 - 1.55
		var inset_z := rd * 0.5 - 1.55
		var slots: Array = [
			Vector3(-inset_x, 0, -inset_z), Vector3(inset_x, 0, -inset_z),
			Vector3(-inset_x, 0, inset_z), Vector3(inset_x, 0, inset_z),
		]
		# Edge-middle slots only where the edge has no doorway.
		var rx2: int = room["x"]
		var rz2: int = room["z"]
		if rz2 == 0 or not door_v.has("%d,%d" % [rx2, rz2 - 1]):
			slots.append(Vector3(0, 0, -(rd * 0.5 - 0.95)))
		if rz2 == rows - 1 or not door_v.has("%d,%d" % [rx2, rz2]):
			slots.append(Vector3(0, 0, rd * 0.5 - 0.95))
		if rx2 == 0 or not door_h.has("%d,%d" % [rx2 - 1, rz2]):
			slots.append(Vector3(-(rw * 0.5 - 0.95), 0, 0))
		if rx2 == cols - 1 or not door_h.has("%d,%d" % [rx2, rz2]):
			slots.append(Vector3(rw * 0.5 - 0.95, 0, 0))
		# shuffle slots deterministically
		for s in range(slots.size() - 1, 0, -1):
			var j := rng.randi() % (s + 1)
			var tmp: Vector3 = slots[s]
			slots[s] = slots[j]
			slots[j] = tmp
		var set_ids: Array = PropsLib.ROOM_SETS[rtype2]
		if style == 2 and rtype2 == "office":
			set_ids = [17, 1, 10, 17, 1, 15]
		elif style == 3 and rtype2 == "storage":
			set_ids = [15, 15, 15, 10, 16, 14]
		elif style == 4 and rtype2 == "living":
			set_ids = [10, 13, 12, 3, 15, 1]
		var furniture_count := mini(set_ids.size() - 1, maxi(slots.size() - 2, 1))
		if i == 0:
			furniture_count = mini(furniture_count, 2)   # entrance hall stays roomy
		var spots: Array = []
		for s in slots.size():
			var local: Vector3 = slots[s]
			var wpos := Vector3(rc2.x + local.x, 0.0, rc2.z + local.z)
			if s < furniture_count:
				var pid := int(set_ids[(s + rng.randi() % 3) % set_ids.size()])
				_place_furniture(house, pid, wpos, atan2(local.x, local.z))
			else:
				spots.append(Vector3(wpos.x, 0.6, wpos.z))
		room["spots"] = spots

	# ---- Spawns: hiders spread over the rooms (not the entrance hall), seekers wait in room 0
	var hider_spawns: Array = []
	var round_robin := 0
	while hider_spawns.size() < 14:
		var ridx := 1 + (round_robin % maxi(rooms.size() - 1, 1))
		var spots_here: Array = rooms[ridx]["spots"]
		var pick := round_robin / maxi(rooms.size() - 1, 1)
		if spots_here.size() > 0:
			hider_spawns.append(spots_here[pick % spots_here.size()])
		else:
			var rcx: Vector3 = rooms[ridx]["center"]
			hider_spawns.append(rcx + Vector3(float(pick) * 0.9 - 1.0, 0, 0))
		round_robin += 1
		if round_robin > 80:
			break
	var seeker_spawns: Array = []
	var hall: Vector3 = rooms[0]["center"]
	for i in 12:
		seeker_spawns.append(hall + Vector3(-1.4 + float(i % 4) * 0.95, 0.0, -0.9 + float(i / 4) * 0.95))

	# ---- Outside decoration: fence posts and trees (visual only)
	var tree_count := 3 if _is_low_quality() else 10
	for t in tree_count:
		var ang := float(t) * TAU / float(tree_count)
		var tr := maxf(total_w, total_d) * 0.5 + 9.0
		var tp := Vector3(cos(ang) * tr, 0, sin(ang) * tr)
		arena.decor_root.add_child(Scenery.mesh_instance(Scenery.cylinder(0.3, 0.4, 3.0, 8), Scenery.mat(Color(0.5, 0.33, 0.2), 0.9), tp + Vector3(0, 1.5, 0)))
		arena.decor_root.add_child(Scenery.mesh_instance(Scenery.sphere(2.2, 12, 6), Scenery.mat(Color(0.3, 0.72, 0.35), 0.8), tp + Vector3(0, 4.2, 0)))
	Scenery.build_cloud_field(arena.decor_root, 4 if _is_low_quality() else 14, 40.0, 90.0, 18.0, 30.0, 321)

	var cam_r := maxf(total_w, total_d) * 0.75 + 6.0
	return {
		"kind": 1, "spawns": hider_spawns, "spawn_groups": [hider_spawns, seeker_spawns],
		"rooms": rooms, "graph": graph, "bot_radius": 0.0, "bot_min_radius": 0.0,
		"cam_radius": cam_r, "cam_height": cam_r * 0.8,
	}


static func _open_door(door_h: Dictionary, door_v: Dictionary, a: Vector2i, b: Vector2i) -> void:
	if a.y == b.y:
		var left := a if a.x < b.x else b
		door_h["%d,%d" % [left.x, left.y]] = true
	else:
		var top := a if a.y < b.y else b
		door_v["%d,%d" % [top.x, top.y]] = true


static func _place_furniture(parent: Node3D, pid: int, pos: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	body.rotation.y = yaw
	var size := PropsLib.size_of(pid)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = Vector3(0, size.y * 0.5, 0)
	body.add_child(shape)
	body.add_child(PropsLib.build(pid))
	parent.add_child(body)


## Shortest list of waypoints between two rooms (BFS over the door graph).
static func plan_path(graph: Dictionary, rooms: Array, from_room: int, to_room: int) -> Array:
	if from_room == to_room:
		return [rooms[to_room]["center"]]
	var prev: Dictionary = {from_room: -1}
	var via: Dictionary = {}
	var queue: Array = [from_room]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		if cur == to_room:
			break
		for edge in graph.get(cur, []):
			var nb: int = int(edge["to"])
			if prev.has(nb):
				continue
			prev[nb] = cur
			via[nb] = edge["door"]
			queue.append(nb)
	if not prev.has(to_room):
		return [rooms[to_room]["center"]]
	var rev: Array = []
	var node := to_room
	while node != from_room:
		rev.append(rooms[node]["center"])
		rev.append(via[node])
		node = int(prev[node])
	rev.reverse()
	return rev


## Index of the room that contains a world position.
static func room_at(rooms: Array, pos: Vector3, rw: float, rd: float) -> int:
	var best := 0
	var best_d := INF
	for i in rooms.size():
		var c: Vector3 = rooms[i]["center"]
		var d := Vector2(c.x - pos.x, c.z - pos.z).length()
		if d < best_d:
			best_d = d
			best = i
	return best
