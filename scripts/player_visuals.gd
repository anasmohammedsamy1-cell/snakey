extends Node3D
## Original low-poly cartoon character assembled from primitive meshes
## (round head, bean body, arms, legs, shoes, eyes, cheeks, smile, antenna).
## Animated procedurally: idle, walk, run, jump, fall, land, push, victory.
## Works standalone (menu / preview) or as the "Visuals" child of player.tscn.
## FRONT of the character = -Z (face, belly, toes, rubber arm all point to -Z, the walking direction).

const Scenery := preload("res://scripts/scenery.gd")
const PropsLib := preload("res://scripts/props.gd")

enum Anim { IDLE, WALK, RUN, JUMP, FALL, LAND, PUSH, VICTORY, DASH, HUG, MELT }

var state: int = Anim.IDLE
var move_speed_factor := 0.0        # 0 = slow walk, 1 = full run
var demo_mode := false              # cycles animations by itself (menus)
var demo_spin := false

var _time := 0.0
var _land_timer := 0.0
var _push_timer := 0.0
var _hit_timer := 0.0
var _victory_spin := 0.0
var _dash_timer := 0.0
var _hug_timer := 0.0
var _hug_total := 1.0
var _melt_timer := 0.0
var _melt_total := 1.0
var melted := false                 # true once the melt animation finished (a puddle is left)
var hold_pose := false              # holding somebody over the head
var hanging := false                # being held by somebody (dangling)
var charge := 0.0                   # local wind-up while the attack button is held (0..1)
var prop_node: Node3D = null        # hide-and-seek disguise
var team_ring: MeshInstance3D = null
var _water_mat: StandardMaterial3D = null

# Rubber arm (real 3D geometry: a stretchy cylinder + fist, driven by a small state machine)
enum ArmPhase { NONE, EXTEND, HOLD, RETRACT }
const ARM_EXTEND_TIME := 0.16
const ARM_RETRACT_TIME := 0.30
const ARM_HOLD_UNCONFIRMED := 0.28   # a grab that the host did not confirm retracts by itself
const ARM_HOLD_FAILSAFE := 2.4
var arm_root: Node3D
var arm_seg_pivot: Node3D
var arm_fist: MeshInstance3D
var _arm_phase: int = ArmPhase.NONE
var _arm_mode := 0
var _arm_t := 0.0
var _arm_len := 0.0
var _arm_goal := 0.0
var _arm_from := 0.0
var _arm_hold_t := 0.0
var _arm_confirmed := false
var _demo_timer := 0.0
var _demo_index := 0
var _color := Color(1.0, 0.85, 0.12)

var _body_mat: StandardMaterial3D
var _accent_mat: StandardMaterial3D

var pivot: Node3D
var body: MeshInstance3D
var head: MeshInstance3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var _built := false


func _ready() -> void:
	if not _built:
		build(_color)


