extends CharacterBody3D
## Third-person player controller.
##  - The OWNER peer simulates its own character (responsive on mobile) and
##    broadcasts position / facing / animation 20 times per second.
##  - Other peers interpolate a smooth puppet.
##  - Pushes and eliminations are validated by the host inside round_manager.gd.
##  - Practice bots are simulated by the host with a tiny wander / chase AI.

const GameConstants := preload("res://scripts/game_constants.gd")
const MapBuilder := preload("res://scripts/map_builder.gd")
const Scenery := preload("res://scripts/scenery.gd")
const AccessoriesLib := preload("res://scripts/accessories.gd")

const SHIELD_SHADER := preload("res://assets/shaders/shield_bubble.gdshader")
const MAGNET_SHADER := preload("res://assets/shaders/magnet_field.gdshader")
const BURST_SHADER := preload("res://assets/shaders/burst_glow.gdshader")

signal jump_performed
signal attack_performed

@export var run_speed := 7.5
@export var acceleration := 36.0
@export var deceleration := 42.0
@export var air_control := 0.45
@export var jump_velocity := 9.6
@export var gravity := 26.0
@export var max_fall_speed := 42.0
@export var dash_speed := GameConstants.DASH_SPEED
@export var dash_time := GameConstants.DASH_TIME
@export var dash_cooldown := GameConstants.DASH_COOLDOWN
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.15

const SYNC_INTERVAL := 0.05

# Trauma-based screen shake: amplitude grows with trauma squared, so weak hits
# stay subtle while heavy ones land hard.
const TRAUMA_DECAY := 1.6              # trauma units lost per second
const TRAUMA_MAX_OFFSET := 0.35        # metres of camera offset at full trauma
const TRAUMA_MAX_ROLL := 1.5           # degrees of camera roll at full trauma
const TRAUMA_LAND_SPEED := 12.0        # fall speed that counts as a hard landing
const TRAUMA_KO_RANGE := 14.0          # nearby KO adds a small kick
const SHAKE_NOISE_SPEED := 14.0        # noise units per second for h/v shake
const SHAKE_ROLL_SPEED := 10.0         # noise units per second for roll
const FOV_KICK_DEGREES := 8.0          # 70 -> 78 on dash
const FOV_KICK_IN := 0.08
const FOV_KICK_OUT := 0.3

var peer_id := 1
var player_name := "Player"
var color_index := 0
var detail_color_index := -1
var hat_id := ""
const SHIELD_PU := 2                    # power-up type index of the BUBBLE SHIELD (see powerups.gd)
const MAGNET_PU := 4                    # power-up type index of the MAGNET (see powerups.gd)
const MAGNET_RANGE := 6.5               # rivals inside this distance are drawn toward the carrier
const MAGNET_PULL := 3.4                # peak pull speed (m/s) right next to the carrier
const AI_TARGET_SCAN_INTERVAL := 0.22   # nearest-enemy refresh cadence for bots (seconds; inside the 0.15–0.25 s band)
const AI_HAZARD_CHECK_INTERVAL := 0.15  # bot hazard proximity refresh cadence (seconds)
var _pu_field: MeshInstance3D           # flat ring that shows the magnet range
var _burst_shader_cache: ShaderMaterial = null  # cached burst glow material (created once, reused)
var _aim_root: Node3D                   # punch aim line (local player only)
var _aim_bar: MeshInstance3D
var _aim_dot: MeshInstance3D
var _aim_mat: StandardMaterial3D
var is_bot := false
var is_local := false
var is_alive := true
var falls := 0
var last_position := Vector3.ZERO

var cam_yaw := 0.0
var cam_pitch := -0.38
var facing_yaw := 0.0
var move_input := Vector2.ZERO
var bot_world_dir := Vector3.ZERO
var jump_requested := false
var push_requested := false
var dash_requested := false
var arm_mode := 0                 # 0 = rubber punch, 1 = grab & pull
var grabbed_by := 0               # peer id currently holding me (pull physics runs on my authority)
var grabbing_id := 0              # peer id I am holding (known on every peer, drives arm length)
var grab_phase := 0               # 0 = being pulled in, 1 = hanging in the holder's hands
var team := 0
var role := 0                     # hide and seek: 0 none, 1 hider, 2 seeker
var hug_timer := 0.0

# --- Floor zone cache (map initialization) ---
var _floor_zone_refs: Array[Node3D] = []        # cached floor zone node refs (rebuilt when map changes)
var _zone_rebuild_stale: bool = true            # force rebuild of floor zone cache if map changed
var _zone_last_scene: Node3D = null             # track current arena scene to detect map change
var _zone_scratch: Dictionary = {}              # reusable scratch dict for influence_at calls (no per-zone alloc)

# --- Magnet carrier cache (efficient collection of relevant magnet carriers) ---
var _magnet_carriers: Array[Node3D] = []       # peer nodes carrying MAGNET_PU
var _magnet_candidates_stale: bool = true      # rebuild magnet carrier list when ownership/powerup state changes
var _zone_ice: bool = false                      # last queried floor zone ice state (no dict allocation)
var _zone_belt: Vector3 = Vector3.ZERO           # last queried floor zone belt contribution
var _zone_wind: Vector3 = Vector3.ZERO           # last queried floor zone wind contribution
var hug_partner := 0
var hug_victim := false
var camera_delta := Vector2.ZERO
var input_enabled := true

var _move_vel := Vector3.ZERO
var _knockback := Vector3.ZERO
var _stun := 0.0
var _pu_type := -1                   # active power-up (-1 none): 0 speed, 1 boots, 2 shield, 3 fist, 4 magnet
var _pu_time := 0.0
var _pu_aura: MeshInstance3D
var _marker_arrow: MeshInstance3D     # "this is YOU" arrow, local player only
var _marker_t := 0.0
var _push_timer := 0.0
var _arm_total_cd := 1.0
var _dash_timer := 0.0
var _dash_cd := 0.0
var _dash_dir := Vector3.ZERO
var _aim_lock := 0.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _was_on_floor := true
var _footstep_timer := 0.12
var _footstep_variant := false
var _fall_reported := false
var _sync_accum := 0.0
var _trauma := 0.0
var _trauma_time := 0.0
var _shake_noise: FastNoiseLite = null
var _fov_tween: Tween = null
var _base_fov := 70.0
var _celebrating := false
var _push_charge := 0.0           # charge (0..1) of the attack that is about to fire
var _key_charge_t := 0.0
var _bot_path: Array = []
var _bot_path_i := 0
var _bot_idle := false
var _bot_stuck_t := 0.0
var _bot_last_pos := Vector3.ZERO
var _bot_scan_t := 0.0

var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_vel := Vector3.ZERO
var _net_received := false
var _net_last_ms := 0

var _bot_timer := 0.0
var _bot_target := Vector3.ZERO
var _bot_jump_timer := 2.0

# --- Bot AI staggered scheduling & arena-scoped caches (perf: no SceneTree scans per tick) ---
var _ai_next_target_scan := 0.0        # seconds until the next nearest-enemy refresh (staggered per bot)
var _ai_next_hazard_check := 0.0       # seconds until the next hazard proximity evaluation (staggered per bot)
var _ai_target: Node = null            # cached nearest-enemy reference (reacquired immediately if it becomes invalid)
var _ai_arena: Node = null             # arena the caches below were built for
var _ai_map_info: Dictionary = {}      # cached arena map_info (read-only)
var _ai_hazards: Array[Node3D] = []    # cached hazard marker refs (rebuilt only when the arena changes)
var _ai_cache_built := false           # arena-scoped caches are built (even if empty / no arena yet)

# Aggregate debug statistics (shared across all bots; snapshot via bot_ai_stats()).
static var _ai_stats_window_start := 0     # Time.get_ticks_usec() at the current window's start
static var _ai_stats_decisions := 0        # staggered decision-block executions in the window
static var _ai_stats_target_searches := 0  # _nearest_enemy executions in the window
static var _ai_stats_hazard_checks := 0    # hazard proximity evaluations in the window

var team_ring_enabled := false
var round_manager: Node = null
var touch_controls: Node = null
var land_particles: CPUParticles3D = null

@onready var visuals: Node3D = $Visuals
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var audio_listener: AudioListener3D = $CameraPivot/SpringArm3D/Camera3D/AudioListener3D
@onready var name_label: Label3D = $NameLabel
var name_plate: Sprite3D


## Must be called BEFORE the node is added to the tree.
func setup(id: int, pname: String, color_idx: int, bot: bool, detail_idx := -1) -> void:
	peer_id = id
	player_name = pname
	color_index = color_idx
	detail_color_index = detail_idx
	is_bot = bot
	name = "P%d" % id
	# Bots are simulated by the host, so they belong to peer 1 (their id is only a label).
	set_multiplayer_authority(1 if bot else id)


