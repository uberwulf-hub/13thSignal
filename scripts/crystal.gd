extends Node3D
## A signal fragment: a cluster of black obsidian shards around a glowing
## core whose colour drifts between violet and a sickly cyan, pulsing at an
## uneven rhythm. It glitches out of place now and then, dark motes drift in
## towards it, and it hums - you can hear one before you find it.

var _core_mat: StandardMaterial3D
var _light: OmniLight3D
var _shards: Node3D
var _hum: AudioStreamPlayer3D
var _t := 0.0
var _glitch_t := 1.0


func _ready() -> void:
	_t = randf() * 10.0
	_shards = Node3D.new()
	add_child(_shards)
	# Smoky, almost-black violet glass: the core's light glows through it.
	var obsidian := StandardMaterial3D.new()
	obsidian.albedo_color = Color(0.07, 0.02, 0.11, 0.82)
	obsidian.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	obsidian.metallic = 0.3
	obsidian.roughness = 0.04
	obsidian.emission_enabled = true
	obsidian.emission = Color(0.25, 0.05, 0.4)
	obsidian.emission_energy_multiplier = 0.35
	obsidian.rim_enabled = true
	obsidian.rim = 0.6
	obsidian.rim_tint = 0.3
	obsidian.clearcoat_enabled = true
	obsidian.clearcoat = 1.0
	# Jagged shards growing up and out from one base, like a crystal cluster.
	for i in 8:
		var shard := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radial_segments = 4
		sm.rings = 2
		sm.radius = 0.05
		sm.height = 0.1
		shard.mesh = sm
		shard.material_override = obsidian
		var len := randf_range(1.3, 2.6) if i > 0 else 3.2
		shard.scale = Vector3(randf_range(0.8, 1.2), len, randf_range(0.8, 1.2))
		shard.rotation = Vector3(randf_range(-0.6, 0.6), randf() * TAU, randf_range(-0.6, 0.6)) if i > 0 else Vector3.ZERO
		shard.position = Vector3(0, -0.06, 0) + shard.basis.y * 0.05 * len * 0.9
		_shards.add_child(shard)
	# The glowing core, half-hidden inside.
	_core_mat = StandardMaterial3D.new()
	_core_mat.albedo_color = Color(0.6, 0.3, 1.0)
	_core_mat.emission_enabled = true
	_core_mat.emission = Color(0.6, 0.3, 1.0)
	_core_mat.emission_energy_multiplier = 3.0
	var core := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radial_segments = 6
	cm.rings = 3
	cm.radius = 0.035
	cm.height = 0.11
	core.mesh = cm
	core.material_override = _core_mat
	_shards.add_child(core)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.6, 0.3, 1.0)
	_light.light_energy = 0.6
	_light.omni_range = 3.0
	add_child(_light)
	# Dark motes drawn in towards it.
	var motes := CPUParticles3D.new()
	motes.amount = 16
	motes.lifetime = 2.0
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	motes.emission_sphere_radius = 0.6
	motes.radial_accel_min = -0.6
	motes.radial_accel_max = -0.3
	motes.gravity = Vector3.ZERO
	motes.initial_velocity_min = 0.0
	motes.initial_velocity_max = 0.05
	motes.scale_amount_min = 0.01
	motes.scale_amount_max = 0.025
	var mm := SphereMesh.new()
	mm.radius = 1.0
	mm.height = 2.0
	motes.mesh = mm
	var mote_mat := StandardMaterial3D.new()
	mote_mat.albedo_color = Color(0.05, 0.0, 0.08)
	mote_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	motes.material_override = mote_mat
	add_child(motes)
	_hum = AudioStreamPlayer3D.new()
	_hum.stream = Sound.stream("crystal_hum")
	_hum.bus = Sound.WORLD
	_hum.unit_size = 1.2
	_hum.max_distance = 12.0
	_hum.volume_db = -8.0
	add_child(_hum)
	_hum.play()


func _process(delta: float) -> void:
	_t += delta
	# An uneven pulse, and a colour that won't settle.
	var pulse := 0.5 + 0.5 * sin(_t * 2.3) * sin(_t * 0.71 + 1.0)
	var hue_mix := 0.5 + 0.5 * sin(_t * 0.37)
	var col := Color(0.55, 0.15, 1.0).lerp(Color(0.15, 0.9, 0.75), hue_mix * 0.6)
	_core_mat.emission = col
	_core_mat.albedo_color = col
	_core_mat.emission_energy_multiplier = 0.8 + pulse * 1.8
	_light.light_color = col
	_light.light_energy = 0.3 + pulse * 0.7
	_shards.rotation.y += delta * 0.25
	_shards.position.y = sin(_t * 1.1) * 0.03
	# Now and then it glitches out of place for a moment.
	_glitch_t -= delta
	if _glitch_t <= 0.0:
		_glitch_t = randf_range(1.5, 4.5)
		_shards.position.x = randf_range(-0.04, 0.04)
		_shards.scale = Vector3(1.0, randf_range(0.85, 1.15), 1.0)
		_core_mat.emission_energy_multiplier = 3.5
		get_tree().create_timer(0.08).timeout.connect(func():
			if is_instance_valid(self):
				_shards.position.x = 0.0
				_shards.scale = Vector3.ONE)
