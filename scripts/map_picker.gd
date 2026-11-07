extends Control
## Map picker popup: a tidy grid of cards, one per map, each with a picture, the name, the size and a
## one-line description. Only the maps that fit the chosen game mode are listed (same rule as before:
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
const DESC_KEYS := ["map_cloud_desc", "map_ring_desc", "map_tiles_desc", "map_islands_desc", "map_donut_desc", "map_villa_desc", "map_flat_desc", "map_bounce_dome_desc", "map_neon_springs_desc", "map_candy_cloud_desc", "map_sky_bounce_desc", "map_pinball_bounce_desc", "map_twister_desc", "map_school_desc", "map_warehouse_desc", "map_museum_desc"]

var _maps: Array = []
var _selected := 0
var _scroll: ScrollContainer = null
var _grid: GridContainer = null
var _selected_card: Control = null


func setup(maps: Array, selected: int) -> void:
	_maps = maps
	_selected = selected


func _ready() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_RTL if GameManager.is_rtl() else Control.LAYOUT_DIRECTION_LTR
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UIKit.dim_background(self)

	var panel := Cartoon.panel()
	var box := UIKit.vbox(10)
	panel.add_child(box)

	box.add_child(Cartoon.title(GameManager.t("choose_map"), 36))
	var kind := 0
	if _maps.size() > 0:
		kind = int(GameConstants.MAPS[int(_maps[0])]["kind"])
	var sub_key := "maps_trampoline" if kind == 2 else ("maps_house" if kind == 1 else "maps_arena")
	box.add_child(Cartoon.label(GameManager.t(sub_key), 20, Color(1, 1, 1, 0.75)))

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = 12
	box.add_child(_scroll)

	var grid := GridContainer.new()
	_grid = grid
	var viewport_width := get_viewport().get_visible_rect().size.x
	var responsive_columns := 1 if viewport_width < 760.0 else (2 if viewport_width < 1100.0 else 3)
	grid.columns = maxi(1, mini(_maps.size(), responsive_columns))
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(grid)

	for id in _maps:
		var card := _make_card(int(id))
		grid.add_child(card)
		if int(id) == _selected:
			_selected_card = card

	box.add_child(Cartoon.button(GameManager.t("back"), _close, Cartoon.STYLE_NORMAL, Vector2(0, 54)))
	add_child(UIKit.centered(panel, Vector2(1120, 660)))
	get_viewport().size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()

	# Bring the current map into view (matters when the list is longer than the screen).
	await get_tree().process_frame
	if is_instance_valid(_scroll) and is_instance_valid(_selected_card):
		_scroll.ensure_control_visible(_selected_card)


func _on_viewport_resized() -> void:
	if _grid == null:
		return
	var width := get_viewport().get_visible_rect().size.x
	var columns := 1 if width < 760.0 else (2 if width < 1100.0 else 3)
	_grid.columns = maxi(1, mini(_maps.size(), columns))
	var card_width := minf(CARD_W, maxf(80.0, width - 120.0))
	for card in _grid.get_children():
		card.custom_minimum_size.x = card_width
		var inner_width := maxf(0.0, card_width - 24.0)
		var thumb: Control = card.get_meta("thumb", null)
		var desc: Control = card.get_meta("description", null)
		if thumb != null:
			thumb.custom_minimum_size = Vector2(inner_width, inner_width * 9.0 / 16.0)
		if desc != null:
			desc.custom_minimum_size.x = inner_width


func _make_card(map_id: int) -> Control:
	var info: Dictionary = GameConstants.MAPS[map_id]
	var is_sel := map_id == _selected

	var card := PanelContainer.new()
	card.theme = Cartoon.theme()
	var viewport_width := get_viewport().get_visible_rect().size.x
	var card_width := minf(CARD_W, maxf(80.0, viewport_width - 120.0))
	card.custom_minimum_size = Vector2(card_width, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var border := Cartoon.YELLOW if is_sel else Color(1, 1, 1, 0.3)
	var bg := Color(1.0, 0.82, 0.15, 0.18) if is_sel else Color(1, 1, 1, 0.1)
	card.add_theme_stylebox_override("panel", Cartoon.stylebox(bg, 18, border, 5 if is_sel else 2, 10))

	var col := UIKit.vbox(6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)

	var inner_w := card_width - 24.0
	var thumb := _make_thumb(map_id, inner_w)
	card.set_meta("thumb", thumb)
	col.add_child(thumb)

	var name_text := GameManager.t(str(info["key"]))
	if is_sel:
		name_text = "✓ " + name_text
	var name_label := Cartoon.label(name_text, 26, Cartoon.YELLOW if is_sel else Cartoon.WHITE)
	col.add_child(name_label)

	var size_label := Cartoon.label("(%s)" % GameManager.t(str(info["size_key"])), 18, Color(1, 1, 1, 0.7))
	col.add_child(size_label)

	var desc := Cartoon.label(GameManager.t(str(DESC_KEYS[map_id])), 17, Color(1, 1, 1, 0.88))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(inner_w, 0)
	card.set_meta("description", desc)
	col.add_child(desc)

	# Transparent button on top of the whole card = one big touch target.
	var hit := Button.new()
	hit.theme = Cartoon.theme()
	hit.focus_mode = Control.FOCUS_NONE
	hit.flat = true
	hit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	hit.add_theme_stylebox_override("hover", Cartoon.stylebox(Color(1, 1, 1, 0.08), 18, Color(0, 0, 0, 0), 0, 0))
	hit.add_theme_stylebox_override("pressed", Cartoon.stylebox(Color(1, 1, 1, 0.16), 18, Color(0, 0, 0, 0), 0, 0))
	hit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	hit.pressed.connect(func() -> void:
		AudioManager.click()
		_pick(map_id)
	)
	card.add_child(hit)
	return card


func _make_thumb(map_id: int, width: float) -> Control:
	var h := width * 9.0 / 16.0
	var path := THUMB_DIR % map_id
	if ResourceLoader.exists(path):
		var tex = load(path)
		if tex is Texture2D:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tr.custom_minimum_size = Vector2(width, h)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return tr
	var cr := ColorRect.new()
	cr.color = Color(0.2, 0.45, 0.9)
	cr.custom_minimum_size = Vector2(width, h)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cr


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