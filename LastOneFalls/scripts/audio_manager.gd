extends Node
## Autoload: AudioManager
## Egyptian-comedy voice lines (recorded files or Arabic TTS) + synthesized fallback sounds/music.
## Drop real files into res://assets/audio/ (see README) and they are used instead.


const MIX_RATE := 44100
const MUSIC_RATE := 22050
const MUSIC_BASE_DB := -12.0
const MUSIC_DUCK_DB := -9.0
const POOL_SIZE := 14
const POOL_SIZE_3D := 4
const SOUND_COOLDOWN := 0.045

## ---- Egyptian comedy sound-effect layer ---------------------------------------
## Recorded effects live in res://assets/audio/voice/<event>_<n>.mp3|ogg|wav  (n = 1..12).
## Several files for one event = random pick. An event with NO file keeps the synthesized beep.
const VOICE_DIR := "res://assets/audio/voice/"
const VOICE_EXTS := ["mp3", "ogg", "wav"]
const VOICE_EVENTS := ["click", "jump", "land", "push", "hit", "fall", "crack", "countdown", "go", "victory", "footstep_a", "footstep_b", "whoosh"]
## Off: the recorded clips are sound effects, not speech. Set true to let the phone's Arabic
## text-to-speech read VOICE_LINES for events that have no recorded file.
const USE_TTS := false
## Only the recorded clips make sound. Anything without a recorded clip stays SILENT:
## no synthesized beeps and no generated music. (Flip to true to bring them back.)
const SYNTH_FALLBACK := false
const GENERATED_MUSIC := true
const VOICE_INTERRUPT := ["fall", "go", "victory", "hit"]
## event: [cooldown_sec, chance 0..1, min_volume_db]
const VOICE_RULES := {
	"click": [0.08, 1.0, -30.0],
	"jump": [0.15, 1.0, -30.0],
	"land": [0.15, 1.0, -30.0],
	"push": [0.12, 1.0, -30.0],
	"hit": [0.1, 1.0, -30.0],
	"fall": [0.3, 1.0, -30.0],
	"crack": [0.25, 1.0, -30.0],
	"countdown": [0.2, 1.0, -30.0],
	"go": [0.3, 1.0, -30.0],
	"victory": [0.5, 1.0, -30.0],
	"footstep_a": [0.15, 1.0, -30.0],
	"footstep_b": [0.15, 1.0, -30.0],
	"whoosh": [0.15, 1.0, -30.0],
}
const VOICE_LINES := {
	"click": ["أيوه كده", "عاش يا وحش", "تمام يا باشا", "ماشي يا ريس", "حاضر", "إيه الجمال ده"],
	"jump": ["هوبّا!", "اوبّا!", "طِرت يا عم", "إلحقوني!", "يا ساتر"],
	"land": ["آه يا ضهري", "يا نهار أبيض", "نزلت على وشّي", "خبطة محترمة", "الله يسامحك يا أرض"],
	"push": ["خد يا عم", "وسّع كده", "اتزحزح يا بيه", "خد دي بقى", "ابعد يا جدع"],
	"hit": ["يا نهار أسود", "ضربة معلم", "إيه ده يا جدع", "ماااما!", "ودّوني المستشفى"],
	"fall": ["أنا وقعت يا ناس", "مع السلامة يا حبيبي", "يا خسارة يا بطل", "رايح فين يا عم", "الحقوني!", "وقّعوني تاني"],
	"crack": ["الأرض بتتشقق يا جماعة", "يا ساتر يا رب", "حاسب بتقع", "مين اللي عمل الأرضية دي"],
	"countdown": ["جاهز يا بطل؟", "واحد.. اتنين.."],
	"go": ["يلا يا رجالة!", "اجري اجري!", "على بركة الله ويلا", "اللي يتأخر يقع"],
	"victory": ["أنا الكسبان يا ولاد!", "هاتوا الكاس يا جماعة", "مين الجامد هنا؟ أنا!", "مبروك عليّا والله", "ما قلتلكوش؟ أنا الأول"],
}

