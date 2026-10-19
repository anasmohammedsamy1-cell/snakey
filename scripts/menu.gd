extends Control


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

	var title := Game.make_label("SNAKE ARENA", 96)
	title.add_theme_color_override("font_color", Color("#4ade80"))
	box.add_child(title)
	box.add_child(Game.make_label("Local multiplayer - one device, up to 4 players", 26))

	if Net.notice != "":
		var n := Game.make_label(Net.notice, 26)
		n.add_theme_color_override("font_color", Color("#fb7185"))
		box.add_child(n)
		Net.notice = ""
	box.add_child(Game.make_stepper("Players", Game.players, 2, 4, _set_players))
	box.add_child(Game.make_button("PLAY (this device)", _play))
	box.add_child(Game.make_button("ONLINE (HOST / JOIN)", _online))
	box.add_child(Game.make_button("SETTINGS", _settings))
	if not OS.has_feature("mobile"):
		box.add_child(Game.make_button("QUIT", func(): get_tree().quit()))


func _set_players(n: int) -> void:
	Game.players = n
	Game.save_settings()


func _play() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _settings() -> void:
	get_tree().change_scene_to_file("res://scenes/settings.tscn")


func _online() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")
