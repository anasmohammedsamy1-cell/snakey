extends Node
## LAN room discovery over plain UDP (no internet needed). Created as a child of the NetworkManager autoload.
##
## PROTOCOL v1 - one UDP datagram = one UTF-8 JSON object, max 512 bytes, always containing
##   "g":"LOF"  (game magic)   "v":1 (protocol version)   "t":<type>   "n":<nonce string, 1..16 chars>
##   t = "q"  DISCOVERY query, sent by a browsing client to <subnet>.255, <subnet>.1 and 255.255.255.255
##   t = "j"  JOIN request / probe, unicast client -> host just before the ENet connect
##   t = "a"  room ADVERTISEMENT, unicast host -> sender of a "q" or "j" (echoes the nonce). Extra fields:
##            "room" (<=24 chars)  "host" (nickname, <=14)  "p" players  "m" max players
##            "port" (ENet port)   "s" 0 = open, 1 = match in progress
## Anything else (wrong magic/version/type, bad JSON, wrong field types, out-of-range values, oversize)
## is dropped silently and counted in `dropped_packets`.
## The host IP is NEVER taken from the payload: it is the datagram's source address (cannot be spoofed
## into pointing at a third machine). Only the nickname and room name are shared - no device data.
##
## Host side: UDP port DISCOVERY_PORT is bound only while a room exists and answers "q"/"j".
## Client side: an unbound/ephemeral socket sends queries every QUERY_INTERVAL and collects answers.
## A room that has not answered for ROOM_TTL seconds is removed from the list.

signal rooms_changed

const MAGIC := "LOF"
const VERSION := 1
const DISCOVERY_PORT := 24600          # UDP, deliberately outside the ENet fallback range 24565..24575
const QUERY_INTERVAL := 1.0
const ROOM_TTL := 5.0
const MAX_PACKET := 512
const MAX_ROOM_NAME := 24
const MAX_HOST_NAME := 14
const MIN_REPLY_GAP_MS := 250          # per-source rate limit on the host side

const NetUtils := preload("res://scripts/net_utils.gd")
const GameConstants := preload("res://scripts/game_constants.gd")

enum Mode { OFF, BROWSE, ADVERTISE }

## key "ip:port" -> {ip, port, room, host, players, max, in_progress, last_seen_ms}
var rooms: Dictionary = {}
var mode: int = Mode.OFF
var last_error := ""
var dropped_packets := 0
## Extra query targets (used by tests to reach 127.0.0.1).
var extra_targets: Array = []
## Host side: Callable returning {room, host, players, max, port, in_progress} or {} when no room is open.
var advert_provider := Callable()

var _udp: PacketPeerUDP = null
var _timer := 0.0
var _prune_timer := 0.0
var _ip_signature := ""
var _last_reply_ms: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func _exit_tree() -> void:
	stop()


# ---------------------------------------------------------------------------
# Public API

## Start looking for rooms. Safe to call repeatedly. Returns "" or an error text.
func start_browsing() -> String:
	if mode == Mode.BROWSE:
		return ""
	stop()
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	# Ephemeral local port (answers come back to it). If binding fails the socket is opened implicitly on first send.
	var err := _udp.bind(0, "*")
	if err != OK:
		push_warning("LanDiscovery: bind(0) failed (%d), relying on implicit socket" % err)
	mode = Mode.BROWSE
	last_error = ""
	_timer = QUERY_INTERVAL      # query immediately on the first frame
	_ip_signature = _local_signature()
	set_process(true)
	return ""


## Host side: answer queries while a room is open. Returns "" or an error text.
func start_advertising(provider: Callable) -> String:
	stop()
	var u := PacketPeerUDP.new()
	var err := u.bind(DISCOVERY_PORT, "*")
	if err != OK:
		last_error = "UDP %d: error %d" % [DISCOVERY_PORT, err]
		return last_error   # the ENet game itself still works, only auto-discovery is unavailable
	_udp = u
	advert_provider = provider
	mode = Mode.ADVERTISE
	last_error = ""
	set_process(true)
	return ""


func stop() -> void:
	if _udp != null:
		_udp.close()
	_udp = null
	var had := not rooms.is_empty()
	rooms.clear()
	_last_reply_ms.clear()
	advert_provider = Callable()
	mode = Mode.OFF
	set_process(false)
	if had:
		rooms_changed.emit()


