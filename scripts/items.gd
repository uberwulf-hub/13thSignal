extends RefCounted
## Everything you can pick up and carry in your inventory: what each item is,
## what it does, and what it looks like (built from simple shapes).
##
## kind:
##   battery  - recharges your flashlight
##   glow     - a glow stick: crack it and toss it; its light holds mannequins still
##   throw    - throw it to make a noise somewhere else (a distraction)
##   read     - look at it (a scrap of the story); can also be dropped
## Throwables have a noise radius (how far the Listener hears it land).
## obj: the sound the item itself makes when it hits something (the surface it
## hits makes its own sound too). bounce: how springy it is. breaks_at: hit
## anything harder than this (m/s) and it shatters.

const ITEMS := {
	"battery": {"name": "Battery", "kind": "battery", "stack": 5, "short": "BATT", "obj": "obj_plastic", "bounce": 0.3},
	"glowstick": {"name": "Glow stick", "kind": "glow", "stack": 5, "short": "GLOW", "obj": "obj_plastic", "bounce": 0.35},
	"soda_can": {"name": "Soda can", "kind": "throw", "stack": 3, "short": "CAN", "noise": 14.0, "obj": "obj_can", "bounce": 0.3},
	"bottle": {"name": "Glass bottle", "kind": "throw", "stack": 2, "short": "BTL", "noise": 18.0, "obj": "obj_bottle", "bounce": 0.25, "breaks_at": 3.5},
	"wrench": {"name": "Wrench", "kind": "throw", "stack": 1, "short": "WRCH", "noise": 18.0, "obj": "obj_steel", "bounce": 0.15},
	"coffee_mug": {"name": "Coffee mug", "kind": "throw", "stack": 2, "short": "MUG", "noise": 12.0, "obj": "obj_ceramic", "bounce": 0.2, "breaks_at": 4.5},
	"stapler": {"name": "Stapler", "kind": "throw", "stack": 2, "short": "STPL", "noise": 10.0, "obj": "obj_stapler", "bounce": 0.15},
	"clipboard": {"name": "Clipboard", "kind": "throw", "stack": 2, "short": "CLIP", "noise": 7.0, "obj": "obj_board", "bounce": 0.05},
	"photo": {"name": "Old photograph", "kind": "read", "stack": 1, "short": "PHOTO", "obj": "obj_paper", "bounce": 0.0,
		"text": "A staff photo, faded. Twelve people smiling in front of the facility sign. Someone has written on the back: \"There were only twelve of us. Who is the thirteenth?\" You count again. Thirteen."},
	"id_badge": {"name": "ID badge", "kind": "read", "stack": 1, "short": "BADGE", "obj": "obj_plastic", "bounce": 0.1,
		"text": "STAFF ID - ACCESS LEVEL 2. The name has been scratched out. The photo hasn't. It looks a lot like you."},
}

## How many of each item to scatter in a sector, by mode (Explorer gets more batteries).
const SPAWN := {
	"battery": [3, 2, 1], "glowstick": [2, 2, 1], "soda_can": [2, 2, 2], "bottle": [1, 1, 1],
	"wrench": [1, 1, 1], "coffee_mug": [1, 1, 1], "stapler": [1, 1, 1], "clipboard": [1, 1, 1],
	"photo": [1, 1, 1], "id_badge": [1, 1, 1],
}


static func info(id: String) -> Dictionary:
	return ITEMS.get(id, {})


