extends Control
# Snake Arena - gameplay. Each player gets a floating joystick in their screen zone.

const CELL := 20
const COLS := 56
const ROWS := 32
const MAX_R := 90.0
const DEAD := 22.0
const FOOD_COUNT := 3
const KEYS := [
	{"u": KEY_W, "d": KEY_S, "l": KEY_A, "r": KEY_D},
	{"u": KEY_UP, "d": KEY_DOWN, "l": KEY_LEFT, "r": KEY_RIGHT},
	{"u": KEY_I, "d": KEY_K, "l": KEY_J, "r": KEY_L},
	{"u": KEY_KP_8, "d": KEY_KP_5, "l": KEY_KP_4, "r": KEY_KP_6},
]

var snakes: Array = []
var foods: Array[Vector2i] = []
var scores := [0, 0, 0, 0]
var state := "countdown"   # countdown | playing | paused | round_over | match_over
var prev_state := "countdown"
var countdown := 3.0
var timer := 0.0
var sticks := {}           # player index -> {id, origin, pos}
var zones: Array[Rect2] = []
var hints: Array[Vector2] = []
var arena_pos := Vector2.ZERO
var pause_btn: Button
var overlay_root: CenterContainer
var overlay_box: VBoxContainer
var n_players := 2
var rounds := 3
var wrap_on := false
var step_t := 0.12
var is_client := false
var local: Array = []
var last_winner := -1
var sync_t := 0.0
var last_sent := Vector2i.ZERO
var last_sent_ms := 0


func _ready() -> void:
	n_players = Net.peers.size() if Net.online else Game.players
	rounds = Net.cfg.get("rounds", Game.rounds_to_win) if Net.online else Game.rounds_to_win
	wrap_on = Net.cfg.get("wrap", Game.wrap) if Net.online else Game.wrap
	step_t = Game.step_time()
	is_client = Net.online and not Net.is_host
	if Net.online:
		local = [Net.my_index]
		Net.game = self
		Net.peer_left.connect(_on_peer_left)
		Net.disconnected.connect(_to_menu)
	else:
		for i in n_players:
			local.append(i)

	pause_btn = Game.make_button("II", _pause, Vector2(80, 36), 20)
	pause_btn.visible = not is_client
	add_child(pause_btn)

	overlay_root = CenterContainer.new()
	overlay_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_root.visible = false
	add_child(overlay_root)
	var panel := PanelContainer.new()
	overlay_root.add_child(panel)
	var margin := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 36)
	panel.add_child(margin)
	overlay_box = VBoxContainer.new()
	overlay_box.add_theme_constant_override("separation", 18)
	margin.add_child(overlay_box)

	get_viewport().size_changed.connect(_layout)
	_layout()
	if is_client:
		state = "countdown"
	else:
		_new_round()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_client:
			_to_menu()
		else:
			_pause()


func _layout() -> void:
	var s := get_viewport_rect().size
	arena_pos = ((s - Vector2(COLS * CELL, ROWS * CELL)) / 2.0).floor()
	var h := s / 2.0
	if n_players == 2:
		zones = [Rect2(0, 0, h.x, s.y), Rect2(h.x, 0, h.x, s.y)]
	else:
		zones = [Rect2(0, h.y, h.x, h.y), Rect2(h.x, h.y, h.x, h.y),
				Rect2(0, 0, h.x, h.y), Rect2(h.x, 0, h.x, h.y)]
	if Net.online:
		var full := Rect2(Vector2.ZERO, s)
		zones = [full, full, full, full]
	hints = [Vector2(150, s.y - 150), Vector2(s.x - 150, s.y - 150),
			Vector2(150, 150), Vector2(s.x - 150, 150)]
	pause_btn.position = Vector2(s.x / 2.0 - 40, s.y - 40)


# ---------- round flow ----------

func _new_round() -> void:
	snakes.clear()
	foods.clear()
	sticks.clear()
	var y := ROWS / 2 if n_players == 2 else 0
	var cells := [Vector2i(6, y if y else 26), Vector2i(COLS - 7, y if y else 26),
			Vector2i(6, 5), Vector2i(COLS - 7, 5)]
	var dirs := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.LEFT]
	for i in n_players:
		var body: Array[Vector2i] = []
		for k in 3:
			body.append(cells[i] - dirs[i] * k)
		snakes.append({"body": body, "dir": dirs[i], "next": dirs[i], "alive": true})
	for i in FOOD_COUNT:
		_spawn_food()
	countdown = 3.0
	timer = 0.0
	state = "countdown"
	overlay_root.visible = false


func _spawn_food() -> void:
	for attempt in 200:
		var c := Vector2i(randi() % COLS, randi() % ROWS)
		if foods.has(c):
			continue
		var taken := false
		for s in snakes:
			if s.body.has(c):
				taken = true
				break
		if not taken:
			foods.append(c)
			return


func _end_round(winner: int) -> void:
	last_winner = winner
	if winner >= 0:
		scores[winner] += 1
	if winner >= 0 and scores[winner] >= rounds:
		state = "match_over"
	else:
		state = "round_over"
	_show_result()