func _ready() -> void:
	add_to_group("players")
	is_local = (not is_bot) and is_multiplayer_authority()
	var color := GameConstants.get_color(color_index)
	visuals.build(color, GameConstants.get_detail_color(detail_color_index))
	visuals.set_local_character(is_local)
	visuals.set_quality(_visual_quality())
	visuals.set_hat(hat_id)
	name_plate = Sprite3D.new()
	name_plate.name = "NamePlate"
	name_plate.texture = load("res://NewAssets/in_game/player_card_BG.png")
	name_plate.pixel_size = 0.012
	name_plate.billboard = 1
	name_plate.no_depth_test = true
	name_plate.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	name_plate.position = Vector3(0.0, 2.35 + AccessoriesLib.plate_lift(hat_id), 0.0)
	add_child(name_plate)
	remove_child(name_label)
	name_plate.add_child(name_label)
	name_label.position = Vector3(0.0, 0.0, 0.015)
	name_label.text = player_name
	name_label.font = load("res://assets/fonts/game_font.tres")
	name_label.modulate = Color.BLACK
	name_label.font_size = 96
	name_label.pixel_size = 0.0038
	name_label.outline_size = 24
	name_label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if team_ring_enabled:
		visuals.set_team_ring(GameConstants.team_color(team))
	# Stagger AI scans so all bots never evaluate on the same frame.
	_ai_next_target_scan = randf_range(0.0, AI_TARGET_SCAN_INTERVAL)
	_ai_next_hazard_check = randf_range(0.0, AI_HAZARD_CHECK_INTERVAL)
	if is_local:
		_build_local_marker()
	if role == GameConstants.HS_ROLE_HIDER:
		_set_name_tag_visible(false)
	spring_arm.add_excluded_object(get_rid())
	spring_arm.collision_mask = GameConstants.LAYER_WORLD
	camera.current = false
	audio_listener.current = is_local
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(50.0)
	_net_pos = global_position
	last_position = global_position
	if is_local:
		camera.current = true
		camera_pivot.top_level = true
		_base_fov = camera.fov
		_shake_noise = FastNoiseLite.new()
		_shake_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_shake_noise.frequency = 1.0
		_shake_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
		touch_controls = get_tree().get_first_node_in_group("touch_controls")
		if touch_controls != null:
			touch_controls.set_role_ui(role)
		SettingsManager.settings_changed.connect(_on_setting_changed)
		_apply_camera_settings()
		if round_manager != null:
			round_manager.knockout_scored.connect(_on_knockout_scored)
	else:
		camera_pivot.visible = false
	# Landing particles are created on demand when effects are enabled.


func face_direction(dir: Vector3) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length() < 0.001:
		return
	d = d.normalized()
	facing_yaw = atan2(-d.x, -d.z)
	cam_yaw = facing_yaw
	visuals.rotation.y = facing_yaw
	camera_pivot.rotation.y = cam_yaw
	spring_arm.rotation.x = cam_pitch
	camera_pivot.global_position = global_position + Vector3(0, 1.4, 0)


# ---------------------------------------------------------------------------
# Main loops

func _can_act() -> bool:
	if _celebrating or hug_timer > 0.0:
		return false
	if round_manager != null:
		if int(round_manager.state) != 2: # 2 = PLAYING
			return false
		if round_manager.is_locked(self):
			return false
	return true


func _physics_process(delta: float) -> void:
	# Rebuild magnet carrier list if ownership/powerup state changes
	if _magnet_candidates_stale:
		_magnet_carriers = []
		if round_manager != null:
			for p in round_manager.players.values():
				if p.is_alive and int(p.get("_pu_type")) == MAGNET_PU and is_enemy(p):
					_magnet_carriers.append(p)
		_magnet_candidates_stale = false
	if not is_alive:
		return
	hug_timer = maxf(0.0, hug_timer - delta)
	if is_multiplayer_authority():
		if not _can_act():
			move_input = Vector2.ZERO
			bot_world_dir = Vector3.ZERO
			jump_requested = false
			push_requested = false
			dash_requested = false
			if is_local and touch_controls != null and is_instance_valid(touch_controls):
				touch_controls.consume_jump()
				touch_controls.consume_push()
				touch_controls.consume_charge()
				touch_controls.consume_dash()
				touch_controls.consume_mode()
				camera_delta += touch_controls.consume_camera_delta()
		elif is_bot:
			if round_manager != null and int(round_manager.mode) == GameConstants.MODE_HIDE:
				_bot_think_hs(delta)
			else:
				_bot_think(delta)
		elif is_local and input_enabled:
			_gather_input()
		_simulate(delta)
		_check_fall()
		_send_sync(delta)
	else:
		_interpolate_remote(delta)
	last_position = global_position


func _process(delta: float) -> void:
	_track_grab_visual()
	_tick_powerup(delta)
	_tick_marker(delta)
	_tick_aim()
	if not is_local:
		return
	_update_camera(delta)
	if touch_controls != null and is_instance_valid(touch_controls):
		touch_controls.set_status(_dash_cd / maxf(dash_cooldown, 0.01), _push_timer / maxf(_arm_total_cd, 0.01), arm_mode, grabbing_id == 0 and grabbed_by == 0)


# ---------------------------------------------------------------------------
# Input

func _gather_input() -> void:
	var input := Vector2.ZERO
	input.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input.y = Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	if touch_controls != null and is_instance_valid(touch_controls):
		input += touch_controls.get_move_vector()
		if touch_controls.consume_jump():
			jump_requested = true
		var touch_punch: bool = touch_controls.consume_punch()
		var touch_grab: bool = touch_controls.consume_grab()
		if touch_punch or touch_grab:
			# Separate HUD buttons select their attack directly; no mode toggle is
			# needed, and either action still uses the existing charged attack flow.
			arm_mode = GameConstants.ARM_MODE_GRAB if touch_grab else GameConstants.ARM_MODE_PUNCH
			push_requested = true
			_push_charge = touch_controls.consume_charge()
		if touch_controls.consume_dash():
			dash_requested = true
		if touch_controls.consume_mode():
			toggle_arm_mode()
		camera_delta += touch_controls.consume_camera_delta()
	if input.length() > 1.0:
		input = input.normalized()
	move_input = input
	if Input.is_action_just_pressed("jump"):
		jump_requested = true
	var instant := round_manager != null and int(round_manager.mode) == GameConstants.MODE_HIDE
	if Input.is_action_just_pressed("push"):
		_key_charge_t = 0.0
		if instant:
			push_requested = true
	if Input.is_action_pressed("push") and not instant:
		_key_charge_t += get_physics_process_delta_time()
	if Input.is_action_just_released("push") and not instant:
		push_requested = true
		_push_charge = clampf(_key_charge_t / GameConstants.CHARGE_TIME, 0.0, 1.0)
		_key_charge_t = 0.0
	# No visual charge feedback (animation removed).
	if Input.is_action_just_pressed("dash"):
		dash_requested = true
	if Input.is_action_just_pressed("arm_mode"):
		toggle_arm_mode()
	var key_cam_x := Input.get_action_strength("cam_right") - Input.get_action_strength("cam_left")
	var key_cam_y := Input.get_action_strength("cam_down") - Input.get_action_strength("cam_up")
	camera_delta += Vector2(key_cam_x, key_cam_y) * 9.0


func _update_camera(delta: float) -> void:
	var sens := float(SettingsManager.get_setting("camera_sensitivity")) * 0.0045
	var inv := -1.0 if bool(SettingsManager.get_setting("invert_camera_y")) else 1.0
	cam_yaw -= camera_delta.x * sens
	cam_pitch -= camera_delta.y * sens * inv
	cam_pitch = clampf(cam_pitch, -0.8 if _indoor_camera() else -1.15, 0.3 if _indoor_camera() else 0.45)
	camera_delta = Vector2.ZERO
	# Smooth follow (pivot is top-level so it can lag behind the body a little).
	var target := global_position + Vector3(0, 1.4, 0)
	camera_pivot.global_position = camera_pivot.global_position.lerp(target, 1.0 - exp(-14.0 * delta))
	camera_pivot.rotation.y = cam_yaw
	spring_arm.rotation.x = cam_pitch
	_update_shake(delta)


## Trauma-driven camera shake. Trauma decays linearly and the offset amplitude
## is trauma squared, so weak hits stay subtle. The FastNoiseLite instance is
## created once in _ready and sampled over time: no random calls, no per-frame
## allocations. Disabled entirely by the "screen_shake" setting.
func _update_shake(delta: float) -> void:
	if _shake_noise == null or _trauma <= 0.0 or not bool(SettingsManager.get_setting("screen_shake")):
		_trauma = 0.0
		camera.h_offset = 0.0
		camera.v_offset = 0.0
		camera.rotation.z = 0.0
		return
	_trauma = maxf(0.0, _trauma - TRAUMA_DECAY * delta)
	_trauma_time += delta
	var amp := _trauma * _trauma
	camera.h_offset = _shake_noise.get_noise_2d(_trauma_time * SHAKE_NOISE_SPEED, 0.0) * amp * TRAUMA_MAX_OFFSET
	camera.v_offset = _shake_noise.get_noise_2d(0.0, _trauma_time * SHAKE_NOISE_SPEED) * amp * TRAUMA_MAX_OFFSET
	camera.rotation.z = deg_to_rad(_shake_noise.get_noise_2d(_trauma_time * SHAKE_ROLL_SPEED, 137.0) * amp * TRAUMA_MAX_ROLL)


## Adds camera trauma (0..1). Amplitude is trauma squared; ignored when the
## screen shake setting is off or when this is not the local player's camera.
func add_trauma(amount: float) -> void:
	if not is_local or amount <= 0.0:
		return
	if not bool(SettingsManager.get_setting("screen_shake")):
		return
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


## Dash FOV kick: 70 -> 78 over 0.08 s, back over 0.3 s. One tween object is
## kept and the previous run is killed before a new kick starts.
func _fov_kick() -> void:
	if not bool(SettingsManager.get_setting("screen_shake")):
		return
	if _fov_tween != null and _fov_tween.is_valid():
		_fov_tween.kill()
	_fov_tween = create_tween()
	_fov_tween.tween_property(camera, "fov", _base_fov + FOV_KICK_DEGREES, FOV_KICK_IN)
	_fov_tween.tween_property(camera, "fov", _base_fov, FOV_KICK_OUT)


## True in hide-and-seek (sealed apartments): shorter, flatter camera.
func _indoor_camera() -> bool:
	return int(GameManager.get_match_config().get("mode", 0)) == GameConstants.MODE_HIDE


func _apply_camera_settings() -> void:
	var dist := clampf(float(SettingsManager.get_setting("camera_distance")), 3.0, 12.0)
	if _indoor_camera():
		dist = minf(dist, 4.6)      # inside a sealed apartment the camera stays close: no ceiling / wall clipping
	spring_arm.spring_length = dist


