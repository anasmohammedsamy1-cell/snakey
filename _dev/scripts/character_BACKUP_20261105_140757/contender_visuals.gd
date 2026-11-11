extends Node3D
 
## Drop-in replacement for the old primitive-mesh player visuals.
##
## The rendered character is the Blender contender GLB.  Its visible Skeleton3D
## is driven exclusively by the physical ragdoll bodies; a hidden Skeleton3D +
## AnimationTree produces the desired pose that feeds the PD joint motors.
## Gameplay keeps using its existing CharacterBody3D authority.

const MODEL_SCENE := preload("res://NewAssets/Model/contender.glb")
const Scenery := preload("res://scripts/scenery.gd")
const PropsLib := preload("res://scripts/props.gd")
const PoseRigScript := preload("res://scripts/character/contender_pose_rig.gd")
const RagdollScript := preload("res://scripts/character/contender_ragdoll.gd")

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
	// The body atlas is neutral white.  Select its bright, low-saturation islands
	// so the paint can replace the whole shell while the warm scratches, eye
	// cream, dark pupils, bolts and purple parts keep their own colours.
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

const HAND_GRIP_LOCAL := Vector3(0.0, 0.22, 0.0)
const CARRY_CHEST_OFFSET := 0.98
const CARRY_OVERHEAD_OFFSET := Vector3(0.12, 2.55, 0.04)
const THROW_WINDUP_TIME := 0.12
const THROW_RELEASE_TIME := 0.30
const THROW_FOLLOW_TIME := 0.48

enum Anim { IDLE, WALK, RUN, JUMP, FALL, LAND, PUSH, VICTORY, DASH, HUG, MELT }
enum ArmPhase { NONE, EXTEND, HOLD, RETRACT }

const ARM_EXTEND_TIME := 0.16
const ARM_RETRACT_TIME := 0.30
const ARM_HOLD_UNCONFIRMED := 0.28
const ARM_HOLD_FAILSAFE := 2.4
const MODEL_YAW := PI

var state: int = Anim.IDLE
var move_speed_factor := 0.0
var grabbing_id := 0
var grab_phase := 0
var demo_mode := false
var demo_spin := false
var melted := false
var hold_pose := false:
	set(value):
		hold_pose = value
var hanging := false:
	set(value):
		hanging = value
var charge := 0.0
var prop_node: Node3D = null
var team_ring: MeshInstance3D = null

var model_root: Node3D
var skeleton: Skeleton3D
var pose_rig: ContenderPoseRig
var ragdoll: ContenderRagdoll

var _built := false
var _local := true
var _quality := 1
var _time := 0.0
var _land_timer := 0.0
var _push_timer := 0.0
var _hit_timer := 0.0
var _dash_timer := 0.0
var _hug_timer := 0.0
var _hug_total := 1.0
var _melt_timer := 0.0
var _melt_total := 1.0
var _demo_timer := 0.0
var _demo_index := 0
var _victory_spin := 0.0
var _color := Color(1.0, 0.85, 0.12)
var _mesh_instances: Array[MeshInstance3D] = []
var _recolor_materials: Array[ShaderMaterial] = []
var _team_color := Color(0, 0, 0, 0)
var _sim_check := 0.0
var _arm_world_from := Vector3.ZERO
var _arm_world_goal := Vector3.ZERO
var _arm_side := "Hand_R"
var _throwing := false
var _throw_active := false
var _throw_released := false
var _throw_t := 0.0
var _throw_origin := Vector3.ZERO
var _hand_bone_ids: Dictionary = {}
var _balance_timer := 0.0
var _balance_state := "stumble"
var speed_mps := 0.0
var _last_speed := 0.0
var _last_yaw := 0.0

static var _recolor_shader: Shader

