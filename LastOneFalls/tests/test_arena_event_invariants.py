#!/usr/bin/env python3
"""Source-level regression checks for arena event authority and pacing.
Run from the project root: python3 tests/test_arena_event_invariants.py
These checks complement, but do not replace, Godot runtime/network tests.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
round_src = (root / "scripts/round_manager.gd").read_text(encoding="utf-8")
tile_src = (root / "scripts/obstacles/falling_tile.gd").read_text(encoding="utf-8")
locale_src = (root / "scripts/locale.gd").read_text(encoding="utf-8")

checks = {}

# The host triggers its own tile before broadcasting call_remote RPC.
start = round_src.index("func _trigger_tile_tremor()")
end = round_src.index("func _set_arena_event", start)
block = round_src[start:end]
checks["host triggers local tile copy"] = "tile.trigger()" in block
checks["host broadcasts tile RPC after local trigger"] = block.index("tile.trigger()") < block.index("tile._rpc_trigger.rpc()")
checks["tile RPC is reliable authority call_remote"] = '@rpc("authority", "call_remote", "reliable")' in tile_src
checks["tile eligibility excludes non-idle states"] = "return state == TileState.IDLE and is_inside_tree()" in tile_src
checks["TILE TREMOR is only offered when crumble tiles exist"] = 'get_nodes_in_group("arena_crumble_tiles").is_empty()' in round_src
checks["adaptive event pacing is implemented"] = "func _adaptive_event_interval() -> float:" in round_src
checks["adaptive pacing is bounded"] = "clampf(interval, 10.0, 18.0)" in round_src
checks["event pacing protects final survivors"] = "survivor_ratio <= 0.25" in round_src
checks["English event announcement exists"] = '"event_tile_tremor"' in locale_src and "THE FLOOR IS BREAKING" in locale_src
checks["Arabic event announcement exists"] = '"event_tile_tremor"' in locale_src and "البلاطات تنهار" in locale_src

# Round end must clear the active event (no slippery floor / low gravity in the results phase).
er = round_src.index("func _end_round(")
checks["round end clears the active arena event"] = "_set_arena_event(ArenaEvent.NONE, 0.0)" in round_src[er:er + 400]

# player_controller.gd uses numeric event ids: they must match the enum order in round_manager.gd.
import re
enum_names = re.search(r"enum ArenaEvent \{([^}]*)\}", round_src).group(1).replace(" ", "").split(",")
ctrl_src = (root / "scripts/player_controller.gd").read_text(encoding="utf-8")
expect = {"LOW_GRAVITY": 1, "SPEED_SURGE": 2, "SLIPPERY_FLOOR": 3, "DASH_FRENZY": 4}
checks["controller event ids match the ArenaEvent enum order"] = (
    all(enum_names.index(k) == v for k, v in expect.items())
    and "arena_event == 4" in ctrl_src and "arena_event == 2" in ctrl_src
    and ctrl_src.count("arena_event == 3") == 2 and ctrl_src.count("arena_event == 1") == 2
)

from invariant_test_utils import register_checks, run_checks

register_checks(globals(), checks)

if __name__ == "__main__":
    raise SystemExit(run_checks(checks))