func _visual_quality() -> int:
	match int(SettingsManager.get_setting("graphics_preset")):
		SettingsManager.PRESET_LOW:
			return 0
		SettingsManager.PRESET_POTATO:
			return 0    # same character detail teardown as LOW
		SettingsManager.PRESET_HIGH:
			return 2
		_:
			return 1


func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "camera_distance":
		_apply_camera_settings()
	elif key == "graphics_preset":
		visuals.set_quality(_visual_quality())
	elif key == "screen_shake" and not bool(value):
		_trauma = 0.0
		camera.h_offset = 0.0
		camera.v_offset = 0.0
		camera.rotation.z = 0.0
		if _fov_tween != null and _fov_tween.is_valid():
			_fov_tween.kill()
		camera.fov = _base_fov


# ---------------------------------------------------------------------------
# Simulation (authority only)

func _simulate(delta: float) -> void:
	var on_floor := is_on_floor()
	_push_timer = maxf(0.0, _push_timer - delta)
	var arena_event := int(round_manager.current_event) if round_manager != null else 0
	var dash_cooldown_rate := 1.8 if arena_event == 4 else 1.0
	_dash_cd = maxf(0.0, _dash_cd - delta * dash_cooldown_rate)
	_aim_lock = maxf(0.0, _aim_lock - delta)
	_stun = maxf(0.0, _stun - delta)
	if grabbed_by != 0 and grab_phase == 1:
		_simulate_carried(delta)
		return
	if hug_timer > 0.0:
		_simulate_hug(delta)
		return
	if on_floor:
		_coyote = coyote_time
	else:
		_coyote = maxf(0.0, _coyote - delta)
	if jump_requested:
		_jump_buffer = jump_buffer_time
		jump_requested = false
	else:
		_jump_buffer = maxf(0.0, _jump_buffer - delta)

	# Desired movement direction
	var wish := Vector3.ZERO
	if is_bot:
		wish = bot_world_dir
	elif not _celebrating:
		var forward := -camera_pivot.global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right := camera_pivot.global_transform.basis.x
		right.y = 0.0
		right = right.normalized()
		wish = right * move_input.x + forward * (-move_input.y)
	var mag := minf(wish.length(), 1.0)
	var speed_scale := 1.3 if arena_event == 2 else 1.0
	if _pu_type == 0 and _pu_time > 0.0:
		speed_scale *= 1.35
	var acceleration_scale := 0.38 if arena_event == 3 else 1.0
	var deceleration_scale := 0.24 if arena_event == 3 else 1.0
	# Floor zones: values are accumulated into member vars by _query_zones (no dict allocation).
	_query_zones(on_floor)
	if _zone_ice:
		acceleration_scale *= 0.16          # ice: slow to start and very slow to stop
		deceleration_scale *= 0.05
	var control := 1.0 if _stun <= 0.0 else 0.25
	var target := Vector3.ZERO
	if mag > 0.01:
		var carry := GameConstants.GRAB_CARRY_SPEED if (grabbing_id != 0 and grab_phase == 1) else 1.0
		target = wish.normalized() * run_speed * speed_scale * mag * control * carry
	var rate := (acceleration * acceleration_scale) if mag > 0.01 else (deceleration * deceleration_scale)
	if not on_floor:
		rate *= air_control
	_move_vel = _move_vel.move_toward(target, rate * delta)

	# Dash: short, powerful directional burst that overrides normal run speed.
	if dash_requested:
		dash_requested = false
		_try_dash(wish)
	if _dash_timer > 0.0:
		_dash_timer -= delta
		_move_vel = _dash_dir * dash_speed

	# While carrying, movement turns the body toward travel. Standing still keeps the
	# last body facing: the hand and the throw follow the BODY, never the camera stick.
	if grabbing_id != 0 and is_local:
		if mag > 0.05:
			facing_yaw = atan2(-wish.x, -wish.z)
	elif mag > 0.05 and _aim_lock <= 0.0 and grabbing_id == 0 and _dash_timer <= 0.0:
		facing_yaw = atan2(-wish.x, -wish.z)
	if grabbing_id != 0 and is_local:
		visuals.rotation.y = facing_yaw
	else:
		visuals.rotation.y = lerp_angle(visuals.rotation.y, facing_yaw, 1.0 - exp(-14.0 * delta))

	# Gravity
	var gravity_scale := 0.58 if arena_event == 1 else 1.0
	var jump_scale := 1.18 if arena_event == 1 else 1.0
	if _pu_type == 1 and _pu_time > 0.0:
		jump_scale *= 1.45
	if not on_floor:
		velocity.y = maxf(velocity.y - gravity * gravity_scale * delta * (0.25 if _dash_timer > 0.0 else 1.0), -max_fall_speed)

	# Jump (buffered + coyote time, never repeats mid-air)
	if _jump_buffer > 0.0 and (on_floor or _coyote > 0.0) and not _celebrating:
		velocity.y = jump_velocity * jump_scale
		_jump_buffer = 0.0
		_coyote = 0.0
		on_floor = false
		if is_local:
			jump_performed.emit()
		AudioManager.play_character("jump", 0.06, 0.0 if is_local else -10.0)
		if grabbed_by != 0:
			_report_escape()   # jumping out of a grab is legitimate counterplay

	# Being pulled in (phase 0): applied here, on the held player's own authority, so it never fights the owner's input.
	# The hook also cuts the victim's running control, otherwise a sprinting target can
	# outrun the pull and the grab times out before it ever reaches the hand.
	var pull_control := 1.0
	if grabbed_by != 0 and grab_phase == 0:
		var holder: Node = null
		if round_manager != null:
			holder = round_manager.players.get(grabbed_by)
		if holder != null and is_instance_valid(holder) and holder.is_alive:
			var to_holder: Vector3 = holder.global_position - global_position
			to_holder.y = 0.0
			if to_holder.length() > GameConstants.GRAB_HOLD_DISTANCE * 0.8:
				_knockback = _knockback.lerp(to_holder.normalized() * GameConstants.GRAB_PULL_SPEED, 1.0 - exp(-10.0 * delta))
				pull_control = GameConstants.GRAB_PULL_CONTROL
		else:
			grabbed_by = 0

	# Knockback decays faster on the ground
	var decay := 7.0 if on_floor else 2.2
	if _zone_ice:
		decay = 1.4                              # knockback keeps sliding on ice
	_knockback = _knockback.lerp(Vector3.ZERO, 1.0 - exp(-decay * delta))
	if _knockback.length() < 0.05:
		_knockback = Vector3.ZERO

	var zone_push: Vector3 = _zone_belt + _zone_wind
	velocity.x = _move_vel.x * pull_control + _knockback.x + zone_push.x
	velocity.z = _move_vel.z * pull_control + _knockback.z + zone_push.z
	var landing_speed := maxf(-velocity.y, 0.0)
	move_and_slide()

	var now_floor := is_on_floor()
	if now_floor and not _was_on_floor:
		_on_landed(landing_speed)
		_apply_trampoline_bounce(landing_speed)
	_update_footsteps(delta, now_floor)
	_was_on_floor = now_floor

	if push_requested:
		push_requested = false
		_try_attack()

	_update_authority_anim(now_floor)


## Hanging in somebody's hands: follow the holder (kinematic, no collisions) until the host releases us.
func _simulate_carried(delta: float) -> void:
	_push_timer = maxf(0.0, _push_timer - delta)
	jump_requested = false
	dash_requested = false
	# Mash punch to struggle free; the host counts taps within a short time window.
	if push_requested:
		push_requested = false
		_push_charge = 0.0
		if is_local:
			_report_escape(false)
	var holder: Node = null
	if round_manager != null:
		holder = round_manager.players.get(grabbed_by)
	if holder == null or not is_instance_valid(holder) or not holder.is_alive:
		grabbed_by = 0
		grab_phase = 0
		collision_shape.set_deferred("disabled", false)
		return
	var yaw: float = holder.visuals.rotation.y
	# CARRY FIX: place the carried player's centre at the overhead hold position.
	# get_grab_overhead_position() returns a point ~2.5 m above the holder's feet,
	# above their head and slightly forward.  This is where the actual hand aims
	# when carry_controlled is true, so the visible hand and the body match.
	var overhead: Vector3
	if holder.visuals.has_method("get_grab_overhead_position"):
		overhead = holder.visuals.get_grab_overhead_position()
	else:
		# Fallback: reconstruct CARRY_OVERHEAD_OFFSET manually.
		var fwd_fb := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var right_fb := Vector3(cos(yaw), 0.0, -sin(yaw))
		overhead = holder.global_position + fwd_fb * 0.12 + Vector3.UP * 2.55 + right_fb * 0.04
	global_position = overhead
	velocity = Vector3.ZERO
	_move_vel = Vector3.ZERO
	_knockback = Vector3.ZERO
	facing_yaw = yaw
	visuals.rotation.y = facing_yaw
	visuals.set_move_speed(0.0)


## Hug: the seeker stands still, the caught hider is anchored in front of the seeker.
func _simulate_hug(delta: float) -> void:
	var partner: Node = null
	if round_manager != null:
		partner = round_manager.players.get(hug_partner)
	if hug_victim and partner != null and is_instance_valid(partner):
		var yaw: float = partner.visuals.rotation.y
		var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
		global_position = partner.global_position + fwd * 0.95
		velocity = Vector3.ZERO
		facing_yaw = yaw + PI
		visuals.rotation.y = facing_yaw
		return
	_move_vel = Vector3.ZERO
	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y = maxf(velocity.y - gravity * delta, -max_fall_speed)
	move_and_slide()


func _update_authority_anim(on_floor: bool) -> void:
	# Animation removed: movement-core only.
	visuals.set_move_speed(Vector2(velocity.x, velocity.z).length())