## Optional file overrides: name -> candidate path
const OPTIONAL_FILES := {
	"click": "res://assets/audio/click.wav",
	"jump": "res://assets/audio/jump.wav",
	"land": "res://assets/audio/land.wav",
	"push": "res://assets/audio/push.wav",
	"hit": "res://assets/audio/hit.wav",
	"fall": "res://assets/audio/fall.wav",
	"countdown": "res://assets/audio/countdown.wav",
	"go": "res://assets/audio/go.wav",
	"victory": "res://assets/audio/victory.wav",
	"crack": "res://assets/audio/crack.wav",
	"whoosh": "res://assets/audio/whoosh.wav",
}

var _sfx: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _last_played: Dictionary = {}
var _music_player: AudioStreamPlayer
var _music_thread: Thread
var _layer_players: Array[AudioStreamPlayer] = []     # [pulse, chaos] extra music layers (generated music only)
var _layer_db: Array[float] = [-60.0, -60.0]
var _music_level := 0                                 # 0 calm, 1 pulse (tension), 2 chaos (sudden death)
var _duck_db := 0.0
var _voice_files: Dictionary = {}
var _voice_last: Dictionary = {}
var _tts_voice := ""
var _voice_ready := false
var _countdown_step := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	for i in POOL_SIZE_3D:
		var p := AudioStreamPlayer3D.new()
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
		p.max_distance = 12.0
		p.unit_size = 1.5
		p.bus = "Character"
		add_child(p)
		_pool3d.append(p)
	if SYNTH_FALLBACK:
		_generate_sfx()
	_setup_voice()
	_start_music()


func _exit_tree() -> void:
	if _music_thread != null and _music_thread.is_started():
		_music_thread.wait_to_finish()


func _process(delta: float) -> void:
	if _music_player == null:
		return
	# Music ducks while someone is talking in voice chat (optional setting).
	var target := 0.0
	if bool(SettingsManager.get_setting("audio_ducking")) and VoiceChat.has_voice_activity():
		target = MUSIC_DUCK_DB
	_duck_db = move_toward(_duck_db, target, 40.0 * delta)
	_music_player.volume_db = MUSIC_BASE_DB + _duck_db
	for i in _layer_players.size():
		var want := MUSIC_BASE_DB + _duck_db - 3.0 if _music_level > i else -60.0
		_layer_db[i] = move_toward(_layer_db[i], want, 70.0 * delta)
		_layer_players[i].volume_db = _layer_db[i]


## 0 = calm loop, 1 = adds the tension pulse, 2 = adds the chaos layer (all layers stay in sync).
func set_music_intensity(level: int) -> void:
	_music_level = clampi(level, 0, 2)


## Background music: res://assets/audio/music.ogg if present, otherwise a small
## generated loop (built on a worker thread so startup never hitches).
func _start_music() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = _valid_bus("Music")
	_music_player.volume_db = MUSIC_BASE_DB
	add_child(_music_player)
	var path := ""
	for ext in ["ogg", "mp3", "wav"]:
		if ResourceLoader.exists("res://assets/audio/music." + ext):
			path = "res://assets/audio/music." + ext
			break
	if path != "":
		var st = load(path)
		if st != null and "loop" in st:
			st.loop = true
		_music_player.stream = st
		_music_player.play()
		return
	if not GENERATED_MUSIC:
		return
	_music_thread = Thread.new()
	_music_thread.start(_music_worker)


func _music_worker() -> void:
	var bufs: Array = [_build_music(), _build_music_extra(1), _build_music_extra(2)]
	_on_music_built.call_deferred(bufs)


func _on_music_built(bufs: Array) -> void:
	if _music_thread != null and _music_thread.is_started():
		_music_thread.wait_to_finish()
	if _music_player == null:
		return
	_music_player.stream = _make_stream(bufs[0], true, 1.0, MUSIC_RATE, 0.5)
	_layer_players.clear()
	for i in 2:
		var lp := AudioStreamPlayer.new()
		lp.bus = _valid_bus("Music")
		lp.volume_db = -60.0
		lp.stream = _make_stream(bufs[i + 1], true, 0.8, MUSIC_RATE, 0.5)
		add_child(lp)
		_layer_players.append(lp)
	# Start every layer in the same frame so the loops stay aligned (all are exactly 4 bars long).
	_music_player.play()
	for lp in _layer_players:
		lp.play()


