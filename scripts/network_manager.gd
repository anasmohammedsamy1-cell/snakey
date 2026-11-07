extends Node
## Autoload: NetworkManager
## LAN multiplayer built on ENetMultiplayerPeer (UDP). Designed for the
## "one phone makes a Wi-Fi hotspot, the others join it" setup.
##
## Authority model:
##  - The HOST (peer id 1) owns the player list, ready states, scores and
##    the match start / return-to-lobby flow. Clients only *request* changes.
##  - The player list is always pushed host -> clients as a whole snapshot
##    (_rpc_player_list), which keeps everybody consistent and avoids RPC loops.

const GameConstants := preload("res://scripts/game_constants.gd")
const NetUtils := preload("res://scripts/net_utils.gd")
const Locale := preload("res://scripts/locale.gd")
const LanDiscovery := preload("res://scripts/lan_discovery.gd")

signal player_list_changed
signal connection_succeeded
signal connection_failed(reason: String)
signal host_disconnected
signal player_joined(id: int, player_name: String)
signal player_left(id: int, player_name: String)
signal match_started
signal returned_to_lobby
signal status_changed(text: String)
signal kicked(reason: String)
signal cfg_changed

const CONNECT_TIMEOUT := 7.0

var online := false
var is_host := false
var match_in_progress := false
var port: int = GameConstants.DEFAULT_PORT
var host_address := ""
## id -> {"name": String, "color": int, "ready": bool, "score": int}
var players: Dictionary = {}
## Match settings chosen by the host (mode, map, bots, round time, hider team...). Mirrored to every client.
var cfg: Dictionary = {}

## Room shown in the LAN room list (host side). Empty name = default "<nickname>'s Arena".
var room_name := ""
## Room size limit chosen by the host (2..MAX_PLAYERS). The ENet server itself always allows MAX_PLAYERS-1 clients;
## the limit is enforced in _rpc_register so a late player gets a clear "lobby is full" message.
var max_players: int = GameConstants.MAX_PLAYERS
## UDP room discovery (child node, see lan_discovery.gd).
var discovery: Node = null

var _connecting := false
var _probing := false
var _connect_attempt := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	discovery = LanDiscovery.new()
	discovery.name = "LanDiscovery"
	add_child(discovery)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ---------------------------------------------------------------------------
# Public API

func get_local_info() -> Dictionary:
	return {"name": SaveManager.player_name, "color": SaveManager.color_index, "ready": false, "score": 0, "team": 0}


## Returns "" on success, otherwise a human readable error.
func host_game(p_port: int, p_room_name := "", p_max_players: int = GameConstants.MAX_PLAYERS) -> String:
	if online and is_host:
		return GameManager.t("already_hosting")      # never create a second server on top of the first
	if _connecting or _probing:
		return GameManager.t("already_connecting")
	leave()
	if p_port < 1024 or p_port > 65535:
		return GameManager.t("invalid_port")
	# If the port is taken (an old copy of the game still running in the background, another room on this
	# phone) try the next ports and tell the host which one was used. Joining players must type that port.
	var peer: ENetMultiplayerPeer = null
	var err := ERR_CANT_CREATE
	var first_err := ERR_CANT_CREATE
	for offset in 11:
		var try_port := p_port + offset
		if try_port > 65535:
			break
		peer = ENetMultiplayerPeer.new()
		err = peer.create_server(try_port, GameConstants.MAX_PLAYERS - 1)
		if offset == 0:
			first_err = err
		if err == OK:
			p_port = try_port
			break
		peer = null
	if err != OK or peer == null:
		return GameManager.t("port_busy") % [p_port, int(first_err)]
	multiplayer.multiplayer_peer = peer
	online = true
	is_host = true
	match_in_progress = false
	port = p_port
	players.clear()
	players[1] = get_local_info()
	cfg = GameManager.default_cfg()
	max_players = clampi(p_max_players, GameConstants.MIN_PLAYERS, GameConstants.MAX_PLAYERS)
	cfg["max_players"] = max_players       # mirrored to clients so the lobby shows "n / max"
	room_name = NetUtils.clean_net_text(p_room_name, LanDiscovery.MAX_ROOM_NAME)
	if room_name == "":
		room_name = default_room_name()
	# Answer LAN discovery queries. A failure here (UDP port in use) only disables auto-discovery.
	var derr: String = discovery.start_advertising(_advert_info)
	if derr != "":
		push_warning("LAN discovery unavailable: " + derr)
	status_changed.emit("%s :%d" % [GameManager.t("hosting"), p_port])
	player_list_changed.emit()
	return ""


