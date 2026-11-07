extends Control
## Microphone test screen. Works WITHOUT any other player: it starts the real capture, shows a live
## level meter and can play your voice back to you (local monitoring, never sent over the network).
## This is a LOCAL test only - it does not prove that voice reaches other phones (use a LAN room for that).

signal closed

const Cartoon := preload("res://scripts/cartoon_ui.gd")
const UIKit := preload("res://scripts/ui_kit.gd")

var _status: Label
var _bar: ProgressBar
var _monitor_toggle: CheckButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UIKit.dim_background(self)
	var panel := Cartoon.panel()
	var box := UIKit.vbox(12)
	panel.add_child(box)
	box.add_child(Cartoon.title(GameManager.t("mic_test"), 38))
	box.add_child(Cartoon.wrapped_label(GameManager.t("mic_test_note"), 18, Color(1, 1, 1, 0.8)))
	_status = Cartoon.label("", 22, Color(1.0, 0.85, 0.12))
	box.add_child(_status)
	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.step = 0.01
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 34)
	_bar.theme = Cartoon.theme()
	box.add_child(_bar)
	var mon := _toggle_row(GameManager.t("mic_monitor"), false, func(v: bool) -> void: VoiceChat.set_monitor(v))
	_monitor_toggle = mon.get_node("Toggle")
	box.add_child(mon)
	box.add_child(_slider_row(GameManager.t("mic_gain"), 0.3, 4.0, 0.1, float(SettingsManager.get_setting("mic_gain")), func(v: float) -> void: SettingsManager.set_setting("mic_gain", v)))
	box.add_child(_slider_row(GameManager.t("voice_volume"), 0.0, 1.0, 0.05, float(SettingsManager.get_setting("voice_volume")), func(v: float) -> void: SettingsManager.set_setting("voice_volume", v)))
	box.add_child(Cartoon.button(GameManager.t("close"), _close, Cartoon.STYLE_PRIMARY, Vector2(240, 58)))
	add_child(UIKit.centered(panel, Vector2(720, 560)))
	SettingsManager.set_setting("voice_enabled", true)
	VoiceChat.set_test_mode(true)


func _process(_delta: float) -> void:
	_bar.value = VoiceChat.level
	if VoiceChat.permission_denied:
		_status.text = GameManager.t("voice_no_permission")
	elif not VoiceChat.mic_ready:
		_status.text = GameManager.t("voice_starting")
	else:
		_status.text = GameManager.t("mic_speaking") if VoiceChat.level > 0.08 else GameManager.t("mic_quiet")


func _close() -> void:
	VoiceChat.set_test_mode(false)
	closed.emit()
	queue_free()


# --- Local UI builders ---

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