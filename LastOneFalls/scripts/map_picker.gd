extends Control
## Map picker popup (carousel): one BIG map at a time with the picture, name, size and description,
## arrow buttons / swipe / keyboard arrows to browse, a strip of small pictures to jump straight to a map,
## and a clear SELECT button. Only the maps that fit the chosen game mode are listed (same rule as before:
## floating arenas for Classic / Team brawl, houses for Hide and seek).
## Usage:
##   var p := MapPickerScript.new()
##   p.setup(GameConstants.maps_for_mode(mode), current_map_id)
##   parent.add_child(p)
##   p.picked.connect(func(id: int) -> void: ...)
## Pictures: res://assets/maps/map_<id>.png (made by tools/gen_map_thumbs.py). If one is missing the
## card shows a plain coloured box, so the picker never breaks.

signal picked(map_id: int)
signal closed

const Cartoon := preload("res://scripts/cartoon_ui.gd")
const UIKit := preload("res://scripts/ui_kit.gd")
const GameConstants := preload("res://scripts/game_constants.gd")

const THUMB_DIR := "res://assets/maps/map_%d.png"
const CARD_W := 330.0
const DESC_KEYS := ["map_cloud_desc", "map_ring_desc", "map_tiles_desc", "map_islands_desc", "map_donut_desc", "map_villa_desc", "map_flat_desc", "map_bounce_dome_desc", "map_neon_springs_desc", "map_candy_cloud_desc", "map_sky_bounce_desc", "map_pinball_bounce_desc", "map_twister_desc", "map_school_desc", "map_warehouse_desc", "map_museum_desc", "map_family_flat_desc", "map_plaza_desc", "map_mini_tiles_desc", "map_split_ring_desc", "map_ice_rink_desc", "map_conveyor_mill_desc", "map_wind_tunnel_desc"]

var _maps: Array = []
var _selected := 0            # the map that is currently chosen
var _index := 0               # index (into _maps) of the map being previewed
var _tex_cache: Dictionary = {}
var _thumb: TextureRect
var _fallback: ColorRect
var _name_label: Label
var _size_label: Label
var _desc_label: Label
var _count_label: Label
var _select_btn: Button
var _strip: HBoxContainer
var _strip_scroll: ScrollContainer
var _swipe_from := Vector2.ZERO
var _swiping := false


func setup(maps: Array, selected: int) -> void:
	_maps = maps
	_selected = selected
	_index = maxi(0, _maps.find(selected))


func _ready() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_RTL if GameManager.is_rtl() else Control.LAYOUT_DIRECTION_LTR
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UIKit.dim_background(self)
	if _maps.is_empty():
		_close()
		return

	var panel := Cartoon.panel()
	var box := UIKit.vbox(8)
	panel.add_child(box)

	box.add_child(Cartoon.title(GameManager.t("choose_map"), 34))
	var kind := int(GameConstants.MAPS[int(_maps[0])]["kind"])
	var sub_key := "maps_trampoline" if kind == 2 else ("maps_house" if kind == 1 else "maps_arena")
	box.add_child(Cartoon.label(GameManager.t(sub_key), 18, Color(1, 1, 1, 0.75)))

	# ---- middle: [prev] [big card] [next]
	var rtl := GameManager.is_rtl()
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 10)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(mid)
	var prev_btn := Cartoon.button("▶" if rtl else "◀", func() -> void: _step(-1), Cartoon.STYLE_NORMAL, Vector2(64, 0))
	var next_btn := Cartoon.button("◀" if rtl else "▶", func() -> void: _step(1), Cartoon.STYLE_NORMAL, Vector2(64, 0))
	prev_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	next_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(prev_btn)

	var card := PanelContainer.new()
	card.theme = Cartoon.theme()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", Cartoon.stylebox(Color(1, 1, 1, 0.1), 20, Cartoon.YELLOW, 4, 10))
	card.gui_input.connect(_on_card_input)
	mid.add_child(card)
	mid.add_child(next_btn)

	var col := UIKit.vbox(6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)

	var frame := Control.new()
	frame.custom_minimum_size = Vector2(0, 150)
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.clip_contents = true            # the picture is cropped to the card, never spills over
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(frame)
	_fallback = ColorRect.new()
	_fallback.color = Color(0.2, 0.45, 0.9)
	_fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_fallback)
	_thumb = TextureRect.new()
	_thumb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_thumb)

	_name_label = Cartoon.label("", 30, Cartoon.YELLOW)
	col.add_child(_name_label)
	_size_label = Cartoon.label("", 18, Color(1, 1, 1, 0.7))
	col.add_child(_size_label)
	_desc_label = Cartoon.wrapped_label("", 18, Color(1, 1, 1, 0.9))
	col.add_child(_desc_label)
	_count_label = Cartoon.label("", 16, Color(1, 1, 1, 0.55))
	col.add_child(_count_label)

	# ---- strip of small pictures (tap = jump to that map)
	_strip_scroll = ScrollContainer.new()
	_strip_scroll.custom_minimum_size = Vector2(0, 74)
	_strip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_strip_scroll.scroll_deadzone = 12
	box.add_child(_strip_scroll)
	_strip = HBoxContainer.new()
	_strip.add_theme_constant_override("separation", 8)
	_strip_scroll.add_child(_strip)
	for i in _maps.size():
		var b := Button.new()
		b.theme = Cartoon.theme()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(104, 62)
		b.clip_contents = true
		b.expand_icon = true
		b.icon = _texture_for(int(_maps[i]))
		b.pressed.connect(func() -> void:
			AudioManager.click()
			_go(i)
		)
		_strip.add_child(b)

	# ---- bottom buttons
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	box.add_child(bottom)
	_select_btn = Cartoon.button(GameManager.t("pick_map"), _on_select_pressed, Cartoon.STYLE_PRIMARY, Vector2(0, 58))
	_select_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_select_btn)
	var rand_btn := Cartoon.button("🎲 " + GameManager.t("random_map"), _on_random_pressed, Cartoon.STYLE_NORMAL, Vector2(150, 58))
	bottom.add_child(rand_btn)
	var back := Cartoon.button(GameManager.t("back"), _close, Cartoon.STYLE_NORMAL, Vector2(140, 58))
	bottom.add_child(back)

	add_child(UIKit.centered(panel, Vector2(920, 640)))
	_refresh()


