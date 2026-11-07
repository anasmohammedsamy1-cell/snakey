extends Node
## Knockout mode test (single process, headless). Drives the REAL host logic in round_manager.gd.
## Run: godot --headless --path . res://tests/ko_test.tscn
## Covers: mode selection, match init, scoring, duplicate prevention, simultaneous knockouts, host authority,
## snapshot mirroring (client side), tie-breaks, match completion (target + timer) and the results screen.
## Bots / hazards are frozen so every score change in here is caused by the test itself.

const GameConstants := preload("res://scripts/game_constants.gd")
const ResultsScene := preload("res://scenes/ui/results_screen.tscn")

var _fails := 0
var _results: Array = []
var _headline := ""


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(ok: bool, label: String) -> void:
	if ok:
		print("[KO] PASS  " + label)
	else:
		print("[KO] FAIL  " + label)
		_fails += 1


func _ready() -> void:
	reparent.call_deferred(get_tree().root)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = null
	await _wait(0.5)
	_test_constants_and_ranking()
	_test_mode_selection()
	await _test_results_screen()
	await _test_match_scoring()
	await _test_match_timer_draw()
	print("[KO] finished with %d failure(s)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


# ---------------------------------------------------------------------------

func _entry(id: int, kos: int, falls: int, last_ms: int) -> Dictionary:
	return {"id": id, "kos": kos, "falls": falls, "last_ms": last_ms}


func _test_constants_and_ranking() -> void:
	_check(GameConstants.MODE_KNOCKOUT == 3 and GameConstants.MODE_TRAMPOLINE == 4 and GameConstants.MODE_COUNT == 5, "Trampoline mode extends modes without changing existing ids")
	_check(not GameConstants.uses_teams(GameConstants.MODE_KNOCKOUT) and not GameConstants.uses_teams(GameConstants.MODE_FFA), "KO / classic use no teams")
	_check(GameConstants.uses_teams(GameConstants.MODE_TEAMS) and GameConstants.uses_teams(GameConstants.MODE_HIDE), "team / hide modes still use teams")
	var maps: Array = GameConstants.maps_for_mode(GameConstants.MODE_KNOCKOUT)
	var all_floating := not maps.is_empty()
	for m in maps:
		if int(GameConstants.MAPS[int(m)]["kind"]) != 0:
			all_floating = false
	_check(all_floating, "KO offers the floating arenas only")
	_check(GameConstants.default_round_time(GameConstants.MODE_KNOCKOUT) == GameConstants.KO_DURATION, "KO default duration")
	var trampoline_maps: Array = GameConstants.maps_for_mode(GameConstants.MODE_TRAMPOLINE)
	_check(trampoline_maps.size() == 5, "Trampoline mode exposes five dedicated maps")
	for map_id in trampoline_maps:
		_check(int(GameConstants.MAPS[int(map_id)]["kind"]) == 2, "Trampoline map uses trampoline geometry")
	# Tie-breaks: kos desc -> falls asc -> earlier last knockout -> shared place.
	var r: Array = GameConstants.ko_rank_entries([_entry(1, 3, 2, 9000), _entry(2, 5, 9, 1000), _entry(3, 3, 1, 9500), _entry(4, 3, 1, 8000)])
	_check(int(r[0]["id"]) == 2 and int(r[0]["rank"]) == 1, "most knockouts ranks first")
	_check(int(r[1]["id"]) == 4 and int(r[1]["rank"]) == 2, "tie on knockouts: fewer falls, then earlier last knockout")
	_check(int(r[2]["id"]) == 3 and int(r[2]["rank"]) == 3, "third place")
	_check(int(r[3]["id"]) == 1 and int(r[3]["rank"]) == 4, "last place")
	var t: Array = GameConstants.ko_rank_entries([_entry(1, 2, 1, 5000), _entry(2, 2, 1, 5000), _entry(3, 1, 0, 100)])
	_check(int(t[0]["rank"]) == 1 and int(t[1]["rank"]) == 1 and int(t[2]["rank"]) == 3, "identical stats share first place (competition ranking)")
	var z: Array = GameConstants.ko_rank_entries([_entry(1, 0, 0, -1), _entry(2, 0, 1, -1)])
	_check(int(z[0]["id"]) == 1 and int(z[1]["rank"]) == 2, "no knockouts: fewer falls ranks higher")
	_check(GameConstants.ko_points(1, 4) == 3 and GameConstants.ko_points(2, 1) == 2 and GameConstants.ko_points(4, 1) == 0, "match points 3 / 2 / 1 / 0")
	_check(GameConstants.ko_points(1, 0) == 0, "no knockouts = no match points")
	_check(GameManager.t("mode_ko") != "mode_ko" and _locale_has_ko(), "mode name exists in English and Arabic")


func _locale_has_ko() -> bool:
	var Loc := preload("res://scripts/locale.gd")
	for key in ["mode_ko", "ko_feed", "ko_you_scored", "ko_knocked_out_by", "ko_short", "ko_rank_short", "ko_you_marker"]:
		if Loc.t(key, "ar") == key or Loc.t(key, "en") == key or Loc.t(key, "ar") == Loc.t(key, "en"):
			return false
	return true


func _test_mode_selection() -> void:
	var err := NetworkManager.host_game(GameConstants.DEFAULT_PORT + 40, "ko-test", 4)
	_check(err == "", "host_game for the lobby test (%s)" % err)
	if err != "":
		return
	NetworkManager.set_cfg_value("mode", GameConstants.MODE_KNOCKOUT)
	_check(int(NetworkManager.cfg["mode"]) == GameConstants.MODE_KNOCKOUT, "host selects KNOCKOUT")
	_check(float(NetworkManager.cfg["round_time"]) == GameConstants.KO_DURATION, "KO duration applied to the lobby config")
	_check(GameConstants.maps_for_mode(GameConstants.MODE_KNOCKOUT).has(int(NetworkManager.cfg["map"])), "KO map is a valid floating arena")
	NetworkManager.set_cfg_value("bots", 1)
	_check(NetworkManager.start_problem() == "", "KO can start with host + 1 bot and no team assignment")
	NetworkManager.set_cfg_value("mode", 99)
	_check(int(NetworkManager.cfg["mode"]) == GameConstants.MODE_COUNT - 1, "out-of-range mode is clamped by the host")
	NetworkManager.set_cfg_value("mode", GameConstants.MODE_HIDE)
	_check(float(NetworkManager.cfg["round_time"]) == GameConstants.HS_SEEK_TIME, "hide and seek keeps its own duration")
	NetworkManager.set_cfg_value("mode", GameConstants.MODE_TEAMS)
	_check(NetworkManager.start_problem() == "", "team brawl with a bot still starts")
	var bt: Array = GameManager.make_bot_teams({"mode": GameConstants.MODE_KNOCKOUT, "bots": 3})
	_check(bt.size() == 3 and bt.count(0) == 3, "KO bots are not split into teams")
	NetworkManager.leave()


func _test_results_screen() -> void:
	var rs: Control = ResultsScene.instantiate()
	add_child(rs)
	var rows := [
		{"id": 1, "name": "Alice", "color": 0, "rank": 1, "points": 3, "falls": 1, "kos": 7, "ko_mode": true, "total": 3, "bot": false, "stats": {}},
		{"id": 100, "name": "Bot 1", "color": 2, "rank": 2, "points": 2, "falls": 4, "kos": 5, "ko_mode": true, "total": 0, "bot": true, "stats": {}},
	]
	rs.show_results(rows, "Alice WINS!", false)
	await _frames(3)
	_check(rs.get_child_count() > 0, "results screen renders KO rows without errors")
	rs.queue_free()


# ---------------------------------------------------------------------------

func _freeze(arena: Node) -> void:
	for p in get_tree().get_nodes_in_group("players"):
		p.set_physics_process(false)
	for o in get_tree().get_nodes_in_group("obstacles"):
		o.process_mode = Node.PROCESS_MODE_DISABLED


func _start_ko(time_s: float) -> Node:
	var cfg: Dictionary = GameManager.default_cfg()
	cfg["mode"] = GameConstants.MODE_KNOCKOUT
	cfg["map"] = 0
	cfg["bots"] = 3
	cfg["round_time"] = time_s
	GameManager.start_solo(cfg, false)
	await _wait(5.0)
	var arena := get_tree().current_scene
	if arena == null or arena.name != "Arena":
		return null
	_freeze(arena)
	return arena.get_node("RoundManager")


func _credit(rm: Node, victim: int, by: int, age := 0.0) -> void:
	rm._last_hit_by[victim] = {"by": by, "time": Time.get_ticks_msec() / 1000.0 - age}


func _all_alive(rm: Node) -> bool:
	for id in rm.alive.keys():
		if not bool(rm.alive[id]):
			return false
	return true


func _wait_all_alive(rm: Node) -> void:
	var guard := 0.0
	while not _all_alive(rm) and guard < 6.0:
		await _wait(0.25)
		guard += 0.25
	await _wait(GameConstants.KO_FALL_GRACE + 0.3)   # past the stale-report grace window


func _test_match_scoring() -> void:
	var rm: Node = await _start_ko(60.0)
	_check(rm != null, "KO match: arena loaded")
	if rm == null:
		return
	rm.round_ended.connect(func(results: Array, headline: String) -> void:
		_results = results
		_headline = headline)
	_check(int(rm.mode) == GameConstants.MODE_KNOCKOUT and rm.is_knockout(), "KO match: round manager is in KNOCKOUT mode")
	_check(int(rm.state) == 2 and not rm.practice, "KO match: PLAYING and not practice")
	_check(is_equal_approx(float(rm.round_duration), 60.0), "KO match: timer uses the configured length")
	_check(rm.players.size() == 4 and rm.ko_kos.size() == 4, "KO match: 4 competitors with scores")
	var zero := true
	for id in rm.ko_kos.keys():
		if int(rm.ko_kos[id]) != 0 or int(rm.ko_falls[id]) != 0:
			zero = false
	_check(zero, "KO match: everybody starts on 0 knockouts / 0 falls")
	_check(rm.are_enemies(1, 100) and rm.are_enemies(100, 101) and not rm.are_enemies(1, 1), "KO match: everybody is an enemy (no teams)")

	# 1) validated knockout + duplicate prevention (same frame and later)
	_credit(rm, 100, 1)
	rm._queue_elimination(100)
	rm._queue_elimination(100)
	await _frames(3)
	_check(int(rm.ko_kos[1]) == 1 and int(rm.ko_falls[100]) == 1 and not bool(rm.alive[100]), "knockout counted once for the attacker")
	rm._queue_elimination(100)
	rm._ko_register(100)
	await _frames(3)
	_check(int(rm.ko_kos[1]) == 1 and int(rm.ko_falls[100]) == 1, "duplicate reports of the same fall are ignored")
	_check(not rm.players[100].is_alive, "victim is hidden while waiting to respawn")

	# 2) simultaneous knockouts: two victims, one frame, each exactly once
	_credit(rm, 101, 1)
	_credit(rm, 102, 1)
	rm._queue_elimination(101)
	rm._queue_elimination(102)
	rm._queue_elimination(101)
	await _frames(3)
	_check(int(rm.ko_kos[1]) == 3 and int(rm.ko_falls[101]) == 1 and int(rm.ko_falls[102]) == 1, "simultaneous falls: both credited exactly once")

	# 3) respawn after the delay, with stale-report grace and spawn protection
	var guard := 0.0
	while not _all_alive(rm) and guard < 6.0:
		await _wait(0.1)
		guard += 0.1
	_check(_all_alive(rm) and rm.players[100].is_alive, "knocked-out players respawn after the delay")
	rm._queue_elimination(100)
	await _frames(3)
	_check(bool(rm.alive[100]) and int(rm.ko_falls[100]) == 1, "fall report right after a respawn is ignored (stale packet)")
	_check(float(rm._ko_protect_until.get(100, 0.0)) > float(rm.elapsed) - 0.5, "respawned player has spawn protection")
	rm.players[100].global_position = rm.players[1].global_position + Vector3(1.4, 0, 0)
	rm._server_arm(1, GameConstants.ARM_MODE_PUNCH, 100, Vector3.RIGHT, 0.5)
	_check(not rm._last_hit_by.has(100), "host ignores a punch on a protected player")
	await _wait(GameConstants.KO_SPAWN_PROTECT + 0.3)
	rm.players[100].global_position = rm.players[1].global_position + Vector3(1.4, 0, 0)
	rm._server_arm(1, GameConstants.ARM_MODE_PUNCH, 100, Vector3.RIGHT, 0.5)
	_check(rm._last_hit_by.has(100) and int(rm._last_hit_by[100]["by"]) == 1, "host-validated punch records the attacker")
	rm._queue_elimination(100)
	await _frames(3)
	_check(int(rm.ko_kos[1]) == 4, "knockout from a real validated punch is attributed to the puncher")

	# 4) no credit: self, expired, departed attacker, no hit at all
	await _wait_all_alive(rm)
	_credit(rm, 101, 101)
	_credit(rm, 102, 1, GameConstants.KO_CREDIT_WINDOW + 1.0)
	rm._queue_elimination(101)
	rm._queue_elimination(102)
	await _frames(3)
	_check(int(rm.ko_kos[1]) == 4 and int(rm.ko_kos[101]) == 0, "self credit and expired credit score nothing")
	_check(int(rm.ko_falls[101]) == 2 and int(rm.ko_falls[102]) == 2, "...but the falls are still recorded")
	await _wait_all_alive(rm)
	_credit(rm, 100, 999)
	rm._queue_elimination(100)
	rm._queue_elimination(101)
	await _frames(3)
	var total_kos := 0
	for id in rm.ko_kos.keys():
		total_kos += int(rm.ko_kos[id])
	_check(total_kos == 4, "unknown attacker and an unprovoked fall score nothing")

	# 5) mutual simultaneous knockout
	await _wait_all_alive(rm)
	_credit(rm, 1, 100)
	_credit(rm, 100, 1)
	rm._queue_elimination(1)
	rm._queue_elimination(100)
	await _frames(3)
	_check(int(rm.ko_kos[1]) == 5 and int(rm.ko_kos[100]) == 1, "mutual knockout: both attackers credited once")

	# 6) host authority / client mirroring
	await _wait_all_alive(rm)
	var seq_before: int = rm.ko_seq
	rm.is_host = false
	_credit(rm, 102, 1)
	rm._ko_register(102)
	rm.is_host = true
	rm._last_hit_by.erase(102)
	_check(int(rm.ko_kos[1]) == 5 and int(rm.ko_seq) == seq_before, "a non-host peer cannot register a knockout")
	var snap: Dictionary = rm._ko_snapshot()
	var kos_1_before: int = int(rm.ko_kos[1])
	rm._apply_ko_event(102, 1, seq_before, snap)
	_check(int(rm.ko_kos[1]) == kos_1_before and rm.players[102].is_alive, "an event with an old sequence number is ignored (idempotent)")
	snap[1][0] = 42
	snap[102][3] = 0
	rm._apply_ko_event(102, 1, seq_before + 1, snap)
	_check(int(rm.ko_kos[1]) == 42 and not rm.players[102].is_alive, "mirrored events take the host snapshot (no local increment)")
	rm._apply_ko_event(102, 1, seq_before + 1, snap)
	_check(int(rm.ko_kos[1]) == 42, "replaying the same event changes nothing")
	rm._apply_ko_respawn(102, rm.players[1].global_position + Vector3(3, 0, 0))
	rm.ko_kos[1] = 5   # undo the fake host snapshot value for the remaining checks
	rm.ko_seq = maxi(rm.ko_seq, seq_before + 1)

	# 7) live standings
	var st: Array = rm.ko_standings()
	_check(int(st[0]["id"]) == 1 and int(st[0]["rank"]) == 1 and st.size() == 4, "standings: leader first")

	# 8) victory: first to the target ends the match immediately
	await _wait_all_alive(rm)
	rm.ko_kos[1] = GameConstants.KO_TARGET_SCORE - 1
	_credit(rm, 100, 1)
	rm._queue_elimination(100)
	await _frames(4)
	_check(bool(rm._ended) and int(rm.state) == 3, "reaching the target score ends the match")
	await _wait(0.3)
	_check(_results.size() == 4 and int(_results[0]["id"]) == 1 and int(_results[0]["rank"]) == 1, "final ranking: winner first")
	_check(bool(_results[0].get("ko_mode", false)) and int(_results[0]["kos"]) == GameConstants.KO_TARGET_SCORE, "results carry the knockout count")
	_check(int(_results[0]["points"]) == 3, "winner gets 3 match points")
	_check(_headline.contains(str(_results[0]["name"])), "headline names the winner")
	# no scoring after the match ended
	var frozen_kos: int = int(rm.ko_kos[1])
	_credit(rm, 101, 1)
	rm._queue_elimination(101)
	rm._ko_register(101)
	await _frames(3)
	_check(int(rm.ko_kos[1]) == frozen_kos, "no knockouts count after the match ended")
	await _wait(2.5)
	var hud: Node = get_tree().current_scene.get("hud")
	_check(hud != null and hud.get("_results") != null, "results screen is shown after the match")


func _test_match_timer_draw() -> void:
	var rm: Node = await _start_ko(30.0)
	_check(rm != null, "timer match: arena loaded")
	if rm == null:
		return
	_results = []
	rm.round_ended.connect(func(results: Array, headline: String) -> void:
		_results = results
		_headline = headline)
	_check(is_equal_approx(float(rm.round_duration), 30.0), "timer match: 30 s")
	await _wait(31.5)
	_check(int(rm.state) == 3, "match ends when the timer runs out")
	_check(_results.size() == 4, "timer match: results for everybody")
	var all_first := true
	var no_points := true
	for r in _results:
		if int(r["rank"]) != 1:
			all_first = false
		if int(r["points"]) != 0:
			no_points = false
	_check(all_first, "nobody scored: shared first place (draw)")
	_check(no_points, "a scoreless draw awards no match points")
	_check(_headline == GameManager.t("draw"), "draw headline")
