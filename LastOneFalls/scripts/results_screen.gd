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
	if not practice and SaveManager.last_coins_earned > 0:
		box.add_child(Cartoon.wrapped_label(GameManager.t("coins_earned") % [SaveManager.last_coins_earned, SaveManager.coins], 20, Cartoon.YELLOW))
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

	var show_acc := not narrow
	var is_ko := false
	for r0 in results:
		if bool(r0.get("ko_mode", false)):
			is_ko = true
	list.add_child(_header_row(practice, is_ko, show_acc))
	var me_id := multiplayer.get_unique_id()
	for r in results:
		list.add_child(_result_row(r, practice, show_acc, compact, int(r["id"]) == me_id or str(r["name"]) == SaveManager.player_name))

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


const COL_RANK := 64.0
const COL_NUM := 78.0


func _col(text: String, width: float, size: int, color: Color) -> Label:
	var l := Cartoon.label(text, size, color)
	l.custom_minimum_size = Vector2(width, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _header_row(practice: bool, is_ko: bool, show_acc: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var dim := Color(1, 1, 1, 0.6)
	row.add_child(_col("#", COL_RANK + 34.0, 16, dim))
	var name_h := Cartoon.label(GameManager.t("hdr_player"), 16, dim, HORIZONTAL_ALIGNMENT_LEFT)
	name_h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_h)
	if is_ko:
		row.add_child(_col(GameManager.t("ko_short"), COL_NUM, 16, dim))
		row.add_child(_col(GameManager.t("falls"), COL_NUM, 16, dim))
		row.add_child(_col(GameManager.t("points"), COL_NUM, 16, dim))
	elif practice:
		row.add_child(_col(GameManager.t("falls"), COL_NUM, 16, dim))
	else:
		row.add_child(_col(GameManager.t("points"), COL_NUM, 16, dim))
		row.add_child(_col(GameManager.t("total"), COL_NUM, 16, dim))
		if show_acc:
			row.add_child(_col("KO", COL_NUM, 16, dim))
			row.add_child(_col(GameManager.t("hdr_accuracy"), COL_NUM, 16, dim))
	return row


func _result_row(r: Dictionary, practice: bool, show_acc: bool, compact: bool, is_me: bool) -> Control:
	var rank := int(r["rank"])
	var card := PanelContainer.new()
	card.theme = Cartoon.theme()
	var bg := Color(1.0, 0.85, 0.12, 0.22) if rank == 1 else Color(1, 1, 1, 0.09)
	var border := Cartoon.YELLOW if is_me else (_rank_color(rank) if rank <= 3 else Color(1, 1, 1, 0.15))
	card.add_theme_stylebox_override("panel", Cartoon.stylebox(bg, 14, border, 4 if is_me else 2, 6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	card.add_child(row)
	row.add_child(_col(_rank_text(rank), COL_RANK, 24, _rank_color(rank)))
	var swatch := ColorRect.new()
	swatch.color = GameConstants.get_color(int(r["color"]))
	swatch.custom_minimum_size = Vector2(28, 28)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)
	var pname := str(r["name"])
	if bool(r.get("bot", false)):
		pname += " (%s)" % GameManager.t("bots")
	if is_me:
		pname += "  ◄ " + GameManager.t("you")
	if str(r.get("tag", "")) != "":
		pname += "  [" + str(r["tag"]) + "]"
	var name_label := Cartoon.label(pname, 18 if compact else 22, Cartoon.YELLOW if is_me else Cartoon.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	row.add_child(name_label)
	var green := Color(0.45, 0.95, 0.4)
	if bool(r.get("ko_mode", false)):
		row.add_child(_col(str(int(r["kos"])), COL_NUM, 24, Color(1.0, 0.85, 0.12)))
		row.add_child(_col(str(int(r["falls"])), COL_NUM, 20, Color(1, 1, 1, 0.75)))
		row.add_child(_col("+%d" % int(r["points"]), COL_NUM, 22, green))
	elif practice:
		row.add_child(_col(str(int(r["falls"])), COL_NUM, 22, Color(1, 1, 1, 0.9)))
	else:
		row.add_child(_col("+%d" % int(r["points"]), COL_NUM, 22, green))
		row.add_child(_col(str(int(r["total"])), COL_NUM, 20, Color(1, 1, 1, 0.8)))
		if show_acc:
			var st: Dictionary = r.get("stats", {})
			var att := int(st.get("attacks", 0))
			var hit := int(st.get("hits", 0))
			var acc := 0 if att == 0 else roundi(100.0 * float(hit) / float(att))
			row.add_child(_col(str(int(st.get("kos", 0))), COL_NUM, 18, Color(1, 1, 1, 0.8)))
			row.add_child(_col("%d%%" % acc, COL_NUM, 18, Color(1, 1, 1, 0.8)))
	return card


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