var _arm_phase: int = ArmPhase.NONE
var _arm_mode := 0
var _arm_t := 0.0
var _arm_len := 0.0
var _arm_goal := 0.0
var _arm_from := 0.0
var _arm_hold_t := 0.0
var _arm_confirmed := false
var _upper_loop := ""


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
	mesh_fade_reset()
	_built = true
	_color = color
	_time = 0.0
	_land_timer = 0.0
	_push_timer = 0.0
	_hit_timer = 0.0
	_dash_timer = 0.0
	_hug_timer = 0.0
	_melt_timer = 0.0
	_arm_phase = ArmPhase.NONE
	_arm_len = 0.0
	_upper_loop = ""
	_throwing = false
	_throw_active = false
	_throw_released = false
	_throw_t = 0.0
	_balance_timer = 0.0
	speed_mps = 0.0
	_last_speed = 0.0
	_last_yaw = 0.0

	model_root = MODEL_SCENE.instantiate() as Node3D
	if model_root == null:
		push_error("ContenderVisuals: could not instantiate contender.glb")
		return
	model_root.name = "ContenderModel"
	model_root.rotation.y = MODEL_YAW
	add_child(model_root)
	skeleton = model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		push_error("ContenderVisuals: Skeleton3D missing from contender.glb")
		return
	_hand_bone_ids.clear()
	for side in ["L", "R"]:
		_hand_bone_ids["Hand_" + side] = skeleton.find_bone("Hand_" + side)
	_collect_meshes()
	_apply_tint()

	pose_rig = PoseRigScript.new()
	pose_rig.name = "PoseRig"
	add_child(pose_rig)
	pose_rig.build(skeleton)

	ragdoll = RagdollScript.new()
	ragdoll.name = "Ragdoll"
	add_child(ragdoll)
	ragdoll.setup(skeleton, pose_rig, _local)
	ragdoll.quality = _quality
	ragdoll.landed.connect(_on_ragdoll_landed)

	if _team_color.a > 0.01:
		set_team_ring(_team_color)
	_apply_simulation_mode()


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
	# Every character owns its ShaderMaterial instances, so repainting one player
	# never touches another player's model.
	for mat in _recolor_materials:
		if is_instance_valid(mat):
			mat.set_shader_parameter("body_color", _color)


func set_move_speed(value: float) -> void:
	speed_mps = maxf(value, 0.0)
	if team_ring != null and _team_color.a > 0.01:
		set_team_ring(_team_color)


func set_local_character(value: bool) -> void:
	_local = value
	if ragdoll != null:
		ragdoll.is_local_character = value
	_apply_simulation_mode()


func set_quality(level: int) -> void:
	_quality = clampi(level, 0, 2)
	if ragdoll != null:
		ragdoll.set_quality(_quality)
	_apply_simulation_mode()


# ---------------------------------------------------------------------------
# Animation API

func set_state(new_state: int) -> void:
	var previous := state
	state = new_state
	if new_state == Anim.JUMP and previous != Anim.JUMP:
		if ragdoll != null:
			ragdoll.apply_jump()
	if new_state == Anim.VICTORY and _upper_loop != "victory":
		_play_loop("victory")
	elif new_state != Anim.VICTORY and _upper_loop == "victory":
		_stop_loop()


func play_land(speed := 0.0) -> void:
	_land_timer = 0.25
	if ragdoll != null:
		ragdoll.apply_landing(speed)
	if speed > 9.0:
		play_balance("stumble", 0.38)


func play_push() -> void:
	_push_timer = 0.35
	if pose_rig != null and pose_rig.upper_action != "punch":
		pose_rig.play_upper("punch", false)


## The carry arm sweeps through a real wind-up, release and follow-through arc.
## The gameplay release happens at THROW_RELEASE_TIME; the hand keeps moving
## afterwards instead of snapping back.
func play_throw() -> void:
	_throwing = true
	_throw_active = true
	_throw_released = false
	_throw_t = 0.0
	_arm_phase = ArmPhase.NONE
	_arm_len = 0.0
	hold_pose = false
	_stop_loop()
	if pose_rig != null:
		_arm_side = pose_rig.get_carry_hand()
		_throw_origin = get_grab_hand_transform().origin
		pose_rig.play_upper("throw", false)
		pose_rig.set_reach_target(_throw_origin, _arm_side)


