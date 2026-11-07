extends CanvasLayer
## In-match HUD: timer, alive / out counters, status messages, elimination feed,
## compact ranking list, pause menu and the results screen hook.
## Layout keeps the bottom corners free for the joystick and action buttons.

const Cartoon := preload("res://scripts/cartoon_ui.gd")
const UIKit := preload("res://scripts/ui_kit.gd")
const GameConstants := preload("res://scripts/game_constants.gd")
const ResultsScene := preload("res://scenes/ui/results_screen.tscn")
const SettingsScene := preload("res://scenes/ui/settings_menu.tscn")
const HUD_VIVID_SHADER := preload("res://assets/shaders/hud_vivid.gdshader")
const ICON_FONT := preload("res://assets/fonts/main_font.ttf")

var round_manager: Node = null
var touch_controls: Control = null

var _timer_label: Label
var _go_icon: TextureRect
var _go_tween: Tween
var _player_card_texture: Texture2D
var _vivid_material: ShaderMaterial
var _alive_label: Label
var _out_label: Label
var _counter_holder: Control
var _counter_bg: Panel
var _center_label: Label
var _sub_label: Label
var _feed: VBoxContainer
var _ranking: VBoxContainer
var _pause_menu: Control
var _results: Control = null
var _settings_overlay: Control = null
var _center_tween: Tween = null
var _paused := false
var _ended := false
var _mic_button: Button
var _chan_button: Button
var _friends_audio_button: Button
var _game_audio_button: TextureButton  # Animated texture button for music
var _audio_menu: Control
var _game_audio_muted := false
var _pause_button: TextureButton  # Animated texture button for pause
var _blind: ColorRect
var _hs_label: Label
var _refresh_t := 0.0
var _anim_timer := 0.0
var _anim_frame := 0
const ANIM_FRAME_TIME := 0.5
var _pause_texes: Array[Texture2D] = []
var _music_texes: Array[Texture2D] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	touch_controls = $TouchControls
	_build()


func bind(rm: Node) -> void:
	round_manager = rm
	rm.state_changed.connect(_on_state_changed)
	rm.timer_updated.connect(_on_timer)
	rm.player_eliminated.connect(_on_eliminated)
	rm.round_ended.connect(_on_round_ended)
	rm.announce.connect(show_center_text)
	rm.local_player_eliminated.connect(_on_local_eliminated)
	rm.players_changed.connect(_refresh_ranking)
	rm.knockout_scored.connect(_on_knockout)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not _ended:
		_toggle_pause(not _paused)
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Building