## Forget the list and query again right away (REFRESH button).
func refresh() -> void:
	if mode != Mode.BROWSE:
		return
	if not rooms.is_empty():
		rooms.clear()
		rooms_changed.emit()
	_timer = QUERY_INTERVAL


## Ask one host directly ("j" message) whether it still has room.
## Returns "ok", "full", "busy" (match running), "timeout" or "error".
func probe(ip: String, timeout_sec := 1.5, port := DISCOVERY_PORT) -> String:
	var clean := NetUtils.parse_ipv4(ip)
	if clean == "":
		return "error"
	var u := PacketPeerUDP.new()
	u.bind(0, "*")
	var nonce := _make_nonce()
	if u.set_dest_address(clean, port) != OK:
		u.close()
		return "error"
	if u.put_packet(_encode({"t": "j", "n": nonce})) != OK:
		u.close()
		return "error"
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	var result := "timeout"
	while Time.get_ticks_msec() < deadline:
		while u.get_available_packet_count() > 0:
			var data := u.get_packet()
			if u.get_packet_error() != OK:
				continue
			var msg := parse_message(data)
			if msg.is_empty() or str(msg["t"]) != "a" or str(msg["n"]) != nonce or u.get_packet_ip() != clean:
				continue
			if int(msg["s"]) == 1:
				result = "busy"
			elif int(msg["p"]) >= int(msg["m"]):
				result = "full"
			else:
				result = "ok"
			u.close()
			return result
		if not is_inside_tree():
			break
		await get_tree().process_frame
	u.close()
	return result


# ---------------------------------------------------------------------------
# Message encoding / validation (static: unit-testable without sockets)

static func _make_nonce() -> String:
	return "%08x" % (randi() & 0x7fffffff)


static func _encode(fields: Dictionary) -> PackedByteArray:
	var d := {"g": MAGIC, "v": VERSION}
	d.merge(fields)
	return JSON.stringify(d).to_utf8_buffer()


