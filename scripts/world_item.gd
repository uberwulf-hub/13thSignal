extends RigidBody3D
## An item lying in the world, or flying through the air after you threw it.
## Look at it and press E to put it in your inventory. A thrown item makes a
## noise where it lands (the Listener goes to check), and some break.
## A cracked glow stick lights the area for a while; mannequins can't move in
## its light.

const Items := preload("res://scripts/items.gd")
const GLOW_TIME := 90.0

var sector: Node
var item_id := ""
var thrown := false
var lit := false
var _landed := false
var _light: OmniLight3D
var _glow_t := 0.0


func setup(s: Node, id: String, is_lit := false) -> void:
	sector = s
	item_id = id
	lit = is_lit
	# Layer 2: your look-ray can find it. It falls onto and rolls on the
	# world (mask 1), but you walk straight through it.
	collision_layer = 2
	collision_mask = 1
	mass = 0.4
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 2
	add_child(Items.model(id, lit))
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Items.size(id)
	cs.shape = box
	cs.position.y = box.size.y / 2.0
	add_child(cs)
	body_entered.connect(_on_hit)
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


func _on_hit(_body: Node) -> void:
	if not thrown or _landed:
		return
	if linear_velocity.length() < 1.0 and not thrown:
		return
	_landed = true
	var info := Items.info(item_id)
	Sound.play_at(info.get("hit", "hit_soft"), global_position, 0.0, randf_range(0.9, 1.1))
	# The noise it makes is the point: the Listener goes to see what it was.
	sector.emit_noise(global_position, float(info.get("noise", 6.0)), false)
	if info.get("breaks", false):
		queue_free()


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
