extends RigidBody3D
## An item lying in the world, or flying through the air after you threw it.
## Look at it and press E to put it in your inventory. Every time it hits
## something you hear two things: the item itself (a can's tinny clank, a
## wrench's ring) and whatever it hit (concrete, a grate, a metal door, glass,
## a hollow mannequin). It bounces off solid things, including mannequins.
## A thrown item makes a noise the Listener hears, and glass can shatter.
## A cracked glow stick lights the area for a while; mannequins can't move in
## its light.

const Items := preload("res://scripts/items.gd")
const GLOW_TIME := 90.0

var sector: Node
var item_id := ""
var thrown := false
var lit := false
var _light: OmniLight3D
var _glow_t := 0.0
var _prev_vel := Vector3.ZERO
var _touching: Dictionary = {}     # collider id -> true, last physics step
var _sound_cd: Dictionary = {}     # collider id -> time left before it can sound again
var _noises := 0
var hit_mannequin := false
var surfaces_hit: Array[String] = []


func setup(s: Node, id: String, is_lit := false) -> void:
	sector = s
	item_id = id
	lit = is_lit
	# Layer 2: your look-ray can find it. It falls onto and rolls on the
	# world (mask 1), but you walk straight through it.
	collision_layer = 2
	collision_mask = 1 | 8      # the world, and mannequins (layer 4)
	mass = 0.4
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	var info := Items.info(id)
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = float(info.get("bounce", 0.2))
	physics_material_override.friction = 0.7
	var m := Items.model(id, lit)
	add_child(m)
	# The physics shape fits the model, whichever model it is.
	var bounds := AABB()
	var first := true
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var mesh_node: MeshInstance3D = mi
		var chain := Transform3D()
		var n: Node = mesh_node
		while n != self:
			chain = (n as Node3D).transform * chain
			n = n.get_parent()
		var b: AABB = chain * mesh_node.get_aabb()
		bounds = b if first else bounds.merge(b)
		first = false
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = bounds.size.max(Vector3(0.02, 0.01, 0.02)) if not first else Items.size(id)
	cs.shape = box
	cs.position = bounds.position + bounds.size / 2.0 if not first else Vector3(0, box.size.y / 2.0, 0)
	add_child(cs)
	if lit:
		_light = OmniLight3D.new()
		_light.light_color = Color(0.35, 1.0, 0.45)
		_light.light_energy = 1.4
		_light.omni_range = 5.0
		_light.position.y = 0.1
		add_child(_light)
		_glow_t = GLOW_TIME
		sector.glows.append(self)


func prompt() -> String:
	if lit:
		return ""
	return "Take " + Items.info(item_id)["name"].to_lower()


func interact(player: Node) -> void:
	if lit:
		return
	if player.add_item(item_id):
		Sound.play("pickup_item", -10.0, randf_range(0.95, 1.1))
		queue_free()


## Watch for new contacts every physics step: each one is a hit (a bounce,
## the first touch of a wall, landing on the floor) and gets its own sound.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var now: Dictionary = {}
	for i in state.get_contact_count():
		var id := state.get_contact_collider_id(i)
		now[id] = true
		if _touching.has(id) or _sound_cd.get(id, 0.0) > 0.0:
			continue
		var n := state.get_contact_local_normal(i)
		var speed := absf(_prev_vel.dot(n))
		if speed < 0.7:
			continue
		_sound_cd[id] = 0.09
		call_deferred("_impact", state.get_contact_collider_object(i), state.get_contact_local_position(i), n, speed)
	_touching = now
	_prev_vel = state.linear_velocity
	for k in _sound_cd.keys():
		_sound_cd[k] -= state.step


## What is this made of? Things can say for themselves (meta "surface");
## otherwise it's the building: concrete, or a metal grate in the floor.
func _surface_of(obj: Object, pos: Vector3, n: Vector3) -> String:
	if obj and obj.has_meta("surface"):
		return obj.get_meta("surface")
	if absf(n.y) > 0.6 and pos.y < 0.4 and sector.is_grate(pos):
		return "grate"
	return "concrete"


func _impact(obj: Object, pos: Vector3, n: Vector3, speed: float) -> void:
	if not is_inside_tree():
		return
	var info := Items.info(item_id)
	var surface := _surface_of(obj, pos, n)
	surfaces_hit.append(surface)
	# Louder the harder it hits; a gentle roll is barely a tick.
	var amount := clampf(speed / 7.0, 0.06, 1.0)
	var vol := linear_to_db(amount)
	# Glass and china shatter if they hit hard enough (a mannequin is softer).
	var breaks_at := float(info.get("breaks_at", 0.0))
	if thrown and breaks_at > 0.0 and speed >= breaks_at * (1.4 if surface == "mannequin" else 1.0):
		Sound.play_at("hit_glass", pos, vol + 2.0, randf_range(0.9, 1.1))
		Sound.play_at("surf_" + surface, pos, vol - 4.0, randf_range(0.92, 1.08))
		_make_noise(pos, info, 1.0)
		if surface == "mannequin":
			_mannequin_reacts(obj, pos)
		queue_free()
		return
	Sound.play_at(info.get("obj", "obj_plastic"), pos, vol - 2.0, randf_range(0.93, 1.07))
	Sound.play_at("surf_" + surface, pos, vol - (0.0 if surface == "mannequin" else 3.0), randf_range(0.92, 1.08))
	if thrown:
		_make_noise(pos, info, amount)
	if surface == "mannequin" and speed > 1.5:
		_mannequin_reacts(obj, pos)


## Hit a mannequin and, a moment later, it makes a sound of its own. Quiet.
## Something shifting inside it. Something that might have been a breath.
func _mannequin_reacts(_obj: Object, pos: Vector3) -> void:
	hit_mannequin = true
	var at := pos
	get_tree().create_timer(randf_range(0.25, 0.5)).timeout.connect(
		func(): Sound.play_at("mq_hit_reaction", at, -10.0 if Game.is_explorer() else -6.0, randf_range(0.9, 1.05)))


## The Listener hears it. The first hit is the loud one; each bounce after
## that is quieter, and it soon stops counting.
func _make_noise(pos: Vector3, info: Dictionary, amount: float) -> void:
	if _noises >= 4:
		return
	# The first landing always carries (that's the point of throwing it);
	# the bounces after it are quieter.
	var radius := float(info.get("noise", 6.0)) * (clampf(amount * 1.6, 0.75, 1.0) if _noises == 0 else clampf(amount * 1.6, 0.35, 1.0) * 0.6)
	_noises += 1
	sector.emit_noise(pos, radius, false)


func _process(delta: float) -> void:
	if not lit:
		return
	_glow_t -= delta
	_light.light_energy = 1.4 * clampf(_glow_t / 15.0, 0.0, 1.0)
	if _glow_t <= 0.0:
		sector.glows.erase(self)
		queue_free()


## Is a glow stick's light still bright enough to hold the mannequins?
func glowing() -> bool:
	return lit and _glow_t > 5.0
