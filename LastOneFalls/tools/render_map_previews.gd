extends Node3D
## Offline authoring tool; captures actual map geometry under the compatibility renderer.
## Run via tools/render_map_previews.tscn with a graphics display; output assets/maps/map_12..15.png.
const Builder := preload("res://scripts/map_builder.gd")
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
	for id in [12, 13, 14, 15]:
		var fixture := Node3D.new()
		fixture.set_script(load("res://tests/map_test_fixture.gd"))
		add_child(fixture)
		fixture.process_mode = Node.PROCESS_MODE_DISABLED
		Builder.build(id, fixture)
		for frame in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.resize(480, 270, Image.INTERPOLATE_LANCZOS)
		var path := "res://assets/maps/map_%d.png" % id
		var err := image.save_png(path)
		print("[THUMB] map=%d size=%s result=%d" % [id, image.get_size(), err])
		fixture.queue_free()
		await get_tree().process_frame
	get_tree().quit()
