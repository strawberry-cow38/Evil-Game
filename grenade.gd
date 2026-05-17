extends Node3D

# 40mm grenade — physical projectile with gravity. Raycasts each step from
# prev->next position so it can't tunnel through thin walls. On contact
# spawns an explosion (particles + brief light flash) and frees itself.

const STEP_SCALE := 1.0           # marches at delta * vel each frame
const GRAVITY := 9.8
const MAX_LIFETIME := 8.0

const EXPLOSION_PARTICLE_COUNT := 80
const EXPLOSION_RADIUS := 5.0
const EXPLOSION_DAMAGE := 220        # damage at the epicentre; tapers linearly to 0 at EXPLOSION_RADIUS
const EXPLOSION_IMPULSE := 18.0      # peak knockback impulse for dynamic props at the epicentre
const EXPLOSION_LIGHT_ENERGY := 8.0
const EXPLOSION_LIGHT_RANGE := 12.0
const EXPLOSION_LIGHT_FADE := 0.25
const EXPLOSION_SOUND_PATH := "res://assets/audio/explosion.ogg"
const EXPLOSION_VOL_DB := 2.0
const EXPLOSION_PITCH_MIN := 0.92
const EXPLOSION_PITCH_MAX := 1.06

var _velocity: Vector3 = Vector3.ZERO
var _exclude: Array[RID] = []
var _age := 0.0
var _exploded := false

func setup(start_pos: Vector3, start_vel: Vector3, exclude: Array[RID]) -> void:
	global_position = start_pos
	_velocity = start_vel
	_exclude = exclude

func _ready() -> void:
	# Visible 40mm shell.
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.02
	mesh.height = 0.04
	mesh.radial_segments = 10
	mesh.rings = 5
	var mat := StandardMaterial3D.new()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.albedo_color = Color(0.45, 0.35, 0.10)
	mat.metallic = 0.6
	mat.roughness = 0.5
	mesh.material = mat
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _apply_splash(world_pos: Vector3) -> void:
	var tree := get_tree()
	if tree == null:
		return
	# Damage: walk every node with a take_damage method that sits within
	# EXPLOSION_RADIUS. Linear falloff. Headshots etc. flow through whatever
	# the receiver's take_damage already does.
	for n in tree.get_nodes_in_group("dynamic_prop"):
		if not (n is RigidBody3D) or not is_instance_valid(n):
			continue
		var rb: RigidBody3D = n
		var to_node: Vector3 = rb.global_position - world_pos
		var dist: float = to_node.length()
		if dist >= EXPLOSION_RADIUS:
			continue
		var falloff: float = 1.0 - (dist / EXPLOSION_RADIUS)
		var dir: Vector3 = (to_node + Vector3(0.0, 0.3, 0.0)).normalized()
		var impulse: Vector3 = dir * EXPLOSION_IMPULSE * falloff * rb.mass
		rb.apply_central_impulse(impulse)
	# Damage receivers — dummies live as StaticBody3D w/ a take_damage method.
	# Walk the whole scene tree once and dispatch. Cheap enough for the prop
	# counts we ship; if it grows we can swap in a spatial query.
	_apply_damage_recursive(tree.current_scene, world_pos)
	# Fence destruction — every picket within radius takes a synthetic hit at
	# its own position so the existing weapon-driven destruction path fires.
	var fences_root := tree.current_scene.get_node_or_null("Fences")
	if fences_root != null and fences_root.has_method("notify_picket_hit"):
		for n in tree.get_nodes_in_group("fence_picket_destructible"):
			if not (n is Node3D) or not is_instance_valid(n):
				continue
			var p: Node3D = n
			var d: float = p.global_position.distance_to(world_pos)
			if d > EXPLOSION_RADIUS:
				continue
			fences_root.notify_picket_hit(p, p.global_position)

func _apply_damage_recursive(node: Node, world_pos: Vector3) -> void:
	if node == null:
		return
	if node is Node3D:
		var n3d: Node3D = node
		var d: float = n3d.global_position.distance_to(world_pos)
		if d < EXPLOSION_RADIUS:
			var falloff: float = 1.0 - (d / EXPLOSION_RADIUS)
			var dmg: int = int(round(EXPLOSION_DAMAGE * falloff))
			if dmg > 0:
				if node.has_method("take_damage"):
					node.call("take_damage", dmg)
				elif node.has_meta("destructible") and bool(node.get_meta("destructible")):
					var hp: int = int(node.get_meta("hp", 0))
					hp = max(hp - dmg, 0)
					node.set_meta("hp", hp)
					if hp <= 0:
						node.queue_free()
						# Skip recursion — children freed alongside parent.
						return
	for c in node.get_children():
		_apply_damage_recursive(c, world_pos)