## Returns a sanitised message Dictionary, or {} when the datagram is not a valid LOF v1 message.
static func parse_message(data: PackedByteArray) -> Dictionary:
	if data.size() == 0 or data.size() > MAX_PACKET:
		return {}
	var parsed: Variant = JSON.parse_string(data.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = parsed
	if not _is_num(d.get("v")) or int(d["v"]) != VERSION:
		return {}
	if typeof(d.get("g")) != TYPE_STRING or str(d["g"]) != MAGIC:
		return {}
	if typeof(d.get("t")) != TYPE_STRING or not ["q", "j", "a"].has(str(d["t"])):
		return {}
	if typeof(d.get("n")) != TYPE_STRING or str(d["n"]).length() < 1 or str(d["n"]).length() > 16:
		return {}
	var out := {"t": str(d["t"]), "n": str(d["n"])}
	if out["t"] != "a":
		return out
	for k in ["p", "m", "port", "s"]:
		if not _is_num(d.get(k)):
			return {}
	if typeof(d.get("room")) != TYPE_STRING or typeof(d.get("host")) != TYPE_STRING:
		return {}
	var p := int(d["p"])
	var m := int(d["m"])
	var port := int(d["port"])
	var s := int(d["s"])
	if m < 2 or m > GameConstants.MAX_PLAYERS or p < 0 or p > m:
		return {}
	if port < 1024 or port > 65535 or (s != 0 and s != 1):
		return {}
	out["room"] = NetUtils.clean_net_text(str(d["room"]), MAX_ROOM_NAME)
	out["host"] = NetUtils.clean_net_text(str(d["host"]), MAX_HOST_NAME)
	if out["room"] == "":
		out["room"] = "?"
	out["p"] = p
	out["m"] = m
	out["port"] = port
	out["s"] = s
	return out


static func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


# ---------------------------------------------------------------------------
# Main loop

func _process(delta: float) -> void:
	if _udp == null:
		return
	if mode == Mode.BROWSE:
		_timer += delta
		if _timer >= QUERY_INTERVAL:
			_timer = 0.0
			_send_queries()
		_prune_timer += delta
		if _prune_timer >= 0.5:
			_prune_timer = 0.0
			prune(Time.get_ticks_msec())
	_read_packets()


func _send_queries() -> void:
	var sig := _local_signature()
	if sig != _ip_signature:       # Wi-Fi / hotspot changed: old rooms belong to another network
		_ip_signature = sig
		if not rooms.is_empty():
			rooms.clear()
			rooms_changed.emit()
	var q := _encode({"t": "q", "n": _make_nonce()})
	var targets: Array = NetUtils.discovery_targets(IP.get_local_addresses())
	targets.append_array(extra_targets)
	var sent := 0
	for target in targets:
		if _udp.set_dest_address(str(target), DISCOVERY_PORT) == OK and _udp.put_packet(q) == OK:
			sent += 1
	last_error = "" if sent > 0 else "no_network"


func _local_signature() -> String:
	var ips: Array = []
	for ip in IP.get_local_addresses():
		var s := str(ip)
		if not s.contains(":") and not s.begins_with("127."):
			ips.append(s)
	ips.sort()
	return ",".join(ips)


func _read_packets() -> void:
	var budget := 32       # never spend a whole frame on a flood
	while _udp.get_available_packet_count() > 0 and budget > 0:
		budget -= 1
		var data := _udp.get_packet()
		if _udp.get_packet_error() != OK:
			continue
		var from_ip := _udp.get_packet_ip()
		var from_port := _udp.get_packet_port()
		var msg := parse_message(data)
		if msg.is_empty():
			dropped_packets += 1
			continue
		var t := str(msg["t"])
		if mode == Mode.ADVERTISE and (t == "q" or t == "j"):
			_answer(from_ip, from_port, str(msg["n"]), t)
		elif mode == Mode.BROWSE and t == "a":
			_add_room(from_ip, msg)


func _answer(ip: String, port: int, nonce: String, kind := "q") -> void:
	if not advert_provider.is_valid():
		return
	var now := Time.get_ticks_msec()
	# Rate-limit per source AND message type: otherwise a join probe ("j") that lands right after a
	# browse query ("q") from the same phone would be dropped and the join check would time out.
	var gap_key := "%s|%s" % [ip, kind]
	if now - int(_last_reply_ms.get(gap_key, -100000)) < MIN_REPLY_GAP_MS:
		return
	_last_reply_ms[gap_key] = now
	if _last_reply_ms.size() > 64:
		_last_reply_ms.clear()
	var info: Dictionary = advert_provider.call()
	if info.is_empty():
		return
	var reply := _encode({
		"t": "a", "n": nonce,
		"room": str(info["room"]), "host": str(info["host"]),
		"p": int(info["players"]), "m": int(info["max"]),
		"port": int(info["port"]), "s": 1 if bool(info["in_progress"]) else 0,
	})
	if _udp.set_dest_address(ip, port) == OK:
		_udp.put_packet(reply)


func _add_room(ip: String, msg: Dictionary) -> void:
	if NetUtils.parse_ipv4(ip) == "":
		return
	var key := "%s:%d" % [ip, int(msg["port"])]
	var entry := {
		"ip": ip, "port": int(msg["port"]), "room": str(msg["room"]), "host": str(msg["host"]),
		"players": int(msg["p"]), "max": int(msg["m"]), "in_progress": int(msg["s"]) == 1,
	}
	var changed := true
	if rooms.has(key):
		var old: Dictionary = rooms[key]
		changed = false
		for k in entry.keys():
			if old.get(k) != entry[k]:
				changed = true
				break
	entry["last_seen_ms"] = Time.get_ticks_msec()
	rooms[key] = entry         # duplicates (same host answering several queries) just refresh the entry
	if changed:
		rooms_changed.emit()


## Removes rooms silent for more than ROOM_TTL seconds. `now_ms` is injectable for tests.
func prune(now_ms: int) -> void:
	var removed := false
	for key in rooms.keys():
		if now_ms - int(rooms[key]["last_seen_ms"]) > int(ROOM_TTL * 1000.0):
			rooms.erase(key)
			removed = true
	if removed:
		rooms_changed.emit()


func get_room_list() -> Array:
	var list: Array = rooms.values()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["room"]) < str(b["room"]))
	return list
