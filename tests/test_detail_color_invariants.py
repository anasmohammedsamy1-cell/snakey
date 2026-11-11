#!/usr/bin/env python3
"""Source-level guards for the customisable screws/gaps (detail) colour.

The detail colour follows the exact same path as the body colour: GameConstants
palette -> SaveManager profile -> NetworkManager player info -> RoundManager spawn
-> PlayerController.setup -> ContenderVisuals.build(detail) -> the recolor
shader's detail_color uniform, and it is pickable from the customisation screen.
Index -1 means "classic metal" so existing players keep the old look.
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from invariant_test_utils import register_checks, run_checks

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


gc = read("scripts/game_constants.gd")
save = read("scripts/save_manager.gd")
net = read("scripts/network_manager.gd")
rm = read("scripts/round_manager.gd")
pc = read("scripts/player_controller.gd")
cv = read("scripts/character/contender_visuals.gd")
menu = read("scripts/customization_menu.gd")
locale = read("scripts/locale.gd")
shader_code = cv.split('const RECOLOR_SHADER := """', 1)[1].split('"""', 1)[0]

spawn_block = rm.split("func _spawn_all() -> void:", 1)[1].split("\nfunc ", 1)[0]
setup_block = pc.split("func setup(id: int,", 1)[1].split("\nfunc ", 1)[0]
fragment_block = shader_code.split("void fragment() {", 1)[1].split("}", 1)[0]

CHECKS = {
    "the classic metal colour is a constant":
        "const DEFAULT_DETAIL_COLOR := Color(0.72, 0.75, 0.8)" in gc,
    "GameConstants resolves detail colours (-1 = metal)":
        "static func get_detail_color(index: int) -> Color:" in gc
        and "DEFAULT_DETAIL_COLOR if index < 0" in gc
        and "static func is_detail_color_valid(index: int) -> bool:" in gc,
    "the picker offers the metal swatch plus every colour preset":
        "static func detail_color_count() -> int:" in gc
        and "return color_count() + 1" in gc,
    "SaveManager keeps a detail index that defaults to the classic metal":
        "var detail_color_index := DEFAULT_DETAIL" in save
        and "const DEFAULT_DETAIL := -1" in save,
    "the detail colour survives save / load / reset":
        'cfg.set_value("profile", "detail", detail_color_index)' in save
        and 'cfg.get_value("profile", "detail", DEFAULT_DETAIL)' in save
        and "detail_color_index = DEFAULT_DETAIL" in save,
    "set_profile accepts and validates the detail colour":
        "func set_profile(new_name: String, new_color: int, new_detail: int = DEFAULT_DETAIL) -> String:" in save
        and "is_detail_color_valid(new_detail)" in save,
    "the local player info carries the detail colour":
        '"detail": SaveManager.detail_color_index' in net,
    "the join/update path replicates the detail colour":
        "_rpc_set_detail.rpc_id(1, SaveManager.detail_color_index)" in net
        and 'func _rpc_register(pname: String, color: int, detail: int = -1) -> void:' in net
        and "_sanitize_detail(detail)" in net
        and "func _rpc_set_detail(detail: int) -> void:" in net
        and 'players[1]["detail"] = SaveManager.detail_color_index' in net,
    "the offline spawn reads the saved detail colour":
        'int(info.get("detail", -1))' in spawn_block
        and "detail = SaveManager.detail_color_index" in spawn_block,
    "the spawn path forwards the detail index to the player":
        "_spawn_player(int(id), name_text, color, false, counters[grp], grp, hat, detail)" in spawn_block
        and re.search(r'func _spawn_player\(id: int, pname: String, color: int, bot: bool, spawn_index: int, group := 0, hat := "", detail := -1\)', rm) is not None,
    "the player stores the detail index and hands it to the visuals":
        "var detail_color_index := -1" in pc
        and "detail_color_index = detail_idx" in setup_block
        and "visuals.build(color, GameConstants.get_detail_color(detail_color_index))" in pc,
    "ContenderVisuals applies the detail colour at build time":
        "func build(color: Color, detail_color: Color = GameConstants.DEFAULT_DETAIL_COLOR) -> void:" in cv
        and 'recolor.set_shader_parameter("detail_color", _detail_color)' in cv,
    "set_detail_color() updates the live material":
        "func set_detail_color(color: Color) -> void:" in cv
        and 'set_shader_parameter("detail_color", _detail_color)' in cv
        and "set_detail_color(detail_color)" in cv,
    "the recolor shader tints the true screws/gaps only (near-black pixels)":
        "uniform vec4 detail_color : source_color" in shader_code
        and "uniform float detail_strength = 1.0;" in shader_code
        and "float metal = smoothstep(0.42, 0.25, luminance) * (1.0 - smoothstep(0.10, 0.25, saturation));" in fragment_block
        and "albedo = mix(albedo, detail, clamp(metal * detail_strength, 0.0, 1.0));" in fragment_block,
    "the body colour path is untouched":
        'recolor.set_shader_parameter("body_color", _color)' in cv
        and 'func set_color(color: Color) -> void:' in cv,
    "the customisation screen has a detail picker with live preview":
        "_detail_grid" in menu and "_detail_name" in menu
        and "_refresh_detail_swatches()" in menu
        and "_preview_char.set_detail_color(GameConstants.get_detail_color(index))" in menu
        and '"Detail%d" % i' in menu,
    "the picker gates locked colours and the metal swatch stays always available":
        "stored >= 0 and not SaveManager.is_color_unlocked(stored)" in menu
        and "if not GameConstants.is_detail_color_valid(index):" in menu,
    "save and reset carry the detail selection":
        "SaveManager.set_profile(_name_edit.text, _selected_color, _selected_detail)" in menu
        and "_selected_detail = SaveManager.detail_color_index" in menu
        and "_select_detail(_selected_detail)" in menu,
    "the detail colour is localised in English and Arabic":
        locale.count('"detail_color"') == 2 and locale.count('"detail_metal"') == 2,
}

register_checks(globals(), CHECKS)

if __name__ == "__main__":
    sys.exit(run_checks(CHECKS))
