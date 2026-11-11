extends Node
## Autoload: GameManager
## Global flow: input action registration, scene transitions with a fade,
## toast messages, translation helper and small platform helpers.

const Locale := preload("res://scripts/locale.gd")
const GameConstants := preload("res://scripts/game_constants.gd")

const SCENE_MAIN_MENU := "res://scenes/main_menu.tscn"
const SCENE_LOBBY := "res://scenes/lobby.tscn"
const SCENE_ARENA := "res://scenes/arena.tscn"
const SCENE_TUTORIAL := "res://scenes/tutorial.tscn"

var practice_mode := false      # solo free-for-all with respawns
var solo_cfg: Dictionary = {}   # offline match configuration (see default_cfg)
var pending_message := ""
var ui_theme: Theme = null
var is_switching := false

var _overlay_layer: CanvasLayer
var _fade: ColorRect
var _toast_box: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	_register_input_actions()
	call_deferred("_setup_overlay")
	NetworkManager.host_disconnected.connect(_on_host_disconnected)
	NetworkManager.kicked.connect(_on_kicked)
	NetworkManager.player_joined.connect(func(_id: int, pname: String) -> void: toast(t("joined") % pname))
	NetworkManager.player_left.connect(func(_id: int, pname: String) -> void: toast(t("left") % pname))


# ---------------------------------------------------------------------------
# Translation

func t(key: String) -> String:
	return Locale.t(key, str(SettingsManager.get_setting("language")))


func is_rtl() -> bool:
	return str(SettingsManager.get_setting("language")) == "ar"


# ---------------------------------------------------------------------------
# Scene flow

func go_to_main_menu() -> void:
	go_to_scene(SCENE_MAIN_MENU)


func go_to_lobby() -> void:
	practice_mode = false
	go_to_scene(SCENE_LOBBY)


func go_to_arena() -> void:
	go_to_scene(SCENE_ARENA)


func start_tutorial() -> void:
	practice_mode = false
	NetworkManager.leave()
	go_to_scene(SCENE_TUTORIAL)


func start_practice() -> void:
	var c := default_cfg()
	c["bots"] = 3
	start_solo(c, true)


## Offline match against bots. `practice` = free-for-all with respawns (original practice mode).
func start_solo(cfg: Dictionary, practice := false) -> void:
	NetworkManager.leave()
	solo_cfg = cfg.duplicate(true)
	solo_cfg["bot_teams"] = make_bot_teams(solo_cfg)
	practice_mode = practice and int(solo_cfg.get("mode", 0)) == GameConstants.MODE_FFA
	go_to_scene(SCENE_ARENA)


func restart_solo() -> void:
	if bool(SettingsManager.get_setting("rotate_maps")) and not practice_mode:
		solo_cfg["map"] = next_map_id(int(solo_cfg.get("mode", 0)), int(solo_cfg.get("map", 0)))
	start_solo(solo_cfg, practice_mode)


## The next map of the same mode (wraps around). Used by the automatic map rotation.
func next_map_id(mode: int, current: int) -> int:
	var list: Array = GameConstants.maps_for_mode(mode)
	if list.is_empty():
		return current
	var i := list.find(current)
	return int(list[(i + 1) % list.size()])


func default_cfg() -> Dictionary:
	return {"mode": GameConstants.MODE_FFA, "map": 0, "bots": 0, "round_time": GameConstants.ROUND_DURATION,
		"hider_team": 0, "bot_teams": [], "solo_team": 0}


## The configuration the arena should use: the lobby's one online, the solo setup offline.
func get_match_config() -> Dictionary:
	if NetworkManager.online:
		return NetworkManager.cfg
	if solo_cfg.is_empty():
		solo_cfg = default_cfg()
	return solo_cfg


## Bots fill the smaller team (humans' teams are known from `humans`). Used by solo setup and by the lobby host.
func make_bot_teams(cfg: Dictionary, humans: Array = []) -> Array:
	var mode := int(cfg.get("mode", 0))
	var n := int(cfg.get("bots", 0))
	var out: Array = []
	if not GameConstants.uses_teams(mode):
		for i in n:
			out.append(0)
		return out
	var team_count := 2 if mode == GameConstants.MODE_HIDE else clampi(int(cfg.get("team_count", 2)), 2, 4)
	var sizes: Array = []
	for i in team_count:
		sizes.append(0)
	if humans.is_empty():
		var st := clampi(int(cfg.get("solo_team", 0)), 0, team_count - 1)
		humans = [st]
	for tm in humans:
		var ti := clampi(int(tm), 0, team_count - 1)
		sizes[ti] = int(sizes[ti]) + 1
	for i in n:
		var best := 0
		for k in team_count:
			if int(sizes[k]) < int(sizes[best]):
				best = k
		out.append(best)
		sizes[best] = int(sizes[best]) + 1
	return out


