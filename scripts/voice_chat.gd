extends Node
## Autoload: VoiceChat  -  REAL voice chat over the existing ENet connection.
##
## Capture : AudioStreamMicrophone -> muted bus "VoiceRec" with an AudioEffectCapture.
## Encode  : mono, decimated to 16 kHz, 8-bit mu-law, 20 ms packets (320 bytes, ~16 KB/s while talking).
## Transport: client -> host (unreliable RPC), the HOST relays to the listeners that are allowed to hear it
##            (everybody, or team-only). The host decides who hears what, clients cannot bypass it.
## Playback: one AudioStreamGenerator player per remote speaker on the bus "Voice".
## Needs   : project setting audio/driver/enable_input = true (already set) and, on Android, the
##           RECORD_AUDIO permission ticked in the export preset (see README).
## Voice is only active while connected to a LAN room (NetworkManager.online).

signal speaking_changed(peer_id: int)

const MIC_BUS := "VoiceRec"
const VOICE_BUS := "Voice"
const NET_RATE := 16000
const CHUNK := 320                 # samples per packet (20 ms)
const VAD_THRESHOLD := 0.012       # RMS needed to open the mic in open-mic mode
const VAD_HANG := 0.35             # keep sending a little after the voice stops

var muted := false                 # my microphone is muted (button on the HUD / settings)
var team_only := false             # I talk to my team only
var ptt_down := false              # push-to-talk button held (only used when open mic is off)
var mic_ready := false             # capture is running
var permission_denied := false
var level := 0.0                   # live microphone level 0..1 (drives the meters)
var monitor := false               # mic test: hear myself (local only, never sent anywhere)
var test_mode := false             # mic test screen is open: capture runs even without a room
var master_mute := false           # mute everybody I would hear
var muted_peers: Dictionary = {}   # peer id -> true (per-player mute, local)

var _capture: AudioEffectCapture = null
var _mic_player: AudioStreamPlayer = null
var _mon_player: AudioStreamPlayer = null
var _mon_pb: AudioStreamGeneratorPlayback = null
var _pending := PackedFloat32Array()
var _sum := 0.0
var _count := 0
var _pos := 0.0
var _hang := 0.0
var _perm_timer := 0.0
var _asked := false
var _voices: Dictionary = {}       # sender id -> {"pb": AudioStreamGeneratorPlayback, "player": AudioStreamPlayer}
var _speaking: Dictionary = {}     # peer id -> time left
var _decode := PackedFloat32Array()
var _local_speaking := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_decode.resize(256)
	for i in 256:
		var sgn := -1.0 if (i & 0x80) != 0 else 1.0
		var y := float(i & 0x7F) / 127.0
		_decode[i] = sgn * (pow(256.0, y) - 1.0) / 255.0
	_ensure_buses()
	SettingsManager.refresh_audio()
	NetworkManager.player_left.connect(func(id: int, _n: String) -> void: forget_peer(id))


# ---------------------------------------------------------------------------
# Public API (HUD, lobby, settings, mic test)

func is_active() -> bool:
	return mic_ready and (NetworkManager.online or test_mode)


func has_voice_activity() -> bool:
	return _local_speaking or not _speaking.is_empty()


func is_speaking(id: int) -> bool:
	if id == multiplayer.get_unique_id():
		return _local_speaking
	return float(_speaking.get(id, 0.0)) > 0.0


func toggle_mute() -> void:
	muted = not muted


func toggle_team_only() -> void:
	team_only = not team_only


func toggle_peer_mute(id: int) -> void:
	if muted_peers.has(id):
		muted_peers.erase(id)
	else:
		muted_peers[id] = true
	_apply_peer_mutes()


func is_peer_muted(id: int) -> bool:
	return muted_peers.has(id)


func set_master_mute(v: bool) -> void:
	set_voice_output_muted(v)
	_apply_peer_mutes()


## Mute/unmute remote voice playback without affecting game audio or microphone capture.
func set_voice_output_muted(v: bool) -> void:
	master_mute = v
	_ensure_buses()
	var idx := AudioServer.get_bus_index(VOICE_BUS)
	if idx >= 0:
		AudioServer.set_bus_mute(idx, v)


func toggle_voice_output() -> void:
	set_voice_output_muted(not master_mute)


func status_text() -> String:
	if not bool(SettingsManager.get_setting("voice_enabled")):
		return GameManager.t("voice_off")
	if permission_denied:
		return GameManager.t("voice_no_permission")
	if not mic_ready:
		return GameManager.t("voice_starting")
	if muted:
		return GameManager.t("voice_muted")
	return GameManager.t("voice_on")


## Microphone test screen: capture without a room, optional local monitoring.
func set_test_mode(on: bool) -> void:
	test_mode = on
	if not on:
		set_monitor(false)