## Dice button: jump to a random map AND confirm it in one tap (a "random" button that still
## asks you to press SELECT twice is just an extra step).
func _on_random_pressed() -> void:
	AudioManager.click()
	if _maps.size() > 1:
		var i := randi() % (_maps.size() - 1)
		_go(i if i < _index else i + 1)        # always a different map than the one on screen
	_pick(int(_maps[_index]))


func _on_select_pressed() -> void:
	AudioManager.click()
	_pick(int(_maps[_index]))


func _step(delta: int) -> void:
	AudioManager.click()
	_go(posmod(_index + delta, _maps.size()))


func _go(i: int) -> void:
	_index = clampi(i, 0, _maps.size() - 1)
	_refresh()


func _refresh() -> void:
	var id := int(_maps[_index])
	var info: Dictionary = GameConstants.MAPS[id]
	var tex := _texture_for(id)
	_thumb.texture = tex
	_fallback.visible = tex == null
	var chosen := id == _selected
	_name_label.text = ("✓ " if chosen else "") + GameManager.t(str(info["key"]))
	_size_label.text = "(%s)" % GameManager.t(str(info["size_key"]))
	_desc_label.text = GameManager.t(str(DESC_KEYS[id]))
	_count_label.text = "%d / %d" % [_index + 1, _maps.size()]
	# strip highlight
	for i in _strip.get_child_count():
		var b: Button = _strip.get_child(i)
		var on := i == _index
		var col := Cartoon.YELLOW if on else Color(1, 1, 1, 0.25)
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, Cartoon.stylebox(Color(1, 1, 1, 0.12), 12, col, 5 if on else 2, 2))
	if is_instance_valid(_strip_scroll) and _strip.get_child_count() > _index:
		_strip_scroll.ensure_control_visible.call_deferred(_strip.get_child(_index))


## Picture cropped tightly around the map: the middle of the thumbnail only (sky border removed).
func _texture_for(map_id: int) -> Texture2D:
	if _tex_cache.has(map_id):
		return _tex_cache[map_id]
	var result: Texture2D = null
	var path := THUMB_DIR % map_id
	if ResourceLoader.exists(path):
		var tex = load(path)
		if tex is Texture2D:
			var sz := Vector2((tex as Texture2D).get_size())
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(sz.x * 0.10, sz.y * 0.14, sz.x * 0.80, sz.y * 0.74)
			result = at
	_tex_cache[map_id] = result
	return result


func _on_card_input(event: InputEvent) -> void:
	# swipe left / right on the big card to browse
	var pos := Vector2.ZERO
	var down := false
	var up := false
	var mb := event as InputEventMouseButton
	var st := event as InputEventScreenTouch
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		pos = mb.position
		down = mb.pressed
		up = not mb.pressed
	elif st != null:
		pos = st.position
		down = st.pressed
		up = not st.pressed
	else:
		return
	if down:
		_swipe_from = pos
		_swiping = true
	elif up and _swiping:
		_swiping = false
		var dx := pos.x - _swipe_from.x
		if absf(dx) > 70.0:
			var rtl_sign := -1 if GameManager.is_rtl() else 1
			_step(-rtl_sign if dx > 0.0 else rtl_sign)


func _pick(map_id: int) -> void:
	picked.emit(map_id)
	_close()


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
	elif event.is_action_pressed("ui_left") and not _maps.is_empty():
		get_viewport().set_input_as_handled()
		_step(1 if GameManager.is_rtl() else -1)
	elif event.is_action_pressed("ui_right") and not _maps.is_empty():
		get_viewport().set_input_as_handled()
		_step(-1 if GameManager.is_rtl() else 1)
	elif event.is_action_pressed("ui_accept") and not _maps.is_empty():
		get_viewport().set_input_as_handled()
		_pick(int(_maps[_index]))
