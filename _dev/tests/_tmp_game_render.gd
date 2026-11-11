extends Node

var _placeholder: Node


func _ready() -> void:
	call_deferred("_start")


func _start() -> void:
	_placeholder = Node.new()
	get_tree().root.add_child(_placeholder)
	get_tree().current_scene = _placeholder
	call_deferred("_run")


func _run() -> void:
	SettingsManager.apply_preset(SettingsManager.PRESET_HIGH)
	GameManager.start_practice()
	await get_tree().create_timer(5.0).timeout
	var arena := get_tree().current_scene
	print("GAME arena=", arena.name if arena != null else "null")
	if arena == null:
		get_tree().quit(1)
		return
	var rm = arena.get_node_or_null("RoundManager")
	var player = rm.local_player if rm != null else null
	print("GAME player=", player, " state=", rm.state if rm != null else -1)
	if player == null:
		get_tree().quit(1)
		return
	_capture("arena_idle")
	print("GAME idle pos=%s camera=%s" % [player.global_position, get_viewport().get_camera_3d()])

	Input.action_press("move_forward")
	await get_tree().create_timer(1.0).timeout
	Input.action_release("move_forward")
	await get_tree().create_timer(0.15).timeout
	_capture("arena_run")
	print("GAME run pos=%s rag=%s" % [player.global_position, player.visuals.get_ragdoll().get_anchor_lag()])

	await get_tree().create_timer(0.6).timeout
	player.apply_knockback(Vector3(10.0, 4.0, -18.0), 22.0, 8.0)
	await get_tree().create_timer(0.12).timeout
	var rag = player.visuals.get_ragdoll()
	print("GAME knock rag=%s up=%.3f lag=%.3f" % [
		rag.is_ragdolled(), rag.get_uprightness(), rag.get_anchor_lag()])
	_capture("arena_hit")
	await get_tree().create_timer(0.8).timeout
	_capture("arena_ragdoll")
	print("GAME rag later rag=%s rec=%s up=%.3f lag=%.3f" % [
		rag.is_ragdolled(), rag.is_recovering(), rag.get_uprightness(), rag.get_anchor_lag()])
	await get_tree().create_timer(2.5).timeout
	_capture("arena_recovered")
	print("GAME final rag=%s rec=%s up=%.3f lag=%.3f pos=%s" % [
		rag.is_ragdolled(), rag.is_recovering(), rag.get_uprightness(), rag.get_anchor_lag(), player.global_position])
	get_tree().quit()


func _capture(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/opencode/%s.png" % tag)
	print("GAME saved ", tag)
