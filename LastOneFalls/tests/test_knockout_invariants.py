#!/usr/bin/env python3
"""Source-level invariants for KNOCKOUT mode (no Godot needed). Run from the project root:
    python3 tests/test_knockout_invariants.py
These checks complement, but do NOT replace, the runtime test tests/ko_test.tscn (needs Godot 4.3)."""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from invariant_test_utils import register_checks, run_checks

root = Path(__file__).resolve().parents[1]
rd = lambda p: (root / p).read_text(encoding="utf-8")
rm, const, net = rd("scripts/round_manager.gd"), rd("scripts/game_constants.gd"), rd("scripts/network_manager.gd")
lobby, menu, hud, res, loc, gm = (rd("scripts/lobby_manager.gd"), rd("scripts/main_menu.gd"), rd("scripts/gameplay_hud.gd"),
                                  rd("scripts/results_screen.gd"), rd("scripts/locale.gd"), rd("scripts/game_manager.gd"))

a = rm.index("# Knockout mode (host authoritative)")
b = rm.index("# Round end", a)
ko = rm[a:b]


def func_body(src, name):
    m = re.search(r"^func %s\(.*?(?=^func |^@rpc|\Z)" % re.escape(name), src, re.S | re.M)
    return m.group(0) if m else ""


checks = {}
# --- mode wiring
checks["MODE_KNOCKOUT = 3 and MODE_TRAMPOLINE = 4 and MODE_COUNT = 5"] = all(x in const for x in ("const MODE_KNOCKOUT := 3", "const MODE_TRAMPOLINE := 4", "const MODE_COUNT := 5"))
checks["existing mode ids unchanged"] = all(s in const for s in ("const MODE_FFA := 0", "const MODE_TEAMS := 1", "const MODE_HIDE := 2"))
checks["lobby cycles through all modes"] = "% GameConstants.MODE_COUNT" in lobby and '"mode_trampoline"' in lobby
checks["solo menu cycles through all modes"] = "% GameConstants.MODE_COUNT" in menu and '"mode_trampoline"' in menu
checks["host validates / clamps the mode"] = "clampi(int(value), 0, GameConstants.MODE_COUNT - 1)" in net
checks["KO lobby start needs no teams"] = "if GameConstants.uses_teams(mode):" in net
checks["team UI is hidden for KO"] = "GameConstants.uses_teams(mode)" in lobby and "GameConstants.uses_teams(mode)" in menu
checks["KO bots are not assigned to teams"] = "not GameConstants.uses_teams(mode)" in gm
checks["KO and trampoline are free-for-all combat modes"] = "mode == GameConstants.MODE_FFA or mode == GameConstants.MODE_KNOCKOUT or mode == GameConstants.MODE_TRAMPOLINE" in rm
# --- host authority
checks["KO section has no any_peer RPC"] = "any_peer" not in ko
checks["every KO RPC is authority + reliable"] = len(re.findall(r'@rpc\("authority", "call_remote", "reliable"\)', ko)) == len(re.findall(r"@rpc", ko)) >= 3
checks["client-side RPC handlers refuse to run on the host"] = all("multiplayer.is_server()" in func_body(ko, n) for n in ("_rpc_ko_event", "_rpc_ko_respawn", "_rpc_ko_snapshot"))
checks["_ko_register is host-only"] = "if not is_host or state != State.PLAYING or _ended:" in func_body(ko, "_ko_register")
checks["knockout counter is incremented only in _ko_register"] = len(re.findall(r"ko_kos\[killer\] = int\(ko_kos\.get", rm)) == 1 and "ko_kos[killer]" in func_body(ko, "_ko_register")
checks["clients mirror snapshots (no local increment in _apply_ko_event)"] = "+ 1" not in func_body(ko, "_apply_ko_event") and "_ko_load_snapshot(snap)" in func_body(ko, "_apply_ko_event")
checks["fall reports cannot carry a score"] = "func _rpc_report_fall(id: int)" in rm and "ko_kos" not in func_body(rm, "_rpc_report_fall")
checks["clients have no RPC that takes a score or killer"] = not re.search(r'@rpc\("any_peer"[^\n]*\)\nfunc \w+\([^)]*(killer|score|kos)', rm)
# --- duplicate prevention / simultaneity
reg = func_body(ko, "_ko_register")
checks["duplicate fall is ignored (alive flag)"] = "not bool(alive.get(victim, false))" in reg
checks["credit is consumed once"] = "_last_hit_by.erase(victim)" in reg
checks["alive flag flips before the event is built"] = reg.index("alive[victim] = false") < reg.index("_ko_snapshot()")
checks["victims in a frame are processed in id order"] = "batch.sort()" in func_body(ko, "_ko_process_pending")
checks["queue refuses duplicates already pending"] = "if _pending_elims.has(id):" in func_body(rm, "_queue_elimination")
checks["events carry a sequence number and replays are ignored"] = "if seq <= _ko_applied_seq:" in func_body(ko, "_apply_ko_event") and "ko_seq += 1" in reg
checks["credit window / self / departed attacker are rejected"] = all(s in func_body(ko, "_ko_attribute") for s in ("by == victim", "not players.has(by)", "KO_CREDIT_WINDOW"))
checks["stale fall reports after a respawn are ignored"] = "KO_FALL_GRACE" in func_body(rm, "_queue_elimination")
checks["spawn-protected players cannot be hit"] = "_ko_protect_until" in func_body(rm, "_server_arm")
checks["no score after the match ended"] = "or _ended:" in reg
# --- combat reuse
checks["no second combat system (KO uses _server_arm + _last_hit_by)"] = "func _server_arm" in rm and rm.count("func _server_arm") == 1 and "_last_hit_by[target_id] = {" in rm
checks["falls still go through report_fall / host check"] = "_queue_elimination(p.peer_id)" in rm and "_host_check_falls()" in rm
# --- end of match
checks["timer end uses the shared _end_round"] = '_end_round("time_up")' in rm
checks["target score ends the match"] = '_end_round("target_reached")' in ko and "KO_TARGET_SCORE" in ko
checks["leaving players cannot strand the match"] = '_end_round("opponents_left")' in rm
checks["final ranking uses the shared tie-break helper"] = "GameConstants.ko_rank_entries(entries)" in ko and "static func ko_before" in const
checks["tie-break order: kos, falls, earlier last knockout"] = const.index('int(a["kos"]) > int(b["kos"])') < const.index('int(a["falls"]) < int(b["falls"])') < const.index("ko_last_key(a) < ko_last_key(b)")
checks["no match points for a scoreless match"] = "if kos <= 0:" in const
checks["results are broadcast by the host only"] = "_rpc_round_ended.rpc(results, reason, win_team)" in rm
# --- other modes intact
checks["classic last-standing rule untouched"] = '_end_round("last_standing")' in rm and "var n := _count_alive()" in rm
checks["team brawl rule untouched"] = '_end_round("team_win" if teams_alive.size() == 1 else "draw")' in rm
checks["hide and seek rules untouched"] = '_end_round("seekers_win")' in rm and '_end_round("hiders_win")' in rm and "_server_catch" in rm
checks["practice respawn path untouched"] = "func _on_practice_fall" in rm and "if practice:\n\t\t_on_practice_fall(p)" in rm
checks["voice chat script untouched by this feature"] = "knockout" not in rd("scripts/voice_chat.gd").lower()
# --- UI
checks["HUD has a KO scoreboard + knockout feed"] = "_refresh_ko_board" in hud and "knockout_scored.connect" in hud and '"ko_feed"' in hud
checks["HUD shows rank and score of the local player"] = '"ko_rank_short"' in hud and '"ko_short"' in hud
checks["scoreboard is capped for small screens"] = "shown >= 5" in hud
checks["results screen has a KO row"] = 'r.get("ko_mode", false)' in res
checks["EN/AR strings exist for every KO key"] = all(len(re.findall(r'"%s":' % k, loc)) == 2 for k in ("mode_ko", "ko_feed", "ko_you_scored", "ko_knocked_out_by", "ko_short", "ko_rank_short", "ko_you_marker"))
checks["runtime KO test exists"] = (root / "tests/ko_test.gd").exists() and (root / "tests/ko_test.tscn").exists()

register_checks(globals(), checks)

if __name__ == "__main__":
    sys.exit(run_checks(checks))
