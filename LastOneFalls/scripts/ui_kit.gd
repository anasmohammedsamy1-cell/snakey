extends RefCounted
## Code-built UI toolkit. All menus are assembled from these helpers so the
## project needs no texture assets and every button behaves consistently
## (press animation, click sound, large touch targets, optional custom font).
## Usage: const UIKit := preload("res://scripts/ui_kit.gd")

const STYLE_NORMAL := 0
const STYLE_PRIMARY := 1
const STYLE_DANGER := 2
const STYLE_GHOST := 3

const COLOR_PRIMARY := Color(1.0, 0.82, 0.15)
const COLOR_DANGER := Color(1.0, 0.38, 0.55)
const COLOR_PANEL := Color(0.08, 0.1, 0.26, 0.78)
const COLOR_DIM := Color(0.03, 0.05, 0.15, 0.6)
const COLOR_TEXT_DARK := Color(0.12, 0.08, 0.25)

const FONT_PATH := "res://assets/fonts/game_font.tres"


static func get_theme() -> Theme:
	if GameManager.ui_theme == null:
		GameManager.ui_theme = _build_theme()
	return GameManager.ui_theme


static func stylebox(bg: Color, radius := 18, border := Color(0, 0, 0, 0), border_width := 0, margin := 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border_width)
	sb.border_color = border
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	return sb


static func _build_theme() -> Theme:
	var th := Theme.new()
	if ResourceLoader.exists(FONT_PATH):
		var f = load(FONT_PATH)
		if f is Font:
			th.default_font = f
	th.default_font_size = 22

	th.set_stylebox("normal", "Button", stylebox(Color(1, 1, 1, 0.16), 18, Color(1, 1, 1, 0.35), 2, 14))
	th.set_stylebox("hover", "Button", stylebox(Color(1, 1, 1, 0.26), 18, Color(1, 1, 1, 0.65), 2, 14))
	th.set_stylebox("pressed", "Button", stylebox(Color(1, 1, 1, 0.1), 18, Color(1, 1, 1, 0.5), 2, 14))
	th.set_stylebox("focus", "Button", stylebox(Color(0, 0, 0, 0), 18, Color(1, 0.9, 0.3, 0.9), 3, 14))
	th.set_stylebox("disabled", "Button", stylebox(Color(1, 1, 1, 0.06), 18, Color(1, 1, 1, 0.15), 2, 14))
	th.set_color("font_color", "Button", Color.WHITE)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", Color(1, 1, 1, 0.85))
	th.set_color("font_focus_color", "Button", Color.WHITE)
	th.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.45))
	th.set_font_size("font_size", "Button", 26)

	th.set_color("font_color", "Label", Color.WHITE)
	th.set_font_size("font_size", "Label", 22)

	th.set_stylebox("normal", "LineEdit", stylebox(Color(0, 0, 0, 0.35), 12, Color(1, 1, 1, 0.4), 2, 10))
	th.set_stylebox("focus", "LineEdit", stylebox(Color(0, 0, 0, 0.45), 12, Color(1, 0.9, 0.3, 0.9), 2, 10))
	th.set_color("font_color", "LineEdit", Color.WHITE)
	th.set_color("font_placeholder_color", "LineEdit", Color(1, 1, 1, 0.45))
	th.set_font_size("font_size", "LineEdit", 24)

	th.set_stylebox("panel", "PanelContainer", stylebox(COLOR_PANEL, 24, Color(1, 1, 1, 0.22), 2, 18))

	th.set_stylebox("slider", "HSlider", stylebox(Color(1, 1, 1, 0.25), 8, Color(0, 0, 0, 0), 0, 0))
	th.set_stylebox("grabber_area", "HSlider", stylebox(COLOR_PRIMARY, 8, Color(0, 0, 0, 0), 0, 0))
	th.set_stylebox("grabber_area_highlight", "HSlider", stylebox(COLOR_PRIMARY.lightened(0.2), 8, Color(0, 0, 0, 0), 0, 0))

	th.set_font_size("font_size", "CheckButton", 22)
	th.set_color("font_color", "CheckButton", Color.WHITE)
	th.set_font_size("font_size", "OptionButton", 22)
	th.set_font_size("font_size", "PopupMenu", 22)
	return th


