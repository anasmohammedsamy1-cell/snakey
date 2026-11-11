#!/usr/bin/env python3
"""Source-level invariants for authoritative match start and rematch paths."""
from pathlib import Path

source = (Path(__file__).resolve().parents[1] / "scripts" / "network_manager.gd").read_text()

def block(name: str, next_marker: str) -> str:
    start = source.index(f"func {name}(")
    end = source.index(next_marker, start)
    return source[start:end]

start = block("start_match", "\n\n## Shared launch path")
launch = block("_launch_match", "\n\nfunc return_to_lobby")
rematch = block("rematch", "\n\nfunc add_score")
checks = {
    "fresh match start requires host authority": "not is_host" in start,
    "fresh match start requires an online session": "not online" in start,
    "fresh match start rejects an already-running match": "match_in_progress" in start,
    "fresh match start enforces can_start readiness and team rules": "not can_start()" in start,
    "validated start delegates to one shared launch path": "_launch_match()" in start,
    "shared launch marks match active": "match_in_progress = true" in launch,
    "shared launch clears ready flags": 'players[id]["ready"] = false' in launch,
    "shared launch builds bot teams": 'GameManager.make_bot_teams(cfg, humans)' in launch,
    "rematch remains host-only and online-only": "not online or not is_host" in rematch,
    "rematch requires an active match lifecycle": "not match_in_progress" in rematch,
    "hide-and-seek rematch swaps hider team": 'cfg["hider_team"] = 1 - int(cfg.get("hider_team", 0))' in rematch,
    "rematch bypasses lobby readiness through shared launch": "_launch_match()" in rematch and "start_match()" not in rematch,
}
from invariant_test_utils import register_checks, run_checks

register_checks(globals(), checks)

if __name__ == "__main__":
    raise SystemExit(run_checks(checks))
