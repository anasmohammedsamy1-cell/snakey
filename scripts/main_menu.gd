extends Control
## Main menu built around the NewAssets cartoon identity.
##
## The supplied background and logo are used directly; the action panel, buttons
## and profile strip are real Godot controls styled by CartoonUI so localisation,
## live profile data, keyboard/gamepad focus and touch all keep working.
## Motion uses Tweens (bouncy cascades, hover lift, gentle idle drift).

const UIKit := preload("res://scripts/ui_kit.gd")
const Cartoon := preload("res://scripts/cartoon_ui.gd")
const GameConstants := preload("res://scripts/game_constants.gd")
const SettingsScene := preload("res://scenes/ui/settings_menu.tscn")
const CustomScene := preload("res://scenes/ui/customization_menu.tscn")
const MapPickerScript := preload("res://scripts/map_picker.gd")

const BG_TEXTURE := preload("res://NewAssets/mainMenu/MainMenuBG.jpeg")
const LOGO_TEXTURE := preload("res://NewAssets/mainMenu/MainMenuIcon.png")
const BTNS_BG_TEXTURE := preload("res://NewAssets/mainMenu/BtnsBG.png")

# Main-menu buttons use one shared primary texture (Play) and one shared
# secondary texture (every other action). Labels are real Button text so they
# stay localised. game_font.tres pairs the Milkyway display face with the
# project's Noto Sans Arabic fallback for digits, punctuation and Arabic.
const BRAND_FONT := preload("res://assets/fonts/game_font.tres")

const PRIMARY_BTN_TEX := preload("res://NewAssets/mainMenu/PrimaryBtnTexture.png")
const SECONDARY_BTN_TEX := preload("res://NewAssets/mainMenu/SecondaryBtnTexture.png")
# Visible pill bounds inside SecondaryBtnTexture.png. Trimming the transparent
# padding keeps the pill at the source proportions when it is stretched into
# the different button slots.
const SECONDARY_BTN_REGION := Rect2(15, 31, 365, 71)

const OUTER_MARGIN_WIDE := 26.0
const OUTER_MARGIN_COMPACT := 14.0
const PROFILE_BAR_WIDE_HEIGHT := 58.0
const PROFILE_BAR_COMPACT_HEIGHT := 46.0

# MainMenuBG.jpeg is 1024x576 and has a baked-in profile strip. The bar below is
# resized and placed to cover it at every aspect ratio.
const BG_ART_SIZE := Vector2(1024.0, 576.0)
const BG_STRIP_TOP := 528.0
const BG_STRIP_BOTTOM := 563.0

var _background_root: Control
var _bg: TextureRect
var _root: Control
var _overlay: Control = null
var _map_picker: Control = null

var _menu_margin: MarginContainer
var _menu_row: BoxContainer
var _menu_left: VBoxContainer
var _menu_spacer: Control
var _logo_wrap: Control
var _logo: TextureRect
var _menu_panel_wrap: Control
var _menu_panel: Control
var _menu_scroll: ScrollContainer
var _menu_actions: AspectRatioContainer
var _card: Control
var _card_bg: TextureRect
var _play_wrap: Control = null
var _play_ribbon: Panel = null
var _menu_buttons: Array[Button] = []

var _profile_margin: MarginContainer
var _profile_bar: PanelContainer
var _profile_name_label: Label
var _profile_color_dot: Panel
var _profile_color_label: Label
var _profile_score_label: Label
var _profile_star: Panel
var _profile_separators: Array[Panel] = []

var _solo: Dictionary = {}
var _solo_mode_btn: Button
var _solo_map_btn: Button
var _solo_bots_label: Label
var _solo_team_btn: Button

var _ambient_enabled := true
var _intro_finished := false
var _ambient_tweens: Array[Tween] = []


func _ready() -> void:
	_build_background()
	_build_ui()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()
	_apply_quality()
	SaveManager.profile_changed.connect(_refresh_profile)
	SettingsManager.settings_changed.connect(_on_setting_changed)
	_start_intro()


# ---------------------------------------------------------------------------
# 2D background

func _build_background() -> void:
	_background_root = Control.new()
	_background_root.name = "MenuBackground"
	_background_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background_root)

	# Solid sky colour behind KEEP_ASPECT_COVERED avoids any transparent edge
	# on unusual aspect ratios.
	var sky := ColorRect.new()
	sky.color = Cartoon.SKY
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background_root.add_child(sky)

	_bg = TextureRect.new()
	_bg.name = "Artwork"
	_bg.texture = BG_TEXTURE
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_bg.flip_h = GameManager.is_rtl()
	_bg.modulate = Color(1, 1, 1, 0)
	_bg.resized.connect(func() -> void: _bg.pivot_offset = _bg.size * 0.5)
	_background_root.add_child(_bg)


# ---------------------------------------------------------------------------
# UI

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "MenuUI"
	_root.layout_direction = Control.LAYOUT_DIRECTION_RTL if GameManager.is_rtl() else Control.LAYOUT_DIRECTION_LTR
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_menu_margin = MarginContainer.new()
	_menu_margin.name = "MenuMargin"
	_menu_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_menu_margin)

	_menu_row = BoxContainer.new()
	_menu_row.name = "MenuRow"
	_menu_row.add_theme_constant_override("separation", 26)
	_menu_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_margin.add_child(_menu_row)

	_build_brand_column()
	_build_menu_panel()
	_build_profile_bar()