func build(color: Color) -> void:
	for c in get_children():
		c.queue_free()
	prop_node = null
	team_ring = null
	melted = false
	_melt_timer = 0.0
	_hug_timer = 0.0
	_built = true
	_color = color
	_body_mat = Scenery.dup_material(Scenery.mat(color, 0.55)) as StandardMaterial3D
	_accent_mat = Scenery.dup_material(Scenery.mat(color.lightened(0.4), 0.6)) as StandardMaterial3D
	var dark := Scenery.mat(Color(0.12, 0.1, 0.16), 0.5)
	var white := Scenery.mat(Color(1, 1, 1), 0.4)
	var pink := Scenery.mat(Color(1.0, 0.55, 0.65), 0.8)
	var shoe := Scenery.mat(color.darkened(0.45), 0.6)

	pivot = Node3D.new()
	pivot.name = "Pivot"
	add_child(pivot)

	# Body (bean)
	body = Scenery.mesh_instance(Scenery.capsule(0.36, 0.95), _body_mat, Vector3(0, 0.86, 0))
	body.name = "Body"
	pivot.add_child(body)
	var belly := Scenery.mesh_instance(Scenery.sphere(0.27, 14, 7), _accent_mat, Vector3(0, 0.78, -0.2))
	belly.scale = Vector3(1.0, 1.25, 0.45)
	pivot.add_child(belly)

	# Head
	head = Scenery.mesh_instance(Scenery.sphere(0.35, 18, 10), _body_mat, Vector3(0, 1.5, 0))
	head.name = "Head"
	pivot.add_child(head)
	# Eyes
	for side in [-1.0, 1.0]:
		var eye := Scenery.mesh_instance(Scenery.sphere(0.09, 12, 6), white, Vector3(0.13 * side, 1.56, -0.29), false)
		eye.scale = Vector3(1.0, 1.15, 0.6)
		head.add_child(eye)
		eye.position -= head.position
		var pupil := Scenery.mesh_instance(Scenery.sphere(0.045, 10, 5), dark, Vector3(0.13 * side, 1.56, -0.345), false)
		head.add_child(pupil)
		pupil.position -= head.position
		var cheek := Scenery.mesh_instance(Scenery.sphere(0.06, 10, 5), pink, Vector3(0.22 * side, 1.46, -0.25), false)
		cheek.scale = Vector3(1.0, 0.6, 0.4)
		head.add_child(cheek)
		cheek.position -= head.position
	# Smile
	var mouth := Scenery.mesh_instance(Scenery.box(Vector3(0.16, 0.035, 0.03)), dark, Vector3(0, 1.41, -0.33), false)
	head.add_child(mouth)
	mouth.position -= head.position
	# Antenna with coloured ball: a recognisable silhouette
	var stem := Scenery.mesh_instance(Scenery.cylinder(0.025, 0.025, 0.18, 6), dark, Vector3(0, 1.92, 0), false)
	head.add_child(stem)
	stem.position -= head.position
	var ball := Scenery.mesh_instance(Scenery.sphere(0.075, 10, 5), _accent_mat, Vector3(0, 2.03, 0), false)
	head.add_child(ball)
	ball.position -= head.position

	# Arms
	arm_l = _make_limb(Vector3(-0.4, 1.18, 0), 0.1, 0.46, _body_mat, _accent_mat, true)
	arm_r = _make_limb(Vector3(0.4, 1.18, 0), 0.1, 0.46, _body_mat, _accent_mat, true)
	# Legs
	leg_l = _make_limb(Vector3(-0.16, 0.48, 0), 0.115, 0.42, _body_mat, shoe, false)
	leg_r = _make_limb(Vector3(0.16, 0.48, 0), 0.115, 0.42, _body_mat, shoe, false)

	# Rubber arm: hidden until an attack starts. -Z is "forward".
	_arm_phase = ArmPhase.NONE
	_arm_len = 0.0
	arm_root = Node3D.new()
	arm_root.name = "RubberArm"
	arm_root.position = Vector3(0.4, 1.18, -0.05)
	arm_root.visible = false
	pivot.add_child(arm_root)
	arm_seg_pivot = Node3D.new()
	arm_root.add_child(arm_seg_pivot)
	var seg := Scenery.mesh_instance(Scenery.cylinder(0.09, 0.09, 1.0, 10), _body_mat, Vector3(0, 0, -0.5), false)
	seg.rotation_degrees = Vector3(90, 0, 0)
	arm_seg_pivot.add_child(seg)
	arm_fist = Scenery.mesh_instance(Scenery.sphere(0.17, 12, 6), _accent_mat, Vector3.ZERO, false)
	arm_root.add_child(arm_fist)


func _make_limb(origin: Vector3, radius: float, length: float, limb_mat: Material, tip_mat: Material, is_arm: bool) -> Node3D:
	var joint := Node3D.new()
	joint.position = origin
	pivot.add_child(joint)
	var limb := Scenery.mesh_instance(Scenery.capsule(radius, length), limb_mat, Vector3(0, -length * 0.5, 0))
	joint.add_child(limb)
	if is_arm:
		var hand := Scenery.mesh_instance(Scenery.sphere(radius * 1.25, 10, 5), tip_mat, Vector3(0, -length - radius * 0.3, 0))
		joint.add_child(hand)
	else:
		var foot := Scenery.mesh_instance(Scenery.sphere(radius * 1.3, 10, 5), tip_mat, Vector3(0, -length - radius * 0.2, -0.05))
		foot.scale = Vector3(1.0, 0.55, 1.5)
		joint.add_child(foot)
	return joint


