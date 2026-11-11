extends RefCounted
## Shared 3D scenery builders (sky, sun, clouds, islands) used by the arena,
## the main menu background and the customisation preview.
## Everything is built from Godot primitive meshes: no external models required.
## Usage: const Scenery := preload("res://scripts/scenery.gd")

const FLOOR_DETAIL_SHADER := preload("res://assets/shaders/floor_detail.gdshader")


# ---------------------------------------------------------------------------
# Shared resource cache. Identical procedural materials / meshes are built once
# and reused; callers that need to tweak a property use dup_material() (or dup
# inside the build call) to get their own mutable copy. Bounded: when a cache
# fills, it is cleared wholesale - cached values are cheap and re-derivable.
const RESOURCE_CACHE_LIMIT := 512

static var _mat_cache: Dictionary = {}
static var _floor_cache: Dictionary = {}
static var _mesh_cache: Dictionary = {}
static var _res_stats := {
	"mat_hits": 0, "mat_misses": 0,
	"floor_hits": 0, "floor_misses": 0,
	"mesh_hits": 0, "mesh_misses": 0,
	"duplicates": 0, "evictions": 0,
}


static func _f3(v: float) -> String:
	return "%.4f" % v


static func _color_key(color: Color) -> String:
	return "%s,%s,%s,%s" % [_f3(color.r), _f3(color.g), _f3(color.b), _f3(color.a)]


static func _cache_put(cache: Dictionary, key: String, value: Resource) -> void:
	if cache.size() >= RESOURCE_CACHE_LIMIT:
		cache.clear()               # bounded growth; entries re-derive on demand
		_res_stats["evictions"] = int(_res_stats["evictions"]) + 1
	cache[key] = value


## Returns an independent, mutable copy of a shared material. Tracked for the
## debug statistics ("duplicates").
static func dup_material(m: Material) -> Material:
	_res_stats["duplicates"] = int(_res_stats["duplicates"]) + 1
	return m.duplicate()


## Debug statistics snapshot for the resource caches (does not reset).
static func cache_stats() -> Dictionary:
	return {
		"mat_hits": int(_res_stats["mat_hits"]), "mat_misses": int(_res_stats["mat_misses"]),
		"mat_cache_size": _mat_cache.size(),
		"floor_hits": int(_res_stats["floor_hits"]), "floor_misses": int(_res_stats["floor_misses"]),
		"floor_cache_size": _floor_cache.size(),
		"mesh_hits": int(_res_stats["mesh_hits"]), "mesh_misses": int(_res_stats["mesh_misses"]),
		"mesh_cache_size": _mesh_cache.size(),
		"duplicates": int(_res_stats["duplicates"]), "evictions": int(_res_stats["evictions"]),
		"limit": RESOURCE_CACHE_LIMIT,
	}


static func mat(color: Color, roughness := 0.75, unshaded := false, alpha := 1.0) -> StandardMaterial3D:
	var rim_enabled := not _potato()
	var key := "%s|%s|%d|%s|%d" % [_color_key(color), _f3(roughness), 1 if unshaded else 0, _f3(alpha), int(rim_enabled)]
	var cached: StandardMaterial3D = _mat_cache.get(key) as StandardMaterial3D
	if cached != null:
		_res_stats["mat_hits"] = int(_res_stats["mat_hits"]) + 1
		return cached
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.roughness = roughness
	m.metallic = 0.0
	m.metallic_specular = 0.35
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		if rim_enabled:
			# Soft cartoon rim light: makes every shape pop and look less flat.
			m.rim_enabled = true
			m.rim = 0.28
			m.rim_tint = 0.55
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cache_put(_mat_cache, key, m)
	_res_stats["mat_misses"] = int(_res_stats["mat_misses"]) + 1
	return m