func _build_brand_column() -> void:
	_menu_left = UIKit.vbox(0)
	_menu_left.name = "BrandColumn"
	_menu_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_menu_row.add_child(_menu_left)

	_logo_wrap = Control.new()
	_logo_wrap.name = "LogoWrap"
	_logo_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_logo_wrap.custom_minimum_size = Vector2(0, 240)
	_menu_left.add_child(_logo_wrap)

	_logo = TextureRect.new()
	_logo.name = "Logo"
	_logo.texture = LOGO_TEXTURE
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.rotation = -0.026
	_logo.resized.connect(func() -> void: _logo.pivot_offset = _logo.size * 0.5)
	_logo_wrap.add_child(_logo)

	_menu_spacer = UIKit.spacer()
	_menu_spacer.name = "BrandSpacer"
	_menu_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_menu_left.add_child(_menu_spacer)


func _build_menu_panel() -> void:
	_menu_panel_wrap = Control.new()
	_menu_panel_wrap.name = "MenuPanelWrap"
	_menu_panel_wrap.custom_minimum_size = Vector2(440, 0)
	_menu_panel_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_menu_panel_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_panel_wrap.resized.connect(func() -> void: _menu_panel_wrap.pivot_offset = _menu_panel_wrap.size * 0.5)
	_menu_row.add_child(_menu_panel_wrap)

	_menu_panel = Control.new()
	_menu_panel.name = "MenuPanel"
	_menu_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_menu_panel_wrap.add_child(_menu_panel)

	_menu_scroll = ScrollContainer.new()
	_menu_scroll.name = "MenuScroll"
	_menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_menu_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_menu_scroll.scroll_deadzone = 10
	_menu_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_menu_scroll.resized.connect(_fit_menu_actions_height)
	_menu_panel.add_child(_menu_scroll)

	_menu_actions = AspectRatioContainer.new()
	_menu_actions.name = "CardAspect"
	_menu_actions.ratio = 497.0 / 612.0
	_menu_actions.stretch_mode = AspectRatioContainer.STRETCH_FIT
	_menu_actions.alignment_horizontal = AspectRatioContainer.ALIGNMENT_CENTER
	_menu_actions.alignment_vertical = AspectRatioContainer.ALIGNMENT_CENTER
	_menu_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_actions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_menu_scroll.add_child(_menu_actions)

	_card = Control.new()
	_card.name = "Card"
	_menu_actions.add_child(_card)

	_card_bg = TextureRect.new()
	_card_bg.name = "CardBackground"
	_card_bg.texture = BTNS_BG_TEXTURE
	_card_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_card_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_card_bg)

	_menu_buttons.clear()

	var button_defs := [
		{
			"key": "play",
			"primary": true,
			"icon": "res://assets/icons/play.svg",
			"x0": 50.0,
			"y0": 44.0,
			"w": 397.0,
			"h": 129.0,
			"action": _open_mode_select
		},
		{
			"key": "multiplayer",
			"primary": false,
			"icon": "res://assets/icons/group.svg",
			"x0": 66.0,
			"y0": 175.0,
			"w": 364.0,
			"h": 70.0,
			"action": func() -> void: GameManager.go_to_lobby()
		},
		{
			"key": "tutorial_title",
			"primary": false,
			"icon": "res://assets/icons/tutorial.svg",
			"x0": 68.0,
			"y0": 246.0,
			"w": 362.0,
			"h": 66.0,
			"action": func() -> void: GameManager.start_tutorial()
		},
		{
			"key": "practice",
			"primary": false,
			"icon": "res://assets/icons/practice.svg",
			"x0": 70.0,
			"y0": 314.0,
			"w": 356.0,
			"h": 62.0,
			"action": func() -> void: GameManager.start_practice()
		},
		{
			"key": "customize",
			"primary": false,
			"icon": "res://assets/icons/customize.svg",
			"x0": 70.0,
			"y0": 378.0,
			"w": 356.0,
			"h": 58.0,
			"action": _open_customize
		},
		{
			"key": "settings",
			"primary": false,
			"icon": "res://assets/icons/settings.svg",
			"x0": 70.0,
			"y0": 437.0,
			"w": 357.0,
			"h": 65.0,
			"action": _open_settings
		},
		{
			"key": "how_to_play",
			"primary": false,
			"icon": "res://assets/icons/book.svg",
			"x0": 67.0,
			"y0": 503.0,
			"w": 363.0,
			"h": 67.0,
			"action": func() -> void: _open_text_panel(GameManager.t("how_to_play"), GameManager.t("how_to_text"))
		}
	]

	for def in button_defs:
		var btn := _create_texture_button(def)
		_card.add_child(btn)
		_menu_buttons.append(btn)

	for i in range(_menu_buttons.size()):
		var b := _menu_buttons[i]
		if i > 0:
			b.focus_neighbor_top = _menu_buttons[i - 1].get_path()
		if i < _menu_buttons.size() - 1:
			b.focus_neighbor_bottom = _menu_buttons[i + 1].get_path()
		b.focus_neighbor_left = b.get_path()
		b.focus_neighbor_right = b.get_path()