static func _m(color: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


static func _glowm(color: Color, energy := 2.0) -> StandardMaterial3D:
	var m := _m(color, 0.3)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


static func _cyl(r: float, h: float, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 16
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	return mi


static func _box(size: Vector3, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	return mi


## Items that use a real model (Poly Haven, CC0) instead of simple shapes:
## [model folder, rotation so it lies naturally on the floor].
const REAL_MODELS := {
	"wrench": ["adjustable_wrench", Vector3(0, 0, PI / 2.0)],
	"clipboard": ["clipboard", Vector3.ZERO],
	"stapler": ["vintage_stapler", Vector3.ZERO],
}


## A real model from assets/models/<name>/<name>.gltf, rotated, sitting on y = 0.
static func real_model(folder: String, rot := Vector3.ZERO) -> Node3D:
	var path := "res://assets/models/%s/%s.gltf" % [folder, folder]
	if not ResourceLoader.exists(path):
		return null
	var root := Node3D.new()
	var scene: Node3D = (load(path) as PackedScene).instantiate()
	scene.rotation = rot
	root.add_child(scene)
	var box := AABB()
	var first := true
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		var t := scene.transform
		var n: Node = m
		var chain := Transform3D()
		while n != scene:
			chain = (n as Node3D).transform * chain
			n = n.get_parent()
		var b: AABB = (t * chain) * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	scene.position = Vector3(-(box.position.x + box.size.x / 2.0), -box.position.y, -(box.position.z + box.size.z / 2.0))
	return root


## The item's 3D model, standing on y = 0. `lit` makes a glow stick glow.
static func model(id: String, lit := false) -> Node3D:
	if REAL_MODELS.has(id):
		var real := real_model(REAL_MODELS[id][0], REAL_MODELS[id][1])
		if real:
			return real
	var root := Node3D.new()
	match id:
		"battery":
			root.add_child(_cyl(0.017, 0.06, _m(Color(0.1, 0.1, 0.1), 0.4), Vector3(0, 0.03, 0)))
			root.add_child(_cyl(0.017, 0.012, _m(Color(0.75, 0.5, 0.15), 0.3, 0.8), Vector3(0, 0.054, 0)))
			root.add_child(_cyl(0.005, 0.006, _m(Color(0.8, 0.8, 0.8), 0.2, 1.0), Vector3(0, 0.063, 0)))
		"glowstick":
			var mat: Material = _glowm(Color(0.3, 1.0, 0.4), 3.0) if lit else _m(Color(0.25, 0.6, 0.3, 0.8), 0.2)
			root.add_child(_cyl(0.009, 0.16, mat, Vector3(0, 0.08, 0)))
			root.add_child(_cyl(0.011, 0.012, _m(Color(0.1, 0.1, 0.1)), Vector3(0, 0.16, 0)))
		"soda_can":
			root.add_child(_cyl(0.033, 0.12, _m(Color(0.7, 0.08, 0.08), 0.35, 0.6), Vector3(0, 0.06, 0)))
			root.add_child(_cyl(0.03, 0.006, _m(Color(0.8, 0.8, 0.82), 0.2, 1.0), Vector3(0, 0.121, 0)))
		"bottle":
			var glass := _m(Color(0.2, 0.45, 0.25, 0.7), 0.05, 0.1)
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			root.add_child(_cyl(0.035, 0.18, glass, Vector3(0, 0.09, 0)))
			root.add_child(_cyl(0.013, 0.08, glass, Vector3(0, 0.22, 0)))
		"wrench":
			var steel := _m(Color(0.6, 0.62, 0.65), 0.3, 0.9)
			root.add_child(_box(Vector3(0.22, 0.012, 0.025), steel, Vector3(0, 0.006, 0)))
			root.add_child(_box(Vector3(0.05, 0.014, 0.05), steel, Vector3(0.12, 0.007, 0)))
		"coffee_mug":
			var white := _m(Color(0.9, 0.88, 0.84), 0.4)
			root.add_child(_cyl(0.04, 0.095, white, Vector3(0, 0.0475, 0)))
			var handle := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.018
			tm.outer_radius = 0.028
			handle.mesh = tm
			handle.material_override = white
			handle.position = Vector3(0.045, 0.05, 0)
			handle.rotation.x = PI / 2.0
			root.add_child(handle)
			root.add_child(_cyl(0.036, 0.004, _m(Color(0.2, 0.12, 0.06), 0.2), Vector3(0, 0.085, 0)))
		"stapler":
			root.add_child(_box(Vector3(0.16, 0.025, 0.04), _m(Color(0.15, 0.15, 0.17), 0.5), Vector3(0, 0.0125, 0)))
			root.add_child(_box(Vector3(0.15, 0.02, 0.035), _m(Color(0.6, 0.6, 0.62), 0.3, 0.8), Vector3(0, 0.035, 0)))
		"clipboard":
			root.add_child(_box(Vector3(0.23, 0.008, 0.32), _m(Color(0.45, 0.3, 0.15), 0.7), Vector3(0, 0.004, 0)))
			root.add_child(_box(Vector3(0.2, 0.003, 0.27), _m(Color(0.92, 0.9, 0.85), 0.9), Vector3(0, 0.0095, 0.015)))
			root.add_child(_box(Vector3(0.08, 0.012, 0.02), _m(Color(0.7, 0.7, 0.72), 0.3, 0.9), Vector3(0, 0.012, -0.145)))
		"photo":
			root.add_child(_box(Vector3(0.15, 0.003, 0.1), _m(Color(0.85, 0.82, 0.72), 0.8), Vector3(0, 0.0015, 0)))
			root.add_child(_box(Vector3(0.13, 0.002, 0.08), _m(Color(0.35, 0.32, 0.28), 0.8), Vector3(0, 0.0035, 0)))
		"id_badge":
			root.add_child(_box(Vector3(0.085, 0.004, 0.055), _m(Color(0.92, 0.92, 0.95), 0.5), Vector3(0, 0.002, 0)))
			root.add_child(_box(Vector3(0.025, 0.002, 0.03), _m(Color(0.4, 0.35, 0.3), 0.6), Vector3(-0.022, 0.005, 0)))
			root.add_child(_box(Vector3(0.03, 0.002, 0.008), _m(Color(0.2, 0.4, 0.8), 0.5), Vector3(0.018, 0.005, -0.01)))
	return root


## A rough box size for the item's physics shape.
static func size(id: String) -> Vector3:
	match id:
		"battery": return Vector3(0.035, 0.07, 0.035)
		"glowstick": return Vector3(0.025, 0.17, 0.025)
		"soda_can": return Vector3(0.066, 0.125, 0.066)
		"bottle": return Vector3(0.07, 0.26, 0.07)
		"wrench": return Vector3(0.25, 0.02, 0.05)
		"coffee_mug": return Vector3(0.1, 0.1, 0.08)
		"stapler": return Vector3(0.16, 0.05, 0.04)
		"clipboard": return Vector3(0.23, 0.02, 0.32)
	return Vector3(0.15, 0.01, 0.1)