func _show_result() -> void:
	var w := last_winner
	var col: Color = Color.WHITE if w < 0 else Game.COLORS[w]
	var items: Array
	if state == "match_over":
		items = [["LEAVE", _to_menu]] if is_client else [["REMATCH", _rematch], ["MENU", _to_menu]]
		_show_overlay("%s wins the match!" % Game.NAMES[maxi(w, 0)], items, col)
	else:
		items = [["LEAVE", _to_menu]] if is_client else [["NEXT ROUND", _new_round]]
		_show_overlay("Draw!" if w < 0 else "%s wins the round!" % Game.NAMES[w], items, col)


func _rematch() -> void:
	scores = [0, 0, 0, 0]
	_new_round()


func _to_menu() -> void:
	Net.leave()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _pause() -> void:
	if state == "playing" or state == "countdown":
		prev_state = state
		state = "paused"
		sticks.clear()
		_show_overlay("PAUSED", [["RESUME", _resume], ["MENU", _to_menu]], Color.WHITE)


func _resume() -> void:
	state = prev_state
	overlay_root.visible = false


func _show_overlay(title: String, items: Array, col: Color) -> void:
	for c in overlay_box.get_children():
		c.queue_free()
	var l := Game.make_label(title, 64)
	l.add_theme_color_override("font_color", col)
	overlay_box.add_child(l)
	for it in items:
		overlay_box.add_child(Game.make_button(it[0], it[1], Vector2(460, 84)))
	overlay_root.visible = true


# ---------- input ----------

func _input(e: InputEvent) -> void:
	if state != "playing" and state != "countdown":
		return
	if e is InputEventScreenTouch:
		if e.pressed:
			if pause_btn.get_global_rect().grow(12).has_point(e.position):
				return
			for i in local:
				if not sticks.has(i) and zones[i].has_point(e.position):
					sticks[i] = {"id": e.index, "origin": e.position, "pos": e.position}
					break
		else:
			for i in sticks.keys():
				if sticks[i].id == e.index:
					sticks.erase(i)
	elif e is InputEventScreenDrag:
		for i in sticks.keys():
			var st: Dictionary = sticks[i]
			if st.id != e.index:
				continue
			st.pos = e.position
			var off: Vector2 = st.pos - st.origin
			if off.length() > MAX_R:
				st.origin = st.pos - off.normalized() * MAX_R   # joystick follows the thumb
				off = st.pos - st.origin
			if off.length() > DEAD:
				if absf(off.x) > absf(off.y):
					_set_dir(i, Vector2i(int(signf(off.x)), 0))
				else:
					_set_dir(i, Vector2i(0, int(signf(off.y))))


func _set_dir(i: int, d: Vector2i) -> void:
	if is_client:
		var now := Time.get_ticks_msec()
		if d != last_sent or now - last_sent_ms > 100:
			last_sent = d
			last_sent_ms = now
			Net.rpc_dir.rpc_id(1, d)
		return
	if i >= snakes.size():
		return
	var s: Dictionary = snakes[i]
	if s.alive and d != -s.dir:
		s.next = d


func _poll_keys() -> void:
	for i in local:
		var sets: Array = [KEYS[0], KEYS[1]] if Net.online else [KEYS[i]]
		for k in sets:
			if Input.is_physical_key_pressed(k.u): _set_dir(i, Vector2i.UP)
			elif Input.is_physical_key_pressed(k.d): _set_dir(i, Vector2i.DOWN)
			elif Input.is_physical_key_pressed(k.l): _set_dir(i, Vector2i.LEFT)
			elif Input.is_physical_key_pressed(k.r): _set_dir(i, Vector2i.RIGHT)


# ---------- simulation ----------

func _process(delta: float) -> void:
	if is_client:
		if state == "countdown" or state == "playing":
			_poll_keys()
		queue_redraw()
		return
	if state == "countdown" or state == "playing":
		_poll_keys()
	if state == "countdown":
		countdown -= delta
		if countdown <= 0.0:
			state = "playing"
	elif state == "playing":
		timer += delta
		while timer >= step_t and state == "playing":
			timer -= step_t
			_step()
	if Net.online:
		sync_t += delta
		if sync_t >= 1.0 / 30.0:
			sync_t = 0.0
			Net.rpc_state.rpc(_pack())
	queue_redraw()


func _step() -> void:
	var heads: Array = []
	var eats: Array = []
	for s in snakes:
		if not s.alive:
			heads.append(null)
			eats.append(false)
			continue
		s.dir = s.next
		var h: Vector2i = s.body[0] + s.dir
		if wrap_on:
			h = Vector2i(posmod(h.x, COLS), posmod(h.y, ROWS))
		heads.append(h)
		eats.append(foods.has(h))

	var dead: Array = []
	for i in snakes.size():
		if heads[i] == null:
			continue
		var h: Vector2i = heads[i]
		var die := h.x < 0 or h.y < 0 or h.x >= COLS or h.y >= ROWS
		if not die:
			for j in snakes.size():
				var o: Dictionary = snakes[j]
				if not o.alive:
					continue
				var limit: int = o.body.size() if eats[j] else o.body.size() - 1
				for k in limit:
					if o.body[k] == h:
						die = true
				if j != i and heads[j] == h:
					die = true
		if die:
			dead.append(i)

	for i in snakes.size():
		if heads[i] == null:
			continue
		var s: Dictionary = snakes[i]
		if dead.has(i):
			s.alive = false
			s.body = [] as Array[Vector2i]
			continue
		s.body.push_front(heads[i])
		if eats[i]:
			foods.erase(heads[i])
			_spawn_food()
		else:
			s.body.pop_back()

	_check_end()