## Returns "" when the connection attempt started, otherwise an error.
func join_game(address: String, p_port: int) -> String:
	if _connecting or _probing:
		return GameManager.t("already_connecting")    # no duplicate connection attempts
	leave()
	# Localized digits (Arabic-Indic / Persian) are converted to ASCII, then the address is validated strictly.
	var addr := NetUtils.parse_ipv4(address)
	if addr == "":
		return GameManager.t("invalid_ip")
	if p_port < 1024 or p_port > 65535:
		return GameManager.t("invalid_port")
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(addr, p_port)
	if err != OK:
		return GameManager.t("conn_failed")
	multiplayer.multiplayer_peer = peer
	online = true
	is_host = false
	match_in_progress = false
	port = p_port
	host_address = addr
	players.clear()
	_connecting = true
	_connect_attempt += 1
	var attempt := _connect_attempt
	status_changed.emit(GameManager.t("connecting"))
	get_tree().create_timer(CONNECT_TIMEOUT).timeout.connect(func() -> void:
		if _connecting and attempt == _connect_attempt:
			_connecting = false
			leave()
			connection_failed.emit(GameManager.t("timeout"))
	)
	return ""


## Cleanly shuts down any network session and returns to the offline peer.
func leave() -> void:
	_connecting = false
	_probing = false
	_connect_attempt += 1       # invalidates pending connect timers / join probes
	if discovery != null and discovery.mode == LanDiscovery.Mode.ADVERTISE:
		discovery.stop()
	if online and multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	online = false
	is_host = false
	match_in_progress = false
	host_address = ""
	players.clear()
	cfg = {}
	room_name = ""
	player_list_changed.emit()
	status_changed.emit(GameManager.t("not_connected"))


func set_ready(value: bool) -> void:
	if not online or match_in_progress:
		return
	if is_host:
		if players.has(1):
			players[1]["ready"] = value
		_broadcast_players()
	else:
		_rpc_set_ready.rpc_id(1, value)


## Called after the customization screen saves while connected to a lobby.
func update_local_info() -> void:
	if not online or match_in_progress:
		return
	if is_host:
		if players.has(1):
			players[1]["name"] = SaveManager.player_name
			players[1]["color"] = SaveManager.color_index
		_broadcast_players()
	else:
		_rpc_update_info.rpc_id(1, SaveManager.player_name, SaveManager.color_index)


func can_start() -> bool:
	return start_problem() == ""


## "" when the match can start, otherwise a locale key explaining why not.
func start_problem() -> String:
	if not online or not is_host:
		return "host_required"
	var bots := int(cfg.get("bots", 0))
	if players.size() + bots < GameConstants.MIN_PLAYERS:
		return "need_players"
	for id in players.keys():
		if id != 1 and not bool(players[id]["ready"]):
			return "need_ready"
	var mode := int(cfg.get("mode", 0))
	if GameConstants.uses_teams(mode):
		var used: Array = []
		for id in players.keys():
			var tm := int(players[id].get("team", 0))
			if not used.has(tm):
				used.append(tm)
		var team_count := 2 if mode == GameConstants.MODE_HIDE else clampi(int(cfg.get("team_count", 2)), 2, 4)
		if used.size() < 2 and bots == 0:
			return "need_two_teams"
		if mode == GameConstants.MODE_HIDE and bots == 0 and (not used.has(0) or not used.has(1)):
			return "need_two_teams"
		for tm in used:
			if int(tm) >= team_count:
				return "need_two_teams"
	return ""


