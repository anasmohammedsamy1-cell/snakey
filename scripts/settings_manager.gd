extends Node
## Autoload: SettingsManager
## Loads, saves and APPLIES every user setting. Every entry here has a real effect:
##  - graphics  -> viewport render scale, MSAA, shadows (arena sun), effects (particles/glow/fog)
##  - audio     -> audio bus volumes / mute
##  - controls  -> read live by touch_controls.gd and player_controller.gd
##  - gameplay  -> camera inversion, vibration, language

signal settings_changed(key: String, value: Variant)

const SAVE_PATH := "user://settings.cfg"

const PRESET_LOW := 0
const PRESET_MEDIUM := 1
const PRESET_HIGH := 2
const PRESET_CUSTOM := 3

const GRAPHICS_KEYS := ["render_scale", "shadows", "effects", "msaa"]

const SETTINGS_VERSION := 3      # medium preset now uses a lighter render scale

var defaults := {
	"graphics_preset": PRESET_MEDIUM,
	"render_scale": 0.85,          # Medium balances clarity and performance; High uses native resolution.
	"shadows": true,
	"effects": true,
	"msaa": true,
	"master_volume": 1.0,
	"music_volume": 0.6,
	"sfx_volume": 0.85,
	"environment_volume": 0.55,
	"character_volume": 0.85,
	"ui_volume": 0.70,
	"audio_ducking": true,
	"audio_comfort": true,
	"game_audio_muted": false,
	"muted": false,
	"camera_sensitivity": 1.0,
	"camera_distance": 6.0,
	"invert_camera_y": false,
	"joystick_size": 1.0,
	"joystick_opacity": 0.6,
	"joystick_sensitivity": 1.0,
	"button_size": 1.0,
	"button_opacity": 0.75,
	"controls_swapped": false,
	"vibration": true,
	"language": "en",
	"voice_enabled": true,
	"voice_open_mic": true,        # false = push to talk
	"voice_volume": 1.0,
	"mic_gain": 1.0,
}

## Settings that "RESET TO DEFAULTS" leaves alone (the language is not a gameplay setting).
const KEEP_ON_RESET := ["language"]

var settings: Dictionary = {}
var _applying_preset := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	settings = defaults.duplicate(true)
	_ensure_audio_buses()
	var first_run := not FileAccess.file_exists(SAVE_PATH)
	load_settings()
	apply_all()
	if first_run and is_mobile():
		apply_preset(PRESET_LOW)     # weak-phone friendly default; the player can raise it in Settings


func get_setting(key: String) -> Variant:
	if settings.has(key):
		return settings[key]
	return defaults.get(key)


func set_setting(key: String, value: Variant, save := true) -> void:
	settings[key] = value
	if key in GRAPHICS_KEYS and not _applying_preset:
		settings["graphics_preset"] = PRESET_CUSTOM
		settings_changed.emit("graphics_preset", PRESET_CUSTOM)
	_apply(key, value)
	settings_changed.emit(key, value)
	if save:
		save_settings()


func apply_preset(preset: int) -> void:
	_applying_preset = true
	match preset:
		PRESET_LOW:
			set_setting("render_scale", 0.65, false)
			set_setting("shadows", false, false)
			set_setting("effects", false, false)
			set_setting("msaa", false, false)
		PRESET_HIGH:
			set_setting("render_scale", 1.0, false)
			set_setting("shadows", true, false)
			set_setting("effects", true, false)
			set_setting("msaa", true, false)
		PRESET_MEDIUM:
			set_setting("render_scale", 0.85, false)
			set_setting("shadows", true, false)
			set_setting("effects", true, false)
			set_setting("msaa", true, false)
		_:
			set_setting("render_scale", 1.0, false)
			set_setting("shadows", true, false)
			set_setting("effects", true, false)
			set_setting("msaa", true, false)
	_applying_preset = false
	settings["graphics_preset"] = preset
	_apply("graphics_preset", preset) # Apply MSAA after the new preset is stored.
	settings_changed.emit("graphics_preset", preset)
	save_settings()


