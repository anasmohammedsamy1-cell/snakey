extends Control
## Character customisation: live 3D preview, 8 original colour presets,
## name entry with validation, save / reset. Saved locally via SaveManager and
## pushed to the lobby if we are currently connected.

signal closed

const Cartoon := preload("res://scripts/cartoon_ui.gd")
const UIKit := preload("res://scripts/ui_kit.gd")
const GameConstants := preload("res://scripts/game_constants.gd")
const Scenery := preload("res://scripts/scenery.gd")
const VisualsScript := preload("res://scripts/character/contender_visuals.gd")
const AccessoriesLib := preload("res://scripts/accessories.gd")

var _name_edit: LineEdit
var _color_grid: GridContainer
var _color_name: Label
var _detail_grid: GridContainer
var _detail_name: Label
var _selected_detail := -1
var _preview_char: Node3D
var _selected_color := 0
var _error_label: Label
var _body_layout: BoxContainer
var _preview_frame: PanelContainer
var _preview_container: SubViewportContainer
var _header_title: Label
var _header_back: Button
var _coins_label: Label
var _name_cost_label: Label
var _acc_grid: GridContainer
var _acc_info: Label
var _acc_action: Button
var _acc_selected := ""              # item shown in the preview ("" = no accessory)
var _acc_equipped := ""              # what will be saved as the equipped accessory


func _ready() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_RTL if GameManager.is_rtl() else Control.LAYOUT_DIRECTION_LTR
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_selected_color = SaveManager.color_index
	_selected_detail = SaveManager.detail_color_index
	_acc_equipped = SaveManager.equipped_hat
	_acc_selected = _acc_equipped
	_build()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()


