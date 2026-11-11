extends Node3D
## Cartoon face for the contender: two eyes (with pupils that follow the movement), a mouth that changes with the
## situation (normal / surprised in the air / hurt after a hit / happy while celebrating) and random blinking.
## It is attached to the "Head" bone, so it nods and leans with the head animation and the ragdoll.
## Positions are in the model's own space (+Z = the front of the visor; the visor plate sits at z = 0.56).

const Scenery := preload("res://scripts/scenery.gd")

const HEAD_REST := Vector3(0.0, 1.359, -0.027)       # rest position of the Head bone in model space
const EYE_X := 0.17
const EYE_POS := Vector3(0.0, 1.765, 0.572)
const MOUTH_POS := Vector3(0.0, 1.64, 0.538)

var _eyes: Array[MeshInstance3D] = []
var _pupils: Array[MeshInstance3D] = []
var _mouth: MeshInstance3D
var _next_blink := 3.0
var _blink := 0.0
var _look := Vector2.ZERO
var _mouth_scale := Vector3(1.3, 0.28, 0.25)
var _eye_scale := Vector2(1.0, 1.0)
var quality := 2


## Returns false when the skeleton has no "Head" bone (the face is then simply not shown).
func build(skeleton: Skeleton3D) -> bool:
	if skeleton == null or skeleton.find_bone("Head") < 0:
		return false
	var attach := BoneAttachment3D.new()
	attach.name = "FaceAttachment"
	attach.bone_name = "Head"
	skeleton.add_child(attach)
	name = "Face"
	attach.add_child(self)
	_next_blink = randf_range(1.5, 5.0)
	var white := Scenery.mat(Color(1, 1, 1), 0.6, true)
	var black := Scenery.mat(Color(0.03, 0.03, 0.05), 0.6, true)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = Scenery.sphere(0.1, 10, 5)
		eye.material_override = white
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eye.position = EYE_POS + Vector3(side * EYE_X, 0.0, 0.0) - HEAD_REST
		eye.scale = Vector3(1.0, 1.15, 0.4)
		add_child(eye)
		_eyes.append(eye)
		var pupil := MeshInstance3D.new()
		pupil.mesh = Scenery.sphere(0.052, 8, 4)
		pupil.material_override = black
		pupil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pupil.scale = Vector3(1.0, 1.0, 0.5)
		add_child(pupil)
		_pupils.append(pupil)
	_mouth = MeshInstance3D.new()
	_mouth.mesh = Scenery.sphere(0.06, 10, 5)
	_mouth.material_override = Scenery.mat(Color(0.14, 0.02, 0.05), 0.6, true)
	_mouth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mouth.position = MOUTH_POS - HEAD_REST
	_mouth.scale = _mouth_scale
	add_child(_mouth)
	update(0.0, 0, Vector2.ZERO)
	return true


## LOW remotes keep the mood/eye shapes but stop the tiny blink and pupil
## micro-animation. The local player always runs at quality 2.
func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)


## mood: 0 normal, 1 surprised (in the air), 2 hurt, 3 happy.   look: gaze, each axis -1..1 (model space).
func update(delta: float, mood: int, look: Vector2) -> void:
	if _mouth == null:
		return
	if quality > 0:
		_next_blink -= delta
		if _next_blink <= 0.0:
			_blink = 0.13
			_next_blink = randf_range(2.5, 5.5)
		_blink = maxf(0.0, _blink - delta)
		_look = _look.lerp(look, 1.0 - exp(-12.0 * delta))
	else:
		_blink = 0.0
		_look = Vector2.ZERO
		_next_blink = maxf(_next_blink, 1.0)
	var eye_target := Vector2(1.0, 1.0)
	var mouth_target := Vector3(1.3, 0.28, 0.25)
	match mood:
		1:
			eye_target = Vector2(1.15, 1.3)
			mouth_target = Vector3(0.75, 0.95, 0.3)       # round "oh"
		2:
			eye_target = Vector2(1.1, 0.45)
			mouth_target = Vector3(1.25, 1.1, 0.3)        # wide open
		3:
			eye_target = Vector2(1.0, 0.55)
			mouth_target = Vector3(1.7, 0.75, 0.3)        # big grin
	var k := 1.0 - exp(-14.0 * delta)
	_eye_scale = _eye_scale.lerp(eye_target, k)
	_mouth_scale = _mouth_scale.lerp(mouth_target, k)
	_mouth.scale = _mouth_scale
	var blink_y := 0.12 if _blink > 0.0 else 1.0
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var eye := _eyes[i]
		eye.scale = Vector3(_eye_scale.x, _eye_scale.y * 1.15 * blink_y, 0.4)
		var pupil := _pupils[i]
		if quality > 0:
			pupil.visible = _blink <= 0.0
			pupil.position = eye.position + Vector3(_look.x * 0.032, _look.y * 0.032, 0.048)
		else:
			pupil.visible = true
			pupil.position = eye.position + Vector3(0.0, 0.0, 0.048)
		pupil.scale = Vector3(1.0, minf(1.0, _eye_scale.y + 0.2), 0.5)
