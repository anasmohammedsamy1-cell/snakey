extends Node3D

const MODEL := preload("res://NewAssets/Model/contender.glb")
const VisualsScript := preload("res://scripts/character/contender_visuals.gd")

var visuals: Node3D
var rag: ContenderRagdoll
var cam: Camera3D


func _ready() -> void:
	_build_world()
	var raw := MODEL.instantiate() as Node3D
	raw.name = "RawModel"
	raw.position = Vector3(-1.35, 0, 0)
	raw.rotation.y = PI
	add_child(raw)

	visuals = VisualsScript.new()
	visuals.name = "ActiveVisual"
	visuals.position = Vector3(1.35, 0, 0)
	add_child(visuals)
	rag = visuals.get_ragdoll()
	call_deferred("_run")


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.68, 0.78)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.8, 0.9)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.15
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(20.0, 0.5, 20.0)
	col.shape = shape
	col.position = Vector3(0, -0.25, 0)
	floor_body.add_child(col)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = shape.size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.42, 0.34)
	mi.material_override = mat
	mi.position = col.position
	floor_body.add_child(mi)
	add_child(floor_body)

	cam = Camera3D.new()
	cam.fov = 45
	cam.position = Vector3(4.3, 1.5, -6.2)
	add_child(cam)
	cam.look_at(Vector3(0, 1.0, 0))


func _run() -> void:
	await _wait(150)
	_capture("sim_compare")
	print("SIM idle torso=%s up=%.3f lag=%.3f" % [
		rag.get_body_world("Torso").origin, rag.get_uprightness(), rag.get_anchor_lag()])
	cam.position = Vector3(3.55, 1.5, -4.75)
	cam.look_at(Vector3(1.35, 1.0, 0))
	_capture("sim_idle")

	visuals.set_state(visuals.Anim.RUN)
	visuals.move_speed_factor = 1.0
	await _wait(40)
	_capture("sim_run")
	print("SIM run up=%.3f lag=%.3f" % [rag.get_uprightness(), rag.get_anchor_lag()])

	visuals.set_state(visuals.Anim.IDLE)
	visuals.move_speed_factor = 0.0
	await _wait(35)
	visuals.apply_impact(Vector3(30, 9, -18), rag.get_body_world("Torso").origin + Vector3.UP * 0.3, 1.0)
	var best := 1.0
	var best_frame := 0
	for i in 60:
		await get_tree().physics_frame
		var up := rag.get_uprightness()
		if up < best:
			best = up
			best_frame = i
		if i == best_frame:
			pass
	if best_frame > 0:
		pass
	_capture("sim_ragdoll")
	print("SIM impact min_up=%.3f frame=%d rag=%s up_now=%.3f" % [
		best, best_frame, rag.is_ragdolled(), rag.get_uprightness()])
	await _wait(280)
	_capture("sim_recovered")
	print("SIM recovered up=%.3f rag=%s rec=%s" % [
		rag.get_uprightness(), rag.is_ragdolled(), rag.is_recovering()])
	get_tree().quit()


func _capture(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/opencode/ragdoll_%s.png" % tag)
	print("SIM saved ", tag)


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame
