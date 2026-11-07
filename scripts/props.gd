extends RefCounted
## Furniture / household props built from primitive meshes (no external assets).
## The SAME builders are used for the furniture inside the houses and for the disguises of the
## hiders in hide-and-seek, so a hider is only recognisable by looking carefully (or by moving).
## Origin = floor level, the front of every prop looks toward -Z.
## Usage: const PropsLib := preload("res://scripts/props.gd")

const Scenery := preload("res://scripts/scenery.gd")

const PROP_COUNT := 18

## Rough bounding boxes (x, y, z) used for the furniture collision shapes.
const SIZES := [
	Vector3(1.6, 1.1, 2.2),   # 0 bed
	Vector3(0.7, 1.1, 0.7),   # 1 chair
	Vector3(2.0, 0.95, 0.95), # 2 sofa
	Vector3(1.4, 0.85, 0.9),  # 3 table
	Vector3(0.6, 0.95, 0.85), # 4 toilet
	Vector3(0.9, 0.65, 1.8),  # 5 bathtub
	Vector3(0.7, 1.05, 0.5),  # 6 sink
	Vector3(0.8, 1.85, 0.8),  # 7 fridge
	Vector3(0.8, 0.95, 0.7),  # 8 stove
	Vector3(1.4, 1.4, 0.5),   # 9 tv stand
	Vector3(1.2, 1.9, 0.4),   # 10 bookshelf
	Vector3(1.2, 2.0, 0.6),   # 11 wardrobe
	Vector3(0.45, 1.6, 0.45), # 12 lamp
	Vector3(0.7, 1.3, 0.7),   # 13 plant
	Vector3(0.7, 0.95, 0.7),  # 14 washing machine
	Vector3(0.85, 0.85, 0.85),# 15 crate
	Vector3(0.5, 0.85, 0.5),  # 16 trash bin
	Vector3(1.3, 0.85, 0.7),  # 17 desk
]

const NAME_KEYS := [
	"prop_bed", "prop_chair", "prop_sofa", "prop_table", "prop_toilet", "prop_bathtub",
	"prop_sink", "prop_fridge", "prop_stove", "prop_tv", "prop_bookshelf", "prop_wardrobe",
	"prop_lamp", "prop_plant", "prop_washer", "prop_crate", "prop_bin", "prop_desk",
]

## Which props belong into which kind of room.
const ROOM_SETS := {
	"bedroom": [0, 11, 12, 10, 1],
	"bathroom": [4, 5, 6, 14, 16],
	"kitchen": [7, 8, 3, 1, 16, 15],
	"living": [2, 9, 10, 13, 12, 3],
	"office": [17, 1, 10, 12, 15, 13],
	"storage": [15, 15, 16, 14, 10, 13],
}


static func size_of(id: int) -> Vector3:
	return SIZES[posmod(id, PROP_COUNT)]


static func build(id: int) -> Node3D:
	var root := Node3D.new()
	var pid := posmod(id, PROP_COUNT)
	root.name = "Prop%d" % pid
	match pid:
		0: _bed(root)
		1: _chair(root)
		2: _sofa(root)
		3: _table(root)
		4: _toilet(root)
		5: _bathtub(root)
		6: _sink(root)
		7: _fridge(root)
		8: _stove(root)
		9: _tv(root)
		10: _bookshelf(root)
		11: _wardrobe(root)
		12: _lamp(root)
		13: _plant(root)
		14: _washer(root)
		15: _crate(root)
		16: _bin(root)
		_: _desk(root)
	return root


# ---------------------------------------------------------------------------
# Tiny helpers

static func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, rough := 0.7) -> MeshInstance3D:
	var mi := Scenery.mesh_instance(Scenery.box(size), Scenery.mat(color, rough), pos)
	parent.add_child(mi)
	return mi


static func _cyl(parent: Node3D, top: float, bottom: float, height: float, pos: Vector3, color: Color, segments := 14) -> MeshInstance3D:
	var mi := Scenery.mesh_instance(Scenery.cylinder(top, bottom, height, segments), Scenery.mat(color, 0.65), pos)
	parent.add_child(mi)
	return mi


