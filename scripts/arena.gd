extends Node3D
## Arena shell: builds the selected map (see map_builder.gd), the sky / light, the HUD and
## wires up the round manager. The map is chosen by the match configuration
## (GameManager.get_match_config()): 5 floating arenas and 2 houses for hide and seek.

const GameConstants := preload("res://scripts/game_constants.gd")
const Scenery := preload("res://scripts/scenery.gd")
const MapBuilder := preload("res://scripts/map_builder.gd")
const HUDScene := preload("res://scenes/ui/gameplay_hud.tscn")

@onready var round_manager: Node = $RoundManager
@onready var players_root: Node3D = $Players
@onready var obstacles_root: Node3D = $Obstacles
@onready var decor_root: Node3D = $Decor
@onready var overview_camera: Camera3D = $OverviewCamera

var map_id := 0
var map_info: Dictionary = {}
var hud: CanvasLayer = null
var sun: DirectionalLight3D = null
var env: Environment = null
var _poof: CPUParticles3D = null
var _splash: CPUParticles3D = null
var _confetti: CPUParticles3D = null
var _spectating := false
var _orbit := 0.0


func _ready() -> void:
	var cfg: Dictionary = GameManager.get_match_config()
	var mode := int(cfg.get("mode", GameConstants.MODE_FFA))
	map_id = int(cfg.get("map", 0))
	var allowed: Array = GameConstants.maps_for_mode(mode)
	if not allowed.has(map_id):
		map_id = int(allowed[0])
	var shadows := bool(SettingsManager.get_setting("shadows"))
	var preset := int(SettingsManager.get_setting("graphics_preset"))
	var scenery := Scenery.build_environment(self, shadows, preset)
	sun = scenery["sun"]
	env = scenery["env"]
	map_info = MapBuilder.build(map_id, self)
	if bool(SettingsManager.get_setting("effects")):
		_build_effects()

	hud = HUDScene.instantiate()
	add_child(hud)
	hud.bind(round_manager)
	round_manager.local_player_eliminated.connect(_on_local_eliminated)
	round_manager.setup(self)
	overview_camera.global_position = Vector3(0, float(map_info.get("cam_height", 15.0)), float(map_info.get("cam_radius", 24.0)))
	overview_camera.look_at(Vector3(0, 0, 0), Vector3.UP)
	SettingsManager.settings_changed.connect(_on_setting_changed)
	_apply_quality()


func _process(delta: float) -> void:
	if _spectating:
		_orbit += delta * 0.15
		var r := float(map_info.get("cam_radius", 24.0))
		var h := float(map_info.get("cam_height", 15.0))
		overview_camera.global_position = Vector3(cos(_orbit) * r, h, sin(_orbit) * r)
		overview_camera.look_at(Vector3(0, 0.5, 0), Vector3.UP)


## Spawn point for the n-th player. Houses have two groups: 0 = hiders, 1 = seekers.
func get_spawn_point(index: int, group := 0) -> Vector3:
	var list: Array = map_info.get("spawns", [])
	if map_info.has("spawn_groups"):
		var groups: Array = map_info["spawn_groups"]
		list = groups[clampi(group, 0, groups.size() - 1)]
	if list.is_empty():
		return Vector3(0, 0.6, 0)
	var v: Vector3 = list[index % list.size()]
	return v


func is_house() -> bool:
	return int(map_info.get("kind", 0)) == 1


func is_trampoline_arena() -> bool:
	return int(map_info.get("kind", 0)) == 2


# ---------------------------------------------------------------------------
# Effects