func _build() -> void:
	UIKit.dim_background(self)
	var panel := Cartoon.panel(Cartoon.COLOR_PANEL, 22, 12)
	var box := UIKit.vbox(6)
	panel.add_child(box)

	var header := UIKit.hbox(8)
	_header_title = Cartoon.title(GameManager.t("customize"), 36)
	header.add_child(_header_title)
	header.add_child(UIKit.spacer())
	_coins_label = Cartoon.label("", 24, Cartoon.YELLOW, HORIZONTAL_ALIGNMENT_RIGHT)
	_coins_label.name = "CoinsLabel"
	header.add_child(_coins_label)
	_header_back = Cartoon.button(GameManager.t("back"), _close, Cartoon.STYLE_NORMAL, Vector2(120, 48))
	header.add_child(_header_back)
	box.add_child(header)

	var body := BoxContainer.new()
	_body_layout = body
	body.vertical = get_viewport().get_visible_rect().size.x < 900.0
	body.add_theme_constant_override("separation", 8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var body_scroll := ScrollContainer.new()
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.add_child(body)
	box.add_child(body_scroll)

	# ---- Left: 3D preview in its own world
	var preview_frame := Cartoon.panel(Color(1, 1, 1, 0.08), 12, 6)
	_preview_frame = preview_frame
	preview_frame.custom_minimum_size = Vector2(210, 240) if not body.vertical else Vector2(0, 170)
	preview_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var container := SubViewportContainer.new()
	_preview_container = container
	container.stretch = true
	container.custom_minimum_size = Vector2(210, 240) if not body.vertical else Vector2(0, 170)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	preview_frame.add_child(container)
	body.add_child(preview_frame)
	_build_preview_world(viewport)

	# ---- Right: controls
	var right := UIKit.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right)

	right.add_child(Cartoon.label(GameManager.t("your_name"), 20, Cartoon.WHITE, HORIZONTAL_ALIGNMENT_LEFT))
	_name_edit = LineEdit.new()
	_name_edit.theme = Cartoon.theme()
	_name_edit.text = SaveManager.player_name
	_name_edit.max_length = SaveManager.MAX_NAME_LENGTH
	_name_edit.placeholder_text = "Player"
	_name_edit.custom_minimum_size = Vector2(0, 48)
	_name_edit.text_changed.connect(_on_name_changed)
	right.add_child(_name_edit)
	_name_cost_label = Cartoon.wrapped_label("", 15, Color(1, 1, 1, 0.75))
	right.add_child(_name_cost_label)
	_error_label = Cartoon.label("", 16, Color(1, 0.6, 0.6), HORIZONTAL_ALIGNMENT_LEFT)
	right.add_child(_error_label)

	right.add_child(Cartoon.label(GameManager.t("choose_color"), 20, Cartoon.WHITE, HORIZONTAL_ALIGNMENT_LEFT))
	_color_grid = GridContainer.new()
	_color_grid.columns = 4 if get_viewport().get_visible_rect().size.x >= 520.0 else 2
	_color_grid.add_theme_constant_override("h_separation", 8)
	_color_grid.add_theme_constant_override("v_separation", 8)
	right.add_child(_color_grid)
	_color_name = Cartoon.label(GameConstants.get_color_name(_selected_color), 20, GameConstants.get_color(_selected_color), HORIZONTAL_ALIGNMENT_LEFT)
	right.add_child(_color_name)
	_refresh_swatches()

	right.add_child(Cartoon.label(GameManager.t("detail_color"), 20, Cartoon.WHITE, HORIZONTAL_ALIGNMENT_LEFT))
	_detail_grid = GridContainer.new()
	_detail_grid.columns = 4 if get_viewport().get_visible_rect().size.x >= 520.0 else 2
	_detail_grid.add_theme_constant_override("h_separation", 8)
	_detail_grid.add_theme_constant_override("v_separation", 8)
	right.add_child(_detail_grid)
	_detail_name = Cartoon.label(_detail_color_name(_selected_detail), 20, GameConstants.get_detail_color(_selected_detail), HORIZONTAL_ALIGNMENT_LEFT)
	right.add_child(_detail_name)
	_refresh_detail_swatches()

	right.add_child(Cartoon.label(GameManager.t("accessories"), 20, Cartoon.WHITE, HORIZONTAL_ALIGNMENT_LEFT))
	_acc_grid = GridContainer.new()
	_acc_grid.columns = 3 if get_viewport().get_visible_rect().size.x >= 520.0 else 2
	_acc_grid.add_theme_constant_override("h_separation", 6)
	_acc_grid.add_theme_constant_override("v_separation", 6)
	right.add_child(_acc_grid)
	_acc_info = Cartoon.wrapped_label("", 16, Cartoon.YELLOW)
	right.add_child(_acc_info)
	_acc_action = Cartoon.button("", _on_acc_action, Cartoon.STYLE_PRIMARY, Vector2(0, 46))
	right.add_child(_acc_action)
	_refresh_shop()

	right.add_child(Cartoon.label(GameManager.t("progress_title"), 19, Cartoon.COLOR_PRIMARY, HORIZONTAL_ALIGNMENT_LEFT))
	var matches_text := GameManager.t("challenge_matches") % mini(SaveManager.matches_played, SaveManager.MATCH_COLOR_TARGET)
	if SaveManager.is_color_unlocked(SaveManager.MATCH_COLOR):
		matches_text += "  ✓ " + GameManager.t("challenge_unlocked")
	var wins_text := GameManager.t("challenge_win") % mini(SaveManager.rounds_won, 1)
	if SaveManager.is_color_unlocked(SaveManager.WIN_COLOR):
		wins_text += "  ✓ " + GameManager.t("challenge_unlocked")
	right.add_child(Cartoon.wrapped_label(matches_text, 16))
	right.add_child(Cartoon.wrapped_label(wins_text, 16))
	right.add_child(Cartoon.wrapped_label(GameManager.t("progress_excludes_practice"), 14, Color(1, 1, 1, 0.7)))

	right.add_child(UIKit.spacer())
	var actions := UIKit.hbox(12)
	var save_button := Cartoon.button(GameManager.t("save"), _save, Cartoon.STYLE_PRIMARY, Vector2(0, 52))
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var reset_button := Cartoon.button(GameManager.t("reset_default"), _reset, Cartoon.STYLE_NORMAL, Vector2(0, 52))
	reset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(save_button)
	actions.add_child(reset_button)
	right.add_child(actions)

	add_child(UIKit.centered(panel, Vector2(760, 540)))
	UIKit.add_fade_in(panel)


func _on_viewport_resized() -> void:
	if _body_layout == null or _color_grid == null:
		return
	var width := get_viewport().get_visible_rect().size.x
	var compact := width < 900.0
	_header_title.add_theme_font_size_override("font_size", 26 if width < 520.0 else 36)
	_header_back.custom_minimum_size = Vector2(92, 48) if width < 520.0 else Vector2(120, 48)
	_body_layout.vertical = compact
	_color_grid.columns = 2 if width < 520.0 else 4
	if _detail_grid != null:
		_detail_grid.columns = 2 if width < 520.0 else 4
	if _acc_grid != null:
		_acc_grid.columns = 2 if width < 520.0 else 3
	_preview_frame.custom_minimum_size = Vector2(0, 180) if compact else Vector2(240, 260)
	_preview_container.custom_minimum_size = Vector2(0, 180) if compact else Vector2(240, 260)