## Extra loop layers, same length / tempo as the base loop.
## 1 = pulse: steady eighth-note hats, hand-clap on beats 3 and 7, octave bass pulse.
## 2 = chaos: sixteenth hats, kick on every quarter, high warbling "zaghroota"-style trill.
func _build_music_extra(layer: int) -> PackedFloat32Array:
	var r := MUSIC_RATE
	var eighth := 0.3
	var bar := eighth * 8.0
	var bass := [38.0, 38.0, 43.0, 45.0]
	var b := PackedFloat32Array()
	for i in 4:
		var t0 := float(i) * bar
		var bf := _note(float(bass[i]))
		for k in 8:
			var tk := t0 + float(k) * eighth
			if layer == 1:
				b = _add_tone(b, tk, 0.05, 1200.0, 900.0, 0.14, 1, 0.001, 2.0, r)
				b = _add_tone(b, tk, 0.18, bf * 2.0, bf * 2.0, 0.16, 2, 0.01, 1.5, r)
				if k == 2 or k == 6:
					b = _add_tone(b, tk, 0.09, 1800.0, 1400.0, 0.26, 1, 0.001, 1.6, r)
			else:
				b = _add_tone(b, tk, 0.04, 1500.0, 1100.0, 0.12, 1, 0.001, 2.0, r)
				b = _add_tone(b, tk + eighth * 0.5, 0.04, 1500.0, 1100.0, 0.10, 1, 0.001, 2.0, r)
				if k % 2 == 0:
					b = _add_tone(b, tk, 0.18, 150.0, 60.0, 0.5, 0, 0.002, 1.6, r)
		if layer == 2 and i == 3:
			for w in 16:
				var f := 1500.0 if w % 2 == 0 else 1950.0
				b = _add_tone(b, t0 + float(w) * 0.13, 0.12, f, f, 0.10, 0, 0.01, 1.2, r)
	b.resize(int(4.0 * bar * float(r)))
	return b


## Egyptian-flavoured loop: maqam Hijaz on D, "maqsum" drum pattern (Dum Tak _ Tak Dum _ Tak _),
## drone bass, ney-like lead. 4 bars, 100 BPM. Drop a real sung track in as assets/audio/music.mp3|ogg.
func _build_music() -> PackedFloat32Array:
	var r := MUSIC_RATE
	var eighth := 0.3
	var bar := eighth * 8.0
	var dum := [1, 0, 0, 0, 1, 0, 0, 0]
	var tak := [0, 1, 0, 1, 0, 0, 1, 0]
	var bass := [38.0, 38.0, 43.0, 45.0]
	var lead := [
		[74, 75, 78, 75, 74, -1, 70, -1],
		[69, 70, 74, 75, 78, -1, 75, -1],
		[79, 78, 75, 74, 75, 78, 79, -1],
		[78, 75, 74, 70, 69, 70, 74, -1],
	]
	var b := PackedFloat32Array()
	for i in 4:
		var t0 := float(i) * bar
		var bf := _note(float(bass[i]))
		b = _add_tone(b, t0, bar, _note(50.0), _note(50.0), 0.05, 0, 0.2, 0.5, r)
		b = _add_tone(b, t0, bar, _note(57.0), _note(57.0), 0.04, 0, 0.2, 0.5, r)
		var mel: Array = lead[i]
		for k in 8:
			var tk := t0 + float(k) * eighth
			if int(dum[k]) == 1:
				b = _add_tone(b, tk, 0.2, 170.0, 65.0, 0.55, 0, 0.002, 1.6, r)
				b = _add_tone(b, tk, 0.42, bf, bf, 0.38, 2, 0.01, 1.3, r)
			if int(tak[k]) == 1:
				b = _add_tone(b, tk, 0.05, 1100.0, 800.0, 0.2, 1, 0.001, 2.0, r)
			var m := int(mel[k])
			if m < 0:
				continue
			var f := _note(float(m))
			b = _add_tone(b, tk, 0.42, f, f, 0.2, 0, 0.012, 1.4, r)
			b = _add_tone(b, tk, 0.3, f * 2.0, f * 2.0, 0.05, 0, 0.01, 2.0, r)
			b = _add_tone(b, tk, 0.3, f * 3.0, f * 3.0, 0.02, 0, 0.01, 2.0, r)
	b.resize(int(4.0 * bar * float(r)))
	return b


