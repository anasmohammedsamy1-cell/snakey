extends Node
## Exercises the host-authoritative grab, carry and delayed throw flow in practice mode.

const GameConstants := preload("res://scripts/game_constants.gd")

var _failures := 0


func _ready() -> void:
	call_deferred("_start")


func _gm() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		return tree.root.get_node_or_null("/root/GameManager")
	return null

func _start() -> void:
	var placeholder := Node.new()
	placeholder.name = "GrabCarryTestPlaceholder"
	get_tree().root.add_child(placeholder)
	get_tree().current_scene = placeholder
	_gm().start_practice()
	await _wait(4.5)
	var arena: Node = get_tree().current_scene
	if arena == null or arena.name != "Arena":
		_check(false, "practice arena loads")
		_finish()
		return
	var round_manager: Node = arena.get_node("RoundManager")
	var holder: Node = round_manager.local_player
	var target: Node = null
	if holder == null:
		_check(false, "local practice player is available")
		_finish()
		return
	for peer_id in round_manager.players:
		if int(peer_id) != holder.peer_id:
			target = round_manager.players[peer_id]
			break
	_check(target != null, "two practice players are available")
	if target == null:
		_finish()
		return

	for player in round_manager.players.values():
		if player != holder and player != target:
			player.process_mode = Node.PROCESS_MODE_DISABLED
	target.process_mode = Node.PROCESS_MODE_DISABLED
	holder.global_position = Vector3(0.0, 1.0, 0.0)
	target.global_position = Vector3(1.25, 1.0, 0.0)
	holder.velocity = Vector3.ZERO
	target.velocity = Vector3.ZERO
	holder.facing_yaw = -PI * 0.5
	holder.visuals.rotation.y = holder.facing_yaw

	round_manager._server_arm(
		holder.peer_id,
		GameConstants.ARM_MODE_GRAB,
		target.peer_id,
		Vector3.RIGHT,
		0.5
	)
	_check(round_manager._grabs.has(holder.peer_id), "host accepts a reachable grab")
	if not round_manager._grabs.has(holder.peer_id):
		_finish()
		return
	holder._push_timer = 0.0
	holder._try_attack()
	_check(not (holder.visuals.animator.throw_t >= 0.0) and holder._push_timer == 0.0,
		"an in-progress grab cannot start a throw")
	round_manager._process_grabs(1.0 / 60.0)
	_check(holder.grabbing_id == target.peer_id and holder.grab_phase == 1,
		"grab reaches the carrying phase")
	_check(target.grabbed_by == holder.peer_id and target.grab_phase == 1,
		"target is attached to the holder state")

	for i in 72:
		await get_tree().physics_frame
		target._simulate_carried(1.0 / 60.0)
		if i % 12 == 0:
			round_manager._process_grabs(1.0 / 60.0)
	var anim: ContenderAnimator = holder.visuals.animator
	var waited := 0.0
	while anim.lift_p < 0.99 and waited < 4.0:
		await get_tree().physics_frame
		waited += 1.0 / 60.0
		target._simulate_carried(1.0 / 60.0)
	var hand_l: Vector3 = anim.get_hand_world(0)
	var hand_r: Vector3 = anim.get_hand_world(1)
	print("[GRAB-CARRY] hands=%s / %s root=%s lift=%.2f state=%s" % [hand_l, hand_r, holder.global_position, anim.lift_p, anim.state])
	_check(anim.lift_p > 0.99, "the lift animation completed (progress %.2f)" % anim.lift_p)
	_check(hand_l.y > holder.global_position.y + 1.5 and hand_r.y > holder.global_position.y + 1.5,
		"BOTH hands are raised overhead (%.2f / %.2f)" % [hand_l.y, hand_r.y])
	_check(target.global_position.distance_to(holder.visuals.get_grab_overhead_position()) < 0.35,
		"the carried target follows the carry anchor")
	var start: Vector3 = holder.global_position
	Input.action_press("move_forward")
	for i in 12:
		await get_tree().physics_frame
		target._simulate_carried(1.0 / 60.0)
	Input.action_release("move_forward")
	_check(start.distance_to(holder.global_position) > 0.05,
		"holder can move while carrying")

	holder._push_timer = 0.0
	holder._try_attack()
	for i in 12:
		await get_tree().physics_frame
		target._simulate_carried(1.0 / 60.0)
	_check(round_manager._grabs.has(holder.peer_id),
		"throw keeps the target attached during its wind-up")
	await _wait(0.6)
	_check(not round_manager._grabs.has(holder.peer_id)
		and target.grabbed_by == 0,
		"host releases the target after the throw delay")
	_check(int(round_manager.stats[holder.peer_id]["hits"]) > 0,
		"throw release records a hit")
	_finish()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[GRAB-CARRY] PASS  " + label)
	else:
		_failures += 1
		print("[GRAB-CARRY] FAIL  " + label)


func _finish() -> void:
	print("[GRAB-CARRY] finished with %d failure(s)" % _failures)
	var gm := _gm()
	if gm and gm.has_method("leave_match"):
		gm.call("leave_match")
	get_tree().quit(1 if _failures > 0 else 0)