func set_color(color: Color) -> void:
	_color = color
	if _body_mat:
		_body_mat.albedo_color = color
	if _accent_mat:
		_accent_mat.albedo_color = color.lightened(0.4)


# ---------------------------------------------------------------------------
# Animation API

func set_state(new_state: int) -> void:
	state = new_state


func play_land() -> void:
	_land_timer = 0.25


func play_push() -> void:
	_push_timer = 0.35


func play_hit() -> void:
	_hit_timer = 0.3


func play_dash() -> void:
	_dash_timer = 0.2


func is_dashing() -> bool:
	return _dash_timer > 0.0


## Arms up, hugging somebody, for `duration` seconds (the seeker in hide and seek).
func play_hug(duration: float) -> void:
	_hug_total = maxf(duration, 0.2)
	_hug_timer = _hug_total


## The hider reveals itself and melts into a puddle of water over `duration` seconds.
func play_melt(duration: float) -> void:
	clear_disguise()
	_melt_total = maxf(duration, 0.2)
	_melt_timer = _melt_total
	melted = false
	if pivot == null:
		return
	if _water_mat == null:
		_water_mat = Scenery.dup_material(Scenery.mat(Color(0.3, 0.65, 1.0), 0.15, false, 0.82)) as StandardMaterial3D
		_water_mat.metallic = 0.2
		_water_mat.emission_enabled = true
		_water_mat.emission = Color(0.1, 0.3, 0.6)
	_apply_to_meshes(pivot, _water_mat)


func _apply_to_meshes(node: Node, material: Material) -> void:
	for c in node.get_children():
		if c is MeshInstance3D and c != arm_fist:
			(c as MeshInstance3D).material_override = material
		_apply_to_meshes(c, material)


func is_hugging() -> bool:
	return _hug_timer > 0.0


## Hide and seek disguise: the character disappears and a piece of furniture takes its place.
func set_disguise(prop_id: int) -> void:
	clear_disguise()
	if pivot == null:
		return
	prop_node = PropsLib.build(prop_id)
	add_child(prop_node)
	pivot.visible = false
	if arm_root != null:
		arm_root.visible = false
	if team_ring != null:
		team_ring.visible = false


func clear_disguise() -> void:
	if prop_node != null and is_instance_valid(prop_node):
		prop_node.queue_free()
	prop_node = null
	if pivot != null:
		pivot.visible = true
	if team_ring != null:
		team_ring.visible = true


func is_disguised() -> bool:
	return prop_node != null and is_instance_valid(prop_node)


## Coloured ring under the feet marks the team (all game modes with teams).
func set_team_ring(color: Color) -> void:
	if team_ring != null and is_instance_valid(team_ring):
		team_ring.queue_free()
	team_ring = MeshInstance3D.new()
	var torus := Scenery.torus(0.5, 0.66, 24, 6)
	team_ring.mesh = torus
	team_ring.material_override = Scenery.mat(color, 0.4, true)
	team_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	team_ring.position = Vector3(0, 0.05, 0)
	add_child(team_ring)
	if is_disguised():
		team_ring.visible = false


## Start a rubber-arm strike. mode 0 = punch (extends then snaps back),
## mode 1 = grab (extends then holds until confirm_grab()/release_arm()).
func start_arm(mode: int, length: float, pitch := 0.0) -> void:
	if arm_root == null:
		return
	_arm_mode = mode
	_arm_goal = maxf(length, 0.6)
	_arm_t = 0.0
	_arm_hold_t = 0.0
	_arm_confirmed = false
	_arm_phase = ArmPhase.EXTEND
	arm_root.rotation.x = pitch
	arm_root.visible = true
	if arm_r != null:
		arm_r.visible = false
	if arm_fist != null:
		var fm := arm_fist.mesh as SphereMesh
		if fm != null:
			fm.radius = 0.2 if mode == 1 else 0.17