func _build_preview_world(viewport: SubViewport) -> void:
	var world := Node3D.new()
	viewport.add_child(world)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.45, 4.7)
	cam.fov = 45.0
	world.add_child(cam)
	# look_at_from_position works even while the preview viewport is not inside the tree yet
	cam.look_at_from_position(cam.position, Vector3(0, 0.95, 0), Vector3.UP)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 35, 0)
	light.light_energy = 1.12
	world.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -120, 0)
	fill.light_energy = 0.45
	world.add_child(fill)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.12, 0.3, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.8, 1.0)
	env.ambient_light_energy = 0.88
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.92
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.34
	env.adjustment_saturation = 1.45
	env_node.environment = env
	world.add_child(env_node)
	var disc := Scenery.mesh_instance(Scenery.cylinder(1.1, 1.1, 0.2, 32), Scenery.mat(Color(1.0, 0.6, 0.2), 0.7), Vector3(0, -0.1, 0))
	world.add_child(disc)
	_preview_char = Node3D.new()
	_preview_char.set_script(VisualsScript)
	_preview_char.demo_mode = true
	_preview_char.demo_spin = true
	world.add_child(_preview_char)
	_preview_char.rotation.y = PI      # the character faces -Z, turn it toward the preview camera
	_preview_char.build(GameConstants.get_color(_selected_color), GameConstants.get_detail_color(_selected_detail))
	_preview_char.set_hat(_acc_selected)


func _refresh_swatches() -> void:
	for c in _color_grid.get_children():
		c.queue_free()
	for i in GameConstants.color_count():
		var swatch := _color_swatch(GameConstants.get_color(i), i == _selected_color, func() -> void: _select_color(i), 52.0)
		swatch.name = "Color%d" % i
		if not SaveManager.is_color_unlocked(i):
			swatch.disabled = true
			swatch.text = GameManager.t("color_locked_short")
			swatch.add_theme_font_size_override("font_size", 14)
			swatch.tooltip_text = GameManager.t("challenge_matches") % mini(SaveManager.matches_played, SaveManager.MATCH_COLOR_TARGET) if i == SaveManager.MATCH_COLOR else GameManager.t("challenge_win") % mini(SaveManager.rounds_won, 1)
		_color_grid.add_child(swatch)


func _select_color(index: int) -> void:
	if not SaveManager.is_color_unlocked(index):
		return
	_selected_color = index
	_color_name.text = GameConstants.get_color_name(index)
	_color_name.add_theme_color_override("font_color", GameConstants.get_color(index))
	if _preview_char != null:
		_preview_char.set_color(GameConstants.get_color(index))
	_refresh_swatches()


## Screws, gaps and seams colour: swatch 0 keeps the classic metal, the rest are
## the body colour presets (stored index = swatch - 1).
func _refresh_detail_swatches() -> void:
	for c in _detail_grid.get_children():
		c.queue_free()
	for i in GameConstants.detail_color_count():
		var stored := i - 1
		var col := GameConstants.get_detail_color(stored)
		var swatch := _color_swatch(col, stored == _selected_detail, func() -> void: _select_detail(stored), 52.0)
		swatch.name = "Detail%d" % i
		if stored >= 0 and not SaveManager.is_color_unlocked(stored):
			swatch.disabled = true
			swatch.text = GameManager.t("color_locked_short")
			swatch.add_theme_font_size_override("font_size", 14)
		_detail_grid.add_child(swatch)


func _select_detail(index: int) -> void:
	if not GameConstants.is_detail_color_valid(index):
		return
	if index >= 0 and not SaveManager.is_color_unlocked(index):
		return
	_selected_detail = index
	_detail_name.text = _detail_color_name(index)
	_detail_name.add_theme_color_override("font_color", GameConstants.get_detail_color(index))
	if _preview_char != null:
		_preview_char.set_detail_color(GameConstants.get_detail_color(index))
	_refresh_detail_swatches()


func _detail_color_name(index: int) -> String:
	return GameManager.t("detail_metal") if index < 0 else GameConstants.get_color_name(index)


func _on_name_changed(new_text: String) -> void:
	if new_text.strip_edges().is_empty():
		_error_label.text = GameManager.t("empty_name_hint")
	else:
		_error_label.text = ""


func _refresh_coins() -> void:
	_coins_label.text = "%s: %d" % [GameManager.t("coins"), SaveManager.coins]
	var cost := SaveManager.name_change_cost()
	_name_cost_label.text = GameManager.t("name_first_free") if cost == 0 else GameManager.t("name_cost") % cost


