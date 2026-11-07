from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")

def test_audio_buses_are_independent():
    source = read("scripts/settings_manager.gd")
    for bus in ("Music", "SFX", "Environment", "Character", "UI", "Voice"):
        assert f'"{bus}"' in source
    for key in ("music_volume", "sfx_volume", "environment_volume", "character_volume", "ui_volume", "voice_volume", "game_audio_muted"):
        assert f'"{key}"' in source

def test_voice_ducking_is_optional_and_activity_driven():
    audio = read("scripts/audio_manager.gd")
    voice = read("scripts/voice_chat.gd")
    assert 'get_setting("audio_ducking")' in audio
    assert 'has_voice_activity' in audio and 'func has_voice_activity()' in voice
    assert "MUSIC_DUCK_DB" in audio
    settings = read("scripts/settings_manager.gd")
    assert "game_audio_muted" in settings and "set_bus_mute(game_bus_idx, game_muted)" in settings
    assert 'for bus_name in ["Music", "SFX", "Environment", "Character", "UI"]' in settings

def test_generated_audio_has_headroom_and_comfort_limiter():
    audio = read("scripts/audio_manager.gd")
    assert "0.72 / peak" in audio
    assert 'get_setting("audio_comfort")' in audio
    assert "max_effect_db" in audio

def test_sound_retrigger_guard_and_pool_are_present():
    audio = read("scripts/audio_manager.gd")
    assert "SOUND_COOLDOWN" in audio
    assert "POOL_SIZE := 14" in audio
    assert "_last_played" in audio
    assert "_bus_priority" in audio and "request_priority < lowest_priority" in audio

def test_footsteps_are_grounded_and_not_remote_puppet_spam():
    player = read("scripts/player_controller.gd")
    audio = read("scripts/audio_manager.gd")
    assert "func _update_footsteps" in player
    assert "not is_local and not is_bot" in player
    assert '"footstep_a"' in audio and '"footstep_b"' in audio

def test_audio_settings_expose_independent_mix_and_comfort():
    menu = read("scripts/settings_menu.gd")
    for label in ("character_volume", "environment_volume", "ui_volume", "audio_comfort", "audio_ducking", "game_audio_muted"):
        assert label in menu

def test_new_audio_controls_are_localized_in_both_languages():
    locale = read("scripts/locale.gd")
    for key in ("character_volume", "environment_volume", "ui_volume", "audio_comfort", "audio_ducking", "game_audio_muted"):
        assert locale.count(f'"{key}"') >= 2
