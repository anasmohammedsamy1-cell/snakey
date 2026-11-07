#!/usr/bin/env python3
"""Source-level invariants preventing lobby mutations during an active match."""
from pathlib import Path

source = (Path(__file__).resolve().parents[1] / "scripts" / "network_manager.gd").read_text()

def block(signature: str, next_marker: str) -> str:
    start = source.index(signature)
    end = source.index(next_marker, start)
    return source[start:end]

checks = {
    "host-side ready API rejects active-match calls": "if not online or match_in_progress:" in block("func set_ready(", "\n\n## Called after"),
    "host-side profile API rejects active-match calls": "if not online or match_in_progress:" in block("func update_local_info(", "\n\nfunc can_start"),
    "client ready RPC is rejected by host during a match": "if not multiplayer.is_server() or match_in_progress:" in block("func _rpc_set_ready(", "\n\n@rpc"),
    "client profile RPC is rejected by host during a match": "if not multiplayer.is_server() or match_in_progress:" in block("func _rpc_update_info(", "\n\n# ---------------------------------------------------------------------------"),
    "ready state mutation remains after the authoritative guard": block("func _rpc_set_ready(", "\n\n@rpc").index('players[id]["ready"] = value') > 0,
    "profile mutation remains after the authoritative guard": block("func _rpc_update_info(", "\n\n# ---------------------------------------------------------------------------").index('players[id]["name"] = SaveManager.sanitize_name(pname)') > 0,
    "host config changes are locked during a match": "if not online or not is_host or match_in_progress:" in block("func set_cfg_value(", "\n\n## Host only: put a player"),
    "host team assignment is locked during a match": "or match_in_progress" in block("func set_team(", "\n\nfunc auto_balance_teams"),
    "host auto-balance is locked during a match": "or match_in_progress" in block("func auto_balance_teams(", "\n\n## Host: next round"),
}
from invariant_test_utils import register_checks, run_checks

register_checks(globals(), checks)

if __name__ == "__main__":
    raise SystemExit(run_checks(checks))
