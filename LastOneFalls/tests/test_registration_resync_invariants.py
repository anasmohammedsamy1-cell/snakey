#!/usr/bin/env python3
"""Source-level checks for idempotent registration snapshot recovery."""
from pathlib import Path

source = (Path(__file__).resolve().parents[1] / "scripts" / "network_manager.gd").read_text(encoding="utf-8")
start = source.index("func _rpc_register(")
end = source.index("\n\n@rpc", start)
register = source[start:end]
duplicate = register[register.index("if players.has(id):"):register.index("if players.size() >= max_players:")]

checks = {
    "duplicate registration does not create a second player": "players[id] =" not in duplicate,
    "duplicate registration resends the authoritative player snapshot": "_rpc_player_list.rpc_id(id, players)" in duplicate,
    "duplicate registration resends current match configuration": "_rpc_cfg.rpc_id(id, cfg)" in duplicate,
    "duplicate recovery returns before new-player insertion": duplicate.index("return") < register.index("players[id] ="),
    "registration still rejects active matches": "if match_in_progress:" in register,
    "registration still validates remote sender": "if id <= 1:" in register,
}
from invariant_test_utils import register_checks, run_checks

register_checks(globals(), checks)

if __name__ == "__main__":
    raise SystemExit(run_checks(checks))
