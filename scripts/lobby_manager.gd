extends Control
## Multiplayer lobby: host / join panel, then the player list with ready states.
## Only the host can start, and only when >= 2 players are connected and all
## clients are ready. All list updates come from NetworkManager (host snapshot).

const Cartoon := preload("res://scripts/cartoon_ui.gd")
const UIKit := preload("res://scripts/ui_kit.gd")
const GameConstants := preload("res://scripts/game_constants.gd")
const CustomScene := preload("res://scenes/ui/customization_menu.tscn")
const NetUtils := preload("res://scripts/net_utils.gd")
const LanDiscovery := preload("res://scripts/lan_discovery.gd")
const MapPickerScript := preload("res://scripts/map_picker.gd")

var _connect_panel: Control
var _lobby_panel: Control
var _ip_edit: LineEdit
var _port_edit: LineEdit
var _status_label: Label
var _error_label: Label
var _ip_list_label: Label
var _player_list: VBoxContainer
var _ready_button: Button
var _start_button: Button
var _host_info_label: Label
var _count_label: Label
var _hint_label: Label
var _is_ready := false
var _overlay: Control = null
var _mode_btn: Button
var _map_btn: Button
var _map_overlay: Control = null
var _bots_label: Label
var _bots_minus: Button
var _bots_plus: Button
var _voice_btn: Button
var _extra_btn: Button
var _balance_btn: Button
var _mic_btn: Button
var _settings_box: VBoxContainer
var _room_edit: LineEdit
var _max_label: Label
var _max_value: int = GameConstants.MAX_PLAYERS
var _rooms_box: VBoxContainer
var _rooms_status: Label
var _manual_box: Control
var _manual_toggle: Button
var _connect_scroll: ScrollContainer
var _kb_spacer: Control
var _last_kb_height := 0.0
var _status_tick := 0.0
var _connect_columns: BoxContainer
var _connect_separator: ColorRect
var _responsive_boxes: Array[BoxContainer] = []


func _ready() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_RTL if GameManager.is_rtl() else Control.LAYOUT_DIRECTION_LTR
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()
	NetworkManager.player_list_changed.connect(_refresh_players)
	NetworkManager.connection_succeeded.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_failed)
	NetworkManager.status_changed.connect(_on_status)
	NetworkManager.cfg_changed.connect(_refresh_players)
	NetworkManager.discovery.rooms_changed.connect(_rebuild_rooms)
	if NetworkManager.online:
		_show_lobby()
	else:
		_show_connect()


func _exit_tree() -> void:
	_stop_browsing()
	if NetworkManager.discovery != null and NetworkManager.discovery.rooms_changed.is_connected(_rebuild_rooms):
		NetworkManager.discovery.rooms_changed.disconnect(_rebuild_rooms)
	if NetworkManager.player_list_changed.is_connected(_refresh_players):
		NetworkManager.player_list_changed.disconnect(_refresh_players)
	if NetworkManager.connection_succeeded.is_connected(_on_connected):
		NetworkManager.connection_succeeded.disconnect(_on_connected)
	if NetworkManager.connection_failed.is_connected(_on_failed):
		NetworkManager.connection_failed.disconnect(_on_failed)
	if NetworkManager.status_changed.is_connected(_on_status):
		NetworkManager.status_changed.disconnect(_on_status)
	if NetworkManager.cfg_changed.is_connected(_refresh_players):
		NetworkManager.cfg_changed.disconnect(_refresh_players)


# ---------------------------------------------------------------------------
# Building

