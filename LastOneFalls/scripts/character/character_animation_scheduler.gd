extends Node
## Shared animation LOD scheduler for every ContenderVisuals instance.
##
## One autoload drives all remote contenders, so no character owns a Timer node.
## Each remote visual is classified as near / distant / off-screen and scheduled
## at its own interval.  Due times are staggered at registration, so a lobby of
## characters never animates on the same frame.  The visual receives the real
## elapsed time since its previous tick, so animation state and elapsed time are
## preserved even when the update rate is low; the skeleton pose is interpolated
## between ticks by ContenderVisuals.
##
## Debug: run with ANIM_LOD_DEBUG=1 (or --anim-lod-debug) for a one-line report
## per second, or call CharacterAnimation.get_debug_stats() at any time.

const LOD_LOCAL := 0
const LOD_NEAR := 1
const LOD_DISTANT := 2
const LOD_OFFSCREEN := 3

const MIN_INTERVAL := 1.0 / 240.0
const MAX_INTERVAL := 1.0
## First updates are spread over this window so a full lobby does not animate
## on the same frame. Later ticks keep that phase (cadence is accumulated).
const STAGGER_WINDOW := 0.20

class Entry:
	var visual: WeakRef
	var is_local := true
	var lod := LOD_LOCAL
	var interval := 1.0 / 60.0
	var next_due := 0.0
	var last_update := 0.0
	var updates := 0


var _entries: Array[Entry] = []
var _clock := 0.0
var _window_time := 0.0
var _window_updates := 0
var _total_updates := 0
var _updates_per_second := 0.0
var _last_report := -10.0
var _debug := false


func _ready() -> void:
	_debug = OS.get_environment("ANIM_LOD_DEBUG") == "1" or OS.get_cmdline_user_args().has("--anim-lod-debug")


## Called by every ContenderVisuals once it is inside the tree.
func register_visual(visual: Node, is_local: bool) -> void:
	if visual == null or not is_instance_valid(visual):
		return
	for e in _entries:
		var existing: Node = e.visual.get_ref() as Node
		if existing == visual:
			set_local(visual, is_local)
			return
	var entry := Entry.new()
	entry.visual = weakref(visual)
	entry.is_local = is_local
	entry.lod = LOD_LOCAL if is_local else LOD_DISTANT
	entry.interval = 1.0 / 60.0 if is_local else 1.0 / 30.0
	entry.last_update = _clock
	# Spread the first due times across several frames; the cadence advance
	# below is relative to this due time, so the phase is retained afterwards.
	entry.next_due = _clock + fmod(float(_entries.size()) * 0.0137, STAGGER_WINDOW)
	_entries.append(entry)


func unregister_visual(visual: Node) -> void:
	for i in range(_entries.size() - 1, -1, -1):
		var existing: Node = _entries[i].visual.get_ref() as Node
		if existing == null or existing == visual:
			_entries.remove_at(i)


## A character that becomes local (or a menu preview) is driven by its own
## _process at full rate; remotes are registered for scheduler ticks.
func set_local(visual: Node, is_local: bool) -> void:
	for i in _entries.size():
		var e := _entries[i]
		var existing: Node = e.visual.get_ref() as Node
		if existing != visual:
			continue
		e.is_local = is_local
		e.lod = LOD_LOCAL if is_local else LOD_DISTANT
		e.last_update = _clock
		e.interval = 1.0 / 60.0 if is_local else 1.0 / 30.0
		e.next_due = _clock + fmod(float(i) * 0.0137, STAGGER_WINDOW)
		return


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	_clock += delta
	_window_time += delta
	if _window_time >= 1.0:
		_updates_per_second = float(_window_updates) / _window_time
		_window_updates = 0
		_window_time = 0.0
		if _debug and _clock - _last_report >= 1.0:
			_last_report = _clock
			var s := get_debug_stats()
			print("[ANIM-LOD] active=%d updates/s=%.1f local=%d near=%d distant=%d offscreen=%d" % [
				int(s["active"]), float(s["updates_per_second"]), int(s["local"]),
				int(s["near"]), int(s["distant"]), int(s["offscreen"])
			])
	var i := 0
	while i < _entries.size():
		var e := _entries[i]
		var visual: Node = e.visual.get_ref() as Node
		if visual == null or not is_instance_valid(visual) or not visual.is_inside_tree():
			_entries.remove_at(i)
			continue
		if e.is_local or _clock < e.next_due:
			i += 1
			continue
		var elapsed := _clock - e.last_update
		if elapsed <= 0.0:
			elapsed = delta
		e.last_update = _clock
		var interval: float = visual._scheduler_update_animation(elapsed)
		e.interval = clampf(interval, MIN_INTERVAL, MAX_INTERVAL)
		# Advance the cadence from the previous due time, not from the current
		# clock: adding to the clock quantizes 30 Hz down to every third 60 Hz
		# frame (~20 Hz) whenever the due time lands between frames.
		e.next_due += e.interval
		if e.next_due <= _clock:
			# Long stall: restart the cadence instead of emitting a burst.
			e.next_due = _clock + e.interval
		e.lod = int(visual.animation_lod)
		e.updates += 1
		_window_updates += 1
		_total_updates += 1
		i += 1


## Called by ContenderVisuals for local/menu updates, which are not scheduled
## here. Remote ticks are counted by _process, so the debug rate is a total.
func note_visual_update() -> void:
	_window_updates += 1
	_total_updates += 1


func get_debug_stats() -> Dictionary:
	var local := 0
	var near := 0
	var distant := 0
	var offscreen := 0
	var active := 0
	for e in _entries:
		var visual: Node = e.visual.get_ref() as Node
		if visual == null or not is_instance_valid(visual):
			continue
		active += 1
		if e.is_local or int(visual.animation_lod) == LOD_LOCAL:
			local += 1
		else:
			match int(visual.animation_lod):
				LOD_NEAR:
					near += 1
				LOD_DISTANT:
					distant += 1
				_:
					offscreen += 1
	return {
		"active": active,
		"local": local,
		"near": near,
		"distant": distant,
		"offscreen": offscreen,
		"updates_per_second": _updates_per_second,
		"total_updates": _total_updates,
	}


func reset_debug_stats() -> void:
	_window_time = 0.0
	_window_updates = 0
	_total_updates = 0
	_updates_per_second = 0.0