func set_monitor(on: bool) -> void:
	# Local sidetone is permitted only on the dedicated microphone-test screen.
	if on and not test_mode:
		monitor = false
		return
	monitor = on
	if on and _mon_player == null:
		_mon_player = AudioStreamPlayer.new()
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = NET_RATE
		gen.buffer_length = 0.4
		_mon_player.stream = gen
		_mon_player.bus = VOICE_BUS
		add_child(_mon_player)
		_mon_player.play()
		_mon_pb = _mon_player.get_stream_playback() as AudioStreamGeneratorPlayback
	elif not on and _mon_player != null:
		_mon_player.queue_free()
		_mon_player = null
		_mon_pb = null


# ---------------------------------------------------------------------------
# Main loop

func _process(delta: float) -> void:
	# Never feed the captured microphone back to the local speaker during a match.
	if monitor and not test_mode:
		set_monitor(false)
	var want := bool(SettingsManager.get_setting("voice_enabled")) and (NetworkManager.online or test_mode)
	if want and not mic_ready:
		_try_start(delta)
	elif not want and mic_ready:
		_stop()
	if mic_ready:
		_pump_capture(delta)
	for id in _speaking.keys():
		_speaking[id] = float(_speaking[id]) - delta
		if float(_speaking[id]) <= 0.0:
			_speaking.erase(id)
			speaking_changed.emit(int(id))
	if not NetworkManager.online and not test_mode:
		level = 0.0


func _has_permission() -> bool:
	if OS.get_name() != "Android":
		return true
	return OS.get_granted_permissions().has("android.permission.RECORD_AUDIO")


func _try_start(delta: float) -> void:
	if not bool(ProjectSettings.get_setting("audio/driver/enable_input", false)):
		permission_denied = true
		return
	if not _has_permission():
		if not _asked:
			_asked = true
			OS.request_permissions()      # asks for everything ticked in the export preset (RECORD_AUDIO)
		_perm_timer += delta
		if _perm_timer > 6.0 and _asked:
			permission_denied = true      # still no permission after the dialog: show the hint, keep polling
		return
	permission_denied = false
	_ensure_buses()
	if _mic_player == null:
		_mic_player = AudioStreamPlayer.new()
		_mic_player.stream = AudioStreamMicrophone.new()
		_mic_player.bus = MIC_BUS
		add_child(_mic_player)
	_mic_player.play()
	_pending.clear()
	_sum = 0.0
	_count = 0
	_pos = 0.0
	mic_ready = _capture != null


func _stop() -> void:
	mic_ready = false
	level = 0.0
	_local_speaking = false
	if _mic_player != null:
		_mic_player.stop()
	set_monitor(false)


func _ensure_buses() -> void:
	if AudioServer.get_bus_index(MIC_BUS) < 0:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, MIC_BUS)
		var cap := AudioEffectCapture.new()
		cap.buffer_length = 0.25
		AudioServer.add_bus_effect(idx, cap)
	# Capture remains available through AudioEffectCapture, but the raw mic bus
	# must never reach Master. Reapply this even if the bus already existed.
	var mic_idx := AudioServer.get_bus_index(MIC_BUS)
	if mic_idx >= 0:
		AudioServer.set_bus_mute(mic_idx, true)
	if AudioServer.get_bus_index(VOICE_BUS) < 0:
		var vidx := AudioServer.bus_count
		AudioServer.add_bus(vidx)
		AudioServer.set_bus_name(vidx, VOICE_BUS)
		AudioServer.set_bus_send(vidx, "Master")
		AudioServer.set_bus_mute(vidx, master_mute)
	var voice_idx := AudioServer.get_bus_index(VOICE_BUS)
	if voice_idx >= 0:
		AudioServer.set_bus_mute(voice_idx, master_mute)
	if _capture == null:
		var mi := AudioServer.get_bus_index(MIC_BUS)
		if mi >= 0 and AudioServer.get_bus_effect_count(mi) > 0:
			_capture = AudioServer.get_bus_effect(mi, 0) as AudioEffectCapture


func _pump_capture(delta: float) -> void:
	var voice_idx := AudioServer.get_bus_index(VOICE_BUS)
	if voice_idx >= 0:
		AudioServer.set_bus_mute(voice_idx, master_mute)
	if _capture == null:
		return
	var avail := _capture.get_frames_available()
	if avail <= 0:
		_local_speaking = _hang > 0.0
		_hang = maxf(0.0, _hang - delta)
		return
	var frames: PackedVector2Array = _capture.get_buffer(avail)
	var step := AudioServer.get_mix_rate() / float(NET_RATE)
	var gain := float(SettingsManager.get_setting("mic_gain"))
	for f in frames:
		_sum += (f.x + f.y) * 0.5 * gain
		_count += 1
		_pos += 1.0
		if _pos >= step:
			_pos -= step
			_pending.append(clampf(_sum / float(maxi(_count, 1)), -1.0, 1.0))
			_sum = 0.0
			_count = 0
	while _pending.size() >= CHUNK:
		var chunk := _pending.slice(0, CHUNK)
		_pending = _pending.slice(CHUNK)
		_handle_chunk(chunk, delta)