func _build() -> void:
	UIKit.dim_background(self)
	var margin := UIKit.safe_margin_container(get_viewport(), 14)
	add_child(margin)
	var column := UIKit.vbox(8)
	margin.add_child(column)

	var header := BoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	_responsive_boxes.append(header)
	var header_back := Cartoon.button(GameManager.t("back"), _on_back, Cartoon.STYLE_NORMAL, Vector2(140, 54))
	header.add_child(header_back)
	header.add_child(UIKit.spacer())
	header.add_child(Cartoon.title(GameManager.t("multiplayer"), 36))
	header.add_child(UIKit.spacer())
	header.add_child(Cartoon.button(GameManager.t("customize"), _open_customize, Cartoon.STYLE_NORMAL, Vector2(190, 54)))
	column.add_child(header)

	_status_label = Cartoon.label(GameManager.t("not_connected"), 20, Color(1, 1, 1, 0.85))
	column.add_child(_status_label)

	# ---- Connect panel: CREATE ROOM (left) | automatic room list + manual IP fallback (right)
	_connect_panel = Cartoon.panel()
	_connect_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_connect_scroll = ScrollContainer.new()
	_connect_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_connect_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_connect_panel.add_child(_connect_scroll)
	var cwrap := UIKit.vbox(6)
	cwrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_connect_scroll.add_child(cwrap)
	_connect_columns = BoxContainer.new()
	_connect_columns.add_theme_constant_override("separation", 18)
	cwrap.add_child(_connect_columns)
	_kb_spacer = Control.new()      # grows with the on-screen keyboard so inputs can be scrolled above it
	cwrap.add_child(_kb_spacer)

	var host_col := UIKit.vbox(10)
	host_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_col.size_flags_stretch_ratio = 0.8
	host_col.add_child(Cartoon.label(GameManager.t("create_room"), 20, Cartoon.YELLOW, HORIZONTAL_ALIGNMENT_LEFT))
	host_col.add_child(Cartoon.label(GameManager.t("room_name"), 18, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_LEFT))
	_room_edit = LineEdit.new()
	_room_edit.theme = Cartoon.theme()
	_room_edit.placeholder_text = NetworkManager.default_room_name()
	_room_edit.max_length = 24
	_room_edit.custom_minimum_size = Vector2(0, 52)
	_room_edit.focus_entered.connect(_on_field_focused.bind(_room_edit))
	host_col.add_child(_room_edit)
	var max_row := UIKit.hbox(8)
	max_row.add_child(Cartoon.label(GameManager.t("max_players"), 18, Cartoon.WHITE, HORIZONTAL_ALIGNMENT_LEFT))
	max_row.add_child(UIKit.spacer())
	max_row.add_child(Cartoon.button("-", func() -> void: _set_max(_max_value - 1), Cartoon.STYLE_NORMAL, Vector2(56, 52)))
	_max_label = Cartoon.label(str(_max_value), 24, Color(1.0, 0.85, 0.12))
	_max_label.custom_minimum_size = Vector2(44, 0)
	max_row.add_child(_max_label)
	max_row.add_child(Cartoon.button("+", func() -> void: _set_max(_max_value + 1), Cartoon.STYLE_NORMAL, Vector2(56, 52)))
	host_col.add_child(max_row)
	host_col.add_child(Cartoon.button(GameManager.t("create_room"), _on_host_pressed, Cartoon.STYLE_PRIMARY, Vector2(0, 64)))
	host_col.add_child(Cartoon.label(GameManager.t("your_ip"), 16, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_LEFT))
	_ip_list_label = Cartoon.label(_format_local_ips(), 20, Color(1.0, 0.85, 0.12), HORIZONTAL_ALIGNMENT_LEFT)
	host_col.add_child(_ip_list_label)
	var port_row := UIKit.hbox(10)
	port_row.add_child(Cartoon.label(GameManager.t("port"), 18, Cartoon.WHITE, HORIZONTAL_ALIGNMENT_LEFT))
	_port_edit = LineEdit.new()
	_port_edit.layout_direction = Control.LAYOUT_DIRECTION_LTR
	_port_edit.text_direction = Control.TEXT_DIRECTION_LTR
	_port_edit.theme = Cartoon.theme()
	_port_edit.text = str(GameConstants.DEFAULT_PORT)
	_port_edit.max_length = 5
	_port_edit.custom_minimum_size = Vector2(140, 48)
	_port_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_port_edit.text_changed.connect(_on_digits_changed.bind(_port_edit))
	_port_edit.focus_entered.connect(_on_field_focused.bind(_port_edit))
	port_row.add_child(_port_edit)
	host_col.add_child(port_row)
	_connect_columns.add_child(host_col)

	_connect_separator = ColorRect.new()
	_connect_separator.color = Color(1, 1, 1, 0.2)
	_connect_separator.custom_minimum_size = Vector2(2, 0)
	_connect_columns.add_child(_connect_separator)

	var join_col := UIKit.vbox(10)
	join_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_col.add_child(Cartoon.label(GameManager.t("rooms_nearby"), 20, Cartoon.YELLOW, HORIZONTAL_ALIGNMENT_LEFT))
	_rooms_status = Cartoon.wrapped_label(GameManager.t("searching"), 18, Color(1, 1, 1, 0.8))
	join_col.add_child(_rooms_status)
	_rooms_box = UIKit.vbox(8)
	_rooms_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_col.add_child(_rooms_box)
	var jrow := UIKit.hbox(8)
	jrow.add_child(Cartoon.button(GameManager.t("refresh"), _on_refresh_pressed, Cartoon.STYLE_NORMAL, Vector2(0, 52)))
	jrow.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_col.add_child(jrow)
	# Manual IPv4 join = optional fallback (hidden until requested).
	var mbox := UIKit.vbox(8)
	_manual_box = mbox
	mbox.add_child(Cartoon.label(GameManager.t("manual_ip") + " - " + GameManager.t("ip_address"), 18, Cartoon.WHITE, HORIZONTAL_ALIGNMENT_LEFT))
	_ip_edit = LineEdit.new()
	_ip_edit.layout_direction = Control.LAYOUT_DIRECTION_LTR
	_ip_edit.text_direction = Control.TEXT_DIRECTION_LTR
	_ip_edit.theme = Cartoon.theme()
	_ip_edit.placeholder_text = "192.168.43.1"
	_ip_edit.max_length = 15
	_ip_edit.custom_minimum_size = Vector2(0, 52)
	_ip_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	_ip_edit.text = _load_last_ip()
	_ip_edit.text_changed.connect(_on_digits_changed.bind(_ip_edit))   # Arabic/Persian digits -> ASCII while typing
	_ip_edit.focus_entered.connect(_on_field_focused.bind(_ip_edit))
	mbox.add_child(_ip_edit)
	mbox.add_child(Cartoon.button(GameManager.t("join_game"), _on_join_pressed, Cartoon.STYLE_PRIMARY, Vector2(0, 60)))
	join_col.add_child(mbox)
	_error_label = Cartoon.wrapped_label("", 18, Color(1, 0.7, 0.7))
	join_col.add_child(_error_label)
	_connect_columns.add_child(join_col)
	column.add_child(_connect_panel)

	_hint_label = Cartoon.wrapped_label(GameManager.t("lobby_hint"), 16, Color(1, 1, 1, 0.75))
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_hint_label)

	# ---- Lobby panel
	_lobby_panel = Cartoon.panel()
	_lobby_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var lbox := UIKit.vbox(10)
	_lobby_panel.add_child(lbox)
	var lhead := UIKit.hbox(10)
	_count_label = Cartoon.label(GameManager.t("players"), 20, Cartoon.YELLOW, HORIZONTAL_ALIGNMENT_LEFT)
	lhead.add_child(_count_label)
	lhead.add_child(UIKit.spacer())
	_host_info_label = Cartoon.label("", 20, Color(1.0, 0.85, 0.12))
	lhead.add_child(_host_info_label)
	lbox.add_child(lhead)
	_settings_box = UIKit.vbox(6)
	var row1 := BoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	_responsive_boxes.append(row1)
	_mode_btn = Cartoon.button("", _on_mode_pressed, Cartoon.STYLE_NORMAL, Vector2(0, 50))
	_mode_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_btn.add_theme_font_size_override("font_size", 20)
	row1.add_child(_mode_btn)
	_map_btn = Cartoon.button("", _on_map_pressed, Cartoon.STYLE_NORMAL, Vector2(0, 50))
	_map_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_btn.add_theme_font_size_override("font_size", 20)
	row1.add_child(_map_btn)
	_bots_minus = Cartoon.button("-", func() -> void: NetworkManager.set_cfg_value("bots", int(NetworkManager.cfg.get("bots", 0)) - 1), Cartoon.STYLE_NORMAL, Vector2(54, 50))
	_bots_label = Cartoon.label("", 20, Cartoon.WHITE)
	_bots_label.custom_minimum_size = Vector2(110, 0)
	_bots_plus = Cartoon.button("+", func() -> void: NetworkManager.set_cfg_value("bots", int(NetworkManager.cfg.get("bots", 0)) + 1), Cartoon.STYLE_NORMAL, Vector2(54, 50))
	row1.add_child(_bots_minus)
	row1.add_child(_bots_label)
	row1.add_child(_bots_plus)
	_settings_box.add_child(row1)
	var row2 := BoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	_responsive_boxes.append(row2)
	_voice_btn = Cartoon.button("", _on_voice_policy_pressed, Cartoon.STYLE_NORMAL, Vector2(0, 46))
	_voice_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_voice_btn.add_theme_font_size_override("font_size", 18)
	row2.add_child(_voice_btn)
	_extra_btn = Cartoon.button("", _on_extra_pressed, Cartoon.STYLE_NORMAL, Vector2(0, 46))
	_extra_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_extra_btn.add_theme_font_size_override("font_size", 18)
	row2.add_child(_extra_btn)
	_balance_btn = Cartoon.button(GameManager.t("auto_teams"), func() -> void: NetworkManager.auto_balance_teams(), Cartoon.STYLE_NORMAL, Vector2(0, 46))
	_balance_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_balance_btn.add_theme_font_size_override("font_size", 18)
	row2.add_child(_balance_btn)
	_mic_btn = Cartoon.button(GameManager.t("mic_test"), _open_mic_test, Cartoon.STYLE_NORMAL, Vector2(0, 46))
	_mic_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mic_btn.add_theme_font_size_override("font_size", 18)
	row2.add_child(_mic_btn)
	_settings_box.add_child(row2)
	lbox.add_child(_settings_box)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbox.add_child(scroll)
	_player_list = UIKit.vbox(6)
	_player_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_player_list)
	var actions := BoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_responsive_boxes.append(actions)
	_ready_button = Cartoon.button(GameManager.t("ready"), _on_ready_pressed, Cartoon.STYLE_PRIMARY, Vector2(220, 60))
	actions.add_child(_ready_button)
	_start_button = Cartoon.button(GameManager.t("start_match"), _on_start_pressed, Cartoon.STYLE_PRIMARY, Vector2(260, 60))
	actions.add_child(_start_button)
	actions.add_child(Cartoon.button(GameManager.t("leave"), _on_leave_pressed, Cartoon.STYLE_DANGER, Vector2(160, 60)))
	lbox.add_child(actions)
	column.add_child(_lobby_panel)


