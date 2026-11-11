extends Node
## Round flow. The HOST (peer 1, or the local game in practice mode) is the
## single source of truth for: state, timer, eliminations, ranks, winner, pushes.
## Clients mirror the state through "authority" RPCs and only send requests.

const GameConstants := preload("res://scripts/game_constants.gd")
const PlayerScene := preload("res://scenes/player.tscn")
const PropsLib := preload("res://scripts/props.gd")
const PowerupsScript := preload("res://scripts/powerups.gd")
const AccessoriesLib := preload("res://scripts/accessories.gd")
const THROW_RELEASE_DELAY := GameConstants.THROW_TOTAL_TIME   # 2x faster wind-up + release; matches ContenderAnimator.THROW_TOTAL

enum State { WAITING, COUNTDOWN, PLAYING, ENDED }

signal state_changed(state: int)
signal timer_updated(remaining: float)
signal player_eliminated(peer_id: int, player_name: String, alive_count: int)
signal round_ended(results: Array, headline: String)
signal announce(text: String, duration: float)
signal local_player_eliminated
signal players_changed
signal knockout_scored(killer_id: int, victim_id: int, killer_name: String, victim_name: String)

@export var countdown_time := 2.4
@export var ready_timeout := 8.0

var state: int = State.WAITING
var round_duration: float = GameConstants.ROUND_DURATION
var elapsed := 0.0
var remaining: float = GameConstants.ROUND_DURATION
var countdown_left := 0.0
var practice := false
var powerups: Node            # floor power-ups (scripts/powerups.gd)
var is_host := true

var players: Dictionary = {}     # id -> player node
var alive: Dictionary = {}       # id -> bool
var ranks: Dictionary = {}       # id -> int
var falls: Dictionary = {}       # id -> int (practice)
var local_player: Node = null
var arena: Node3D = null

var _ready_peers: Dictionary = {}
var _ready_wait := 0.0
var _time_sync_accum := 0.0
var _pending_elims: Array = []
var _last_push_time: Dictionary = {}
var stats: Dictionary = {}       # id -> {attacks,hits,grabs,escapes,dodges,kos}  (host-authoritative)
var _grabs: Dictionary = {}      # attacker id -> {"target": int, "t": float}
var _escape_attempts: Dictionary = {} # target id -> {"count": int, "last": float}
var _last_hit_by: Dictionary = {}  # victim id -> {"by": int, "time": float}
var _ended := false
var _cd_phase := 0

# Game mode / teams / hide and seek
var mode: int = GameConstants.MODE_FFA
var cfg: Dictionary = {}
var team_of: Dictionary = {}       # id -> team index
var hs_props: Dictionary = {}      # hider id -> prop id (host decides, everybody mirrors)
var _hs_hugs: Dictionary = {}      # hider id -> {"seeker": id, "t": float}
var _hs_seek_announced := false
var bot_count := 0

# Knockout mode. The HOST is the only writer; clients mirror host snapshots (never increment locally).
var ko_kos: Dictionary = {}        # id -> validated knockouts
var ko_falls: Dictionary = {}      # id -> times knocked out / fallen
var ko_last_ms: Dictionary = {}    # id -> host time (ms) of the latest knockout, -1 = none yet
var ko_seq := 0                    # host: number of validated knockout events so far
var _ko_applied_seq := 0           # last event number applied on this peer (makes mirroring idempotent)
var _ko_respawn_at: Dictionary = {}    # host: id -> elapsed time when the respawn happens
var _ko_protect_until: Dictionary = {} # host: id -> elapsed time until hits are ignored

# Host-driven arena modifiers. Clients only mirror the selected modifier via RPC.
enum ArenaEvent { NONE, LOW_GRAVITY, SPEED_SURGE, SLIPPERY_FLOOR, DASH_FRENZY, TILE_TREMOR }
var current_event: int = ArenaEvent.NONE
var event_remaining := 0.0
var _event_cycle_timer := 16.0
var _last_event := ArenaEvent.NONE
var _sd_active := false           # Sudden Death: the outer floor tiers / tiles start to crumble in the last quarter
var _sd_timer := 0.0
var _sd_loose_guard := 2          # never drop the last few crumbling tiles: the round must stay playable
var _sd_pieces: Array[Node] = []  # cached arena_crumble_tiles list; rebuilt once per round
var _sd_scanned := false
var _last_timer_secs: int = -1    # timer_updated is only emitted when the displayed value changes
var _last_timer_flash: int = -1
var _music_accum := 1.0           # music intensity is recomputed at 4 Hz (1.0 forces an immediate first pass)


func setup(arena_node: Node3D) -> void:
	arena = arena_node
	cfg = GameManager.get_match_config()
	mode = int(cfg.get("mode", GameConstants.MODE_FFA))
	bot_count = int(cfg.get("bots", 0))
	practice = GameManager.practice_mode and mode == GameConstants.MODE_FFA
	is_host = multiplayer.is_server()
	if mode == GameConstants.MODE_HIDE:
		round_duration = GameConstants.HS_SEEK_TIME
	elif practice:
		round_duration = GameConstants.PRACTICE_DURATION
	elif mode == GameConstants.MODE_KNOCKOUT:
		round_duration = clampf(float(cfg.get("round_time", GameConstants.KO_DURATION)), 30.0, 300.0)
	elif mode == GameConstants.MODE_TRAMPOLINE:
		round_duration = clampf(float(cfg.get("round_time", GameConstants.TRAMPOLINE_DURATION)), 30.0, 300.0)
	else:
		round_duration = float(cfg.get("round_time", GameConstants.ROUND_DURATION))
	remaining = round_duration
	_build_teams()
	_spawn_all()
	powerups = PowerupsScript.new()
	powerups.name = "PowerUps"          # same node path on every peer (needed for the RPCs)
	add_child(powerups)
	powerups.setup(self)
	if mode == GameConstants.MODE_HIDE and is_host:
		_hs_assign_props()
	if NetworkManager.online:
		NetworkManager.player_left.connect(_on_player_left)
	if is_host:
		_ready_peers[1] = true
		if not NetworkManager.online:
			_begin_countdown()
	else:
		_announce_client_ready()
	state_changed.emit(state)
	if practice:
		announce.emit(GameManager.t("practice_tip"), 4.0)


## Same result on every peer: humans come from the lobby snapshot, bots from the host's config.
func _build_teams() -> void:
	team_of.clear()
	var ids: Array = NetworkManager.get_sorted_ids() if NetworkManager.online else [1]
	for id in ids:
		var info: Dictionary = NetworkManager.get_player_info(int(id))
		var tm := int(info.get("team", 0))
		if not NetworkManager.online:
			tm = int(cfg.get("solo_team", 0))
		team_of[int(id)] = clampi(tm, 0, 3)
	var bt: Array = cfg.get("bot_teams", [])
	for b in bot_count:
		team_of[100 + b] = clampi(int(bt[b]) if b < bt.size() else 0, 0, 3)


func is_team_mode() -> bool:
	return GameConstants.uses_teams(mode)


func is_knockout() -> bool:
	return mode == GameConstants.MODE_KNOCKOUT


## Modes where falling scores a knockout and the player respawns instead of being eliminated.
func is_respawn_score_mode() -> bool:
	return mode == GameConstants.MODE_KNOCKOUT or mode == GameConstants.MODE_TRAMPOLINE


func hider_team() -> int:
	return int(cfg.get("hider_team", 0))


func role_of(id: int) -> int:
	if mode != GameConstants.MODE_HIDE:
		return GameConstants.HS_ROLE_NONE
	return GameConstants.HS_ROLE_HIDER if int(team_of.get(id, 0)) == hider_team() else GameConstants.HS_ROLE_SEEKER


## Seekers cannot move while the hiders run and hide.
func is_locked(p: Node) -> bool:
	return mode == GameConstants.MODE_HIDE and state == State.PLAYING and elapsed < GameConstants.HS_HIDE_TIME and int(p.role) == GameConstants.HS_ROLE_SEEKER


func hide_time_left() -> float:
	if mode != GameConstants.MODE_HIDE or state != State.PLAYING:
		return 0.0
	return maxf(GameConstants.HS_HIDE_TIME - elapsed, 0.0)