func confirm_grab() -> void:
	_arm_confirmed = true


func set_grab_length(length: float) -> void:
	if _arm_phase == ArmPhase.HOLD:
		_arm_goal = maxf(length, 0.4)


func release_arm() -> void:
	if _arm_phase == ArmPhase.EXTEND or _arm_phase == ArmPhase.HOLD:
		_begin_retract()


func is_arm_active() -> bool:
	return _arm_phase != ArmPhase.NONE


func _begin_retract() -> void:
	_arm_phase = ArmPhase.RETRACT
	_arm_t = 0.0
	_arm_from = _arm_len


func _update_arm(delta: float) -> void:
	if _arm_phase == ArmPhase.NONE or arm_root == null:
		return
	match _arm_phase:
		ArmPhase.EXTEND:
			_arm_t += delta / ARM_EXTEND_TIME
			var k := clampf(_arm_t, 0.0, 1.0)
			var c1 := 1.70158
			var c3 := c1 + 1.0
			var e := 1.0 + c3 * pow(k - 1.0, 3.0) + c1 * pow(k - 1.0, 2.0)   # ease-out-back: elastic overshoot
			_arm_len = _arm_goal * e
			if k >= 1.0:
				if _arm_mode == 1:
					_arm_phase = ArmPhase.HOLD
					_arm_hold_t = 0.0
				else:
					_begin_retract()
		ArmPhase.HOLD:
			_arm_hold_t += delta
			_arm_len = lerpf(_arm_len, _arm_goal, 1.0 - exp(-18.0 * delta))
			if (not _arm_confirmed and _arm_hold_t > ARM_HOLD_UNCONFIRMED) or _arm_hold_t > ARM_HOLD_FAILSAFE:
				_begin_retract()
		ArmPhase.RETRACT:
			_arm_t += delta / ARM_RETRACT_TIME
			var k2 := clampf(_arm_t, 0.0, 1.0)
			var v := 1.0 - k2
			_arm_len = maxf(0.0, _arm_from * (v * v + 0.12 * sin(k2 * PI * 3.0) * v))
			if k2 >= 1.0:
				_arm_phase = ArmPhase.NONE
				_arm_len = 0.0
				arm_root.visible = false
				if arm_r != null:
					arm_r.visible = true
				return
	arm_seg_pivot.scale = Vector3(1.0, 1.0, maxf(_arm_len, 0.01))
	arm_fist.position = Vector3(0, 0, -_arm_len)
	# Thin the arm slightly while it is stretched (rubber look).
	var thin := clampf(1.0 - _arm_len * 0.06, 0.55, 1.0)
	arm_seg_pivot.scale.x = thin
	arm_seg_pivot.scale.y = thin


## Animation id that should be replicated to other peers.
func get_net_anim() -> int:
	if _dash_timer > 0.0:
		return Anim.DASH
	if _push_timer > 0.0:
		return Anim.PUSH
	if _land_timer > 0.15:
		return Anim.LAND
	return state


## Apply an animation id received from the network.
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
				AudioManager.play_character("jump", 0.08, -12.0)
			state = anim


