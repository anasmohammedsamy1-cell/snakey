extends Node3D
class_name ContenderVisuals
## Visual wrapper for the Blender contender GLB.
## Loads the model, applies the colour tint and drives the ORIGINAL skeleton with
## ContenderAnimator (procedural full-body animation: IK gait, grab/lift/carry/throw,
## punches, hits, tumble).  The parent CharacterBody3D stays the only physics object.

const MODEL_SCENE := preload("res://NewAssets/Model/contender.glb")
const Scenery := preload("res://scripts/scenery.gd")
const PropsLib := preload("res://scripts/props.gd")

const RECOLOR_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
uniform bool use_normal = false;
uniform float normal_scale = 1.0;
uniform vec4 body_color : source_color = vec4(1.0, 0.85, 0.12, 1.0);
uniform float recolor_strength = 1.0;
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
	ALBEDO = mix(source.rgb, recolored, neutral * recolor_strength);
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	if (use_normal) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
}
"""

const MODEL_YAW := PI

var model_root: Node3D
var skeleton: Skeleton3D
var _built := false
var _color := Color(1.0, 0.85, 0.12)
var _mesh_instances: Array[MeshInstance3D] = []
var _recolor_materials: Array[ShaderMaterial] = []
var _team_color := Color(0, 0, 0, 0)
var prop_node: Node3D = null
var team_ring: MeshInstance3D = null
var animator: ContenderAnimator = null
var demo_mode := false        # customisation-menu preview: idle animation
var demo_spin := false        # customisation-menu preview: slow turntable rotation

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


func _ready() -> void:
	if not _built:
		build(_color)


func build(color: Color) -> void:
	if _built:
		set_color(color)
		return
	for c in get_children():
		c.queue_free()
	prop_node = null
	team_ring = null
	_built = true
	_color = color

	model_root = MODEL_SCENE.instantiate() as Node3D
	if model_root == null:
		push_error("ContenderVisuals: could not instantiate contender.glb")
		return
	model_root.name = "ContenderModel"
	model_root.rotation.y = MODEL_YAW
	add_child(model_root)
	skeleton = model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	_collect_meshes()
	_apply_tint()
	animator = ContenderAnimator.new()
	if not animator.build(skeleton):
		animator = null
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


func set_color(color: Color) -> void:
	_color = color
	for mat in _recolor_materials:
		if is_instance_valid(mat):
			mat.set_shader_parameter("body_color", _color)


func set_move_speed(_value: float) -> void:
	# Speed is derived from the real position delta inside _process (works for the
	# owner, host bots and remote puppets alike).
	pass


func set_local_character(_value: bool) -> void:
	pass


func set_quality(_level: int) -> void:
	pass


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
	# One cheap ground ray per physics tick (shared by every animation decision).
	var p := get_parent() as CharacterBody3D
	if p == null or _ray == null or not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return
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
	if animator == null or delta <= 0.0 or model_root == null or not model_root.visible:
		return
	if demo_spin:
		rotation.y += delta * 0.8
	var p := get_parent() as CharacterBody3D
	if p == null:
		# Menu / customisation preview: plain idle animation.
		animator.in_grounded = true
		animator.in_ground_y = global_position.y
		animator.update(delta)
		return
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
	a.update(delta)


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