func _on_viewport_resized() -> void:
	if _connect_columns == null:
		return
	var size := get_viewport().get_visible_rect().size
	var compact := size.x < 900.0 or size.y < 560.0
	_connect_columns.vertical = compact
	if _connect_separator != null:
		_connect_separator.custom_minimum_size = Vector2(0, 2) if compact else Vector2(2, 0)
	for box in _responsive_boxes:
		if is_instance_valid(box):
			box.vertical = compact
	for button in [_ready_button, _start_button]:
		if button != null:
			button.custom_minimum_size.x = 0.0 if compact else (220.0 if button == _ready_button else 260.0)


func _format_local_ips() -> String:
	var ips := NetworkManager.get_local_ips()
	if ips.is_empty():
		return GameManager.t("no_ip")
	var shown: Array = []
	for i in mini(ips.size(), 3):
		shown.append(str(ips[i]))
	return "  |  ".join(shown)


# ---------------------------------------------------------------------------
# Panel switching

func _show_connect() -> void:
	_connect_panel.visible = true
	_hint_label.visible = true
	_lobby_panel.visible = false
	_ip_list_label.text = _format_local_ips()
	_start_browsing()
	_rebuild_rooms()


func _show_lobby() -> void:
	_connect_panel.visible = false
	_hint_label.visible = false
	_lobby_panel.visible = true
	_stop_browsing()
	_is_ready = false
	_refresh_players()