func finish_throw() -> void:
	_throwing = false
	_throw_released = true


func play_balance(balance_state: String, duration: float) -> void:
	if balance_state not in ["stop", "turn", "stumble"]:
		return
	_balance_state = balance_state
	_balance_timer = maxf(_balance_timer, duration)


func _update_throw(delta: float) -> void:
	if not _throw_active:
		return
	_throw_t += delta
	var fwd := Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
	var right := Vector3(cos(rotation.y), 0.0, -sin(rotation.y))
	var side_offset := right * (0.16 if _arm_side == "Hand_L" else -0.16)
	var wind := global_position - fwd * 0.10 + Vector3.UP * 2.00 + side_offset
	var release := global_position + fwd * 0.95 + Vector3.UP * 1.95 + side_offset * 0.7
	var follow := global_position + fwd * 1.15 + Vector3.UP * 1.35 + side_offset * 0.4
	var point := _throw_origin
	if _throw_t < THROW_WINDUP_TIME:
		var k := smoothstep(0.0, THROW_WINDUP_TIME, _throw_t)
		point = _throw_origin.lerp(wind, k)
	elif _throw_t < THROW_RELEASE_TIME:
		var k := smoothstep(THROW_WINDUP_TIME, THROW_RELEASE_TIME, _throw_t)
		point = wind.lerp(release, k)
	elif _throw_t < THROW_FOLLOW_TIME:
		var k := smoothstep(THROW_RELEASE_TIME, THROW_FOLLOW_TIME, _throw_t)
		point = release.lerp(follow, k)
	if pose_rig != null:
		pose_rig.set_reach_target(point, _arm_side)
	if _throw_t >= THROW_FOLLOW_TIME:
		_throw_active = false
		_throw_released = true
		if pose_rig != null:
			pose_rig.clear_reach_target()


func play_hit() -> void:
	_hit_timer = 0.3
	if pose_rig != null:
		pose_rig.play_upper("hit", false)


func play_dash() -> void:
	_dash_timer = 0.2
	if pose_rig != null:
		pose_rig.stop_upper()


func is_dashing() -> bool:
	return _dash_timer > 0.0


func play_hug(duration: float) -> void:
	_hug_total = maxf(duration, 0.2)
	_hug_timer = _hug_total
	_play_loop("hug")


func is_hugging() -> bool:
	return _hug_timer > 0.0


func play_melt(duration: float) -> void:
	clear_disguise()
	_melt_total = maxf(duration, 0.2)
	_melt_timer = _melt_total
	melted = false
	if ragdoll != null:
		ragdoll.set_melted(true)


func _update_melt(delta: float) -> void:
	if _melt_timer <= 0.0 and not melted:
		return
	if _melt_timer > 0.0:
		_melt_timer = maxf(0.0, _melt_timer - delta)
		if _melt_timer <= 0.0:
			melted = true
	var k := 1.0
	if _melt_timer > 0.0:
		k = 1.0 - _melt_timer / _melt_total
	var e := pow(clampf(k, 0.0, 1.0), 1.6)
	var scale := Vector3(1.0 + 0.9 * e, maxf(0.06, 1.0 - 0.94 * e), 1.0 + 0.9 * e)
	if model_root != null:
		model_root.scale = scale
	if pose_rig != null:
		pose_rig.scale = scale


func mesh_fade_reset() -> void:
	melted = false
	_melt_timer = 0.0
	if model_root != null:
		model_root.scale = Vector3.ONE
	if pose_rig != null:
		pose_rig.scale = Vector3.ONE


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
	_apply_simulation_mode()


