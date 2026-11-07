from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
const = (ROOT / "scripts/game_constants.gd").read_text()
builder = (ROOT / "scripts/map_builder.gd").read_text()
player = (ROOT / "scripts/player_controller.gd").read_text()
round_manager = (ROOT / "scripts/round_manager.gd").read_text()
lobby = (ROOT / "scripts/lobby_manager.gd").read_text()
menu = (ROOT / "scripts/main_menu.gd").read_text()
locale = (ROOT / "scripts/locale.gd").read_text()
voice = (ROOT / "scripts/voice_chat.gd").read_text()

checks = {
    "trampoline mode registered": "const MODE_TRAMPOLINE := 4" in const and "const MODE_COUNT := 5" in const,
    "five trampoline maps registered": all(k in const for k in ["map_bounce_dome", "map_neon_springs", "map_candy_cloud", "map_sky_bounce", "map_pinball_bounce"]),
    "all trampoline maps built": all(k in builder for k in ["MAP_BOUNCE_DOME", "MAP_NEON_SPRINGS", "MAP_CANDY_CLOUD", "MAP_SKY_BOUNCE", "MAP_PINBALL_BOUNCE"]),
    "bounce surface metadata": 'set_meta("bounce_strength"' in builder and 'add_to_group("trampoline_surfaces")' in builder,
    "player bounce is authority-only": "not is_multiplayer_authority()" in player and "MODE_TRAMPOLINE" in player,
    "trampoline players can fight": "or mode == GameConstants.MODE_TRAMPOLINE" in round_manager,
    "trampoline uses the respawn score loop": "func is_respawn_score_mode() -> bool:" in round_manager and "mode == GameConstants.MODE_TRAMPOLINE" in round_manager[round_manager.index("func is_respawn_score_mode"):round_manager.index("func hider_team")],
    "trampoline fall processing uses authoritative KO snapshots": "if is_respawn_score_mode():\n\t\t_ko_process_pending()" in round_manager and "if not is_respawn_score_mode() or _ko_respawn_at.is_empty()" in round_manager,
    "trampoline is timed and does not end at KO target": "TRAMPOLINE_DURATION := 120.0" in const and "if mode == GameConstants.MODE_TRAMPOLINE:\n\t\treturn\n\tfor id in ko_kos.keys():" in round_manager,
    "trampoline live board shows KOs and falls": "round_manager.is_respawn_score_mode()" in (ROOT / "scripts/gameplay_hud.gd").read_text() and "%dK / %dF" in (ROOT / "scripts/gameplay_hud.gd").read_text(),
    "lobby mode selector includes trampoline": '"mode_trampoline"' in lobby,
    "solo selector includes trampoline": '"mode_trampoline"' in menu,
    "Arabic and English map/mode labels": locale.count('"mode_trampoline"') == 2 and locale.count('"map_bounce_dome"') == 2,
    "self monitoring restricted to mic test": "if on and not test_mode" in voice and "if monitor and not test_mode" in voice,
    "raw microphone bus always muted": "AudioServer.set_bus_mute(mic_idx, true)" in voice,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("PASS" if ok else "FAIL") + " - " + name)
if failed:
    raise SystemExit(1)
print(f"{len(checks)}/{len(checks)} trampoline/audio source invariants passed")
