import re, pathlib
R = pathlib.Path(__file__).resolve().parent.parent
rd = lambda p: (R / p).read_text(encoding="utf8")

def test_new_maps_registered_everywhere():
    gc, mb, mp, lo = rd("scripts/game_constants.gd"), rd("scripts/map_builder.gd"), rd("scripts/map_picker.gd"), rd("scripts/locale.gd")
    keys = re.findall(r'\{"key": "(map_[a-z_]+)"', gc)
    assert keys[16:20] == ["map_family_flat", "map_plaza", "map_mini_tiles", "map_split_ring"]
    assert len(re.findall(r'"map_[a-z_]+_desc"', mp.split("DESC_KEYS")[1].split("\n")[0])) == len(keys)
    for k in keys[16:]:
        assert lo.count('"%s"' % k) == 2 and lo.count('"%s_desc"' % k) == 2
        assert (R / ("assets/maps/map_%d.png" % (keys.index(k)))).exists()
    assert keys[20:23] == ["map_ice_rink", "map_conveyor_mill", "map_wind_tunnel"]
    for c in ["MAP_FAMILY_FLAT := 16", "MAP_PLAZA := 17", "MAP_MINI_TILES := 18", "MAP_SPLIT_RING := 19", "MAP_ICE_RINK := 20", "MAP_CONVEYOR_MILL := 21", "MAP_WIND_TUNNEL := 22"]:
        assert c in mb

def test_houses_sealed_and_camera_indoor():
    mb, pc = rd("scripts/map_builder.gd"), rd("scripts/player_controller.gd")
    assert "_build_ceiling(house" in mb and "_build_ceiling(school" in mb and "HOUSE_WALL_H := 5.0" in mb
    assert "_indoor_camera" in pc


def test_hammer_pole_solid_and_spiked():
    h = rd("scripts/obstacles/rotating_hammer.gd")
    assert "PoleBody" in h and "CylinderShape3D" in h and "_add_spikes" in h

def test_results_rows_and_effects():
    assert "_result_row" in rd("scripts/results_screen.gd") and "_header_row" in rd("scripts/results_screen.gd")
    assert "_spawn_burst" in rd("scripts/player_controller.gd")
    assert "GENERATED_MUSIC := true" in rd("scripts/audio_manager.gd")


def test_sudden_death_and_bumper():
    rm = rd("scripts/round_manager.gd")
    assert "_process_sudden_death" in rm and "_rpc_sudden_death" in rm and "_sd_active = false" in rm
    assert "extends Node3D" in rd("scripts/obstacles/bumper.gd") and "BumperScript" in rd("scripts/map_builder.gd")
    assert "_on_random_pressed" in rd("scripts/map_picker.gd")


def test_sudden_death_shrinks_every_tiered_arena():
    """v5: the floor is built from concentric tiers, and only the solid core is unbreakable."""
    mb = rd("scripts/map_builder.gd")
    layer = rd("scripts/obstacles/arena_layer.gd")
    rm = rd("scripts/round_manager.gd")

    # the tier helper exists and never registers the core as collapsible
    assert "_tiered_disc" in mb and "_tiered_box" in mb and "_tier_at" in mb
    assert "i + 1 < bounds.size()" in mb, "the innermost tier must be built with drops=false"
    assert 'tier.set_script(ArenaLayerScript)' in mb
    assert layer.count("arena_crumble_tiles") >= 1 and "collapse_rank" in layer
    assert "@rpc(\"authority\", \"call_remote\", \"reliable\")" in layer

    # every arena map that can shrink says so, and the round manager respects the flag
    for key in ["map_cloud", "map_ring", "map_tiles", "map_islands", "map_twister",
                "map_plaza", "map_mini_tiles", "map_split_ring"]:
        block = mb.split('"%s"' % key)[0]
        assert block, key
    assert mb.count('"shrinkable": true') >= 8, "the shrinkable maps must advertise it"
    assert 'bool(_map_info().get("shrinkable", false))' in rm
    assert "func _map_info() -> Dictionary" in rm
    assert "sudden_death_supported" in rm

    # obstacles are parented to the tier they stand on, so they fall with their own floor
    assert "_tier_at(tiers" in mb
    assert "_bumpers(" in mb

    # the collapse order must be tier-first, and it must never eat the whole floor
    assert "func _next_tier(" in rm and "func _loose_pieces(" in rm
    assert "_sd_loose_guard" in rm
    assert "for i in mini(3, loose.size()):" in rm

    # a sudden-death alarm exists in both languages and is actually played
    loc = rd("scripts/locale.gd")
    assert loc.count('"sudden_death"') == 2
    assert '"alarm"' in rd("scripts/audio_manager.gd")
    assert 'AudioManager.play("alarm"' in rm