func _build() -> void:
	_player_card_texture = load("res://NewAssets/in_game/player_card_BG.png")
	_vivid_material = ShaderMaterial.new()
	_vivid_material.shader = HUD_VIVID_SHADER
	var root := Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	move_child(root, 0) # keep TouchControls on top for input ordering

	var margin := UIKit.safe_margin_container(get_viewport(), 12)
	root.add_child(margin)

	var column := UIKit.vbox(6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	# --- Top bar
	var top := UIKit.hbox(10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(top)

	# Keep the counter text at its original size, while shrinking only its
	# purple backing to 30% and making the backing corners square.
	_counter_holder = Control.new()
	_counter_holder.custom_minimum_size = Vector2(230, 54)
	_counter_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_counter_bg = Panel.new()
	_counter_bg.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_counter_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_counter_bg.add_theme_stylebox_override("panel", Cartoon.stylebox(Color("#6728a8"), 0, Cartoon.PURPLE_DARK, 3, 0, 4, Color(0.03, 0.01, 0.08, 0.5), Vector2(0, 3)))
	var left_box := UIKit.hbox(14)
	left_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	left_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_alive_label = Cartoon.label("", 25, Color("#83f64b"))
	_out_label = Cartoon.label("", 25, Color("#ff75b3"))
	_alive_label.add_theme_color_override("font_outline_color", Cartoon.PURPLE_DARK)
	_out_label.add_theme_color_override("font_outline_color", Cartoon.PURPLE_DARK)
	_alive_label.add_theme_constant_override("outline_size", 5)
	_out_label.add_theme_constant_override("outline_size", 5)
	left_box.add_child(_alive_label)
	left_box.add_child(_out_label)
	_counter_holder.add_child(_counter_bg)
	_counter_holder.add_child(left_box)
	top.add_child(_counter_holder)

	top.add_child(UIKit.spacer())
	var timer_panel := TextureRect.new()
	timer_panel.texture = load("res://NewAssets/in_game/timer_BG.png")
	timer_panel.material = _vivid_material
	timer_panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	timer_panel.stretch_mode = TextureRect.STRETCH_SCALE
	timer_panel.custom_minimum_size = Vector2(230, 82)
	timer_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var timer_box := CenterContainer.new()
	timer_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	timer_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timer_label = Cartoon.title("1:30", 48, Cartoon.WHITE)
	_timer_label.add_theme_color_override("font_outline_color", Cartoon.PURPLE_DARK)
	_timer_label.add_theme_constant_override("outline_size", 7)
	timer_box.add_child(_timer_label)
	timer_panel.add_child(timer_box)
	top.add_child(timer_panel)
	top.add_child(UIKit.spacer())

	# Load animated textures
	_pause_texes.append(load("res://NewAssets/in_game/pause_1.png"))
	_pause_texes.append(load("res://NewAssets/in_game/pause_2.png"))
	_music_texes.append(load("res://NewAssets/in_game/music_1.png"))
	_music_texes.append(load("res://NewAssets/in_game/music_2.png"))

	_mic_button = _icon_button("mic", GameManager.t("mic_test"), _on_mic_pressed, Cartoon.STYLE_NORMAL, Vector2(56, 56))
	_mic_button.button_down.connect(func() -> void: VoiceChat.ptt_down = true)
	_mic_button.button_up.connect(func() -> void: VoiceChat.ptt_down = false)
	top.add_child(_mic_button)
	_chan_button = _icon_button("group", GameManager.t("chan_all"), _on_chan_pressed, Cartoon.STYLE_NORMAL, Vector2(54, 54))
	top.add_child(_chan_button)
	_friends_audio_button = _icon_button("speaker", GameManager.t("voice_output_on"), _on_friends_audio_pressed, Cartoon.STYLE_NORMAL, Vector2(54, 54))
	top.add_child(_friends_audio_button)

	# Game audio / music button with animated texture
	_game_audio_button = _animated_texture_button(_music_texes, GameManager.t("game_audio_on"), _on_game_audio_pressed, Vector2(94, 94))
	_game_audio_button.material = _vivid_material
	top.add_child(_game_audio_button)

	# Pause button with animated texture
	_pause_button = _animated_texture_button(_pause_texes, GameManager.t("pause_btn"), func() -> void: _toggle_pause(true), Vector2(94, 94))
	_pause_button.material = _vivid_material
	top.add_child(_pause_button)

	# --- Ranking (top-left, under the counters) + feed
	var under := UIKit.hbox(10)
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(under)
	_ranking = UIKit.vbox(2)
	_ranking.mouse_filter = Control.MOUSE_FILTER_IGNORE
	under.add_child(_ranking)
	under.add_child(UIKit.spacer())
	_feed = UIKit.vbox(2)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	under.add_child(_feed)

	# --- Centre messages
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var cbox := UIKit.vbox(4)
	cbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(cbox)
	_center_label = Cartoon.title("", 72)
	_center_label.pivot_offset = Vector2.ZERO
	_center_label.modulate.a = 0.0
	cbox.add_child(_center_label)
	_sub_label = Cartoon.label("", 24, Color(1, 1, 1, 0.9))
	_sub_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_sub_label.add_theme_constant_override("outline_size", 6)
	_sub_label.visible = false
	cbox.add_child(_sub_label)

	_hs_label = Cartoon.title("", 44, Color(1.0, 0.95, 0.5))
	_hs_label.visible = false
	cbox.add_child(_hs_label)
	_go_icon = TextureRect.new()
	_go_icon.texture = load("res://NewAssets/in_game/Go.png")
	_go_icon.material = _vivid_material
	_go_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_go_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_go_icon.custom_minimum_size = Vector2(250, 155)
	_go_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_go_icon.visible = false
	var go_center := CenterContainer.new()
	go_center.name = "GoCenter"
	go_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	go_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	go_center.add_child(_go_icon)
	root.add_child(go_center)
	root.move_child(go_center, root.get_child_count() - 1)
	_blind = ColorRect.new()
	_blind.color = Color(0.02, 0.02, 0.05, 0.96)
	_blind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blind.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blind.visible = false
	root.add_child(_blind)
	root.move_child(_blind, 0)

	# --- Pause menu
	_pause_menu = Control.new()
	_pause_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_menu.visible = false
	root.add_child(_pause_menu)
	UIKit.dim_background(_pause_menu)
	var panel := Cartoon.panel()
	var pbox := UIKit.vbox(14)
	pbox.alignment = BoxContainer.ALIGNMENT_CENTER
	pbox.add_child(Cartoon.title(GameManager.t("paused"), 44))
	pbox.add_child(Cartoon.button(GameManager.t("resume"), func() -> void: _toggle_pause(false), Cartoon.STYLE_PRIMARY))
	pbox.add_child(Cartoon.button(GameManager.t("settings"), _open_settings))
	pbox.add_child(Cartoon.button(GameManager.t("leave_match"), _leave_match, Cartoon.STYLE_DANGER))
	panel.add_child(pbox)
	_pause_menu.add_child(UIKit.centered(panel, Vector2(420, 380)))

	# Keep the match HUD uncluttered: voice channel, friend voice and game audio
	# live in one compact quick panel, while the microphone remains one-tap reachable.
	_audio_menu = Control.new()
	_audio_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_audio_menu.visible = false
	root.add_child(_audio_menu)
	UIKit.dim_background(_audio_menu, Color(0.01, 0.03, 0.1, 0.72))
	var audio_panel := Cartoon.panel()
	var audio_box := UIKit.vbox(12)
	audio_box.add_child(Cartoon.title(GameManager.t("audio"), 34))
	for audio_control in [_chan_button, _friends_audio_button]:
		top.remove_child(audio_control)
		audio_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		audio_box.add_child(audio_control)
	audio_box.add_child(Cartoon.button(GameManager.t("close"), _toggle_audio_menu, Cartoon.STYLE_PRIMARY, Vector2(0, 54)))
	audio_panel.add_child(audio_box)
	_audio_menu.add_child(UIKit.centered(audio_panel, Vector2(420, 360)))


# ---------------------------------------------------------------------------
# Signals from the round manager

func _toggle_audio_menu() -> void:
	if _audio_menu == null:
		return
	_audio_menu.visible = not _audio_menu.visible
	if _audio_menu.visible:
		UIKit.add_fade_in(_audio_menu)


func _on_mic_pressed() -> void:
	if bool(SettingsManager.get_setting("voice_open_mic")):
		VoiceChat.toggle_mute()


func _on_chan_pressed() -> void:
	VoiceChat.toggle_team_only()


func _on_friends_audio_pressed() -> void:
	VoiceChat.toggle_voice_output()
	_update_audio_buttons()


func _on_game_audio_pressed() -> void:
	_game_audio_muted = not _game_audio_muted
	for bus_name in ["Music", "SFX"]:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx >= 0:
			AudioServer.set_bus_mute(idx, _game_audio_muted)
	_update_audio_buttons()


func _update_audio_buttons() -> void:
	if _friends_audio_button != null:
		_friends_audio_button.icon = load("res://assets/icons/speaker_off.svg" if VoiceChat.master_mute else "res://assets/icons/speaker.svg")
		_friends_audio_button.tooltip_text = GameManager.t("voice_output_off") if VoiceChat.master_mute else GameManager.t("voice_output_on")
		_friends_audio_button.modulate = Color(1.0, 0.55, 0.55) if VoiceChat.master_mute else Color.WHITE
	if _game_audio_button != null:
		# For the animated music button, we update the pressed/hover textures
		_game_audio_button.texture_pressed = _music_texes[_anim_frame]  # same as normal for simplicity
		_game_audio_button.tooltip_text = GameManager.t("game_audio_off") if _game_audio_muted else GameManager.t("game_audio_on")
		_game_audio_button.modulate = Color(1.0, 0.55, 0.55) if _game_audio_muted else Color.WHITE


func _process(delta: float) -> void:
	if round_manager == null:
		return

	# Animation timer for pause/music buttons (0.5 sec cycle)
	_anim_timer += delta
	if _anim_timer >= ANIM_FRAME_TIME:
		_anim_timer = 0.0
		_anim_frame = 1 - _anim_frame
		if _pause_button != null and _pause_texes.size() >= 2:
			_pause_button.texture_normal = _pause_texes[_anim_frame]
		if _game_audio_button != null and _music_texes.size() >= 2:
			_game_audio_button.texture_normal = _music_texes[_anim_frame]

	# Voice buttons only matter online.
	var online := NetworkManager.online
	_mic_button.visible = online
	_chan_button.visible = online and round_manager.is_team_mode()
	_friends_audio_button.visible = online
	_game_audio_button.visible = true
	if online:
		var open_mic := bool(SettingsManager.get_setting("voice_open_mic"))
		var label := GameManager.t("mic_short")
		var mic_icon := "mic"
		if not VoiceChat.mic_ready:
			label = "..." if not VoiceChat.permission_denied else "X"
		elif VoiceChat.muted and open_mic:
			label = GameManager.t("mic_off_short")
			mic_icon = "mic_off"
		elif VoiceChat.is_speaking(multiplayer.get_unique_id()):
			label = GameManager.t("mic_talk_short")
			mic_icon = "mic"
		_mic_button.icon = load("res://assets/icons/%s.svg" % mic_icon)
		_mic_button.tooltip_text = label
		_mic_button.modulate = Color(1, 0.55, 0.55) if (VoiceChat.muted and open_mic) else (Color(0.6, 1, 0.6) if VoiceChat.is_speaking(multiplayer.get_unique_id()) else Color.WHITE)
		_chan_button.icon = load("res://assets/icons/group.svg")
		_chan_button.tooltip_text = GameManager.t("chan_team") if VoiceChat.team_only else GameManager.t("chan_all")
	_update_audio_buttons()
	# Hide and seek: blindfold + countdown while the hiders are hiding
	var hide_left: float = round_manager.hide_time_left()
	var local: Node = round_manager.local_player
	var blind: bool = hide_left > 0.0 and local != null and int(local.role) == GameConstants.HS_ROLE_SEEKER
	_blind.visible = blind
	if hide_left > 0.0 and local != null:
		_hs_label.visible = true
		var key := "hs_hiding_left" if int(local.role) == GameConstants.HS_ROLE_HIDER else "hs_blind_left"
		_hs_label.text = GameManager.t(key) % int(ceil(hide_left))
	else:
		_hs_label.visible = false
	_refresh_t += delta
	if _refresh_t > 0.5:
		_refresh_t = 0.0
		_refresh_ranking()


func _on_state_changed(state: int) -> void:
	_refresh_ranking()
	match state:
		0:
			_sub_label.text = GameManager.t("waiting_players")
			_sub_label.visible = NetworkManager.online
		1:
			_sub_label.visible = false
		2:
			_sub_label.visible = false
			_show_round_goal()
			_play_go_icon()
		_:
			pass


func _show_round_goal() -> void:
	if round_manager == null:
		return
	var key := "goal_ffa"
	if GameManager.practice_mode:
		key = "goal_practice"
	elif int(round_manager.mode) == GameConstants.MODE_TEAMS:
		key = "goal_teams"
	elif int(round_manager.mode) == GameConstants.MODE_HIDE:
		if round_manager.local_player != null and int(round_manager.local_player.role) == GameConstants.HS_ROLE_SEEKER:
			key = "goal_seeker"
		else:
			key = "goal_hider"
	elif int(round_manager.mode) in [GameConstants.MODE_KNOCKOUT, GameConstants.MODE_TRAMPOLINE]:
		key = "goal_ko"
	GameManager.toast(GameManager.t(key), 3.5)


func _on_timer(remaining: float) -> void:
	var secs := int(ceil(remaining))
	_timer_label.text = "%d:%02d" % [int(secs / 60.0), secs % 60]
	if remaining <= 10.0:
		_timer_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4) if int(remaining * 2.0) % 2 == 0 else Color.WHITE)
	else:
		_timer_label.add_theme_color_override("font_color", Color.WHITE)