func clear_disguise() -> void:
	if prop_node != null and is_instance_valid(prop_node):
		prop_node.queue_free()
	prop_node = null
	if model_root != null:
		model_root.visible = true
	if team_ring != null:
		team_ring.visible = true
	_apply_simulation_mode()


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
# Real-hand reach: the selected original arm/hand bones are aimed by the pose rig.
func start_arm(mode: int, length: float, pitch := 0.0, target_world := Vector3.ZERO) -> void:
	_arm_mode = mode
	_arm_goal = maxf(length, 0.6)
	_arm_t = 0.0
	_arm_hold_t = 0.0
	_arm_confirmed = false
	_arm_phase = ArmPhase.EXTEND
	_throwing = false
	_throw_active = false
	_throw_released = false
	_throw_t = 0.0
	var forward := Vector3(-sin(global_rotation.y), 0.0, -cos(global_rotation.y))
	_arm_world_goal = target_world if target_world != Vector3.ZERO else global_position + forward * _arm_goal + Vector3.UP * 1.15
	_arm_side = pose_rig.choose_reach_hand(_arm_world_goal) if pose_rig != null else "Hand_R"
	_arm_world_from = get_grab_hand_transform().origin
	if pose_rig != null:
		pose_rig.set_reach_target(_arm_world_from, _arm_side)
		var action := "grab" if mode == 1 else "punch"
		if pose_rig.upper_action != action:
			pose_rig.play_upper(action, false)


func confirm_grab() -> void:
	_arm_confirmed = true


func set_grab_target(world_point: Vector3) -> void:
	if _arm_phase == ArmPhase.EXTEND or _arm_phase == ArmPhase.HOLD:
		_arm_world_goal = world_point


## Grip point in the middle of the real glove, along the hand bone.  This is the
## only attachment point used by grabbing and carrying; no extra hand mesh is
## created anywhere.
func get_grab_hand_transform() -> Transform3D:
	if skeleton == null:
		return Transform3D(Basis.IDENTITY, global_position)
	var hand_name := pose_rig.get_reach_hand() if pose_rig != null else _arm_side
	var id: int = _hand_bone_ids.get(hand_name, -1)
	if id < 0:
		return Transform3D(Basis.IDENTITY, global_position)
	return skeleton.global_transform * skeleton.get_bone_global_pose(id) * Transform3D(Basis.IDENTITY, HAND_GRIP_LOCAL)


## Root position that puts the carried player's chest in the real hand.
func get_grab_hold_position() -> Vector3:
	return get_grab_hand_transform().origin - Vector3.UP * CARRY_CHEST_OFFSET


func get_grab_hand_name() -> String:
	return _arm_side


func release_arm() -> void:
	if _arm_phase == ArmPhase.EXTEND or _arm_phase == ArmPhase.HOLD:
		if _arm_phase == ArmPhase.HOLD and not _arm_confirmed:
			play_balance("stop", 0.22)
		_arm_phase = ArmPhase.RETRACT
		_arm_t = 0.0
		_arm_from = _arm_len
	if _upper_loop == "grab":
		_stop_loop()


func is_arm_active() -> bool:
	return _arm_phase != ArmPhase.NONE


func _begin_retract() -> void:
	_arm_phase = ArmPhase.RETRACT
	_arm_t = 0.0
	_arm_from = _arm_len


