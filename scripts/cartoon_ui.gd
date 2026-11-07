extends RefCounted
## Playful cartoon UI theme for the NewAssets visual identity.
##
## The main menu uses the supplied background/logo artwork directly, while the
## controls are built as real Godot controls with this Theme so labels can be
## localised (English + Arabic), profile data stays live, and every action has
## proper hover/focus/press feedback. Palette and shapes follow
## NewAssets/mainMenu/menu_prototype.png.
##
## Usage: const Cartoon := preload("res://scripts/cartoon_ui.gd")

const FONT_PATH := "res://assets/fonts/game_font.tres"

# Shared cartoon button art. Primary actions use the yellow/ribbon pill,
# everything else uses the pink pill. Both are drawn as 9-patch styleboxes so
# they keep their hand-drawn edges at every button size.
const PRIMARY_BTN_TEX := preload("res://NewAssets/mainMenu/PrimaryBtnTexture.png")
const SECONDARY_BTN_TEX := preload("res://NewAssets/mainMenu/SecondaryBtnTexture.png")
const SECONDARY_BTN_REGION := Rect2(15, 31, 365, 71)

const STYLE_PRIMARY := 0
const STYLE_NORMAL := 1
const STYLE_GHOST := 2
const STYLE_DANGER := 3

# Compatibility with UIKit color references
const COLOR_PRIMARY := Color("#ffc828")
const COLOR_DANGER := Color("#f43f8e")
const COLOR_PANEL := Color("#5b2f9f")
const COLOR_DIM := Color(0.03, 0.05, 0.15, 0.6)
const COLOR_TEXT_DARK := Color("#24113f")

const INK := Color("#24113f")
const INK_SOFT := Color("#3a225f")
const PURPLE_DARK := Color("#2a154d")
const PURPLE := Color("#6b3ab5")
const PURPLE_LIGHT := Color("#8a5bd0")
const PURPLE_PANEL := Color("#5b2f9f")
const PINK := Color("#f43f8e")
const PINK_LIGHT := Color("#ff74ae")
const YELLOW := Color("#ffc828")
const YELLOW_LIGHT := Color("#ffdf63")
const CREAM := Color("#f7e7f8")
const CREAM_HOVER := Color("#fff5ff")
const WHITE := Color("#fffaf3")
const SKY := Color("#42b8f5")

static var _theme: Theme
static var _font: Font


static func font() -> Font:
	if _font == null:
		var base = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null
		# game_font.tres already pairs the Milkyway display face with an
		# emboldened Noto Sans Arabic fallback for digits, punctuation and Arabic.
		_font = base if base is Font else ThemeDB.fallback_font
	return _font


