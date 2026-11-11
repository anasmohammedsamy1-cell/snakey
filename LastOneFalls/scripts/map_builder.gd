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
const BumperScript := preload("res://scripts/obstacles/bumper.gd")
const ArenaLayerScript := preload("res://scripts/obstacles/arena_layer.gd")
const FloorZoneScript := preload("res://scripts/obstacles/floor_zone.gd")

## Floor tier ratios for the tiered arenas: each entry is the outer radius of the next tier,
## as a fraction of the full radius. The last tier left is the solid core.
const TIER_RATIOS := [0.80, 0.60, 0.42]
const TIER_RATIOS_SMALL := [0.75, 0.55]
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
const MAP_FAMILY_FLAT := 16
const MAP_PLAZA := 17
const MAP_MINI_TILES := 18
const MAP_SPLIT_RING := 19
const MAP_ICE_RINK := 20
const MAP_CONVEYOR_MILL := 21
const MAP_WIND_TUNNEL := 22

const HOUSE_WALL_H := 5.0     # tall rooms: jumping never touches the ceiling and the camera has room


static func build(map_id: int, arena: Node3D) -> Dictionary:
	var info := {}
	match map_id:
		MAP_TWISTER:
			info = _build_twister(arena)
		MAP_RING:
			info = _build_ring(arena)
		MAP_TILES:
			info = _build_tiles(arena)
		MAP_ISLANDS:
			info = _build_islands(arena)
		MAP_DONUT:
			info = _build_donut(arena)
		MAP_VILLA:
			info = _build_house(arena, 4, 3, 9.5, 9.5, 7771, 0)
		MAP_FLAT:
			info = _build_house(arena, 3, 2, 9.0, 9.0, 4242, 1)
		MAP_FAMILY_FLAT:
			info = _build_house(arena, 4, 2, 9.5, 9.5, 5151, 5)
		MAP_PLAZA:
			info = _build_plaza(arena)
		MAP_MINI_TILES:
			info = _build_mini_tiles(arena)
		MAP_SPLIT_RING:
			info = _build_split_ring(arena)
		MAP_ICE_RINK:
			info = _build_ice_rink(arena)
		MAP_CONVEYOR_MILL:
			info = _build_conveyor_mill(arena)
		MAP_WIND_TUNNEL:
			info = _build_wind_tunnel(arena)
		MAP_SCHOOL:
			info = _build_school(arena)
		MAP_WAREHOUSE:
			info = _build_house(arena, 3, 3, 10.0, 10.0, 1802, 3)
		MAP_MUSEUM:
			info = _build_house(arena, 4, 2, 10.0, 10.0, 1803, 4)
		MAP_BOUNCE_DOME:
			info = _build_trampoline(arena, 0)
		MAP_NEON_SPRINGS:
			info = _build_trampoline(arena, 1)
		MAP_CANDY_CLOUD:
			info = _build_trampoline(arena, 2)
		MAP_SKY_BOUNCE:
			info = _build_trampoline(arena, 3)
		MAP_PINBALL_BOUNCE:
			info = _build_trampoline(arena, 4)
		_:
			info = _build_cloud(arena)
	# One final pass over the whole arena: batches walls, furniture, decor pieces,
	# trampoline pads, hoops, lamp pools and everything else that is static.
	# Per-tier passes already collapsed the floor rings; those MMIs are not
	# MeshInstance3D and are skipped here. Scripted subtrees (obstacles, zones,
	# players) are never touched.
	_batch_meshes(arena)
	return info


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


## ---------------------------------------------------------------------------
## Tiered floors (Sudden Death)
## The floor of an arena is built from concentric tiers instead of one solid disc, so Sudden Death
## can drop the outer tier, then the next, and the survivors are really pushed together.
## Nothing overlaps: each tier owns its own ring of collision segments plus its own checker tiles,
## so there is no coplanar ridge under the players' feet.
## Returns {"outer", "middle", "inner", "all"} (all = outer -> inner).
static func _tiered_disc(arena: Node3D, radius: float, color: Color, side: Color, cell := 2.0,
		ratios: Array = TIER_RATIOS) -> Dictionary:
	var bounds: Array = [radius]
	for r in ratios:
		bounds.append(radius * float(r))
	var seg_count := 24 if radius >= 12.0 else (20 if radius >= 8.0 else 16)
	var tiers: Array = []
	for i in bounds.size():
		var r_out := float(bounds[i])
		var r_in := 0.0
		if i + 1 < bounds.size():
			r_in = float(bounds[i + 1])
		var tier := _make_tier(arena, i, i + 1 < bounds.size())
		var plate: Color = color.darkened(0.06 * float(i))
		if r_in <= 0.05:
			# Solid core: a single cylinder, so no seams under the last survivors.
			var cshape := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = r_out
			cyl.height = 1.0
			cshape.shape = cyl
			cshape.position.y = -0.5
			tier.add_child(cshape)
			tier.add_child(Scenery.mesh_instance(Scenery.cylinder(r_out, r_out - 0.3, 1.0, 40),
				Scenery.mat(plate, 0.7), Vector3(0, -0.5, 0)))
		else:
			# Ring tier: short slabs around the circle (same trick the donut map uses).
			var width := r_out - r_in
			var mid := (r_out + r_in) * 0.5
			var seg_len := TAU * mid / float(seg_count) * 1.14
			for k in seg_count:
				var a := float(k) * TAU / float(seg_count)
				var pos := Vector3(cos(a) * mid, 0.0, sin(a) * mid)
				var shape := CollisionShape3D.new()
				var box := BoxShape3D.new()
				box.size = Vector3(width, 1.0, seg_len)
				shape.shape = box
				shape.position = pos + Vector3(0, -0.5, 0)
				shape.rotation.y = -a
				tier.add_child(shape)
				var slab := Scenery.mesh_instance(Scenery.box(Vector3(width, 1.0, seg_len)),
					Scenery.mat(plate, 0.7), pos + Vector3(0, -0.5, 0))
				slab.rotation.y = -a
				tier.add_child(slab)
		if cell > 0.0:
			_checker_tiles(tier, r_out, cell, r_in)
		tiers.append(tier)

	var outer: Node3D = tiers[0]
	# Classic floating-island underside + white rim live on the outer tier, so they break away with it.
	outer.add_child(Scenery.mesh_instance(Scenery.cylinder(radius - 0.4, radius * 0.18, radius * 0.55, 24),
		Scenery.mat(side, 0.9), Vector3(0, -1.0 - radius * 0.275, 0)))
	var rim := MeshInstance3D.new()
	rim.mesh = Scenery.torus(radius - 0.4, radius + 0.1, 48, 8)
	rim.material_override = Scenery.mat(Color(1, 1, 1), 0.5)
	rim.position.y = -0.05
	outer.add_child(rim)
	# Ring slabs of each tier share one cached mesh + material: collapse them into
	# MultiMesh instances. MMIs are parented to their own tier, so Sudden Death
	# still drops them exactly as before.
	for t in tiers:
		_batch_meshes(t)
	return {
		"outer": outer,
		"middle": tiers[mini(1, tiers.size() - 1)],
		"inner": tiers[tiers.size() - 1],
		"all": tiers,
		"radii": bounds,
	}