# ---------------------------------------------------------------------------
# Actions

func _on_host_pressed() -> void:
	_error_label.text = ""
	var port := _parse_port()
	if port < 0:
		return
	_stop_browsing()
	var err := NetworkManager.host_game(port, _room_edit.text, _max_value)
	if err != "":
		_error_label.text = err
		_start_browsing()
		return
	if NetworkManager.discovery.mode != LanDiscovery.Mode.ADVERTISE:
		GameManager.toast(GameManager.t("discovery_off"))     # server runs, only auto-discovery is unavailable
	_show_lobby()


## Manual IPv4 fallback.
func _on_join_pressed() -> void:
	_error_label.text = ""
	if NetworkManager.is_busy():
		return
	var port := _parse_port()
	if port < 0:
		return
	var ip := NetUtils.parse_ipv4(_ip_edit.text)
	if ip == "":
		_error_label.text = GameManager.t("invalid_ip")
		return
	_ip_edit.text = ip
	var err := NetworkManager.join_game(ip, port)
	if err != "":
		_error_label.text = err
		return
	_save_last_ip(ip)
	_status_label.text = GameManager.t("connecting")
	_rebuild_rooms()


## One-tap join of a discovered room (no IP typing).
func _on_room_join(room: Dictionary) -> void:
	_error_label.text = ""
	if NetworkManager.is_busy():
		return
	_status_label.text = GameManager.t("connecting")
	NetworkManager.join_room(room)
	_rebuild_rooms()      # greys out the JOIN buttons while connecting


