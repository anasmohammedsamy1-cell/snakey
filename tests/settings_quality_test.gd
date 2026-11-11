extends Node
const Scenery := preload("res://scripts/scenery.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("[QUALITY] FAIL ", label)
	else:
		print("[QUALITY] PASS ", label)
func _ready() -> void:
	var saved: Dictionary = SettingsManager.settings.duplicate(true)
	SettingsManager.apply_preset(SettingsManager.PRESET_HIGH)
	check(get_tree().root.msaa_3d == Viewport.MSAA_4X, "high preset applies 4x MSAA immediately")
	SettingsManager.apply_preset(SettingsManager.PRESET_LOW)
	check(get_tree().root.msaa_3d == Viewport.MSAA_DISABLED, "low preset disables MSAA")
	check(is_equal_approx(get_tree().root.scaling_3d_scale, 0.65), "low preset renders at 65 percent per dimension")
	check(not bool(SettingsManager.get_setting("shadows")) and not bool(SettingsManager.get_setting("effects")), "low preset disables shadows and effects")
	SettingsManager.apply_preset(SettingsManager.PRESET_MEDIUM)
	check(is_equal_approx(get_tree().root.scaling_3d_scale, 0.85), "medium preset renders at 85 percent")
	check(get_tree().root.msaa_3d == Viewport.MSAA_2X, "medium preset uses 2x MSAA")
	var env := Environment.new()
	Scenery.configure_environment(env, SettingsManager.PRESET_MEDIUM)
	check(env.sky.sky_material is ProceduralSkyMaterial, "medium preset uses the procedural sky")
	Scenery.configure_environment(env, SettingsManager.PRESET_HIGH)
	check(env.sky.sky_material is PanoramaSkyMaterial, "high preset uses the imported HDRI sky")
	check(is_equal_approx(env.adjustment_saturation, 1.45) and is_equal_approx(env.adjustment_contrast, 1.34), "shared saturation and contrast grade is preserved across presets")
	SettingsManager.settings = saved
	SettingsManager.apply_all()
	SettingsManager.save_settings()
	print("[QUALITY] finished with %d failure(s)" % failures)
	get_tree().quit(1 if failures else 0)