func _button_texture_style(primary: bool, state: int) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = PRIMARY_BTN_TEX if primary else SECONDARY_BTN_TEX
	if not primary:
		sb.region_rect = SECONDARY_BTN_REGION
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	match state:
		1:
			sb.modulate_color = Color(1.06, 1.06, 1.06, 1.0)
		2:
			sb.modulate_color = Color(0.9, 0.9, 0.9, 1.0)
		3:
			sb.modulate_color = Color(0.8, 0.8, 0.8, 0.55)
		_:
			sb.modulate_color = Color.WHITE
	return sb


func _create_texture_button(def: Dictionary) -> Button:
	var key := str(def["key"])
	var primary := bool(def.get("primary", false))
	var on_pressed: Callable = def["action"]
	var x0 := float(def["x0"])
	var y0 := float(def["y0"])
	var w := float(def["w"])
	var h := float(def["h"])

	var b := Button.new()
	b.name = key.capitalize().replace(" ", "") + "Button"
	b.text = GameManager.t(key)
	b.tooltip_text = GameManager.t(key)
	b.accessibility_name = GameManager.t(key)
	b.set_meta("i18n_key", key)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.focus_mode = Control.FOCUS_NONE if SettingsManager.is_mobile() else Control.FOCUS_ALL
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Theme the built-in Button content (text + icon) instead of stacking a
	# TextureRect over it, so the label stays crisp and localisation-safe.
	b.add_theme_font_override("font", BRAND_FONT)
	b.add_theme_font_size_override("font_size", 46 if primary else 26)
	b.add_theme_constant_override("outline_size", 0)
	b.add_theme_constant_override("h_separation", 10)
	for color_name in [
		"font_color",
		"font_hover_color",
		"font_pressed_color",
		"font_focus_color",
		"font_disabled_color"
	]:
		b.add_theme_color_override(color_name, Cartoon.INK)
	b.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.35))

	b.add_theme_stylebox_override("normal", _button_texture_style(primary, 0))
	b.add_theme_stylebox_override("hover", _button_texture_style(primary, 1))
	b.add_theme_stylebox_override("pressed", _button_texture_style(primary, 2))
	b.add_theme_stylebox_override("disabled", _button_texture_style(primary, 3))
	var focus_box := Cartoon.stylebox(
		Color(0, 0, 0, 0),
		22,
		Cartoon.PINK if primary else Cartoon.YELLOW,
		3,
		6
	)
	focus_box.expand_margin_left = 2
	focus_box.expand_margin_top = 2
	focus_box.expand_margin_right = 2
	focus_box.expand_margin_bottom = 2
	b.add_theme_stylebox_override("focus", focus_box)

	var icon_path := str(def.get("icon", ""))
	if icon_path != "" and ResourceLoader.exists(icon_path):
		b.icon = load(icon_path) as Texture2D
		b.add_theme_constant_override("icon_max_width", 42 if primary else 28)
		for icon_color_name in [
			"icon_normal_color",
			"icon_hover_color",
			"icon_pressed_color",
			"icon_focus_color",
			"icon_disabled_color"
		]:
			b.add_theme_color_override(icon_color_name, Cartoon.INK)

	# Proportional placement inside the card (497 x 612 reference canvas)
	# matching the card artwork's button slots.
	b.anchor_left = x0 / 497.0
	b.anchor_right = (x0 + w) / 497.0
	b.anchor_top = y0 / 612.0
	b.anchor_bottom = (y0 + h) / 612.0
	b.offset_left = 0
	b.offset_top = 0
	b.offset_right = 0
	b.offset_bottom = 0

	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	b.mouse_entered.connect(func() -> void: _hover_button(b, true))
	b.mouse_exited.connect(func() -> void: _hover_button(b, false))
	b.focus_entered.connect(func() -> void: _hover_button(b, true))
	b.focus_exited.connect(func() -> void: _hover_button(b, false))
	b.button_down.connect(func() -> void: _squash_button(b))
	b.button_up.connect(func() -> void: _unsquash_button(b))
	b.pressed.connect(func() -> void: AudioManager.click())
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)

	return b