# ---------------------------------------------------------------------------
# Egyptian comedy voice layer
# ---------------------------------------------------------------------------
func _setup_voice() -> void:
	for event in VOICE_EVENTS:
		var found: Array = []
		for n in range(1, 13):
			for ext in VOICE_EXTS:
				var vpath: String = "%s%s_%d.%s" % [VOICE_DIR, event, n, ext]
				if ResourceLoader.exists(vpath):
					var st = load(vpath)
					if st != null:
						found.append(st)
					break
		if not found.is_empty():
			_voice_files[event] = found
	_tts_voice = _find_arabic_voice() if USE_TTS else ""
	_voice_ready = not _voice_files.is_empty() or _tts_voice != ""


## Prefers an Egyptian Arabic voice (ar-EG), otherwise any Arabic voice. "" if none.
func _find_arabic_voice() -> String:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return ""
	var any_arabic := ""
	for v in DisplayServer.tts_get_voices():
		var lang := str(v.get("language", "")).to_lower().replace("_", "-")
		if lang == "ar-eg":
			return str(v.get("id", ""))
		if any_arabic == "" and lang.begins_with("ar"):
			any_arabic = str(v.get("id", ""))
	return any_arabic


## Returns true when the event was played by the voice layer, so the caller must not also
## play the synthesized beep. Events without a recorded file return false (beep fallback).
## When `position` is given, the sound is played as 3D positional audio attenuated by distance.
func _voice_play(sfx_name: String, volume_db: float, category: String, position: Variant = null) -> bool:
	if not _voice_ready or not VOICE_EVENTS.has(sfx_name):
		return false
	var files: Array = _voice_files.get(sfx_name, [])
	if files.is_empty() and (_tts_voice == "" or not VOICE_LINES.has(sfx_name)):
		return false
	if sfx_name == "go":
		_countdown_step = 0
	var rule: Array = VOICE_RULES.get(sfx_name, [0.1, 1.0, -30.0])
	if volume_db < float(rule[2]):
		return true
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_voice_last.get(sfx_name, -1000.0)) < float(rule[0]):
		return true
	if randf() > float(rule[1]):
		return true
	if bool(SettingsManager.get_setting("game_audio_muted")) or bool(SettingsManager.get_setting("muted")):
		return true
	_voice_last[sfx_name] = now
	var step := 0
	if sfx_name == "countdown":
		step = _countdown_step
		_countdown_step += 1
	if not files.is_empty():
		var stream = files[step % files.size()] if sfx_name == "countdown" else files.pick_random()
		if position != null:
			_play_voice_stream_3d(stream, position as Vector3, volume_db, category)
		else:
			_play_voice_stream(stream, volume_db, category)
		return true
	var lines: Array = VOICE_LINES[sfx_name]
	var text: String = str(lines[step % lines.size()] if sfx_name == "countdown" else lines.pick_random())
	DisplayServer.tts_speak(text, _tts_voice, 100, 1.0, 1.0, 0, VOICE_INTERRUPT.has(sfx_name))
	return true


func _play_voice_stream(stream: AudioStream, volume_db: float, category: String) -> void:
	var routed_bus := _valid_bus(category)
	var player := _find_free_player(_bus_priority(routed_bus))
	if player == null:
		return
	player.stop()
	player.stream = stream
	player.bus = routed_bus
	player.set_meta("audio_priority", _bus_priority(routed_bus))
	player.set_meta("audio_started_ms", Time.get_ticks_msec())
	player.pitch_scale = randf_range(0.96, 1.04)
	var max_db := -2.0 if bool(SettingsManager.get_setting("audio_comfort")) else 0.0
	player.volume_db = clampf(volume_db, -24.0, max_db)
	player.play()


