extends RefCounted
## Hats and accessories for the character. Pure data + procedural meshes (no imported assets), so they work on every device.
## Parts are positioned in the local space of the "Head" bone attachment: x right, y up, z forward (the visor side).
## The top of the head is at about y = 0.62 (local) and its centre is at z = 0.07.

const Scenery := preload("res://scripts/scenery.gd")

## id, locale key, price in coins. Order = order in the shop.
const ITEMS := [
	{"id": "party", "key": "acc_party", "price": 60},
	{"id": "cap", "key": "acc_cap", "price": 80},
	{"id": "shades", "key": "acc_shades", "price": 100},
	{"id": "ears", "key": "acc_ears", "price": 120},
	{"id": "wizard", "key": "acc_wizard", "price": 150},
	{"id": "tophat", "key": "acc_tophat", "price": 200},
	{"id": "halo", "key": "acc_halo", "price": 250},
	{"id": "crown", "key": "acc_crown", "price": 400},
]

const TOP := Vector3(0.0, 0.6, 0.07)


static func ids() -> Array:
	var out: Array = []
	for it in ITEMS:
		out.append(str(it["id"]))
	return out


## Extra height (m) the name plate must rise so tall hats do not cover it.
static func plate_lift(id: String) -> float:
	match id:
		"wizard":
			return 0.45
		"tophat":
			return 0.25
		"party":
			return 0.2
		"halo", "crown":
			return 0.15
		"ears":
			return 0.08
	return 0.0


static func is_valid(id: String) -> bool:
	return id.is_empty() or ids().has(id)


static func price_of(id: String) -> int:
	for it in ITEMS:
		if str(it["id"]) == id:
			return int(it["price"])
	return 0


static func key_of(id: String) -> String:
	for it in ITEMS:
		if str(it["id"]) == id:
			return str(it["key"])
	return "acc_none"


static func _part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot := Vector3.ZERO, unshaded := false) -> MeshInstance3D:
	var mi := Scenery.mesh_instance(mesh, Scenery.mat(color, 0.55, unshaded), pos, false)
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi


## Returns a Node3D holding the accessory (empty node for "" / unknown ids).
static func build(id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Acc_" + id
	match id:
		"party":
			var cone := _part(root, Scenery.cylinder(0.0, 0.22, 0.46, 12), Color(1.0, 0.35, 0.6), TOP + Vector3(0, 0.22, 0), Vector3(-8, 0, 0))
			cone.name = "PartyCone"
			_part(root, Scenery.torus(0.15, 0.19, 16, 6), Color(0.3, 0.8, 1.0), TOP + Vector3(0, 0.1, 0.0))
			_part(root, Scenery.sphere(0.06, 8, 4), Color(1.0, 0.85, 0.2), TOP + Vector3(0, 0.47, -0.03))
		"cap":
			var dome := _part(root, Scenery.sphere(0.34, 14, 7), Color(0.9, 0.2, 0.2), TOP + Vector3(0, -0.04, 0))
			dome.scale = Vector3(1.0, 0.62, 1.0)
			_part(root, Scenery.box(Vector3(0.5, 0.04, 0.3)), Color(0.75, 0.12, 0.12), TOP + Vector3(0, 0.0, 0.4), Vector3(8, 0, 0))
			_part(root, Scenery.sphere(0.045, 6, 3), Color(1, 1, 1), TOP + Vector3(0, 0.2, 0))
		"shades":
			var z := 0.67
			for side in [-1.0, 1.0]:
				_part(root, Scenery.box(Vector3(0.24, 0.15, 0.04)), Color(0.04, 0.04, 0.06), Vector3(side * 0.17, 0.4, z))
			_part(root, Scenery.box(Vector3(0.12, 0.03, 0.04)), Color(0.04, 0.04, 0.06), Vector3(0, 0.43, z))
			_part(root, Scenery.box(Vector3(0.64, 0.03, 0.04)), Color(0.04, 0.04, 0.06), Vector3(0, 0.455, z - 0.02))
		"ears":
			for side in [-1.0, 1.0]:
				_part(root, Scenery.cylinder(0.0, 0.12, 0.26, 4), Color(0.15, 0.15, 0.2), TOP + Vector3(side * 0.2, 0.06, -0.02), Vector3(0, 45, side * -14.0))
				_part(root, Scenery.cylinder(0.0, 0.07, 0.17, 4), Color(1.0, 0.6, 0.75), TOP + Vector3(side * 0.2, 0.04, 0.04), Vector3(0, 45, side * -14.0))
		"wizard":
			_part(root, Scenery.cylinder(0.0, 0.3, 0.7, 16), Color(0.45, 0.25, 0.85), TOP + Vector3(0, 0.33, 0), Vector3(-6, 0, 0))
			_part(root, Scenery.cylinder(0.5, 0.5, 0.04, 20), Color(0.35, 0.18, 0.7), TOP + Vector3(0, -0.01, 0))
			_part(root, Scenery.torus(0.29, 0.33, 16, 6), Color(1.0, 0.85, 0.2), TOP + Vector3(0, 0.05, 0))
		"tophat":
			_part(root, Scenery.cylinder(0.24, 0.24, 0.42, 16), Color(0.08, 0.08, 0.1), TOP + Vector3(0, 0.2, 0))
			_part(root, Scenery.cylinder(0.4, 0.4, 0.04, 20), Color(0.08, 0.08, 0.1), TOP + Vector3(0, -0.01, 0))
			_part(root, Scenery.torus(0.235, 0.265, 16, 6), Color(0.85, 0.15, 0.2), TOP + Vector3(0, 0.07, 0))
		"halo":
			var ring := _part(root, Scenery.torus(0.24, 0.32, 24, 8), Color(1.0, 0.9, 0.3), TOP + Vector3(0, 0.34, 0), Vector3.ZERO, true)
			ring.name = "HaloRing"
		"crown":
			_part(root, Scenery.cylinder(0.3, 0.27, 0.16, 16), Color(1.0, 0.8, 0.15), TOP + Vector3(0, 0.07, 0))
			for i in 5:
				var a := float(i) * TAU / 5.0
				_part(root, Scenery.cylinder(0.0, 0.065, 0.17, 6), Color(1.0, 0.85, 0.25), TOP + Vector3(cos(a) * 0.25, 0.22, sin(a) * 0.25))
				_part(root, Scenery.sphere(0.035, 6, 3), Color(0.9, 0.15, 0.25), TOP + Vector3(cos(a) * 0.25, 0.32, sin(a) * 0.25))
		_:
			pass
	return root
