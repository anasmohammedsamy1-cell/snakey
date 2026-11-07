extends Control
## End-of-round results: winner headline, ranking with points / totals,
## and the follow-up actions (rematch, lobby, leave, play again).

const Cartoon := preload("res://scripts/cartoon_ui.gd")
const UIKit := preload("res://scripts/ui_kit.gd")
const GameConstants := preload("res://scripts/game_constants.gd")


func _ready() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_RTL if GameManager.is_rtl() else Control.LAYOUT_DIRECTION_LTR
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func show_results(results: Array, headline: String, practice: bool) -> void:
	for c in get_children():
		c.queue_free()
	UIKit.dim_background(self, Color(0.03, 0.05, 0.15, 0.7))

	var panel := Cartoon.panel()
	var box := UIKit.vbox(10)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)

	var compact := _is_compact(get_viewport(), 760.0)
	var narrow := get_viewport().get_visible_rect().size.x < 760.0
	var title := Cartoon.title(headline, 38 if compact else 46)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(0, 0)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(title)
	box.add_child(Cartoon.wrapped_label(GameManager.t("round_over") if not practice else GameManager.t("practice_tip"), 20, Color(1, 1, 1, 0.75)))
	if not practice and not SaveManager.last_unlocked_colors.is_empty():
		var names: PackedStringArray = []
		for color_id in SaveManager.last_unlocked_colors:
			names.append(GameConstants.get_color_name(color_id))
		box.add_child(Cartoon.wrapped_label(GameManager.t("new_colors_unlocked") % ", ".join(names), 18, Cartoon.COLOR_PRIMARY))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 160 if compact else 280)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var list := UIKit.vbox(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for r in results:
		var row := BoxContainer.new()
		row.vertical = narrow
		row.add_theme_constant_override("separation", 8 if compact else 12)
		var rank := int(r["rank"])
		var rank_label := Cartoon.label(_rank_text(rank), 26, _rank_color(rank))
		rank_label.custom_minimum_size = Vector2(70, 44)
		row.add_child(rank_label)
		var swatch := ColorRect.new()
		swatch.color = GameConstants.get_color(int(r["color"]))
		swatch.custom_minimum_size = Vector2(28, 28)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var pname := str(r["name"])
		if bool(r.get("bot", false)):
			pname += " (%s)" % GameManager.t("bots")
		var name_label := Cartoon.label(pname, 18 if compact else 24, Cartoon.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		if str(r.get("tag", "")) != "":
			row.add_child(Cartoon.label(str(r["tag"]), 18, Color(1, 1, 1, 0.75)))
		if bool(r.get("ko_mode", false)):
			# Knockout: knockouts first (the ranking key), then falls (first tie-break), then the match points.
			row.add_child(Cartoon.label("%d %s" % [int(r["kos"]), GameManager.t("ko_short")], 24, Color(1.0, 0.85, 0.12)))
			row.add_child(Cartoon.label("%d %s" % [int(r["falls"]), GameManager.t("falls")], 18, Color(1, 1, 1, 0.7)))
			row.add_child(Cartoon.label("+%d %s" % [int(r["points"]), GameManager.t("points")], 20, Color(0.45, 0.95, 0.4)))
		elif practice:
			row.add_child(Cartoon.label("%d %s" % [int(r["falls"]), GameManager.t("falls")], 22, Color(1, 1, 1, 0.85)))
		else:
			row.add_child(Cartoon.label("+%d %s" % [int(r["points"]), GameManager.t("points")], 22, Color(0.45, 0.95, 0.4)))
			var total := Cartoon.label("%s: %d" % [GameManager.t("total"), int(r["total"])], 20, Color(1, 1, 1, 0.75))
			total.custom_minimum_size = Vector2(120, 0)
			row.add_child(total)
			var st: Dictionary = r.get("stats", {})
			if not st.is_empty():
				var att := int(st.get("attacks", 0))
				var hit := int(st.get("hits", 0))
				var acc := 0 if att == 0 else roundi(100.0 * float(hit) / float(att))
				var extra := Cartoon.label("KO %d  |  %d%%" % [int(st.get("kos", 0)), acc], 16, Color(1, 1, 1, 0.6))
				extra.custom_minimum_size = Vector2(100, 0)
				row.add_child(extra)
		list.add_child(row)

	var buttons := BoxContainer.new()
	buttons.vertical = narrow
	buttons.add_theme_constant_override("separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	if practice or not NetworkManager.online:
		buttons.add_child(Cartoon.button(GameManager.t("play_again"), func() -> void: GameManager.restart_solo(), Cartoon.STYLE_PRIMARY, Vector2(240, 60)))
		buttons.add_child(Cartoon.button(GameManager.t("main_menu"), func() -> void: GameManager.leave_match(), Cartoon.STYLE_NORMAL, Vector2(240, 60)))
	elif NetworkManager.is_host:
		buttons.add_child(Cartoon.button(GameManager.t("rematch"), func() -> void: NetworkManager.rematch(), Cartoon.STYLE_PRIMARY, Vector2(240, 60)))
		buttons.add_child(Cartoon.button(GameManager.t("to_lobby"), func() -> void: NetworkManager.return_to_lobby(), Cartoon.STYLE_NORMAL, Vector2(240, 60)))
	else:
		var waiting := Cartoon.label(GameManager.t("waiting_host"), 22, Color(1, 1, 1, 0.8))
		buttons.add_child(waiting)
		buttons.add_child(Cartoon.button(GameManager.t("leave"), func() -> void: GameManager.leave_match(), Cartoon.STYLE_DANGER, Vector2(200, 60)))
	box.add_child(buttons)
	add_child(UIKit.centered(panel, Vector2(760, 560)))
	UIKit.add_fade_in(panel)


func _rank_text(rank: int) -> String:
	match rank:
		1:
			return "1st"
		2:
			return "2nd"
		3:
			return "3rd"
		_:
			return "%dth" % rank


func _rank_color(rank: int) -> Color:
	match rank:
		1:
			return Color(1.0, 0.85, 0.12)
		2:
			return Color(0.85, 0.85, 0.9)
		3:
			return Color(0.85, 0.55, 0.3)
		_:
			return Color(1, 1, 1, 0.7)


func _is_compact(viewport: Viewport, threshold: float) -> bool:
	return viewport.get_visible_rect().size.x < threshold or viewport.get_visible_rect().size.y < threshold * 0.75