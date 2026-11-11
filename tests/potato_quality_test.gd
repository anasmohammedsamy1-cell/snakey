extends Node
## POTATO preset verification: every knob the menu shows, everything it consumes,
## persistence across save/load, and mid-game switching safety.
const Scenery := preload("res://scripts/scenery.gd")

var failures := 0

func _ready() -> void:
	reparent.call_deferred(get_tree().root)
	await get_tree().process_frame
	await get_tree().process_frame
	var placeholder := Node.new()
	get_tree().root.add_child(placeholder)
	get_tree().current_scene = placeholder
	call_deferred("run_test")

func check(ok: bool, label: String) -> void:
	if ok:
		print("[POTATO] PASS ", label)
	else:
		failures += 1
		print("[POTATO] FAIL ", label)

func _src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""

func run_test() -> void:
	var saved: Dictionary = SettingsManager.settings.duplicate(true)
	_viewport_tests()
	_persistence_tests()
	_source_tests()
	await _menu_test()
	await _arena_test()
	await _switch_tests()
	SettingsManager.settings = saved
	SettingsManager.apply_all()
	SettingsManager.save_settings()
	print("[POTATO] finished with %d failure(s)" % failures)
	get_tree().quit(1 if failures else 0)

func _viewport_tests() -> void:
	SettingsManager.apply_preset(SettingsManager.PRESET_POTATO)
	check(int(SettingsManager.get_setting("graphics_preset")) == SettingsManager.PRESET_POTATO, "preset stored as POTATO")
	check(abs(float(SettingsManager.get_setting("render_scale")) - 0.5) < 0.001, "render_scale = 0.50")
	check(not bool(SettingsManager.get_setting("shadows")), "shadows off")
	check(not bool(SettingsManager.get_setting("effects")), "effects off")
	check(not bool(SettingsManager.get_setting("msaa")), "msaa off")
	var root: Window = get_tree().root
	check(abs(root.scaling_3d_scale - 0.5) < 0.001, "viewport 3D scale applied (0.5)")
	check(root.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR, "3D scale mode is bilinear")
	check(root.msaa_3d == Viewport.MSAA_DISABLED, "MSAA disabled on the viewport")
	check(root.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED, "screen-space AA stays disabled")
	check(Scenery.floor_mat(Color(0.173, 0.281, 0.397)) is StandardMaterial3D, "POTATO uses flat floor materials")
	check(not Scenery.mat(Color(0.173, 0.281, 0.397)).rim_enabled, "POTATO disables decorative material rim lighting")
	var potato_env := Environment.new()
	Scenery.configure_environment(potato_env, SettingsManager.PRESET_POTATO)
	check(not potato_env.adjustment_enabled and not potato_env.glow_enabled, "POTATO environment disables post-processing")
	SettingsManager.apply_preset(SettingsManager.PRESET_MEDIUM)
	check(Scenery.floor_mat(Color(0.173, 0.281, 0.397)) is ShaderMaterial, "MEDIUM keeps procedural floor detail")
	check(Scenery.mat(Color(0.173, 0.281, 0.397)).rim_enabled, "MEDIUM preserves decorative material rim lighting")
	# Existing presets keep their exact values (no regression).
	for p in [SettingsManager.PRESET_LOW, SettingsManager.PRESET_MEDIUM, SettingsManager.PRESET_HIGH]:
		SettingsManager.apply_preset(p)
		var scale := float(SettingsManager.get_setting("render_scale"))
		var expect := 0.65 if p == SettingsManager.PRESET_LOW else (0.85 if p == SettingsManager.PRESET_MEDIUM else 1.0)
		check(abs(scale - expect) < 0.001, "preset %d keeps render_scale %.2f" % [p, expect])
		check(bool(SettingsManager.get_setting("shadows")) == (p != SettingsManager.PRESET_LOW), "preset %d keeps shadows" % p)
		check(bool(SettingsManager.get_setting("effects")) == (p != SettingsManager.PRESET_LOW), "preset %d keeps effects" % p)
	SettingsManager.apply_preset(SettingsManager.PRESET_HIGH)
	check(get_tree().root.msaa_3d == Viewport.MSAA_4X, "HIGH preset still upgrades to 4x MSAA")
	SettingsManager.apply_preset(SettingsManager.PRESET_POTATO)

func _persistence_tests() -> void:
	SettingsManager.apply_preset(SettingsManager.PRESET_POTATO)
	SettingsManager.save_settings()
	SettingsManager.set_setting("graphics_preset", SettingsManager.PRESET_HIGH, false)
	SettingsManager.load_settings()
	check(int(SettingsManager.get_setting("graphics_preset")) == SettingsManager.PRESET_POTATO, "POTATO restored from settings.cfg")
	check(abs(float(SettingsManager.get_setting("render_scale")) - 0.5) < 0.001, "restored render_scale = 0.50")
	SettingsManager.apply_all()

