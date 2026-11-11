extends Node
## Command validation: invalid grabs are rejected, no self grab, no double grab, one throw per command.
const GameConstants := preload("res://scripts/game_constants.gd")
var _fails := 0

func _ready() -> void:
	call_deferred("_start")

func _check(ok: bool, msg: String) -> void:
	print("[RULES] %s  %s" % ["PASS" if ok else "FAIL", msg])
	if not ok:
		_fails += 1

func _start() -> void:
	var ph := Node.new()
	get_tree().root.add_child(ph)
	get_tree().current_scene = ph
	GameManager.start_practice()
	await get_tree().create_timer(4.0).timeout
	var rm: Node = get_tree().current_scene.get_node_or_null("RoundManager")
	var ids: Array = rm.players.keys()
	var a = rm.players[rm.local_player.peer_id]
	var b = null
	var c = null
	for id in ids:
		var o = rm.players[id]
		if o != a:
			if b == null:
				b = o
			elif c == null:
				c = o
	for o in rm.players.values():
		if o != a and o != b and o != c:
			o.process_mode = Node.PROCESS_MODE_DISABLED
	b.process_mode = Node.PROCESS_MODE_DISABLED
	c.process_mode = Node.PROCESS_MODE_DISABLED
	a.global_position = Vector3(0, 1, 0)
	b.global_position = Vector3(1.25, 1, 0)
	c.global_position = Vector3(-1.25, 1, 0)
	a.facing_yaw = -PI * 0.5
	a.visuals.rotation.y = a.facing_yaw
	rm._last_push_time.clear()
	rm._server_arm(a.peer_id, GameConstants.ARM_MODE_GRAB, a.peer_id, Vector3.RIGHT, 0.5)
	_check(not rm._grabs.has(a.peer_id), "grabbing yourself is rejected")
	b.global_position = Vector3(14, 1, 0)
	rm._last_push_time.clear()
	rm._server_arm(a.peer_id, GameConstants.ARM_MODE_GRAB, b.peer_id, Vector3.RIGHT, 0.5)
	_check(not rm._grabs.has(a.peer_id), "grab from an invalid distance is rejected")
	b.global_position = Vector3(1.25, 1, 0)
	rm._last_push_time.clear()
	rm._server_arm(a.peer_id, GameConstants.ARM_MODE_GRAB, b.peer_id, Vector3.RIGHT, 0.5)
	_check(rm._grabs.has(a.peer_id), "valid grab accepted")
	rm._last_push_time.clear()
	rm._server_arm(a.peer_id, GameConstants.ARM_MODE_GRAB, c.peer_id, Vector3.LEFT, 0.5)
	_check(rm._grabs.size() == 1 and int(rm._grabs[a.peer_id]["target"]) == b.peer_id, "repeated grab press does not grab a second player")
	rm._last_push_time.clear()
	rm._server_arm(c.peer_id, GameConstants.ARM_MODE_GRAB, b.peer_id, Vector3.RIGHT, 0.5)
	_check(not rm._grabs.has(c.peer_id), "a third player cannot grab someone already held")
	for i in 80:
		await get_tree().physics_frame
		rm._process_grabs(1.0 / 60.0)
	var hits0: int = int(rm.stats[a.peer_id]["hits"])
	rm._last_push_time.clear()
	rm._server_arm(a.peer_id, GameConstants.ARM_MODE_PUNCH, b.peer_id, Vector3.RIGHT, 0.7)
	rm._last_push_time.clear()
	rm._server_arm(a.peer_id, GameConstants.ARM_MODE_PUNCH, b.peer_id, Vector3.RIGHT, 0.7)
	for i in 90:
		await get_tree().physics_frame
		rm._process_grabs(1.0 / 60.0)
	_check(not rm._grabs.has(a.peer_id), "throw released the target")
	_check(int(rm.stats[a.peer_id]["hits"]) - hits0 == 1, "double throw command releases/impulses exactly once (hits +%d)" % (int(rm.stats[a.peer_id]["hits"]) - hits0))
	print("[RULES] finished with %d failure(s)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
