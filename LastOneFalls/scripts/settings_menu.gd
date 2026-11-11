extends Control
## Settings screen. Every control writes straight into SettingsManager, which
## applies the change immediately (render scale, MSAA, audio buses...) and
## saves it. Can be opened from the main menu or from the pause menu.

signal closed

const Cartoon := preload("res://scripts/cartoon_ui.gd")
const UIKit := preload("res://scripts/ui_kit.gd")

var _preset_buttons: Array = []
var _render_slider: HSlider
var _shadow_toggle: CheckButton
var _effects_toggle: CheckButton
var _msaa_toggle: CheckButton
var _confirm: Control = null
var _mic_overlay: Control = null
var _settings_scroll: ScrollContainer
var _section_headers: Array[Control] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	UIKit.dim_background(self)
	var panel := Cartoon.panel()
	var box := UIKit.vbox(10)
	panel.add_child(box)

	var compact_header := get_viewport().get_visible_rect().size.x < 560.0
	var header := BoxContainer.new()
	header.vertical = compact_header
	header.add_theme_constant_override("separation", 8)
	var screen_title := Cartoon.title(GameManager.t("settings"), 36)
	header.add_child(screen_title)
	header.add_child(UIKit.spacer())
	var reset_button := Cartoon.button(GameManager.t("reset_all"), _ask_reset, Cartoon.STYLE_DANGER, Vector2(0 if compact_header else 150, 52))
	reset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_button.add_theme_font_size_override("font_size", 18)
	header.add_child(reset_button)
	var back_button := Cartoon.button(GameManager.t("back"), _close, Cartoon.STYLE_PRIMARY, Vector2(0 if compact_header else 110, 52))
	back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_button.add_theme_font_size_override("font_size", 18)
	header.add_child(back_button)
	box.add_child(header)

	# Category shortcuts keep the long settings catalogue navigable without hiding options.
	var nav := GridContainer.new()
	nav.columns = 2 if compact_header else 3
	nav.add_theme_constant_override("h_separation", 6)
	nav.add_theme_constant_override("v_separation", 6)
	var category_keys := ["graphics", "audio", "voice", "controls", "gameplay"]
	for i in 5:
		var nav_button := Cartoon.button(GameManager.t(category_keys[i]), _jump_to_section.bind(i), Cartoon.STYLE_GHOST, Vector2(0, 46))
		nav_button.add_theme_font_size_override("font_size", 16)
		nav_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nav.add_child(nav_button)
	box.add_child(nav)

	_settings_scroll = ScrollContainer.new()
	_settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_settings_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_settings_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_settings_scroll)
	var list := UIKit.vbox(10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_scroll.add_child(list)

	# ---------------- GRAPHICS
	list.add_child(_make_section(GameManager.t("graphics")))
	var preset_row := BoxContainer.new()
	preset_row.add_theme_constant_override("separation", 8)
	var compact_settings := get_viewport().get_visible_rect().size.x < 760.0
	preset_row.vertical = compact_settings
	preset_row.add_child(Cartoon.label(GameManager.t("preset"), 20, Cartoon.WHITE, HORIZONTAL_ALIGNMENT_LEFT))
	var names := [GameManager.t("low"), GameManager.t("medium"), GameManager.t("high"), GameManager.t("potato")]
	var preset_ids := [SettingsManager.PRESET_LOW, SettingsManager.PRESET_MEDIUM, SettingsManager.PRESET_HIGH, SettingsManager.PRESET_POTATO]
	for i in names.size():
		var b := Cartoon.button(names[i], _on_preset.bind(preset_ids[i]), Cartoon.STYLE_NORMAL, Vector2(0 if compact_settings else 130, 52))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.set_meta("preset", preset_ids[i])
		preset_row.add_child(b)
		_preset_buttons.append(b)
	list.add_child(preset_row)
	var potato_desc := Cartoon.label(GameManager.t("potato_desc"), 15, Cartoon.INK_SOFT)
	potato_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	potato_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(potato_desc)
	var render_row := _slider_row(GameManager.t("render_scale"), 0.5, 1.0, 0.05, float(SettingsManager.get_setting("render_scale")), func(v: float) -> void: SettingsManager.set_setting("render_scale", v))
	_render_slider = render_row.get_node("Slider")
	list.add_child(render_row)
	var shadow_row := _toggle_row(GameManager.t("shadows"), bool(SettingsManager.get_setting("shadows")), func(v: bool) -> void: SettingsManager.set_setting("shadows", v))
	_shadow_toggle = shadow_row.get_node("Toggle")
	list.add_child(shadow_row)
	var effects_row := _toggle_row(GameManager.t("effects"), bool(SettingsManager.get_setting("effects")), func(v: bool) -> void: SettingsManager.set_setting("effects", v))
	_effects_toggle = effects_row.get_node("Toggle")
	list.add_child(effects_row)
	var msaa_row := _toggle_row(GameManager.t("msaa"), bool(SettingsManager.get_setting("msaa")), func(v: bool) -> void: SettingsManager.set_setting("msaa", v))
	_msaa_toggle = msaa_row.get_node("Toggle")
	list.add_child(msaa_row)
	_refresh_preset_buttons()

	# ---------------- AUDIO
	list.add_child(_make_section(GameManager.t("audio")))
	list.add_child(_slider_row(GameManager.t("master_volume"), 0.0, 1.0, 0.05, float(SettingsManager.get_setting("master_volume")), func(v: float) -> void: SettingsManager.set_setting("master_volume", v)))
	list.add_child(_slider_row(GameManager.t("music_volume"), 0.0, 1.0, 0.05, float(SettingsManager.get_setting("music_volume")), func(v: float) -> void: SettingsManager.set_setting("music_volume", v)))
	list.add_child(_slider_row(GameManager.t("sfx_volume"), 0.0, 1.0, 0.05, float(SettingsManager.get_setting("sfx_volume")), func(v: float) -> void:
		SettingsManager.set_setting("sfx_volume", v)
		AudioManager.play_ui("click", 0.0)
	))
	list.add_child(_slider_row(GameManager.t("character_volume"), 0.0, 1.0, 0.05, float(SettingsManager.get_setting("character_volume")), func(v: float) -> void: SettingsManager.set_setting("character_volume", v)))
	list.add_child(_slider_row(GameManager.t("environment_volume"), 0.0, 1.0, 0.05, float(SettingsManager.get_setting("environment_volume")), func(v: float) -> void: SettingsManager.set_setting("environment_volume", v)))
	list.add_child(_slider_row(GameManager.t("ui_volume"), 0.0, 1.0, 0.05, float(SettingsManager.get_setting("ui_volume")), func(v: float) -> void: SettingsManager.set_setting("ui_volume", v)))
	list.add_child(_toggle_row(GameManager.t("audio_comfort"), bool(SettingsManager.get_setting("audio_comfort")), func(v: bool) -> void: SettingsManager.set_setting("audio_comfort", v)))
	list.add_child(_toggle_row(GameManager.t("audio_ducking"), bool(SettingsManager.get_setting("audio_ducking")), func(v: bool) -> void: SettingsManager.set_setting("audio_ducking", v)))
	list.add_child(_toggle_row(GameManager.t("game_audio_muted"), bool(SettingsManager.get_setting("game_audio_muted")), func(v: bool) -> void: SettingsManager.set_setting("game_audio_muted", v)))
	list.add_child(_toggle_row(GameManager.t("mute"), bool(SettingsManager.get_setting("muted")), func(v: bool) -> void: SettingsManager.set_setting("muted", v)))

	# ---------------- VOICE
	list.add_child(_make_section(GameManager.t("voice")))
	list.add_child(_toggle_row(GameManager.t("voice_enable"), bool(SettingsManager.get_setting("voice_enabled")), func(v: bool) -> void: SettingsManager.set_setting("voice_enabled", v)))
	list.add_child(_toggle_row(GameManager.t("voice_open_mic"), bool(SettingsManager.get_setting("voice_open_mic")), func(v: bool) -> void: SettingsManager.set_setting("voice_open_mic", v)))
	list.add_child(_slider_row(GameManager.t("voice_volume"), 0.0, 1.0, 0.05, float(SettingsManager.get_setting("voice_volume")), func(v: float) -> void: SettingsManager.set_setting("voice_volume", v)))
	list.add_child(_slider_row(GameManager.t("mic_gain"), 0.3, 4.0, 0.1, float(SettingsManager.get_setting("mic_gain")), func(v: float) -> void: SettingsManager.set_setting("mic_gain", v)))
	list.add_child(Cartoon.button(GameManager.t("mic_test"), _open_mic_test, Cartoon.STYLE_NORMAL, Vector2(320, 56)))

	# ---------------- CONTROLS
	list.add_child(_make_section(GameManager.t("controls")))
	list.add_child(_slider_row(GameManager.t("camera_sensitivity"), 0.3, 2.5, 0.1, float(SettingsManager.get_setting("camera_sensitivity")), func(v: float) -> void: SettingsManager.set_setting("camera_sensitivity", v)))
	list.add_child(_slider_row(GameManager.t("camera_distance"), 3.5, 10.0, 0.5, float(SettingsManager.get_setting("camera_distance")), func(v: float) -> void: SettingsManager.set_setting("camera_distance", v), " m"))
	list.add_child(_slider_row(GameManager.t("joystick_size"), 0.7, 1.6, 0.05, float(SettingsManager.get_setting("joystick_size")), func(v: float) -> void: SettingsManager.set_setting("joystick_size", v)))
	list.add_child(_slider_row(GameManager.t("joystick_opacity"), 0.2, 1.0, 0.05, float(SettingsManager.get_setting("joystick_opacity")), func(v: float) -> void: SettingsManager.set_setting("joystick_opacity", v)))
	list.add_child(_slider_row(GameManager.t("joystick_sensitivity"), 0.6, 1.6, 0.05, float(SettingsManager.get_setting("joystick_sensitivity")), func(v: float) -> void: SettingsManager.set_setting("joystick_sensitivity", v)))
	list.add_child(_slider_row(GameManager.t("button_size"), 0.7, 1.6, 0.05, float(SettingsManager.get_setting("button_size")), func(v: float) -> void: SettingsManager.set_setting("button_size", v)))
	list.add_child(_slider_row(GameManager.t("button_opacity"), 0.2, 1.0, 0.05, float(SettingsManager.get_setting("button_opacity")), func(v: float) -> void: SettingsManager.set_setting("button_opacity", v)))
	list.add_child(_toggle_row(GameManager.t("swap_controls"), bool(SettingsManager.get_setting("controls_swapped")), func(v: bool) -> void: SettingsManager.set_setting("controls_swapped", v)))

	# ---------------- GAMEPLAY
	list.add_child(_make_section(GameManager.t("gameplay")))
	list.add_child(_toggle_row(GameManager.t("invert_camera"), bool(SettingsManager.get_setting("invert_camera_y")), func(v: bool) -> void: SettingsManager.set_setting("invert_camera_y", v)))
	list.add_child(_toggle_row(GameManager.t("vibration"), bool(SettingsManager.get_setting("vibration")), func(v: bool) -> void: SettingsManager.set_setting("vibration", v)))
	list.add_child(_toggle_row(GameManager.t("aim_line"), bool(SettingsManager.get_setting("aim_line")), func(v: bool) -> void: SettingsManager.set_setting("aim_line", v)))
	list.add_child(_toggle_row(GameManager.t("hitstop"), bool(SettingsManager.get_setting("hitstop")), func(v: bool) -> void: SettingsManager.set_setting("hitstop", v)))
	list.add_child(_toggle_row(GameManager.t("screen_shake"), bool(SettingsManager.get_setting("screen_shake")), func(v: bool) -> void: SettingsManager.set_setting("screen_shake", v)))
	list.add_child(_toggle_row(GameManager.t("rotate_maps"), bool(SettingsManager.get_setting("rotate_maps")), func(v: bool) -> void: SettingsManager.set_setting("rotate_maps", v)))
	var lang_row := BoxContainer.new()
	lang_row.vertical = get_viewport().get_visible_rect().size.x < 560.0
	lang_row.add_theme_constant_override("separation", 8)
	var lang_label := Cartoon.label(GameManager.t("language"), 22, Cartoon.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	lang_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lang_row.add_child(lang_label)
	var current_lang := str(SettingsManager.get_setting("language"))
	var lang_width := 0.0 if lang_row.vertical else 150.0
	var en_btn := Cartoon.button("English", func() -> void: _set_language("en"), Cartoon.STYLE_PRIMARY if current_lang == "en" else Cartoon.STYLE_NORMAL, Vector2(lang_width, 52))
	var ar_btn := Cartoon.button("العربية", func() -> void: _set_language("ar"), Cartoon.STYLE_PRIMARY if current_lang == "ar" else Cartoon.STYLE_NORMAL, Vector2(lang_width, 52))
	en_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ar_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lang_row.add_child(en_btn)
	lang_row.add_child(ar_btn)
	list.add_child(lang_row)
	list.add_child(Cartoon.label(GameManager.t("language_note"), 16, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_LEFT))
	list.add_child(UIKit.spacer(Vector2(0, 20), false))

	add_child(UIKit.centered(panel, Vector2(860, 620)))
	UIKit.add_fade_in(panel)


func _make_section(text: String) -> Label:
	var heading := Cartoon.label(text, 20, Cartoon.YELLOW, HORIZONTAL_ALIGNMENT_LEFT)
	heading.add_theme_font_size_override("font_size", 20)
	heading.add_theme_color_override("font_color", Cartoon.YELLOW)
	_section_headers.append(heading)
	return heading


func _jump_to_section(index: int) -> void:
	if index < 0 or index >= _section_headers.size() or _settings_scroll == null:
		return
	_settings_scroll.ensure_control_visible(_section_headers[index])


func _open_mic_test() -> void:
	if _mic_overlay != null and is_instance_valid(_mic_overlay):
		return
	_mic_overlay = preload("res://scripts/mic_test.gd").new()
	add_child(_mic_overlay)


## Reset to defaults: asks first, explains what changes, keeps the profile / stats / language.
func _ask_reset() -> void:
	if _confirm != null and is_instance_valid(_confirm):
		return
	_confirm = Control.new()
	_confirm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_confirm)
	UIKit.dim_background(_confirm, Color(0, 0, 0, 0.6))
	var panel := Cartoon.panel()
	var box := UIKit.vbox(14)
	box.add_child(Cartoon.title(GameManager.t("reset_all"), 34))
	box.add_child(Cartoon.wrapped_label(GameManager.t("reset_explain"), 20))
	var row := BoxContainer.new()
	row.vertical = get_viewport().get_visible_rect().size.x < 560.0
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var confirm_button := Cartoon.button(GameManager.t("reset_yes"), _do_reset, Cartoon.STYLE_DANGER, Vector2(0 if row.vertical else 240, 58))
	var cancel_button := Cartoon.button(GameManager.t("cancel"), _cancel_reset, Cartoon.STYLE_NORMAL, Vector2(0 if row.vertical else 200, 58))
	confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(confirm_button)
	row.add_child(cancel_button)
	box.add_child(row)
	panel.add_child(box)
	_confirm.add_child(UIKit.centered(panel, Vector2(640, 380)))


func _cancel_reset() -> void:
	if _confirm != null and is_instance_valid(_confirm):
		_confirm.queue_free()
	_confirm = null


func _do_reset() -> void:
	SettingsManager.reset_to_defaults()
	GameManager.toast(GameManager.t("reset_done"))
	# Rebuild the screen so every slider / toggle shows the restored value immediately.
	for c in get_children():
		c.queue_free()
	_preset_buttons.clear()
	_section_headers.clear()
	_confirm = null
	_mic_overlay = null
	await get_tree().process_frame
	_build()


func _on_preset(index: int) -> void:
	SettingsManager.apply_preset(index)
	_render_slider.set_value_no_signal(float(SettingsManager.get_setting("render_scale")))
	_shadow_toggle.set_pressed_no_signal(bool(SettingsManager.get_setting("shadows")))
	_effects_toggle.set_pressed_no_signal(bool(SettingsManager.get_setting("effects")))
	_msaa_toggle.set_pressed_no_signal(bool(SettingsManager.get_setting("msaa")))
	_refresh_preset_buttons()


func _refresh_preset_buttons() -> void:
	var current := int(SettingsManager.get_setting("graphics_preset"))
	for i in _preset_buttons.size():
		var b: Button = _preset_buttons[i]
		b.set_pressed_no_signal(int(b.get_meta("preset", -1)) == current)


func _set_language(lang: String) -> void:
	SettingsManager.set_setting("language", lang)
	GameManager.toast(GameManager.t("saved"))
	_close()


func _close() -> void:
	closed.emit()


# --- Local UI builders (formerly in UIKit) ---

func _slider_row(label_text: String, min_v: float, max_v: float, step: float, value: float, on_changed: Callable, suffix: String = "") -> BoxContainer:
	var row := UIKit.hbox(10)
	var label := Cartoon.label(label_text, 20, Cartoon.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = "Slider"
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(160, 0)
	slider.theme = Cartoon.theme()
	slider.value_changed.connect(on_changed)
	row.add_child(slider)
	if suffix != "":
		row.add_child(Cartoon.label(suffix, 20, Cartoon.WHITE, HORIZONTAL_ALIGNMENT_LEFT))
	return row


func _toggle_row(label_text: String, pressed: bool, on_toggled: Callable) -> BoxContainer:
	var row := UIKit.hbox(10)
	var label := Cartoon.label(label_text, 20, Cartoon.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var toggle := CheckButton.new()
	toggle.name = "Toggle"
	toggle.button_pressed = pressed
	toggle.theme = Cartoon.theme()
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	toggle.toggled.connect(on_toggled)
	row.add_child(toggle)
	return row