## `drops` false builds the solid core: a plain StaticBody3D that Sudden Death can never remove,
## so there is always a small island left to fight on.
static func _make_tier(arena: Node3D, index: int, drops: bool) -> Node3D:
	var tier := StaticBody3D.new()
	if drops:
		tier.set_script(ArenaLayerScript)
		tier.set("layer_index", index)
	tier.name = "FloorTier%d" % index
	tier.position = Vector3.ZERO
	arena.obstacles_root.add_child(tier)
	return tier


## Tier whose annulus contains `r` (used to parent obstacles so they fall with their own floor).
static func _tier_at(tiers: Dictionary, r: float) -> Node3D:
	var list: Array = tiers.get("all", [])
	var radii: Array = tiers.get("radii", [])
	for i in list.size():
		if i + 1 >= radii.size():
			return list[i]
		if r >= float(radii[i + 1]):
			return list[i]
	return list[list.size() - 1]


## Square floor built from three nested tiers (the plaza).
static func _tiered_box(arena: Node3D, half: float, color: Color, side: Color,
		ratios: Array = [0.70, 0.46]) -> Dictionary:
	var bounds: Array = [half]
	for r in ratios:
		bounds.append(half * float(r))
	var tiers: Array = []
	for i in bounds.size():
		var outer_h := float(bounds[i])
		var inner_h := 0.0
		if i + 1 < bounds.size():
			inner_h = float(bounds[i + 1])
		var tier := _make_tier(arena, i, i + 1 < bounds.size())
		var plate: Color = color.darkened(0.05 * float(i))
		if inner_h <= 0.05:
			tier.add_child(_slab_shape(Vector3(outer_h * 2.0, 1.0, outer_h * 2.0), Vector3(0, -0.5, 0)))
			tier.add_child(Scenery.mesh_instance(Scenery.box(Vector3(outer_h * 2.0, 1.0, outer_h * 2.0)),
				Scenery.mat(plate, 0.7), Vector3(0, -0.5, 0), false))
			tier.add_child(_quarter_plates(outer_h, 0.0))
		else:
			var band := outer_h - inner_h
			var mid := (outer_h + inner_h) * 0.5
			var strips := [
				{"size": Vector3(outer_h * 2.0, 1.0, band), "pos": Vector3(0, -0.5, mid)},
				{"size": Vector3(outer_h * 2.0, 1.0, band), "pos": Vector3(0, -0.5, -mid)},
				{"size": Vector3(band, 1.0, inner_h * 2.0), "pos": Vector3(mid, -0.5, 0)},
				{"size": Vector3(band, 1.0, inner_h * 2.0), "pos": Vector3(-mid, -0.5, 0)},
			]
			# One calm colour per tier band: the four bright quarters stay on the core only,
			# so the plaza reads as "three rings" instead of a patchwork of colours.
			var top_color: Color = plate.lightened(0.14 - 0.05 * float(i))
			for st in strips:
				var size: Vector3 = st["size"]
				var pos: Vector3 = st["pos"]
				tier.add_child(_slab_shape(size, pos))
				tier.add_child(Scenery.mesh_instance(Scenery.box(size), Scenery.mat(plate, 0.7), pos, false))
				var top := Scenery.mesh_instance(Scenery.box(Vector3(size.x - 0.25, 0.14, size.z - 0.25)),
					Scenery.floor_mat(top_color, 0.6), pos + Vector3(0, 0.5, 0), false)
				tier.add_child(top)
		tiers.append(tier)
	var outer_tier: Node3D = tiers[0]
	outer_tier.add_child(Scenery.mesh_instance(Scenery.cylinder(half * 0.98, half * 0.3, half * 0.5, 32),
		Scenery.mat(side, 0.9), Vector3(0, -1.0 - half * 0.25, 0), false))
	for t in tiers:
		_batch_meshes(t)
	return {"outer": outer_tier, "middle": tiers[mini(1, tiers.size() - 1)],
		"inner": tiers[tiers.size() - 1], "all": tiers, "radii": bounds}


static func _slab_shape(size: Vector3, pos: Vector3) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	return shape