## Drives the real hand bones through the pose rig so the grabbed character is
## always held by the Contender's actual hand, moving with shoulder + elbow.
func _update_arm(delta: float) -> void:
	if _throw_active or _arm_phase == ArmPhase.NONE:
		return
	if _arm_phase == ArmPhase.EXTEND:
		_arm_t += delta / ARM_EXTEND_TIME
		var k := clampf(_arm_t, 0.0, 1.0)
		var c1 := 1.70158
		var c3 := c1 + 1.0
		var e := 1.0 + c3 * pow(k - 1.0, 3.0) + c1 * pow(k - 1.0, 2.0)
		_arm_len = _arm_goal * e
		var reach := 1.0 - pow(1.0 - k, 3.0)
		if pose_rig != null:
			pose_rig.set_reach_target(_arm_world_from.lerp(_arm_world_goal, reach), _arm_side)
		if k >= 1.0:
			if _arm_mode == 1:
				_arm_phase = ArmPhase.HOLD
				_arm_hold_t = 0.0
			else:
				_arm_phase = ArmPhase.NONE
				_arm_len = 0.0
				if pose_rig != null:
					pose_rig.clear_reach_target()
	elif _arm_phase == ArmPhase.HOLD:
		_arm_hold_t += delta
		_arm_len = lerpf(_arm_len, _arm_goal, 1.0 - exp(-18.0 * delta))
		if pose_rig != null:
			pose_rig.set_reach_target(_arm_world_goal, _arm_side)
		if (not _arm_confirmed and _arm_hold_t > ARM_HOLD_UNCONFIRMED) or _arm_hold_t > ARM_HOLD_FAILSAFE:
			_begin_retract()
	elif _arm_phase == ArmPhase.RETRACT:
		_arm_t += delta / ARM_RETRACT_TIME
		var k2 := clampf(_arm_t, 0.0, 1.0)
		var v := 1.0 - k2
		_arm_len = maxf(0.0, _arm_from * (v * v + 0.12 * sin(k2 * PI * 3.0) * v))
		if pose_rig != null:
			pose_rig.set_reach_target(_arm_world_goal.lerp(_arm_world_from, k2 * k2), _arm_side)
		if k2 >= 1.0:
			_arm_phase = ArmPhase.NONE
			_arm_len = 0.0
			if pose_rig != null:
				pose_rig.clear_reach_target()


# ---------------------------------------------------------------------------
# Frame update

func _process(delta: float) -> void:
	if not _built:
		return
	_time += delta
	_land_timer = maxf(0.0, _land_timer - delta)
	_push_timer = maxf(0.0, _push_timer - delta)
	_hit_timer = maxf(0.0, _hit_timer - delta)
	_dash_timer = maxf(0.0, _dash_timer - delta)
	_hug_timer = maxf(0.0, _hug_timer - delta)
	if _hug_timer <= 0.0 and _upper_loop == "hug":
		_stop_loop()
	_update_arm(delta)
	_update_throw(delta)
	_update_balance(delta)
	_update_melt(delta)
	if demo_mode:
		_update_demo(delta)
	if demo_spin:
		_victory_spin += delta * 0.8
		rotation.y = _victory_spin
	_apply_pose_state()
	_sim_check -= delta
	if _sim_check <= 0.0:
		_sim_check = 0.35
		_apply_simulation_mode()


func _update_balance(delta: float) -> void:
	_balance_timer = maxf(0.0, _balance_timer - delta)
	var yaw_rate := absf(angle_difference(_last_yaw, rotation.y)) / maxf(delta, 0.0001)
	if _balance_timer <= 0.0:
		if _last_speed > 5.0 and speed_mps < 0.8:
			play_balance("stop", 0.26)
		elif yaw_rate > 9.0 and speed_mps > 1.5:
			play_balance("turn", 0.28)
	_last_speed = speed_mps
	_last_yaw = rotation.y