func _announce_client_ready() -> void:
	# Give the host a moment to finish loading its own arena.
	await get_tree().create_timer(0.4).timeout
	if is_inside_tree() and NetworkManager.online:
		_rpc_client_ready.rpc_id(1)


func t(key: String) -> String:
	return GameManager.t(key)


# ---------------------------------------------------------------------------
# Spawning

func _spawn_all() -> void:
	var ids: Array = []
	if NetworkManager.online:
		ids = NetworkManager.get_sorted_ids()
	else:
		ids = [1]
	var counters := [0, 0]
	for id in ids:
		var info: Dictionary = NetworkManager.get_player_info(int(id))
		var name_text := str(info.get("name", "Player"))
		var color := int(info.get("color", 0))
		var hat := str(info.get("hat", ""))
		var detail := int(info.get("detail", -1))
		if not NetworkManager.online:
			name_text = SaveManager.player_name
			color = SaveManager.color_index
			hat = SaveManager.equipped_hat
			detail = SaveManager.detail_color_index
		var grp := 1 if role_of(int(id)) == GameConstants.HS_ROLE_SEEKER else 0
		_spawn_player(int(id), name_text, color, false, counters[grp], grp, hat, detail)
		counters[grp] += 1
	for b in bot_count:
		var bid := 100 + b
		var bgrp := 1 if role_of(bid) == GameConstants.HS_ROLE_SEEKER else 0
		var base_color := SaveManager.color_index
		var bot_hats: Array = AccessoriesLib.ids()
		var bot_hat: String = str(bot_hats[(b * 3 + 1) % bot_hats.size()]) if b % 2 == 0 else ""
		_spawn_player(bid, "Bot %d" % (b + 1), (base_color + 1 + b * 2) % GameConstants.color_count(), true, counters[bgrp], bgrp, bot_hat)
		counters[bgrp] += 1
	players_changed.emit()


func _spawn_player(id: int, pname: String, color: int, bot: bool, spawn_index: int, group := 0, hat := "", detail := -1) -> void:
	var p := PlayerScene.instantiate()
	var tm := int(team_of.get(id, 0))
	if is_team_mode() and mode == GameConstants.MODE_TEAMS:
		color = GameConstants.team_color_index(tm)     # team colour on the whole character
	p.setup(id, pname, color, bot, detail)
	p.hat_id = hat
	p.set_team_info(tm, mode == GameConstants.MODE_TEAMS, role_of(id))
	p.round_manager = self
	arena.get_node("Players").add_child(p)
	var sp: Vector3 = arena.get_spawn_point(spawn_index, group)
	p.global_position = sp
	p.face_direction(-sp)
	players[id] = p
	alive[id] = true
	falls[id] = 0
	stats[id] = {"attacks": 0, "hits": 0, "grabs": 0, "escapes": 0, "dodges": 0, "kos": 0}
	ko_kos[id] = 0
	ko_falls[id] = 0
	ko_last_ms[id] = -1
	if p.is_local:
		local_player = p


# ---------------------------------------------------------------------------
# Main loop

func _process(delta: float) -> void:
	match state:
		State.WAITING:
			if is_host and NetworkManager.online:
				_ready_wait += delta
				if _all_clients_ready() or _ready_wait > ready_timeout:
					_begin_countdown()
		State.COUNTDOWN:
			countdown_left -= delta
			_update_countdown_phase()
			if is_host and countdown_left <= 0.0:
				_begin_playing()
		State.PLAYING:
			elapsed += delta
			if mode == GameConstants.MODE_HIDE:
				remaining = maxf(round_duration - maxf(elapsed - GameConstants.HS_HIDE_TIME, 0.0), 0.0)
				if not _hs_seek_announced and elapsed >= GameConstants.HS_HIDE_TIME:
					_hs_seek_announced = true
					announce.emit(t("hs_seekers_go"), 1.8)
					AudioManager.play_ui("go", 0.0)
			else:
				remaining = maxf(round_duration - elapsed, 0.0)
			# Emit only when the displayed value changes: whole-second ticks, plus the
			# blink phase while the timer is in the <=10s red-flash window (HUD derives
			# text and color entirely from the received `remaining`).
			var timer_secs := int(ceil(remaining))
			var timer_flash := (int(remaining * 2.0) % 2) if remaining <= 10.0 else -1
			if timer_secs != _last_timer_secs or timer_flash != _last_timer_flash:
				_last_timer_secs = timer_secs
				_last_timer_flash = timer_flash
				timer_updated.emit(remaining)
			_music_accum += delta
			if _music_accum >= 0.25:
				_music_accum = 0.0
				_update_music_intensity()
			if is_host:
				_host_check_falls()
				_process_grabs(delta)
				_process_hugs(delta)
				_process_pending_elims()
				_ko_process_respawns()
				_process_arena_events(delta)
				_process_sudden_death(delta)
				if NetworkManager.online:
					_time_sync_accum += delta
					if _time_sync_accum >= 0.5:
						_time_sync_accum = 0.0
						_rpc_time_sync.rpc(elapsed)
				if remaining <= 0.0:
					_end_round("time_up")
			elif current_event != ArenaEvent.NONE:
				event_remaining = maxf(0.0, event_remaining - delta)
		_:
			pass


# ---------------------------------------------------------------------------
# Arena events — short, readable gameplay twists. The host selects and broadcasts
# the event; movement modifiers are applied locally by each authoritative player.

## Last 25 % of a classic / team round on a "shrinkable" map: the floor really gives way, so the
## safe area shrinks and the survivors are forced together instead of waiting out the clock.
## Two kinds of pieces cooperate, and both use the same host-authority flow:
##   * arena_layer.gd  - whole floor tiers (outermost first, one per tick);
##   * falling_tile.gd - single crumbling tiles (up to 3 per tick, farthest first).
## Maps that cannot shrink simply never announce it (see "shrinkable" in map_builder.gd).
## Layered music: calm -> tension (last 30 s or <= 4 players left) -> chaos (Sudden Death). Runs on every peer.
func _update_music_intensity() -> void:
	if mode == GameConstants.MODE_HIDE:
		AudioManager.set_music_intensity(1 if remaining < 20.0 else 0)
		return
	var level := 0
	if remaining < 30.0 or (not is_respawn_score_mode() and players.size() > 4 and _count_alive() <= 4):
		level = 1
	if _sd_active or (remaining < 10.0 and not is_respawn_score_mode()):
		level = 2
	AudioManager.set_music_intensity(level)


func _exit_tree() -> void:
	Engine.time_scale = 1.0              # never leave a hit-stop running when the round scene goes away
	AudioManager.set_music_intensity(0)


func _process_sudden_death(delta: float) -> void:
	if mode == GameConstants.MODE_HIDE or is_respawn_score_mode():
		return
	if not bool(_map_info().get("shrinkable", false)):
		return
	if remaining > round_duration * 0.25:
		return
	if not _sd_scanned:
		_sd_scanned = true
		for node in get_tree().get_nodes_in_group("arena_crumble_tiles"):
			if node.has_method("can_be_event_triggered"):
				_sd_pieces.append(node)
	var pieces: Array[Node] = []
	for p in _sd_pieces:
		if is_instance_valid(p) and p.can_be_event_triggered():
			pieces.append(p)
	_sd_pieces = pieces  # drop freed/dropped tiles so later ticks stay cheap
	if pieces.is_empty():
		return
	if not _sd_active:
		_sd_active = true
		_sd_timer = 1.5
		_sd_loose_guard = maxi(2, int(round(_count_loose(pieces) * 0.25)))
		announce.emit(t("sudden_death"), 1.8)
		AudioManager.play("alarm", 0.0, -3.0)
		if NetworkManager.online:
			_rpc_sudden_death.rpc()
		return
	_sd_timer -= delta
	if _sd_timer > 0.0:
		return
	_sd_timer = 2.4
	# Whole floor tiers go first, one per tick: that is the big, readable "the arena just got smaller".
	var tier: Node = _next_tier(pieces)
	if tier != null:
		_collapse_piece(tier)
		return
	var loose := _loose_pieces(pieces)
	if loose.size() <= _sd_loose_guard:
		return
	loose.sort_custom(func(a, b) -> bool: return _piece_rank(a) > _piece_rank(b))
	for i in mini(3, loose.size()):
		_collapse_piece(loose[i])