## Four coloured quarter plates that give the plaza its look (visual only).
static func _quarter_plates(half: float, y: float) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Quarters"
	var qi := 0
	for qx in [-1.0, 1.0]:
		for qz in [-1.0, 1.0]:
			var c: Color = GameConstants.ARENA_PALETTE[qi % GameConstants.ARENA_PALETTE.size()]
			holder.add_child(Scenery.mesh_instance(Scenery.box(Vector3(half - 0.3, 0.12, half - 0.3)),
				Scenery.floor_mat(c, 0.6), Vector3(qx * half * 0.5, y, qz * half * 0.5), false))
			qi += 1
	return holder


## Solid bouncy posts. Parented to the floor tier they stand on, so they fall away with it.
static func _bumpers(parent: Node3D, positions: Array, color: Color) -> void:
	for bp in positions:
		var bumper := Node3D.new()
		bumper.set_script(BumperScript)
		bumper.name = "Bumper%d" % parent.get_child_count()
		bumper.set("color", color)
		bumper.position = bp
		parent.add_child(bumper)


static func _checker_tiles(parent: Node3D, radius: float, cell: float, r_min := 0.0) -> void:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var tile := BoxMesh.new()
	tile.size = Vector3(cell * 0.95, 0.16, cell * 0.95)
	# Tier top tiles: procedural detail on MEDIUM / HIGH (vertex colours keep the
	# checker pattern), plain flat material on LOW.
	var tmat := Scenery.floor_mat(Color.WHITE, 0.65, cell)
	if tmat is StandardMaterial3D:
		tmat = Scenery.dup_material(tmat)
		var std := tmat as StandardMaterial3D
		std.vertex_color_use_as_albedo = true
		std.rim_enabled = not _is_low_quality()
		std.rim = 0.2 if not _is_low_quality() else 0.0
	tile.material = tmat
	mm.mesh = tile
	var transforms: Array = []
	var colors: Array = []
	var n := int(ceil(radius / cell)) + 1
	for ix in range(-n, n + 1):
		for iz in range(-n, n + 1):
			var pos := Vector3(float(ix) * cell, -0.06, float(iz) * cell)
			var d := Vector2(pos.x, pos.z).length()
			# Each floor tier draws only its own annulus, so the checkerboard stays continuous
			# across the seams and each tier's tiles fall away with that tier.
			if d < r_min or d >= radius:
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


static func _sweeper(arena: Node3D, pos: Vector3, arm: float, speed: float, color: Color, height := 0.55,
		parent: Node3D = null) -> void:
	var s := HammerScene.instantiate()
	s.configure(arm, speed, height, color, true, 0.0, Vector3(1.2, 0.5, 0.8))
	s.pole_height = 2.2
	s.knockback = 9.0
	s.round_manager = arena.round_manager
	s.position = pos
	var host: Node3D = parent if parent != null else arena.obstacles_root
	host.add_child(s)


static func _hammer(arena: Node3D, pos: Vector3, arm: float, speed: float, color: Color, phase := 0.0,
		parent: Node3D = null) -> void:
	var h := HammerScene.instantiate()
	h.configure(arm, speed, 1.0, color, false, phase)
	h.round_manager = arena.round_manager
	h.position = pos
	var host: Node3D = parent if parent != null else arena.obstacles_root
	host.add_child(h)


static func _crumble_ring(arena: Node3D, count: int, radius: float, tile_size: Vector3,
		parent: Node3D = null) -> void:
	var host: Node3D = parent if parent != null else arena.obstacles_root
	for i in count:
		var a := float(i) * TAU / float(count)
		var tile := TileScene.instantiate()
		tile.name = "RingTile%d" % i
		tile.configure(tile_size, GameConstants.ARENA_PALETTE[i % GameConstants.ARENA_PALETTE.size()])
		tile.position = Vector3(cos(a) * radius, -0.2, sin(a) * radius)
		tile.rotation.y = -a
		host.add_child(tile)


static func _is_low_quality() -> bool:
	# LOW and POTATO share the weak-device paths; POTATO adds its own reductions.
	return int(SettingsManager.get_setting("graphics_preset")) in [SettingsManager.PRESET_LOW, SettingsManager.PRESET_POTATO]


const _BATCH_MIN_INSTANCES := 2

## Merge static MeshInstance3D under `root` into MultiMeshInstance3D groups.
## Guarantees:
##  - subtrees with a script are never touched, so moving obstacles (hammers,
##    sweepers, falling tiles, FloorZones) and anything spawned later (players)
##    keep their individual transforms;
##  - collision (CollisionShape3D / StaticBody3D bodies) is never touched;
##  - groups are keyed on (mesh resource, material resource, cast_shadow,
##    visibility range): only identical geometry+material collapses;
##  - groups of 1 stay individual.
## Multi-surface meshes stay individual (their materials are per-surface; the
## checker tiles already batch themselves via _checker_tiles()).
static func _batch_meshes(root: Node3D) -> void:
	var groups: Dictionary = {}
	_collect_batch(root, Transform3D.IDENTITY, true, groups)
	var idx := 0
	for key in groups:
		var entries: Array = groups[key]
		if entries.size() < _BATCH_MIN_INSTANCES:
			continue
		var first: MeshInstance3D = entries[0]["mi"]
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Batch%d" % idx
		idx += 1
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = first.mesh
		mm.instance_count = entries.size()
		var i := 0
		for e in entries:
			var mi := e["mi"] as MeshInstance3D
			mm.set_instance_transform(i, e["xform"])
			i += 1
		mmi.multimesh = mm
		var mat: Material = first.material_override
		if mat == null and first.mesh.surface_get_material_count() > 0:
			mat = first.mesh.surface_get_material(0)
		mmi.material_override = mat
		mmi.cast_shadow = first.cast_shadow
		mmi.visibility_range_begin = first.visibility_range_begin
		mmi.visibility_range_end = first.visibility_range_end
		mmi.visibility_range_begin_margin = first.visibility_range_begin_margin
		mmi.visibility_range_end_margin = first.visibility_range_end_margin
		root.add_child(mmi)
		for e in entries:
			var mi := e["mi"] as MeshInstance3D
			mi.get_parent().remove_child(mi)
			mi.free()


