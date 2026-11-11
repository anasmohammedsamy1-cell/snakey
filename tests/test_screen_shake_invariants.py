#!/usr/bin/env python3
"""Source-level guards for the trauma screen shake + dash FOV kick.

The old shake used randf_range() every frame. The new system must keep one
FastNoiseLite instance, decay trauma linearly, scale the offset by trauma
squared, expose add_trauma(), and be switchable with the "screen_shake" setting.
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from invariant_test_utils import register_checks, run_checks

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


controller = read("scripts/player_controller.gd")
settings = read("scripts/settings_manager.gd")
menu = read("scripts/settings_menu.gd")
locale = read("scripts/locale.gd")


def function_body(source, name):
    marker = f"func {name}("
    if marker not in source:
        return ""
    body = source.split(marker, 1)[1]
    return body.split("\nfunc ", 1)[0]


update_shake = function_body(controller, "_update_shake")
add_trauma = function_body(controller, "add_trauma")
fov_kick = function_body(controller, "_fov_kick")


CHECKS = {
    "screen_shake defaults to on":
        re.search(r'"screen_shake"\s*:\s*true', settings) is not None,
    "screen_shake toggle exists in the gameplay settings":
        '"screen_shake"' in menu and 'set_setting("screen_shake"' in menu,
    "screen_shake is localised in English and Arabic":
        locale.count('"screen_shake"') >= 2,
    "add_trauma is a public API":
        "func add_trauma(amount: float) -> void:" in controller,
    "trauma decays linearly at 1.6 per second":
        "const TRAUMA_DECAY := 1.6" in controller
        and "maxf(0.0, _trauma - TRAUMA_DECAY * delta)" in update_shake,
    "shake amplitude is trauma squared":
        "var amp := _trauma * _trauma" in update_shake,
    "camera shake uses one FastNoiseLite, not randf":
        "FastNoiseLite.new()" in controller
        and "get_noise_2d(" in update_shake
        and "randf" not in update_shake
        and "FastNoiseLite.new()" not in update_shake,
    "shake drives h_offset, v_offset and a small roll":
        "camera.h_offset" in update_shake
        and "camera.v_offset" in update_shake
        and "camera.rotation.z" in update_shake
        and "TRAUMA_MAX_ROLL := 1.5" in controller,
    "hit, landing and nearby KO replace the old _shake writes":
        re.search(r"\b_shake\b", controller) is None
        and "lerpf(0.35, 0.6" in controller
        and "add_trauma(0.15)" in controller
        and "add_trauma(0.25)" in controller,
    "online hit-stop raises trauma to at least 0.65":
        "if _trauma < 0.65:" in controller and "add_trauma(0.65 - _trauma)" in controller,
    "dash FOV kick tweens 70->78 and back with one tween":
        "FOV_KICK_DEGREES := 8.0" in controller
        and "FOV_KICK_IN := 0.08" in controller
        and "FOV_KICK_OUT := 0.3" in controller
        and "_fov_tween.kill()" in fov_kick
        and fov_kick.count('tween_property(camera, "fov"') == 2,
    "screen_shake off disables trauma and the FOV kick":
        'get_setting("screen_shake")' in add_trauma
        and 'get_setting("screen_shake")' in fov_kick
        and 'get_setting("screen_shake")' in update_shake,
}

register_checks(globals(), CHECKS)

if __name__ == "__main__":
    sys.exit(run_checks(CHECKS))
