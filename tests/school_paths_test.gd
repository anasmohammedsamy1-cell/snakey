extends Node3D
## Checks real collision geometry along corridors, doorways, and hiding spots.
const Builder = preload("res://scripts/map_builder.gd")
var fails := 0
func _ready() -> void:
	call_deferred("run_test")
func check(ok: bool, label: String) -> void:
	if not ok:
		fails += 1
		print("[SCHOOL] FAIL ", label)
func clear_segment(a: Vector3, b: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	for step in 21:
		var p := a.lerp(b, float(step) / 20.0)
		p.y = 1.0
		q.transform = Transform3D(Basis.IDENTITY, p)
		if not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
			return false
	return true
func run_test() -> void:
	var old_preset: Variant = SettingsManager.settings["graphics_preset"]
	if OS.get_environment("SCHOOL_LOW") == "1":
		SettingsManager.settings["graphics_preset"] = SettingsManager.PRESET_LOW
	var fixture := Node3D.new()
	fixture.set_script(load("res://tests/map_test_fixture.gd"))
	add_child(fixture)
	var info: Dictionary = Builder.build(Builder.MAP_SCHOOL, fixture)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var rooms: Array = info["rooms"]
	var graph: Dictionary = info["graph"]
	check(rooms.size() == 12, "four corridor waypoints and eight themed rooms")
	check(info["spawn_groups"][0].size() >= 8 and info["spawn_groups"][1].size() >= 8, "enough spawn points")
	for col in 3:
		check(clear_segment(rooms[col]["center"], rooms[col + 1]["center"]), "corridor segment %d" % col)
	for index in range(4, rooms.size()):
		var room: Dictionary = rooms[index]
		var door: Vector3 = graph[index][0]["door"]
		check(clear_segment(rooms[int(graph[index][0]["to"])]["center"], door), "corridor to door %d" % index)
		check(clear_segment(door, room["center"]), "door to room %d" % index)
		for spot in room["spots"]:
			check(clear_segment(room["center"], spot), "room to hiding spot %d" % index)
	for spawn in info["spawn_groups"][1]:
		check(clear_segment(spawn, spawn), "seeker spawn collision")
	SettingsManager.settings["graphics_preset"] = old_preset
	print("[SCHOOL] finished with %d failure(s)" % fails)
	get_tree().quit(1 if fails else 0)