func start_match() -> void:
	# Treat the host-side API as a security boundary too: UI button state is not
	# sufficient protection against stale input or another local caller.
	if not online or not is_host or match_in_progress or not can_start():
		return
	_launch_match()


## Shared launch path for a validated lobby start and an explicit post-round rematch.
func _launch_match() -> void:
	var humans: Array = []
	for id in players.keys():
		humans.append(int(players[id].get("team", 0)))
	cfg["bot_teams"] = GameManager.make_bot_teams(cfg, humans)
	match_in_progress = true
	for id in players.keys():
		players[id]["ready"] = false
	_rpc_cfg.rpc(cfg)
	_rpc_start_match.rpc()
	_on_start_match()


func return_to_lobby() -> void:
	if not online or not is_host:
		return
	match_in_progress = false
	_broadcast_players()
	_rpc_return_to_lobby.rpc()
	_on_return_to_lobby()


## Host only. Every setting is validated here (clients cannot call this: it is not an RPC).
func set_cfg_value(key: String, value: Variant) -> void:
	if not online or not is_host or match_in_progress:
		return
	match key:
		"mode":
			cfg["mode"] = clampi(int(value), 0, GameConstants.MODE_COUNT - 1)
			var allowed: Array = GameConstants.maps_for_mode(int(cfg["mode"]))
			if not allowed.has(int(cfg.get("map", 0))):
				cfg["map"] = int(allowed[0])
			cfg["round_time"] = GameConstants.default_round_time(int(cfg["mode"]))
		"map":
			if GameConstants.maps_for_mode(int(cfg.get("mode", 0))).has(int(value)):
				cfg["map"] = int(value)
		"bots":
			cfg["bots"] = clampi(int(value), 0, maxi(GameConstants.MAX_TOTAL - players.size(), 0))
		"round_time":
			if int(cfg.get("mode", 0)) != GameConstants.MODE_HIDE:
				cfg["round_time"] = clampf(float(value), 30.0, 300.0)
		"team_count":
			cfg["team_count"] = clampi(int(value), 2, 4)
		"hider_team":
			cfg["hider_team"] = clampi(int(value), 0, 1)
		"voice_policy":
			cfg["voice_policy"] = clampi(int(value), 0, 2)      # 0 player choice, 1 team only, 2 everybody
	_broadcast_players()


## Host only: put a player into a team.
func set_team(id: int, team: int) -> void:
	if not online or not is_host or match_in_progress or not players.has(id):
		return
	var limit := 2 if int(cfg.get("mode", 0)) == GameConstants.MODE_HIDE else clampi(int(cfg.get("team_count", 2)), 2, 4)
	players[id]["team"] = posmod(team, limit)
	_broadcast_players()


func auto_balance_teams() -> void:
	if not online or not is_host or match_in_progress:
		return
	var limit := 2 if int(cfg.get("mode", 0)) == GameConstants.MODE_HIDE else clampi(int(cfg.get("team_count", 2)), 2, 4)
	var i := 0
	for id in get_sorted_ids():
		players[id]["team"] = i % limit
		i += 1
	_broadcast_players()


## Host: next round with swapped roles (hide and seek) and the same settings.
func rematch() -> void:
	# A rematch is a results-screen action, not a fresh lobby start: players are
	# intentionally unready after the previous round, so it uses the shared launch
	# path without reapplying the lobby readiness gate.
	if not online or not is_host or not match_in_progress:
		return
	if int(cfg.get("mode", 0)) == GameConstants.MODE_HIDE:
		cfg["hider_team"] = 1 - int(cfg.get("hider_team", 0))
	_launch_match()


func add_score(id: int, points: int) -> void:
	if is_host and players.has(id):
		players[id]["score"] = int(players[id]["score"]) + points


func get_score(id: int) -> int:
	if players.has(id):
		return int(players[id]["score"])
	return 0


func broadcast_players() -> void:
	_broadcast_players()


func get_sorted_ids() -> Array:
	var ids := players.keys()
	ids.sort()
	return ids