func _check_end() -> void:
	var alive: Array = []
	for i in snakes.size():
		if snakes[i].alive:
			alive.append(i)
	if alive.size() <= 1:
		_end_round(alive[0] if alive.size() == 1 else -1)


func _on_peer_left(i: int) -> void:
	if i >= snakes.size():
		return
	snakes[i].alive = false
	snakes[i].body = [] as Array[Vector2i]
	if state == "playing" or state == "countdown":
		_check_end()


func _pack() -> Dictionary:
	var sn := []
	for s in snakes:
		sn.append({"body": s.body, "dir": s.dir, "alive": s.alive})
	return {"snakes": sn, "foods": foods, "scores": scores, "state": state,
			"cd": countdown, "winner": last_winner}


func apply_state(d: Dictionary) -> void:
	snakes = d.snakes
	foods.assign(d.foods)
	scores = d.scores
	countdown = d.cd
	last_winner = d.winner
	var ns: String = d.state
	if ns == state:
		return
	state = ns
	match ns:
		"countdown":
			last_sent = Vector2i.ZERO
			sticks.clear()
			overlay_root.visible = false
		"playing":
			overlay_root.visible = false
		"paused":
			sticks.clear()
			_show_overlay("PAUSED BY HOST", [["LEAVE", _to_menu]], Color.WHITE)
		"round_over", "match_over":
			_show_result()


# ---------- drawing ----------

func _draw() -> void:
	var s := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, s), Color("#0b1220"))
	var arena := Rect2(arena_pos, Vector2(COLS * CELL, ROWS * CELL))
	draw_rect(arena, Color("#111c33"))
	for x in COLS + 1:
		draw_line(arena_pos + Vector2(x * CELL, 0), arena_pos + Vector2(x * CELL, ROWS * CELL), Color(1, 1, 1, 0.03))
	for y in ROWS + 1:
		draw_line(arena_pos + Vector2(0, y * CELL), arena_pos + Vector2(COLS * CELL, y * CELL), Color(1, 1, 1, 0.03))
	draw_rect(arena, Color("#38bdf8") if wrap_on else Color("#64748b"), false, 3.0)

	for f in foods:
		draw_circle(arena_pos + (Vector2(f) + Vector2(0.5, 0.5)) * CELL, CELL * 0.38, Color("#fb7185"))

	for i in snakes.size():
		var col: Color = Game.COLORS[i]
		var body: Array = snakes[i].body
		for k in body.size():
			var r := Rect2(arena_pos + Vector2(body[k]) * CELL + Vector2(1, 1), Vector2(CELL - 2, CELL - 2))
			draw_rect(r, col.lightened(0.35) if k == 0 else col)
		if body.size() > 0:
			var c := arena_pos + (Vector2(body[0]) + Vector2(0.5, 0.5)) * CELL
			var d := Vector2(snakes[i].dir)
			var perp := Vector2(-d.y, d.x)
			draw_circle(c + d * 3 + perp * 4, 2.5, Color.BLACK)
			draw_circle(c + d * 3 - perp * 4, 2.5, Color.BLACK)

	for i in n_players:
		var col: Color = Game.COLORS[i]
		var a := 1.0 if (i < snakes.size() and snakes[i].alive) else 0.4
		var x := arena_pos.x + i * 260.0
		draw_rect(Rect2(x, arena_pos.y - 28, 16, 16), Color(col, a))
		draw_string(font, Vector2(x + 24, arena_pos.y - 14), "%s%s  %d / %d" % [Game.NAMES[i], " (you)" if Net.online and i == Net.my_index else "", scores[i], rounds],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, a))

	for i in local:
		var col: Color = Game.COLORS[i]
		if sticks.has(i):
			var st: Dictionary = sticks[i]
			draw_circle(st.origin, MAX_R, Color(col, 0.15))
			draw_arc(st.origin, MAX_R, 0, TAU, 48, Color(col, 0.6), 3.0)
			draw_circle(st.origin + (st.pos - st.origin).limit_length(MAX_R), 38, Color(col, 0.7))
		else:
			draw_arc(hints[i], MAX_R, 0, TAU, 48, Color(col, 0.25), 3.0)
			draw_circle(hints[i], 38, Color(col, 0.18))

	if state == "countdown":
		draw_string(font, Vector2(0, s.y / 2.0 + 40), str(ceili(countdown)),
				HORIZONTAL_ALIGNMENT_CENTER, s.x, 130, Color(1, 1, 1, 0.9))