# ---------------------------------------------------------------------------
# Widgets

static func button(text: String, on_pressed: Callable = Callable(), style := STYLE_NORMAL, min_size := Vector2(280, 64)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE if SettingsManager.is_mobile() else Control.FOCUS_ALL
	b.theme = get_theme()
	match style:
		STYLE_PRIMARY:
			b.add_theme_stylebox_override("normal", stylebox(COLOR_PRIMARY, 18, Color(1, 1, 1, 0.8), 2, 14))
			b.add_theme_stylebox_override("hover", stylebox(COLOR_PRIMARY.lightened(0.15), 18, Color.WHITE, 2, 14))
			b.add_theme_stylebox_override("pressed", stylebox(COLOR_PRIMARY.darkened(0.12), 18, Color.WHITE, 2, 14))
			b.add_theme_color_override("font_color", COLOR_TEXT_DARK)
			b.add_theme_color_override("font_hover_color", COLOR_TEXT_DARK)
			b.add_theme_color_override("font_pressed_color", COLOR_TEXT_DARK)
			b.add_theme_color_override("font_focus_color", COLOR_TEXT_DARK)
			b.add_theme_font_size_override("font_size", 30)
		STYLE_DANGER:
			b.add_theme_stylebox_override("normal", stylebox(COLOR_DANGER, 18, Color(1, 1, 1, 0.7), 2, 14))
			b.add_theme_stylebox_override("hover", stylebox(COLOR_DANGER.lightened(0.15), 18, Color.WHITE, 2, 14))
			b.add_theme_stylebox_override("pressed", stylebox(COLOR_DANGER.darkened(0.15), 18, Color.WHITE, 2, 14))
		STYLE_GHOST:
			b.add_theme_stylebox_override("normal", stylebox(Color(0, 0, 0, 0.0), 18, Color(1, 1, 1, 0.5), 2, 14))
		_:
			pass
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	b.button_down.connect(func() -> void: _animate_scale(b, 0.93))
	b.button_up.connect(func() -> void: _animate_scale(b, 1.0))
	b.pressed.connect(func() -> void: AudioManager.click())
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = text
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	return b


## Icon-only action button. The visible name is replaced by an SVG; tooltip and
## accessibility name retain the localized action description.
static func icon_button(icon_name: String, description: String, on_pressed: Callable = Callable(), style := STYLE_NORMAL, min_size := Vector2(58, 58)) -> Button:
	var b := button("", on_pressed, style, min_size)
	var icon_path := "res://assets/icons/%s.svg" % icon_name
	if ResourceLoader.exists(icon_path):
		b.icon = load(icon_path) as Texture2D
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.expand_icon = true
	b.tooltip_text = description
	b.accessibility_name = description
	return b


static func _animate_scale(c: Control, s: float) -> void:
	if not is_instance_valid(c) or not c.is_inside_tree():
		return
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE * s, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


static func label(text: String, size := 22, color := Color.WHITE, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.theme = get_theme()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if align == HORIZONTAL_ALIGNMENT_LEFT and GameManager.is_rtl() else align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func title(text: String, size := 56, color := COLOR_PRIMARY) -> Label:
	var l := label(text, size, color)
	l.add_theme_color_override("font_outline_color", Color(0.15, 0.06, 0.3, 1.0))
	l.add_theme_constant_override("outline_size", int(size * 0.22))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 5)
	return l


static func wrapped_label(text: String, size := 20, color := Color.WHITE) -> Label:
	var l := label(text, size, color, HORIZONTAL_ALIGNMENT_LEFT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func panel(bg := COLOR_PANEL, radius := 24, margin := 18) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme = get_theme()
	p.add_theme_stylebox_override("panel", stylebox(bg, radius, Color(1, 1, 1, 0.22), 2, margin))
	return p


static func vbox(separation := 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v


static func hbox(separation := 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h


static func spacer(min_size := Vector2(0, 0), expand := true) -> Control:
	var c := Control.new()
	c.custom_minimum_size = min_size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func slider(min_value: float, max_value: float, step: float, value: float, on_changed: Callable) -> HSlider:
	var s := HSlider.new()
	s.theme = get_theme()
	s.min_value = min_value
	s.max_value = max_value
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(240, 44)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(on_changed)
	return s


## A labelled slider row: [label      ---o---  value]
static func slider_row(text: String, min_value: float, max_value: float, step: float, value: float, on_changed: Callable, suffix := "") -> BoxContainer:
	var row := BoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var tree := Engine.get_main_loop() as SceneTree
	var compact := tree != null and tree.root.get_viewport().get_visible_rect().size.x < 760.0
	row.vertical = compact
	var l := label(text, 20 if compact else 22, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	l.custom_minimum_size = Vector2(0 if compact else 260, 44)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var value_label := label(_fmt(value, step, suffix), 18, Color(1, 1, 1, 0.8))
	value_label.custom_minimum_size = Vector2(70, 44)
	var s := slider(min_value, max_value, step, value, func(v: float) -> void:
		value_label.text = _fmt(v, step, suffix)
		on_changed.call(v)
	)
	s.name = "Slider"
	row.add_child(s)
	row.add_child(value_label)
	return row


static func _fmt(v: float, step: float, suffix: String) -> String:
	if step >= 1.0:
		return "%d%s" % [int(v), suffix]
	return "%.2f%s" % [v, suffix]


static func toggle_row(text: String, value: bool, on_toggled: Callable) -> HBoxContainer:
	var row := hbox(16)
	var l := label(text, 22, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var cb := CheckButton.new()
	cb.theme = get_theme()
	cb.button_pressed = value
	cb.focus_mode = Control.FOCUS_NONE
	cb.custom_minimum_size = Vector2(90, 48)
	cb.toggled.connect(func(v: bool) -> void:
		AudioManager.click()
		on_toggled.call(v)
	)
	cb.name = "Toggle"
	row.add_child(cb)
	return row


static func section_title(text: String) -> Label:
	var l := label(text, 26, COLOR_PRIMARY, HORIZONTAL_ALIGNMENT_LEFT)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.25, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	return l


static func color_swatch(color: Color, selected: bool, on_pressed: Callable, size := 58.0) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(size, size)
	b.focus_mode = Control.FOCUS_NONE
	b.theme = get_theme()
	var border := Color.WHITE if selected else Color(0, 0, 0, 0.25)
	b.add_theme_stylebox_override("normal", stylebox(color, int(size * 0.3), border, 4 if selected else 2, 4))
	b.add_theme_stylebox_override("hover", stylebox(color.lightened(0.15), int(size * 0.3), Color.WHITE, 3, 4))
	b.add_theme_stylebox_override("pressed", stylebox(color.darkened(0.15), int(size * 0.3), Color.WHITE, 4, 4))
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	b.button_down.connect(func() -> void: _animate_scale(b, 0.9))
	b.button_up.connect(func() -> void: _animate_scale(b, 1.0))
	b.pressed.connect(func() -> void: AudioManager.click())
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	return b


static func dim_background(parent: Control, color := COLOR_DIM) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP # swallow touches so gameplay is not affected
	parent.add_child(r)
	return r


static func fullscreen(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


## Safe-area insets (left, top, right, bottom) in canvas pixels. Zero on desktop.
static func safe_insets(viewport: Viewport) -> Vector4:
	if not SettingsManager.is_mobile():
		return Vector4.ZERO
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0 or safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO
	var vs := viewport.get_visible_rect().size
	var sx := vs.x / float(win.x)
	var sy := vs.y / float(win.y)
	var left := float(safe.position.x) * sx
	var top := float(safe.position.y) * sy
	var right := float(win.x - (safe.position.x + safe.size.x)) * sx
	var bottom := float(win.y - (safe.position.y + safe.size.y)) * sy
	return Vector4(maxf(left, 0.0), maxf(top, 0.0), maxf(right, 0.0), maxf(bottom, 0.0))


static func _apply_safe_margins(container: MarginContainer, viewport: Viewport, extra: int) -> void:
	if not is_instance_valid(container) or not is_instance_valid(viewport):
		return
	var insets := safe_insets(viewport)
	container.add_theme_constant_override("margin_left", int(ceil(insets.x)) + extra)
	container.add_theme_constant_override("margin_top", int(ceil(insets.y)) + extra)
	container.add_theme_constant_override("margin_right", int(ceil(insets.z)) + extra)
	container.add_theme_constant_override("margin_bottom", int(ceil(insets.w)) + extra)


static func safe_margin_container(viewport: Viewport, extra := 16) -> MarginContainer:
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_safe_margins(m, viewport, extra)
	# Disconnect the bound callback when its container exits; otherwise a freed
	# container leaves a dangling listener on later viewport rotations.
	var update := _apply_safe_margins.bind(m, viewport, extra)
	viewport.size_changed.connect(update)
	m.tree_exiting.connect(func() -> void:
		if is_instance_valid(viewport) and viewport.size_changed.is_connected(update):
			viewport.size_changed.disconnect(update)
	)
	return m


static func _apply_centered_layout(container: CenterContainer, child: Control, viewport: Viewport, max_size: Vector2) -> void:
	if not is_instance_valid(container) or not is_instance_valid(child) or not is_instance_valid(viewport):
		return
	var view_size := viewport.get_visible_rect().size
	var safe := safe_insets(viewport)
	container.offset_left = safe.x
	container.offset_top = safe.y
	container.offset_right = -safe.z
	container.offset_bottom = -safe.w
	# Do not force a 280/240 px minimum on very small or split-screen viewports.
	var available := Vector2(
		maxf(0.0, view_size.x - safe.x - safe.z - 28.0),
		maxf(0.0, view_size.y - safe.y - safe.w - 28.0)
	)
	child.custom_minimum_size = Vector2(minf(max_size.x, available.x), minf(max_size.y, available.y))


## Centre a control on screen with a maximum size that adapts to small phones.
## The safe area and panel constraints are recalculated whenever the viewport changes.
static func centered(child: Control, max_size := Vector2(900, 620)) -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	child.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	child.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.add_child(child)
	# Resolve the actual owning viewport once attached (not necessarily the root).
	# This supports split views and avoids stale bound callbacks on repeated menus.
	var state := {}
	c.tree_entered.connect(func() -> void:
		var viewport := c.get_viewport()
		if viewport == null:
			return
		_apply_centered_layout(c, child, viewport, max_size)
		var update := _apply_centered_layout.bind(c, child, viewport, max_size)
		state["viewport"] = viewport
		state["update"] = update
		if not viewport.size_changed.is_connected(update):
			viewport.size_changed.connect(update)
	)
	c.tree_exiting.connect(func() -> void:
		var viewport: Viewport = state.get("viewport")
		var update: Callable = state.get("update", Callable())
		if is_instance_valid(viewport) and update.is_valid() and viewport.size_changed.is_connected(update):
			viewport.size_changed.disconnect(update)
		state.clear()
	)
	return c


## Shared breakpoint for compact/mobile layouts. Uses the actual canvas size, not device DPI.
static func is_compact(viewport: Viewport, min_width := 900.0) -> bool:
	if viewport == null:
		return false
	var size := viewport.get_visible_rect().size
	return size.x < min_width or size.y < 560.0


static func add_fade_in(control: Control, duration := 0.16) -> void:
	control.modulate.a = 0.0
	var tw := control.create_tween()
	tw.tween_property(control, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