func _find_free_player_3d(request_priority: int) -> AudioStreamPlayer3D:
	for p in _pool3d:
		if not p.playing:
			return p
	var candidate: AudioStreamPlayer3D = null
	var lowest_priority := 999
	var oldest_time := 2147483647
	for p in _pool3d:
		var priority := int(p.get_meta("audio_priority", 0))
		var started := int(p.get_meta("audio_started_ms", 0))
		if priority < lowest_priority or (priority == lowest_priority and started < oldest_time):
			lowest_priority = priority
			oldest_time = started
			candidate = p
	if request_priority < lowest_priority:
		return null
	return candidate


## Plays a voice/sfx stream at a 3D position so it attenuates with distance from the listener.
func _play_voice_stream_3d(stream: AudioStream, position: Vector3, volume_db: float, category: String) -> void:
	var routed_bus := _valid_bus(category)
	var player := _find_free_player_3d(_bus_priority(routed_bus))
	if player == null:
		return
	player.stop()
	player.stream = stream
	player.bus = routed_bus
	player.global_position = position
	player.set_meta("audio_priority", _bus_priority(routed_bus))
	player.set_meta("audio_started_ms", Time.get_ticks_msec())
	player.pitch_scale = randf_range(0.96, 1.04)
	var max_db := -2.0 if bool(SettingsManager.get_setting("audio_comfort")) else 0.0
	player.volume_db = clampf(volume_db, -24.0, max_db)
	player.play()


func play(sfx_name: String, pitch_variation := 0.06, volume_db := 0.0, category := "SFX") -> void:
	if _voice_play(sfx_name, volume_db, category):
		return
	if not _sfx.has(sfx_name):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var last := float(_last_played.get(sfx_name, -1000.0))
	if now - last < SOUND_COOLDOWN:
		return
	_last_played[sfx_name] = now
	var routed_bus := _valid_bus(category)
	var player := _find_free_player(_bus_priority(routed_bus))
	if player == null:
		return
	player.stop()
	player.stream = _sfx[sfx_name]
	player.bus = routed_bus
	player.set_meta("audio_priority", _bus_priority(routed_bus))
	player.set_meta("audio_started_ms", Time.get_ticks_msec())
	var variation_limit := 0.10 if bool(SettingsManager.get_setting("audio_comfort")) else 0.18
	var safe_variation := clampf(pitch_variation, 0.0, variation_limit)
	player.pitch_scale = randf_range(1.0 - safe_variation, 1.0 + safe_variation)
	# Never allow individual effects to add gain above unity; generated and imported assets
	# are both kept below digital full scale by the master mix.
	var max_effect_db := -2.0 if bool(SettingsManager.get_setting("audio_comfort")) else 0.0
	player.volume_db = clampf(volume_db, -24.0, max_effect_db)
	player.play()


func play_ui(sfx_name: String, pitch_variation := 0.03, volume_db := -4.0) -> void:
	play(sfx_name, pitch_variation, volume_db, "UI")


func play_character(sfx_name: String, pitch_variation := 0.06, volume_db := -2.0) -> void:
	play(sfx_name, pitch_variation, volume_db, "Character")


## Plays a character voice/sfx at a 3D position with distance attenuation (fall voice, etc.).
func play_character_3d(sfx_name: String, position: Vector3, pitch_variation := 0.06, volume_db := -2.0) -> void:
	if _voice_play(sfx_name, volume_db, "Character", position):
		return
	play(sfx_name, pitch_variation, volume_db, "Character")


func play_environment(sfx_name: String, pitch_variation := 0.04, volume_db := -6.0) -> void:
	play(sfx_name, pitch_variation, volume_db, "Environment")


func _valid_bus(requested: String) -> String:
	return requested if AudioServer.get_bus_index(requested) >= 0 else "SFX"


func click() -> void:
	play_ui("click", 0.03, -4.0)


func _bus_priority(bus_name: String) -> int:
	match bus_name:
		"UI":
			return 3
		"Character":
			return 2
		_:
			return 1


func _find_free_player(request_priority: int) -> AudioStreamPlayer:
	for p in _pool:
		if not p.playing:
			return p
	var candidate: AudioStreamPlayer = null
	var lowest_priority := 999
	var oldest_time := 2147483647
	for p in _pool:
		var priority := int(p.get_meta("audio_priority", 0))
		var started := int(p.get_meta("audio_started_ms", 0))
		if priority < lowest_priority or (priority == lowest_priority and started < oldest_time):
			lowest_priority = priority
			oldest_time = started
			candidate = p
	if request_priority < lowest_priority:
		return null
	return candidate