func team_name(team: int) -> String:
	return t(GameConstants.TEAM_KEYS[posmod(team, GameConstants.TEAM_KEYS.size())])


## Leaves any match / lobby, closes the network session and returns to the menu.
func leave_match() -> void:
	practice_mode = false
	get_tree().paused = false
	NetworkManager.leave()
	go_to_scene(SCENE_MAIN_MENU)


func go_to_scene(path: String) -> void:
	if is_switching:
		return
	is_switching = true
	get_tree().paused = false
	await _fade_to(1.0, 0.22)
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("GameManager: could not change scene to %s (error %d)" % [path, err])
	await get_tree().process_frame
	await get_tree().process_frame
	await _fade_to(0.0, 0.3)
	is_switching = false


func quit_game() -> void:
	NetworkManager.leave()
	SettingsManager.save_settings()
	get_tree().quit()


# ---------------------------------------------------------------------------
# Feedback helpers

func vibrate(ms := 40) -> void:
	if bool(SettingsManager.get_setting("vibration")) and SettingsManager.is_mobile():
		Input.vibrate_handheld(ms)


## Small non-blocking message at the top of the screen.
func toast(text: String, duration := 2.6) -> void:
	if _toast_box == null:
		return
	# Purple stitched-looking message ribbon matching the in-game prototype.
	var pill := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#5b2e91")
	sb.set_corner_radius_all(24)
	sb.set_border_width_all(4)
	sb.border_color = Color("#261044")
	sb.shadow_color = Color(0.02, 0.0, 0.08, 0.48)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 5)
	sb.set_content_margin_all(12)
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	pill.add_theme_stylebox_override("panel", sb)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pill.custom_minimum_size = Vector2(500, 66)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color("#fff8ef"))
	label.add_theme_color_override("font_outline_color", Color("#261044"))
	label.add_theme_constant_override("outline_size", 4)
	label.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	pill.add_child(label)
	pill.modulate.a = 0.0
	_toast_box.add_child(pill)
	while _toast_box.get_child_count() > 4:
		_toast_box.get_child(0).queue_free()
		await get_tree().process_frame
	var tw := pill.create_tween()
	tw.tween_property(pill, "modulate:a", 1.0, 0.2)
	tw.tween_interval(duration)
	tw.tween_property(pill, "modulate:a", 0.0, 0.4)
	tw.tween_callback(pill.queue_free)


# ---------------------------------------------------------------------------
# Internals

func _setup_overlay() -> void:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 100
	_overlay_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(_overlay_layer)

	_fade = ColorRect.new()
	_fade.color = Color(0.05, 0.08, 0.2, 1.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.modulate.a = 0.0
	_overlay_layer.add_child(_fade)

	var holder := MarginContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	holder.add_theme_constant_override("margin_top", 70)
	holder.add_theme_constant_override("margin_left", 40)
	holder.add_theme_constant_override("margin_right", 40)
	_overlay_layer.add_child(holder)
	_toast_box = VBoxContainer.new()
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toast_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toast_box.add_theme_constant_override("separation", 4)
	holder.add_child(_toast_box)

	if pending_message != "":
		var msg := pending_message
		pending_message = ""
		toast(msg, 4.0)


func _fade_to(alpha: float, duration: float) -> void:
	if _fade == null:
		return
	var tw := _fade.create_tween()
	tw.tween_property(_fade, "modulate:a", alpha, duration)
	await tw.finished


func _on_host_disconnected() -> void:
	practice_mode = false
	get_tree().paused = false
	pending_message = t("host_left")
	go_to_scene(SCENE_MAIN_MENU)


func _on_kicked(reason: String) -> void:
	practice_mode = false
	get_tree().paused = false
	pending_message = reason
	go_to_scene(SCENE_MAIN_MENU)


func _register_input_actions() -> void:
	_add_key_action("move_left", [KEY_A])
	_add_key_action("move_right", [KEY_D])
	_add_key_action("move_forward", [KEY_W])
	_add_key_action("move_back", [KEY_S])
	_add_key_action("jump", [KEY_SPACE])
	_add_key_action("push", [KEY_E, KEY_F])
	_add_key_action("dash", [KEY_SHIFT, KEY_R])
	_add_key_action("arm_mode", [KEY_TAB, KEY_G])
	_add_key_action("cam_left", [KEY_LEFT, KEY_Q])
	_add_key_action("cam_right", [KEY_RIGHT])
	_add_key_action("cam_up", [KEY_UP])
	_add_key_action("cam_down", [KEY_DOWN])
	_add_key_action("pause", [KEY_ESCAPE, KEY_P])


func _add_key_action(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