func _update_footsteps(delta: float, grounded: bool) -> void:
	# Only locally simulated characters (and host-simulated bots) emit steps on this device.
	if not grounded or (not is_local and not is_bot) or _celebrating:
		_footstep_timer = minf(_footstep_timer, 0.10)
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed < 1.35:
		_footstep_timer = minf(_footstep_timer, 0.10)
		return
	_footstep_timer -= delta
	if _footstep_timer <= 0.0:
		var step_name := "footstep_a" if not _footstep_variant else "footstep_b"
		_footstep_variant = not _footstep_variant
		AudioManager.play_character(step_name, 0.025, -5.0)
		_footstep_timer = clampf(0.43 - horizontal_speed * 0.012, 0.28, 0.42)


func _apply_trampoline_bounce(landing_speed: float) -> void:
	if round_manager == null or int(round_manager.mode) != GameConstants.MODE_TRAMPOLINE:
		return
	if not is_multiplayer_authority() or get_slide_collision_count() <= 0:
		return
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision.get_normal().y < 0.55:
			continue
		var collider := collision.get_collider()
		if collider is Node and collider.is_in_group("trampoline_surfaces"):
			var base_strength := float(collider.get_meta("bounce_strength", 15.0))
			var impact_bonus := clampf(landing_speed * 0.12, 0.0, 2.0)
			velocity.y = clampf(maxf(base_strength, landing_speed * 1.15) + impact_bonus, 13.0, 19.0)
			_coyote = 0.0
			_jump_buffer = 0.0
			if is_local:
				AudioManager.play_character("jump", 0.1, -2.0)
			return

func _on_landed(landing_speed := 0.0) -> void:
	# Animation removed: movement-core only.
	AudioManager.play_character("land", 0.08, -4.0 if is_local else -14.0)
	if is_local and landing_speed >= TRAUMA_LAND_SPEED:
		add_trauma(0.15)
	if bool(SettingsManager.get_setting("effects")):
		if land_particles == null:
			_setup_particles()
		land_particles.restart()


func _check_fall() -> void:
	if global_position.y < GameConstants.FALL_Y and not _fall_reported:
		_fall_reported = true
		if round_manager != null:
			round_manager.report_fall(self)


# ---------------------------------------------------------------------------
# Dash

func _try_dash(wish: Vector3) -> void:
	if _dash_cd > 0.0 or _celebrating or _stun > 0.3 or _dash_timer > 0.0:
		if is_local and touch_controls != null and is_instance_valid(touch_controls):
			touch_controls.flash_denied("dash")
		return
	var d := Vector3(wish.x, 0.0, wish.z)
	if d.length() < 0.15:
		d = Vector3(-sin(facing_yaw), 0.0, -cos(facing_yaw))
	_dash_dir = d.normalized()
	facing_yaw = atan2(-_dash_dir.x, -_dash_dir.z)
	visuals.rotation.y = facing_yaw
	_dash_timer = dash_time
	_dash_cd = dash_cooldown
	# Animation removed: movement-core only.
	AudioManager.play_character("push", 0.1, 2.0 if is_local else -8.0)
	if bool(SettingsManager.get_setting("effects")):
		if land_particles == null:
			_setup_particles()
		land_particles.restart()
	if is_local:
		GameManager.vibrate(30)
		_fov_kick()
	if grabbed_by != 0:
		_report_escape()


func _report_escape(instant := true) -> void:
	if grabbed_by == 0 or round_manager == null:
		return
	round_manager.request_escape(self, instant)


# ---------------------------------------------------------------------------
# Physical hand reach: the host validates attacks while the pose rig moves the
# selected original hand through its connected arm bones.

func toggle_arm_mode() -> void:
	if grabbing_id != 0 or grabbed_by != 0:
		arm_mode = GameConstants.ARM_MODE_PUNCH
		return
	arm_mode = 1 - arm_mode
	AudioManager.play_ui("click", 0.0)


func get_arm_range() -> float:
	return GameConstants.arm_range(arm_mode, 1.0)


func _try_attack() -> void:
	if grabbed_by != 0:
		_push_charge = 0.0
		if is_local:
			_report_escape(false)
		return
	if grabbing_id != 0 and grab_phase == 0:
		_push_charge = 0.0
		if is_local and touch_controls != null and is_instance_valid(touch_controls):
			touch_controls.flash_denied("attack")
		return
	if round_manager != null and int(round_manager.mode) == GameConstants.MODE_HIDE:
		_try_catch()
		return
	var charge := clampf(_push_charge, 0.0, 1.0)
	_push_charge = 0.0
	if _push_timer > 0.0 or _celebrating or _stun > 0.3 or hug_timer > 0.0:
		if is_local and touch_controls != null and is_instance_valid(touch_controls):
			touch_controls.flash_denied("attack")
		return
	var carrying := grabbing_id != 0 and grab_phase == 1
	var attack_mode := GameConstants.ARM_MODE_PUNCH if carrying else arm_mode
	var grab := attack_mode == GameConstants.ARM_MODE_GRAB
	var rng := GameConstants.arm_range(attack_mode, charge)
	_arm_total_cd = GameConstants.arm_cooldown(attack_mode, charge)
	_push_timer = _arm_total_cd          # a miss still costs the full cooldown
	if is_local:
		attack_performed.emit()
	# The arm follows the character's BODY facing (yaw only), never the camera /
	# joystick.  The body turns from movement or toward a valid aim-assist target,
	# and the hand target keeps the holder's chest height so the arm never pitches.
	var aim_yaw := facing_yaw
	var dir_flat := Vector3(-sin(aim_yaw), 0.0, -cos(aim_yaw))
	var length := rng
	var tid := 0
	var target: Node = round_manager.players.get(grabbing_id) if carrying and round_manager != null else _find_arm_target(rng, aim_yaw)
	var hand_target := global_position + dir_flat * length + Vector3.UP * 1.15
	if target != null:
		tid = target.peer_id
		if not carrying:
			var flat: Vector3 = target.global_position - global_position
			flat.y = 0.0
			if flat.length() > 0.01:
				dir_flat = flat.normalized()
				facing_yaw = atan2(-dir_flat.x, -dir_flat.z)   # turn the body onto the target, yaw only
			# Use physics-root distance: animated running limbs and squash/lean poses
			# never change attack eligibility or the rubber-arm reach.
			length = clampf(GameConstants.combat_ground_distance(self, target) - GameConstants.ARM_TARGET_RADIUS, 0.8, rng)
			hand_target = global_position + dir_flat * length + Vector3.UP * 1.15
		else:
			hand_target = target.global_position + Vector3.UP * 1.0
	visuals.rotation.y = facing_yaw        # the hand and the body point the same way
	_aim_lock = 0.35
	if carrying:
		visuals.play_throw()
	elif grab:
		visuals.play_grab(hand_target, true)
	else:
		visuals.play_punch(hand_target, true, charge)
	AudioManager.play_character("push", 0.08, 0.0 if is_local else -10.0)
	if is_local:
		GameManager.vibrate(int(20.0 + 40.0 * charge))
	if NetworkManager.online and is_multiplayer_authority():
		_arm_fx.rpc(1 if grab else 0, length, facing_yaw, hand_target, carrying)
	if round_manager != null:
		round_manager.request_arm(self, attack_mode, tid, dir_flat, charge)


## Hide and seek: the seeker tries to catch a hider in front of him (no charge, instant).
func _try_catch() -> void:
	if role != GameConstants.HS_ROLE_SEEKER or _push_timer > 0.0 or hug_timer > 0.0 or _celebrating:
		if is_local and touch_controls != null and is_instance_valid(touch_controls):
			touch_controls.flash_denied("attack")
		return
	_arm_total_cd = GameConstants.HS_CATCH_COOLDOWN
	_push_timer = _arm_total_cd
	var facing := Vector3(-sin(facing_yaw), 0.0, -cos(facing_yaw))
	var best: Node = null
	var best_score := INF
	for p in get_tree().get_nodes_in_group("players"):
		if p == self or not p.is_alive or p.role != GameConstants.HS_ROLE_HIDER:
			continue
		var to: Vector3 = p.global_position - global_position
		to.y = 0.0
		var d := GameConstants.combat_ground_distance(self, p)
		if d > GameConstants.HS_CATCH_RANGE or d < 0.001:
			continue
		if facing.dot(to / d) < 0.05 or not _has_line_of_sight(p):
			continue
		if d < best_score:
			best_score = d
			best = p
	var tid := 0
	if best != null:
		var flat: Vector3 = best.global_position - global_position
		flat.y = 0.0
		facing_yaw = atan2(-flat.x, -flat.z)
		tid = best.peer_id
	visuals.rotation.y = facing_yaw
	_aim_lock = 0.3
	# Animation removed: movement-core only.
	AudioManager.play_character("push", 0.08, -4.0 if is_local else -12.0)
	if tid != 0 and round_manager != null:
		round_manager.request_catch(self, tid)


## Cosmetic only: lets other peers play the same stretch animation. The effect itself is decided by the host.
@rpc("authority", "call_remote", "reliable")
func _arm_fx(mode: int, length: float, yaw: float, hand_target: Vector3, throwing := false) -> void:
	if not is_inside_tree() or visuals == null:
		return
	_net_yaw = yaw
	visuals.rotation.y = yaw
	if throwing:
		visuals.play_throw()
		return
	if mode == GameConstants.ARM_MODE_GRAB:
		visuals.play_grab(hand_target, true)
	else:
		visuals.play_punch(hand_target, true, 0.5)


func _find_arm_target(rng: float, aim_yaw := NAN) -> Node:
	var best: Node = null
	var best_score := INF
	var yaw := facing_yaw if is_nan(aim_yaw) else aim_yaw
	var facing := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var reach := rng + GameConstants.ARM_LENIENCE   # same lenience the host applies
	for p in (round_manager.players.values() if round_manager != null else get_tree().get_nodes_in_group("players")):
		if p == self or not p.is_alive or not is_enemy(p):
			continue
		var to: Vector3 = p.global_position - global_position
		if absf(to.y) > GameConstants.ARM_VERTICAL_REACH:
			continue
		to.y = 0.0
		var d := to.length()
		var surface_distance := maxf(d - GameConstants.ARM_TARGET_RADIUS, 0.0)
		if surface_distance > reach or d < 0.001:
			continue
		var dot := facing.dot(to / d)
		if dot < 0.2:                       # wider cone: far targets at the screen edge are valid
			continue
		if not _has_line_of_sight(p):
			continue
		var score := surface_distance * (2.0 - dot) # prefer close, centered body contacts
		if score < best_score:
			best_score = score
			best = p
	return best