def test_engine_level_sudden_death_regression_is_wired():
    """The engine-level test that really builds the arenas must ship with the project."""
    import os
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    assert os.path.exists(os.path.join(root, "tests", "sudden_death_test.gd"))
    assert os.path.exists(os.path.join(root, "tests", "sudden_death_test.tscn"))
    gd = rd("tests/sudden_death_test.gd")
    assert "collapse_rank" in gd and "can_be_event_triggered" in gd


def test_map_picker_random_confirms_in_one_tap():
    mp = rd("scripts/map_picker.gd")
    block = mp.split("func _on_random_pressed")[1].split("func ")[0]
    assert "_pick(" in block, "the dice button must confirm, not just preview"


def test_powerups_wired():
    pu, rm, pc = rd("scripts/powerups.gd"), rd("scripts/round_manager.gd"), rd("scripts/player_controller.gd")
    assert "_rpc_request_collect" in pu and "get_remote_sender_id" in pu and "_rpc_collected" in pu
    assert "PowerupsScript.new()" in rm and 'powerups.name = "PowerUps"' in rm
    assert "const SHIELD_PU := 2" in pc
    assert "func apply_powerup" in pc and "_pu_type == SHIELD_PU" in pc and "shield_used" in pc
    assert '"pickup"' in rd("scripts/audio_manager.gd")
    lo = rd("scripts/locale.gd")
    for k in ["pu_speed", "pu_boots", "pu_shield"]:
        assert lo.count('"%s"' % k) == 2


def test_layered_music_wired():
    au, rm = rd("scripts/audio_manager.gd"), rd("scripts/round_manager.gd")
    assert "func set_music_intensity" in au and "_build_music_extra" in au and "_layer_players" in au
    assert "_update_music_intensity()" in rm and "set_music_intensity(0)" in rm


def test_local_marker():
    pc = rd("scripts/player_controller.gd")
    assert "_build_local_marker()" in pc and "func _tick_marker" in pc and "_tick_marker(delta)" in pc


def test_giant_fist():
    assert "consume_fist" in rd("scripts/powerups.gd") and "powerups.consume_fist(attacker_id)" in rd("scripts/round_manager.gd")
    assert rd("scripts/locale.gd").count('"pu_fist"') == 2


def test_map_voting():
    nm, lb = rd("scripts/network_manager.gd"), rd("scripts/lobby_manager.gd")
    assert "func cast_map_vote" in nm and "_rpc_vote_map" in nm and "get_remote_sender_id" in nm
    assert "_resolve_map_votes()" in nm and "vote_tally" in nm and "map_votes.clear()" in nm
    assert "cast_map_vote" in lb and "_vote_label" in lb and "_map_btn.disabled = false" in lb
    assert rd("scripts/locale.gd").count('"map_votes"') == 2


def test_face_hitstop_rotation():
    v, f = rd("scripts/character/contender_visuals.gd"), rd("scripts/character/contender_face.gd")
    assert "FaceScript.new()" in v and "_update_face" in v and "BoneAttachment3D" in f and "func update" in f
    pc = rd("scripts/player_controller.gd")
    assert "_hit_stop(0.07)" in pc and "ignore_time_scale" not in pc and "create_timer(real_seconds, true, false, true)" in pc
    assert "Engine.time_scale = 1.0" in rd("scripts/round_manager.gd")
    nm, gm = rd("scripts/network_manager.gd"), rd("scripts/game_manager.gd")
    assert "_rotate_map()" in nm and "func next_map_id" in gm and "next_map_id" in nm
    for k in ["hitstop", "rotate_maps"]:
        assert '"%s"' % k in rd("scripts/settings_manager.gd") and rd("scripts/locale.gd").count('"%s"' % k) == 2


def test_coins_shop_and_hats():
    sm, acc = rd("scripts/save_manager.gd"), rd("scripts/accessories.gd")
    assert "NAME_CHANGE_COST := 100" in sm and "func change_name" in sm and "func buy_hat" in sm and "func equip_hat" in sm
    # the name must never be reset for free
    reset = sm.split("func reset_defaults")[1].split("\nfunc ")[0]
    assert "player_name" not in reset
    assert "coins" in sm.split("func save_profile")[1].split("\nfunc ")[0] and "func record_match(won: bool, kos := 0)" in sm
    ids = re.findall(r'\{"id": "(\w+)", "key": "(acc_\w+)", "price": (\d+)\}', acc)
    assert len(ids) == 8 and all(f'case "{i}"' not in acc for i, _, _ in ids)
    for i, k, price in ids:
        assert f'"{i}":' in acc and int(price) > 0
        assert rd("scripts/locale.gd").count(f'"{k}"') == 2
    for k in ["coins", "accessories", "acc_buy", "need_coins", "need_coins_name", "name_cost", "name_first_free", "coins_earned", "acc_none"]:
        assert rd("scripts/locale.gd").count(f'"{k}"') == 2, k
    nm = rd("scripts/network_manager.gd")
    assert "_rpc_set_hat" in nm and "AccessoriesLib.is_valid(hat)" in nm and '"hat"' in nm
    cm = rd("scripts/customization_menu.gd")
    assert "SaveManager.buy_hat" in cm and 'err == "need_coins"' in cm and "set_hat(" in cm
    assert "p.hat_id = hat" in rd("scripts/round_manager.gd") and "set_hat(hat_id)" in rd("scripts/player_controller.gd")