func get_player_info(id: int) -> Dictionary:
	if players.has(id):
		return players[id]
	return get_local_info()


func get_player_name(id: int) -> String:
	if players.has(id):
		return str(players[id]["name"])
	return "Player %d" % id


## IPv4 addresses of this device, private LAN ranges first.
func get_local_ips() -> Array:
	var out: Array = []
	for ip in IP.get_local_addresses():
		var s := str(ip)
		if s.contains(":"):
			continue # IPv6
		if s.begins_with("127.") or s.begins_with("0."):
			continue
		if s.begins_with("192.168.") or s.begins_with("10.") or s.begins_with("172."):
			out.push_front(s)
		else:
			out.append(s)
	return out


func default_room_name() -> String:
	return GameManager.t("default_room") % SaveManager.player_name


func is_busy() -> bool:
	return _connecting or _probing


## One-tap join for a room taken from `discovery.rooms`. Asks the host first (so "full" / "match running" are
## reported precisely), then opens the ENet connection on the port the host advertised.
## Failures are reported through `connection_failed`; success through `connection_succeeded`.
func join_room(room: Dictionary) -> void:
	if is_busy():
		return
	var ip := NetUtils.parse_ipv4(str(room.get("ip", "")))
	var rport := int(room.get("port", 0))
	if ip == "" or rport < 1024 or rport > 65535:
		connection_failed.emit(GameManager.t("invalid_ip"))
		return
	leave()
	_probing = true
	var attempt := _connect_attempt
	status_changed.emit(GameManager.t("connecting"))
	var result: String = await discovery.probe(ip)
	if not _probing or attempt != _connect_attempt:
		return                                   # cancelled (leave / back) while waiting
	_probing = false
	match result:
		"ok":
			var err := join_game(ip, rport)
			if err != "":
				connection_failed.emit(err)
		"full":
			connection_failed.emit(GameManager.t("lobby_full"))
		"busy":
			connection_failed.emit(GameManager.t("kicked_in_progress"))
		_:
			connection_failed.emit(GameManager.t("room_gone"))


## Data shared with LAN browsers (called by LanDiscovery on every query). Only room name + nickname.
func _advert_info() -> Dictionary:
	if not online or not is_host:
		return {}
	return {"room": room_name, "host": SaveManager.player_name, "players": players.size(),
		"max": max_players, "port": port, "in_progress": match_in_progress}


# ---------------------------------------------------------------------------
# Multiplayer signals

func _on_peer_connected(id: int) -> void:
	if not is_host:
		return
	if match_in_progress:
		_rpc_kicked.rpc_id(id, GameManager.t("kicked_in_progress"))
		get_tree().create_timer(0.6).timeout.connect(func() -> void:
			if online and is_host and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
				if multiplayer.get_peers().has(id):
					multiplayer.multiplayer_peer.disconnect_peer(id)
		)
	# Otherwise wait for the client's _rpc_register.


func _on_peer_disconnected(id: int) -> void:
	if is_host and players.has(id):
		var pname := str(players[id]["name"])
		players.erase(id)
		_broadcast_players()
		player_left.emit(id, pname)
		status_changed.emit(GameManager.t("left") % pname)


func _on_connected_to_server() -> void:
	if not _connecting or not online:
		return
	# ENet connected is not the same as an accepted lobby registration.
	# Keep the timeout and busy state until the authoritative list contains us.
	_rpc_register.rpc_id(1, SaveManager.player_name, SaveManager.color_index)
	status_changed.emit(GameManager.t("registering"))


func _on_connection_failed() -> void:
	if not _connecting:
		return # Ignore a stale failure after cancellation or a completed join.
	leave()
	connection_failed.emit(GameManager.t("conn_failed"))


func _on_server_disconnected() -> void:
	if not online:
		return # Delayed signal from a session already left.
	var was_connecting := _connecting
	leave()
	if was_connecting:
		connection_failed.emit(GameManager.t("join_host_left"))
	else:
		host_disconnected.emit()