static func stylebox(
	bg: Color,
	radius := 18,
	border := Color(0, 0, 0, 0),
	border_width := 0,
	margin := 12,
	shadow := 0,
	shadow_color := Color(0, 0, 0, 0.24),
	shadow_offset := Vector2(0, 5)
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border_width)
	sb.border_color = border
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	if shadow > 0:
		sb.shadow_color = shadow_color
		sb.shadow_size = shadow
		sb.shadow_offset = shadow_offset
	return sb


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var th := Theme.new()
	th.default_font = font()
	th.default_font_size = 22

	# Default Button look is the pink secondary pill. Primary, ghost and danger
	# buttons override these styles per instance.
	th.set_stylebox("normal", "Button", _button_box(STYLE_NORMAL, false))
	th.set_stylebox("hover", "Button", _button_box(STYLE_NORMAL, true))
	th.set_stylebox("pressed", "Button", _button_box(STYLE_NORMAL, false, true))
	th.set_stylebox("disabled", "Button", _button_box(STYLE_NORMAL, false, false, true))
	var default_focus := stylebox(Color(0, 0, 0, 0), 20, YELLOW, 4, 0)
	default_focus.expand_margin_left = 2
	default_focus.expand_margin_top = 2
	default_focus.expand_margin_right = 2
	default_focus.expand_margin_bottom = 2
	th.set_stylebox("focus", "Button", default_focus)
	th.set_color("font_color", "Button", INK)
	th.set_color("font_hover_color", "Button", INK)
	th.set_color("font_pressed_color", "Button", INK)
	th.set_color("font_focus_color", "Button", INK)
	th.set_color("font_disabled_color", "Button", Color(0.14, 0.06, 0.25, 0.45))
	th.set_font_size("font_size", "Button", 25)
	th.set_constant("outline_size", "Button", 0)
	th.set_constant("h_separation", "Button", 8)
	th.set_color("font_outline_color", "Button", PURPLE_DARK)
	th.set_color("icon_normal_color", "Button", INK)
	th.set_color("icon_hover_color", "Button", INK)
	th.set_color("icon_pressed_color", "Button", INK)
	th.set_color("icon_focus_color", "Button", INK)

	th.set_color("font_color", "Label", WHITE)
	th.set_font_size("font_size", "Label", 22)

	# CheckButton uses the Button styleboxes as a fallback, which would put a
	# full pill behind its small switch. Keep toggles clean: the switch icon is
	# the only visual, like before the texture pass.
	var empty_toggle := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		th.set_stylebox(state, "CheckButton", empty_toggle)
	th.set_color("font_color", "CheckButton", WHITE)
	th.set_color("font_hover_color", "CheckButton", YELLOW_LIGHT)
	th.set_color("font_pressed_color", "CheckButton", YELLOW)
	th.set_color("font_focus_color", "CheckButton", YELLOW_LIGHT)
	th.set_font_size("font_size", "CheckButton", 20)

	th.set_stylebox("panel", "PanelContainer", stylebox(PURPLE_PANEL, 26, PURPLE_DARK, 4, 18, 12, Color(0.05, 0.01, 0.12, 0.4), Vector2(0, 7)))
	th.set_stylebox("panel", "Panel", stylebox(Color(1, 1, 1, 0.14), 14, Color(1, 1, 1, 0.25), 2, 0))

	th.set_stylebox("scroll", "VScrollBar", stylebox(Color(0.08, 0.03, 0.16, 0.4), 6, Color(0, 0, 0, 0), 0, 0))
	th.set_stylebox("grabber", "VScrollBar", stylebox(Color(1, 1, 1, 0.5), 6, Color(0, 0, 0, 0), 0, 0))
	th.set_stylebox("grabber_highlight", "VScrollBar", stylebox(YELLOW, 6, Color(0, 0, 0, 0), 0, 0))
	th.set_stylebox("grabber_pressed", "VScrollBar", stylebox(YELLOW_LIGHT, 6, Color(0, 0, 0, 0), 0, 0))

	_theme = th
	return _theme


static func _button_box(style: int, hover: bool, pressed := false, disabled := false) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	var primary := style == STYLE_PRIMARY
	sb.texture = PRIMARY_BTN_TEX if primary else SECONDARY_BTN_TEX
	if primary:
		# Keep the ribbon ends and the pill's top/bottom edges intact.
		sb.texture_margin_left = 46
		sb.texture_margin_right = 46
		sb.texture_margin_top = 22
		sb.texture_margin_bottom = 22
	else:
		# Trim the transparent padding, then 9-patch the visible pill.
		sb.region_rect = SECONDARY_BTN_REGION
		sb.texture_margin_left = 26
		sb.texture_margin_right = 26
		sb.texture_margin_top = 16
		sb.texture_margin_bottom = 16

	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 4
	sb.content_margin_bottom = 6

	var normal := Color.WHITE
	var hover_tint := Color(1.06, 1.06, 1.06, 1.0)
	var pressed_tint := Color(0.9, 0.9, 0.9, 1.0)
	match style:
		STYLE_GHOST:
			normal = Color(0.42, 0.27, 0.68, 1.0)
			hover_tint = Color(0.55, 0.38, 0.86, 1.0)
			pressed_tint = Color(0.33, 0.2, 0.55, 1.0)
		STYLE_DANGER:
			normal = Color(1.0, 0.48, 0.6, 1.0)
			hover_tint = Color(1.0, 0.62, 0.72, 1.0)
			pressed_tint = Color(0.82, 0.36, 0.48, 1.0)

	if disabled:
		sb.modulate_color = Color(0.62, 0.62, 0.62, 0.55)
	elif pressed:
		sb.modulate_color = pressed_tint
	elif hover:
		sb.modulate_color = hover_tint
	else:
		sb.modulate_color = normal
	return sb


