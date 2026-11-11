#!/usr/bin/env python3
"""Source-level guards for bugs found by running the project in Godot 4.3 (Fix pass 12)."""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from invariant_test_utils import register_checks, run_checks

ROOT = Path(__file__).resolve().parents[1]
RESERVED = {"breakpoint", "signal", "class", "match", "var", "const", "enum", "static", "func", "in", "as", "is",
            "and", "or", "not", "self", "super", "await", "trait", "namespace", "preload", "pass", "if", "elif",
            "else", "for", "while", "return", "void", "extends", "assert", "yield"}

def reserved_param_hits():
    hits = []
    for path in (ROOT / "scripts").rglob("*.gd"):
        for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            m = re.match(r"\s*(?:static\s+)?func\s+\w+\((.*)\)", line)
            if not m:
                continue
            for part in m.group(1).split(","):
                name = part.strip().split(":")[0].split("=")[0].strip()
                if name in RESERVED:
                    hits.append(f"{path.name}:{n}:{name}")
    return hits

disc = (ROOT / "scripts/lan_discovery.gd").read_text(encoding="utf-8")
cust = (ROOT / "scripts/customization_menu.gd").read_text(encoding="utf-8")
lobby = (ROOT / "scripts/lobby_manager.gd").read_text(encoding="utf-8")

CHECKS = {
    "no GDScript function parameter uses a reserved keyword": not reserved_param_hits(),
    "ui_kit is_compact uses a legal parameter name": "min_width := 900.0" in (ROOT / "scripts/ui_kit.gd").read_text(encoding="utf-8"),
    "discovery rate limit is keyed per source and message type": 'gap_key := "%s|%s" % [ip, kind]' in disc,
    "join probes are answered with their own message type": '_answer(from_ip, from_port, str(msg["n"]), t)' in disc,
    "customization preview camera aims without needing the tree": "look_at_from_position" in cust and "cam.look_at(" not in cust,
    "virtual keyboard is only queried when supported": "FEATURE_VIRTUAL_KEYBOARD" in lobby,
}

register_checks(globals(), CHECKS)

if __name__ == "__main__":
    sys.exit(run_checks(CHECKS))