# ---------------------------------------------------------------------------
# Synthesis helpers

func _make_stream(samples: PackedFloat32Array, loop := false, level := 1.0, rate := MIX_RATE, smooth := 0.6) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	# One-pole low-pass removes the harsh, buzzy top end of raw synth waves.
	var data := samples.duplicate()
	var y := 0.0
	for i in data.size():
		y += (data[i] - y) * smooth
		data[i] = y
	var peak := 0.0
	for sample in data:
		peak = maxf(peak, absf(sample))
	var gain := minf(1.0, 0.72 / peak) if peak > 0.0001 else 1.0
	gain *= level
	# Short fade-out so one-shot sounds never end with a click.
	var fade := mini(data.size(), int(0.008 * float(rate)))
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		var v := data[i] * gain
		if not loop and i >= data.size() - fade:
			v *= float(data.size() - i) / float(maxi(1, fade))
		bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = data.size()
	return stream


## Mixes a tone into `buf` (returned, because packed arrays may be copied on write).
## wave: 0 sine, 1 square, 2 triangle, 3 noise
func _add_tone(buf: PackedFloat32Array, start_time: float, duration: float, freq_start: float,
		freq_end: float, volume: float, wave := 0, attack := 0.005, decay_power := 1.0, rate := MIX_RATE) -> PackedFloat32Array:
	var start := int(start_time * rate)
	var count := int(duration * rate)
	if count <= 0:
		return buf
	var needed := start + count
	if buf.size() < needed:
		buf.resize(needed)
	var phase := 0.0
	var nz := 0.0
	var attack_samples := maxf(1.0, attack * rate)
	for i in count:
		var t := float(i) / float(count)
		var freq := lerpf(freq_start, freq_end, t)
		phase += freq / float(rate)
		var env := minf(1.0, float(i) / attack_samples) * pow(1.0 - t, decay_power)
		var s := 0.0
		match wave:
			0:
				s = sin(phase * TAU)
			1:
				s = tanh(sin(phase * TAU) * 2.2) * 0.85  # soft square, no harsh aliasing
			2:
				s = 4.0 * absf(fmod(phase, 1.0) - 0.5) - 1.0
			_:
				nz += (randf_range(-1.0, 1.0) - nz) * 0.3  # filtered noise: whoosh, not hiss
				s = nz * 2.2
		buf[start + i] += s * volume * env
	return buf