## Procedural floor / tile material: soft checker + thin darker seams + a
## noise-free gradient, all computed in the shader (no texture lookups).
## MEDIUM / HIGH get the detail; LOW / POTATO keep the plain flat material.
static func floor_mat(color: Color, roughness := 0.7, cell_size := 1.5) -> Material:
	if _low_quality():
		return mat(color, roughness)   # plain flat material on LOW / POTATO (cached there)
	# MEDIUM and HIGH share the same shader settings: one shared cache entry.
	var key := "floor|%s|%s|%s" % [_color_key(color), _f3(roughness), _f3(cell_size)]
	var cached: Material = _floor_cache.get(key) as Material
	if cached != null:
		_res_stats["floor_hits"] = int(_res_stats["floor_hits"]) + 1
		return cached
	var m := ShaderMaterial.new()
	m.shader = FLOOR_DETAIL_SHADER
	m.set_shader_parameter("base_color", Color(color.r, color.g, color.b, color.a))
	m.set_shader_parameter("roughness", roughness)
	m.set_shader_parameter("cell_size", cell_size)
	_cache_put(_floor_cache, key, m)
	_res_stats["floor_misses"] = int(_res_stats["floor_misses"]) + 1
	return m


static func _low_quality() -> bool:
	return SettingsManager != null and int(SettingsManager.get_setting("graphics_preset")) in [SettingsManager.PRESET_LOW, SettingsManager.PRESET_POTATO]


## POTATO is even cheaper than LOW: it reads the same weak-device paths plus
## its own extra reductions (detail factor, cloud puffs, sky decor).
static func _potato() -> bool:
	return SettingsManager != null and int(SettingsManager.get_setting("graphics_preset")) == SettingsManager.PRESET_POTATO


static func _detail_factor() -> float:
	# Four distinct geometry tiers: Potato .35x, Low .5x, Medium .75x, High 1x.
	if SettingsManager == null:
		return 0.75
	match int(SettingsManager.get_setting("graphics_preset")):
		SettingsManager.PRESET_LOW:
			return 0.5
		SettingsManager.PRESET_HIGH:
			return 1.0
		SettingsManager.PRESET_POTATO:
			return 0.35
		_:
			return 0.75


## Scale primitive mesh detail for weak devices without changing gameplay/collision shapes.
static func detail_segments(requested: int, minimum := 4) -> int:
	return maxi(minimum, int(round(float(requested) * _detail_factor())))


static func detail_rings(requested: int, minimum := 3) -> int:
	return maxi(minimum, int(round(float(requested) * _detail_factor())))