func _process(delta: float) -> void:
	if pivot == null:
		return
	_time += delta
	_land_timer = maxf(0.0, _land_timer - delta)
	_push_timer = maxf(0.0, _push_timer - delta)
	_hit_timer = maxf(0.0, _hit_timer - delta)
	_dash_timer = maxf(0.0, _dash_timer - delta)
	_hug_timer = maxf(0.0, _hug_timer - delta)
	if _melt_timer > 0.0:
		_melt_timer = maxf(0.0, _melt_timer - delta)
		if _melt_timer <= 0.0:
			melted = true
	_update_arm(delta)
	if demo_mode:
		_update_demo(delta)

	var t := _time
	var arm_l_a := 0.0
	var arm_r_a := 0.0
	var arm_side := 0.12            # arms slightly away from the body (z rotation)
	var leg_l_a := 0.0
	var leg_r_a := 0.0
	var bob := 0.0
	var lean := 0.0
	var target_scale := Vector3.ONE
	var head_tilt := 0.0
	var spin_speed := 0.0

	match state:
		Anim.IDLE:
			# A proudly wobbly bean: little squash-bounces and an antenna-like head bob.
			bob = sin(t * 3.1) * 0.035
			arm_l_a = sin(t * 2.7) * 0.12
			arm_r_a = -sin(t * 2.7 + 0.7) * 0.12
			head_tilt = sin(t * 1.8) * 0.1
			target_scale = Vector3(1.0 + sin(t * 3.1) * 0.025, 1.0 + sin(t * 3.1 + 0.8) * 0.035, 1.0)
		Anim.WALK, Anim.RUN:
			var f := clampf(move_speed_factor, 0.0, 1.0)
			var freq := lerpf(7.0, 12.5, f)
			var amp := lerpf(0.58, 1.18, f)
			var swing := sin(t * freq)
			leg_l_a = swing * amp
			leg_r_a = -swing * amp
			arm_l_a = -swing * amp * 0.9
			arm_r_a = swing * amp * 0.9
			bob = absf(cos(t * freq)) * lerpf(0.035, 0.12, f)
			lean = lerpf(0.08, 0.28, f) + sin(t * freq * 0.5) * 0.08
			head_tilt = sin(t * freq) * 0.16
		Anim.JUMP:
			arm_l_a = 3.1
			arm_r_a = 3.1
			arm_side = 0.85
			leg_l_a = 1.0 + sin(t * 13.0) * 0.18
			leg_r_a = -0.75 - sin(t * 13.0) * 0.18
			head_tilt = sin(t * 12.0) * 0.18
			target_scale = Vector3(0.86, 1.2, 0.86)
		Anim.FALL:
			arm_l_a = 2.4 + sin(t * 16.0) * 0.35
			arm_r_a = 2.4 - sin(t * 16.0) * 0.35
			arm_side = 0.7
			leg_l_a = 0.5 + sin(t * 12.0) * 0.4
			leg_r_a = -0.5 - sin(t * 12.0) * 0.4
			target_scale = Vector3(0.95, 1.05, 0.95)
		Anim.VICTORY:
			bob = absf(sin(t * 6.5)) * 0.28
			arm_l_a = 2.8 + sin(t * 9.0) * 0.3
			arm_r_a = 2.8 - sin(t * 9.0) * 0.3
			arm_side = 0.6
			leg_l_a = sin(t * 6.5) * 0.4
			leg_r_a = -sin(t * 6.5) * 0.4
			spin_speed = 4.0
			head_tilt = sin(t * 4.0) * 0.15
		_:
			pass

	# Overlays (push / land / hit) win over the base pose.
	if _push_timer > 0.0:
		var k := _push_timer / 0.35
		var thrust := sin(k * PI)
		# Wind up, launch the fist, then recoil like the punch surprised its owner.
		arm_r_a = (2.2 if k > 0.55 else -0.25) * thrust + 0.2
		arm_l_a = -0.9 * thrust
		lean += (0.48 if k > 0.55 else -0.28) * thrust
		head_tilt += sin(t * 26.0) * 0.12 * thrust
		target_scale = Vector3(1.0 + 0.12 * thrust, 1.0 - 0.14 * thrust, 1.0 + 0.08 * thrust)
	if _dash_timer > 0.0:
		lean += 0.55
		target_scale = Vector3(0.85, 0.85, 1.3)
		arm_l_a = -1.2
		arm_r_a = -1.2
		leg_l_a = 0.9
		leg_r_a = -0.9
	if hold_pose:
		arm_l_a = 2.9 + sin(t * 8.0) * 0.12
		arm_r_a = 2.9 - sin(t * 8.0) * 0.12
		arm_side = 0.25
	if hanging:
		arm_l_a = 2.9 + sin(t * 14.0) * 0.65
		arm_r_a = 2.9 - sin(t * 14.0) * 0.65
		arm_side = 0.75
		leg_l_a = sin(t * 12.0) * 0.72
		leg_r_a = -sin(t * 12.0) * 0.72
		head_tilt = sin(t * 8.0) * 0.3
		lean = sin(t * 7.0) * 0.12
	if charge > 0.02 and _push_timer <= 0.0:
		# Wind-up: the punching arm goes back, the body squashes a little.
		arm_r_a = -1.4 * charge
		arm_l_a = 0.5 * charge
		lean -= 0.12 * charge
		target_scale = Vector3(1.0 + 0.06 * charge, 1.0 - 0.08 * charge, 1.0 + 0.06 * charge)
	if _hug_timer > 0.0:
		# Raise both arms, then wrap them around and squeeze (funny hug).
		var hk := 1.0 - _hug_timer / _hug_total
		if hk < 0.3:
			var up := hk / 0.3
			arm_l_a = 2.9 * up
			arm_r_a = 2.9 * up
			arm_side = 0.5
		else:
			var squeeze := 0.5 + 0.5 * sin((hk - 0.3) * 24.0)
			arm_l_a = 1.45
			arm_r_a = 1.45
			arm_side = 0.9 + 0.35 * squeeze
			target_scale = Vector3(1.0 + 0.05 * squeeze, 1.0 - 0.06 * squeeze, 1.0 + 0.05 * squeeze)
		lean += 0.15
	if _melt_timer > 0.0 or melted:
		# Melt into a flat puddle of water.
		var mk := 1.0
		if _melt_timer > 0.0:
			mk = 1.0 - _melt_timer / _melt_total
		var melt_e := pow(mk, 1.6)
		target_scale = Vector3(1.0 + 0.9 * melt_e, maxf(0.06, 1.0 - 0.95 * melt_e), 1.0 + 0.9 * melt_e)
		arm_l_a = 0.0
		arm_r_a = 0.0
		leg_l_a = 0.0
		leg_r_a = 0.0
		lean = 0.0
		bob = 0.0
	if _land_timer > 0.0:
		var k2 := _land_timer / 0.25
		target_scale = Vector3(1.0 + 0.22 * k2, 1.0 - 0.25 * k2, 1.0 + 0.22 * k2)
	if _hit_timer > 0.0:
		var k3 := _hit_timer / 0.3
		head_tilt += sin(t * 40.0) * 0.25 * k3
		lean -= 0.3 * k3

	var blend := 1.0 - exp(-14.0 * delta)
	arm_l.rotation.x = lerp_angle(arm_l.rotation.x, arm_l_a, blend)
	arm_r.rotation.x = lerp_angle(arm_r.rotation.x, arm_r_a, blend)
	arm_l.rotation.z = lerp_angle(arm_l.rotation.z, arm_side, blend)
	arm_r.rotation.z = lerp_angle(arm_r.rotation.z, -arm_side, blend)
	leg_l.rotation.x = lerp_angle(leg_l.rotation.x, leg_l_a, blend)
	leg_r.rotation.x = lerp_angle(leg_r.rotation.x, leg_r_a, blend)
	head.rotation.z = lerp_angle(head.rotation.z, head_tilt, blend)
	pivot.position.y = lerpf(pivot.position.y, bob, blend)
	pivot.rotation.x = lerp_angle(pivot.rotation.x, -lean, blend)
	pivot.scale = pivot.scale.lerp(target_scale, 1.0 - exp(-(30.0 if (_melt_timer > 0.0 or melted) else 14.0) * delta))
	if spin_speed > 0.0 or demo_spin:
		_victory_spin += delta * (spin_speed if spin_speed > 0.0 else 0.8)
		pivot.rotation.y = _victory_spin
	else:
		_victory_spin = 0.0
		pivot.rotation.y = lerp_angle(pivot.rotation.y, 0.0, blend)


func _update_demo(delta: float) -> void:
	_demo_timer -= delta
	if _demo_timer <= 0.0:
		_demo_timer = randf_range(2.0, 3.5)
		_demo_index = (_demo_index + 1) % 4
		match _demo_index:
			0:
				state = Anim.IDLE
			1:
				state = Anim.RUN
				move_speed_factor = 1.0
			2:
				state = Anim.VICTORY
			_:
				state = Anim.WALK
				move_speed_factor = 0.3
