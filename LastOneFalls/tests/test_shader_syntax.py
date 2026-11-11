#!/usr/bin/env python3
"""Source-level syntax checks for Godot 4 .gdshader files.
Run from the project root: python3 -m pytest tests/test_shader_syntax.py -q

Fails if any .gdshader under assets/shaders contains:
- hint_color (should be source_color)
- hint_albedo 
- hint_white
"""

import re
from pathlib import Path

def check_shaders():
    root = Path(__file__).resolve().parents[1]
    shader_dir = root / "assets" / "shaders"
    errors = []

    for shader_file in shader_dir.glob("*.gdshader"):
        content = shader_file.read_text(encoding="utf-8")
        lines = content.split("\n")

        for i, line in enumerate(lines, 1):
            line_stripped = line.strip()

            # Check for hint_color
            if "hint_color" in line:
                errors.append(f"{shader_file.name}:{i}: Godot 4 invalid hint 'hint_color' (should be 'source_color')")

            # Check for hint_albedo
            if "hint_albedo" in line:
                errors.append(f"{shader_file.name}:{i}: Godot 4 invalid hint 'hint_albedo'")

            # Check for hint_white
            if "hint_white" in line:
                errors.append(f"{shader_file.name}:{i}: Godot 4 invalid hint 'hint_white'")

    return errors

if __name__ == "__main__":
    shader_errors = check_shaders()
    if shader_errors:
        print("Shader syntax errors found:")
        for error in shader_errors:
            print("  " + error)
        raise SystemExit(1)
    else:
        print("All shaders pass syntax checks")