extends Node3D
class_name InteractionController
## InteractionController - Physical grabbing and punching using real robot hands.

const GameConstants := preload("res://scripts/game_constants.gd")

var rig: PhysicalPlayer

# Grab targeting
var _grab_target: Node = null
var _grab_mode := 0          # 0 = punch, 1 = grab
var _grab_range := 3.0
var _grab_charge := 0.0
var _arm_cooldown := 0.0
var _aim_lock := 0.0

# Punch tracking
var _punch_cooldown := 0.0
var _punch_hand := ""        # "Hand_L" or "Hand_R"

var _grab_target_point = null
var _grab_target_strength: float = 0.0


func update(delta: float) -> void:
	_arm_cooldown = maxf(0.0, _arm_cooldown - delta)
	_punch_cooldown = maxf(0.0, _punch_cooldown - delta)
	_aim_lock = maxf(0.0, _aim_lock - delta)

	if rig.push_requested:
		rig.push_requested = false
		_try_attack()

	if rig.grabbing_id != 0 and rig.grab_phase == 0:
		_track_grab_target(delta)


func _try_attack() -> void:
	if rig.grabbed_by != 0:
		rig.grabbed_by = 0
		rig.grab_phase = 0
		if rig.is_local:
			rig.round_manager.request_escape(rig)
		return
	if _arm_cooldown > 0.0 or rig._stun > 0.3:
		return
	if rig.round_manager != null and int(rig.round_manager.mode) == GameConstants.MODE_HIDE:
		_try_catch()
		return

	var charge := clampf(rig._push_charge, 0.0, 1.0)
	var carrying := rig.grabbing_id != 0 and rig.grab_phase == 1
	var attack_mode := 1 if carrying else _grab_mode
	var grab := attack_mode == 1

	var rng := _grab_range
	if grab:
		rng = 2.5
	else:
		rng = 3.0

	var dir_flat := Vector3(-sin(rig.facing_yaw), 0.0, -cos(rig.facing_yaw))
	var target: Node = null
	var tid := 0
	var target_pos := rig.torso_body.global_position + dir_flat * rng + Vector3.UP * 1.15

	if carrying and rig.round_manager != null:
		target = rig.round_manager.players.get(rig.grabbing_id)
		tid = target.peer_id if target != null else 0
		target_pos = target.global_position + Vector3.UP * 1.0
	else:
		target = _find_arm_target(rng)
		if target != null:
			var flat: Vector3 = target.global_position - rig.torso_body.global_position
			flat.y = 0.0
			if flat.length() > 0.01:
				dir_flat = flat.normalized()
				rig.facing_yaw = atan2(-dir_flat.x, -dir_flat.z)
			var length := clampf(combat_distance(rig, target) - 0.4, 0.8, rng)
			tid = target.peer_id
			target_pos = target.global_position + Vector3.UP * 1.0

	rig.facing_yaw = atan2(-dir_flat.x, -dir_flat.z)
	_aim_lock = 0.35

	AudioManager.play_character("push", 0.08, 0.0 if rig.is_local else -10.0)

	if rig.is_local:
		rig.attack_performed.emit()

	if rig.round_manager != null:
		rig.round_manager.request_arm(rig, attack_mode, tid, dir_flat, charge)


func _try_catch() -> void:
	if rig._push_timer > 0.0 or rig._stun > 0.3:
		return
	_arm_cooldown = 1.5
	rig._push_timer = 1.5
	var facing := Vector3(-sin(rig.facing_yaw), 0.0, -cos(rig.facing_yaw))
	var best: Node = null
	var best_score := INF
	for p in get_tree().get_nodes_in_group("players"):
		if p == rig or not p.is_alive or p.role != 2:
			continue
		var to: Vector3 = p.global_position - rig.torso_body.global_position
		to.y = 0.0
		var d := to.length()
		if d > 2.5 or d < 0.001:
			continue
		if facing.dot(to / d) < 0.05:
			continue
		if d < best_score:
			best_score = d
			best = p
	var tid := 0
	if best != null:
		var flat: Vector3 = best.global_position - rig.torso_body.global_position
		flat.y = 0.0
		rig.facing_yaw = atan2(-flat.x, -flat.z)
		tid = best.peer_id
	rig._aim_lock = 0.3
	AudioManager.play_character("push", 0.08, -4.0 if rig.is_local else -12.0)
	if tid != 0 and rig.round_manager != null:
		rig.round_manager.request_catch(rig, tid)


func _find_arm_target(rng: float) -> Node:
	var best: Node = null
	var best_score := INF
	var facing := Vector3(-sin(rig.facing_yaw), 0.0, -cos(rig.facing_yaw))
	for p in get_tree().get_nodes_in_group("players"):
		if p == rig or not p.is_alive:
			continue
		if rig.round_manager != null and not rig.round_manager.are_enemies(rig.peer_id, p.peer_id):
			continue
		var to: Vector3 = p.global_position - rig.torso_body.global_position
		if absf(to.y) > 1.5:
			continue
		to.y = 0.0
		var d := to.length()
		if d > rng or d < 0.001:
			continue
		var dot := facing.dot(to / d)
		if dot < 0.35:
			continue
		var score := d * (2.0 - dot)
		if score < best_score:
			best_score = score
			best = p
	return best


func _track_grab_target(delta: float) -> void:
	if rig.grabbing_id == 0 or rig.round_manager == null:
		return
	var t: Node = rig.round_manager.players.get(rig.grabbing_id)
	if t == null or not is_instance_valid(t):
		return
	var to: Vector3 = t.global_position - rig.torso_body.global_position
	to.y = 0.0
	if to.length() > 0.01:
		var dir := to.normalized()
		rig.facing_yaw = atan2(-dir.x, -dir.z)


func set_target(point: Vector3, strength: float) -> void:
	_grab_target_point = point
	_grab_target_strength = strength


func clear_tether() -> void:
	_grab_target_point = null


func confirm() -> void:
	pass


func release() -> void:
	_grab_target_point = null


func finish_throw() -> void:
	_grab_target_point = null


func is_active() -> bool:
	return _grab_target_point != null or _arm_cooldown > 0.0


func set_tether(point: Vector3, strength: float) -> void:
	if rig.grabbed_by != 0 and rig.grab_phase == 1:
		return
	var dir: Vector3 = (point - rig.torso_body.global_position)
	dir.y = 0.0
	if dir.length() > 0.01:
		rig.torso_body.apply_central_force(dir.normalized() * strength * 2.0)


# ---------------------------------------------------------------------------
# Helpers

func combat_distance(a: Node3D, b: Node3D) -> float:
	var flat: Vector3 = b.global_position - a.global_position
	flat.y = 0.0
	return flat.length()


func _clamp_vector(v: Vector3, max_mag: float) -> Vector3:
	if v.length() > max_mag:
		return v.normalized() * max_mag
	return v
