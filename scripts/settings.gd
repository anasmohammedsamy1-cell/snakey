extends Control

var wrap_btn: Button


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#0b1220")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	center.add_child(box)

	box.add_child(Game.make_label("SETTINGS", 72))
	box.add_child(Game.make_stepper("Speed", Game.speed, 1, 10, _set_speed))
	box.add_child(Game.make_stepper("Rounds to win", Game.rounds_to_win, 1, 10, _set_rounds))
	wrap_btn = Game.make_button("", _toggle_wrap, Vector2(560, 84))
	box.add_child(wrap_btn)
	_refresh()
	box.add_child(Game.make_button("BACK", _back))


func _refresh() -> void:
	wrap_btn.text = "Wrap walls: %s" % ("ON" if Game.wrap else "OFF")


func _toggle_wrap() -> void:
	Game.wrap = not Game.wrap
	Game.save_settings()
	_refresh()


func _back() -> void:
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _set_speed(v: int) -> void:
	Game.speed = v
	Game.save_settings()


func _set_rounds(v: int) -> void:
	Game.rounds_to_win = v
	Game.save_settings()