def test_floor_zones_and_new_maps():
    fz, pc, mb = rd("scripts/obstacles/floor_zone.gd"), rd("scripts/player_controller.gd"), rd("scripts/map_builder.gd")
    for w in ["CONVEYOR", "ICE", "FAN", "func influence_at", "func wind_level", "floor_zones"]:
        assert w in fz
    # floor zones are wired into movement via the (allocation-free) member-var accumulators
    assert "_query_zones(on_floor)" in pc and "_zone_ice" in pc and "zone_push" in pc
    for fn in ["_build_ice_rink", "_build_conveyor_mill", "_build_wind_tunnel"]:
        assert f"static func {fn}" in mb
    # every zone is created with the generic helper (parent = a tier, so it falls with its floor in Sudden Death)
    assert mb.count("_zone(arena,") >= 9
    # belts are placed clockwise: N east, E south, S west, W north
    assert "Vector3(0, 0, -5.5), 0.0" in mb and "Vector3(5.5, 0, 0), -90.0" in mb


def test_magnet_and_aim_line():
    pu, pc = rd("scripts/powerups.gd"), rd("scripts/player_controller.gd")
    assert '"pu_magnet"' in pu and "MAGNET_TYPE := 4" in pu and "_pull_items_to_magnets" in pu
    assert "MAGNET_PU := 4" in pc and "func _magnet_pull" in pc and "_pu_field" in pc
    assert "func _tick_aim" in pc and "_tick_aim()" in pc and "top_level = true" in pc and '"aim_line"' in pc
    for k in ["aim_line", "pu_magnet"]:
        assert rd("scripts/locale.gd").count(f'"{k}"') == 2
    assert '"aim_line"' in rd("scripts/settings_manager.gd") and '"aim_line"' in rd("scripts/settings_menu.gd")


def test_procedural_floor_detail():
    """Floors/tier tops get procedural detail from a shader (no textures), and
    the falling-tile flash still works with a ShaderMaterial."""
    sc = rd("scripts/scenery.gd")
    mb = rd("scripts/map_builder.gd")
    ft = rd("scripts/obstacles/falling_tile.gd")

    # the shader exists and only writes ALBEDO/ROUGHNESS (never ALPHA: stays opaque)
    shader = rd("assets/shaders/floor_detail.gdshader")
    assert 'const FLOOR_DETAIL_SHADER := preload("res://assets/shaders/floor_detail.gdshader")' in sc
    assert "ALBEDO = albedo;" in shader and "ROUGHNESS = roughness;" in shader
    assert "ALPHA" not in shader
    assert "texture(" not in shader, "no texture lookups"
    assert "smoothstep" in shader and "mod(cell.x + cell.y, 2.0)" in shader

    # floor_mat: MEDIUM/HIGH use the shader, LOW falls back to the flat material
    assert "static func floor_mat(" in sc and "_low_quality()" in sc.split("static func floor_mat(")[1].split("\nstatic func ")[0]

    # the tier/tile top faces use it (disc checker tiles, plaza tops + quarters, donut, center)
    assert mb.count("Scenery.floor_mat(") >= 5
    assert "tile.material = tmat" in mb and "vertex_color_use_as_albedo" in mb

    # falling tiles still flash on warning and cool as they fall, on both backends
    assert "_shader_mat.set_shader_parameter(\"flash\", a)" in ft
    assert "_mat is StandardMaterial3D" in ft
    assert "_flash(0.5 + 0.5 * sin(_timer * 40.0))" in ft
    assert "func _fade_out()" in ft
    # the transparency write can never be reached by a ShaderMaterial (no such property)
    start = ft.index("func _start_fall()")
    assert ft[start:].index("if _mat is StandardMaterial3D:") < ft[start:].index("std.transparency")


def test_no_variant_inference_on_untyped_nodes():
    """Godot 4 refuses `var x := <Variant>` (parse error). These receivers are untyped Nodes, so their calls return Variant."""
    import glob
    bad = []
    pat = re.compile(r'\bvar\s+\w+\s*:= (?!int\(|float\(|str\(|bool\()[^#\n]*(?<![\(\w.])(rm\.|round_manager\.|powerups\.)')
    for f in glob.glob(str(R / "scripts" / "**" / "*.gd"), recursive=True):
        for n, line in enumerate(open(f, encoding="utf8"), 1):
            if pat.search(line):
                bad.append(f"{f}:{n}: {line.strip()}")
    assert not bad, bad