static var _pool_mat: StandardMaterial3D

## Shared lamp pool material: flat warm light with additive blend. One instance
## for every lamp pool in every map - pools batch into a MultiMesh instead of
## one unique material each. Appearance is identical to the previous per-lamp dup.
static func _lamp_pool_mat() -> StandardMaterial3D:
	if _pool_mat == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.9, 0.55, 0.16)
		m.roughness = 1.0
		m.metallic = 0.0
		m.metallic_specular = 0.35
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_pool_mat = m
	return _pool_mat


static func _collect_batch(node: Node, parent_xform: Transform3D, is_root: bool, groups: Dictionary) -> void:
	# A scripted node means a dynamic subtree (obstacles, floor zones, players):
	# leave every visual child alone.
	if not is_root and node.get_script() != null:
		return
	var xform := parent_xform
	if not is_root and node is Node3D:
		xform = parent_xform * (node as Node3D).transform
	if node is MeshInstance3D:
		_add_batch_candidate(node as MeshInstance3D, xform, groups)
		return
	for child in node.get_children():
		_collect_batch(child, xform, false, groups)


static func _add_batch_candidate(mi: MeshInstance3D, xform: Transform3D, groups: Dictionary) -> void:
	var mesh := mi.mesh
	if mesh == null:
		return
	if mesh.get_surface_count() != 1:
		return   # multi-surface meshes stay individual
	var mat: Material = mi.material_override
	if mat == null and mesh.surface_get_material_count() > 0:
		mat = mesh.surface_get_material(0)
	if mat == null:
		return
	var key := "%d|%d|%d|%s|%s" % [mesh.get_instance_id(), mat.get_instance_id(), int(mi.cast_shadow),
		"%.4f" % mi.visibility_range_begin, "%.4f" % mi.visibility_range_end]
	if not groups.has(key):
		groups[key] = []
	groups[key].append({"mi": mi, "xform": xform})


static func _sky_decor(arena: Node3D, sea_y := -30.0) -> void:
	if int(SettingsManager.get_setting("graphics_preset")) == SettingsManager.PRESET_POTATO:
		# Weakest: one tiny cloud field + the cloud sea only (no second field, no islands).
		Scenery.build_cloud_field(arena.decor_root, 2, 28.0, 70.0, -14.0, -4.0, 4242)
		Scenery.build_cloud_sea(arena.decor_root, sea_y, 160.0)
		return
	if _is_low_quality():
		# Weak phones: one small cloud field + the cloud sea only (no far islands, no second field).
		Scenery.build_cloud_field(arena.decor_root, 3, 28.0, 70.0, -14.0, -4.0, 4242)
		Scenery.build_cloud_sea(arena.decor_root, sea_y, 160.0)
		return
	Scenery.build_cloud_field(arena.decor_root, 14, 28.0, 70.0, -14.0, -4.0, 4242)
	Scenery.build_cloud_field(arena.decor_root, 5, 40.0, 90.0, 8.0, 20.0, 777)
	Scenery.build_cloud_sea(arena.decor_root, sea_y, 160.0)
	Scenery.build_distant_islands(arena.decor_root)


static func _balloons(arena: Node3D, ring_radius: float) -> void:
	if _is_low_quality():
		return
	var balloon_colors := [Color(1.0, 0.42, 0.72), Color(1.0, 0.85, 0.12), Color(0.2, 0.85, 0.95), Color(0.45, 0.9, 0.3)]
	for i in 3:
		var a := float(i) * TAU / 3.0 + 0.3
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
	var tiers := _tiered_disc(arena, radius, Color(1.0, 0.6, 0.2), Color(0.5, 0.35, 0.7), 2.0)
	var core: Node3D = tiers["inner"]
	core.add_child(Scenery.mesh_instance(Scenery.cylinder(1.6, 1.6, 0.2, 32), Scenery.mat(Color(1, 1, 1), 0.5), Vector3(0, -0.05, 0)))

	# The centre sweeper lives on the solid core, so it survives until the very end.
	var sweeper := HammerScene.instantiate()
	sweeper.name = "CenterSweeper"
	sweeper.configure(4.0, 1.05, 0.55, Color(1.0, 0.56, 0.16), true, 0.0, Vector3(1.2, 0.5, 0.8))
	sweeper.pole_height = 2.2
	sweeper.knockback = 9.0
	sweeper.round_manager = arena.round_manager
	core.add_child(sweeper)

	# The three hammers stand on the tier that holds radius 9: they fall away with that floor.
	var hammer_tier := _tier_at(tiers, 9.0)
	var speeds := [1.3, -1.6, 1.9]
	var colors := [Color(0.95, 0.27, 0.27), Color(0.62, 0.36, 0.95), Color(0.2, 0.85, 0.95)]
	for i in 3:
		var a := float(i) * TAU / 3.0 + PI / 2.0
		var hammer := HammerScene.instantiate()
		hammer.name = "Hammer%d" % i
		hammer.configure(3.0, speeds[i], 1.0, colors[i], false, float(i) * 2.1)
		hammer.round_manager = arena.round_manager
		hammer.position = Vector3(cos(a) * 9.0, 0.0, sin(a) * 9.0)
		hammer_tier.add_child(hammer)

	_crumble_ring(arena, 32, 14.5, Vector3(2.75, 0.4, 2.8), tiers["outer"])

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
		"kind": 0, "spawns": _ring_spawns(12, 5.2, TAU / 24.0), "bot_radius": 7.2, "bot_min_radius": 0.0,
		"cam_radius": 24.0, "cam_height": 15.0, "shrinkable": true,
	}