func is_enemy(other: Node) -> bool:
	if round_manager != null:
		return round_manager.are_enemies(peer_id, other.peer_id)
	return true


func _has_line_of_sight(other: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return true
	for height in [0.2, 0.8, 1.4]:
		var offset := Vector3(0, height, 0)
		var q := PhysicsRayQueryParameters3D.create(global_position + offset, other.global_position + offset, GameConstants.LAYER_WORLD)
		if space.intersect_ray(q).is_empty():
			return true
	return false


## Animation removed: movement-core only.
func _track_grab_visual() -> void:
	if grabbing_id == 0 or grab_phase != 0 or round_manager == null:
		return
	var t: Node = round_manager.players.get(grabbing_id)
	if t == null or not is_instance_valid(t):
		return


## Host -> everyone (via round_manager): I started / stopped holding `holding`, or I am (no longer) held by `held_by`.
## phase 0 = the arm is pulling, phase 1 = the victim hangs in the holder's hands (2 s), then it is dropped.
func set_grab_links(holding: int, held_by: int, phase := 0) -> void:
	var was_holding := grabbing_id
	var old_holder := grabbed_by
	var was_hanging := grabbed_by != 0 and grab_phase == 1
	grabbing_id = holding
	grabbed_by = held_by
	grab_phase = phase
	visuals.on_grab_links(holding, held_by, phase)
	if round_manager != null:
		var held_target: Node = round_manager.players.get(holding) if holding != 0 else null
		var old_target: Node = round_manager.players.get(was_holding) if was_holding != 0 else null
		if held_target != null and held_target.visuals != null:
			if phase == 1:
				pass
		if old_target != null and old_target.visuals != null and old_target != held_target:
			if old_target.visuals.has_method("clear_grab_tether"):
				pass
	if holding != 0 or held_by != 0:
		# A successful grab switches the attack button to punch/throw (or escape).
		arm_mode = GameConstants.ARM_MODE_PUNCH
	if holding != 0:
		if phase == 1:
			_push_timer = 0.0
		# Animation removed: movement-core only.
	elif was_holding != 0:
		# Animation removed: movement-core only.
		pass
	var hanging_now := held_by != 0 and phase == 1
	# Animation removed: movement-core only.
	if hanging_now:
		collision_shape.set_deferred("disabled", true)
	elif was_hanging:
		if is_alive:
			collision_shape.set_deferred("disabled", false)
		if is_multiplayer_authority() and round_manager != null:
			# Dropped: a small push away from the holder so we do not land inside him.
			var h: Node = round_manager.players.get(old_holder)
			if h != null and is_instance_valid(h):
				var away: Vector3 = global_position - h.global_position
				away.y = 0.0
				if away.length() < 0.05:
					away = Vector3(-sin(facing_yaw), 0, -cos(facing_yaw)) * -1.0
				_knockback = away.normalized() * GameConstants.GRAB_DROP_PUSH
			velocity.y = 1.0


## Hide and seek: the seeker starts hugging a hider.
func begin_hug_seeker(hider_id: int, duration: float) -> void:
	hug_timer = duration
	hug_partner = hider_id
	hug_victim = false
	_move_vel = Vector3.ZERO
	# Animation removed: movement-core only.


## Hide and seek: the caught hider reveals itself, gets hugged and melts into water.
func begin_hug_victim(seeker_id: int, duration: float) -> void:
	hug_timer = duration
	hug_partner = seeker_id
	hug_victim = true
	_move_vel = Vector3.ZERO
	_knockback = Vector3.ZERO
	_set_name_tag_visible(false)
	# Animation removed: movement-core only.


func set_disguise(prop_id: int) -> void:
	visuals.set_disguise(prop_id)
	_set_name_tag_visible(false)


func _set_name_tag_visible(value: bool) -> void:
	if is_instance_valid(name_label):
		name_label.visible = value
	if is_instance_valid(name_plate):
		name_plate.visible = value


## Called by the round manager before the node enters the tree.
func set_team_info(team_id: int, ring: bool, hs_role: int) -> void:
	team = team_id
	team_ring_enabled = ring
	role = hs_role


## Hide and seek: caught hider stays on the floor as a puddle, out of the game.
func become_puddle() -> void:
	is_alive = false
	grabbed_by = 0
	grabbing_id = 0
	collision_shape.set_deferred("disabled", true)
	_set_name_tag_visible(false)
	_move_vel = Vector3.ZERO
	_knockback = Vector3.ZERO
	velocity = Vector3.ZERO


## Called on the authority of this player (host validated the push / hammer hit).
func apply_knockback(impulse: Vector3, max_horizontal := 22.0, max_upward := 8.0) -> void:
	if not is_alive:
		return
	if _pu_type == SHIELD_PU and _pu_time > 0.0 and impulse.length() > 3.0:
		# Bubble shield: absorbs exactly one hit.
		clear_powerup()
		if round_manager != null and round_manager.get("powerups") != null:
			round_manager.powerups.shield_used(peer_id)
		if bool(SettingsManager.get_setting("effects")):
			_spawn_burst(global_position + Vector3(0, 1.0, 0), Color(0.4, 0.9, 1.0, 0.95), 24, 7.0)
		return
	_knockback += Vector3(impulse.x, 0.0, impulse.z)
	var h := Vector2(_knockback.x, _knockback.z)
	if h.length() > max_horizontal:
		h = h.normalized() * max_horizontal
		_knockback = Vector3(h.x, 0.0, h.y)
	velocity.y = maxf(velocity.y, 0.0) + clampf(impulse.y, 0.0, max_upward)
	_stun = 0.4
	var impact := Vector3(impulse.x, 0.0, impulse.z).length() / 22.0 + maxf(impulse.y, 0.0) / 30.0
	visuals.play_hit(impulse, clampf(impact, 0.3, 1.5))
	var spin_axis := Vector3.UP.cross(Vector3(impulse.x, 0.0, impulse.z)).normalized()
	if spin_axis.length_squared() > 0.0001:
		# Animation removed: movement-core only.
		pass
	if is_local:
		add_trauma(lerpf(0.35, 0.6, clampf(impact, 0.0, 1.0)))
		GameManager.vibrate(50)
		if bool(SettingsManager.get_setting("hitstop")) and Vector2(impulse.x, impulse.z).length() >= 12.0:
			_hit_stop(0.07)
	if bool(SettingsManager.get_setting("effects")) and impulse.length() > 3.0:
		_spawn_burst(global_position + Vector3(0, 1.0, 0), Color(1.0, 0.9, 0.35, 0.95), 5 if _visual_quality() == 0 else 12, 4.5)


## Conveyor belts, ice patches and fans under / around this player (see obstacles/floor_zone.gd).
## Called every physics tick; updates persistent member variables instead of allocating a new dictionary.
func _query_zones(on_floor: bool) -> void:
	# Reset zone accumulators for this frame.
	_zone_ice = false
	_zone_belt = Vector3.ZERO
	_zone_wind = Vector3.ZERO
	if grabbed_by != 0 or _dash_timer > 0.0:
		return
	# Resolve floor zone references once per map change; iterate cached list instead of scanning the SceneTree.
	_resolve_floor_zones(on_floor)
	# Add magnet pull to wind component (magnet runs on carrier's peer only).
	_zone_wind += _magnet_pull()


## Builds/refreshes cached floor zone references when the map changes, then queries each zone.
func _resolve_floor_zones(on_floor: bool) -> void:
	var arena: Node3D = round_manager.arena if round_manager != null else null
	if arena != null and not is_instance_valid(arena):
		arena = null
	if _zone_last_scene != null and not is_instance_valid(_zone_last_scene):
		# Previous arena was freed (map change): drop the stale node reference.
		_zone_last_scene = null
		_zone_rebuild_stale = true
	if _zone_rebuild_stale or arena != _zone_last_scene:
		_zone_last_scene = arena
		_floor_zone_refs.clear()
		if arena != null:
			# Find floor zones anywhere under this arena (they are parented to tier nodes, not the root).
			_collect_zone_refs(arena)
		else:
			# Fallback: global group scan (first frame or no round_manager yet).
			for z in get_tree().get_nodes_in_group("floor_zones"):
				if is_instance_valid(z):
					_floor_zone_refs.append(z)
		_zone_rebuild_stale = false
	# Iterate cached references and accumulate zone influence.
	for z in _floor_zone_refs:
		if not is_instance_valid(z):
			continue
		z.influence_at(global_position, on_floor, _zone_scratch)
		if bool(_zone_scratch["ice"]):
			_zone_ice = true
		_zone_belt += _zone_scratch["belt"] as Vector3
		_zone_wind += _zone_scratch["wind"] as Vector3


## Recursively collects floor zone nodes under `node` (zones are nested inside arena tier nodes).
func _collect_zone_refs(node: Node) -> void:
	for child in node.get_children():
		if child is Node3D and child.has_method("influence_at"):
			_floor_zone_refs.append(child)
		_collect_zone_refs(child)


## Rivals holding the MAGNET power-up draw this player toward them (runs on the owner's peer, so no extra network traffic).
func _magnet_pull() -> Vector3:
	var pull := Vector3.ZERO
	# Use cached magnet carrier list instead of scanning all players every tick.
	# is_instance_valid / is_alive / _pu_time guards cover lifecycle changes
	# between cache rebuilds (e.g. a carrier being eliminated mid-round).
	for p in _magnet_carriers:
		if not is_instance_valid(p) or not p.is_alive:
			continue
		if int(p.get("_pu_type")) != MAGNET_PU or float(p.get("_pu_time")) <= 0.0:
			continue
		var to: Vector3 = p.global_position - global_position
		to.y = 0.0
		var d2 := to.length_squared()
		if d2 > MAGNET_RANGE * MAGNET_RANGE or d2 < 1.4 * 1.4:
			continue
		var d := sqrt(d2)
		pull += to / d * MAGNET_PULL * (1.0 - d / MAGNET_RANGE)
	return pull


## Punch aim line: while the attack button is charging, a line on the floor shows where the punch goes and how far it
## reaches (it grows with the charge). It turns red and snaps onto an enemy that would be hit.
func _tick_aim() -> void:
	if not is_local:
		return
	var f := 0.0
	var want := bool(SettingsManager.get_setting("aim_line")) and is_alive and grabbed_by == 0 and not _celebrating
	if want and round_manager != null and int(round_manager.mode) == GameConstants.MODE_HIDE:
		want = false
	if want:
		f = clampf(_key_charge_t / GameConstants.CHARGE_TIME, 0.0, 1.0)
		if touch_controls != null and is_instance_valid(touch_controls):
			f = maxf(f, float(touch_controls.get_charge_fraction()))
		want = f > 0.04
	if not want:
		if _aim_root != null:
			_aim_root.visible = false
		return
	if _aim_root == null:
		_build_aim()
	var rng := GameConstants.arm_range(arm_mode, f)
	var yaw := facing_yaw
	var length := rng
	var locked := false
	var target := _find_arm_target(rng, yaw)
	if target != null:
		var flat: Vector3 = target.global_position - global_position
		flat.y = 0.0
		if flat.length() > 0.01:
			yaw = atan2(-flat.x, -flat.z)
			length = clampf(GameConstants.combat_ground_distance(self, target), 0.8, rng)
			locked = true
	var col := Color(1.0, 0.25, 0.2) if locked else Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.7, 0.1), f)
	_aim_mat.albedo_color = Color(col.r, col.g, col.b, 0.75 if locked else 0.55)
	var bar := maxf(length - 0.45, 0.1)
	_aim_bar.scale = Vector3(1.0, 1.0, bar)
	_aim_bar.position = Vector3(0.0, 0.0, -(0.45 + bar * 0.5))
	_aim_dot.position = Vector3(0.0, 0.0, -length)
	_aim_root.visible = true
	_aim_root.global_position = Vector3(global_position.x, global_position.y + 0.07, global_position.z)
	_aim_root.global_rotation = Vector3(0.0, yaw, 0.0)