## Tiny square/round controls (icon buttons, +/- steppers) cannot use the wide
## pill art without distorting it, so they get a solid chip in the same palette.
static func _compact_button_box(style: int, hover: bool, pressed := false, disabled := false) -> StyleBoxFlat:
	var fill := Color("#e7c6d8")
	var border := PURPLE_DARK
	match style:
		STYLE_PRIMARY:
			fill = YELLOW
		STYLE_GHOST:
			fill = Color("#4a2f78")
			border = Color(1, 1, 1, 0.35)
		STYLE_DANGER:
			fill = PINK

	if disabled:
		fill = Color(0.35, 0.3, 0.46, 0.55)
	elif pressed:
		fill = fill.darkened(0.12)
	elif hover:
		fill = fill.lightened(0.08)
		if style != STYLE_GHOST:
			border = YELLOW

	return stylebox(fill, 999, border, 3, 6, 4, Color(0.12, 0.03, 0.22, 0.32), Vector2(0, 3))


static func _style_button(b: Button, style: int, compact := false) -> void:
	if compact:
		b.add_theme_stylebox_override("normal", _compact_button_box(style, false))
		b.add_theme_stylebox_override("hover", _compact_button_box(style, true))
		b.add_theme_stylebox_override("pressed", _compact_button_box(style, false, true))
		b.add_theme_stylebox_override("disabled", _compact_button_box(style, false, false, true))
	else:
		b.add_theme_stylebox_override("normal", _button_box(style, false))
		b.add_theme_stylebox_override("hover", _button_box(style, true))
		b.add_theme_stylebox_override("pressed", _button_box(style, false, true))
		b.add_theme_stylebox_override("disabled", _button_box(style, false, false, true))
	var focus_color := PINK if style == STYLE_PRIMARY else YELLOW
	var focus_box := stylebox(Color(0, 0, 0, 0), 20, focus_color, 4, 0)
	focus_box.expand_margin_left = 2
	focus_box.expand_margin_top = 2
	focus_box.expand_margin_right = 2
	focus_box.expand_margin_bottom = 2
	b.add_theme_stylebox_override("focus", focus_box)

	match style:
		STYLE_PRIMARY:
			b.add_theme_color_override("font_color", INK)
			b.add_theme_color_override("font_hover_color", INK)
			b.add_theme_color_override("font_pressed_color", INK)
			b.add_theme_color_override("font_focus_color", INK)
			b.add_theme_color_override("font_disabled_color", Color(INK.r, INK.g, INK.b, 0.45))
			b.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.38))
			b.add_theme_constant_override("outline_size", 2)
			b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.18))
			b.add_theme_constant_override("shadow_offset_x", 0)
			b.add_theme_constant_override("shadow_offset_y", 2)
			b.add_theme_font_size_override("font_size", 38)
			for key in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
				b.add_theme_color_override(key, INK)
		STYLE_GHOST:
			b.add_theme_color_override("font_color", WHITE)
			b.add_theme_color_override("font_hover_color", YELLOW_LIGHT)
			b.add_theme_color_override("font_pressed_color", YELLOW)
			b.add_theme_color_override("font_focus_color", YELLOW_LIGHT)
			b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.4))
			b.add_theme_color_override("font_outline_color", PURPLE_DARK)
			b.add_theme_constant_override("outline_size", 4)
			b.add_theme_font_size_override("font_size", 19)
			for key in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
				b.add_theme_color_override(key, WHITE)
		STYLE_DANGER:
			b.add_theme_color_override("font_color", WHITE)
			b.add_theme_color_override("font_hover_color", WHITE)
			b.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.9))
			b.add_theme_color_override("font_focus_color", WHITE)
			b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.4))
			b.add_theme_color_override("font_outline_color", PURPLE_DARK)
			b.add_theme_constant_override("outline_size", 4)
			b.add_theme_font_size_override("font_size", 24)
			for key in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
				b.add_theme_color_override(key, WHITE)
		_:
			b.add_theme_color_override("font_color", INK)
			b.add_theme_color_override("font_hover_color", INK)
			b.add_theme_color_override("font_pressed_color", INK)
			b.add_theme_color_override("font_focus_color", INK)
			b.add_theme_color_override("font_disabled_color", Color(INK.r, INK.g, INK.b, 0.45))
			b.add_theme_font_size_override("font_size", 25)
			for key in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
				b.add_theme_color_override(key, INK)