func _refresh_shop() -> void:
	_refresh_coins()
	for c in _acc_grid.get_children():
		c.queue_free()
	var none_btn := Cartoon.button(GameManager.t("acc_none"), func() -> void: _select_acc(""), Cartoon.STYLE_PRIMARY if _acc_selected == "" else Cartoon.STYLE_NORMAL, Vector2(0, 44))
	none_btn.name = "Acc_none"
	_acc_grid.add_child(none_btn)
	for it in AccessoriesLib.ITEMS:
		var id := str(it["id"])
		var owned := SaveManager.owned_hats.has(id)
		var label := GameManager.t(str(it["key"])) + ("  ✓" if owned else "  %d" % int(it["price"]))
		var b := Cartoon.button(label, func() -> void: _select_acc(id), Cartoon.STYLE_PRIMARY if _acc_selected == id else Cartoon.STYLE_NORMAL, Vector2(0, 44))
		b.name = "Acc_" + id
		_acc_grid.add_child(b)
	_refresh_acc_action()


func _refresh_acc_action() -> void:
	if _acc_selected == "":
		_acc_info.text = ""
		_acc_action.visible = _acc_equipped != ""
		_acc_action.text = GameManager.t("acc_unequip")
		return
	_acc_action.visible = true
	if SaveManager.owned_hats.has(_acc_selected):
		_acc_info.text = GameManager.t(AccessoriesLib.key_of(_acc_selected))
		_acc_action.text = GameManager.t("acc_equipped") if _acc_equipped == _acc_selected else GameManager.t("acc_equip")
	else:
		var price := AccessoriesLib.price_of(_acc_selected)
		_acc_info.text = "%s - %d %s" % [GameManager.t(AccessoriesLib.key_of(_acc_selected)), price, GameManager.t("coins")]
		_acc_action.text = GameManager.t("acc_buy") % price


func _select_acc(id: String) -> void:
	_acc_selected = id
	if _preview_char != null:
		_preview_char.set_hat(id)
	_refresh_shop()


func _on_acc_action() -> void:
	if _acc_selected == "":
		_acc_equipped = ""
		SaveManager.equip_hat("")
	elif SaveManager.owned_hats.has(_acc_selected):
		_acc_equipped = _acc_selected
		SaveManager.equip_hat(_acc_selected)
	else:
		var err := SaveManager.buy_hat(_acc_selected)
		if err == "need_coins":
			GameManager.toast(GameManager.t("need_coins"))
		elif err == "":
			_acc_equipped = _acc_selected
			SaveManager.equip_hat(_acc_selected)
			GameManager.toast(GameManager.t("acc_bought"))
	NetworkManager.update_local_info()
	_refresh_shop()


func _save() -> void:
	var err := SaveManager.set_profile(_name_edit.text, _selected_color, _selected_detail)
	if err == "need_coins":
		_error_label.text = GameManager.t("need_coins_name") % SaveManager.NAME_CHANGE_COST
		_name_edit.text = SaveManager.player_name
		_refresh_coins()
		return
	_name_edit.text = SaveManager.player_name
	NetworkManager.update_local_info()
	GameManager.toast(GameManager.t("saved"))
	_close()


func _reset() -> void:
	SaveManager.reset_defaults()
	_selected_color = SaveManager.color_index
	_selected_detail = SaveManager.detail_color_index
	_name_edit.text = SaveManager.player_name
	_acc_equipped = ""
	_select_acc("")
	_select_color(_selected_color)
	_select_detail(_selected_detail)
	NetworkManager.update_local_info()
	GameManager.toast(GameManager.t("saved"))


func _close() -> void:
	closed.emit()


# --- Local UI builder (formerly in UIKit) ---

func _color_swatch(color: Color, selected: bool, on_pressed: Callable, size: float) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(size, size)
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.flat = false
	b.focus_mode = Control.FOCUS_NONE
	var sb_normal := Cartoon.stylebox(color, int(size * 0.33), Cartoon.PURPLE_DARK, 0, 0, 4)
	var sb_hover := Cartoon.stylebox(color.lightened(0.15), int(size * 0.33), Cartoon.YELLOW, 3, 0, 4)
	var sb_pressed := Cartoon.stylebox(color.darkened(0.1), int(size * 0.33), Cartoon.YELLOW, 3, 0, 4)
	b.add_theme_stylebox_override("normal", sb_normal)
	b.add_theme_stylebox_override("hover", sb_hover)
	b.add_theme_stylebox_override("pressed", sb_pressed)
	b.add_theme_stylebox_override("disabled", Cartoon.stylebox(Color(1, 1, 1, 0.1), int(size * 0.33), Color(0, 0, 0, 0), 0, 0))
	if selected:
		var sb_sel := Cartoon.stylebox(color, int(size * 0.33), Cartoon.YELLOW, 4, 0, 4)
		b.add_theme_stylebox_override("normal", sb_sel)
	b.pressed.connect(on_pressed)
	return b