func _source_tests() -> void:
	var sm := _src("res://scripts/settings_manager.gd")
	check("const PRESET_POTATO := 4" in sm, "POTATO preset constant exists")
	check('set_setting("render_scale", 0.5, false)' in sm, "POTATO applies 0.5 render scale")
	var menu := _src("res://scripts/settings_menu.gd")
	check("SettingsManager.PRESET_POTATO" in menu, "settings menu offers the POTATO button")
	check("preset_ids" in menu, "preset buttons bind explicit preset ids")
	check("potato_desc" in menu, "POTATO description shown in the menu")
	var lo := _src("res://scripts/locale.gd")
	check(lo.count('"potato"') >= 2 and lo.count('"potato_desc"') >= 2, "POTATO label + description in both languages")
	var vs := _src("res://scripts/character/contender_visuals.gd")
	check("SettingsManager.PRESET_POTATO:" in vs, "character quality maps POTATO to level 0 (outlines off)")
	check("LOD_NEAR:\n\t\t\t\treturn 1.0 / 10.0" in vs, "POTATO remote near cadence 10 Hz")
	check("LOD_DISTANT:\n\t\t\t\treturn 1.0 / 6.0" in vs, "POTATO remote distant cadence 6 Hz")
	check("LOD_OFFSCREEN:\n\t\t\t\treturn 1.0 / 2.0" in vs, "POTATO off-screen cadence 2 Hz")
	check("LOD_NEAR:\n\t\t\t\treturn 0.30" in vs, "POTATO face updates 3 Hz (near)")
	var mb := _src("res://scripts/map_builder.gd")
	check("PRESET_POTATO" in mb.split("func _is_low_quality", 1)[1], "weak-device paths include POTATO")
	check("PRESET_POTATO:\n\t\t# Weakest:" in mb or "== SettingsManager.PRESET_POTATO:" in mb, "POTATO sky decor branch")
	var sc := _src("res://scripts/scenery.gd")
	check("SettingsManager.PRESET_POTATO:\n\t\t\treturn 0.35" in sc, "POTATO geometry detail 0.35x")
	check("visibility_range_end = 120.0" in sc, "POTATO visibility range on the cloud sea")
	var pc := _src("res://scripts/player_controller.gd")
	check('int(SettingsManager.get_setting("graphics_preset")) == SettingsManager.PRESET_POTATO' in pc, "POTATO cheap aura path in player_controller")
	check("preset != SettingsManager.PRESET_LOW and preset != SettingsManager.PRESET_POTATO" in pc, "POTATO blocks shader bursts")

func _menu_test() -> void:
	await get_tree().process_frame
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child(menu)
	await get_tree().process_frame
	SettingsManager.apply_preset(SettingsManager.PRESET_POTATO)
	await get_tree().process_frame
	check(not menu._ambient_enabled, "menu ambient animation off on POTATO")
	SettingsManager.apply_preset(SettingsManager.PRESET_MEDIUM)
	await get_tree().process_frame
	check(menu._ambient_enabled, "menu ambient animation restored on MEDIUM")
	menu.free()

