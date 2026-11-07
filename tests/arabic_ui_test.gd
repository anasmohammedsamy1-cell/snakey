extends Node
## Functional UI checks with an explicitly sized SubViewport; no phone device required.
const Picker := preload("res://scripts/map_picker.gd")
const Constants := preload("res://scripts/game_constants.gd")
var failures := 0
var selected := -1
func _ready() -> void:
	call_deferred("run_test")
func check(ok: bool, label: String) -> void:
	if ok: print("[AR-UI] PASS ", label)
	else:
		failures += 1
		print("[AR-UI] FAIL ", label)
func on_picked(id: int) -> void:
	selected = id
func run_test() -> void:
	SettingsManager.settings["language"] = "ar"
	var vp := SubViewport.new()
	vp.size = Vector2i(480, 400)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var font = load("res://assets/fonts/main_font.ttf")
	check(font != null and font.has_char("ع".unicode_at(0)) and font.has_char("A".unicode_at(0)), "bundled font supports Arabic and Latin")
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	vp.add_child(menu)
	await get_tree().process_frame
	check(menu._root.layout_direction == Control.LAYOUT_DIRECTION_RTL, "Arabic main menu uses RTL layout")
	check(menu._menu_buttons[0].text == GameManager.t("play") and menu._menu_buttons[2].text == GameManager.t("tutorial_title"), "play and tutorial are prioritized")
	menu._open_customize()
	await get_tree().process_frame
	var custom = menu._overlay
	check(custom != null and custom.layout_direction == Control.LAYOUT_DIRECTION_RTL, "customization opens with RTL layout")
	check(custom._body_layout.vertical and custom._color_grid.columns == 2, "customization stacks for narrow viewport")
	await get_tree().process_frame
	var custom_panel: Control = custom.get_child(custom.get_child_count() - 1).get_child(0)
	check(custom_panel.size.x <= 480.5, "customization panel fits narrow viewport")
	var scrolls: Array[Node] = custom.find_children("*", "ScrollContainer", true, false)
	check(not scrolls.is_empty() and scrolls[0].get_v_scroll_bar().max_value > scrolls[0].get_v_scroll_bar().page, "customization content scrolls on short viewport")
	custom._on_name_changed("")
	check(custom._error_label.text == GameManager.t("empty_name_hint"), "empty name hint translated")
	check(Constants.get_color_name(0) == GameManager.t("color_sunny"), "original colors translated")
	if OS.get_environment("UI_CAPTURE") == "1":
		await get_tree().create_timer(0.35).timeout
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png("/tmp/arabic_custom.png")
	vp.size = Vector2i(1280, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	check(not custom._body_layout.vertical and custom._color_grid.columns == 4, "customization adapts after resize")
	menu._close_overlay()
	await get_tree().process_frame
	menu.queue_free()
	await get_tree().process_frame
	vp.size = Vector2i(480, 400)
	var lobby = load("res://scenes/lobby.tscn").instantiate()
	vp.add_child(lobby)
	await get_tree().process_frame
	check(lobby.layout_direction == Control.LAYOUT_DIRECTION_RTL, "lobby uses RTL layout")
	check(lobby._ip_edit.text_direction == Control.TEXT_DIRECTION_LTR and lobby._port_edit.text_direction == Control.TEXT_DIRECTION_LTR, "IP address and port stay LTR")
	lobby._ip_edit.text = "bad"
	lobby._on_join_pressed()
	check(lobby._error_label.text == GameManager.t("invalid_ip"), "invalid IP shows Arabic error")
	if OS.get_environment("UI_CAPTURE") == "1":
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png("/tmp/arabic_lobby.png")
	lobby.queue_free()
	await get_tree().process_frame
	var picker = Picker.new()
	picker.setup([5, 6, 13, 14, 15], 13)
	picker.picked.connect(on_picked)
	vp.add_child(picker)
	await get_tree().process_frame
	check(picker.layout_direction == Control.LAYOUT_DIRECTION_RTL and picker._grid.columns == 1, "map picker is RTL and single-column when narrow")
	vp.size = Vector2i(1280, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	check(picker._grid.columns == 3, "map picker adjusts columns after resize")
	var card = picker._grid.get_child(2)
	var hit: Button = card.get_child(card.get_child_count() - 1)
	hit.pressed.emit()
	check(selected == 13, "map card sends selected map")
	picker.queue_free()
	await get_tree().process_frame
	var result = load("res://scenes/ui/results_screen.tscn").instantiate()
	vp.add_child(result)
	await get_tree().process_frame
	result.show_results([{"rank": 1, "color": 0, "name": "لاعب", "points": 3, "total": 3}], "فائز", false)
	check(result.layout_direction == Control.LAYOUT_DIRECTION_RTL, "results screen uses RTL")
	result.queue_free()
	await get_tree().process_frame
	SettingsManager.settings["language"] = "en"
	var english_menu = load("res://scenes/main_menu.tscn").instantiate()
	vp.add_child(english_menu)
	await get_tree().process_frame
	check(english_menu._root.layout_direction == Control.LAYOUT_DIRECTION_LTR, "English menu stays LTR")
	check(Constants.get_color_name(0) == "Sunny Yellow", "English color names preserved")
	english_menu.queue_free()
	await get_tree().process_frame
	print("[AR-UI] finished with %d failure(s)" % failures)
	get_tree().quit(1 if failures else 0)