func _on_refresh_pressed() -> void:
	_error_label.text = ""
	NetworkManager.discovery.refresh()
	_rebuild_rooms()


func _set_max(v: int) -> void:
	_max_value = clampi(v, GameConstants.MIN_PLAYERS, GameConstants.MAX_PLAYERS)
	_max_label.text = str(_max_value)


## Keeps typed numbers ASCII: Arabic-Indic / Persian digits and Arabic separators are converted on the fly.
func _on_digits_changed(new_text: String, edit: LineEdit) -> void:
	var fixed := NetUtils.normalize_text(new_text)
	if fixed != new_text:
		var col := edit.caret_column
		edit.text = fixed
		edit.caret_column = mini(col, fixed.length())
	if edit == _ip_edit and NetUtils.parse_ipv4(fixed) != "":
		_save_last_ip(NetUtils.parse_ipv4(fixed))      # a valid manual IP is remembered automatically


func _parse_port() -> int:
	var port := NetUtils.parse_port(_port_edit.text)
	if port < 0:
		_error_label.text = GameManager.t("invalid_port")
	return port


func _start_browsing() -> void:
	NetworkManager.discovery.start_browsing()


func _stop_browsing() -> void:
	if NetworkManager.discovery != null and NetworkManager.discovery.mode == LanDiscovery.Mode.BROWSE:
		NetworkManager.discovery.stop()


