extends Node3D
class_name ContenderVisuals
## Visual wrapper for the Blender contender GLB.
## Loads the model, applies the colour tint and drives the ORIGINAL skeleton with
## ContenderAnimator (procedural full-body animation: IK gait, grab/lift/carry/throw,
## punches, hits, tumble).  The parent CharacterBody3D stays the only physics object.

const MODEL_SCENE := preload("res://NewAssets/Model/contender.glb")
const FaceScript := preload("res://scripts/character/contender_face.gd")
const AccessoriesLib := preload("res://scripts/accessories.gd")
const Scenery := preload("res://scripts/scenery.gd")
const PropsLib := preload("res://scripts/props.gd")
const GameConstants := preload("res://scripts/game_constants.gd")
const OUTLINE_SHADER := preload("res://assets/shaders/outline.gdshader")

const RECOLOR_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
uniform bool use_normal = false;
uniform float normal_scale = 1.0;
uniform vec4 body_color : source_color = vec4(1.0, 0.85, 0.12, 1.0);
uniform float recolor_strength = 1.0;
uniform float body_saturation = 1.35;
uniform vec4 detail_color : source_color = vec4(0.72, 0.75, 0.8, 1.0);
uniform float detail_strength = 1.0;
uniform float metallic = 0.0;
uniform float roughness = 0.7;
uniform float specular = 0.5;

