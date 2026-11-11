extends Node3D
## Offline authoring tool: re-captures the map picker thumbnails for the arenas whose floor is now
## built from concentric tiers (v5), using the exact camera/lighting of render_map_previews.gd so the
## picker stays visually consistent. Run with a graphics display:
##   xvfb-run godot --path . res://tools/render_tier_thumbs.tscn
const Builder := preload("res://scripts/map_builder.gd")
const MAP_IDS := [0, 1, 3, 12, 17, 19]

var _cam: Camera3D


func _ready() -> void:
	call_deferred("run_capture")


func run_capture() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.24, 0.39)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.88, 0.95)
	env.ambient_light_energy = 0.7
	world.environment = env
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, 35, 0)
	light.light_energy = 0.7
	add_child(light)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 34.0
	add_child(_cam)
	_cam.current = true
	_cam.look_at_from_position(Vector3(0, 38, 30), Vector3(0, 0, 0), Vector3.UP)
	for id in MAP_IDS:
		var fixture := Node3D.new()
		fixture.set_script(load("res://tests/map_test_fixture.gd"))
		add_child(fixture)
		Builder.build(id, fixture)
		for frame in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.resize(480, 270, Image.INTERPOLATE_LANCZOS)
		var err := image.save_png("res://assets/maps/map_%d.png" % id)
		print("[TIER-THUMB] map=%d result=%d" % [id, err])
		fixture.queue_free()
		await get_tree().process_frame
	get_tree().quit()