# ---------------------------------------------------------------------------
# MAP 1: Mini Ring (small) - one tight platform, a fast sweeper, crumbling rim

# MAP 12: Twister Arena — safe central spawns and opposing sweepers.
static func _build_twister(arena: Node3D) -> Dictionary:
	var radius := 14.0
	var tiers := _tiered_disc(arena, radius, Color(0.18, 0.72, 0.72), Color(0.22, 0.27, 0.56), 2.0)
	var core: Node3D = tiers["inner"]
	var mid_tier := _tier_at(tiers, 6.0)
	var outer_tier := _tier_at(tiers, 10.0)
	_sweeper(arena, Vector3(-6.0, 0, 0), 3.2, 1.1, Color(1.0, 0.38, 0.23), 0.55, mid_tier)
	_sweeper(arena, Vector3(6.0, 0, 0), 3.2, -1.1, Color(0.62, 0.36, 0.95), 0.55, mid_tier)
	_hammer(arena, Vector3(0, 0, 10.0), 2.0, 1.3, Color(1.0, 0.8, 0.2), 0.0, outer_tier)
	_hammer(arena, Vector3(0, 0, -10.0), 2.0, -1.3, Color(1.0, 0.8, 0.2), 1.5, outer_tier)
	# Two solid bumper posts on the middle tier: they bounce players toward the sweepers.
	_bumpers(mid_tier, [Vector3(0, 0, 4.4), Vector3(0, 0, -4.4)], Color(0.2, 0.85, 0.95))
	_crumble_ring(arena, 28, 15.5, Vector3(2.9, 0.4, 2.9), tiers["outer"])
	_sky_decor(arena)
	_balloons(arena, 21.0)
	return {
		"kind": 0, "spawns": _ring_spawns(12, 3.0, TAU / 24.0), "bot_radius": 8.0, "bot_min_radius": 0.0,
		"cam_radius": 25.0, "cam_height": 16.0, "shrinkable": true,
	}


static func _build_ring(arena: Node3D) -> Dictionary:
	var radius := 8.0
	var tiers := _tiered_disc(arena, radius, Color(0.2, 0.75, 0.9), Color(0.35, 0.3, 0.6), 2.0, TIER_RATIOS_SMALL)
	var core: Node3D = tiers["inner"]
	var mid_tier := _tier_at(tiers, 5.6)
	_sweeper(arena, Vector3.ZERO, 3.2, 1.5, Color(1.0, 0.45, 0.2), 0.55, core)
	_hammer(arena, Vector3(5.6, 0, 0), 1.9, -1.8, Color(0.95, 0.27, 0.27), 0.0, mid_tier)
	_hammer(arena, Vector3(-5.6, 0, 0), 1.9, 1.8, Color(0.62, 0.36, 0.95), 1.5, mid_tier)
	_crumble_ring(arena, 22, 9.6, Vector3(2.9, 0.4, 2.9), tiers["outer"])
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
		"kind": 0, "spawns": spawns, "bot_radius": 5.2, "bot_min_radius": 0.0,
		"cam_radius": 18.0, "cam_height": 12.0, "shrinkable": true,
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
			center_body.add_child(Scenery.mesh_instance(Scenery.box(Vector3(cell * 0.94, 0.14, cell * 0.94)), Scenery.floor_mat(c, 0.6), Vector3(float(ix) * cell, 0.0, float(iz) * cell), false))
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
		"cam_radius": 30.0, "cam_height": 20.0, "shrinkable": true,
	}


# ---------------------------------------------------------------------------
# MAP 3: Island Hop (medium) - a centre island with four satellite islands reached by shuttle bridges

static func _build_islands(arena: Node3D) -> Dictionary:
	var tiers := _tiered_disc(arena, 6.0, Color(0.45, 0.9, 0.3), Color(0.55, 0.4, 0.75), 2.0, TIER_RATIOS_SMALL)
	var core: Node3D = tiers["inner"]
	_sweeper(arena, Vector3.ZERO, 2.6, 1.7, Color(1.0, 0.56, 0.16), 0.55, core)
	# Four bumper posts guard the way to the bridges: the middle island squeezes the fight.
	_bumpers(_tier_at(tiers, 4.4), [Vector3(2.6, 0, 2.6), Vector3(-2.6, 0, 2.6),
		Vector3(2.6, 0, -2.6), Vector3(-2.6, 0, -2.6)], Color(1.0, 0.42, 0.72))
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
		"kind": 0, "spawns": _ring_spawns(12, 3.9, TAU / 24.0), "bot_radius": 4.2, "bot_min_radius": 0.0,
		"cam_radius": 26.0, "cam_height": 17.0, "shrinkable": true,
	}


# ---------------------------------------------------------------------------
# MAP 4: Hammer Donut (small) - a ring-shaped track with a void in the middle

static func _build_donut(arena: Node3D) -> Dictionary:
	var mid := 9.0
	var width := 6.0
	var segs := 24
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
		var top := Scenery.mesh_instance(Scenery.box(Vector3(width - 0.5, 0.14, seg_len * 0.92)), Scenery.floor_mat(c, 0.6), Vector3(pos.x, 0.0, pos.z), false)
		top.rotation.y = -a
		body.add_child(top)
	# Rocky underside ring
	body.add_child(Scenery.mesh_instance(Scenery.cylinder(mid + width * 0.45, mid + width * 0.25, 1.4, 40), Scenery.mat(Color(0.5, 0.35, 0.7), 0.9), Vector3(0, -1.6, 0), false))
	_batch_meshes(body)   # the 24 identical ring segments share one cached mesh + per-slab palette material
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
	var door_w := 2.4
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
	_wall_with_door(school, Vector3(0, 0, -12), 32.3, true, false, HOUSE_WALL_H, 0.3, wall_color)
	_wall_with_door(school, Vector3(0, 0, 12), 32.3, true, false, HOUSE_WALL_H, 0.3, wall_color)
	_wall_with_door(school, Vector3(-16, 0, 0), 24.3, false, false, HOUSE_WALL_H, 0.3, wall_color)
	_wall_with_door(school, Vector3(16, 0, 0), 24.3, false, false, HOUSE_WALL_H, 0.3, wall_color)
	for x in [-8.0, 0.0, 8.0]:
		_wall_with_door(school, Vector3(x, 0, -8), 8.0, false, false, HOUSE_WALL_H, 0.3, wall_color)
		_wall_with_door(school, Vector3(x, 0, 8), 8.0, false, false, HOUSE_WALL_H, 0.3, wall_color)
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
			_wall_with_door(school, Vector3(x, 0, door_z), 8.0, true, true, HOUSE_WALL_H, 0.3, wall_color)
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
	# Sealed like the houses: ceiling + one lamp per corridor section and classroom.
	_build_ceiling(school, 32.0, 24.0, Vector3(-16.0, 0.0, -12.0), HOUSE_WALL_H, 0.3, wall_color)
	for lamp_room in rooms:
		_build_lamp(school, lamp_room["center"], HOUSE_WALL_H, 8.0, 8.0)
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
	var wall_h := HOUSE_WALL_H
	var thick := 0.3
	var wall_palette := [Color(0.97, 0.88, 0.76), Color(0.78, 0.86, 0.94), Color(0.95, 0.88, 0.62), Color(0.58, 0.62, 0.66), Color(0.83, 0.78, 0.93), Color(0.99, 0.93, 0.82)]
	var wall_color: Color = wall_palette[clampi(style, 0, 5)]

	# Hand-authored topology families, always connected. Each theme has different
	# door placement; graph entries below use these same doors for bot pathing.
	var room_count := cols * rows
	var door_h: Dictionary = {}
	var door_v: Dictionary = {}
	if style == 5:
		# Real family flat: top row hall - living - kitchen - bathroom, bottom row bedrooms + storage.
		_open_door(door_h, door_v, Vector2i(0, 0), Vector2i(1, 0))
		_open_door(door_h, door_v, Vector2i(1, 0), Vector2i(2, 0))
		_open_door(door_h, door_v, Vector2i(2, 0), Vector2i(3, 0))
		_open_door(door_h, door_v, Vector2i(0, 0), Vector2i(0, 1))
		_open_door(door_h, door_v, Vector2i(1, 0), Vector2i(1, 1))
		_open_door(door_h, door_v, Vector2i(3, 0), Vector2i(3, 1))
		_open_door(door_h, door_v, Vector2i(1, 1), Vector2i(2, 1))
	elif style == 0 or style == 3:
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
	if style == 5:
		type_cycle = ["living", "living", "kitchen", "bathroom", "bedroom", "bedroom", "bedroom", "storage"]
	elif style == 1:
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

	# ---- Closed apartment: solid ceiling (nobody can leave, camera stays inside) + one lamp per room
	_build_ceiling(house, total_w, total_d, origin, wall_h, thick, wall_color)
	for lamp_room in rooms:
		_build_lamp(house, lamp_room["center"], wall_h, rw, rd)

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
		var furniture_count := mini(set_ids.size() - 1, maxi(slots.size() - 3, 1))
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
		# One hiding alcove (a screen with a side gap) in a free corner of rooms big enough for it.
		if i > 0 and rw >= 8.0 and rd >= 8.0:
			for s2 in range(furniture_count, slots.size()):
				var cl: Vector3 = slots[s2]
				if absf(absf(cl.x) - inset_x) < 0.01 and absf(absf(cl.z) - inset_z) < 0.01:
					var nook_spot := _build_nook(house, rc2, cl, rw, rd, wall_color.darkened(0.12))
					for q in range(spots.size() - 1, -1, -1):
						var sp: Vector3 = spots[q]
						if absf(sp.x - nook_spot.x) < 0.01 and absf(sp.z - nook_spot.z) < 0.01:
							spots.remove_at(q)
					spots.push_front(nook_spot)       # hiders spawn inside the alcove first
					break
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

	# The apartment is sealed, so there is no outside scenery to draw (lighter on weak devices).

	var cam_r := maxf(total_w, total_d) * 0.75 + 6.0
	return {
		"kind": 1, "spawns": hider_spawns, "spawn_groups": [hider_spawns, seeker_spawns],
		"rooms": rooms, "graph": graph, "bot_radius": 0.0, "bot_min_radius": 0.0,
		"cam_radius": cam_r, "cam_height": cam_r * 0.8,
	}


## Sealed ceiling. The collider blocks players and the spring-arm camera; the visible quad faces DOWN only,
## so it is seen from inside but is invisible from the spectator camera above (back-face culled).
static func _build_ceiling(parent: Node3D, total_w: float, total_d: float, origin: Vector3, wall_h: float, thick: float, color: Color) -> void:
	var cx := origin.x + total_w * 0.5
	var cz := origin.z + total_d * 0.5
	var body := StaticBody3D.new()
	body.name = "Ceiling"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(total_w + thick * 2.0, 0.6, total_d + thick * 2.0)
	shape.shape = box
	shape.position = Vector3(cx, wall_h + 0.3, cz)
	body.add_child(shape)
	var plane := PlaneMesh.new()
	plane.size = Vector2(total_w + thick, total_d + thick)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = Scenery.mat(color.lightened(0.25), 0.95, true)
	mi.position = Vector3(cx, wall_h, cz)
	mi.rotation.x = PI          # flip so the visible side points down into the rooms
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	parent.add_child(body)