## Bouncy, touch-friendly button with hover/focus lift and a squashy press.
static func button(
	text: String,
	on_pressed: Callable = Callable(),
	style := STYLE_NORMAL,
	min_size := Vector2(280, 54)
) -> Button:
	var b := Button.new()
	b.text = text
	b.theme = theme()
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE if SettingsManager.is_mobile() else Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = text
	b.accessibility_name = text
	b.set_meta("cartoon_style", style)
	var compact := min_size.x > 0.0 and min_size.x <= 72.0 and min_size.y <= 72.0
	_style_button(b, style, compact)
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	b.mouse_entered.connect(func() -> void: _hover(b, true))
	b.mouse_exited.connect(func() -> void: _hover(b, false))
	b.focus_entered.connect(func() -> void: _hover(b, true))
	b.focus_exited.connect(func() -> void: _hover(b, false))
	b.button_down.connect(func() -> void: _squash(b))
	b.button_up.connect(func() -> void: _unsquash(b))
	b.pressed.connect(func() -> void: AudioManager.click())
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	return b


static func _hover(b: Button, on: bool) -> void:
	if not is_instance_valid(b) or not b.is_inside_tree():
		return
	var previous = b.get_meta("hover_tween") if b.has_meta("hover_tween") else null
	if previous is Tween and previous.is_valid():
		previous.kill()
	var target := Vector2.ONE * (1.035 if on else 1.0)
	var target_rotation := -0.008 if on else 0.0
	var tw := b.create_tween().set_parallel(true)
	b.set_meta("hover_tween", tw)
	tw.tween_property(b, "scale", target, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "rotation", target_rotation, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func _squash(b: Button) -> void:
	if not is_instance_valid(b):
		return
	var previous = b.get_meta("hover_tween") if b.has_meta("hover_tween") else null
	if previous is Tween and previous.is_valid():
		previous.kill()
	var tw := b.create_tween()
	b.set_meta("hover_tween", tw)
	tw.tween_property(b, "scale", Vector2(0.95, 0.95), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


static func _unsquash(b: Button) -> void:
	if not is_instance_valid(b) or not b.is_inside_tree():
		return
	var active := b.is_hovered() or b.has_focus()
	var target := Vector2.ONE * (1.035 if active else 1.0)
	var previous = b.get_meta("hover_tween") if b.has_meta("hover_tween") else null
	if previous is Tween and previous.is_valid():
		previous.kill()
	var tw := b.create_tween().set_parallel(true)
	b.set_meta("hover_tween", tw)
	tw.tween_property(b, "scale", target, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "rotation", -0.008 if active else 0.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func panel(
	bg := PURPLE_PANEL,
	radius := 26,
	margin := 18,
	border := PURPLE_DARK,
	border_width := 4,
	shadow := 12,
	shadow_color := Color(0.05, 0.01, 0.12, 0.4),
	shadow_offset := Vector2(0, 7)
) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme = theme()
	p.add_theme_stylebox_override("panel", stylebox(bg, radius, border, border_width, margin, shadow, shadow_color, shadow_offset))
	return p


static func overlay_panel() -> PanelContainer:
	return panel(Color("#2a154d"), 26, 20, YELLOW, 3, 14)


static func label(
	text: String,
	size := 22,
	color := WHITE,
	align := HORIZONTAL_ALIGNMENT_CENTER
) -> Label:
	var l := Label.new()
	l.text = text
	l.theme = theme()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if align == HORIZONTAL_ALIGNMENT_LEFT and GameManager.is_rtl() else align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func title(text: String, size := 42, color := YELLOW) -> Label:
	var l := label(text, size, color)
	l.add_theme_color_override("font_outline_color", PURPLE_DARK)
	l.add_theme_constant_override("outline_size", maxi(4, int(size * 0.18)))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.3))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 3)
	return l


static func wrapped_label(text: String, size := 20, color := WHITE) -> Label:
	var l := label(text, size, color, HORIZONTAL_ALIGNMENT_LEFT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l
