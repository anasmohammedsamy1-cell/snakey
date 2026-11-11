extends Node3D
## Runtime probe for the contender active ragdoll.
##
##   godot --headless --path . res://tests/ragdoll_test.tscn
##
## Verifies construction, settling, target-pose animation feed, impacts,
## recovery and the direct-target fallback.  Exits 1 on failure.

const VisualsScript := preload("res://scripts/character/contender_visuals.gd")

var _failures := 0
var _visuals: Node3D
var _ragdoll: ContenderRagdoll


func _ready() -> void:
	call_deferred("_start")


func _start() -> void:
	print("[RAGDOLL-TEST] start")
	_build_floor()
	_visuals = VisualsScript.new()
	_visuals.name = "TestVisuals"
	add_child(_visuals)
	_ragdoll = _visuals.get_ragdoll()

	await _wait_physics(3)
	_check(_ragdoll != null, "ragdoll exists")
	if _ragdoll == null:
		_finish()
		return
	_check(_ragdoll.is_built(), "ragdoll built")
	if not _ragdoll.is_built():
		_finish()
		return
	_check(_ragdoll.body.size() == 10, "10 rigid bodies (got %d)" % _ragdoll.body.size())
	_check(_ragdoll.joint.size() == 9, "9 joints (got %d)" % _ragdoll.joint.size())
	_check(_visuals.pose_rig != null and _visuals.pose_rig.pose_ready, "pose rig ready")
	print("[RAGDOLL-TEST] initial torso=%s target=%s" % [
		_ragdoll.get_body_world("Torso").origin,
		_ragdoll.target_world.get("Torso", Transform3D.IDENTITY).origin])

	# ---------------------------------------------------------------- settle
	await _wait_seconds(2.0)
	var torso: RigidBody3D = _ragdoll.body["Torso"]
	var up := _ragdoll.get_uprightness()
	var lag := _ragdoll.get_anchor_lag()
	print("[RAGDOLL-TEST] settled torso=%s upright=%.3f lag=%.3f grounded=%s feet=%s" % [
		torso.global_position, up, lag, _ragdoll.grounded, str(_ragdoll.get_foot_contacts())])
	_check(_finite3(torso.global_position), "torso position finite")
	_check(_finite3(torso.linear_velocity), "torso velocity finite")
	_check(up > 0.55, "torso stays upright (%.3f)" % up)
	_check(lag < 0.45, "torso anchor lag small (%.3f)" % lag)
	_check(_ragdoll.grounded or _finite3(torso.global_position), "feet reach the floor")
	for key in ContenderRagdoll.BODY_ORDER:
		_check(_finite3(_ragdoll.get_body_world(key).origin), "body finite: " + key)
		var bq: Quaternion = _ragdoll.get_body_world(key).basis.get_rotation_quaternion()
		var tq: Quaternion = _ragdoll.target_basis[key].get_rotation_quaternion()
		var err := rad_to_deg(bq.angle_to(tq))
		print("[RAGDOLL-TEST] track %-7s origin_err=%.3f angle_err=%.1fdeg" % [
			key, _ragdoll.get_body_world(key).origin.distance_to(_ragdoll.target_world[key].origin), err])
		_check(err < 58.0, "body tracks target rotation: %s (%.1f deg)" % [key, err])

	# The visible skeleton must be written from the bodies, not from the target.
	await get_tree().process_frame
	var before_skel := _bone_world("Hand_L")
	var body_hand := _ragdoll.get_body_world("Hand_L").origin
	_check(before_skel.distance_to(body_hand) < 0.06,
		"visible Hand_L is driven by physics (%.3f)" % before_skel.distance_to(body_hand))
	var target_hand: Vector3 = _ragdoll.target_world["Hand_L"].origin
	print("[RAGDOLL-TEST] hand physics=%s target=%s" % [body_hand, target_hand])
	_check(body_hand.distance_to(target_hand) < 0.55,
		"hand tracks animation target (%.3f)" % body_hand.distance_to(target_hand))

	# ------------------------------------------------------------ locomotion
	_visuals.set_state(_visuals.Anim.WALK)
	_visuals.move_speed_factor = 0.7
	var foot_z_min := INF
	var foot_z_max := -INF
	var hand_z_min := INF
	var hand_z_max := -INF
	var tfoot_z_min := INF
	var tfoot_z_max := -INF
	var thand_z_min := INF
	var thand_z_max := -INF
	for i in 72:
		await get_tree().physics_frame
		var fz: float = _ragdoll.get_body_world("Foot_L").origin.z
		var hz: float = _ragdoll.get_body_world("Hand_L").origin.z
		var tfz: float = _ragdoll.target_world["Foot_L"].origin.z
		var thz: float = _ragdoll.target_world["Hand_L"].origin.z
		foot_z_min = minf(foot_z_min, fz)
		foot_z_max = maxf(foot_z_max, fz)
		hand_z_min = minf(hand_z_min, hz)
		hand_z_max = maxf(hand_z_max, hz)
		tfoot_z_min = minf(tfoot_z_min, tfz)
		tfoot_z_max = maxf(tfoot_z_max, tfz)
		thand_z_min = minf(thand_z_min, thz)
		thand_z_max = maxf(thand_z_max, thz)
	print("[RAGDOLL-TEST] walk physical swing foot_z=%.3f hand_z=%.3f target foot_z=%.3f hand_z=%.3f" % [
		foot_z_max - foot_z_min, hand_z_max - hand_z_min,
		tfoot_z_max - tfoot_z_min, thand_z_max - thand_z_min])
	_check(tfoot_z_max - tfoot_z_min > 0.06, "walk target moves the foot (%.3f m)" % (tfoot_z_max - tfoot_z_min))
	_check(thand_z_max - thand_z_min > 0.04, "walk target moves the arm (%.3f m)" % (thand_z_max - thand_z_min))
	_check(hand_z_max - hand_z_min > 0.03, "walking moves the physical arm (%.3f m)" % (hand_z_max - hand_z_min))
	up = _ragdoll.get_uprightness()
	print("[RAGDOLL-TEST] walk upright=%.3f lag=%.3f" % [up, _ragdoll.get_anchor_lag()])
	_check(up > 0.5, "walking stays upright (%.3f)" % up)
	_check(_finite3(torso.global_position), "walking torso finite")

	# ---------------------------------------------------------- carry posture
	_visuals.set_grab_state(123, 1)
	await _wait_physics(48)
	var carry_hand: Vector3 = _ragdoll.target_world["Hand_R"].origin
	var carry_head: Vector3 = _ragdoll.target_world["Head"].origin
	var carry_arm: Vector3 = _ragdoll.target_world["Arm_R"].origin
	var carry_arm_body := _ragdoll.get_body_world("Arm_R")
	var carry_arm_target: Quaternion = _ragdoll.target_basis["Arm_R"].get_rotation_quaternion()
	var carry_arm_rotation: Quaternion = carry_arm_body.basis.get_rotation_quaternion()
	var carry_hand_target: Quaternion = _ragdoll.target_basis["Hand_R"].get_rotation_quaternion()
	var carry_hand_rotation: Quaternion = _ragdoll.get_body_world("Hand_R").basis.get_rotation_quaternion()
	var carry_hand_body := _ragdoll.get_body_world("Hand_R").origin
	var carry_head_body := _ragdoll.get_body_world("Head").origin
	print("[RAGDOLL-TEST] carry target arm=%s hand=%s head=%s physical arm=%s hand=%s head=%s arm_angle=%.1f hand_angle=%.1f" % [
		carry_arm, carry_hand, carry_head, carry_arm_body.origin, carry_hand_body, carry_head_body,
		rad_to_deg(carry_arm_rotation.angle_to(carry_arm_target)),
		rad_to_deg(carry_hand_rotation.angle_to(carry_hand_target))])
	_check(carry_hand.y > carry_head.y - 0.55, "carry pose targets the real hand above the head")
	_check(carry_hand_body.y > carry_head_body.y - 0.55,
		"physical hand follows the overhead carry pose")
	_visuals.set_grab_state(0, 0)

	# ----------------------------------------------------------- throw motion
	var throw_start: Vector3 = _ragdoll.target_world["Hand_R"].origin
	_visuals.play_throw()
	await _wait_physics(12)
	var throw_peak: Vector3 = _ragdoll.target_world["Hand_R"].origin
	_check(throw_start.distance_to(throw_peak) > 0.04,
		"throw animation moves the real hand target")
	_visuals.finish_throw()
	_ragdoll.pose_rig.stop_upper()
	await _wait_physics(2)

	# ---------------------------------------------------------- ragdoll impact
	_visuals.set_state(_visuals.Anim.IDLE)
	await _wait_physics(2)
	_ragdoll.apply_impact(Vector3(30.0, 8.0, -14.0), torso.global_position + Vector3.UP * 0.4, 1.0)
	await _wait_physics(2)
	print("[RAGDOLL-TEST] impact ragdolled=%s up=%.3f" % [
		_ragdoll.is_ragdolled(), _ragdoll.get_uprightness()])
	_check(_ragdoll.is_ragdolled(), "strong impact enters ragdoll")
	_check(_finite3(torso.global_position), "impact torso finite")

	var min_up := 1.0
	var min_torso_y := torso.global_position.y
	for i in 45:
		await get_tree().physics_frame
		min_up = minf(min_up, _ragdoll.get_uprightness())
		min_torso_y = minf(min_torso_y, torso.global_position.y)
	print("[RAGDOLL-TEST] impact min uprightness=%.3f torso_dy=%.3f" % [min_up, min_torso_y - torso.global_position.y])
	_check(min_up < 0.985 or absf(min_torso_y - torso.global_position.y) > 0.025, "impact visibly tips the torso (%.3f)" % min_up)

	var recovered := false
	for i in 14:
		await _wait_seconds(0.5)
		if not _ragdoll.is_ragdolled() and not _ragdoll.is_recovering():
			recovered = true
			break
	print("[RAGDOLL-TEST] recovery=%s up=%.3f torso=%s" % [
		recovered, _ragdoll.get_uprightness(), torso.global_position])
	_check(recovered, "recovers from ragdoll")
	_check(_ragdoll.get_uprightness() > 0.5, "recovered upright (%.3f)" % _ragdoll.get_uprightness())
	_check(_finite3(torso.global_position), "recovery torso finite")

	# ------------------------------------------------------------- fallback
	_ragdoll.set_simulation_enabled(false)
	await _wait_physics(2)
	var frozen := true
	for key in ContenderRagdoll.BODY_ORDER:
		if not (_ragdoll.body[key] as RigidBody3D).freeze:
			frozen = false
	_check(frozen, "fallback freezes bodies")
	await get_tree().process_frame
	await get_tree().process_frame
	var target_torso: Vector3 = _ragdoll.target_world["Torso"].origin
	var skel_torso := _bone_world("Torso")
	print("[RAGDOLL-TEST] fallback skeleton=%s target=%s" % [skel_torso, target_torso])
	_check(skel_torso.distance_to(target_torso) < 0.05,
		"fallback drives skeleton from target (%.3f)" % skel_torso.distance_to(target_torso))
	_ragdoll.set_simulation_enabled(true)
	await _wait_physics(2)
	_check(_ragdoll.is_built(), "re-enable keeps ragdoll built")

	_finish()


# ---------------------------------------------------------------------------

func _build_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(30.0, 0.5, 30.0)
	col.shape = shape
	col.position = Vector3(0, -0.25, 0)
	floor_body.add_child(col)
	add_child(floor_body)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	mesh.mesh = box
	mesh.position = col.position
	floor_body.add_child(mesh)


func _bone_world(bone: String) -> Vector3:
	var sk: Skeleton3D = _visuals.get_visible_skeleton()
	for i in sk.get_bone_count():
		if sk.get_bone_name(i) == bone:
			return sk.global_transform * sk.get_bone_global_pose(i).origin
	return Vector3.INF


func _finite3(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[RAGDOLL-TEST] PASS  " + label)
	else:
		_failures += 1
		print("[RAGDOLL-TEST] FAIL  " + label)


func _wait_physics(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _wait_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _finish() -> void:
	print("[RAGDOLL-TEST] finished with %d failure(s)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