## Cheap lamp: cord + shade + glowing bulb + soft light pool on the floor. No real light nodes (weak phones).
static func _build_lamp(parent: Node3D, room_center: Vector3, wall_h: float, rw: float, rd: float) -> void:
	var x := room_center.x
	var z := room_center.z
	var cord_len := 0.5
	parent.add_child(Scenery.mesh_instance(Scenery.cylinder(0.02, 0.02, cord_len, 4), Scenery.mat(Color(0.2, 0.2, 0.22), 0.9, true), Vector3(x, wall_h - cord_len * 0.5, z), false))
	parent.add_child(Scenery.mesh_instance(Scenery.cylinder(0.08, 0.34, 0.22, 10), Scenery.mat(Color(0.95, 0.85, 0.55), 0.8, true), Vector3(x, wall_h - cord_len - 0.08, z), false))
	parent.add_child(Scenery.mesh_instance(Scenery.sphere(0.13, 8, 4), Scenery.mat(Color(1.0, 0.96, 0.7), 0.5, true), Vector3(x, wall_h - cord_len - 0.26, z), false))
	parent.add_child(Scenery.mesh_instance(Scenery.cylinder(minf(rw, rd) * 0.42, minf(rw, rd) * 0.42, 0.01, 20), _lamp_pool_mat(), Vector3(x, 0.075, z), false))


## Alcove in a room corner: a screen parallel to the wall + a short side screen, 1 m gap beside the wall.
## Returns the spawn / hiding position inside the alcove.
static func _build_nook(parent: Node3D, room_center: Vector3, corner: Vector3, rw: float, rd: float, color: Color) -> Vector3:
	var sx := signf(corner.x)
	var sz := signf(corner.z)
	var h := 2.4
	var x_wall := sx * (rw * 0.5 - 0.15)
	var x_in := sx * (rw * 0.5 - 2.85)
	var z_front := sz * (rd * 0.5 - 2.45)
	var front_len := absf(x_wall - x_in)
	_wall(parent, Vector3(front_len, h, 0.15), Vector3(room_center.x + (x_wall + x_in) * 0.5, h * 0.5, room_center.z + z_front), color)
	var side_len := 1.3
	_wall(parent, Vector3(0.15, h, side_len), Vector3(room_center.x + x_in, h * 0.5, room_center.z + z_front + sz * side_len * 0.5), color)
	return Vector3(room_center.x + corner.x, 0.6, room_center.z + corner.z)


# ---------------------------------------------------------------------------
# LIGHT FALL MAPS (weak devices): few nodes, no clouds, small size

static func _light_decor(arena: Node3D) -> void:
	Scenery.build_cloud_field(arena.decor_root, 3, 28.0, 70.0, -14.0, -4.0, 909)
	Scenery.build_cloud_sea(arena.decor_root, -30.0, 120.0)


## MAP 17 Plaza: one square slab with four coloured quarters and a central sweeper.
static func _build_plaza(arena: Node3D) -> Dictionary:
	var half := 10.0
	var tiers := _tiered_box(arena, half, Color(1.0, 0.6, 0.2), Color(0.5, 0.35, 0.7))
	var core: Node3D = tiers["inner"]
	var mid_tier := _tier_at(tiers, 6.5)
	_sweeper(arena, Vector3.ZERO, 3.6, 1.4, Color(0.95, 0.27, 0.27), 0.55, core)
	# Four solid bumper posts on the middle tier: they block the way and bounce players
	# back toward the sweeper, and they fall away with their own floor plate.
	_bumpers(mid_tier, [Vector3(4.6, 0, 4.6), Vector3(-4.6, 0, 4.6), Vector3(4.6, 0, -4.6), Vector3(-4.6, 0, -4.6)],
		Color(1.0, 0.42, 0.72))
	_light_decor(arena)
	return {
		"kind": 0, "spawns": _ring_spawns(12, 4.4, TAU / 24.0), "bot_radius": 6.0, "bot_min_radius": 0.0,
		"cam_radius": 20.0, "cam_height": 14.0, "shrinkable": true,
	}


## MAP 18 Mini Tiles: 5 x 5 crumbling tiles (the 9 x 9 map is heavy on weak phones).
static func _build_mini_tiles(arena: Node3D) -> Dictionary:
	var cell := 3.4
	var idx := 0
	for ix in range(-2, 3):
		for iz in range(-2, 3):
			var tile := TileScene.instantiate()
			tile.name = "Tile%d" % idx
			idx += 1
			tile.configure(Vector3(cell - 0.18, 0.4, cell - 0.18), GameConstants.ARENA_PALETTE[(absi(ix) + absi(iz)) % GameConstants.ARENA_PALETTE.size()])
			tile.position = Vector3(float(ix) * cell, -0.2, float(iz) * cell)
			arena.obstacles_root.add_child(tile)
	_light_decor(arena)
	return {
		"kind": 0, "spawns": _ring_spawns(8, 4.2, TAU / 16.0), "bot_radius": 6.0, "bot_min_radius": 0.0,
		"cam_radius": 18.0, "cam_height": 13.0, "shrinkable": true,
	}


## MAP 19 Split Ring: a small disc with a sweeper and a hammer.
static func _build_split_ring(arena: Node3D) -> Dictionary:
	var radius := 8.0
	var tiers := _tiered_disc(arena, radius, Color(0.2, 0.85, 0.95), Color(0.22, 0.27, 0.56), 2.0, TIER_RATIOS_SMALL)
	var core: Node3D = tiers["inner"]
	var mid_tier := _tier_at(tiers, 5.2)
	_sweeper(arena, Vector3.ZERO, 3.2, 1.5, Color(0.95, 0.27, 0.27), 0.55, core)
	_hammer(arena, Vector3(0, 0, 5.2), 1.8, -2.0, Color(0.62, 0.36, 0.95), 0.5, mid_tier)
	_bumpers(mid_tier, [Vector3(-4.6, 0, -2.6), Vector3(4.6, 0, -2.6)], Color(0.95, 0.27, 0.27))
	_light_decor(arena)
	return {
		"kind": 0, "spawns": _ring_spawns(10, 5.0, TAU / 20.0), "bot_radius": 5.2, "bot_min_radius": 0.0,
		"cam_radius": 18.0, "cam_height": 13.0, "shrinkable": true,
	}