func _handle_chunk(chunk: PackedFloat32Array, delta: float) -> void:
	var acc := 0.0
	for v in chunk:
		acc += v * v
	var rms := sqrt(acc / float(chunk.size()))
	level = lerpf(level, clampf(rms * 6.0, 0.0, 1.0), 0.5)
	var open := true
	if not bool(SettingsManager.get_setting("voice_open_mic")):
		open = ptt_down                      # push to talk
	else:
		if rms > VAD_THRESHOLD:
			_hang = VAD_HANG
		_hang = maxf(0.0, _hang - delta)
		open = _hang > 0.0
	_local_speaking = open and not muted
	if monitor and _mon_pb != null:
		_push_samples(_mon_pb, chunk)       # local test only: never leaves this device
	if muted or not open or not NetworkManager.online:
		return                               # muted microphones transmit NOTHING
	var bytes := PackedByteArray()
	bytes.resize(chunk.size())
	for i in chunk.size():
		bytes[i] = _encode(chunk[i])
	var mine := multiplayer.get_unique_id()
	var tonly := team_only and int(NetworkManager.cfg.get("mode", 0)) != 0
	if multiplayer.is_server():
		_relay(mine, bytes, tonly)
	else:
		_rpc_voice_up.rpc_id(1, bytes, tonly)


func _encode(sample: float) -> int:
	var x := clampf(sample, -1.0, 1.0)
	var sgn := 0
	if x < 0.0:
		sgn = 0x80
		x = -x
	var y := log(1.0 + 255.0 * x) / log(256.0)
	return int(y * 127.0 + 0.5) | sgn


# ---------------------------------------------------------------------------
# Network: client -> host -> allowed listeners

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_voice_up(data: PackedByteArray, tonly: bool) -> void:
	if not multiplayer.is_server():
		return
	if data.size() != CHUNK:
		return                                # invalid packet
	_relay(multiplayer.get_remote_sender_id(), data, tonly)


func _relay(sender: int, data: PackedByteArray, tonly: bool) -> void:
	if not NetworkManager.players.has(sender):
		return
	if sender != 1 and _may_hear(1, sender, tonly):
		_play_voice(sender, data)
	for id in multiplayer.get_peers():
		if id == sender or not NetworkManager.players.has(id):
			continue
		if _may_hear(id, sender, tonly):
			_rpc_voice_down.rpc_id(id, sender, data)


## Host policy: team-only speech reaches teammates only. Hide and seek can force team-only voice.
func _may_hear(listener: int, sender: int, tonly: bool) -> bool:
	var mode := int(NetworkManager.cfg.get("mode", 0))
	if mode == 0:
		return true
	var policy := int(NetworkManager.cfg.get("voice_policy", 0))     # 0 = player choice, 1 = team only, 2 = everybody
	if policy == 1:
		tonly = true
	elif policy == 2:
		tonly = false
	if not tonly:
		return true
	return int(NetworkManager.players[listener].get("team", 0)) == int(NetworkManager.players[sender].get("team", 0))


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_voice_down(sender: int, data: PackedByteArray) -> void:
	if data.size() != CHUNK:
		return
	_play_voice(sender, data)


# ---------------------------------------------------------------------------
# Playback

func _play_voice(sender: int, data: PackedByteArray) -> void:
	if master_mute or muted_peers.has(sender):
		return
	if not _voices.has(sender):
		_make_voice(sender)
	var entry: Dictionary = _voices[sender]
	var pb: AudioStreamGeneratorPlayback = entry["pb"]
	var buf := PackedFloat32Array()
	buf.resize(data.size())
	for i in data.size():
		buf[i] = _decode[data[i]]
	_push_samples(pb, buf)
	if float(_speaking.get(sender, 0.0)) <= 0.0:
		speaking_changed.emit(sender)
	_speaking[sender] = 0.35


func _push_samples(pb: AudioStreamGeneratorPlayback, samples: PackedFloat32Array) -> void:
	if pb == null or pb.get_frames_available() < samples.size():
		return                                 # buffer full: drop (keeps latency low)
	var out := PackedVector2Array()
	out.resize(samples.size())
	for i in samples.size():
		out[i] = Vector2(samples[i], samples[i])
	pb.push_buffer(out)


func _make_voice(sender: int) -> void:
	var player := AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = NET_RATE
	gen.buffer_length = 0.5
	player.stream = gen
	player.bus = VOICE_BUS
	add_child(player)
	player.play()
	var pb := player.get_stream_playback() as AudioStreamGeneratorPlayback
	# small pre-buffer (40 ms of silence) against jitter
	var silence := PackedVector2Array()
	silence.resize(640)
	pb.push_buffer(silence)
	_voices[sender] = {"pb": pb, "player": player}


func _apply_peer_mutes() -> void:
	pass   # muting is applied when packets arrive (see _play_voice): muted speakers are dropped before playback


## Clean up the playback node of a player who left.
func forget_peer(id: int) -> void:
	if _voices.has(id):
		var entry: Dictionary = _voices[id]
		var pl: AudioStreamPlayer = entry["player"]
		if is_instance_valid(pl):
			pl.queue_free()
		_voices.erase(id)
	_speaking.erase(id)
	muted_peers.erase(id)