func apply_all() -> void:
	for key in settings.keys():
		_apply(key, settings[key])


func reset_to_defaults() -> void:
	var keep: Dictionary = {}
	for k in KEEP_ON_RESET:
		keep[k] = settings.get(k, defaults.get(k))
	settings = defaults.duplicate(true)
	# Reset on phones must not silently switch weak devices to expensive defaults.
	if is_mobile():
		settings["graphics_preset"] = PRESET_LOW
		settings["render_scale"] = 0.65
		settings["shadows"] = false
		settings["effects"] = false
		settings["msaa"] = false
	for k in keep.keys():
		settings[k] = keep[k]
	apply_all()
	save_settings()
	for key in settings.keys():
		settings_changed.emit(key, settings[key])


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var version := int(cfg.get_value("meta", "version", 1))
	for key in defaults.keys():
		if version < SETTINGS_VERSION and key in ["graphics_preset", "render_scale", "shadows", "effects", "msaa"]:
			continue       # older graphics presets are upgraded to the current defaults
		if cfg.has_section_key("settings", key):
			var value: Variant = cfg.get_value("settings", key, defaults[key])
			# Keep the stored type consistent with the default type.
			if typeof(value) == typeof(defaults[key]) or (typeof(value) in [TYPE_INT, TYPE_FLOAT] and typeof(defaults[key]) in [TYPE_INT, TYPE_FLOAT]):
				settings[key] = value


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", SETTINGS_VERSION)
	for key in settings.keys():
		cfg.set_value("settings", key, settings[key])
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("SettingsManager: could not save settings (error %d)" % err)


func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


# ---------------------------------------------------------------------------
# Applying

func _apply(key: String, value: Variant) -> void:
	var root := get_tree().root
	match key:
		"render_scale":
			root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			root.scaling_3d_scale = clampf(float(value), 0.5, 1.0)
		"msaa", "graphics_preset":
			var on := bool(settings.get("msaa", true))
			var high := int(settings.get("graphics_preset", PRESET_MEDIUM)) == PRESET_HIGH
			root.msaa_3d = (Viewport.MSAA_4X if high else Viewport.MSAA_2X) if on else Viewport.MSAA_DISABLED
			root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		"master_volume", "music_volume", "sfx_volume", "environment_volume", "character_volume", "ui_volume", "audio_ducking", "audio_comfort", "game_audio_muted", "muted", "voice_volume":
			_apply_audio()
		_:
			pass # Read live by the systems that need them (controls, camera, shadows...).


func _apply_audio() -> void:
	_set_bus_volume("Master", float(get_setting("master_volume")))
	_set_bus_volume("Music", float(get_setting("music_volume")))
	_set_bus_volume("SFX", float(get_setting("sfx_volume")))
	_set_bus_volume("Environment", float(get_setting("environment_volume")))
	_set_bus_volume("Character", float(get_setting("character_volume")))
	_set_bus_volume("UI", float(get_setting("ui_volume")))
	_set_bus_volume("Voice", float(get_setting("voice_volume")))
	var game_muted := bool(get_setting("game_audio_muted"))
	for bus_name in ["Music", "SFX", "Environment", "Character", "UI"]:
		var game_bus_idx := AudioServer.get_bus_index(bus_name)
		if game_bus_idx >= 0:
			AudioServer.set_bus_mute(game_bus_idx, game_muted)
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_mute(master_idx, bool(get_setting("muted")))


func refresh_audio() -> void:
	_apply_audio()


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	linear = clampf(linear, 0.0, 1.0)
	if linear <= 0.001:
		AudioServer.set_bus_volume_db(idx, -80.0)
	else:
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear))


## Creates independent game-audio buses at runtime; VoiceChat owns Voice/VoiceRec.
func _ensure_audio_buses() -> void:
	for bus_name in ["Music", "SFX", "Environment", "Character", "UI"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