## True on maps that can actually shrink (used by the HUD/tests).
func sudden_death_supported() -> bool:
	return bool(_map_info().get("shrinkable", false))


func _map_info() -> Dictionary:
	if arena == null or not is_instance_valid(arena):
		return {}
	var info: Variant = arena.get("map_info")
	return info if info is Dictionary else {}


## Higher rank = collapses first. Floor tiers return ~1e9 so they always beat single tiles.
func _piece_rank(piece: Node) -> float:
	if piece.has_method("collapse_rank"):
		return float(piece.call("collapse_rank"))
	return piece.global_position.length_squared()


func _is_tier(piece: Node) -> bool:
	return piece.has_method("collapse_rank")


func _next_tier(pieces: Array) -> Node:
	var best: Node = null
	var best_rank := -1.0
	for piece in pieces:
		if not _is_tier(piece):
			continue
		var rank := _piece_rank(piece)
		if rank > best_rank:
			best_rank = rank
			best = piece
	return best


func _loose_pieces(pieces: Array) -> Array:
	var out: Array = []
	for piece in pieces:
		if not _is_tier(piece):
			out.append(piece)
	return out


func _count_loose(pieces: Array) -> int:
	return _loose_pieces(pieces).size()


func _collapse_piece(piece: Node) -> void:
	piece.trigger()
	if NetworkManager.online:
		piece._rpc_trigger.rpc()


@rpc("authority", "call_remote", "reliable")
func _rpc_sudden_death() -> void:
	_sd_active = true
	announce.emit(t("sudden_death"), 1.8)
	AudioManager.play("alarm", 0.0, -3.0)


func _process_arena_events(delta: float) -> void:
	if mode == GameConstants.MODE_HIDE:
		return
	if current_event != ArenaEvent.NONE:
		event_remaining = maxf(0.0, event_remaining - delta)
		if event_remaining <= 0.0:
			_set_arena_event(ArenaEvent.NONE, 0.0)
			_event_cycle_timer = _adaptive_event_interval()
		return
	_event_cycle_timer -= delta
	if _event_cycle_timer <= 0.0:
		_start_random_arena_event()


func _adaptive_event_interval() -> float:
	# The Arena Director increases event cadence as the round progresses, but
	# gives the final survivors a little more breathing room instead of piling
	# hazards onto a single player. This is host-only gameplay pacing.
	var progress := clampf(elapsed / maxf(round_duration, 1.0), 0.0, 1.0)
	var interval := lerpf(16.0, 11.0, progress)
	var total_players := maxi(players.size(), 1)
	var survivor_ratio := float(_count_alive()) / float(total_players)
	if survivor_ratio <= 0.25:
		interval += 2.0
	return clampf(interval, 10.0, 18.0)


func _start_random_arena_event() -> void:
	var choices := [ArenaEvent.LOW_GRAVITY, ArenaEvent.SPEED_SURGE, ArenaEvent.SLIPPERY_FLOOR, ArenaEvent.DASH_FRENZY]
	# Tile tremors only make sense on maps that actually contain crumble tiles.
	if not get_tree().get_nodes_in_group("arena_crumble_tiles").is_empty():
		choices.append(ArenaEvent.TILE_TREMOR)
	if choices.has(_last_event) and choices.size() > 1:
		choices.erase(_last_event)
	var chosen: int = choices[randi() % choices.size()]
	_last_event = chosen
	_set_arena_event(chosen, 9.0)
	if chosen == ArenaEvent.TILE_TREMOR:
		_trigger_tile_tremor()


func _trigger_tile_tremor() -> void:
	# The host selects a small random subset; each tile uses its own reliable
	# authority RPC so every peer observes the exact same collapse sequence.
	if not is_host:
		return
	var candidates: Array[Node] = []
	for node in get_tree().get_nodes_in_group("arena_crumble_tiles"):
		if node.has_method("can_be_event_triggered") and node.can_be_event_triggered():
			candidates.append(node)
	if candidates.is_empty():
		return
	candidates.shuffle()
	var trigger_count := mini(4, maxi(2, int(ceil(float(candidates.size()) * 0.18))))
	for i in mini(trigger_count, candidates.size()):
		var tile: Node = candidates[i]
		# RPC is call_remote, so the host must trigger its local copy explicitly.
		# Otherwise only clients see the selected tiles collapse.
		tile.trigger()
		if NetworkManager.online:
			tile._rpc_trigger.rpc()


func _set_arena_event(event_id: int, duration: float) -> void:
	_apply_arena_event(event_id, duration)
	if NetworkManager.online:
		_rpc_set_arena_event.rpc(event_id, duration)


@rpc("authority", "call_remote", "reliable")
func _rpc_set_arena_event(event_id: int, duration: float) -> void:
	_apply_arena_event(event_id, duration)


func _apply_arena_event(event_id: int, duration: float) -> void:
	# Clamp network-provided values so malformed packets cannot create invalid state.
	current_event = clampi(event_id, ArenaEvent.NONE, ArenaEvent.TILE_TREMOR)
	event_remaining = clampf(duration, 0.0, 30.0)
	match current_event:
		ArenaEvent.LOW_GRAVITY:
			announce.emit(t("event_low_gravity"), 2.5)
		ArenaEvent.SPEED_SURGE:
			announce.emit(t("event_speed_surge"), 2.5)
		ArenaEvent.SLIPPERY_FLOOR:
			announce.emit(t("event_slippery"), 2.5)
		ArenaEvent.DASH_FRENZY:
			announce.emit(t("event_dash_frenzy"), 2.5)
		ArenaEvent.TILE_TREMOR:
			announce.emit(t("event_tile_tremor"), 2.8)
		_:
			pass


func _all_clients_ready() -> bool:
	for id in NetworkManager.players.keys():
		if not _ready_peers.has(id):
			return false
	return true


func _update_countdown_phase() -> void:
	if _cd_phase == 0:
		_cd_phase = 1
		announce.emit(t("ready_txt"), 1.1)
		AudioManager.play_ui("countdown", 0.0)
	elif _cd_phase == 1 and countdown_left <= countdown_time * 0.5:
		_cd_phase = 2
		announce.emit(t("set_txt"), 1.1)
		AudioManager.play_ui("countdown", 0.0, 2.0)


# ---------------------------------------------------------------------------
# State transitions (host) + mirrored application (everyone)

func _begin_countdown() -> void:
	if state != State.WAITING:
		return
	_apply_state(State.COUNTDOWN)
	if NetworkManager.online:
		_rpc_set_state.rpc(State.COUNTDOWN)


func _begin_playing() -> void:
	if state != State.COUNTDOWN:
		return
	_apply_state(State.PLAYING)
	if NetworkManager.online:
		_rpc_set_state.rpc(State.PLAYING)


func _apply_state(new_state: int) -> void:
	state = new_state
	if new_state != State.PLAYING:
		AudioManager.set_music_intensity(0)
	match new_state:
		State.COUNTDOWN:
			countdown_left = countdown_time
			_cd_phase = 0
		State.PLAYING:
			elapsed = 0.0
			remaining = round_duration
			# Start the arena-event clock from the actual PLAYING transition,
			# not from scene construction (loading/countdown time must not consume it).
			_event_cycle_timer = _adaptive_event_interval()
			_last_event = ArenaEvent.NONE
			_sd_active = false
			_sd_pieces.clear()
			_sd_scanned = false
			_last_timer_secs = -1
			_last_timer_flash = -1
			_music_accum = 1.0
			if is_host:
				_set_arena_event(ArenaEvent.NONE, 0.0)
			else:
				_apply_arena_event(ArenaEvent.NONE, 0.0)
			if mode == GameConstants.MODE_HIDE and local_player != null:
				announce.emit(t("hs_hide_now") if int(local_player.role) == GameConstants.HS_ROLE_HIDER else t("hs_blindfold"), 2.5)
			else:
				announce.emit(t("go"), 1.0)
			AudioManager.play_ui("go", 0.0)
		_:
			pass
	state_changed.emit(state)


