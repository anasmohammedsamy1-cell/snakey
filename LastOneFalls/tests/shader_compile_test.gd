extends Node3D

const SHADER_PATHS := [
	"res://assets/shaders/burst_glow.gdshader",
	"res://assets/shaders/magnet_field.gdshader",
	"res://assets/shaders/shield_bubble.gdshader",
	"res://assets/shaders/item_glow.gdshader",
	"res://assets/shaders/hud_vivid.gdshader"
]

var _results: Array = []
func _ready() -> void:
	call_deferred("_start")
func _start() -> void:
	call_deferred("_test_shaders")
func _test_shaders() -> void:
	for shader_path in SHADER_PATHS:
		_results.append(await test_shader(shader_path))
	_report_results()
func test_shader(path: String) -> Dictionary:
	var shader_file = FileAccess.open(path, FileAccess.READ)
	if shader_file == null:
		return {"path": path, "passed": false, "error": "Could not open shader file"}
	var shader_code := shader_file.get_as_text()
	shader_file.close()
	if shader_code.strip_edges().is_empty():
		return {"path": path, "passed": false, "error": "Shader file is empty"}
	var shader := load(path) as Shader
	if shader == null:
		return {"path": path, "passed": false, "error": "Could not load shader resource"}
	var shader_material := ShaderMaterial.new()
	shader_material.shader = shader
	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	mesh_instance.mesh = sphere
	mesh_instance.material_override = shader_material
	add_child(mesh_instance)
	await get_tree().process_frame
	await get_tree().process_frame
	# resource_name is not populated by the importer; resource_path is the real identity.
	# A parsed shader exposes its uniforms, while a failed parse leaves this list empty.
	var uniforms := shader.get_shader_uniform_list()
	if shader.resource_path == path and not uniforms.is_empty():
		mesh_instance.queue_free()
		return {"path": path, "passed": true, "error": ""}
	mesh_instance.queue_free()
	return {"path": path, "passed": false, "error": "Shader failed to parse or has no uniforms"}

func _report_results() -> void:
	var all_passed: bool = true
	for result in _results:
		if not result["passed"]:
			all_passed = false
			print("FAIL: %s - %s" % [result["path"], result["error"]])
	if all_passed:
		print("PASS: All shaders compiled successfully")
	else:
		print("FAIL: Some shaders failed to compile")
	get_tree().quit(0 if all_passed else 1)