func _rebuild_rooms() -> void:
	if _rooms_box == null or not is_inside_tree():
		return
	for c in _rooms_box.get_children():
		_rooms_box.remove_child(c)
		c.queue_free()
	var busy := NetworkManager.is_busy()
	var autofilled := false
	for r in NetworkManager.discovery.get_room_list():
		# The manual IP box is filled automatically with the first open room found (no typing needed).
		if not autofilled and not _ip_edit.has_focus() and int(r["players"]) < int(r["max"]) and not bool(r["in_progress"]):
			_ip_edit.text = str(r["ip"])
			autofilled = true
		var full := int(r["players"]) >= int(r["max"])
		var running := bool(r["in_progress"])
		var row := Cartoon.panel(Color(1, 1, 1, 0.10), 14, 8)
		var h := UIKit.hbox(10)
		var info := UIKit.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var title := Cartoon.label("%s: %s" % [GameManager.t("room_label"), str(r["room"])], 22, Cartoon.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		title.clip_text = true
		info.add_child(title)
		var state_text := GameManager.t("room_in_progress") if running else (GameManager.t("room_full") if full else GameManager.t("room_open"))
		var state_color := Color(1.0, 0.6, 0.5) if (running or full) else Color(0.55, 1.0, 0.5)
		info.add_child(Cartoon.label(GameManager.t("host_nick") % str(r["host"]), 16, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_LEFT))
		var line := UIKit.hbox(10)
		line.add_child(Cartoon.label(GameManager.t("players_count") % [int(r["players"]), int(r["max"])], 18, Color(1.0, 0.85, 0.12), HORIZONTAL_ALIGNMENT_LEFT))
		line.add_child(Cartoon.label(state_text, 16, state_color, HORIZONTAL_ALIGNMENT_LEFT))
		info.add_child(line)
		h.add_child(info)
		var jb := Cartoon.button(GameManager.t("join_btn"), _on_room_join.bind(r.duplicate()), Cartoon.STYLE_PRIMARY, Vector2(130, 64))
		jb.disabled = full or running or busy
		h.add_child(jb)
		row.add_child(h)
		_rooms_box.add_child(row)
	_update_rooms_status()


func _update_rooms_status() -> void:
	if _rooms_status == null:
		return
	if NetworkManager.is_busy():
		_rooms_status.text = GameManager.t("connecting")
	elif NetworkManager.discovery.last_error == "no_network":
		_rooms_status.text = GameManager.t("no_network")
	elif NetworkManager.discovery.rooms.is_empty():
		_rooms_status.text = GameManager.t("searching") + "\n" + GameManager.t("no_rooms_hint")
	else:
		_rooms_status.text = ""


func _on_field_focused(edit: LineEdit) -> void:
	await get_tree().create_timer(0.35).timeout      # let the keyboard animate in first
	if is_instance_valid(edit) and edit.is_inside_tree():
		_connect_scroll.ensure_control_visible(edit)


func _process(delta: float) -> void:
	if _connect_panel == null or not _connect_panel.visible:
		return
	_status_tick += delta
	if _status_tick >= 0.5:
		_status_tick = 0.0
		_update_rooms_status()
	# Reserve space for the Android on-screen keyboard so it never hides the input fields.
	# Only query the keyboard where the display server supports it (desktop/headless print an error every call).
	var kb := 0.0
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		kb = float(DisplayServer.virtual_keyboard_get_height())
	var win_h := float(DisplayServer.window_get_size().y)
	var h := kb * get_viewport_rect().size.y / win_h if (kb > 0.0 and win_h > 0.0) else 0.0
	if absf(h - _last_kb_height) > 1.0:
		_last_kb_height = h
		_kb_spacer.custom_minimum_size = Vector2(0, h)
		var f := get_viewport().gui_get_focus_owner()
		if h > 0.0 and f is Control and _connect_panel.is_ancestor_of(f):
			_connect_scroll.ensure_control_visible.call_deferred(f)


func _on_ready_pressed() -> void:
	_is_ready = not _is_ready
	NetworkManager.set_ready(_is_ready)
	_refresh_players()


func _on_start_pressed() -> void:
	if not NetworkManager.is_host:
		GameManager.toast(GameManager.t("host_required"))
		return
	var problem := NetworkManager.start_problem()
	if problem != "":
		var msg := GameManager.t(problem)
		if problem == "need_players":
			msg = msg % GameConstants.MIN_PLAYERS
		GameManager.toast(msg)
		return
	NetworkManager.start_match()


func _toggle_peer_mute(id: int) -> void:
	VoiceChat.toggle_peer_mute(id)
	_refresh_players()


func _on_mode_pressed() -> void:
	var next_mode := (int(NetworkManager.cfg.get("mode", 0)) + 1) % GameConstants.MODE_COUNT
	NetworkManager.set_cfg_value("mode", next_mode)
	var valid_maps := GameConstants.maps_for_mode(next_mode)
	if not valid_maps.has(int(NetworkManager.cfg.get("map", 0))):
		NetworkManager.set_cfg_value("map", int(valid_maps[0]))


func _on_map_pressed() -> void:
	# Opens the picture picker (host only: the button is disabled for clients).
	if _map_overlay != null and is_instance_valid(_map_overlay):
		return
	var maps: Array = GameConstants.maps_for_mode(int(NetworkManager.cfg.get("mode", 0)))
	_map_overlay = MapPickerScript.new()
	_map_overlay.setup(maps, int(NetworkManager.cfg.get("map", 0)))
	add_child(_map_overlay)
	_map_overlay.picked.connect(func(map_id: int) -> void: NetworkManager.set_cfg_value("map", map_id))
	_map_overlay.closed.connect(func() -> void: _map_overlay = null)


func _on_voice_policy_pressed() -> void:
	NetworkManager.set_cfg_value("voice_policy", (int(NetworkManager.cfg.get("voice_policy", 0)) + 1) % 3)


func _on_extra_pressed() -> void:
	var mode := int(NetworkManager.cfg.get("mode", 0))
	if mode == GameConstants.MODE_HIDE:
		NetworkManager.set_cfg_value("hider_team", 1 - int(NetworkManager.cfg.get("hider_team", 0)))
	elif mode == GameConstants.MODE_TEAMS:
		var n := int(NetworkManager.cfg.get("team_count", 2)) + 1
		NetworkManager.set_cfg_value("team_count", 2 if n > 4 else n)


func _open_mic_test() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return
	_overlay = preload("res://scripts/mic_test.gd").new()
	add_child(_overlay)
	_overlay.closed.connect(func() -> void: _overlay = null)


func _on_leave_pressed() -> void:
	NetworkManager.leave()
	_show_connect()


func _on_back() -> void:
	NetworkManager.leave()
	GameManager.go_to_main_menu()


func _open_customize() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return
	_overlay = CustomScene.instantiate()
	add_child(_overlay)
	_overlay.closed.connect(func() -> void:
		if _overlay != null and is_instance_valid(_overlay):
			_overlay.queue_free()
		_overlay = null
	)


# ---------------------------------------------------------------------------
# Network feedback

func _on_connected() -> void:
	if NetUtils.parse_ipv4(NetworkManager.host_address) != "":
		_save_last_ip(NetworkManager.host_address)     # also remember hosts joined through the room list
		_ip_edit.text = NetworkManager.host_address
	_show_lobby()


func _on_failed(reason: String) -> void:
	_show_connect()
	_rebuild_rooms()
	_error_label.text = reason
	_status_label.text = GameManager.t("not_connected")


func _on_status(text: String) -> void:
	_status_label.text = text


func _refresh_players() -> void:
	if not is_inside_tree():
		return
	if not NetworkManager.online:
		if _lobby_panel.visible:
			_show_connect()
		return
	for c in _player_list.get_children():
		c.queue_free()
	var my_id := multiplayer.get_unique_id()
	var ids := NetworkManager.get_sorted_ids()
	for id in ids:
		var info: Dictionary = NetworkManager.players[id]
		var row := Cartoon.panel(Color(1, 1, 1, 0.08), 14, 8)
		var h := UIKit.hbox(12)
		var swatch := ColorRect.new()
		swatch.color = GameConstants.get_color(int(info.get("color", 0)))
		swatch.custom_minimum_size = Vector2(34, 34)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(swatch)
		var label_text := str(info.get("name", "Player"))
		if int(id) == 1:
			label_text += "  [%s]" % GameManager.t("host")
		if int(id) == my_id:
			label_text += "  (%s)" % GameManager.t("you")
		var name_label := Cartoon.label(label_text, 22, Cartoon.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(name_label)
		h.add_child(Cartoon.label("%s: %d" % [GameManager.t("score"), int(info.get("score", 0))], 18, Color(1, 1, 1, 0.7)))
		var cfg_mode := int(NetworkManager.cfg.get("mode", 0))
		if GameConstants.uses_teams(cfg_mode):
			var tm := int(info.get("team", 0))
			var tname := GameManager.team_name(tm)
			if cfg_mode == GameConstants.MODE_HIDE:
				tname = GameManager.t("hs_hiders") if tm == int(NetworkManager.cfg.get("hider_team", 0)) else GameManager.t("hs_seekers")
			var tb := Cartoon.button(tname, func() -> void: NetworkManager.set_team(int(id), int(NetworkManager.players[id].get("team", 0)) + 1), Cartoon.STYLE_NORMAL, Vector2(150, 44))
			tb.add_theme_font_size_override("font_size", 18)
			tb.add_theme_color_override("font_color", GameConstants.team_color(tm).lightened(0.3))
			tb.disabled = not NetworkManager.is_host     # only the host assigns teams
			h.add_child(tb)
		if int(id) != my_id:
			var mb := Cartoon.button(GameManager.t("unmute_btn") if VoiceChat.is_peer_muted(int(id)) else GameManager.t("mute_btn"), _toggle_peer_mute.bind(int(id)), Cartoon.STYLE_NORMAL, Vector2(110, 44))
			mb.add_theme_font_size_override("font_size", 16)
			h.add_child(mb)
		var ready_text := GameManager.t("ready") if bool(info.get("ready", false)) else GameManager.t("not_ready")
		var ready_color := Color(0.45, 0.95, 0.4) if bool(info.get("ready", false)) else Color(1, 1, 1, 0.5)
		if int(id) == 1:
			ready_text = GameManager.t("host")
			ready_color = Color(1.0, 0.85, 0.12)
		h.add_child(Cartoon.label(ready_text, 20, ready_color))
		row.add_child(h)
		_player_list.add_child(row)
	_count_label.text = "%s: %d / %d" % [GameManager.t("players"), ids.size(), int(NetworkManager.cfg.get("max_players", GameConstants.MAX_PLAYERS))]
	_refresh_settings()
	if NetworkManager.is_host:
		_host_info_label.text = "%s: %s  |  %s : %d" % [GameManager.t("room_label"), NetworkManager.room_name, _format_local_ips(), NetworkManager.port]
		_ready_button.visible = false
		_start_button.visible = true
		_start_button.disabled = not NetworkManager.can_start()
	else:
		_host_info_label.text = "%s %s:%d" % [GameManager.t("host"), NetworkManager.host_address, NetworkManager.port]
		_ready_button.visible = true
		_start_button.visible = false
		_ready_button.text = ("✓ " + GameManager.t("ready")) if _is_ready else (GameManager.t("ready") + "?")
		_ready_button.modulate = Color(0.75, 1.0, 0.75) if _is_ready else Color.WHITE


func _refresh_settings() -> void:
	var cfg: Dictionary = NetworkManager.cfg
	if cfg.is_empty():
		return
	var host := NetworkManager.is_host
	var mode := int(cfg.get("mode", 0))
	var mode_keys := ["mode_ffa", "mode_teams", "mode_hide", "mode_ko", "mode_trampoline"]
	_mode_btn.text = "%s: %s" % [GameManager.t("mode"), GameManager.t(mode_keys[mode])]
	var map_id := int(cfg.get("map", 0))
	_map_btn.text = "%s: %s (%s)" % [GameManager.t("map"), GameManager.t(GameConstants.MAPS[map_id]["key"]), GameManager.t(GameConstants.MAPS[map_id]["size_key"])]
	_bots_label.text = "%s %d" % [GameManager.t("bots"), int(cfg.get("bots", 0))]
	var vp_keys := ["voice_choice", "voice_team", "voice_all"]
	_voice_btn.text = "%s: %s" % [GameManager.t("voice"), GameManager.t(vp_keys[int(cfg.get("voice_policy", 0))])]
	if mode == GameConstants.MODE_HIDE:
		_extra_btn.text = GameManager.t("swap_roles")
		_extra_btn.visible = true
	elif mode == GameConstants.MODE_TEAMS:
		_extra_btn.text = "%s: %d" % [GameManager.t("team_count"), int(cfg.get("team_count", 2))]
		_extra_btn.visible = true
	else:
		_extra_btn.visible = false
	_balance_btn.visible = GameConstants.uses_teams(mode)
	for b in [_mode_btn, _map_btn, _bots_minus, _bots_plus, _voice_btn, _extra_btn, _balance_btn]:
		b.disabled = not host      # only the host can change room-wide settings (the host also re-validates)


# ---------------------------------------------------------------------------
# Remember the last IP used

func _load_last_ip() -> String:
	var cfg := ConfigFile.new()
	if cfg.load("user://lobby.cfg") == OK:
		return str(cfg.get_value("lobby", "last_ip", ""))
	return ""


func _save_last_ip(ip: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("lobby", "last_ip", ip)
	cfg.save("user://lobby.cfg")