func _build_effects() -> void:
	_poof = _make_burst(18, 0.7, Color(1, 1, 1), 2.0, 5.0)
	add_child(_poof)
	_splash = _make_burst(40, 1.0, Color(0.35, 0.7, 1.0), 1.5, 4.5)
	_splash.gravity = Vector3(0, -9, 0)
	add_child(_splash)

	_confetti = CPUParticles3D.new()
	_confetti.emitting = false
	_confetti.one_shot = true
	_confetti.amount = 60
	_confetti.lifetime = 2.2
	_confetti.explosiveness = 0.9
	_confetti.spread = 70.0
	_confetti.direction = Vector3(0, 1, 0)
	_confetti.initial_velocity_min = 5.0
	_confetti.initial_velocity_max = 9.0
	_confetti.gravity = Vector3(0, -4, 0)
	_confetti.scale_amount_min = 0.5
	_confetti.scale_amount_max = 1.0
	_confetti.angular_velocity_min = -360.0
	_confetti.angular_velocity_max = 360.0
	var cm := BoxMesh.new()
	cm.size = Vector3(0.18, 0.04, 0.12)
	var cmat := StandardMaterial3D.new()
	cmat.vertex_color_use_as_albedo = true
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.material = cmat
	_confetti.mesh = cm
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.12))
	grad.set_color(1, Color(0.2, 0.85, 0.95))
	grad.add_point(0.33, Color(1.0, 0.42, 0.72))
	grad.add_point(0.66, Color(0.45, 0.9, 0.3))
	_confetti.color_initial_ramp = grad
	add_child(_confetti)


func _make_burst(amount: int, lifetime: float, color: Color, vmin: float, vmax: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = maxi(1, int(amount / 2)) if int(SettingsManager.get_setting("graphics_preset")) == SettingsManager.PRESET_LOW else amount
	p.lifetime = lifetime
	p.explosiveness = 1.0
	p.spread = 180.0
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = Vector3(0, -2, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var pm := SphereMesh.new()
	pm.radius = 0.16
	pm.height = 0.32
	pm.radial_segments = Scenery.detail_segments(8)
	pm.rings = Scenery.detail_rings(4)
	pm.material = Scenery.mat(color, 1.0, true)
	p.mesh = pm
	return p


# ---------------------------------------------------------------------------
# Effects API (used by round_manager)

func spawn_poof(pos: Vector3) -> void:
	if _poof == null or not bool(SettingsManager.get_setting("effects")):
		return
	_poof.global_position = pos
	_poof.restart()


func spawn_splash(pos: Vector3) -> void:
	if _splash == null or not bool(SettingsManager.get_setting("effects")):
		return
	_splash.global_position = pos
	_splash.restart()


func celebrate_at(pos: Vector3) -> void:
	if _confetti == null or not bool(SettingsManager.get_setting("effects")):
		return
	_confetti.global_position = pos + Vector3(0, 1.5, 0)
	_confetti.restart()


# ---------------------------------------------------------------------------
# Spectator + quality

func _on_local_eliminated() -> void:
	_spectating = true
	_orbit = randf() * TAU
	overview_camera.current = true


func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "graphics_preset" and env != null:
		Scenery.configure_environment(env, int(value))
	if key == "effects" and bool(SettingsManager.get_setting("effects")) and _poof == null:
		_build_effects() # Create once if effects are enabled mid-round.
	if key in ["shadows", "effects", "graphics_preset", "render_scale", "msaa"]:
		_apply_quality()


func _apply_quality() -> void:
	var preset := int(SettingsManager.get_setting("graphics_preset"))
	if sun != null:
		sun.shadow_enabled = bool(SettingsManager.get_setting("shadows"))
		sun.light_energy = 1.2 if preset == SettingsManager.PRESET_HIGH else (1.08 if preset == SettingsManager.PRESET_MEDIUM else 1.0)
	if env != null:
		var effects := bool(SettingsManager.get_setting("effects"))
		env.fog_enabled = effects and preset == SettingsManager.PRESET_HIGH
		env.glow_enabled = effects and preset == SettingsManager.PRESET_HIGH
		if env.glow_enabled:
			env.glow_intensity = 0.3
			env.glow_bloom = 0.08
			env.glow_hdr_threshold = 1.1
