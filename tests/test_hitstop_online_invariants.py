#!/usr/bin/env python3
"""Source-level guards for the online hit-stop.

Online the simulation must never be slowed down: movement is client-authoritative
and replicated every 0.05 s, so a one-peer Engine.time_scale change would desync
that player. Every Engine.time_scale assignment in player_controller.gd therefore
has to sit inside an `if not NetworkManager.online:` block. The offline time
freeze stays, and RoundManager._exit_tree keeps its safety restore.
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from invariant_test_utils import register_checks, run_checks

ROOT = Path(__file__).resolve().parents[1]
CONTROLLER = (ROOT / "scripts/player_controller.gd").read_text(encoding="utf-8")
ROUND_MANAGER = (ROOT / "scripts/round_manager.gd").read_text(encoding="utf-8")


def _indent(line):
    return len(line) - len(line.lstrip(" \t"))


def unguarded_time_scale_assignments(source):
    """Line numbers of Engine.time_scale assignments that are not inside an
    enclosing `if not NetworkManager.online:` block."""
    lines = source.splitlines()
    bad = []
    for index, line in enumerate(lines):
        code = line.split("#", 1)[0]
        if not re.search(r"\bEngine\.time_scale\s*=", code):
            continue
        walk_indent = _indent(line)
        guarded = False
        cursor = index - 1
        while cursor >= 0:
            previous = lines[cursor]
            previous_code = previous.split("#", 1)[0]
            if not previous_code.strip():
                cursor -= 1
                continue
            previous_indent = _indent(previous)
            if previous_indent < walk_indent:
                if re.match(r"\s*if\s+not\s+NetworkManager\.online\s*:", previous_code):
                    guarded = True
                    break
                if re.match(r"\s*(?:static\s+)?func\s+\w+\s*\(", previous_code):
                    break
                walk_indent = previous_indent
            cursor -= 1
        if not guarded:
            bad.append(index + 1)
    return bad


def _exit_tree_body(source):
    marker = "func _exit_tree() -> void:"
    if marker not in source:
        return ""
    return source.split(marker, 1)[1].split("\nfunc ", 1)[0]


CHECKS = {
    "online hit-stop never changes Engine.time_scale":
        not unguarded_time_scale_assignments(CONTROLLER),
    "hit-stop keeps the offline time freeze":
        "func _hit_stop(" in CONTROLLER and "Engine.time_scale = 0.06" in CONTROLLER,
    "round manager restores Engine.time_scale when the arena exits":
        "Engine.time_scale = 1.0" in _exit_tree_body(ROUND_MANAGER),
}

register_checks(globals(), CHECKS)

if __name__ == "__main__":
    sys.exit(run_checks(CHECKS))
