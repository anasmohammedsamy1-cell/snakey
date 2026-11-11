extends Node3D
## Engine-level regression for Sudden Death (v5): the floor must really shrink, and it must
## never disappear completely.
## For every arena map we build it exactly like the game does, then:
##   * shrinking maps expose at least one collapse piece (a floor tier or a crumbling tile);
##   * the solid core tier is NOT part of the collapse group, so it can never fall;
##   * dropping every tier in rank order (outermost first) still leaves a floor with collision;
##   * maps that cannot shrink are flagged "shrinkable": false, so the HUD stays quiet.
const Builder = preload("res://scripts/map_builder.gd")
const Constants = preload("res://scripts/game_constants.gd")

var failures := 0


func _ready() -> void:
	call_deferred("run_test")


func check(ok: bool, msg: String) -> void:
	if not ok:
		failures += 1
		print("[SUDDEN-DEATH] FAIL ", msg)


func run_test() -> void:
	for id in Constants.MAPS.size():
		if int(Constants.MAPS[id]["kind"]) != 0:
			continue
		var arena := Node3D.new()
		arena.set_script(load("res://tests/map_test_fixture.gd"))
		add_child(arena)
		var info: Dictionary = Builder.build(id, arena)
		var shrinkable := bool(info.get("shrinkable", false))

		# Only this map's pieces: earlier arenas may still be waiting for a deferred free.
		var tiers: Array = []
		var loose: Array = []
		for node in get_tree().get_nodes_in_group("arena_crumble_tiles"):
			if not arena.is_ancestor_of(node):
				continue
			if node.has_method("collapse_rank"):
				tiers.append(node)
			else:
				loose.append(node)

		if shrinkable:
			check(not tiers.is_empty() or not loose.is_empty(), "map %d is shrinkable but has no pieces" % id)
		# Tiers must be ordered outer -> inner and must never include the last (solid) one.
		var max_index := -1
		for tier in tiers:
			max_index = maxi(max_index, int(tier.get("layer_index")))
		var all_tiers: Array = []
		for child in arena.obstacles_root.get_children():
			if str(child.name).begins_with("FloorTier"):
				all_tiers.append(child)
		tiers.sort_custom(func(a, b) -> bool: return int(a.get("layer_index")) < int(b.get("layer_index")))
		if not all_tiers.is_empty():
			check(tiers.size() == all_tiers.size() - 1, "map %d: only the core tier may be unbreakable (tiers %d of %d)"
				% [id, tiers.size(), all_tiers.size()])
			check(max_index == tiers.size() - 1, "map %d: tier indices must be 0..n-1" % id)

		# Drop every tier the way RoundManager does (highest rank first).
		var dropped := 0
		while true:
			var best: Node = null
			var best_rank := -1.0
			for tier in tiers:
				if not is_instance_valid(tier) or not tier.can_be_event_triggered():
					continue
				var rank := float(tier.call("collapse_rank"))
				if rank > best_rank:
					best_rank = rank
					best = tier
			if best == null:
				break
			var expect_index := 0
			for tier in tiers:
				if not tier.can_be_event_triggered():
					expect_index += 1  # tiers are ordered outer -> inner
			check(int(best.get("layer_index")) == expect_index, "map %d: tier %d dropped out of order" % [id, int(best.get("layer_index"))])
			best.trigger()
			check(not best.can_be_event_triggered(), "map %d: a triggered tier is still collapsible" % id)
			dropped += 1
			if dropped > 16:
				break
		if not all_tiers.is_empty():
			check(dropped == all_tiers.size() - 1, "map %d: expected %d tier drops, got %d"
				% [id, all_tiers.size() - 1, dropped])

		# The core must still be a real floor with collision.
		if not all_tiers.is_empty():
			var core: Node = all_tiers[all_tiers.size() - 1]
			var has_shape := false
			for child in core.get_children():
				if child is CollisionShape3D and not child.disabled:
					has_shape = true
					break
			check(has_shape, "map %d: the core tier lost its collision" % id)

		print("[SUDDEN-DEATH] map %d shrinkable=%s tiers=%d loose=%d" % [id, str(shrinkable), tiers.size(), loose.size()])
		arena.free()
	print("[SUDDEN-DEATH] finished with %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)