func _apply_pose_state() -> void:
	if pose_rig == null:
		return
	var base := "idle"
	if demo_mode:
		match state:
			Anim.WALK: base = "walk"
			Anim.RUN: base = "run"
			Anim.VICTORY: base = "victory"
			_: base = "idle"
	elif _dash_timer > 0.0:
		base = "dash"
	elif _land_timer > 0.0:
		base = "land"
	else:
		match state:
			Anim.WALK: base = "walk"
			Anim.RUN: base = "run"
			Anim.JUMP: base = "jump"
			Anim.FALL: base = "fall"
			Anim.VICTORY: base = "victory"
			_: base = "idle"
	var limp := ragdoll != null and ragdoll.is_ragdolled()
	if ragdoll != null and ragdoll.is_recovering():
		base = "recover"
	var carrying := grabbing_id != 0 and grab_phase == 1
	var carry_controlled := carrying and not _throwing and not limp
	if ragdoll != null and ragdoll.is_recovering():
		carry_controlled = false
	if _balance_timer > 0.0 and not carrying and not limp and base in ["idle", "walk", "run", "sprint"]:
		base = _balance_state
	pose_rig.set_locomotion(base, move_speed_factor, limp)
	pose_rig.set_charge(charge)
	pose_rig.set_carrying(carry_controlled, move_speed_factor, _arm_side, 1.0)
	if ragdoll != null:
		ragdoll.set_carrying_pose(carry_controlled, _arm_side, 1.0)
	if carry_controlled:
		var forward := Vector3(-sin(global_rotation.y), 0.0, -cos(global_rotation.y))
		var right := Vector3(cos(global_rotation.y), 0.0, -sin(global_rotation.y))
		var side := 1.0 if _arm_side == "Hand_L" else -1.0
		var overhead := global_position + forward * CARRY_OVERHEAD_OFFSET.x + Vector3.UP * CARRY_OVERHEAD_OFFSET.y + right * (CARRY_OVERHEAD_OFFSET.z * side)
		pose_rig.set_reach_target(overhead, _arm_side)
	elif _arm_phase == ArmPhase.NONE and not _throw_active and grabbing_id == 0:
		pose_rig.clear_reach_target()
	pose_rig.set_hold_pose(hold_pose and not _throwing)
	pose_rig.set_hanging(hanging)
	# Persistent loop actions are driven by gameplay flags, not by per-frame
	# calls, so an action is never restarted mid-swing.
	if hanging:
		if _upper_loop != "held":
			_play_loop("held")
	elif hold_pose:
		if _upper_loop != "hold":
			_play_loop("hold")
	elif _upper_loop in ["held", "hold"]:
		_stop_loop()


func _play_loop(action: String) -> void:
	_upper_loop = action
	if pose_rig != null:
		pose_rig.play_upper(action, true)


func _stop_loop() -> void:
	if _upper_loop == "":
		return
	if _upper_loop in ["hug", "grab"]:
		pose_rig.stop_upper()
	if _upper_loop in ["victory", "held", "hold"]:
		pose_rig.stop_upper()
	_upper_loop = ""


func _apply_simulation_mode() -> void:
	if ragdoll == null or not ragdoll.is_built():
		return
	var simulate := false
	if not demo_mode and not melted and _melt_timer <= 0.0 and not is_disguised():
		if _local:
			simulate = true
		else:
			var distance := 999.0
			var cam := get_viewport().get_camera_3d()
			if cam != null:
				distance = cam.global_position.distance_to(global_position)
			if _quality >= 2 and distance < 22.0:
				simulate = true
			elif _quality >= 1 and distance < 11.0:
				simulate = true
	ragdoll.set_simulation_enabled(simulate)


func _on_ragdoll_landed(speed: float) -> void:
	if speed > 2.0:
		_land_timer = 0.25


func _update_demo(delta: float) -> void:
	_demo_timer -= delta
	if _demo_timer <= 0.0:
		_demo_timer = randf_range(2.0, 3.5)
		_demo_index = (_demo_index + 1) % 4
		match _demo_index:
			0:
				state = Anim.IDLE
				move_speed_factor = 0.0
			1:
				state = Anim.RUN
				move_speed_factor = 1.0
			2:
				state = Anim.VICTORY
				_play_loop("victory")
			_:
				state = Anim.WALK
				move_speed_factor = 0.3
				_stop_loop()


# ---------------------------------------------------------------------------
# Networking

func get_net_anim() -> int:
	if _dash_timer > 0.0:
		return Anim.DASH
	if _push_timer > 0.0:
		return Anim.PUSH
	if _land_timer > 0.15:
		return Anim.LAND
	return state