static func _ball(parent: Node3D, radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := Scenery.mesh_instance(Scenery.sphere(radius, 12, 6), Scenery.mat(color, 0.7), pos)
	parent.add_child(mi)
	return mi


static func _legs(parent: Node3D, x: float, z: float, height: float, radius: float, color: Color) -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_cyl(parent, radius, radius, height, Vector3(x * float(sx), height * 0.5, z * float(sz)), color, 8)


# ---------------------------------------------------------------------------
# Props

static func _bed(r: Node3D) -> void:
	var wood := Color(0.55, 0.36, 0.22)
	_box(r, Vector3(1.6, 0.35, 2.2), Vector3(0, 0.3, 0), wood)
	_box(r, Vector3(1.5, 0.25, 2.05), Vector3(0, 0.6, 0), Color(0.93, 0.95, 1.0))
	_box(r, Vector3(1.52, 0.12, 1.2), Vector3(0, 0.76, -0.35), Color(0.9, 0.35, 0.45))
	_box(r, Vector3(0.9, 0.16, 0.42), Vector3(0, 0.78, 0.8), Color(1, 1, 1))
	_box(r, Vector3(1.6, 0.95, 0.12), Vector3(0, 0.62, 1.07), wood.darkened(0.15))


static func _chair(r: Node3D) -> void:
	var wood := Color(0.7, 0.45, 0.25)
	_box(r, Vector3(0.6, 0.1, 0.6), Vector3(0, 0.5, 0), wood)
	_legs(r, 0.25, 0.25, 0.5, 0.04, wood.darkened(0.2))
	_box(r, Vector3(0.6, 0.6, 0.08), Vector3(0, 0.85, 0.28), wood)


static func _sofa(r: Node3D) -> void:
	var c := Color(0.35, 0.5, 0.85)
	_box(r, Vector3(2.0, 0.45, 0.9), Vector3(0, 0.3, 0), c)
	_box(r, Vector3(2.0, 0.6, 0.25), Vector3(0, 0.78, 0.35), c.darkened(0.1))
	_box(r, Vector3(0.25, 0.4, 0.9), Vector3(-0.88, 0.62, 0), c.darkened(0.15))
	_box(r, Vector3(0.25, 0.4, 0.9), Vector3(0.88, 0.62, 0), c.darkened(0.15))
	_box(r, Vector3(0.75, 0.14, 0.6), Vector3(-0.4, 0.58, -0.05), c.lightened(0.15))
	_box(r, Vector3(0.75, 0.14, 0.6), Vector3(0.4, 0.58, -0.05), c.lightened(0.15))


static func _table(r: Node3D) -> void:
	var wood := Color(0.62, 0.42, 0.25)
	_box(r, Vector3(1.4, 0.1, 0.9), Vector3(0, 0.75, 0), wood)
	_legs(r, 0.6, 0.38, 0.75, 0.05, wood.darkened(0.2))


static func _toilet(r: Node3D) -> void:
	var w := Color(0.97, 0.97, 1.0)
	_cyl(r, 0.27, 0.2, 0.45, Vector3(0, 0.22, -0.1), w, 16)
	_box(r, Vector3(0.5, 0.5, 0.2), Vector3(0, 0.7, 0.3), w)
	_cyl(r, 0.27, 0.27, 0.05, Vector3(0, 0.47, -0.1), Color(0.85, 0.9, 1.0), 16)
	_cyl(r, 0.05, 0.05, 0.06, Vector3(0, 0.98, 0.3), Color(0.75, 0.75, 0.8), 8)


static func _bathtub(r: Node3D) -> void:
	_box(r, Vector3(0.9, 0.6, 1.8), Vector3(0, 0.3, 0), Color(0.96, 0.97, 1.0), 0.4)
	_box(r, Vector3(0.74, 0.05, 1.62), Vector3(0, 0.6, 0), Color(0.45, 0.75, 1.0), 0.2)
	_cyl(r, 0.04, 0.04, 0.25, Vector3(0, 0.72, 0.8), Color(0.8, 0.8, 0.85), 8)


static func _sink(r: Node3D) -> void:
	var w := Color(0.96, 0.97, 1.0)
	_cyl(r, 0.14, 0.18, 0.75, Vector3(0, 0.38, 0.05), w, 12)
	_box(r, Vector3(0.7, 0.14, 0.5), Vector3(0, 0.88, 0), w, 0.4)
	_cyl(r, 0.03, 0.03, 0.22, Vector3(0, 1.0, 0.18), Color(0.75, 0.75, 0.82), 8)
	_box(r, Vector3(0.5, 0.6, 0.04), Vector3(0, 1.45, 0.23), Color(0.7, 0.85, 1.0), 0.15)


static func _fridge(r: Node3D) -> void:
	var c := Color(0.88, 0.9, 0.93)
	_box(r, Vector3(0.8, 1.8, 0.8), Vector3(0, 0.9, 0), c, 0.4)
	_box(r, Vector3(0.82, 0.03, 0.82), Vector3(0, 1.22, 0), c.darkened(0.35))
	_box(r, Vector3(0.05, 0.4, 0.05), Vector3(0.3, 1.5, -0.42), Color(0.5, 0.5, 0.55))
	_box(r, Vector3(0.05, 0.6, 0.05), Vector3(0.3, 0.78, -0.42), Color(0.5, 0.5, 0.55))


static func _stove(r: Node3D) -> void:
	_box(r, Vector3(0.8, 0.9, 0.7), Vector3(0, 0.45, 0), Color(0.82, 0.83, 0.87), 0.4)
	_box(r, Vector3(0.82, 0.05, 0.72), Vector3(0, 0.92, 0), Color(0.15, 0.15, 0.2))
	for sx in [-0.2, 0.2]:
		for sz in [-0.15, 0.15]:
			_cyl(r, 0.1, 0.1, 0.02, Vector3(float(sx), 0.96, float(sz)), Color(0.4, 0.1, 0.1), 12)
	_box(r, Vector3(0.55, 0.35, 0.03), Vector3(0, 0.4, -0.36), Color(0.2, 0.22, 0.3), 0.2)


static func _tv(r: Node3D) -> void:
	_box(r, Vector3(1.4, 0.5, 0.5), Vector3(0, 0.25, 0), Color(0.5, 0.33, 0.2))
	_box(r, Vector3(1.15, 0.7, 0.06), Vector3(0, 0.95, 0), Color(0.08, 0.08, 0.1), 0.3)
	_box(r, Vector3(1.05, 0.6, 0.02), Vector3(0, 0.95, -0.035), Color(0.25, 0.55, 0.95), 0.2)
	_box(r, Vector3(0.3, 0.12, 0.2), Vector3(0, 0.56, 0), Color(0.1, 0.1, 0.12))


static func _bookshelf(r: Node3D) -> void:
	var wood := Color(0.5, 0.33, 0.2)
	_box(r, Vector3(1.2, 1.9, 0.4), Vector3(0, 0.95, 0), wood)
	var cols := [Color(0.9, 0.3, 0.3), Color(0.3, 0.6, 0.95), Color(0.95, 0.8, 0.25), Color(0.4, 0.8, 0.4), Color(0.7, 0.4, 0.9)]
	for row in 4:
		var y := 0.35 + float(row) * 0.45
		_box(r, Vector3(1.1, 0.04, 0.38), Vector3(0, y - 0.2, -0.01), wood.lightened(0.15))
		for i in 6:
			var bh := 0.28 + float((i * 7 + row * 3) % 4) * 0.04
			_box(r, Vector3(0.12, bh, 0.26), Vector3(-0.45 + float(i) * 0.18, y - 0.18 + bh * 0.5, -0.06), cols[(i + row) % cols.size()])


static func _wardrobe(r: Node3D) -> void:
	var wood := Color(0.6, 0.4, 0.26)
	_box(r, Vector3(1.2, 2.0, 0.6), Vector3(0, 1.0, 0), wood)
	_box(r, Vector3(0.02, 1.8, 0.02), Vector3(0, 1.0, -0.31), wood.darkened(0.4))
	_ball(r, 0.04, Vector3(-0.1, 1.0, -0.32), Color(0.95, 0.8, 0.3))
	_ball(r, 0.04, Vector3(0.1, 1.0, -0.32), Color(0.95, 0.8, 0.3))


static func _lamp(r: Node3D) -> void:
	_cyl(r, 0.18, 0.2, 0.05, Vector3(0, 0.03, 0), Color(0.25, 0.25, 0.3), 14)
	_cyl(r, 0.025, 0.025, 1.3, Vector3(0, 0.68, 0), Color(0.3, 0.3, 0.35), 8)
	_cyl(r, 0.12, 0.24, 0.35, Vector3(0, 1.45, 0), Color(1.0, 0.92, 0.55), 14)


static func _plant(r: Node3D) -> void:
	_cyl(r, 0.3, 0.22, 0.4, Vector3(0, 0.2, 0), Color(0.75, 0.4, 0.28), 12)
	_ball(r, 0.32, Vector3(0, 0.7, 0), Color(0.25, 0.7, 0.3))
	_ball(r, 0.25, Vector3(0.18, 0.98, 0.05), Color(0.3, 0.78, 0.35))
	_ball(r, 0.22, Vector3(-0.15, 1.05, -0.05), Color(0.2, 0.62, 0.28))


static func _washer(r: Node3D) -> void:
	_box(r, Vector3(0.7, 0.95, 0.7), Vector3(0, 0.48, 0), Color(0.95, 0.96, 1.0), 0.4)
	var door := _cyl(r, 0.24, 0.24, 0.05, Vector3(0, 0.45, -0.36), Color(0.3, 0.45, 0.7), 18)
	door.rotation_degrees = Vector3(90, 0, 0)
	_box(r, Vector3(0.6, 0.12, 0.03), Vector3(0, 0.85, -0.36), Color(0.2, 0.2, 0.28))


static func _crate(r: Node3D) -> void:
	var wood := Color(0.72, 0.52, 0.3)
	_box(r, Vector3(0.85, 0.85, 0.85), Vector3(0, 0.43, 0), wood)
	for y in [0.15, 0.43, 0.71]:
		_box(r, Vector3(0.88, 0.05, 0.88), Vector3(0, float(y), 0), wood.darkened(0.25))
	_box(r, Vector3(0.05, 0.88, 0.88), Vector3(-0.4, 0.43, 0), wood.darkened(0.2))
	_box(r, Vector3(0.05, 0.88, 0.88), Vector3(0.4, 0.43, 0), wood.darkened(0.2))


static func _bin(r: Node3D) -> void:
	_cyl(r, 0.25, 0.2, 0.8, Vector3(0, 0.4, 0), Color(0.45, 0.5, 0.55), 14)
	_cyl(r, 0.27, 0.27, 0.05, Vector3(0, 0.83, 0), Color(0.3, 0.33, 0.38), 14)


static func _desk(r: Node3D) -> void:
	var wood := Color(0.55, 0.38, 0.25)
	_box(r, Vector3(1.3, 0.08, 0.7), Vector3(0, 0.76, 0), wood)
	_box(r, Vector3(0.4, 0.7, 0.6), Vector3(0.43, 0.38, 0), wood.darkened(0.12))
	_cyl(r, 0.04, 0.04, 0.72, Vector3(-0.58, 0.36, -0.28), wood.darkened(0.25), 8)
	_cyl(r, 0.04, 0.04, 0.72, Vector3(-0.58, 0.36, 0.28), wood.darkened(0.25), 8)
	_box(r, Vector3(0.45, 0.03, 0.3), Vector3(-0.25, 0.82, 0.05), Color(0.7, 0.72, 0.78))
	_box(r, Vector3(0.45, 0.3, 0.02), Vector3(-0.25, 0.97, 0.18), Color(0.2, 0.3, 0.5))