func _build_aim() -> void:
	_aim_root = Node3D.new()
	_aim_root.name = "AimLine"
	_aim_root.top_level = true            # keeps its own rotation: the body's facing and the visuals' animation do not tilt it
	add_child(_aim_root)
	_aim_mat = Scenery.dup_material(Scenery.mat(Color(1, 1, 1), 0.5, true, 0.55)) as StandardMaterial3D
	_aim_bar = MeshInstance3D.new()
	_aim_bar.mesh = Scenery.box(Vector3(0.16, 0.02, 1.0))
	_aim_bar.material_override = _aim_mat
	_aim_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_root.add_child(_aim_bar)
	_aim_dot = MeshInstance3D.new()
	_aim_dot.mesh = Scenery.cylinder(0.3, 0.3, 0.02, 16)
	_aim_dot.material_override = _aim_mat
	_aim_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_root.add_child(_aim_dot)


## Hit-stop: offline the local game freezes for a moment on a strong hit
## (real-time timer, so it always ends). Online the simulation must keep
## running — movement is client-authoritative and replicated every 0.05 s — so
## the freeze is purely visual: the victim's and the local player's animators
## pause and the camera gets a stronger kick instead.
func _hit_stop(real_seconds: float) -> void:
	if not NetworkManager.online:
		if Engine.time_scale < 0.99:
			return
		Engine.time_scale = 0.06
		get_tree().create_timer(real_seconds, true, false, true).timeout.connect(func() -> void: Engine.time_scale = 1.0)
		return
	_freeze_impact_visuals(real_seconds)
	if _trauma < 0.65:
		add_trauma(0.65 - _trauma)


## Local-only, purely visual online hit-stop: pause the victim's and the local
## player's ContenderAnimator for a short real-time window.
func _freeze_impact_visuals(real_seconds: float) -> void:
	_freeze_animator(visuals, real_seconds)
	if round_manager != null:
		var lp: Node = round_manager.get("local_player") as Node
		if lp != null and lp != self:
			_freeze_animator(lp.get("visuals") as Node, real_seconds)


func _freeze_animator(v: Node, real_seconds: float) -> void:
	if v != null and is_instance_valid(v) and v.has_method("freeze_animation"):
		v.freeze_animation(real_seconds)


## A knockout near the local player adds a small camera kick. The victim's own
## client already got the hit trauma from apply_knockback().
func _on_knockout_scored(_killer_id: int, victim_id: int, _killer_name: String, _victim_name: String) -> void:
	if victim_id == peer_id or round_manager == null:
		return
	var victim: Node3D = round_manager.players.get(victim_id) as Node3D
	if victim == null or not is_instance_valid(victim):
		return
	if global_position.distance_squared_to(victim.global_position) <= TRAUMA_KO_RANGE * TRAUMA_KO_RANGE:
		add_trauma(0.25)


## Returns true when shader-powered visual effects should be used (effects
## setting on and graphics preset not LOW). Falls back to cheap materials on
## weak devices so the burst never allocates a shader when it cannot show it.
func _effects_allowed() -> bool:
	if SettingsManager == null:
		return false
	if not bool(SettingsManager.get_setting("effects")):
		return false
	var preset := int(SettingsManager.get_setting("graphics_preset"))
	return preset != SettingsManager.PRESET_LOW and preset != SettingsManager.PRESET_POTATO


## Returns the cached burst glow ShaderMaterial, creating it once on first use.
## The burst tint comes from the CPUParticles3D color (read as COLOR by the
## burst_glow shader), so the shader's glow_color can stay a fixed white.
func _get_burst_material() -> ShaderMaterial:
	if _burst_shader_cache == null:
		_burst_shader_cache = _burst_material(Color(1, 1, 1))
	return _burst_shader_cache


