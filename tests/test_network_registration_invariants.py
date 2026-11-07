#!/usr/bin/env python3
"""Static invariants for host-side LAN registration hardening."""
from pathlib import Path

source = (Path(__file__).resolve().parents[1] / "scripts" / "network_manager.gd").read_text()
start = source.index('func _rpc_register(')
end = source.index('\n\n@rpc', start)
register = source[start:end]
checks = {
    "registration handler is host-only": 'if not multiplayer.is_server()' in register,
    "sender id is validated": 'if id <= 1:' in register,
    "match lock is rechecked during registration": 'if match_in_progress:' in register,
    "late joiner receives explicit kick": '_rpc_kicked.rpc_id(id, GameManager.t("kicked_in_progress"))' in register,
    "duplicate registration is ignored": 'if players.has(id):' in register,
    "duplicate check precedes player mutation": register.index('if players.has(id):') < register.index('players[id] ='),
    "capacity is still enforced": 'if players.size() >= max_players:' in register,
    "nickname remains sanitized": 'SaveManager.sanitize_name(pname)' in register,
    "color remains bounded": 'posmod(color, GameConstants.color_count())' in register,
}
from invariant_test_utils import register_checks, run_checks

register_checks(globals(), checks)

if __name__ == "__main__":
    raise SystemExit(run_checks(checks))