func _hover_button(b: Button, on: bool) -> void:
	if not is_instance_valid(b) or not b.is_inside_tree():
		return
	var previous = b.get_meta("hover_tween") if b.has_meta("hover_tween") else null
	if previous is Tween and previous.is_valid():
		previous.kill()
	var target := Vector2.ONE * (1.04 if on else 1.0)
	var target_rot := -0.012 if on else 0.0
	var tw := b.create_tween().set_parallel(true)
	b.set_meta("hover_tween", tw)
	tw.tween_property(b, "scale", target, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "rotation", target_rot, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _squash_button(b: Button) -> void:
	if not is_instance_valid(b) or not b.is_inside_tree():
		return
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector2(1.05, 0.93), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _unsquash_button(b: Button) -> void:
	if not is_instance_valid(b) or not b.is_inside_tree():
		return
	var target := Vector2.ONE * (1.04 if (b.is_hovered() or b.has_focus()) else 1.0)
	var tw := b.create_tween()
	tw.tween_property(b, "scale", target, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build_profile_bar() -> void:
	_profile_margin = MarginContainer.new()
	_profile_margin.name = "ProfileMargin"
	_profile_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_profile_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_profile_margin)

	# Opaque on purpose: it hides the artwork's baked-in strip completely.
	_profile_bar = Cartoon.panel(Color("#120a24"), 24, 8, Cartoon.YELLOW, 3, 9, Color(0.02, 0.0, 0.06, 0.55), Vector2(0, 5))
	_profile_bar.name = "ProfileBar"
	_profile_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	_profile_bar.resized.connect(func() -> void: _profile_bar.pivot_offset = Vector2(_profile_bar.size.x * 0.5, _profile_bar.size.y))
	_profile_margin.add_child(_profile_bar)

	var row := UIKit.hbox(6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_profile_bar.add_child(row)

	# Three equal sections: name / colour / score. Each grows by the same ratio
	# so the bar stays balanced in both LTR and RTL layouts.
	var name_section := UIKit.hbox(0)
	name_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_section.size_flags_stretch_ratio = 1.0
	name_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_profile_name_label = Cartoon.label("", 19, Cartoon.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	_profile_name_label.name = "ProfileName"
	_profile_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_profile_name_label.clip_text = true
	_profile_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_section.add_child(_profile_name_label)
	row.add_child(name_section)

	var name_separator := _vertical_separator()
	_profile_separators.append(name_separator)
	row.add_child(name_separator)

	var color_section := UIKit.hbox(7)
	color_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_section.size_flags_stretch_ratio = 1.0
	color_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_profile_color_dot = Panel.new()
	_profile_color_dot.name = "ColorDot"
	_profile_color_dot.custom_minimum_size = Vector2(20, 20)
	_profile_color_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_profile_color_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	color_section.add_child(_profile_color_dot)
	_profile_color_label = Cartoon.label("", 19, Cartoon.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	_profile_color_label.name = "ProfileColor"
	_profile_color_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_profile_color_label.clip_text = true
	_profile_color_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	color_section.add_child(_profile_color_label)
	row.add_child(color_section)

	var color_separator := _vertical_separator()
	_profile_separators.append(color_separator)
	row.add_child(color_separator)

	var score_section := UIKit.hbox(7)
	score_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_section.size_flags_stretch_ratio = 1.0
	score_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_profile_star = _star_diamond()
	score_section.add_child(_profile_star)
	_profile_score_label = Cartoon.label("", 19, Cartoon.YELLOW, HORIZONTAL_ALIGNMENT_LEFT)
	_profile_score_label.name = "ProfileScore"
	_profile_score_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_profile_score_label.clip_text = true
	_profile_score_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	score_section.add_child(_profile_score_label)
	row.add_child(score_section)
	_refresh_profile()


func _vertical_separator() -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(2, 22)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", Cartoon.stylebox(Color(1, 1, 1, 0.2), 1, Color(0, 0, 0, 0), 0, 0))
	return p


func _star_diamond() -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(14, 14)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.rotation = PI * 0.25
	p.pivot_offset = Vector2(7, 7)
	p.add_theme_stylebox_override("panel", Cartoon.stylebox(Cartoon.YELLOW, 3, Cartoon.PURPLE_DARK, 2, 0))
	return p


func _add_rivet(parent: Control, anchor_x: float, anchor_y: float, x: float, y: float) -> void:
	var r := Panel.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_left = anchor_x
	r.anchor_right = anchor_x
	r.anchor_top = anchor_y
	r.anchor_bottom = anchor_y
	r.offset_left = x
	r.offset_top = y
	r.offset_right = x + 18
	r.offset_bottom = y + 18
	r.add_theme_stylebox_override("panel", Cartoon.stylebox(Cartoon.YELLOW, 9, Cartoon.PURPLE_DARK, 3, 0, 2, Color(0.05, 0.01, 0.12, 0.35), Vector2(0, 2)))
	parent.add_child(r)


func _on_viewport_resized() -> void:
	if _menu_row == null or not is_instance_valid(_menu_row):
		return
	var view := get_viewport().get_visible_rect().size
	var safe := UIKit.safe_insets(get_viewport())
	var portrait := view.y > view.x * 1.15
	var compact := view.x < 900.0 or view.y < 640.0 or portrait
	_menu_row.vertical = compact
	_menu_row.add_theme_constant_override("separation", 12 if compact else 24)
	_menu_left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN if compact else Control.SIZE_EXPAND_FILL
	_menu_spacer.size_flags_vertical = Control.SIZE_SHRINK_BEGIN if compact else Control.SIZE_EXPAND_FILL

	_logo_wrap.custom_minimum_size.y = clampf(view.y * (0.18 if compact else 0.36), 88.0, 240.0 if compact else 350.0)
	if compact:
		var outer := float(int(safe.x + safe.z)) + OUTER_MARGIN_COMPACT * 2.0
		var card_w := minf(maxf(280.0, view.x - outer), 500.0)
		var card_h := clampf(view.y * 0.52, 280.0, 600.0)
		_menu_panel_wrap.custom_minimum_size = Vector2(card_w, card_h)
		_menu_panel_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_menu_panel_wrap.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	else:
		var outer_v := float(int(safe.y + safe.w)) + PROFILE_BAR_WIDE_HEIGHT + 36.0
		var avail_h := maxf(380.0, view.y - outer_v)
		var panel_w := clampf(avail_h * (497.0 / 612.0), 380.0, 560.0)
		_menu_panel_wrap.custom_minimum_size = Vector2(panel_w, 0)
		_menu_panel_wrap.size_flags_horizontal = Control.SIZE_FILL
		_menu_panel_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL

	if _play_wrap != null:
		_play_wrap.custom_minimum_size.y = 86.0 if compact else 98.0
	if _play_ribbon != null:
		_play_ribbon.offset_top = 8 if compact else 10
		_play_ribbon.offset_bottom = -8 if compact else -10

	for button in _menu_buttons:
		button.pivot_offset = button.size * 0.5

	_layout_profile_bar(view, compact)
	_fit_menu_actions_height.call_deferred()


## Makes the action stack fill the panel when it fits (so the buttons stay
## vertically centred) and keep its natural height when it needs to scroll.
func _fit_menu_actions_height() -> void:
	if _menu_scroll == null or _menu_actions == null:
		return
	if not is_instance_valid(_menu_scroll) or not is_instance_valid(_menu_actions):
		return
	var available := floorf(_menu_scroll.size.y)
	if available <= 0.0:
		return
	var view := get_viewport().get_visible_rect().size
	var portrait := view.y > view.x * 1.15
	var compact := view.x < 900.0 or view.y < 640.0 or portrait
	var min_h := 360.0 if compact else 440.0
	_menu_actions.custom_minimum_size.y = maxf(available, min_h)


func _layout_profile_bar(view: Vector2, compact: bool) -> void:
	var safe := UIKit.safe_insets(get_viewport())
	var outer := OUTER_MARGIN_COMPACT if compact else OUTER_MARGIN_WIDE
	var gap := 8.0 if compact else 12.0
	# The bar is flush with the bottom edge: the artwork has a yellow band
	# below its baked strip that would otherwise peek out under the bar.
	var bar_bottom := view.y

	# Map the artwork's baked-in strip (image space) to screen space using the
	# same KEEP_ASPECT_COVERED transform as the TextureRect, then size the bar
	# so it always covers the strip. On very wide windows the strip is cropped
	# below the screen and the natural height is used.
	var cover_scale := maxf(view.x / BG_ART_SIZE.x, view.y / BG_ART_SIZE.y)
	var art_offset_y := (view.y - BG_ART_SIZE.y * cover_scale) * 0.5
	var strip_top := art_offset_y + BG_STRIP_TOP * cover_scale
	var base_height := PROFILE_BAR_COMPACT_HEIGHT if compact else PROFILE_BAR_WIDE_HEIGHT
	var bar_height := maxf(base_height, bar_bottom - strip_top + 4.0)
	bar_height = minf(bar_height, view.y * 0.24)

	# Scale the bar's own artwork and text with its height so it never looks
	# empty on tall portrait screens.
	var radius := int(clampf(bar_height * 0.34, 14.0, 40.0))
	var pad_v := int(clampf(bar_height * 0.10, 4.0, 18.0))
	var pad_h := int(clampf(bar_height * 0.16, 8.0, 26.0))
	# The artwork was cropped to 16:9. On narrower screens its baked strip
	# reaches past the left edge, so bleed the bar's rounded edge off-screen on
	# the artwork side and keep the text at a comfortable inset.
	var edge_bleed := float(radius)
	var lead_pad := pad_h
	var tail_pad := pad_h
	if compact:
		lead_pad = int(edge_bleed + OUTER_MARGIN_COMPACT)
		tail_pad = lead_pad
	elif GameManager.is_rtl():
		tail_pad = int(edge_bleed + OUTER_MARGIN_WIDE)
	else:
		lead_pad = int(edge_bleed + OUTER_MARGIN_WIDE)
	var sb := Cartoon.stylebox(Color("#120a24"), radius, Cartoon.YELLOW, 3, pad_h, 9, Color(0.02, 0.0, 0.06, 0.55), Vector2(0, 5))
	sb.content_margin_left = lead_pad
	sb.content_margin_right = tail_pad
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v + int(safe.w)
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	_profile_bar.add_theme_stylebox_override("panel", sb)

	var text_size := int(clampf(bar_height * 0.34, 14.0, 34.0))
	var dot_size := int(clampf(bar_height * 0.34, 14.0, 34.0))
	var separator_height := int(clampf(bar_height * 0.48, 18.0, 46.0))
	var star_size := int(clampf(bar_height * 0.24, 10.0, 24.0))
	_profile_name_label.add_theme_font_size_override("font_size", text_size)
	_profile_color_label.add_theme_font_size_override("font_size", text_size)
	_profile_score_label.add_theme_font_size_override("font_size", text_size)
	_profile_color_dot.custom_minimum_size = Vector2(dot_size, dot_size)
	_profile_color_dot.add_theme_stylebox_override("panel", Cartoon.stylebox(GameConstants.get_color(SaveManager.color_index), int(dot_size * 0.5), Cartoon.PURPLE_DARK, 2, 0))
	for separator in _profile_separators:
		separator.custom_minimum_size = Vector2(2, separator_height)
	if _profile_star != null:
		_profile_star.custom_minimum_size = Vector2(star_size, star_size)
		_profile_star.pivot_offset = Vector2(star_size, star_size) * 0.5

	_menu_margin.add_theme_constant_override("margin_left", int(safe.x + outer))
	_menu_margin.add_theme_constant_override("margin_top", int(safe.y + outer))
	_menu_margin.add_theme_constant_override("margin_right", int(safe.z + outer))
	_menu_margin.add_theme_constant_override("margin_bottom", int(view.y - bar_bottom + bar_height + gap))

	_profile_margin.add_theme_constant_override("margin_top", int(maxf(0.0, bar_bottom - bar_height)))
	_profile_margin.add_theme_constant_override("margin_bottom", int(view.y - bar_bottom))
	if compact:
		_profile_margin.add_theme_constant_override("margin_left", int(safe.x - edge_bleed))
		_profile_margin.add_theme_constant_override("margin_right", int(safe.z - edge_bleed))
	elif GameManager.is_rtl():
		# The background is mirrored in Arabic, so the profile strip moves to
		# the bottom-right to cover the artwork's baked-in strip.
		_profile_margin.add_theme_constant_override("margin_left", int(safe.x + view.x * 0.24))
		_profile_margin.add_theme_constant_override("margin_right", int(safe.z - edge_bleed))
	else:
		_profile_margin.add_theme_constant_override("margin_left", int(safe.x - edge_bleed))
		_profile_margin.add_theme_constant_override("margin_right", int(safe.z + view.x * 0.24))


# ---------------------------------------------------------------------------
# Profile / localisation / quality

func _refresh_profile() -> void:
	if _profile_name_label == null:
		return
	_profile_name_label.text = "%s: %s" % [GameManager.t("name"), SaveManager.player_name]
	_profile_color_label.text = GameConstants.get_color_name(SaveManager.color_index)
	_profile_score_label.text = "%s: %d" % [GameManager.t("score"), SaveManager.rounds_won]
	var color := GameConstants.get_color(SaveManager.color_index)
	var dot_radius := int(maxf(4.0, _profile_color_dot.custom_minimum_size.x * 0.5))
	_profile_color_dot.add_theme_stylebox_override("panel", Cartoon.stylebox(color, dot_radius, Cartoon.PURPLE_DARK, 2, 0))
	if _intro_finished:
		_pop_profile_bar()


func _pop_profile_bar() -> void:
	if not is_instance_valid(_profile_bar) or not _profile_bar.is_inside_tree():
		return
	var tw := create_tween()
	tw.tween_property(_profile_bar, "scale", Vector2(1.03, 1.03), 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_profile_bar, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "graphics_preset":
		_apply_quality()
	elif key == "language":
		_refresh_texts()


func _refresh_texts() -> void:
	if _root == null:
		return
	_root.layout_direction = Control.LAYOUT_DIRECTION_RTL if GameManager.is_rtl() else Control.LAYOUT_DIRECTION_LTR
	if _bg != null:
		_bg.flip_h = GameManager.is_rtl()
	for button in _menu_buttons:
		var key := str(button.get_meta("i18n_key", ""))
		if key == "":
			continue
		var text := GameManager.t(key)
		button.text = text
		button.tooltip_text = text
		button.accessibility_name = text
	_refresh_profile()
	call_deferred("_on_viewport_resized")


func _apply_quality() -> void:
	_ambient_enabled = int(SettingsManager.get_setting("graphics_preset")) != SettingsManager.PRESET_LOW
	_stop_ambient()
	if _ambient_enabled:
		if _intro_finished:
			_start_ambient()
	else:
		if _bg != null:
			_bg.scale = Vector2.ONE
		if _logo != null:
			_logo.rotation = -0.026
			_logo.scale = Vector2.ONE
		if _play_ribbon != null:
			_play_ribbon.rotation = -0.035
		if _menu_buttons.size() > 0:
			_menu_buttons[0].scale = Vector2.ONE


# ---------------------------------------------------------------------------
# Animation

func _start_intro() -> void:
	if _bg != null:
		_bg.modulate.a = 0.0

	_logo.modulate.a = 0.0
	_logo.scale = Vector2(0.72, 0.72)
	_logo.rotation = -0.09

	_menu_panel_wrap.modulate.a = 0.0
	_menu_panel_wrap.scale = Vector2(0.94, 0.94)
	_menu_panel_wrap.rotation = 0.015

	if _play_ribbon != null:
		_play_ribbon.modulate.a = 0.0
		_play_ribbon.scale = Vector2(0.9, 0.9)

	_profile_bar.modulate.a = 0.0
	_profile_bar.scale = Vector2(0.92, 0.7)

	for button in _menu_buttons:
		button.modulate.a = 0.0
		button.scale = Vector2(0.86, 0.86)

	var tw := create_tween().set_parallel(true)
	if _bg != null:
		tw.tween_property(_bg, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_logo, "modulate:a", 1.0, 0.3).set_delay(0.06)
	tw.tween_property(_logo, "scale", Vector2.ONE, 0.75).set_delay(0.06).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_logo, "rotation", -0.026, 0.6).set_delay(0.06).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_menu_panel_wrap, "modulate:a", 1.0, 0.3).set_delay(0.1)
	tw.tween_property(_menu_panel_wrap, "scale", Vector2.ONE, 0.6).set_delay(0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_menu_panel_wrap, "rotation", 0.0, 0.55).set_delay(0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _play_ribbon != null:
		tw.tween_property(_play_ribbon, "modulate:a", 1.0, 0.25).set_delay(0.2)
		tw.tween_property(_play_ribbon, "scale", Vector2.ONE, 0.5).set_delay(0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_profile_bar, "modulate:a", 1.0, 0.3).set_delay(0.24)
	tw.tween_property(_profile_bar, "scale", Vector2.ONE, 0.55).set_delay(0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	for i in _menu_buttons.size():
		var button := _menu_buttons[i]
		var delay := 0.18 + i * 0.045
		tw.tween_property(button, "modulate:a", 1.0, 0.2).set_delay(delay)
		tw.tween_property(button, "scale", Vector2.ONE, 0.42).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var total := 0.18 + _menu_buttons.size() * 0.045 + 0.55
	var end_tw := create_tween()
	end_tw.tween_interval(total)
	end_tw.tween_callback(func() -> void:
		_intro_finished = true
		if _ambient_enabled:
			_start_ambient()
	)


func _start_ambient() -> void:
	if not _ambient_enabled or not _intro_finished:
		return
	_stop_ambient()
	if _bg != null:
		var drift := create_tween().set_loops()
		drift.tween_property(_bg, "scale", Vector2(1.02, 1.02), 9.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		drift.tween_property(_bg, "scale", Vector2.ONE, 9.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_ambient_tweens.append(drift)
	if _logo != null:
		var float_tw := create_tween().set_loops()
		float_tw.tween_property(_logo, "rotation", -0.010, 2.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		float_tw.tween_property(_logo, "rotation", -0.026, 2.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_ambient_tweens.append(float_tw)
		var breathe := create_tween().set_loops()
		breathe.tween_property(_logo, "scale", Vector2(1.012, 1.012), 2.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		breathe.tween_property(_logo, "scale", Vector2.ONE, 2.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_ambient_tweens.append(breathe)
	if _play_ribbon != null:
		var sway := create_tween().set_loops()
		sway.tween_property(_play_ribbon, "rotation", -0.012, 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		sway.tween_property(_play_ribbon, "rotation", -0.05, 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_ambient_tweens.append(sway)
	elif _menu_buttons.size() > 0:
		var play_btn := _menu_buttons[0]
		var pulse := create_tween().set_loops()
		pulse.tween_property(play_btn, "scale", Vector2(1.025, 1.025), 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		pulse.tween_property(play_btn, "scale", Vector2.ONE, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_ambient_tweens.append(pulse)


func _stop_ambient() -> void:
	for tw in _ambient_tweens:
		if tw is Tween and tw.is_valid():
			tw.kill()
	_ambient_tweens.clear()


# ---------------------------------------------------------------------------
# Overlays

func _close_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null


func _open_mode_select() -> void:
	if _overlay != null:
		return
	_solo = GameManager.default_cfg()
	_solo["bots"] = 3
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_overlay)
	UIKit.dim_background(_overlay, Color(0.03, 0.01, 0.08, 0.72))
	var panel := Cartoon.overlay_panel()
	var mode_scroll := ScrollContainer.new()
	mode_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mode_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := UIKit.vbox(10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(Cartoon.title(GameManager.t("solo_title"), 36))
	_solo_mode_btn = Cartoon.button("", _solo_cycle_mode, Cartoon.STYLE_NORMAL, Vector2(0, 54))
	_solo_mode_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_solo_mode_btn)
	_solo_map_btn = Cartoon.button("", _solo_cycle_map, Cartoon.STYLE_NORMAL, Vector2(0, 54))
	_solo_map_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_solo_map_btn)
	var bots_row := UIKit.hbox(10)
	bots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bots_row.add_child(Cartoon.button("-", func() -> void: _solo_bots(-1), Cartoon.STYLE_NORMAL, Vector2(54, 54)))
	_solo_bots_label = Cartoon.label("", 24, Cartoon.WHITE)
	_solo_bots_label.custom_minimum_size = Vector2(110, 0)
	bots_row.add_child(_solo_bots_label)
	bots_row.add_child(Cartoon.button("+", func() -> void: _solo_bots(1), Cartoon.STYLE_NORMAL, Vector2(54, 54)))
	box.add_child(bots_row)
	_solo_team_btn = Cartoon.button("", _solo_cycle_team, Cartoon.STYLE_NORMAL, Vector2(0, 54))
	_solo_team_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_solo_team_btn)
	var start_button := Cartoon.button(GameManager.t("start"), _solo_start, Cartoon.STYLE_PRIMARY, Vector2(0, 66))
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(start_button)
	var row := UIKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var multi_button := Cartoon.button(GameManager.t("multiplayer"), func() -> void: GameManager.go_to_lobby(), Cartoon.STYLE_NORMAL, Vector2(0, 52))
	multi_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var back_button := Cartoon.button(GameManager.t("back"), _close_overlay, Cartoon.STYLE_NORMAL, Vector2(0, 52))
	back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(multi_button)
	row.add_child(back_button)
	box.add_child(row)
	mode_scroll.add_child(box)
	panel.add_child(mode_scroll)
	_overlay.add_child(UIKit.centered(panel, Vector2(600, 600)))
	_solo_refresh()


func _solo_refresh() -> void:
	var mode := int(_solo["mode"])
	var mode_keys := ["mode_ffa", "mode_teams", "mode_hide", "mode_ko", "mode_trampoline"]
	_solo_mode_btn.text = "%s: %s" % [GameManager.t("mode"), GameManager.t(mode_keys[mode])]
	var m := int(_solo["map"])
	_solo_map_btn.text = "%s: %s (%s)" % [GameManager.t("map"), GameManager.t(GameConstants.MAPS[m]["key"]), GameManager.t(GameConstants.MAPS[m]["size_key"])]
	_solo_bots_label.text = "%s %d" % [GameManager.t("bots"), int(_solo["bots"])]
	_solo_team_btn.visible = GameConstants.uses_teams(mode)
	if mode == GameConstants.MODE_HIDE:
		_solo_team_btn.text = "%s: %s" % [GameManager.t("your_role"), GameManager.t("hs_hider") if int(_solo["solo_team"]) == 0 else GameManager.t("hs_seeker")]
	else:
		_solo_team_btn.text = "%s: %s" % [GameManager.t("your_team"), GameManager.team_name(int(_solo["solo_team"]))]


func _solo_cycle_mode() -> void:
	var mode := (int(_solo["mode"]) + 1) % GameConstants.MODE_COUNT
	_solo["mode"] = mode
	_solo["map"] = int(GameConstants.maps_for_mode(mode)[0])
	_solo["round_time"] = GameConstants.default_round_time(mode)
	_solo["solo_team"] = 0
	if mode != GameConstants.MODE_FFA and int(_solo["bots"]) < 1:
		_solo["bots"] = 3
	_solo_refresh()


func _solo_cycle_map() -> void:
	# Opens the picture picker instead of cycling through the maps one by one.
	if _map_picker != null and is_instance_valid(_map_picker):
		return
	var maps: Array = GameConstants.maps_for_mode(int(_solo["mode"]))
	_map_picker = MapPickerScript.new()
	_map_picker.setup(maps, int(_solo["map"]))
	_root.add_child(_map_picker)
	_map_picker.picked.connect(func(map_id: int) -> void:
		_solo["map"] = map_id
		_solo_refresh()
	)
	_map_picker.closed.connect(func() -> void: _map_picker = null)


func _solo_bots(delta: int) -> void:
	var lo := 0 if int(_solo["mode"]) == GameConstants.MODE_FFA else 1
	_solo["bots"] = clampi(int(_solo["bots"]) + delta, lo, GameConstants.MAX_TOTAL - 1)
	_solo_refresh()


func _solo_cycle_team() -> void:
	var limit := 2
	_solo["solo_team"] = (int(_solo["solo_team"]) + 1) % limit
	_solo_refresh()


func _solo_start() -> void:
	# Free-for-all keeps the original respawning practice rules; the other modes are real elimination rounds.
	GameManager.start_solo(_solo, int(_solo["mode"]) == GameConstants.MODE_FFA)


func _open_text_panel(title_text: String, body_text: String) -> void:
	if _overlay != null:
		return
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_overlay)
	UIKit.dim_background(_overlay, Color(0.03, 0.01, 0.08, 0.72))
	var panel := Cartoon.overlay_panel()
	var box := UIKit.vbox(12)
	var header := UIKit.hbox(10)
	header.add_child(Cartoon.title(title_text, 38))
	header.add_child(UIKit.spacer())
	header.add_child(Cartoon.button(GameManager.t("close"), _close_overlay, Cartoon.STYLE_PRIMARY, Vector2(160, 54)))
	box.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var body := Cartoon.wrapped_label(body_text, 20)
	body.custom_minimum_size = Vector2(0, 0)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	box.add_child(scroll)
	panel.add_child(box)
	_overlay.add_child(UIKit.centered(panel, Vector2(820, 560)))


func _open_settings() -> void:
	if _overlay != null:
		return
	_overlay = SettingsScene.instantiate()
	_root.add_child(_overlay)
	_overlay.closed.connect(_close_overlay)


func _open_customize() -> void:
	if _overlay != null:
		return
	_overlay = CustomScene.instantiate()
	_root.add_child(_overlay)
	_overlay.closed.connect(_close_overlay)
