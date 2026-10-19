extends Node
# Autoload "Game": shared settings + small UI helpers.

const SAVE_PATH := "user://settings.cfg"
const COLORS := [Color("#4ade80"), Color("#60a5fa"), Color("#f87171"), Color("#facc15")]
const NAMES := ["Green", "Blue", "Red", "Yellow"]

var players := 2
var speed := 5          # 1..10
var rounds_to_win := 3
var wrap := false       # walls wrap around instead of killing
var last_ip := ""


func _ready() -> void:
	load_settings()


func step_time() -> float:
	return lerpf(0.20, 0.06, (speed - 1) / 9.0)


func save_settings() -> void:
	var c := ConfigFile.new()
	c.set_value("g", "players", players)
	c.set_value("g", "speed", speed)
	c.set_value("g", "rounds", rounds_to_win)
	c.set_value("g", "wrap", wrap)
	c.set_value("g", "ip", last_ip)
	c.save(SAVE_PATH)


func load_settings() -> void:
	var c := ConfigFile.new()
	if c.load(SAVE_PATH) == OK:
		players = c.get_value("g", "players", 2)
		speed = c.get_value("g", "speed", 5)
		rounds_to_win = c.get_value("g", "rounds", 3)
		wrap = c.get_value("g", "wrap", false)
		last_ip = c.get_value("g", "ip", "")


func make_label(text: String, size := 36) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	return l


func make_button(text: String, cb: Callable, min_size := Vector2(420, 84), font_size := 36) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font_size)
	b.pressed.connect(cb)
	return b


func make_stepper(title: String, value: int, lo: int, hi: int, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	var label := make_label("")
	label.custom_minimum_size = Vector2(380, 0)
	var v := [value]
	var refresh := func() -> void:
		label.text = "%s: %d" % [title, v[0]]
	refresh.call()
	var step := func(d: int) -> void:
		v[0] = clampi(v[0] + d, lo, hi)
		refresh.call()
		on_change.call(v[0])
	row.add_child(make_button("-", func(): step.call(-1), Vector2(84, 84)))
	row.add_child(label)
	row.add_child(make_button("+", func(): step.call(1), Vector2(84, 84)))
	return row