# ---------------------------------------------------------------------------
# RPCs: client -> host (any_peer, validated on the host)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_register(pname: String, color: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id <= 1:
		return
	# A peer can finish its ENet handshake just before the delayed disconnect in
	# _on_peer_connected(). Re-check here: registration must never mutate the
	# lobby snapshot once the host has locked the match.
	if match_in_progress:
		_rpc_kicked.rpc_id(id, GameManager.t("kicked_in_progress"))
		return
	# Registration is a one-time transition. A repeated request must not reset
	# player state, but resending the authoritative snapshot makes the operation
	# idempotent and repairs a client that missed its initial room snapshot.
	if players.has(id):
		_rpc_player_list.rpc_id(id, players)
		_rpc_cfg.rpc_id(id, cfg)
		return
	if players.size() >= max_players:
		_rpc_kicked.rpc_id(id, GameManager.t("lobby_full"))
		return
	var clean := SaveManager.sanitize_name(pname)
	var count_a := 0
	var count_b := 0
	for k in players.keys():
		if int(players[k].get("team", 0)) == 0:
			count_a += 1
		else:
			count_b += 1
	players[id] = {"name": clean, "color": posmod(color, GameConstants.color_count()), "ready": false, "score": 0, "team": 0 if count_a <= count_b else 1}
	_broadcast_players()
	player_joined.emit(id, clean)
	status_changed.emit(GameManager.t("joined") % clean)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_ready(value: bool) -> void:
	if not multiplayer.is_server() or match_in_progress:
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		players[id]["ready"] = value
		_broadcast_players()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_update_info(pname: String, color: int) -> void:
	if not multiplayer.is_server() or match_in_progress:
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		players[id]["name"] = SaveManager.sanitize_name(pname)
		players[id]["color"] = posmod(color, GameConstants.color_count())
		_broadcast_players()


# ---------------------------------------------------------------------------
# RPCs: host -> clients (authority = peer 1)

@rpc("authority", "call_remote", "reliable")
func _rpc_player_list(list: Dictionary) -> void:
	var old := players.duplicate(true)
	players = list.duplicate(true)
	var my_id := multiplayer.get_unique_id()
	if _connecting and online and not is_host and players.has(my_id):
		_connecting = false
		connection_succeeded.emit()
		status_changed.emit("%s %s" % [GameManager.t("connected"), host_address])
	for id in players.keys():
		if not old.has(id) and id != my_id:
			player_joined.emit(id, str(players[id]["name"]))
	for id in old.keys():
		if not players.has(id):
			player_left.emit(id, str(old[id]["name"]))
	player_list_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_cfg(c: Dictionary) -> void:
	cfg = c.duplicate(true)
	cfg_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_start_match() -> void:
	_on_start_match()


@rpc("authority", "call_remote", "reliable")
func _rpc_return_to_lobby() -> void:
	_on_return_to_lobby()


@rpc("authority", "call_remote", "reliable")
func _rpc_kicked(reason: String) -> void:
	# Existing peers send translated text. Translate known messages into the
	# receiver's language while leaving unknown/older custom messages unchanged.
	var localized_reason := reason
	for key in ["lobby_full", "kicked_in_progress"]:
		if reason == Locale.t(key, "en") or reason == Locale.t(key, "ar"):
			localized_reason = GameManager.t(key)
			break
	var was_connecting := _connecting
	leave()
	if was_connecting:
		connection_failed.emit(localized_reason)
	else:
		kicked.emit(localized_reason)


# ---------------------------------------------------------------------------
# Internals

func _broadcast_players() -> void:
	if online and is_host:
		_rpc_player_list.rpc(players)
		_rpc_cfg.rpc(cfg)
	player_list_changed.emit()
	cfg_changed.emit()


func _on_start_match() -> void:
	match_in_progress = true
	GameManager.practice_mode = false
	match_started.emit()
	GameManager.go_to_arena()


func _on_return_to_lobby() -> void:
	match_in_progress = false
	returned_to_lobby.emit()
	GameManager.go_to_lobby()