static func mesh_instance(mesh: Mesh, material: Material, pos := Vector3.ZERO, cast_shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	if not cast_shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func sphere(radius: float, segments := 16, rings := 8) -> SphereMesh:
	var segs := detail_segments(segments)
	var rgs := detail_rings(rings)
	var key := "sphere|%s|%d|%d" % [_f3(radius), segs, rgs]
	var cached: SphereMesh = _mesh_cache.get(key) as SphereMesh
	if cached != null:
		_res_stats["mesh_hits"] = int(_res_stats["mesh_hits"]) + 1
		return cached
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = segs
	s.rings = rgs
	_cache_put(_mesh_cache, key, s)
	_res_stats["mesh_misses"] = int(_res_stats["mesh_misses"]) + 1
	return s


static func box(size: Vector3) -> BoxMesh:
	var key := "box|%s,%s,%s" % [_f3(size.x), _f3(size.y), _f3(size.z)]
	var cached: BoxMesh = _mesh_cache.get(key) as BoxMesh
	if cached != null:
		_res_stats["mesh_hits"] = int(_res_stats["mesh_hits"]) + 1
		return cached
	var b := BoxMesh.new()
	b.size = size
	_cache_put(_mesh_cache, key, b)
	_res_stats["mesh_misses"] = int(_res_stats["mesh_misses"]) + 1
	return b


static func cylinder(top: float, bottom: float, height: float, segments := 24) -> CylinderMesh:
	var segs := detail_segments(segments)
	var key := "cyl|%s|%s|%s|%d" % [_f3(top), _f3(bottom), _f3(height), segs]
	var cached: CylinderMesh = _mesh_cache.get(key) as CylinderMesh
	if cached != null:
		_res_stats["mesh_hits"] = int(_res_stats["mesh_hits"]) + 1
		return cached
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = segs
	_cache_put(_mesh_cache, key, c)
	_res_stats["mesh_misses"] = int(_res_stats["mesh_misses"]) + 1
	return c


static func capsule(radius: float, height: float) -> CapsuleMesh:
	var segs := detail_segments(16)
	var rgs := detail_rings(6)
	var key := "cap|%s|%s|%d|%d" % [_f3(radius), _f3(height), segs, rgs]
	var cached: CapsuleMesh = _mesh_cache.get(key) as CapsuleMesh
	if cached != null:
		_res_stats["mesh_hits"] = int(_res_stats["mesh_hits"]) + 1
		return cached
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = height
	c.radial_segments = segs
	c.rings = rgs
	_cache_put(_mesh_cache, key, c)
	_res_stats["mesh_misses"] = int(_res_stats["mesh_misses"]) + 1
	return c


static func torus(inner_radius: float, outer_radius: float, rings := 48, ring_segments := 8) -> TorusMesh:
	var rgs := detail_segments(rings, 12)
	var segs := detail_segments(ring_segments, 4)
	var key := "torus|%s|%s|%d|%d" % [_f3(inner_radius), _f3(outer_radius), rgs, segs]
	var cached: TorusMesh = _mesh_cache.get(key) as TorusMesh
	if cached != null:
		_res_stats["mesh_hits"] = int(_res_stats["mesh_hits"]) + 1
		return cached
	var t := TorusMesh.new()
	t.inner_radius = inner_radius
	t.outer_radius = outer_radius
	t.rings = rgs
	t.ring_segments = segs
	_cache_put(_mesh_cache, key, t)
	_res_stats["mesh_misses"] = int(_res_stats["mesh_misses"]) + 1
	return t


## Sky + sun + fog. Returns {"world_env", "env", "sun"}.
static func build_environment(parent: Node, shadows: bool, graphics_preset: int) -> Dictionary:
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	configure_environment(env, graphics_preset)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.92
	env.adjustment_enabled = graphics_preset != SettingsManager.PRESET_POTATO
	# Vivid colour grade (shared by every preset): saturated hues, punchy contrast.
	env.adjustment_contrast = 1.34
	env.adjustment_saturation = 1.45
	env.fog_enabled = graphics_preset == SettingsManager.PRESET_HIGH
	env.fog_light_color = Color(0.78, 0.9, 1.0)
	env.fog_density = 0.0025
	env.fog_sky_affect = 0.0
	env.glow_enabled = graphics_preset == SettingsManager.PRESET_HIGH
	if env.glow_enabled:
		env.glow_intensity = 0.3
		env.glow_bloom = 0.08
		env.glow_hdr_threshold = 1.1
	world_env.environment = env
	parent.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, 38.0, 0.0)
	sun.light_energy = 1.2 if graphics_preset == SettingsManager.PRESET_HIGH else (1.08 if graphics_preset == SettingsManager.PRESET_MEDIUM else 1.0)
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = shadows
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.3
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.4
	parent.add_child(sun)
	return {"world_env": world_env, "env": env, "sun": sun}


static func configure_environment(env: Environment, graphics_preset: int) -> void:
	var sky := Sky.new()
	if graphics_preset == SettingsManager.PRESET_HIGH:
		var panorama := PanoramaSkyMaterial.new()
		panorama.panorama = load("res://NewAssets/in_game/rustig_koppie_puresky_1k.hdr")
		sky.sky_material = panorama
		sky.radiance_size = Sky.RADIANCE_SIZE_256
	else:
		var procedural := ProceduralSkyMaterial.new()
		procedural.sky_top_color = Color(0.12, 0.48, 1.0)
		procedural.sky_horizon_color = Color(0.64, 0.88, 1.0)
		procedural.ground_bottom_color = Color(0.46, 0.72, 0.95)
		procedural.ground_horizon_color = Color(0.78, 0.94, 1.0)
		procedural.sun_angle_max = 25.0
		procedural.sun_curve = 0.2
		sky.sky_material = procedural
		env.glow_enabled = false
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0 if graphics_preset == SettingsManager.PRESET_HIGH else (0.88 if graphics_preset == SettingsManager.PRESET_MEDIUM else (0.72 if graphics_preset == SettingsManager.PRESET_POTATO else 0.78))
	env.adjustment_enabled = graphics_preset != SettingsManager.PRESET_POTATO
	env.adjustment_contrast = 1.34
	env.adjustment_saturation = 1.45


