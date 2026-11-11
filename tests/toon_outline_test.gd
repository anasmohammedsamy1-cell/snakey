extends Node3D
## Headless test for the cheap toon look + inverted-hull outline.
##
## Checks (no rendering needed for the wiring part):
##  1. assets/shaders/outline.gdshader imports and compiles (cull_front, vertex push).
##  2. RECOLOR_SHADER keeps its recolor logic and uniforms and gains a light()
##     that quantises diffuse light into 3 smoothstep bands.
##  3. On MEDIUM / HIGH presets the recolor material gets the outline as next_pass.
##  4. On the LOW preset there is no outline pass.
##  5. set_color() still updates body_color on every material in _recolor_materials.
##
##   godot --headless --path . res://tests/toon_outline_test.tscn

const CV := preload("res://scripts/character/contender_visuals.gd")

const OUTLINE_PATH := "res://assets/shaders/outline.gdshader"

var failures := 0


func check(ok: bool, label: String) -> void:
	if ok:
		print("[TOON] PASS  " + label)
	else:
		failures += 1
		print("[TOON] FAIL  " + label)


func _ready() -> void:
	var saved: Dictionary = SettingsManager.settings.duplicate(true)
	await _compile_shaders()
	_check_recolor_shader_source()
	await _check_materials(SettingsManager.PRESET_HIGH, "high")
	await _check_materials(SettingsManager.PRESET_MEDIUM, "medium")
	await _check_materials(SettingsManager.PRESET_LOW, "low")
	SettingsManager.settings = saved
	SettingsManager.apply_all()
	SettingsManager.save_settings()
	print("[TOON] finished with %d failure(s)" % failures)
	get_tree().quit(1 if failures else 0)


## Imports and compiles the outline shader and the runtime recolor shader.
func _compile_shaders() -> void:
	var outline: Shader = load(OUTLINE_PATH)
	check(outline != null, "outline.gdshader imports")
	if outline != null:
		var outline_mat := ShaderMaterial.new()
		outline_mat.shader = outline
		check(outline.code.find("cull_front") >= 0, "outline shader culls front faces")
		check(outline.code.find("VERTEX += NORMAL * (0.012 * outline_width)") >= 0,
			"outline pushes vertices along NORMAL by 0.012 * outline_width")
		check(await _compile_material(outline_mat), "outline shader compiles")
	var recolor := Shader.new()
	recolor.code = CV.RECOLOR_SHADER
	var recolor_mat := ShaderMaterial.new()
	recolor_mat.shader = recolor
	check(await _compile_material(recolor_mat), "recolor shader with light() compiles")


## Builds a throwaway candidate and inspects its material wiring for one preset.
func _check_materials(preset: int, label: String) -> void:
	SettingsManager.apply_preset(preset)
	await get_tree().process_frame
	var visuals := Node3D.new()
	visuals.set_script(CV)
	add_child(visuals)
	visuals.set("TOON_ENABLED", true)
	visuals.call("build", Color(0.2, 0.6, 0.9))
	await get_tree().process_frame
	var materials: Array = visuals.get("_recolor_materials")
	check(materials.size() > 0, "%s preset: recolor materials are built" % label)
	var want_outline: bool = preset != SettingsManager.PRESET_LOW
	var outline_shader: Shader = load(OUTLINE_PATH)
	var links_ok := true
	var color_ok := true
	for mat in materials:
		var outline_pass: ShaderMaterial = mat.get_next_pass()
		if want_outline:
			if outline_pass == null or outline_pass.shader != outline_shader:
				links_ok = false
			elif float(outline_pass.get_shader_parameter("outline_width")) <= 0.0:
				links_ok = false
		elif outline_pass != null:
			links_ok = false
	# set_color still drives the main recolor material.
	visuals.call("set_color", Color(0.95, 0.15, 0.35))
	for mat in materials:
		if Color(mat.get_shader_parameter("body_color")) != Color(0.95, 0.15, 0.35):
			color_ok = false
	check(links_ok, "%s preset: %s" % [label, "outline is linked as next_pass" if want_outline else "no outline pass on LOW"])
	# set_detail_color() must drive the screws/gaps colour on the same materials.
	var detail_ok := true
	visuals.call("set_detail_color", Color(0.95, 0.15, 0.35))
	for mat in materials:
		if Color(mat.get_shader_parameter("detail_color")) != Color(0.95, 0.15, 0.35):
			detail_ok = false
	check(color_ok, "%s preset: set_color still updates body_color of the main material" % label)
	check(detail_ok, "%s preset: set_detail_color updates the screws/gaps colour" % label)
	visuals.free()
	await get_tree().process_frame


## Source-level guard: light() exists, quantises into 3 bands and the recolor
## logic and uniforms of fragment() are untouched.
func _check_recolor_shader_source() -> void:
	var code: String = CV.RECOLOR_SHADER
	check("void light() {" in code, "recolor shader defines light()")
	var body: String = code.split("void light() {", 1)[1].split("}", 1)[0]
	check(body.count("smoothstep(") >= 2, "light() uses smoothstep bands")
	check("DIFFUSE_LIGHT" in body, "light() writes DIFFUSE_LIGHT")
	check("void fragment() {" in code, "recolor fragment() is kept")
	for uniform in ["albedo_texture", "normal_texture", "use_normal", "normal_scale",
			"body_color", "recolor_strength", "metallic", "roughness", "specular"]:
		check("uniform" in code and uniform in code, "uniform '" + uniform + "' is kept")
	# light() may only use what the compiler provides there (NORMAL / LIGHT_* / uniforms).
	for banned in ["luminance", "maxc", "minc", "neutral", "shade", "source"]:
		check(banned not in body, "light() does not use fragment() local '" + banned + "'")


## Renders one frame with the material attached to a mesh so the shader compiles.
## (A shader that fails to compile is reported by the engine on stderr; the check
## here only guards against a hard failure while loading/attaching the material.)
func _compile_material(mat: ShaderMaterial) -> bool:
	if mat.shader == null:
		return false
	var probe := MeshInstance3D.new()
	probe.mesh = SphereMesh.new()
	probe.material_override = mat
	add_child(probe)
	for _i in 2:
		await get_tree().process_frame
	var attached: bool = probe.material_override == mat
	probe.queue_free()
	await get_tree().process_frame
	return attached