func _play_go_icon() -> void:
	if _go_icon == null or not is_instance_valid(_go_icon):
		return
	if _go_tween != null and _go_tween.is_valid():
		_go_tween.kill()
	_go_icon.visible = true
	_go_icon.modulate.a = 1.0
	_go_icon.scale = Vector2.ZERO
	_go_icon.pivot_offset = _go_icon.size * 0.5
	_go_tween = create_tween()
	_go_tween.tween_property(_go_icon, "scale", Vector2.ONE * 1.1, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_go_tween.tween_property(_go_icon, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_go_tween.tween_interval(0.45)
	_go_tween.tween_property(_go_icon, "modulate:a", 0.0, 0.2)
	_go_tween.tween_callback(func() -> void: _go_icon.visible = false)


func _on_eliminated(_peer_id: int, player_name: String, _alive_count: int) -> void:
	_add_feed_line(GameManager.t("fell") % player_name)
	_refresh_ranking()


func _on_local_eliminated() -> void:
	show_center_text(GameManager.t("eliminated"), 1.6)
	_sub_label.text = GameManager.t("spectating")
	_sub_label.visible = true
	if touch_controls != null:
		touch_controls.set_enabled(false)


func _on_round_ended(results: Array, headline: String) -> void:
	_ended = true
	_sub_label.visible = false
	if touch_controls != null:
		touch_controls.set_enabled(false)
	_pause_button.visible = false
	if _paused:
		_toggle_pause(false)
	await get_tree().create_timer(1.8).timeout
	if not is_inside_tree():
		return
	_results = ResultsScene.instantiate()
	add_child(_results)
	_results.show_results(results, headline, GameManager.practice_mode)


# ---------------------------------------------------------------------------
# Presentation helpers

func show_center_text(text: String, duration := 1.0) -> void:
	if text == GameManager.t("go"):
		if _go_icon == null or not _go_icon.visible:
			_play_go_icon()
		return
	_center_label.text = text
	_center_label.pivot_offset = _center_label.size * 0.5
	if _center_tween != null and _center_tween.is_valid():
		_center_tween.kill()
	_center_label.modulate.a = 1.0
	_center_label.scale = Vector2(1.5, 1.5)
	_center_tween = create_tween()
	_center_tween.tween_property(_center_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_center_tween.tween_interval(maxf(duration - 0.25, 0.1))
	_center_tween.tween_property(_center_label, "modulate:a", 0.0, 0.3)


func _add_feed_line(text: String) -> void:
	var l := Cartoon.label(text, 20, Color(1, 1, 1, 0.95), HORIZONTAL_ALIGNMENT_RIGHT)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 5)
	_feed.add_child(l)
	while _feed.get_child_count() > 4:
		var first := _feed.get_child(0)
		_feed.remove_child(first)
		first.queue_free()
	var tw := l.create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


func _on_knockout(killer_id: int, _victim_id: int, killer_name: String, victim_name: String) -> void:
	if killer_id != 0:
		_add_feed_line(GameManager.t("ko_feed") % [killer_name, victim_name])
	else:
		_add_feed_line(GameManager.t("fell") % victim_name)
	_refresh_ranking()


func _add_rank_card(text: String, accent: Color, font_size := 18, marked := true) -> void:
	var card := TextureRect.new()
	card.texture = _player_card_texture
	card.material = _vivid_material
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.stretch_mode = TextureRect.STRETCH_SCALE
	card.custom_minimum_size = Vector2(164, 50)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := UIKit.hbox(5)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 15
	row.offset_right = -9
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if marked:
		var marker := Cartoon.label("●", 22, accent)
		marker.add_theme_font_override("font", ICON_FONT)
		marker.custom_minimum_size = Vector2(24, 28)
		row.add_child(marker)
	var name_label := Cartoon.label(text, font_size, Cartoon.INK, HORIZONTAL_ALIGNMENT_LEFT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_color_override("font_outline_color", Color("#fff7e9"))
	name_label.add_theme_constant_override("outline_size", 1)
	row.add_child(name_label)
	card.add_child(row)
	_ranking.add_child(card)


func _fit_counter_background() -> void:
	if _counter_holder == null or _counter_bg == null or _alive_label == null or _out_label == null:
		return
	var alive_size := _alive_label.get_combined_minimum_size()
	var out_size := _out_label.get_combined_minimum_size()
	var text_size := Vector2(alive_size.x + out_size.x + 14.0, maxf(alive_size.y, out_size.y))
	var fitted_size := text_size * 1.01
	_counter_holder.custom_minimum_size = fitted_size
	_counter_bg.offset_left = -fitted_size.x * 0.5
	_counter_bg.offset_right = fitted_size.x * 0.5
	_counter_bg.offset_top = -fitted_size.y * 0.5
	_counter_bg.offset_bottom = fitted_size.y * 0.5


## Knockout scoreboard: live ranking by validated knockouts (top 5 plus the local player), mobile sized.
func _refresh_ko_board() -> void:
	var standings: Array = round_manager.ko_standings()
	var local_id := -1
	if round_manager.local_player != null and is_instance_valid(round_manager.local_player):
		local_id = int(round_manager.local_player.peer_id)
	var shown := 0
	for e in standings:
		var id := int(e["id"])
		var p: Node = round_manager.players.get(id)
		if p == null or not is_instance_valid(p):
			continue
		var is_me := id == local_id
		if shown >= 5 and not is_me:
			continue
		shown += 1
		var is_alive: bool = bool(round_manager.alive.get(id, false))
		var color: Color = GameConstants.get_color(p.color_index)
		var text := "%d. %s  %dK / %dF" % [int(e["rank"]), str(p.player_name), int(e["kos"]), int(e["falls"])]
		if is_me:
			text += "  ◄ " + GameManager.t("ko_you_marker")
		_add_rank_card(text, color if is_alive else Color("#8d8293"), 18 if not is_me else 20, true)
		if is_me:
			_alive_label.text = "%s %d" % [GameManager.t("ko_short"), int(e["kos"])]
			_out_label.text = "%s %d" % [GameManager.t("falls"), int(e["falls"])]
			_out_label.text = "%s #%d" % [GameManager.t("ko_rank_short"), int(e["rank"])]
	_fit_counter_background()


func _refresh_ranking() -> void:
	if round_manager == null:
		return
	for c in _ranking.get_children():
		_ranking.remove_child(c)
		c.queue_free()
	if round_manager.is_respawn_score_mode():
		_refresh_ko_board()
		return
	var alive_n := 0
	var total := 0
	var ids: Array = round_manager.players.keys()
	ids.sort()
	if round_manager.is_team_mode():
		ids.sort_custom(func(x, y) -> bool: return int(round_manager.team_of.get(x, 0)) < int(round_manager.team_of.get(y, 0)))
	var last_team := -1
	for id in ids:
		var p: Node = round_manager.players[id]
		if p == null or not is_instance_valid(p):
			continue
		total += 1
		var is_alive: bool = bool(round_manager.alive.get(id, false))
		if is_alive:
			alive_n += 1
		var color: Color = GameConstants.get_color(p.color_index)
		var tm := int(round_manager.team_of.get(id, 0))
		if round_manager.is_team_mode():
			color = GameConstants.team_color(tm)
			if tm != last_team:
				last_team = tm
				var head_text := GameManager.team_name(tm)
				if round_manager.mode == GameConstants.MODE_HIDE:
					head_text = GameManager.t("hs_hiders") if tm == round_manager.hider_team() else GameManager.t("hs_seekers")
				_add_rank_card(head_text, color, 18, false)
		var mark := " ♪" if VoiceChat.is_speaking(int(id)) else ""
		_add_rank_card(str(p.player_name) + mark, color if is_alive else Color("#8d8293"), 18, is_alive)
	_alive_label.text = "%d %s" % [alive_n, GameManager.t("alive")]
	_out_label.text = "%d %s" % [total - alive_n, GameManager.t("out")]
	_fit_counter_background()


# ---------------------------------------------------------------------------
# Pause

func _toggle_pause(show: bool) -> void:
	if _ended and show:
		return
	_paused = show
	_pause_menu.visible = show
	if show and _audio_menu != null:
		_audio_menu.visible = false
	if touch_controls != null:
		touch_controls.set_enabled(not show and not (round_manager != null and round_manager.local_player != null and not round_manager.local_player.is_alive))
	if round_manager != null and round_manager.local_player != null:
		round_manager.local_player.set_input_enabled(not show)
	# Only a solo practice game can really freeze the simulation.
	if GameManager.practice_mode:
		get_tree().paused = show
	if _settings_overlay != null and is_instance_valid(_settings_overlay):
		_settings_overlay.queue_free()
		_settings_overlay = null


func _leave_match() -> void:
	get_tree().paused = false
	GameManager.leave_match()


func _open_settings() -> void:
	if _settings_overlay != null and is_instance_valid(_settings_overlay):
		return
	_settings_overlay = SettingsScene.instantiate()
	add_child(_settings_overlay)
	_settings_overlay.closed.connect(func() -> void:
		if _settings_overlay != null and is_instance_valid(_settings_overlay):
			_settings_overlay.queue_free()
		_settings_overlay = null
	)


# --- Local UI builder ---

func _icon_button(icon_name: String, tooltip: String, on_pressed: Callable, style: int, min_size: Vector2) -> Button:
	var b := Cartoon.button("", on_pressed, style, min_size)
	b.icon = load("res://assets/icons/%s.svg" % icon_name)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.tooltip_text = tooltip
	b.accessibility_name = tooltip
	return b


func _animated_texture_button(textures: Array[Texture2D], tooltip: String, on_pressed: Callable, min_size: Vector2) -> TextureButton:
	var b := TextureButton.new()
	# TextureButton normally reports its source image dimensions as its minimum
	# size. The supplied pause/music art is 485x512 / 256x256, which made the
	# top HBox 512px tall and stretched every sibling panel. Ignore that native
	# size so the explicit HUD target below controls its layout size.
	b.ignore_texture_size = true
	b.custom_minimum_size = min_size
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.texture_normal = textures[0] if textures.size() > 0 else null
	b.texture_hover = textures[1] if textures.size() > 1 else textures[0]
	b.texture_pressed = textures[0] if textures.size() > 0 else null
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = tooltip
	b.accessibility_name = tooltip
	b.pressed.connect(func() -> void: AudioManager.click())
	b.pressed.connect(on_pressed)
	# Remove default focus style
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b