void fragment() {
	vec4 source = texture(albedo_texture, UV);
	float maxc = max(source.r, max(source.g, source.b));
	float minc = min(source.r, min(source.g, source.b));
	float saturation = (maxc - minc) / max(maxc, 0.0001);
	float neutral = smoothstep(0.84, 0.98, maxc)
		* (1.0 - smoothstep(0.06, 0.18, saturation));
	float luminance = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
	float shade = clamp(luminance / 0.92, 0.15, 1.15);
	vec3 recolored = body_color.rgb * (0.45 + 0.75 * shade);
	// Vibrance: push the tinted colour away from grey so the player colour reads
	// stronger (white parts stay white, mid tones gain chroma).
	vec3 albedo = mix(source.rgb, recolored, neutral * recolor_strength);
	float albedo_lum = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
	albedo = mix(vec3(albedo_lum), albedo, body_saturation);
	// Detail: dark, desaturated pixels are the screws, gaps and seams of the metal
	// body. Tint them with the player's detail colour (shaded so they keep depth).
	float metal = smoothstep(0.42, 0.25, luminance) * (1.0 - smoothstep(0.10, 0.25, saturation));
	vec3 detail = detail_color.rgb * (0.62 + 0.38 * shade);
	albedo = mix(albedo, detail, clamp(metal * detail_strength, 0.0, 1.0));
	ALBEDO = clamp(albedo, vec3(0.0), vec3(1.0));
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	if (use_normal) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
}
// Quantise diffuse lighting into three soft smoothstep bands.
// Keeps the existing recolor logic and all uniforms intact.
void light() {
	// three soft steps: dark / mid / bright band via smoothstep transitions.
	// LIGHT is the light vector in view space (see the Godot 4 light() built-ins).
	float ndotl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float band = mix(
		smoothstep(-roughness, roughness * 0.5, ndotl),
		smoothstep(roughness * 0.5, roughness, ndotl),
		smoothstep(-roughness, roughness, ndotl)
	);
	DIFFUSE_LIGHT = vec3(band) * LIGHT_COLOR * ATTENUATION / PI;
}
"""

const MODEL_YAW := PI

var model_root: Node3D
var skeleton: Skeleton3D
var hat_node: Node3D                   # accessory on the head bone (see accessories.gd)
var hat_id := ""
var face: Node3D                      # cartoon face (eyes + mouth) on the head bone
var _built := false
var _color := Color(1.0, 0.85, 0.12)
var _detail_color := GameConstants.DEFAULT_DETAIL_COLOR
var _mesh_instances: Array[MeshInstance3D] = []
var _recolor_materials: Array[ShaderMaterial] = []
var _team_color := Color(0, 0, 0, 0)
var prop_node: Node3D = null
var team_ring: MeshInstance3D = null
var animator: ContenderAnimator = null
var demo_mode := false        # customisation-menu preview: idle animation
var demo_spin := false        # customisation-menu preview: slow turntable rotation
var TOON_ENABLED := true       # toggle toon look & outline (MEDIUM/HIGH presets only)

# ---- distance / visibility animation LOD ----------------------------------
const LOD_LOCAL := 0
const LOD_NEAR := 1
const LOD_DISTANT := 2
const LOD_OFFSCREEN := 3
const NEAR_DISTANCE := 12.0
const FAR_DISTANCE := 28.0
const LOD_CHECK_INTERVAL := 0.20
const POSE_BONES := ["Torso", "Head", "Arm_L", "Arm_R", "Hand_L", "Hand_R", "Leg_L", "Leg_R", "Foot_L", "Foot_R"]

var animation_lod := LOD_LOCAL
var _quality := -1
var _is_local_character := true
var _scheduler_driven := false
var _lod_check_accum := 0.0
var _lod_initialized := false
var _anim_update_interval := 1.0 / 60.0
var _face_accum := 0.0
var _face_updates := 0
var _ground_queries := 0
var _pose_ids: PackedInt32Array = PackedInt32Array()
var _pose_from_pos: Array[Vector3] = []
var _pose_from_rot: Array[Quaternion] = []
var _pose_from_scale: Array[Vector3] = []
var _pose_to_pos: Array[Vector3] = []
var _pose_to_rot: Array[Quaternion] = []
var _pose_to_scale: Array[Vector3] = []
var _pose_t := 1.0
var _pose_dur := 0.0

var _last_pos := Vector3.ZERO
var _have_last := false
var _vel_s := Vector3.ZERO
var _grounded := true
var _ground_y := 0.0
var _ray: PhysicsRayQueryParameters3D
var _hit_counter := 0
var _hit_strength := 0
var _net_hit_seen := 0
var _net_dash := false

static var _recolor_shader: Shader
static var _outline_material: ShaderMaterial


func _ready() -> void:
	if SettingsManager != null and not SettingsManager.settings_changed.is_connected(_on_graphics_setting_changed):
		SettingsManager.settings_changed.connect(_on_graphics_setting_changed)
	if not _built:
		build(_color)
	CharacterAnimation.register_visual(self, _is_local_character)


func _exit_tree() -> void:
	CharacterAnimation.unregister_visual(self)


func build(color: Color, detail_color: Color = GameConstants.DEFAULT_DETAIL_COLOR) -> void:
	if _built:
		set_color(color)
		set_detail_color(detail_color)
		return
	for c in get_children():
		c.queue_free()
	prop_node = null
	team_ring = null
	_built = true
	_color = color
	_detail_color = detail_color

	model_root = MODEL_SCENE.instantiate() as Node3D
	if model_root == null:
		push_error("ContenderVisuals: could not instantiate contender.glb")
		return
	model_root.name = "ContenderModel"
	model_root.rotation.y = MODEL_YAW
	add_child(model_root)
	skeleton = model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	_init_pose_cache()
	_collect_meshes()
	_apply_tint()
	animator = ContenderAnimator.new()
	if not animator.build(skeleton):
		animator = null
	face = FaceScript.new()
	if not face.build(skeleton):
		face.free()
		face = null
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collision_mask = 1

	if _team_color.a > 0.01:
		set_team_ring(_team_color)


func _collect_meshes() -> void:
	_mesh_instances.clear()
	_recolor_materials.clear()
	for node in model_root.find_children("*", "MeshInstance3D", true, false):
		_mesh_instances.append(node as MeshInstance3D)


func _apply_tint() -> void:
	_recolor_materials.clear()
	if _recolor_shader == null:
		_recolor_shader = Shader.new()
		_recolor_shader.code = RECOLOR_SHADER
	var shader := _recolor_shader
	for mi in _mesh_instances:
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i)
			if mat is StandardMaterial3D:
				var source := mat as StandardMaterial3D
				var recolor := ShaderMaterial.new()
				recolor.shader = shader
				recolor.set_shader_parameter("albedo_texture", source.albedo_texture)
				recolor.set_shader_parameter("body_color", _color)
				recolor.set_shader_parameter("detail_color", _detail_color)
				recolor.set_shader_parameter("metallic", source.metallic)
				recolor.set_shader_parameter("roughness", source.roughness)
				recolor.set_shader_parameter("specular", source.metallic_specular)
				var use_normal := source.normal_enabled and source.normal_texture != null
				recolor.set_shader_parameter("use_normal", use_normal)
				if use_normal:
					recolor.set_shader_parameter("normal_texture", source.normal_texture)
					recolor.set_shader_parameter("normal_scale", source.normal_scale)
				mi.set_surface_override_material(i, recolor)
				_recolor_materials.append(recolor)
				# Optional toon outline: one shared inverted-hull pass behind every recolor.
				# Skipped on the LOW preset (and fully off when TOON_ENABLED is false).
				recolor.set_next_pass(_outline_pass())


## The single shared outline pass (inverted hull, dark colour).  Returns null when
## the toon look is disabled or on the LOW preset, in which case the recolor
## material renders by itself exactly as before.
func _outline_pass() -> ShaderMaterial:
	if not TOON_ENABLED or _effective_quality() <= 0:
		return null
	if _outline_material == null:
		_outline_material = ShaderMaterial.new()
		_outline_material.shader = OUTLINE_SHADER
		_outline_material.set_shader_parameter("outline_width", 1.0)
	return _outline_material


## Puts an accessory on the head ("" removes it). Needs the head bone, so it is a no-op when the model has no skeleton.
func set_hat(id: String) -> void:
	hat_id = id if AccessoriesLib.is_valid(id) else ""
	if hat_node != null and is_instance_valid(hat_node):
		hat_node.visible = false
		hat_node.queue_free()
	hat_node = null
	_apply_hat_quality()


func _apply_hat_quality() -> void:
	var potato_remote := SettingsManager != null \
		and int(SettingsManager.get_setting("graphics_preset")) == SettingsManager.PRESET_POTATO \
		and not _is_local_character and not demo_mode
	if potato_remote:
		if hat_node != null and is_instance_valid(hat_node):
			hat_node.visible = false
			hat_node.queue_free()
			hat_node = null
		return
	if hat_id.is_empty() or skeleton == null or skeleton.find_bone("Head") < 0:
		return
	if hat_node != null and is_instance_valid(hat_node):
		return
	var attach := BoneAttachment3D.new()
	attach.name = "HatAttachment"
	attach.bone_name = "Head"
	skeleton.add_child(attach)
	var item := AccessoriesLib.build(hat_id)
	item.position = Vector3.ZERO
	attach.add_child(item)
	hat_node = attach


func set_color(color: Color) -> void:
	_color = color
	for mat in _recolor_materials:
		if is_instance_valid(mat):
			mat.set_shader_parameter("body_color", _color)


## Screws, gaps and seams colour (the detail slots of the metal body).
func set_detail_color(color: Color) -> void:
	_detail_color = color
	for mat in _recolor_materials:
		if is_instance_valid(mat):
			mat.set_shader_parameter("detail_color", _detail_color)


func set_move_speed(_value: float) -> void:
	# Speed is derived from the real position delta inside _process (works for the
	# owner, host bots and remote puppets alike).
	pass


func set_local_character(value: bool) -> void:
	_is_local_character = value
	_scheduler_driven = not value and not demo_mode
	animation_lod = LOD_LOCAL if value or demo_mode else LOD_DISTANT
	_pose_t = 1.0
	if is_inside_tree():
		CharacterAnimation.set_local(self, value)
	_apply_animation_quality()
	_apply_hat_quality()


func set_quality(level: int) -> void:
	_quality = clampi(level, 0, 2)
	for mat in _recolor_materials:
		if is_instance_valid(mat):
			mat.set_next_pass(_outline_pass())
	_apply_animation_quality()
	_apply_hat_quality()
	if _scheduler_driven:
		_lod_initialized = false


func _on_graphics_setting_changed(key: String, _value: Variant) -> void:
	if key == "graphics_preset":
		set_quality(_quality_from_settings())


func _quality_from_settings() -> int:
	if SettingsManager == null:
		return 2
	match int(SettingsManager.get_setting("graphics_preset")):
		SettingsManager.PRESET_LOW:
			return 0
		SettingsManager.PRESET_POTATO:
			return 0    # identical character teardown to LOW; extra cuts live in the LOD policy
		SettingsManager.PRESET_HIGH:
			return 2
		_:
			return 1


func _effective_quality() -> int:
	return _quality if _quality >= 0 else _quality_from_settings()


func _apply_animation_quality() -> void:
	if animator != null:
		# The local player and the menu preview keep the full procedural pose:
		# only remote cosmetic animation is simplified by the LOW preset.
		var q := 2 if (_is_local_character or demo_mode) else _effective_quality()
		animator.set_quality(q)


# ---------------------------------------------------------------------------
# Disguise / team ring

func set_disguise(prop_id: int) -> void:
	clear_disguise()
	prop_node = PropsLib.build(prop_id)
	add_child(prop_node)
	if model_root != null:
		model_root.visible = false
	if team_ring != null:
		team_ring.visible = false


func clear_disguise() -> void:
	if prop_node != null and is_instance_valid(prop_node):
		prop_node.queue_free()
	prop_node = null
	if model_root != null:
		model_root.visible = true
	if team_ring != null:
		team_ring.visible = true


func is_disguised() -> bool:
	return prop_node != null and is_instance_valid(prop_node)


func set_team_ring(color: Color) -> void:
	_team_color = color
	if team_ring != null and is_instance_valid(team_ring):
		team_ring.queue_free()
	team_ring = MeshInstance3D.new()
	team_ring.name = "TeamRing"
	var torus := Scenery.torus(0.52, 0.68, 24, 6)
	team_ring.mesh = torus
	team_ring.material_override = Scenery.mat(color, 0.4, true)
	team_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	team_ring.position = Vector3(0, 0.05, 0)
	add_child(team_ring)
	if is_disguised():
		team_ring.visible = false


# ---------------------------------------------------------------------------
# Animation driver

func _physics_process(_delta: float) -> void:
	# The local player keeps the per-physics-tick ground sample. Remotes sample
	# the same ray from their scheduled cosmetic tick instead, so all their
	# gameplay physics still runs at the normal rate without a duplicate ray.
	if _scheduler_driven:
		return
	_sample_ground()


func _sample_ground() -> void:
	var p := get_parent() as CharacterBody3D
	if p == null or _ray == null or not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	_ground_queries += 1
	var o := p.global_position
	_ray.from = o + Vector3(0.0, 0.45, 0.0)
	_ray.to = o + Vector3(0.0, -0.32, 0.0)
	var r := space.intersect_ray(_ray)
	if r.is_empty():
		_grounded = false
	else:
		_grounded = true
		_ground_y = (r["position"] as Vector3).y


func _process(delta: float) -> void:
	if _scheduler_driven:
		# The shared scheduler owns animator updates for remotes. The only
		# per-frame work left here is cheap pose interpolation (and none at all
		# while the character is off-screen).
		if animation_lod != LOD_OFFSCREEN:
			_interpolate_remote_pose(delta)
		return
	_update_visual(delta, false)


## Called by CharacterAnimation for remote characters only. The elapsed time
## since the previous tick is passed to the animator, so state and animation
## time never lose time when the visual update rate drops.
func _scheduler_update_animation(elapsed: float) -> float:
	if animator == null or model_root == null or not model_root.visible:
		return 0.5
	_lod_check_accum += elapsed
	if not _lod_initialized or _lod_check_accum >= LOD_CHECK_INTERVAL:
		_lod_check_accum = 0.0
		_lod_initialized = true
		animation_lod = _classify_lod()
	# A holder's animator drives the carried victim's overhead anchor, which is
	# gameplay positioning, so keep that pose at the full update rate. The
	# distance LOD still applies to every other remote cosmetic update.
	var p := get_parent() as CharacterBody3D
	var gameplay_pose := p != null and int(p.get("grabbing_id")) != 0
	_anim_update_interval = (1.0 / 60.0) if gameplay_pose else _lod_interval(animation_lod)
	_update_visual(elapsed, true)
	return _anim_update_interval


func _classify_lod() -> int:
	if _is_local_character or demo_mode:
		return LOD_LOCAL
	var cam := get_viewport().get_camera_3d()
	var focus := global_position + Vector3(0.0, 1.0, 0.0)
	var dist := 0.0
	if cam != null:
		dist = cam.global_position.distance_to(focus)
		if dist > FAR_DISTANCE or not cam.is_position_in_frustum(focus):
			return LOD_OFFSCREEN
	return LOD_NEAR if dist <= NEAR_DISTANCE else LOD_DISTANT


func _lod_interval(lod: int) -> float:
	var q := _effective_quality()
	var potato := SettingsManager != null and int(SettingsManager.get_setting("graphics_preset")) == SettingsManager.PRESET_POTATO
	if potato:
		# Weakest remote cadence: near 10 Hz, distant 6 Hz, off-screen 2 Hz.
		match lod:
			LOD_NEAR:
				return 1.0 / 10.0
			LOD_DISTANT:
				return 1.0 / 6.0
			LOD_OFFSCREEN:
				return 1.0 / 2.0
			_:
				return 1.0 / 60.0
	match lod:
		LOD_NEAR:
			return 1.0 / (15.0 if q <= 0 else 30.0)
		LOD_DISTANT:
			return 1.0 / (8.0 if q <= 0 else 15.0)
		LOD_OFFSCREEN:
			return 1.0 / (3.0 if q <= 0 else (5.0 if q == 1 else 8.0))
		_:
			return 1.0 / 60.0


func _update_visual(delta: float, remote: bool) -> void:
	if animator == null or delta <= 0.0 or model_root == null or not model_root.visible:
		return
	if demo_spin:
		rotation.y += delta * 0.8
	var p := get_parent() as CharacterBody3D
	if p == null:
		# Menu / customisation preview: plain idle animation.
		animator.in_grounded = true
		animator.in_ground_y = global_position.y
		CharacterAnimation.note_visual_update()
		animator.update(delta)
		_update_face(delta, null)
		return
	if remote:
		_sample_ground()
	var pos := p.global_position
	if not _have_last:
		_last_pos = pos
		_have_last = true
	var raw := (pos - _last_pos) / delta
	_last_pos = pos
	if raw.length() > 60.0:
		raw = Vector3.ZERO          # teleport / respawn, not motion
		_vel_s = Vector3.ZERO
		animator.reset()
	_vel_s = _vel_s.lerp(raw, 1.0 - exp(-18.0 * delta))
	var pv := Vector3.ZERO
	if p.is_multiplayer_authority() and p.is_on_floor():
		pv = p.get_platform_velocity()
	var a: ContenderAnimator = animator
	a.in_vel_w = _vel_s - Vector3(pv.x, 0.0, pv.z)
	a.in_vy = _vel_s.y
	a.in_platform_vel = Vector3(pv.x, 0.0, pv.z)
	a.in_grounded = _grounded      # ray based: identical on owner, host bots and remote puppets
	if a.in_grounded:
		a.in_ground_y = _ground_y
	a.in_alive = bool(p.get("is_alive"))
	a.in_celebrating = bool(p.get("_celebrating"))
	a.in_holding = int(p.get("grabbing_id"))
	a.in_held_by = int(p.get("grabbed_by"))
	a.in_phase = int(p.get("grab_phase"))
	a.in_holder_pos_w = pos
	a.in_holder_yaw = rotation.y
	a.in_has_target = false
	var rm: Node = p.get("round_manager")
	if rm != null:
		if a.in_holding != 0:
			var victim: Node3D = rm.players.get(a.in_holding)
			if victim != null and is_instance_valid(victim):
				a.in_target_w = victim.global_position
				a.in_has_target = true
		if a.in_held_by != 0:
			var holder: Node = rm.players.get(a.in_held_by)
			if holder != null and is_instance_valid(holder) and holder.visuals != null:
				var ha: ContenderAnimator = holder.visuals.get("animator")
				if ha != null:
					a.in_holder_lift = ha.lift_p
	if remote:
		_capture_pose(false)
	else:
		CharacterAnimation.note_visual_update()
	a.update(delta, remote)
	if remote:
		_capture_pose(true)
		_pose_t = 0.0
		_pose_dur = maxf(_anim_update_interval, 1.0 / 120.0)
		_face_accum += delta
		var face_interval := _face_interval_for_lod()
		if face_interval >= 0.0 and (face_interval <= 0.0 or _face_accum >= face_interval):
			_update_face(minf(_face_accum, 0.5), p)
			_face_accum = 0.0
	else:
		_update_face(delta, p)


func _face_interval_for_lod() -> float:
	var q := _effective_quality()
	if SettingsManager != null and int(SettingsManager.get_setting("graphics_preset")) == SettingsManager.PRESET_POTATO:
		# Weakest faces: near 3 Hz updates, distant/off-screen faces frozen.
		match animation_lod:
			LOD_NEAR:
				return 0.30
			_:
				return -1.0
	match animation_lod:
		LOD_NEAR:
			return 0.0 if q > 0 else 0.20
		LOD_DISTANT:
			if q <= 0:
				return -1.0
			return 0.10 if q >= 2 else 0.20
		_:
			return -1.0


func _init_pose_cache() -> void:
	_pose_ids.clear()
	_pose_from_pos.clear()
	_pose_from_rot.clear()
	_pose_from_scale.clear()
	_pose_to_pos.clear()
	_pose_to_rot.clear()
	_pose_to_scale.clear()
	if skeleton == null:
		return
	for bone_name in POSE_BONES:
		var id := skeleton.find_bone(bone_name)
		if id < 0:
			continue
		_pose_ids.append(id)
		_pose_from_pos.append(Vector3.ZERO)
		_pose_from_rot.append(Quaternion.IDENTITY)
		_pose_from_scale.append(Vector3.ONE)
		_pose_to_pos.append(Vector3.ZERO)
		_pose_to_rot.append(Quaternion.IDENTITY)
		_pose_to_scale.append(Vector3.ONE)


## Snapshots the pose the animator is about to replace (false) or the new pose
## it just produced (true). Interpolating between the two removes the visual
## stepping of 30/15 Hz animation without re-running the expensive IK solve.
func _capture_pose(target: bool) -> void:
	if skeleton == null or _pose_ids.is_empty():
		return
	var dst_pos: Array[Vector3] = _pose_to_pos if target else _pose_from_pos
	var dst_rot: Array[Quaternion] = _pose_to_rot if target else _pose_from_rot
	var dst_scale: Array[Vector3] = _pose_to_scale if target else _pose_from_scale
	for i in _pose_ids.size():
		var id := _pose_ids[i]
		dst_pos[i] = skeleton.get_bone_pose_position(id)
		dst_rot[i] = skeleton.get_bone_pose_rotation(id)
		dst_scale[i] = skeleton.get_bone_pose_scale(id)


func _interpolate_remote_pose(delta: float) -> void:
	if skeleton == null or _pose_ids.is_empty() or _pose_dur <= 0.0 or _pose_t >= 1.0:
		return
	_pose_t = minf(1.0, _pose_t + delta / _pose_dur)
	var t := smoothstep(0.0, 1.0, _pose_t)
	for i in _pose_ids.size():
		var id := _pose_ids[i]
		skeleton.set_bone_pose_position(id, _pose_from_pos[i].lerp(_pose_to_pos[i], t))
		skeleton.set_bone_pose_rotation(id, _pose_from_rot[i].slerp(_pose_to_rot[i], t))
		skeleton.set_bone_pose_scale(id, _pose_from_scale[i].lerp(_pose_to_scale[i], t))


## Picks the facial expression from the player's state: surprised in the air, hurt when stunned, happy when celebrating.
func _update_face(delta: float, p: CharacterBody3D) -> void:
	if face == null or not is_instance_valid(face):
		return
	_face_updates += 1
	var mood := 0
	var look := Vector2.ZERO
	if p != null:
		if bool(p.get("_celebrating")):
			mood = 3
		elif float(p.get("_stun")) > 0.0:
			mood = 2
		elif not _grounded:
			mood = 1
		var lv := model_root.global_transform.basis.inverse() * _vel_s
		look = Vector2(clampf(lv.x * 0.25, -1.0, 1.0), clampf(_vel_s.y * 0.08, -1.0, 1.0))
	if face.has_method("set_quality"):
		face.set_quality(2 if not _scheduler_driven else _effective_quality())
	face.update(delta, mood, look)


## Anchor the carried victim's pelvis follows (world position of the victim's feet origin).
func get_grab_overhead_position() -> Vector3:
	var p := get_parent() as Node3D
	if animator == null or p == null:
		return Vector3.ZERO if p == null else p.global_position + Vector3(0.0, 2.55, 0.0)
	return animator.get_carry_origin_w(p.global_position, rotation.y)


func get_anim_state() -> StringName:
	return animator.state if animator != null else &"idle"


func play_punch(target_w := Vector3.ZERO, has_target := false, charge := 0.5) -> void:
	if animator != null:
		animator.trigger_punch(target_w, has_target, charge)


func play_grab(target_w := Vector3.ZERO, has_target := false) -> void:
	if animator != null:
		animator.trigger_grab(target_w, has_target)


func play_throw() -> void:
	if animator != null:
		animator.trigger_throw()


func play_hit(impulse: Vector3, strength := 0.6) -> void:
	_hit_counter = (_hit_counter + 1) & 3
	_hit_strength = clampi(int(round(strength * 2.0)), 0, 3)
	if animator != null:
		animator.trigger_hit(impulse, strength)


## Online hit-stop: freeze the visible pose for a short real-time window.
## Purely cosmetic; physics, movement and network replication keep running.
func freeze_animation(real_seconds: float) -> void:
	if animator != null:
		animator.freeze(real_seconds)


func on_grab_links(holding: int, held_by: int, phase: int) -> void:
	if animator == null:
		return
	var p := get_parent()
	if holding != 0 and p != null:
		# Use the victim's CURRENT position as the start of the lift so it never jumps.
		var rm: Node = p.get("round_manager")
		if rm != null:
			var victim: Node3D = rm.players.get(holding)
			if victim != null and is_instance_valid(victim):
				animator.in_target_w = victim.global_position
		animator.in_holder_pos_w = (p as Node3D).global_position
		animator.in_holder_yaw = rotation.y
	animator.on_grab_links(holding, held_by, phase)


# Network anim word: bits 4-5 hit counter, bits 6-7 hit strength (0..3 -> 0..1.5).
func get_net_anim() -> int:
	return (_hit_counter << 4) | (_hit_strength << 6)


func apply_net_anim(anim: int) -> void:
	var counter := (anim >> 4) & 3
	if counter != _net_hit_seen:
		_net_hit_seen = counter
		var strength := float((anim >> 6) & 3) * 0.5
		var d := Vector3(_vel_s.x, 0.0, _vel_s.z)
		if d.length() < 0.1:
			d = Vector3(0, 0, -1).rotated(Vector3.UP, rotation.y)
		if animator != null:
			animator.trigger_hit(d.normalized(), strength)


func apply_impact(impulse: Vector3, _world_point: Vector3 = Vector3.ZERO, strength: float = 1.0) -> void:
	play_hit(impulse, strength)


func apply_spin(_axis: Vector3, _strength: float) -> void:
	pass


func reset_visual_state() -> void:
	clear_disguise()
	if animator != null:
		animator.reset()
	_have_last = false
	if model_root != null:
		model_root.scale = Vector3.ONE


func set_held(_value: bool) -> void:
	pass


func set_grab_tether(_point: Vector3, _strength: float = 14.0) -> void:
	pass


func set_grab_state(_holding_id: int, _phase: int) -> void:
	pass


func clear_grab_tether() -> void:
	pass


func get_ragdoll() -> ContenderRagdoll:
	return null


func get_visible_skeleton() -> Skeleton3D:
	return skeleton