func _note(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


func _register(sfx_name: String, buf: PackedFloat32Array, level := 1.0) -> void:
	var path: String = OPTIONAL_FILES.get(sfx_name, "")
	if path != "" and ResourceLoader.exists(path):
		_sfx[sfx_name] = load(path)
	else:
		_sfx[sfx_name] = _make_stream(buf, false, level)


func _generate_sfx() -> void:
	var b := PackedFloat32Array()

	# UI click
	b = PackedFloat32Array()
	b = _add_tone(b, 0.0, 0.06, 1500.0, 1100.0, 0.45, 2, 0.002, 1.6)
	_register("click", b, 0.6)

	# Jump: rising chirp
	b = PackedFloat32Array()
	b = _add_tone(b, 0.0, 0.2, 330.0, 820.0, 0.42, 2, 0.01, 1.0)
	_register("jump", b)

	# Two quiet, cushioned footstep variants. Cadence is driven by grounded movement.
	b = PackedFloat32Array()
	b = _add_tone(b, 0.0, 0.055, 0.0, 0.0, 0.12, 3, 0.002, 2.8)
	b = _add_tone(b, 0.0, 0.075, 105.0, 58.0, 0.16, 0, 0.002, 2.2)
	_register("footstep_a", b, 0.5)
	b = PackedFloat32Array()
	b = _add_tone(b, 0.0, 0.05, 0.0, 0.0, 0.10, 3, 0.002, 3.0)
	b = _add_tone(b, 0.0, 0.085, 125.0, 64.0, 0.14, 0, 0.003, 2.4)
	_register("footstep_b", b, 0.5)

	# Land: soft thud (noise + low tone)
	b = PackedFloat32Array()
	b = _add_tone(b, 0.0, 0.09, 0.0, 0.0, 0.35, 3, 0.002, 2.5)
	b = _add_tone(b, 0.0, 0.14, 140.0, 70.0, 0.5, 0, 0.002, 1.5)
	_register("land", b, 0.85)

	# Push: whoosh + punch
	b = PackedFloat32Array()
	b = _add_tone(b, 0.0, 0.22, 0.0, 0.0, 0.3, 3, 0.03, 1.2)
	b = _add_tone(b, 0.05, 0.16, 260.0, 90.0, 0.45, 0, 0.004, 1.5)
	_register("push", b)

	# Whoosh (hammer swing near camera) - light
	b = PackedFloat32Array()
	b = _add_tone(b, 0.0, 0.3, 0.0, 0.0, 0.18, 3, 0.1, 1.0)
	_register("whoosh", b, 0.6)

	# Hammer hit: heavy impact
	b = PackedFloat32Array()
	b = _add_tone(b, 0.0, 0.1, 0.0, 0.0, 0.5, 3, 0.002, 2.0)
	b = _add_tone(b, 0.0, 0.32, 180.0, 55.0, 0.7, 0, 0.002, 1.3)
	b = _add_tone(b, 0.0, 0.2, 620.0, 300.0, 0.2, 2, 0.002, 2.0)
	_register("hit", b)

	# Fall / elimination: slide whistle down
	b = PackedFloat32Array()
	b = _add_tone(b, 0.0, 0.7, 900.0, 160.0, 0.4, 2, 0.01, 0.8)
	b = _add_tone(b, 0.55, 0.12, 0.0, 0.0, 0.3, 3, 0.002, 2.0)
	_register("fall", b)

	# Tile crack
	b = PackedFloat32Array()
	b = _add_tone(b, 0.0, 0.12, 0.0, 0.0, 0.3, 3, 0.002, 1.5)
	b = _add_tone(b, 0.0, 0.1, 900.0, 400.0, 0.2, 1, 0.002, 2.0)
	_register("crack", b, 0.85)

	# Countdown beep and GO
	b = PackedFloat32Array()
	b = _add_tone(b, 0.0, 0.14, 880.0, 880.0, 0.4, 1, 0.004, 1.0)
	_register("countdown", b)
	b = PackedFloat32Array()
	b = _add_tone(b, 0.0, 0.35, 1320.0, 1320.0, 0.42, 1, 0.004, 0.8)
	b = _add_tone(b, 0.0, 0.35, 1760.0, 1760.0, 0.2, 0, 0.004, 0.8)
	_register("go", b)

	# Sudden Death alarm: three rising two-tone siren blasts (host + clients hear the same clip).
	b = PackedFloat32Array()
	for i in 3:
		var at := float(i) * 0.36
		b = _add_tone(b, at, 0.17, 640.0, 640.0, 0.30, 1, 0.008, 1.0)
		b = _add_tone(b, at + 0.18, 0.17, 860.0, 860.0, 0.30, 1, 0.008, 1.0)
	_register("alarm", b, 0.9)

	# Power-up pickup: quick rising two-note chirp
	b = PackedFloat32Array()
	b = _add_tone(b, 0.0, 0.09, 880.0, 880.0, 0.32, 1, 0.004, 1.0)
	b = _add_tone(b, 0.08, 0.16, 1320.0, 1568.0, 0.32, 1, 0.004, 1.0)
	_register("pickup", b, 0.9)

	# Victory: happy arpeggio
	b = PackedFloat32Array()
	var melody := [72, 76, 79, 84, 79, 84]
	for i in melody.size():
		b = _add_tone(b, i * 0.11, 0.26, _note(melody[i]), _note(melody[i]), 0.3, 2, 0.005, 1.2)
	b = _add_tone(b, 0.66, 0.9, _note(72), _note(72), 0.18, 0, 0.01, 1.0)
	b = _add_tone(b, 0.66, 0.9, _note(76), _note(76), 0.18, 0, 0.01, 1.0)
	b = _add_tone(b, 0.66, 0.9, _note(79), _note(79), 0.18, 0, 0.01, 1.0)
	_register("victory", b)
