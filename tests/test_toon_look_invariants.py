#!/usr/bin/env python3
"""Source-level guards for the cheap toon look + inverted-hull outline.

The toon look must be switchable with one constant in contender_visuals.gd, the
recolor shader must gain a light() that quantises the diffuse light into three
smoothstep bands without touching the recolor logic or uniforms, and the outline
is a separate inverted-hull shader file attached as next_pass on the recolor
material (MEDIUM / HIGH presets only, skipped on LOW).
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from invariant_test_utils import register_checks, run_checks

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


visuals = read("scripts/character/contender_visuals.gd")
outline = read("assets/shaders/outline.gdshader")
scenery = read("scripts/scenery.gd")
customization = read("scripts/customization_menu.gd")

shader_code = visuals.split('const RECOLOR_SHADER := """', 1)[1].split('"""', 1)[0]
light_body = shader_code.split("void light() {", 1)[1].split("}", 1)[0]
outline_pass_body = visuals.split("func _outline_pass() -> ShaderMaterial:", 1)[1].split("\n\nfunc ", 1)[0]
quality_from_settings = visuals.split("func _quality_from_settings() -> int:", 1)[1].split("\n\nfunc ", 1)[0]
apply_tint = visuals.split("func _apply_tint() -> void:", 1)[1].split("\n\n\n", 1)[0]

CHECKS = {
    "the toon look is switchable with one constant":
        "var TOON_ENABLED := true" in visuals,
    "TOON_ENABLED is documented next to the other visual flags":
        re.search(r"var TOON_ENABLED := true.*toon look & outline", visuals) is not None,
    "the recolor shader keeps its render_mode for Godot 4 Compatibility":
        "render_mode diffuse_burley, specular_schlick_ggx;" in shader_code,
    "the recolor shader keeps all of its uniforms":
        all(u in shader_code for u in [
            "uniform sampler2D albedo_texture", "uniform sampler2D normal_texture",
            "uniform bool use_normal", "uniform float normal_scale",
            "uniform vec4 body_color", "uniform float recolor_strength",
            "uniform float metallic", "uniform float roughness",
            "uniform float specular",
        ]),
    "the recolor fragment() logic is untouched":
        "void fragment() {" in shader_code
        and "vec3 albedo = mix(source.rgb, recolored, neutral * recolor_strength);" in shader_code
        and "float luminance = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));" in shader_code
        and "vec3 recolored = body_color.rgb * (0.45 + 0.75 * shade);" in shader_code,
    "the player colour is pushed away from grey (vibrance)":
        "uniform float body_saturation = 1.35;" in shader_code
        and "albedo = mix(vec3(albedo_lum), albedo, body_saturation);" in shader_code
        and "ALBEDO = clamp(albedo, vec3(0.0), vec3(1.0));" in shader_code,
    "the recolor shader defines a light() function":
        "void light() {" in shader_code,
    "light() quantises the diffuse light into smoothstep bands":
        light_body.count("smoothstep(") >= 3 and "LIGHT_COLOR" in light_body,
    "light() writes DIFFUSE_LIGHT for the renderer":
        "DIFFUSE_LIGHT =" in light_body,
    "light() only uses identifiers available there (NORMAL / LIGHT / LIGHT_COLOR / ATTENUATION)":
        "dot(NORMAL, LIGHT)" in light_body
        and "LIGHT_DIRECTION" not in shader_code,
    "light() does not reuse fragment() locals":
        all(l not in light_body for l in ["luminance", "maxc", "minc", "neutral", "shade", "source"]),
    "the shader language comments are // (Godot 4 rejects #)":
        "#" not in light_body and "//" in light_body,
    "the outline shader file exists and is an inverted hull":
        "render_mode cull_front;" in outline,
    "the outline pushes vertices along NORMAL by 0.012 * outline_width":
        "VERTEX += NORMAL * (0.012 * outline_width);" in outline,
    "the outline renders a dark colour":
        re.search(r"uniform vec4 dark_color : source_color", outline) is not None
        and "ALBEDO = dark_color.rgb;" in outline,
    "the outline shader only uses // comments":
        "#" not in outline,
    "every effect shader pushes its colour away from grey":
        all(
            "uniform float vibrance" in f.read_text(encoding="utf-8")
            and "mix(vec3(lum)" in f.read_text(encoding="utf-8")
            for f in [
                ROOT / "assets" / "shaders" / "item_glow.gdshader",
                ROOT / "assets" / "shaders" / "burst_glow.gdshader",
                ROOT / "assets" / "shaders" / "magnet_field.gdshader",
                ROOT / "assets" / "shaders" / "shield_bubble.gdshader",
            ]
        ),
    "the HUD vivid shader raises saturation and contrast":
        re.search(r"uniform float saturation : hint_range\(0\.8, 1\.5\) = 1\.32;",
                  read("assets/shaders/hud_vivid.gdshader")) is not None
        and re.search(r"uniform float contrast : hint_range\(0\.8, 1\.5\) = 1\.25;",
                      read("assets/shaders/hud_vivid.gdshader")) is not None,
    "the world colour grade is more saturated and contrasted":
        scenery.count("env.adjustment_saturation = 1.45") >= 2
        and scenery.count("env.adjustment_contrast = 1.34") >= 2
        and "env.adjustment_saturation = 1.45" in customization
        and "env.adjustment_contrast = 1.34" in customization,
    "the outline shader is preloaded as a constant":
        'const OUTLINE_SHADER := preload("res://assets/shaders/outline.gdshader")' in visuals,
    "one shared outline material is cached statically":
        "static var _outline_material: ShaderMaterial" in visuals,
    "_outline_pass() returns null when the toon look is off or quality is LOW":
        "if not TOON_ENABLED or _effective_quality() <= 0:" in outline_pass_body,
    "_outline_pass() skips the LOW preset through the effective quality":
        "_effective_quality()" in outline_pass_body
        and "SettingsManager.PRESET_LOW:" in quality_from_settings
        and "return 0" in quality_from_settings
        and "return _quality if _quality >= 0 else _quality_from_settings()" in visuals,
    "the outline pass is attached as the recolor next_pass at build time":
        "recolor.set_next_pass(_outline_pass())" in apply_tint,
    "the outline width parameter is set when the material is created":
        'set_shader_parameter("outline_width", 1.0)' in outline_pass_body,
    "set_color() still targets the main recolor materials":
        "func set_color(color: Color) -> void:" in visuals
        and 'set_shader_parameter("body_color", _color)' in visuals,
    "no collision, physics or gameplay was touched":
        "The parent CharacterBody3D stays the only physics object." in visuals,
}

register_checks(globals(), CHECKS)

if __name__ == "__main__":
    sys.exit(run_checks(CHECKS))