@rpc("authority", "call_remote", "reliable")
func _rpc_set_state(new_state: int) -> void:
	_apply_state(new_state)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_time_sync(host_elapsed: float) -> void:
	if state != State.PLAYING:
		return
	if absf(host_elapsed - elapsed) > 0.3:
		elapsed = host_elapsed
	else:
		elapsed = lerpf(elapsed, host_elapsed, 0.25)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_ready() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	_ready_peers[sender] = true
	if mode == GameConstants.MODE_HIDE:
		_rpc_hs_props.rpc_id(sender, hs_props)
	# Late joiner (slow load): bring them up to date.
	if state != State.WAITING:
		_rpc_set_state.rpc_id(sender, state)
		if state == State.PLAYING:
			_rpc_time_sync.rpc_id(sender, elapsed)
		if is_respawn_score_mode():
			_rpc_ko_snapshot.rpc_id(sender, ko_seq, _ko_snapshot())


# ---------------------------------------------------------------------------
# Falls / eliminations

## Called by the authority of a player when it drops below the fall height.
func report_fall(p: Node) -> void:
	if practice:
		_on_practice_fall(p)
		return
	if is_host:
		_queue_elimination(p.peer_id)
	else:
		_rpc_report_fall.rpc_id(1, p.peer_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_report_fall(id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != id or not players.has(id):
		return # you may only report your own fall
	var p: Node = players[id]
	# Validate against the host's copy (tolerant: the puppet lags a little).
	if p.global_position.y > GameConstants.FALL_Y + 8.0:
		return
	_queue_elimination(id)


## Host backup: catches players whose fall report got lost.
func _host_check_falls() -> void:
	for id in alive.keys():
		if not alive[id]:
			continue
		var p: Node = players.get(id)
		if p != null and p.global_position.y < GameConstants.FALL_Y - 3.0:
			_queue_elimination(int(id))


func _queue_elimination(id: int) -> void:
	if state != State.PLAYING or not bool(alive.get(id, false)):
		return
	if _pending_elims.has(id):
		return
	if is_respawn_score_mode() and elapsed < float(_ko_protect_until.get(id, -1.0)) - GameConstants.KO_SPAWN_PROTECT + GameConstants.KO_FALL_GRACE:
		return # stale fall report from before the respawn
	_pending_elims.append(id)


## Eliminations are processed once per frame so simultaneous falls share a rank.
func _process_pending_elims() -> void:
	if _pending_elims.is_empty():
		return
	if is_respawn_score_mode():
		_ko_process_pending()
		return
	var alive_count := _count_alive()
	var batch: Array = _pending_elims.duplicate()
	_pending_elims.clear()
	var rank := alive_count
	if batch.size() >= alive_count:
		rank = 1 # everybody left fell together: shared first place (draw)
	for id in batch:
		_eliminate(int(id), rank)
		if NetworkManager.online:
			_rpc_eliminate.rpc(int(id), rank)
	_check_end()


@rpc("authority", "call_remote", "reliable")
func _rpc_eliminate(id: int, rank: int) -> void:
	_eliminate(id, rank)


func _eliminate(id: int, rank: int) -> void:
	if not bool(alive.get(id, false)):
		return
	alive[id] = false
	ranks[id] = rank
	for aid in _grabs.keys():
		if aid == id or int(_grabs[aid]["target"]) == id:
			_release_grab(int(aid))
	if is_host and _last_hit_by.has(id):
		var lh: Dictionary = _last_hit_by[id]
		if Time.get_ticks_msec() / 1000.0 - float(lh["time"]) <= 5.0 and stats.has(int(lh["by"])):
			var kst: Dictionary = stats[int(lh["by"])]
			kst["kos"] = int(kst["kos"]) + 1
	var p: Node = players.get(id)
	var pname := "?"
	if p != null:
		pname = p.player_name
		if mode == GameConstants.MODE_HIDE:
			if arena != null:
				arena.spawn_splash(p.global_position + Vector3(0, 0.3, 0))
			p.become_puddle()
		else:
			if arena != null and arena.has_method("spawn_poof"):
				arena.spawn_poof(p.last_position + Vector3(0, 1, 0))
			p.eliminate()
		if p.is_local:
			local_player_eliminated.emit()
	if p != null:
		AudioManager.play_character_3d("fall", (p as Node3D).global_position)
	else:
		AudioManager.play_character("fall", 0.05)
	player_eliminated.emit(id, pname, _count_alive())
	players_changed.emit()


func _count_alive() -> int:
	var n := 0
	for id in alive.keys():
		if alive[id]:
			n += 1
	return n


func _check_end() -> void:
	if practice or _ended:
		return
	if mode == GameConstants.MODE_HIDE:
		var hiders := _count_alive_role(GameConstants.HS_ROLE_HIDER)
		var seekers := _count_alive_role(GameConstants.HS_ROLE_SEEKER)
		if hiders == 0:
			_end_round("seekers_win")
		elif seekers == 0:
			_end_round("hiders_win")
		return
	if is_respawn_score_mode():
		_ko_check_end()
		return
	if mode == GameConstants.MODE_TEAMS:
		var teams_alive := _alive_teams()
		if teams_alive.size() <= 1:
			_end_round("team_win" if teams_alive.size() == 1 else "draw")
		return
	var n := _count_alive()
	if players.size() >= 2 and n <= 1:
		_end_round("last_standing")
	elif n == 0:
		_end_round("draw")


func _count_alive_role(r: int) -> int:
	var n := 0
	for id in alive.keys():
		if bool(alive[id]) and role_of(int(id)) == r:
			n += 1
	return n


func _alive_teams() -> Array:
	var out: Array = []
	for id in alive.keys():
		if bool(alive[id]):
			var tm := int(team_of.get(int(id), 0))
			if not out.has(tm):
				out.append(tm)
	return out


func _on_practice_fall(p: Node) -> void:
	var id: int = p.peer_id
	falls[id] = int(falls.get(id, 0)) + 1
	if arena != null:
		arena.spawn_poof(p.last_position + Vector3(0, 1, 0))
	p.eliminate()
	if p != null:
		AudioManager.play_character_3d("fall", (p as Node3D).global_position)
	else:
		AudioManager.play_character("fall", 0.05)
	if p.is_local:
		announce.emit(t("you_fell"), 1.5)
	player_eliminated.emit(id, p.player_name, _count_alive())
	await get_tree().create_timer(1.6).timeout
	if not is_inside_tree() or not is_instance_valid(p):
		return
	if state == State.PLAYING or state == State.COUNTDOWN:
		var sp: Vector3 = arena.get_spawn_point(randi() % 8)
		p.respawn(sp)
		players_changed.emit()


# ---------------------------------------------------------------------------
# Rubber arm validation (host authoritative)
# Clients only REQUEST an attack (mode + the target they aimed at). The host re-checks
# state, cooldown, distance, line of sight and dodge frames, then decides the outcome.
# One request can hit at most one target, and the server cooldown caps the request rate,
# so a hit can never be registered twice.

func are_enemies(a_id: int, b_id: int) -> bool:
	if a_id == b_id:
		return false
	if mode == GameConstants.MODE_FFA or mode == GameConstants.MODE_KNOCKOUT or mode == GameConstants.MODE_TRAMPOLINE:
		return true
	return int(team_of.get(a_id, 0)) != int(team_of.get(b_id, 0))   # no friendly fire in team modes


func request_arm(attacker: Node, arm_mode: int, target_id: int, dir: Vector3, charge := 0.5) -> void:
	if is_host:
		_server_arm(attacker.peer_id, arm_mode, target_id, dir, charge)
	else:
		_rpc_request_arm.rpc_id(1, arm_mode, target_id, dir, charge)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_arm(arm_mode: int, target_id: int, dir: Vector3, charge: float) -> void:
	if not multiplayer.is_server():
		return
	_server_arm(multiplayer.get_remote_sender_id(), arm_mode, target_id, dir, charge)


## Backwards compatible entry (used by the automated net test): a medium punch request.
func request_push(pusher: Node, target: Node, dir: Vector3) -> void:
	request_arm(pusher, GameConstants.ARM_MODE_PUNCH, target.peer_id, dir, 0.5)


func _server_push(pusher_id: int, target_id: int, dir: Vector3) -> void:
	_server_arm(pusher_id, GameConstants.ARM_MODE_PUNCH, target_id, dir, 0.5)


## The host recomputes range, force and cooldown from the (clamped) charge.
func _server_arm(attacker_id: int, arm_mode: int, target_id: int, dir: Vector3, charge: float) -> void:
	if state != State.PLAYING or not players.has(attacker_id) or mode == GameConstants.MODE_HIDE:
		return
	if arm_mode != GameConstants.ARM_MODE_PUNCH and arm_mode != GameConstants.ARM_MODE_GRAB:
		return
	if is_nan(charge) or is_inf(charge):
		return
	charge = clampf(charge, 0.0, 1.0)
	if not bool(alive.get(attacker_id, false)):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var cd := GameConstants.arm_server_cooldown(arm_mode, charge)
	# A punch while carrying is a throw, not a new arm attack. It can only
	# affect the victim in this attacker's own active grab.
	if _grabs.has(attacker_id):
		var held: Dictionary = _grabs[attacker_id]
		var held_id := int(held["target"])
		if bool(held.get("throwing", false)) or arm_mode != GameConstants.ARM_MODE_PUNCH or target_id != held_id or int(held["phase"]) != 1:
			return
		if not bool(alive.get(held_id, false)) or not players.has(held_id):
			_release_grab(attacker_id)
			return
		_last_push_time[attacker_id] = now
		var throw_stats: Dictionary = stats[attacker_id]
		throw_stats["attacks"] = int(throw_stats["attacks"]) + 1
		var throw_dir := Vector3(dir.x, 0.0, dir.z)
		if throw_dir.length() < 0.01:
			var holder: Node = players[attacker_id]
			throw_dir = Vector3(-sin(holder.facing_yaw), 0.0, -cos(holder.facing_yaw))
		throw_dir = throw_dir.normalized()
		held["throwing"] = true
		held["throw_time"] = THROW_RELEASE_DELAY
		held["throw_dir"] = throw_dir
		held["throw_charge"] = charge
		return
	if now - float(_last_push_time.get(attacker_id, -10.0)) < cd:
		return # server-side cooldown: spamming requests can never create extra hits
	_last_push_time[attacker_id] = now
	var st: Dictionary = stats[attacker_id]
	st["attacks"] = int(st["attacks"]) + 1          # every validated attempt counts once
	if target_id == 0 or target_id == attacker_id or not players.has(target_id):
		return                                       # a miss: cooldown consumed, stat counted
	if not bool(alive.get(target_id, false)) or not are_enemies(attacker_id, target_id):
		return
	if _is_held(target_id):
		return                                       # one grab per victim at a time
	if is_respawn_score_mode() and elapsed < float(_ko_protect_until.get(target_id, -1.0)):
		return                                       # freshly respawned: cannot be hit yet
	var a: Node = players[attacker_id]
	var b: Node = players[target_id]
	var flat: Vector3 = b.global_position - a.global_position
	flat.y = 0.0
	var rng := GameConstants.arm_range(arm_mode, charge)
	if absf(b.global_position.y - a.global_position.y) > GameConstants.ARM_VERTICAL_REACH:
		return                                       # do not connect across different heights
	# Validate against physics roots on both peers; visual animation transforms
	# (including run-cycle Z motion) are deliberately excluded.
	var surface_distance := maxf(GameConstants.combat_ground_distance(a, b) - GameConstants.ARM_TARGET_RADIUS, 0.0)
	if surface_distance > rng + GameConstants.ARM_LENIENCE:
		return                                       # too far apart even allowing for network lag
	if not _clear_line(a, b):
		return                                       # arms do not pass through walls
	# Dash frames: animation removed, movement-core only.
	if arm_mode == GameConstants.ARM_MODE_PUNCH:
		st["hits"] = int(st["hits"]) + 1
		_last_hit_by[target_id] = {"by": attacker_id, "time": now}
		var d := Vector3(dir.x, 0.0, dir.z)
		if d.length() < 0.01:
			d = flat
		if d.length() < 0.01:
			d = Vector3(1, 0, 0)
		d = d.normalized()
		# The impulse is defined by the host from the charge: weak tap = small push, held = strong push.
		var fist: float = float(powerups.consume_fist(attacker_id)) if powerups != null else 1.0
		_deliver_push(target_id, (d * GameConstants.punch_force(charge) + Vector3.UP * GameConstants.punch_lift(charge)) * fist, GameConstants.PUNCH_FORCE * fist, GameConstants.PUNCH_LIFT * fist)
	else:
		st["hits"] = int(st["hits"]) + 1
		st["grabs"] = int(st["grabs"]) + 1
		_last_hit_by[target_id] = {"by": attacker_id, "time": now}
		_grabs[attacker_id] = {"target": target_id, "t": 0.0, "phase": 0, "throwing": false}
		_broadcast_grab(attacker_id, target_id, true, 0)


func _clear_line(a: Node3D, b: Node3D) -> bool:
	if arena == null:
		return true
	var space := arena.get_world_3d().direct_space_state
	if space == null:
		return true
	# Sample the target capsule at several heights instead of only chest level.
	# A clear arm path to any part of the body is a valid contact.
	for height in [0.2, 0.8, 1.4]:
		var offset := Vector3(0, height, 0)
		var q := PhysicsRayQueryParameters3D.create(a.global_position + offset, b.global_position + offset, GameConstants.LAYER_WORLD)
		if space.intersect_ray(q).is_empty():
			return true
	return false


func _is_held(target_id: int) -> bool:
	for k in _grabs.keys():
		if int(_grabs[k]["target"]) == target_id:
			return true
	return false


## Host: advance every grab. Phase 0 = pull the victim in (max 1.3 s), phase 1 = victim hangs in the
## holder's hands for 2 s and is dropped afterwards. Ends early on death / breaking away.
func _process_grabs(delta: float) -> void:
	if _grabs.is_empty():
		return
	for aid in _grabs.keys():
		var g: Dictionary = _grabs[aid]
		var tid: int = int(g["target"])
		g["t"] = float(g["t"]) + delta
		var a: Node = players.get(aid)
		var b: Node = players.get(tid)
		var end := false
		if a == null or b == null or not bool(alive.get(aid, false)) or not bool(alive.get(tid, false)):
			end = true
		elif bool(g.get("throwing", false)):
			g["throw_time"] = maxf(0.0, float(g.get("throw_time", 0.0)) - delta)
			if float(g["throw_time"]) <= 0.0:
				var throw_dir: Vector3 = g.get("throw_dir", Vector3.ZERO)
				var charge := clampf(float(g.get("throw_charge", 0.0)), 0.0, 1.0)
				var throw_impulse := throw_dir * GameConstants.punch_force(charge) + Vector3.UP * GameConstants.punch_lift(charge)
				throw_impulse += a.velocity * 0.35
				var throw_stats: Dictionary = stats.get(int(aid), {})
				if not throw_stats.is_empty():
					throw_stats["hits"] = int(throw_stats["hits"]) + 1
				_last_hit_by[tid] = {"by": int(aid), "time": Time.get_ticks_msec() / 1000.0}
				_release_grab(int(aid))
				_deliver_push(tid, throw_impulse * 1.5, GameConstants.PUNCH_FORCE * 1.5, GameConstants.PUNCH_LIFT * 1.5)
				continue
		elif int(g["phase"]) == 0:
			var flat: Vector3 = b.global_position - a.global_position
			flat.y = 0.0
			var dist := flat.length()
			if float(g["t"]) >= GameConstants.GRAB_PULL_MAX_TIME:
				end = true      # the pull failed
			elif dist <= GameConstants.GRAB_HOLD_DISTANCE:
				g["phase"] = 1  # pulled in: lift the victim into the hands
				g["t"] = 0.0
				_broadcast_grab(int(aid), tid, true, 1)
			elif dist > GameConstants.GRAB_RANGE + 2.2:
				end = true      # the target broke away by running
		else:
			if float(g["t"]) >= GameConstants.GRAB_HANG_TIME:
				end = true      # two seconds are over: drop
		if end:
			_release_grab(int(aid))


func _release_grab(attacker_id: int) -> void:
	if not _grabs.has(attacker_id):
		return
	var tid: int = int(_grabs[attacker_id]["target"])
	_grabs.erase(attacker_id)
	_escape_attempts.erase(tid)
	_broadcast_grab(attacker_id, tid, false, 0)


func _broadcast_grab(attacker_id: int, target_id: int, on: bool, phase: int) -> void:
	_apply_grab(attacker_id, target_id, on, phase)
	if NetworkManager.online:
		_rpc_grab_state.rpc(attacker_id, target_id, on, phase)


@rpc("authority", "call_remote", "reliable")
func _rpc_grab_state(attacker_id: int, target_id: int, on: bool, phase: int) -> void:
	_apply_grab(attacker_id, target_id, on, phase)


func _apply_grab(attacker_id: int, target_id: int, on: bool, phase: int) -> void:
	var a: Node = players.get(attacker_id)
	var b: Node = players.get(target_id)
	if a != null and is_instance_valid(a):
		a.set_grab_links(target_id if on else 0, a.grabbed_by, phase)
	if b != null and is_instance_valid(b):
		b.set_grab_links(b.grabbing_id, attacker_id if on else 0, phase)


## Escape input from the held player's authority. Jump/dash can break the pull;
## five punch taps in the escape window break either pull or carry phase.
func request_escape(p: Node, instant := true) -> void:
	if is_host:
		_server_escape(p.peer_id, instant)
	else:
		_rpc_request_escape.rpc_id(1, instant)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_escape(instant: bool) -> void:
	if not multiplayer.is_server():
		return
	_server_escape(multiplayer.get_remote_sender_id(), instant)


func _server_escape(target_id: int, instant := true) -> void:
	for aid in _grabs.keys():
		if int(_grabs[aid]["target"]) != target_id:
			continue
		var phase := int(_grabs[aid]["phase"])
		if instant:
			if phase == 0: # retain the existing jump/dash escape during the pull
				_count_grab_escape(target_id)
				_release_grab(int(aid))
			return
		var now := Time.get_ticks_msec() / 1000.0
		var attempt: Dictionary = _escape_attempts.get(target_id, {"count": 0, "last": -10.0})
		var elapsed_since_last := now - float(attempt["last"])
		if elapsed_since_last > GameConstants.GRAB_ESCAPE_WINDOW:
			attempt["count"] = 0
		elif elapsed_since_last < GameConstants.GRAB_ESCAPE_MIN_INTERVAL:
			return # ignore duplicate/implausibly rapid RPCs
		attempt["count"] = int(attempt["count"]) + 1
		attempt["last"] = now
		_escape_attempts[target_id] = attempt
		if int(attempt["count"]) >= GameConstants.GRAB_ESCAPE_PRESSES:
			_count_grab_escape(target_id)
			_release_grab(int(aid))
		return


func _count_grab_escape(target_id: int) -> void:
	var st: Dictionary = stats.get(target_id, {})
	if not st.is_empty():
		st["escapes"] = int(st["escapes"]) + 1


func _deliver_push(target_id: int, impulse: Vector3, max_horizontal := 22.0, max_upward := 8.0) -> void:
	var b: Node = players[target_id]
	var auth := b.get_multiplayer_authority()
	if auth == multiplayer.get_unique_id():
		b.apply_knockback(impulse, max_horizontal, max_upward)
	elif NetworkManager.online:
		_rpc_apply_push.rpc_id(auth, target_id, impulse, max_horizontal, max_upward)


@rpc("authority", "call_remote", "reliable")
func _rpc_apply_push(target_id: int, impulse: Vector3, max_horizontal := 22.0, max_upward := 8.0) -> void:
	var b: Node = players.get(target_id)
	if b != null and b.is_multiplayer_authority():
		b.apply_knockback(impulse, max_horizontal, max_upward)


# ---------------------------------------------------------------------------
# Hide and seek (host authoritative): disguises, catching, hug + melt

func _hs_assign_props() -> void:
	var pool: Array = []
	for i in PropsLib.PROP_COUNT:
		pool.append(i)
	pool.shuffle()
	var n := 0
	hs_props.clear()
	for id in players.keys():
		if role_of(int(id)) == GameConstants.HS_ROLE_HIDER:
			hs_props[int(id)] = int(pool[n % pool.size()])     # unique while props are left (18 types)
			n += 1
	_hs_apply_props()


func _hs_apply_props() -> void:
	for id in hs_props.keys():
		var p: Node = players.get(int(id))
		if p != null and is_instance_valid(p) and p.is_alive:
			p.set_disguise(int(hs_props[id]))


@rpc("authority", "call_remote", "reliable")
func _rpc_hs_props(props: Dictionary) -> void:
	hs_props = props.duplicate()
	_hs_apply_props()


func request_catch(seeker: Node, target_id: int) -> void:
	if is_host:
		_server_catch(seeker.peer_id, target_id)
	else:
		_rpc_request_catch.rpc_id(1, target_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_catch(target_id: int) -> void:
	if not multiplayer.is_server():
		return
	_server_catch(multiplayer.get_remote_sender_id(), target_id)


func _server_catch(seeker_id: int, target_id: int) -> void:
	if mode != GameConstants.MODE_HIDE or state != State.PLAYING or _ended:
		return
	if elapsed < GameConstants.HS_HIDE_TIME:
		return                                           # seekers are still blindfolded
	if not players.has(seeker_id) or not players.has(target_id) or seeker_id == target_id:
		return
	if role_of(seeker_id) != GameConstants.HS_ROLE_SEEKER or role_of(target_id) != GameConstants.HS_ROLE_HIDER:
		return
	if not bool(alive.get(seeker_id, false)) or not bool(alive.get(target_id, false)):
		return
	if _hs_hugs.has(target_id) or _hs_is_hugging(seeker_id):
		return                                           # no repeated captures while the animation plays
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_push_time.get(seeker_id, -10.0)) < GameConstants.HS_CATCH_COOLDOWN * 0.7:
		return
	_last_push_time[seeker_id] = now
	var st: Dictionary = stats[seeker_id]
	st["attacks"] = int(st["attacks"]) + 1
	var a: Node = players[seeker_id]
	var b: Node = players[target_id]
	var flat: Vector3 = b.global_position - a.global_position
	flat.y = 0.0
	if flat.length() > GameConstants.HS_CATCH_RANGE + GameConstants.ARM_LENIENCE:
		return
	if not _clear_line(a, b):
		return
	st["hits"] = int(st["hits"]) + 1
	st["kos"] = int(st["kos"]) + 1
	_hs_hugs[target_id] = {"seeker": seeker_id, "t": 0.0}
	_apply_hug(seeker_id, target_id, GameConstants.HS_HUG_TIME)
	if NetworkManager.online:
		_rpc_hs_hug.rpc(seeker_id, target_id, GameConstants.HS_HUG_TIME)


func _hs_is_hugging(seeker_id: int) -> bool:
	for k in _hs_hugs.keys():
		if int(_hs_hugs[k]["seeker"]) == seeker_id:
			return true
	return false


@rpc("authority", "call_remote", "reliable")
func _rpc_hs_hug(seeker_id: int, hider_id: int, duration: float) -> void:
	_apply_hug(seeker_id, hider_id, duration)


## Runs on every peer: seeker raises the arms and hugs, the hider is revealed and melts.
func _apply_hug(seeker_id: int, hider_id: int, duration: float) -> void:
	var s_node: Node = players.get(seeker_id)
	var h_node: Node = players.get(hider_id)
	if s_node == null or h_node == null or not is_instance_valid(s_node) or not is_instance_valid(h_node):
		return
	s_node.begin_hug_seeker(hider_id, duration)
	h_node.begin_hug_victim(seeker_id, duration)
	AudioManager.play_character("push", 0.1, 0.0)
	announce.emit(t("hs_found") % h_node.player_name, 1.6)


## Host: when the hug is over the hider is out (a puddle stays behind).
func _process_hugs(delta: float) -> void:
	if _hs_hugs.is_empty():
		return
	for hid in _hs_hugs.keys():
		var h: Dictionary = _hs_hugs[hid]
		h["t"] = float(h["t"]) + delta
		if float(h["t"]) >= GameConstants.HS_HUG_TIME:
			_hs_hugs.erase(hid)
			if bool(alive.get(hid, false)):
				var rank := _count_alive()
				_eliminate(int(hid), rank)
				if NetworkManager.online:
					_rpc_eliminate.rpc(int(hid), rank)
				_check_end()


# ---------------------------------------------------------------------------
# Knockout mode (host authoritative)
# A fall is reported by the player's authority (or caught by the host backup check), queued, and
# validated once per frame here. The host alone decides who gets credit (last validated punch / grab
# within KO_CREDIT_WINDOW), bumps the score and broadcasts one reliable event with a full snapshot.
# Clients only mirror that snapshot; they have no RPC with which to add points.

func _ko_attribute(victim: int) -> int:
	if not _last_hit_by.has(victim):
		return 0
	var lh: Dictionary = _last_hit_by[victim]
	var by := int(lh["by"])
	if by == victim or not players.has(by):
		return 0
	if Time.get_ticks_msec() / 1000.0 - float(lh["time"]) > GameConstants.KO_CREDIT_WINDOW:
		return 0
	return by


## Host: handles every fall queued this frame. Victims are processed in id order, each at most
## once (the alive flag flips immediately), so simultaneous falls are all counted exactly once.
func _ko_process_pending() -> void:
	var batch: Array = _pending_elims.duplicate()
	_pending_elims.clear()
	batch.sort()
	for id in batch:
		_ko_register(int(id))
	_check_end()


func _ko_register(victim: int) -> void:
	if not is_host or state != State.PLAYING or _ended:
		return
	if not players.has(victim) or not bool(alive.get(victim, false)):
		return                                       # duplicate / stale report: ignored
	var killer := _ko_attribute(victim)
	_last_hit_by.erase(victim)                       # a hit can be credited only once
	alive[victim] = false
	ko_falls[victim] = int(ko_falls.get(victim, 0)) + 1
	if killer != 0:
		ko_kos[killer] = int(ko_kos.get(killer, 0)) + 1
		ko_last_ms[killer] = int(elapsed * 1000.0)
		if stats.has(killer):
			stats[killer]["kos"] = int(stats[killer]["kos"]) + 1
	_ko_respawn_at[victim] = elapsed + GameConstants.KO_RESPAWN_DELAY
	for aid in _grabs.keys():
		if int(aid) == victim or int(_grabs[aid]["target"]) == victim:
			_release_grab(int(aid))
	ko_seq += 1
	var snap := _ko_snapshot()
	_apply_ko_event(victim, killer, ko_seq, snap)
	if NetworkManager.online:
		_rpc_ko_event.rpc(victim, killer, ko_seq, snap)


## id -> [kos, falls, last_ms, alive]. Small enough to send whole with every event.
func _ko_snapshot() -> Dictionary:
	var snap: Dictionary = {}
	for id in players.keys():
		snap[int(id)] = [int(ko_kos.get(id, 0)), int(ko_falls.get(id, 0)), int(ko_last_ms.get(id, -1)), 1 if bool(alive.get(id, false)) else 0]
	return snap


func _ko_load_snapshot(snap: Dictionary) -> void:
	for id in snap.keys():
		var v: Array = snap[id]
		if v.size() < 4 or not players.has(int(id)):
			continue
		ko_kos[int(id)] = int(v[0])
		ko_falls[int(id)] = int(v[1])
		ko_last_ms[int(id)] = int(v[2])
		alive[int(id)] = int(v[3]) == 1


## Runs on every peer. The score always comes from the snapshot (never "+1 locally").
func _apply_ko_event(victim: int, killer: int, seq: int, snap: Dictionary) -> void:
	if seq <= _ko_applied_seq:
		return
	_ko_applied_seq = seq
	_ko_load_snapshot(snap)
	var v_node: Node = players.get(victim)
	var vname := "?"
	if v_node != null and is_instance_valid(v_node):
		vname = v_node.player_name
		if arena != null and arena.has_method("spawn_poof"):
			arena.spawn_poof(v_node.last_position + Vector3(0, 1, 0))
		v_node.eliminate()
		if v_node.is_local:
			announce.emit(t("you_fell") if killer == 0 else t("ko_knocked_out_by") % _player_name_of(killer), 1.6)
	var kname := _player_name_of(killer) if killer != 0 else ""
	if killer != 0 and local_player != null and killer == local_player.peer_id:
		announce.emit(t("ko_you_scored"), 1.0)
		GameManager.vibrate(60)
	if v_node != null and is_instance_valid(v_node):
		AudioManager.play_character_3d("fall", (v_node as Node3D).global_position)
	else:
		AudioManager.play_character("fall", 0.05)
	knockout_scored.emit(killer, victim, kname, vname)
	players_changed.emit()


func _player_name_of(id: int) -> String:
	var p: Node = players.get(id)
	if p != null and is_instance_valid(p):
		return p.player_name
	return "?"


@rpc("authority", "call_remote", "reliable")
func _rpc_ko_event(victim: int, killer: int, seq: int, snap: Dictionary) -> void:
	if multiplayer.is_server():
		return
	_apply_ko_event(victim, killer, seq, snap)


## Late loader catch-up (see _rpc_client_ready): scores plus who is currently down.
@rpc("authority", "call_remote", "reliable")
func _rpc_ko_snapshot(seq: int, snap: Dictionary) -> void:
	if multiplayer.is_server() or seq < _ko_applied_seq:
		return
	_ko_applied_seq = seq
	_ko_load_snapshot(snap)
	for id in players.keys():
		var p: Node = players[id]
		if p != null and is_instance_valid(p) and not bool(alive.get(id, true)) and p.is_alive:
			p.eliminate()
	players_changed.emit()


## Host: bring back everybody whose respawn delay is over.
func _ko_process_respawns() -> void:
	if not is_respawn_score_mode() or _ko_respawn_at.is_empty() or _ended:
		return
	for id in _ko_respawn_at.keys():
		if elapsed < float(_ko_respawn_at[id]):
			continue
		_ko_respawn_at.erase(id)
		if not players.has(id) or bool(alive.get(id, false)):
			continue
		var pos := _ko_pick_spawn(int(id))
		_ko_protect_until[id] = elapsed + GameConstants.KO_SPAWN_PROTECT
		_apply_ko_respawn(int(id), pos)
		if NetworkManager.online:
			_rpc_ko_respawn.rpc(int(id), pos)


## The spawn point that is farthest from every other living player (a little randomness breaks ties).
func _ko_pick_spawn(id: int) -> Vector3:
	var spawns: Array = arena.map_info.get("spawns", []) if arena != null else []
	if spawns.is_empty():
		return arena.get_spawn_point(0) if arena != null else Vector3(0, 0.6, 0)
	var best: Vector3 = spawns[0]
	var best_score := -1.0
	for s in spawns:
		var nearest := 50.0
		for oid in players.keys():
			if int(oid) == id or not bool(alive.get(oid, false)):
				continue
			var q: Node = players[oid]
			if q == null or not is_instance_valid(q):
				continue
			var d: Vector3 = q.global_position - s
			d.y = 0.0
			nearest = minf(nearest, d.length())
		var sc := nearest + randf() * 0.5
		if sc > best_score:
			best_score = sc
			best = s
	return best


func _apply_ko_respawn(id: int, pos: Vector3) -> void:
	var p: Node = players.get(id)
	alive[id] = true
	if p != null and is_instance_valid(p):
		p.respawn(pos)
	players_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_ko_respawn(id: int, pos: Vector3) -> void:
	if multiplayer.is_server():
		return
	_apply_ko_respawn(id, pos)


## Host: first to KO_TARGET_SCORE wins at once; a match with fewer than two players left is over.
func _ko_check_end() -> void:
	if _ended or state != State.PLAYING:
		return
	# Trampoline Brawl is a timed score race. Unlike Knockout, it never ends early
	# when somebody reaches the KO target; every player keeps bouncing until time-up.
	if mode == GameConstants.MODE_TRAMPOLINE:
		return
	for id in ko_kos.keys():
		if int(ko_kos[id]) >= GameConstants.KO_TARGET_SCORE:
			_end_round("target_reached")
			return


## Live or final standings, best first, ties share a rank (see GameConstants.ko_rank_entries).
func ko_standings() -> Array:
	var entries: Array = []
	for id in players.keys():
		entries.append({"id": int(id), "kos": int(ko_kos.get(id, 0)), "falls": int(ko_falls.get(id, 0)), "last_ms": int(ko_last_ms.get(id, -1))})
	return GameConstants.ko_rank_entries(entries)


func _ko_build_results() -> Array:
	var out: Array = []
	for e in ko_standings():
		var id := int(e["id"])
		var p: Node = players[id]
		var rank := int(e["rank"])
		var pts := GameConstants.ko_points(rank, int(e["kos"]))
		if not p.is_bot:
			NetworkManager.add_score(id, pts)
		out.append({"id": id, "name": p.player_name, "color": p.color_index, "rank": rank, "points": pts, "falls": int(e["falls"]),
			"kos": int(e["kos"]), "ko_mode": true, "total": NetworkManager.get_score(id), "bot": p.is_bot, "stats": stats.get(id, {})})
	NetworkManager.broadcast_players()
	return out


# ---------------------------------------------------------------------------
# Round end

func _winning_team(reason: String) -> int:
	if mode == GameConstants.MODE_HIDE:
		if reason == "seekers_win":
			return 1 - hider_team()
		if reason == "hiders_win":
			return hider_team()
		# time is up: hiders win if somebody survived
		return hider_team() if _count_alive_role(GameConstants.HS_ROLE_HIDER) > 0 else 1 - hider_team()
	var ta := _alive_teams()
	if ta.size() == 1:
		return int(ta[0])
	if ta.is_empty():
		return -1
	# time is up with several teams alive: the team with most survivors wins (tie = draw)
	var best := -1
	var best_n := -1
	var tie := false
	for tm in ta:
		var n := 0
		for id in alive.keys():
			if bool(alive[id]) and int(team_of.get(int(id), 0)) == int(tm):
				n += 1
		if n > best_n:
			best_n = n
			best = int(tm)
			tie = false
		elif n == best_n:
			tie = true
	return -1 if tie else best


func _end_round(reason: String) -> void:
	if _ended:
		return
	_ended = true
	# An arena event must not leak into the results phase (slippery floor, low gravity...).
	if current_event != ArenaEvent.NONE:
		_set_arena_event(ArenaEvent.NONE, 0.0)
	var results: Array = []
	var win_team := -1
	if is_team_mode():
		win_team = _winning_team(reason)
		for id in players.keys():
			var p: Node = players[id]
			var tm := int(team_of.get(int(id), 0))
			var won := win_team >= 0 and tm == win_team
			var pts := 3 if won else 0
			var tag := t(GameConstants.TEAM_KEYS[tm])
			if mode == GameConstants.MODE_HIDE:
				tag = t("hs_hider") if role_of(int(id)) == GameConstants.HS_ROLE_HIDER else t("hs_seeker")
			if not p.is_bot:
				NetworkManager.add_score(int(id), pts)
			results.append({"id": id, "name": p.player_name, "color": GameConstants.team_color_index(tm) if mode == GameConstants.MODE_TEAMS else p.color_index, "rank": 1 if won else 2, "points": pts, "falls": int(falls.get(id, 0)), "total": NetworkManager.get_score(int(id)), "bot": p.is_bot, "stats": stats.get(id, {}), "tag": tag, "team": tm})
		results.sort_custom(func(x, y) -> bool: return int(x["rank"]) < int(y["rank"]))
		NetworkManager.broadcast_players()
	elif is_respawn_score_mode():
		results = _ko_build_results()
	else:
		for id in alive.keys():
			if alive[id]:
				ranks[id] = 1
		if practice:
			# Rank by fewest falls (bots included)
			var ids := players.keys()
			ids.sort_custom(func(x, y) -> bool: return int(falls.get(x, 0)) < int(falls.get(y, 0)))
			var rank := 1
			for id in ids:
				var p: Node = players[id]
				results.append({"id": id, "name": p.player_name, "color": p.color_index, "rank": rank, "points": 0, "falls": int(falls.get(id, 0)), "total": 0, "bot": p.is_bot})
				rank += 1
		else:
			for id in players.keys():
				var p: Node = players[id]
				var rank: int = int(ranks.get(id, 1))
				var pts := maxi(0, 4 - rank)
				if not p.is_bot:
					NetworkManager.add_score(int(id), pts)
				results.append({"id": id, "name": p.player_name, "color": p.color_index, "rank": rank, "points": pts, "falls": int(falls.get(id, 0)), "total": NetworkManager.get_score(int(id)), "bot": p.is_bot, "stats": stats.get(id, {})})
			results.sort_custom(func(x, y) -> bool: return int(x["rank"]) < int(y["rank"]))
			NetworkManager.broadcast_players()
	_apply_end(results, reason, win_team)
	if NetworkManager.online:
		_rpc_round_ended.rpc(results, reason, win_team)


@rpc("authority", "call_remote", "reliable")
func _rpc_round_ended(results: Array, reason: String, win_team: int) -> void:
	if state == State.ENDED:
		return
	_apply_end(results, reason, win_team)


func _apply_end(results: Array, reason: String, win_team := -1) -> void:
	state = State.ENDED
	state_changed.emit(state)
	var winners: Array = []
	for r in results:
		if int(r["rank"]) == 1:
			winners.append(r)
			var p: Node = players.get(r["id"])
			if p != null and p.is_alive:
				p.celebrate()
				if arena != null:
					arena.celebrate_at(p.global_position)
	var headline := ""
	if is_team_mode():
		if win_team < 0:
			headline = t("draw")
		elif mode == GameConstants.MODE_HIDE:
			headline = t("hs_seekers_win") if win_team != hider_team() else t("hs_hiders_win")
		else:
			headline = t("team_wins") % t(GameConstants.TEAM_KEYS[win_team])
	elif is_respawn_score_mode():
		headline = t("winner") % str(winners[0]["name"]) if winners.size() == 1 else t("draw")
	elif practice:
		headline = t("practice_complete")
	elif reason == "draw" or (winners.size() > 1 and reason == "last_standing"):
		headline = t("draw")
	elif winners.size() == 1:
		headline = t("winner") % str(winners[0]["name"])
	else:
		headline = t("survivors_win")
	if reason == "time_up":
		announce.emit(t("time_up"), 1.5)
	var local_won := false
	var local_in_results := false
	for r in results:
		if local_player != null and int(r["id"]) == local_player.peer_id:
			local_in_results = true
			local_won = int(r["rank"]) == 1
	# Ties shown as a draw must not unlock the win challenge.
	if reason == "draw" or (not is_team_mode() and winners.size() > 1 and (is_respawn_score_mode() or reason == "last_standing")):
		local_won = false
	if not practice and local_in_results:
		var my_kos := 0
		if local_player != null:
			my_kos = int(stats.get(local_player.peer_id, {}).get("kos", 0))
		SaveManager.record_match(local_won, my_kos)
	AudioManager.play_ui("victory", 0.0)
	round_ended.emit(results, headline)


# ---------------------------------------------------------------------------
# Disconnections

func _on_player_left(id: int, _pname: String) -> void:
	if not players.has(id):
		return
	if is_host and state == State.PLAYING and is_respawn_score_mode():
		# Respawning mode: nobody is "eliminated" for good. Drop pending work for the leaver, keep everyone else's score.
		_pending_elims.erase(id)
		_ko_respawn_at.erase(id)
		_ko_protect_until.erase(id)
		_last_hit_by.erase(id)
		for aid in _grabs.keys():
			if int(aid) == id or int(_grabs[aid]["target"]) == id:
				_release_grab(int(aid))
	elif is_host and state == State.PLAYING and bool(alive.get(id, false)):
		var rank := _count_alive()
		_eliminate(id, rank)
		if NetworkManager.online:
			_rpc_eliminate.rpc(id, rank)
	_remove_player(id)
	if is_host:
		if state == State.PLAYING:
			_check_end()
			if is_respawn_score_mode() and not _ended and players.size() < 2:
				_end_round("opponents_left")
		elif state == State.WAITING and NetworkManager.online and _all_clients_ready():
			_begin_countdown()


func _remove_player(id: int) -> void:
	var p: Node = players.get(id)
	if p != null and is_instance_valid(p):
		p.queue_free()
	players.erase(id)
	alive.erase(id)
	ko_kos.erase(id)
	ko_falls.erase(id)
	ko_last_ms.erase(id)
	_ready_peers.erase(id)
	players_changed.emit()