## A field of puffy clouds rendered with a single MultiMesh (one draw call).
static func build_cloud_field(parent: Node, count: int, min_radius: float, max_radius: float,
		min_y: float, max_y: float, seed_value := 1337) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Clouds"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sphere(1.0, 12, 6)
	var puffs_per_cloud := 1 if _potato() else (2 if _low_quality() else 4)
	mm.instance_count = count * puffs_per_cloud
	var i := 0
	for c in count:
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(min_radius, max_radius)
		var center := Vector3(cos(angle) * radius, rng.randf_range(min_y, max_y), sin(angle) * radius)
		var base_scale := rng.randf_range(2.0, 4.5)
		for p in puffs_per_cloud:
			var offset := Vector3(rng.randf_range(-1.0, 1.0) * base_scale, rng.randf_range(-0.2, 0.3) * base_scale, rng.randf_range(-0.6, 0.6) * base_scale)
			var s := base_scale * rng.randf_range(0.5, 1.0)
			var basis := Basis.IDENTITY.scaled(Vector3(s * 1.3, s * 0.7, s))
			mm.set_instance_transform(i, Transform3D(basis, center + offset))
			i += 1
	mmi.multimesh = mm
	mmi.material_override = mat(Color(1, 1, 1), 1.0, true)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _potato():
		# Beyond camera reach ~110 units: cull (self-fade avoids a hard pop).
		mmi.visibility_range_end = 130.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mmi)
	return mmi


## Huge flat "cloud sea" far below the arena: marks the fall zone visually.
static func build_cloud_sea(parent: Node, y: float, radius: float) -> MeshInstance3D:
	var disc := cylinder(radius, radius, 0.5, 40)
	var alpha := 1.0 if _potato() else 0.9
	var mi := mesh_instance(disc, mat(Color(0.95, 0.97, 1.0), 1.0, true, alpha), Vector3(0, y, 0), false)
	mi.name = "CloudSea"
	if _potato():
		mi.visibility_range_end = 120.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mi)
	return mi


## Floating island: a coloured disc with a rocky cone underneath.
static func build_island(parent: Node, pos: Vector3, radius: float, top_color: Color, side_color: Color, with_collision: bool) -> Node3D:
	var root: Node3D
	if with_collision:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = radius
		cyl.height = 1.0
		shape.shape = cyl
		shape.position.y = -0.5
		body.add_child(shape)
		root = body
	else:
		root = Node3D.new()
	root.position = pos
	var top := mesh_instance(cylinder(radius, radius, 0.4, 32), mat(top_color, 0.7), Vector3(0, -0.2, 0))
	root.add_child(top)
	var side := mesh_instance(cylinder(radius, radius * 0.75, 0.8, 32), mat(side_color, 0.8), Vector3(0, -0.8, 0))
	root.add_child(side)
	var rock := mesh_instance(cylinder(radius * 0.75, 0.3, radius * 1.6, 16), mat(side_color.darkened(0.35), 0.9), Vector3(0, -1.2 - radius * 0.8, 0))
	root.add_child(rock)
	parent.add_child(root)
	return root


## Decorative far islands around the horizon.
static func build_distant_islands(parent: Node) -> void:
	var colors := [Color(0.45, 0.9, 0.3), Color(1.0, 0.56, 0.16), Color(0.62, 0.36, 0.95), Color(0.2, 0.85, 0.95), Color(1.0, 0.42, 0.72)]
	for i in 5:
		var angle := i * TAU / 5.0 + 0.4
		var dist := 70.0 + 10.0 * (i % 2)
		var pos := Vector3(cos(angle) * dist, -6.0 - 4.0 * (i % 3), sin(angle) * dist)
		var island := build_island(parent, pos, 7.0 + 2.0 * (i % 2), colors[i % colors.size()], Color(0.55, 0.4, 0.75), false)
		var tree := mesh_instance(cylinder(0.0, 2.5, 6.0, 10), mat(Color(0.3, 0.75, 0.35)), Vector3(0, 3.0, 0))
		island.add_child(tree)
		var trunk := mesh_instance(cylinder(0.5, 0.6, 2.0, 8), mat(Color(0.5, 0.33, 0.2)), Vector3(0, 0.8, 0))
		island.add_child(trunk)