func _arena_test() -> void:
	SettingsManager.apply_preset(SettingsManager.PRESET_POTATO)
	GameManager.start_practice()
	await get_tree().create_timer(4.5).timeout
	var arena = get_tree().current_scene
	check(arena != null and arena.name == "Arena", "arena loads on POTATO")
	if arena == null or arena.name != "Arena":
		return
	var rm: Node = arena.round_manager
	var count: int = 0
	for node in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(node) and node.get("round_manager") == rm:
			count += 1
	check(count >= 2, "all players spawned (gameplay objects preserved)")
	check(arena.sun != null and not arena.sun.shadow_enabled, "sun shadows disabled")
	check(arena.env != null and not arena.env.fog_enabled, "fog disabled")
	check(arena.env != null and not arena.env.glow_enabled, "glow disabled")
	check(arena.env != null and not arena.env.adjustment_enabled, "post-processing adjustments disabled")
	var actors: int = 0
	for node in get_tree().get_nodes_in_group("obstacles"):
		if is_instance_valid(node):
			actors += 1
	check(actors > 0, "gameplay obstacles still on the field")
	check(arena.decor_root.get_child_count() > 0, "minimal sky decor still present (sea + clouds)")
	check(arena.decor_root.find_child("CloudSea", true, false) != null, "cloud sea kept for the fall zone read")
	check(arena.decor_root.find_child("NoIslandsHere", true, false) == null, "no island nodes by name")
	var clouds := arena.decor_root.find_child("Clouds", true, false) as MultiMeshInstance3D
	check(clouds != null and clouds.multimesh != null and clouds.multimesh.instance_count == 2, "tiny POTATO cloud field (2 puffs)")
	var distant := 0
	for d in arena.decor_root.get_children():
		distant += 1
	check(distant == 2, "POTATO decor = cloud field + cloud sea only")
	check(arena._poof == null and arena._splash == null and arena._confetti == null, "effect nodes not allocated while disabled")
	var player = rm.local_player
	check(player != null, "local player exists")
	if player != null:
		check(player.land_particles == null, "player particles not allocated when effects disabled")
		check(int(player._visual_quality()) == 0, "character visual quality is 0")
		check(player.visuals != null and bool(player.visuals._is_local_character), "local player stays the local character")
		check(player.visuals != null and int(player.visuals.animation_lod) == 0, "local player runs the full-rate LOD slot")
		check(player.visuals != null and int(player.visuals._effective_quality()) == 0, "effective quality 0 on POTATO")
		check(player.visuals != null and player.visuals.animator != null and player.visuals.animator.quality_level == 2, "local animation remains full quality")
		var remote_visual: Node = null
		for contender in rm.players.values():
			if not bool(contender.get("is_local")):
				remote_visual = contender.get("visuals")
				break
		check(remote_visual != null, "remote character visuals exist for animation LOD checks")
		if remote_visual != null:
			check(int(remote_visual.get("_quality")) == 0, "remote character quality updated for POTATO")
			remote_visual.set_hat("party")
			check(str(remote_visual.get("hat_id")) == "party" and remote_visual.get("hat_node") == null, "POTATO remote hat retained but not instantiated")
			check(is_equal_approx(float(remote_visual.call("_lod_interval", 1)), 0.1), "near remote animation reduced to 10 Hz")
			var previous_lod := int(remote_visual.get("animation_lod"))
			remote_visual.set("animation_lod", 1)
			check(is_equal_approx(float(remote_visual.call("_face_interval_for_lod")), 0.3), "near remote face updates reduced to about 3 Hz")
			remote_visual.set("animation_lod", previous_lod)

func _switch_tests() -> void:
	var arena = get_tree().current_scene
	if arena == null or arena.name != "Arena":
		return
	SettingsManager.apply_preset(SettingsManager.PRESET_HIGH)
	await get_tree().process_frame
	check(arena.sun != null and arena.sun.shadow_enabled, "mid-game switch to HIGH re-enables shadows")
	check(arena.env != null and arena.env.glow_enabled, "mid-game switch to HIGH re-enables glow")
	check(arena.env != null and arena.env.adjustment_enabled, "mid-game switch to HIGH restores color adjustment")
	var remote_visual: Node = null
	for contender in arena.round_manager.players.values():
		if not bool(contender.get("is_local")):
			remote_visual = contender.get("visuals")
			break
	if remote_visual != null:
		check(int(remote_visual.get("_quality")) == 2, "remote character quality updates live on HIGH")
		check(remote_visual.get("hat_node") != null and remote_visual.get("hat_node").visible, "remote hat restored on HIGH")
		var recolor_materials: Array = remote_visual.get("_recolor_materials")
		check(not recolor_materials.is_empty() and recolor_materials[0].get_next_pass() != null, "character outline enabled on HIGH")
	SettingsManager.apply_preset(SettingsManager.PRESET_POTATO)
	await get_tree().process_frame
	check(arena.sun != null and not arena.sun.shadow_enabled, "mid-game switch back to POTATO disables shadows again")
	check(arena.env != null and not arena.env.glow_enabled, "mid-game switch back to POTATO disables glow again")
	check(arena.env != null and not arena.env.adjustment_enabled, "mid-game switch back to POTATO disables color adjustment")
	if remote_visual != null:
		check(int(remote_visual.get("_quality")) == 0, "remote character quality updates live on POTATO")
		check(remote_visual.get("hat_node") == null and str(remote_visual.get("hat_id")) == "party", "remote hat suppressed again without losing selection")
		var recolor_materials: Array = remote_visual.get("_recolor_materials")
		check(not recolor_materials.is_empty() and recolor_materials[0].get_next_pass() == null, "character outline disabled on POTATO")
	SettingsManager.apply_preset(SettingsManager.PRESET_LOW)
	await get_tree().process_frame
	check(arena.sun != null and not arena.sun.shadow_enabled, "LOW still has shadows off (unchanged preset)")
	check(arena.env != null and not arena.env.glow_enabled, "LOW still has glow off (unchanged preset)")