func apply_net_anim(anim: int) -> void:
	match anim:
		Anim.DASH:
			if _dash_timer <= 0.0:
				play_dash()
		Anim.PUSH:
			if _push_timer <= 0.0:
				play_push()
		Anim.LAND:
			if _land_timer <= 0.0:
				play_land()
			state = Anim.IDLE
		_:
			if anim == Anim.JUMP and state != Anim.JUMP:
				var audio := get_node_or_null("/root/AudioManager")
				if audio and audio.has_method("play_character"):
					audio.call("play_character", "jump", 0.08, -12.0)
			set_state(anim)


# ---------------------------------------------------------------------------
# Gameplay hooks used by player_controller.gd

func apply_impact(impulse: Vector3, world_point := Vector3.ZERO, strength := 1.0) -> void:
	if ragdoll == null:
		return
	if world_point == Vector3.ZERO:
		world_point = global_position + Vector3(0, 1.0, 0)
	ragdoll.apply_impact(impulse * 0.42, world_point, strength)
	_hit_timer = 0.3
	if strength > 1.0:
		play_balance("stumble", 0.30)


func apply_spin(axis: Vector3, strength: float) -> void:
	if ragdoll != null:
		ragdoll.apply_spin(axis, strength)


func reset_visual_state() -> void:
	clear_disguise()
	state = Anim.IDLE
	move_speed_factor = 0.0
	_land_timer = 0.0
	_push_timer = 0.0
	_hit_timer = 0.0
	_dash_timer = 0.0
	_hug_timer = 0.0
	_melt_timer = 0.0
	melted = false
	hold_pose = false
	hanging = false
	charge = 0.0
	_arm_phase = ArmPhase.NONE
	_arm_len = 0.0
	_upper_loop = ""
	_throwing = false
	_throw_active = false
	_throw_released = false
	_throw_t = 0.0
	_balance_timer = 0.0
	speed_mps = 0.0
	_last_speed = 0.0
	_last_yaw = 0.0
	set_grab_state(0, 0)
	if pose_rig != null:
		pose_rig.clear_reach_target()
		pose_rig.set_carrying(false)
	if model_root != null:
		model_root.scale = Vector3.ONE
	if pose_rig != null:
		pose_rig.scale = Vector3.ONE
	if ragdoll != null:
		ragdoll.reset_pose()
	if pose_rig != null:
		pose_rig.stop_upper()


func set_held(value: bool) -> void:
	if ragdoll != null:
		ragdoll.set_held(value)


func set_grab_tether(point: Vector3, strength := 14.0) -> void:
	if ragdoll != null:
		ragdoll.set_tether(point, strength)


func set_grab_state(holding_id: int, phase: int) -> void:
	grabbing_id = holding_id
	grab_phase = phase
	hold_pose = holding_id != 0 and phase == 1
	if holding_id != 0 and pose_rig != null:
		_arm_side = pose_rig.get_carry_hand()
	if hold_pose and pose_rig != null:
		var forward := Vector3(-sin(global_rotation.y), 0.0, -cos(global_rotation.y))
		var right := Vector3(cos(global_rotation.y), 0.0, -sin(global_rotation.y))
		var side := 1.0 if _arm_side == "Hand_L" else -1.0
		var overhead := global_position + forward * CARRY_OVERHEAD_OFFSET.x + Vector3.UP * CARRY_OVERHEAD_OFFSET.y + right * (CARRY_OVERHEAD_OFFSET.z * side)
		pose_rig.set_carrying(true, move_speed_factor, _arm_side, 1.0)
		pose_rig.set_reach_target(overhead, _arm_side)
		if ragdoll != null:
			ragdoll.set_carrying_pose(true, _arm_side, 1.0)
	elif holding_id == 0 and pose_rig != null:
		pose_rig.set_carrying(false)
		pose_rig.clear_reach_target()
		if ragdoll != null:
			ragdoll.set_carrying_pose(false, "")


func clear_grab_tether() -> void:
	if ragdoll != null:
		ragdoll.clear_tether()


func get_ragdoll() -> ContenderRagdoll:
	return ragdoll


func get_visible_skeleton() -> Skeleton3D:
	return skeleton