## Floor hazard (obstacles/floor_zone.gd). kind: 0 conveyor, 1 ice, 2 fan. yaw_deg turns the local +X (belt / wind direction).
static func _zone(arena: Node3D, parent: Node3D, kind: int, pos: Vector3, yaw_deg: float, size: Vector2,
		strength := 3.0, color := Color(0.25, 0.27, 0.33), phase := 0.0) -> Node3D:
	var z := Node3D.new()
	z.set_script(FloorZoneScript)
	z.name = "Zone%d" % parent.get_child_count()
	z.set("kind", kind)
	z.set("size", size)
	z.set("strength", strength)
	z.set("color", color)
	z.set("phase", phase)
	z.set("round_manager", arena.round_manager)
	z.position = pos
	z.rotation_degrees.y = yaw_deg
	parent.add_child(z)
	return z


## MAP 20 Ice Rink: a small disc whose middle is ice (slow to start, slow to stop) with a sweeper on top.
static func _build_ice_rink(arena: Node3D) -> Dictionary:
	var radius := 9.0
	var tiers := _tiered_disc(arena, radius, Color(0.78, 0.93, 1.0), Color(0.25, 0.4, 0.7), 2.0, TIER_RATIOS_SMALL)
	var core: Node3D = tiers["inner"]
	var mid_tier := _tier_at(tiers, 5.8)
	_zone(arena, core, 1, Vector3.ZERO, 0.0, Vector2(6.4, 6.4))
	_sweeper(arena, Vector3.ZERO, 3.0, 1.3, Color(0.95, 0.27, 0.27), 0.55, core)
	_bumpers(mid_tier, [Vector3(0, 0, 5.85), Vector3(5.07, 0, -2.92), Vector3(-5.07, 0, -2.92)], Color(0.3, 0.75, 1.0))
	_light_decor(arena)
	return {
		"kind": 0, "spawns": _ring_spawns(8, 4.0, TAU / 16.0), "bot_radius": 5.4, "bot_min_radius": 0.0,
		"cam_radius": 19.0, "cam_height": 13.0, "shrinkable": true,
	}


## MAP 21 Conveyor Mill: four belts run clockwise around a central platform (the middle tier ring).
static func _build_conveyor_mill(arena: Node3D) -> Dictionary:
	var half := 10.0
	var tiers := _tiered_box(arena, half, Color(0.55, 0.6, 0.7), Color(0.3, 0.3, 0.45))
	var core: Node3D = tiers["inner"]
	var mid_tier := _tier_at(tiers, 5.5)
	var belt := Vector2(8.6, 2.6)
	var col := Color(0.22, 0.24, 0.3)
	_zone(arena, mid_tier, 0, Vector3(0, 0, -5.5), 0.0, belt, 3.4, col)      # north side, runs east
	_zone(arena, mid_tier, 0, Vector3(5.5, 0, 0), -90.0, belt, 3.4, col)     # east side, runs south
	_zone(arena, mid_tier, 0, Vector3(0, 0, 5.5), 180.0, belt, 3.4, col)     # south side, runs west
	_zone(arena, mid_tier, 0, Vector3(-5.5, 0, 0), 90.0, belt, 3.4, col)     # west side, runs north
	_sweeper(arena, Vector3.ZERO, 3.0, 1.4, Color(0.95, 0.27, 0.27), 0.55, core)
	_light_decor(arena)
	return {
		"kind": 0, "spawns": _ring_spawns(8, 3.8, TAU / 16.0), "bot_radius": 6.5, "bot_min_radius": 0.0,
		"cam_radius": 20.0, "cam_height": 14.0, "shrinkable": true,
	}


## MAP 22 Wind Tunnel: four fans on the rim blow across the disc in a pinwheel, in pulses.
static func _build_wind_tunnel(arena: Node3D) -> Dictionary:
	var radius := 9.5
	var tiers := _tiered_disc(arena, radius, Color(0.5, 0.85, 0.7), Color(0.2, 0.4, 0.45))
	var core: Node3D = tiers["inner"]
	var outer := _tier_at(tiers, 8.6)
	_hammer(arena, Vector3.ZERO, 2.2, 1.6, Color(0.95, 0.27, 0.27), 0.0, core)
	_zone(arena, outer, 2, Vector3(-8.3, 0, -3.8), 0.0, Vector2(13.0, 4.2), 5.2, Color.WHITE, 0.0)     # blows east
	_zone(arena, outer, 2, Vector3(3.8, 0, -8.3), -90.0, Vector2(13.0, 4.2), 5.2, Color.WHITE, 1.0)    # blows south
	_zone(arena, outer, 2, Vector3(8.3, 0, 3.8), 180.0, Vector2(13.0, 4.2), 5.2, Color.WHITE, 2.0)     # blows west
	_zone(arena, outer, 2, Vector3(-3.8, 0, 8.3), 90.0, Vector2(13.0, 4.2), 5.2, Color.WHITE, 3.0)     # blows north
	_light_decor(arena)
	var spawns: Array = []
	for i in 8:
		var a := float(i) * TAU / 8.0 + TAU / 16.0
		spawns.append(Vector3(cos(a) * 4.8, 0.6, sin(a) * 4.8))
	return {
		"kind": 0, "spawns": spawns, "bot_radius": 6.5, "bot_min_radius": 0.0,
		"cam_radius": 21.0, "cam_height": 15.0, "shrinkable": true,
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