## One-shot spark / dust burst that stays in the world (not parented to the moving player); frees itself.
func _spawn_burst(pos: Vector3, color: Color, amount: int, speed: float) -> void:
	var host := get_parent()
	if host == null or not host.is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount * 2
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.mesh = _puff_mesh()
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.6
	p.initial_velocity_max = speed * 1.4
	p.gravity = Vector3(0, -9.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.1
	# CPUParticles3D color is exposed as COLOR in the burst_glow shader, so the
	# burst tint comes through here (albedo = glow_color * COLOR.rgb).
	p.color = color
	if _effects_allowed() and p.mesh != null:
		# Cached shader material: allocated once per session, never per burst/frame.
		# Without effects (or on LOW), the mesh keeps its cheap vertex-colour material.
		p.material_override = _get_burst_material()
	host.add_child(p)
	p.global_position = pos
	p.restart()
	get_tree().create_timer(1.1).timeout.connect(p.queue_free)


# ---------------------------------------------------------------------------
# Elimination / respawn / celebration

func eliminate() -> void:
	is_alive = false
	grabbed_by = 0
	grabbing_id = 0
	grab_phase = 0
	hug_timer = 0.0
	# Animation removed: movement-core only.
	visible = false
	collision_shape.set_deferred("disabled", true)
	_move_vel = Vector3.ZERO
	_knockback = Vector3.ZERO
	velocity = Vector3.ZERO


func respawn(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	_move_vel = Vector3.ZERO
	_knockback = Vector3.ZERO
	_stun = 0.0
	_dash_timer = 0.0
	_dash_cd = 0.0
	_push_timer = 0.0
	grabbed_by = 0
	grabbing_id = 0
	grab_phase = 0
	hug_timer = 0.0
	clear_powerup()
	visuals.reset_visual_state()
	_fall_reported = false
	is_alive = true
	visible = true
	collision_shape.set_deferred("disabled", false)
	_net_pos = pos
	face_direction(-pos)


func celebrate() -> void:
	_celebrating = true
	move_input = Vector2.ZERO
	# Animation removed: movement-core only.


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if not enabled:
		move_input = Vector2.ZERO
		jump_requested = false
		push_requested = false


# ---------------------------------------------------------------------------
# Networking

func _send_sync(delta: float) -> void:
	if not NetworkManager.online:
		return
	_sync_accum += delta
	if _sync_accum < SYNC_INTERVAL:
		return
	_sync_accum = 0.0
	_sync_state.rpc(global_position, visuals.rotation.y, visuals.get_net_anim(), velocity)


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_state(pos: Vector3, yaw: float, anim: int, vel: Vector3) -> void:
	if not is_inside_tree() or multiplayer == null:
		return
	# Host-side sanity check: ignore physically impossible jumps (> 25 m in < 0.25 s).
	var now := Time.get_ticks_msec()
	if _net_received and multiplayer.is_server():
		var dt := float(now - _net_last_ms) / 1000.0
		if dt < 0.25 and pos.distance_to(_net_pos) > 25.0:
			return
	_net_last_ms = now
	if not _net_received:
		global_position = pos
	_net_received = true
	_net_pos = pos
	_net_yaw = yaw
	_net_vel = vel
	visuals.set_move_speed(Vector2(vel.x, vel.z).length())
	visuals.apply_net_anim(anim)


func _interpolate_remote(delta: float) -> void:
	if not _net_received:
		return
	var target := _net_pos + _net_vel * 0.04
	if global_position.distance_to(target) > 6.0:
		global_position = target
	else:
		global_position = global_position.lerp(target, 1.0 - exp(-16.0 * delta))
	visuals.rotation.y = lerp_angle(visuals.rotation.y, _net_yaw, 1.0 - exp(-16.0 * delta))


# ---------------------------------------------------------------------------
# Practice bots (simulated on the host)

## Debug statistics for bot AI. Snapshot & reset the rolling window (rates are per-second).
## active_bots is the number of live bots in the match, passed by the caller (e.g. bench / debug HUD);
## pass -1 to report it as unknown.
static func bot_ai_stats(active_bots: int = -1) -> Dictionary:
	var now := Time.get_ticks_usec()
	if _ai_stats_window_start == 0:
		_ai_stats_window_start = now
	var elapsed := maxf(float(now - _ai_stats_window_start) / 1000000.0, 0.001)
	var snap := {
		"active_bots": active_bots,
		"window_seconds": elapsed,
		"decisions": _ai_stats_decisions,
		"decisions_per_sec": float(_ai_stats_decisions) / elapsed,
		"target_searches": _ai_stats_target_searches,
		"target_searches_per_sec": float(_ai_stats_target_searches) / elapsed,
		"hazard_checks": _ai_stats_hazard_checks,
		"hazard_checks_per_sec": float(_ai_stats_hazard_checks) / elapsed,
	}
	_ai_stats_window_start = now
	_ai_stats_decisions = 0
	_ai_stats_target_searches = 0
	_ai_stats_hazard_checks = 0
	return snap


## Refresh arena-scoped AI caches (map_info + hazard refs) when the arena changes.
## Rebuilt once per map, not per tick.
func _ai_ensure_arena_caches() -> void:
	var arena: Node3D = null
	if round_manager != null and round_manager.arena != null and is_instance_valid(round_manager.arena):
		arena = round_manager.arena
	if arena == _ai_arena and _ai_cache_built:
		return
	_ai_arena = arena
	_ai_cache_built = true
	_ai_map_info = {}
	_ai_hazards.clear()
	if arena != null:
		var mi: Variant = arena.get("map_info")
		if mi is Dictionary:
			_ai_map_info = mi
		_collect_hazard_refs(arena)
	else:
		# No arena yet (e.g. still streaming in): one global group scan, then cached.
		for h in get_tree().get_nodes_in_group("hazards"):
			if is_instance_valid(h) and h is Node3D:
				_ai_hazards.append(h)


## Recursively collects hazard markers under `node` (they are parented to rotating pivots, not the arena root).
func _collect_hazard_refs(node: Node) -> void:
	for child in node.get_children():
		if child is Node3D and child.is_in_group("hazards"):
			_ai_hazards.append(child)
		_collect_hazard_refs(child)


## O(1) sanity check on the cached target: gone? dead? no longer an enemy?
func _ai_target_valid() -> bool:
	var t := _ai_target
	return t != null and is_instance_valid(t) and t.is_alive and is_enemy(t)


func _bot_think(delta: float) -> void:
	_bot_timer -= delta
	_bot_jump_timer -= delta
	_ai_ensure_arena_caches()
	var info: Dictionary = _ai_map_info
	var r_max := float(info.get("bot_radius", 11.0))
	var r_min := float(info.get("bot_min_radius", 0.0))
	# Nearest enemy: refreshed on a staggered cadence (~0.2 s), or IMMEDIATELY if the cached one died or left.
	_ai_next_target_scan -= delta
	if _ai_next_target_scan <= 0.0:
		_ai_next_target_scan = AI_TARGET_SCAN_INTERVAL
		_ai_target = _nearest_enemy()
		_ai_stats_decisions += 1
	elif not _ai_target_valid():
		_ai_target = _nearest_enemy()
		_ai_next_target_scan = AI_TARGET_SCAN_INTERVAL
	var nearest := _ai_target
	if _bot_timer <= 0.0:
		_bot_timer = randf_range(1.2, 2.6)
		if nearest != null and randf() < 0.5 \
				and nearest.global_position.distance_squared_to(global_position) < 100.0:
			_bot_target = nearest.global_position
		else:
			var a := randf() * TAU
			var r := randf_range(maxf(r_min + 0.8, 1.5), maxf(r_max * 0.8, r_min + 1.6))
			_bot_target = Vector3(cos(a) * r, 0.0, sin(a) * r)
	if nearest != null:
		var td: Vector3 = _bot_target - nearest.global_position
		if td.length_squared() < 9.0:                      # < 3.0 m from the enemy: re-aim at them
			_bot_target = nearest.global_position
	var to := _bot_target - global_position
	to.y = 0.0
	bot_world_dir = Vector3.ZERO if to.length() < 0.6 else to.normalized() * 0.85
	# Stay on the platform (inside r_max, and outside r_min on the donut)
	var flat := Vector3(global_position.x, 0.0, global_position.z)
	if flat.length() > r_max:
		bot_world_dir = -flat.normalized()
		_bot_target = Vector3.ZERO if r_min <= 0.0 else flat.normalized() * (r_min + r_max) * 0.5
	elif r_min > 0.0 and flat.length() < r_min and flat.length() > 0.01:
		bot_world_dir = flat.normalized()
		_bot_target = flat.normalized() * (r_min + r_max) * 0.5
	# Jump over nearby hazards and occasionally for fun (checked on a staggered lower-frequency cadence)
	if is_on_floor():
		_ai_next_hazard_check -= delta
		if _ai_next_hazard_check <= 0.0:
			_ai_next_hazard_check = AI_HAZARD_CHECK_INTERVAL
			_ai_stats_hazard_checks += 1
			for h in _ai_hazards:
				if h == null or not is_instance_valid(h):
					continue
				if h.global_position.distance_squared_to(global_position) < 5.76:   # < 2.4 m
					jump_requested = true
					break
	if _bot_jump_timer <= 0.0:
		_bot_jump_timer = randf_range(2.5, 6.0)
		jump_requested = true
	# Rubber arm: charge a random amount, grab sometimes, punch otherwise (only when in reach).
	if nearest != null:
		var nd: float = nearest.global_position.distance_to(global_position)
		var ch := randf_range(0.25, 0.9)
		var mode := 1 if randf() < 0.25 else 0
		if nd < GameConstants.arm_range(mode, ch) * 0.9 and _push_timer <= 0.0 and randf() < 0.08:
			arm_mode = mode
			_push_charge = ch
			var d: Vector3 = nearest.global_position - global_position
			facing_yaw = atan2(-d.x, -d.z)
			visuals.rotation.y = facing_yaw
			push_requested = true
		elif nd > 4.0 and nd < 8.0 and _dash_cd <= 0.0 and flat.length() < r_max - 2.0 and randf() < 0.01:
			dash_requested = true   # close the gap, but never dash when already near the edge


## Hide and seek bots: hiders walk to a hiding spot and freeze, seekers patrol the rooms and
## catch hiders they actually bump into (they do not know where anybody is).
func _bot_think_hs(delta: float) -> void:
	bot_world_dir = Vector3.ZERO
	if round_manager == null or round_manager.arena == null or not is_on_floor():
		return
	_ai_ensure_arena_caches()
	var info: Dictionary = _ai_map_info
	if not info.has("rooms"):
		return
	var rooms: Array = info["rooms"]
	var graph: Dictionary = info["graph"]
	if role == GameConstants.HS_ROLE_HIDER:
		if _bot_idle:
			return
		if _bot_path.is_empty():
			var here := MapBuilder.room_at(rooms, global_position, 8.0, 8.0)
			var dest := 1 + randi() % maxi(rooms.size() - 1, 1)
			_bot_path = [rooms[here]["center"]]
			_bot_path.append_array(MapBuilder.plan_path(graph, rooms, here, dest))
			var spots: Array = rooms[dest]["spots"]
			if spots.size() > 0:
				_bot_path.append(spots[randi() % spots.size()])
			_bot_path_i = 0
	else:
		if round_manager.is_locked(self) or hug_timer > 0.0:
			return
		if _bot_path_i >= _bot_path.size():
			var here2 := MapBuilder.room_at(rooms, global_position, 8.0, 8.0)
			var dest2 := randi() % rooms.size()
			_bot_path = [rooms[here2]["center"]]
			if dest2 != here2:
				_bot_path.append_array(MapBuilder.plan_path(graph, rooms, here2, dest2))
			_bot_path_i = 0
		# Look around: a hider within arm's length may get caught (not every time).
		_bot_scan_t -= delta
		if _bot_scan_t <= 0.0:
			_bot_scan_t = 0.7
			_ai_stats_target_searches += 1
			var catch_d2 := (GameConstants.HS_CATCH_RANGE - 0.4) * (GameConstants.HS_CATCH_RANGE - 0.4)
			if round_manager != null:
				for id in round_manager.players:
					var p: Node = round_manager.players[id]
					if p == self or not is_instance_valid(p) or not p.is_alive or p.role != GameConstants.HS_ROLE_HIDER:
						continue
					var dd2: float = p.global_position.distance_squared_to(global_position)
					if dd2 < catch_d2 and _push_timer <= 0.0 and randf() < 0.45:
						var dv: Vector3 = p.global_position - global_position
						facing_yaw = atan2(-dv.x, -dv.z)
						visuals.rotation.y = facing_yaw
						push_requested = true
						break
			else:
				for p in get_tree().get_nodes_in_group("players"):
					if p == self or not p.is_alive or p.role != GameConstants.HS_ROLE_HIDER:
						continue
					var dd2: float = p.global_position.distance_squared_to(global_position)
					if dd2 < catch_d2 and _push_timer <= 0.0 and randf() < 0.45:
						var dv: Vector3 = p.global_position - global_position
						facing_yaw = atan2(-dv.x, -dv.z)
						visuals.rotation.y = facing_yaw
						push_requested = true
						break
	# Follow the waypoints
	if _bot_path_i < _bot_path.size():
		var wp: Vector3 = _bot_path[_bot_path_i]
		var to := wp - global_position
		to.y = 0.0
		if to.length() < 0.7:
			_bot_path_i += 1
		else:
			bot_world_dir = to.normalized() * 0.9
			_bot_stuck_t += delta
			if _bot_stuck_t >= 0.8:
				_bot_stuck_t = 0.0
				if global_position.distance_to(_bot_last_pos) < 0.25:
					_bot_path_i += 1          # stuck behind furniture: give up this waypoint
					jump_requested = true
				_bot_last_pos = global_position
	elif role == GameConstants.HS_ROLE_HIDER:
		_bot_idle = true


func _nearest_enemy() -> Node:
	_ai_stats_target_searches += 1
	var best: Node = null
	var best_d2 := INF
	if round_manager != null:
		# Direct dictionary iteration: no temporary Array allocation, no SceneTree scan.
		for id in round_manager.players:
			var p: Node = round_manager.players[id]
			if p == self or not is_instance_valid(p) or not p.is_alive or not is_enemy(p):
				continue
			var d2: float = p.global_position.distance_squared_to(global_position)
			if d2 < best_d2:
				best_d2 = d2
				best = p
		return best
	for p in get_tree().get_nodes_in_group("players"):
		if p == self or not p.is_alive or not is_enemy(p):
			continue
		var d2: float = p.global_position.distance_squared_to(global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = p
	return best


func _nearest_other_player() -> Node:
	return _nearest_enemy()


# ---------------------------------------------------------------------------
# Effects

func _setup_particles() -> void:
	land_particles = CPUParticles3D.new()
	land_particles.emitting = false
	land_particles.one_shot = true
	var preset := int(SettingsManager.get_setting("graphics_preset"))
	land_particles.amount = 2 if preset == SettingsManager.PRESET_POTATO else (4 if preset == SettingsManager.PRESET_LOW else 10)
	land_particles.lifetime = 0.45
	land_particles.explosiveness = 1.0
	land_particles.mesh = _puff_mesh()
	land_particles.direction = Vector3(0, 1, 0)
	land_particles.spread = 80.0
	land_particles.initial_velocity_min = 1.5
	land_particles.initial_velocity_max = 3.0
	land_particles.gravity = Vector3(0, -3.0, 0)
	land_particles.scale_amount_min = 0.5
	land_particles.scale_amount_max = 1.0
	land_particles.color = Color(1, 1, 1, 0.8)
	land_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	land_particles.emission_sphere_radius = 0.3
	land_particles.position = Vector3(0, 0.1, 0)
	add_child(land_particles)


## "Where am I?" helper, drawn only on the local player's screen: a white ring with a dark outline on the
## floor (readable on any tile colour, even one that matches the player's colour) and a bobbing arrow.
func _build_local_marker() -> void:
	var ring := MeshInstance3D.new()
	ring.name = "LocalRing"
	ring.mesh = Scenery.torus(0.74, 0.86, 28, 6)
	ring.material_override = Scenery.mat(Color(1, 1, 1), 0.5, true, 0.9)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(0, 0.05, 0)
	add_child(ring)
	var outline := MeshInstance3D.new()
	outline.name = "LocalRingOutline"
	outline.mesh = Scenery.torus(0.86, 0.95, 28, 6)
	outline.material_override = Scenery.mat(Color(0.05, 0.05, 0.1), 0.5, true, 0.85)
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	outline.position = Vector3(0, 0.045, 0)
	add_child(outline)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.2
	cone.height = 0.4
	cone.radial_segments = 8
	cone.rings = 1
	_marker_arrow = MeshInstance3D.new()
	_marker_arrow.name = "LocalArrow"
	_marker_arrow.mesh = cone
	_marker_arrow.material_override = Scenery.mat(Color(1.0, 0.9, 0.2), 0.4, true)
	_marker_arrow.rotation.x = PI                 # tip points down at the player
	_marker_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker_arrow.position = Vector3(0, 3.0, 0)
	add_child(_marker_arrow)


func _tick_marker(delta: float) -> void:
	if _marker_arrow == null or not is_instance_valid(_marker_arrow):
		return
	_marker_t += delta
	_marker_arrow.position.y = 3.0 + sin(_marker_t * 4.0) * 0.1
	_marker_arrow.visible = is_alive


## Power-up from the floor (runs on every peer: the aura is visual; the effect is read by the owner's movement code).
func _shield_material(color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHIELD_SHADER
	mat.set_shader_parameter("glow_color", Color(color.r, color.g, color.b, 0.55))
	mat.set_shader_parameter("pulse_speed", 5.0)
	mat.set_shader_parameter("pulse_amount", 0.35)
	mat.set_shader_parameter("rim_power", 5.0)
	mat.set_shader_parameter("emission_strength", 4.0)
	return mat


func _magnet_material(color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = MAGNET_SHADER
	mat.set_shader_parameter("glow_color", Color(color.r, color.g, color.b, 0.55))
	mat.set_shader_parameter("swirl_speed", 3.0)
	mat.set_shader_parameter("pulse_speed", 4.0)
	mat.set_shader_parameter("emission_strength", 4.0)
	return mat


func _burst_material(color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = BURST_SHADER
	mat.set_shader_parameter("glow_color", Color(color.r, color.g, color.b, 0.95))
	mat.set_shader_parameter("emission_strength", 6.0)
	mat.set_shader_parameter("pulse_speed", 8.0)
	return mat


## Power-up from the floor (runs on every peer: the aura is visual; the effect is read by the owner's movement code).
func apply_powerup(type: int, duration: float) -> void:
	_pu_type = type
	_pu_time = duration
	if type == MAGNET_PU:
		# Magnet state changed: mark every player's carrier list dirty so each
		# authority rebuilds its own cache next tick.
		if round_manager != null:
			for p in round_manager.players.values():
				p._magnet_candidates_stale = true
	if _pu_aura == null or not is_instance_valid(_pu_aura):
		var aura_quality: int = int(SettingsManager.get_setting("graphics_preset"))
		var cheap_aura := SettingsManager == null or aura_quality == SettingsManager.PRESET_POTATO
		_pu_aura = MeshInstance3D.new()
		_pu_aura.mesh = Scenery.sphere(1.15, 8 if cheap_aura else 14, 5 if cheap_aura else 8)
		_pu_aura.position = Vector3(0, 1.0, 0)
		_pu_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_pu_aura)
	var cols: Array[Color] = [Color(1.0, 0.85, 0.12), Color(0.35, 0.95, 0.4), Color(0.3, 0.85, 1.0), Color(1.0, 0.45, 0.15), Color(0.9, 0.25, 0.9)]
	var col := cols[clampi(type, 0, 4)]
	_pu_aura.visible = true
	var cheap_aura := SettingsManager != null and int(SettingsManager.get_setting("graphics_preset")) == SettingsManager.PRESET_POTATO
	if type == SHIELD_PU and not cheap_aura:
		_pu_aura.material_override = _shield_material(col)
	else:
		# POTATO: every aura (shield included) keeps the cheap translucent look
		# instead of the animated emission / swirl shaders.
		_pu_aura.material_override = Scenery.mat(col, 0.3, true, 0.3)
	if _pu_field != null and is_instance_valid(_pu_field):
		_pu_field.queue_free()
		_pu_field = null
	if type == MAGNET_PU:
		_pu_field = MeshInstance3D.new()
		_pu_field.mesh = Scenery.torus(MAGNET_RANGE - 0.12, MAGNET_RANGE, 40, 4)
		_pu_field.material_override = Scenery.mat(col, 0.16, true, 0.3) if cheap_aura else _magnet_material(col)
		_pu_field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_pu_field.position = Vector3(0, 0.06, 0)
		add_child(_pu_field)
	if is_local:
		GameManager.vibrate(30)


func clear_powerup() -> void:
	if _pu_field != null and is_instance_valid(_pu_field):
		_pu_field.queue_free()
	_pu_field = null
	_pu_type = -1
	_pu_time = 0.0
	if _pu_aura != null and is_instance_valid(_pu_aura):
		_pu_aura.queue_free()
	_pu_aura = null
	if round_manager != null:
		for p in round_manager.players.values():
			p._magnet_candidates_stale = true


func _tick_powerup(delta: float) -> void:
	if _pu_time <= 0.0:
		return
	_pu_time -= delta
	if _pu_time <= 0.0 or not is_alive:
		clear_powerup()
	else:
		# Intensify shield pulse and magnet swirl as the power-up nears expiry.
		var urgency = clamp((2.0 - _pu_time) / 2.0, 0.0, 1.0)
		if _pu_type == SHIELD_PU and _pu_aura != null and is_instance_valid(_pu_aura):
			var mat := _pu_aura.material_override
			if mat is ShaderMaterial:
				mat.set_shader_parameter("pulse_amount", 0.35 + urgency * 0.25)
				mat.set_shader_parameter("emission_strength", 4.0 + urgency * 3.0)
		elif _pu_type == MAGNET_PU and _pu_field != null and is_instance_valid(_pu_field):
			var mat := _pu_field.material_override
			if mat is ShaderMaterial:
				mat.set_shader_parameter("swirl_speed", 3.0 + urgency * 2.0)
				mat.set_shader_parameter("emission_strength", 4.0 + urgency * 3.0)
		# Blink the aura in the last two seconds, whatever the power-up is.
		if _pu_time < 2.0 and _pu_aura != null and is_instance_valid(_pu_aura):
			_pu_aura.visible = int(_pu_time * 6.0) % 2 == 0


static var _puff_mesh_cache: Mesh = null

func _puff_mesh() -> Mesh:
	if _puff_mesh_cache != null:
		return _puff_mesh_cache
	var s := Scenery.sphere(0.12, 6, 3)
	# Cheap default material: _spawn_burst overrides it with the burst shader
	# only when effects are allowed (via material_override, not mesh surgery,
	# because the mesh is shared). vertex_color_use_as_albedo lets
	# CPUParticles3D.color tint each particle (the shader reads the same COLOR).
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1, 0.85)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	s.material = m
	_puff_mesh_cache = s
	return s
