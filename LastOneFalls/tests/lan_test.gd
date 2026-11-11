extends Node
## Single-process tests for the LAN layer: IPv4 / digit normalisation, discovery protocol validation,
## expiry, host/client lifecycle, discovery over loopback. Run:
##   godot --headless --path . res://tests/lan_test.tscn
## Prints PASS / FAIL lines, exits with code 1 on any failure.

const NetUtils := preload("res://scripts/net_utils.gd")
const LanDiscovery := preload("res://scripts/lan_discovery.gd")

var _failures := 0


func _ready() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	if cond:
		print("[LAN] PASS  ", label)
	else:
		_failures += 1
		print("[LAN] FAIL  ", label)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _run() -> void:
	_test_ipv4()
	_test_port()
	_test_protocol()
	_test_targets()
	await _test_lifecycle()
	await _test_discovery_loopback()
	NetworkManager.leave()
	print("[LAN] finished with %d failure(s)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _test_ipv4() -> void:
	for ok in ["192.168.43.1", " 10.0.0.5 ", "172.20.10.1", "127.0.0.1", "192.168.001.010"]:
		_check(NetUtils.parse_ipv4(ok) != "", "valid IPv4 accepted: '%s'" % ok)
	_check(NetUtils.parse_ipv4("192.168.001.010") == "192.168.1.10", "leading zeros canonicalised")
	for bad in ["", "abc", "192.168.1", "192.168.1.256", "1.2.3.4.5", "192.168.1.", "192..1.1", "0.0.0.0", "255.255.255.255",
			"224.0.0.1", "::1", "192.168.1.1:24565", "192.168.-1.1", "1.2.3.4a", "١٩٢.١٦٨.٤٣"]:
		_check(NetUtils.parse_ipv4(bad) == "", "invalid IPv4 rejected: '%s'" % bad)
	# Arabic-Indic, Persian, full-width digits and Arabic separators / invisible RTL marks
	_check(NetUtils.parse_ipv4("١٩٢.١٦٨.٤٣.١") == "192.168.43.1", "Arabic-Indic digits normalised")
	_check(NetUtils.parse_ipv4("۱۹۲.۱۶۸.۴۳.۱") == "192.168.43.1", "Persian digits normalised")
	_check(NetUtils.parse_ipv4("１９２．１６８．４３．１") == "192.168.43.1", "full-width digits normalised")
	_check(NetUtils.parse_ipv4("١٩٢٫١٦٨٫٤٣٫١") == "192.168.43.1", "Arabic decimal separator (U+066B) normalised")
	_check(NetUtils.parse_ipv4("\u200F١٩٢.١٦٨.٤٣.١\u200E ") == "192.168.43.1", "RTL marks + spaces stripped")
	_check(NetUtils.parse_ipv4("١٩٢.١٦٨.٤٣.٢٥٦") == "", "Arabic digits out of range rejected")


func _test_port() -> void:
	_check(NetUtils.parse_port("24565") == 24565, "port ASCII")
	_check(NetUtils.parse_port("٢٤٥٦٥") == 24565, "port Arabic-Indic digits")
	_check(NetUtils.parse_port("80") == -1, "port < 1024 rejected")
	_check(NetUtils.parse_port("70000") == -1, "port > 65535 rejected")
	_check(NetUtils.parse_port("12a4") == -1, "port with letters rejected")


func _advert(extra := {}) -> PackedByteArray:
	var d := {"g": "LOF", "v": 1, "t": "a", "n": "abc", "room": "Ahmed's Arena", "host": "Ahmed", "p": 2, "m": 8, "port": 24565, "s": 0}
	d.merge(extra, true)
	return JSON.stringify(d).to_utf8_buffer()


func _test_protocol() -> void:
	var q := LanDiscovery.parse_message(JSON.stringify({"g": "LOF", "v": 1, "t": "q", "n": "x1"}).to_utf8_buffer())
	_check(not q.is_empty() and q["t"] == "q", "discovery query parsed")
	var j := LanDiscovery.parse_message(JSON.stringify({"g": "LOF", "v": 1, "t": "j", "n": "x1"}).to_utf8_buffer())
	_check(not j.is_empty() and j["t"] == "j", "join request parsed")
	var a := LanDiscovery.parse_message(_advert())
	_check(not a.is_empty() and a["t"] == "a" and a["room"] == "Ahmed's Arena" and a["p"] == 2 and a["m"] == 8, "room advertisement parsed")
	_check(LanDiscovery.parse_message("garbage".to_utf8_buffer()).is_empty(), "malformed (not JSON) dropped")
	_check(LanDiscovery.parse_message("[1,2]".to_utf8_buffer()).is_empty(), "JSON non-object dropped")
	_check(LanDiscovery.parse_message(PackedByteArray()).is_empty(), "empty packet dropped")
	_check(LanDiscovery.parse_message(_advert({"g": "XXX"})).is_empty(), "wrong magic dropped")
	_check(LanDiscovery.parse_message(_advert({"v": 2})).is_empty(), "wrong version dropped")
	_check(LanDiscovery.parse_message(_advert({"t": "z"})).is_empty(), "unknown type dropped")
	_check(LanDiscovery.parse_message(_advert({"n": ""})).is_empty(), "empty nonce dropped")
	_check(LanDiscovery.parse_message(_advert({"p": 9})).is_empty(), "players > max dropped")
	_check(LanDiscovery.parse_message(_advert({"m": 99})).is_empty(), "max above MAX_PLAYERS dropped")
	_check(LanDiscovery.parse_message(_advert({"port": 80})).is_empty(), "bad port dropped")
	_check(LanDiscovery.parse_message(_advert({"s": 5})).is_empty(), "bad status dropped")
	_check(LanDiscovery.parse_message(_advert({"p": "2"})).is_empty(), "wrong field type dropped")
	_check(LanDiscovery.parse_message(_advert({"room": "x".repeat(600)})).is_empty(), "oversize packet dropped")
	var long := LanDiscovery.parse_message(_advert({"room": "y".repeat(100)}))
	_check(not long.is_empty() and str(long["room"]).length() == LanDiscovery.MAX_ROOM_NAME, "long room name truncated")
	var ctl := LanDiscovery.parse_message(_advert({"room": "A\nB\u202EC"}))
	_check(not ctl.is_empty() and ctl["room"] == "ABC", "control / bidi-override characters stripped")


func _test_targets() -> void:
	var t := NetUtils.discovery_targets(["192.168.43.17", "127.0.0.1", "fe80::1", "169.254.1.2"])
	_check(t.has("192.168.43.255") and t.has("192.168.43.1") and t.has("255.255.255.255"), "discovery targets contain subnet broadcast, gateway, global")
	_check(not t.has("127.0.0.255"), "loopback / link-local / IPv6 skipped")
	var t2 := NetUtils.discovery_targets(["192.168.43.1"])
	_check(not t2.has("192.168.43.1"), "own address not queried")


func _test_lifecycle() -> void:
	NetworkManager.leave()
	_check(NetworkManager.host_game(80) != "", "host_game rejects privileged port")
	_check(not NetworkManager.online, "failed host leaves session offline")
	_check(NetworkManager.join_game("not an ip", 24565) != "", "join_game rejects invalid IP")
	_check(NetworkManager.join_game("192.168.1.2", 80) != "", "join_game rejects invalid port")
	# Server creation failure / fallback: occupy the port with a UDP socket first
	var blocker := PacketPeerUDP.new()
	var berr := blocker.bind(24570, "*")
	if berr == OK:
		var err: String = NetworkManager.host_game(24570, "Fallback", 4)
		_check(err == "", "host_game falls back when port is occupied: " + err)
		if NetworkManager.port == 24570:
			print("[LAN] SKIP  fallback check: this OS lets ENet share the UDP port (SO_REUSEADDR)")
		else:
			_check(NetworkManager.port > 24570 and NetworkManager.port <= 24580, "fallback port used and advertised (%d)" % NetworkManager.port)
		_check(NetworkManager.host_game(24570) != "", "second host_game while hosting refused (no duplicate server)")
		NetworkManager.leave()
		blocker.close()
	else:
		print("[LAN] SKIP  port-occupied test (could not bind blocker: %d)" % berr)
	# Host lifecycle + room settings
	var e2: String = NetworkManager.host_game(24571, "", 5)
	_check(e2 == "" and NetworkManager.online and NetworkManager.is_host, "host_game ok")
	_check(NetworkManager.room_name != "", "default room name generated: " + NetworkManager.room_name)
	_check(NetworkManager.max_players == 5 and int(NetworkManager.cfg.get("max_players", 0)) == 5, "player limit stored and mirrored in cfg")
	_check(NetworkManager.discovery.mode == LanDiscovery.Mode.ADVERTISE, "host advertises after room creation")
	NetworkManager.leave()
	_check(not NetworkManager.online and NetworkManager.discovery.mode == LanDiscovery.Mode.OFF, "leave() closes server and stops advertising")
	# Client connection failure: nothing listens on this port -> connection_failed (or timeout) must come
	var state := {"failed": false, "reason": ""}
	var cb := func(reason: String) -> void:
		state["failed"] = true
		state["reason"] = reason
	NetworkManager.connection_failed.connect(cb)
	var jerr: String = NetworkManager.join_game("127.0.0.1", 24598)
	_check(jerr == "", "join_game starts async connect")
	_check(NetworkManager.join_game("127.0.0.1", 24598) != "", "second join while connecting refused (no duplicate connection)")
	var waited := 0.0
	while not state["failed"] and waited < 12.0:
		await _wait(0.25)
		waited += 0.25
	_check(state["failed"], "connection failure reported (%s) after %.1fs" % [state["reason"], waited])
	_check(not NetworkManager.online, "failed connection cleans up")
	NetworkManager.connection_failed.disconnect(cb)


func _test_discovery_loopback() -> void:
	var host_err: String = NetworkManager.host_game(24572, "Loop Room", 3)
	_check(host_err == "", "loopback host ready: " + host_err)
	if host_err != "":
		return
	_check(NetworkManager.discovery.mode == LanDiscovery.Mode.ADVERTISE, "UDP discovery port bound by host")
	# Browser = a second LanDiscovery instance inside this process, aimed at 127.0.0.1
	var browser := LanDiscovery.new()
	add_child(browser)
	browser.extra_targets = ["127.0.0.1"]
	browser.start_browsing()
	var waited := 0.0
	while browser.rooms.is_empty() and waited < 5.0:
		await _wait(0.25)
		waited += 0.25
	await _wait(1.2)
	# On a machine with a real network card the host also answers on its LAN address, so only the
	# loopback entry is counted here (the same room under another IP is not a duplicate bug).
	var loop_rooms: Array = browser.get_room_list().filter(func(e: Dictionary) -> bool: return e["ip"] == "127.0.0.1")
	_check(loop_rooms.size() == 1, "room discovered automatically (%d)" % loop_rooms.size())
	if loop_rooms.size() == 1:
		var r: Dictionary = loop_rooms[0]
		_check(r["room"] == "Loop Room" and r["players"] == 1 and r["max"] == 3 and r["port"] == NetworkManager.port and not r["in_progress"], "room entry shows name / players / max / port")
		_check(r["ip"] == "127.0.0.1", "host IP taken from the datagram source")
	await _wait(2.0)
	loop_rooms = browser.get_room_list().filter(func(e: Dictionary) -> bool: return e["ip"] == "127.0.0.1")
	_check(loop_rooms.size() == 1, "repeated advertisements do not create duplicates")
	var res: String = await browser.probe("127.0.0.1")
	_check(res == "ok", "join probe -> ok (%s)" % res)
	NetworkManager.match_in_progress = true
	await _wait(0.4)   # the host rate-limits answers per source (MIN_REPLY_GAP_MS)
	res = await browser.probe("127.0.0.1")
	_check(res == "busy", "join probe -> busy while a match runs (%s)" % res)
	NetworkManager.match_in_progress = false
	# Expiry: pretend 6 seconds passed
	browser.prune(Time.get_ticks_msec() + 6000)
	_check(browser.rooms.is_empty(), "stale room entry expires after TTL")
	# Host closes -> no more answers; probe times out
	NetworkManager.leave()
	res = await browser.probe("127.0.0.1", 0.8)
	_check(res == "timeout", "closed room no longer answers (%s)" % res)
	browser.stop()
	browser.queue_free()
