extends Node3D
## Engine-level construction and topology regression across every map.
const Builder = preload("res://scripts/map_builder.gd")
const Constants = preload("res://scripts/game_constants.gd")
var obstacles_root: Node3D
var decor_root: Node3D
var round_manager: Node = null
var failures := 0

func _ready() -> void:
	call_deferred("run_test")

func check(ok: bool, msg: String) -> void:
	if not ok:
		failures += 1
		print("[MAP-COVERAGE] FAIL ", msg)

func run_test() -> void:
	for id in Constants.MAPS.size():
		var arena := Node3D.new()
		arena.set_script(load("res://tests/map_test_fixture.gd"))
		add_child(arena)
		var info: Dictionary = Builder.build(id, arena)
		check(int(info.get("kind", -1)) == int(Constants.MAPS[id]["kind"]), "kind map %d" % id)
		check(info.get("spawns", []).size() >= Constants.MAX_PLAYERS, "spawns map %d" % id)
		if int(info.get("kind", -1)) == 1:
			var rooms: Array = info.get("rooms", [])
			var graph: Dictionary = info.get("graph", {})
			check(rooms.size() > 1, "rooms map %d" % id)
			check(info.get("spawn_groups", []).size() == 2, "spawn groups map %d" % id)
			for i in rooms.size():
				if i > 0:
					check(not Builder.plan_path(graph, rooms, 0, i).is_empty(), "path map %d room %d" % [id, i])
					check(_reachable(graph, i), "connected map %d room %d" % [id, i])
		print("[MAP-COVERAGE] constructed map ", id)
		arena.free()
	print("[MAP-COVERAGE] finished with %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _reachable(graph: Dictionary, target: int) -> bool:
	var queue: Array = [0]
	var seen := {0: true}
	while not queue.is_empty():
		var current: int = queue.pop_front()
		if current == target:
			return true
		for edge in graph.get(current, []):
			var next := int(edge["to"])
			if not seen.has(next):
				seen[next] = true
				queue.append(next)
	return false