func _physics_process(delta: float) -> void:
	if _exploded:
		return
	_age += delta
	if _age > MAX_LIFETIME:
		_explode(global_position, Vector3.UP)
		return
	var next_vel: Vector3 = _velocity + Vector3(0, -GRAVITY, 0) * delta
	var next_pos: Vector3 = global_position + (_velocity + next_vel) * 0.5 * delta
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position, next_pos)
	q.exclude = _exclude
	var r := space.intersect_ray(q)
	if r and r.has("position"):
		_explode(r.position, r.get("normal", Vector3.UP))
		return
	global_position = next_pos
	_velocity = next_vel
	# Orient nose along velocity.
	if _velocity.length_squared() > 0.01:
		var fwd: Vector3 = _velocity.normalized()
		var up: Vector3 = Vector3.UP if absf(fwd.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		look_at(global_position + fwd, up)

func _explode(world_pos: Vector3, normal: Vector3) -> void:
	_exploded = true
	var scene := get_tree().current_scene
	if scene == null:
		queue_free()
		return

	# Area damage + knockback. Distance-tapered falloff so a near-miss is
	# survivable. Damage hits anything with take_damage(int); impulse hits
	# anything in the dynamic_prop group (props with frozen=false).
	_apply_splash(world_pos)

	# Fireball / debris particles.
	var p := CPUParticles3D.new()
	var pmesh := SphereMesh.new()
	pmesh.radius = 0.06
	pmesh.height = 0.12
	pmesh.radial_segments = 6
	pmesh.rings = 3
	var pmat := StandardMaterial3D.new()
	pmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.albedo_color = Color(1.0, 0.55, 0.10)
	pmat.disable_receive_shadows = true
	pmesh.material = pmat
	p.mesh = pmesh
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = EXPLOSION_PARTICLE_COUNT
	p.lifetime = 0.9
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 12.0
	p.gravity = Vector3(0, -9.0, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	p.damping_min = 1.5
	p.damping_max = 4.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(p)
	p.global_position = world_pos + normal.normalized() * 0.05
	p.restart()
	p.emitting = true

	# Boom — load the stream straight from disk like the rest of the audio,
	# since .import is gitignored on the source-pull repo.
	var snd_path := ProjectSettings.globalize_path(EXPLOSION_SOUND_PATH)
	if FileAccess.file_exists(snd_path):
		var sp := AudioStreamPlayer3D.new()
		sp.stream = AudioStreamOggVorbis.load_from_file(snd_path)
		sp.bus = "Master"
		sp.volume_db = EXPLOSION_VOL_DB
		sp.unit_size = 30.0
		sp.max_distance = 200.0
		sp.pitch_scale = randf_range(EXPLOSION_PITCH_MIN, EXPLOSION_PITCH_MAX)
		scene.add_child(sp)
		sp.global_position = world_pos
		sp.play()
		var st := get_tree().create_timer(4.0)
		var sp_ref: WeakRef = weakref(sp)
		st.timeout.connect(func():
			var n: Node = sp_ref.get_ref() as Node
			if n != null:
				n.queue_free()
		)

	# Brief light flash.
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = EXPLOSION_LIGHT_ENERGY
	light.omni_range = EXPLOSION_LIGHT_RANGE
	scene.add_child(light)
	light.global_position = world_pos + normal.normalized() * 0.2
	# Tween lives on the light, not on self — self queue_frees at end of _explode.
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 0.0, EXPLOSION_LIGHT_FADE)
	lt.tween_callback(light.queue_free)

	# Cleanup the particles + self after particles finish.
	var t := get_tree().create_timer(p.lifetime + 0.4)
	var p_ref: WeakRef = weakref(p)
	t.timeout.connect(func():
		var n: Node = p_ref.get_ref() as Node
		if n != null:
			n.queue_free()
	)
	queue_free()
