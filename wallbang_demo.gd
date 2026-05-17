extends Node3D

# Headless capture: builds a picket fence + a brick back-wall a few meters
# behind it, then fires simulated bullets at the picket fence so the
# recording shows entry impact, exit impact, ricochet onto the back wall,
# and damage falloff. Mirrors the wallbang loop in weapon.gd::_fire_pellet
# without pulling in the full player/audio stack.

const FENCES_SCRIPT := preload("res://editor_fences.gd")

const RUN_LEN: float = 8.0
const FENCE_Z: float = 0.0
const WALL_Z: float = 3.0
const FIRE_INTERVAL: float = 0.55
const PRE_DELAY: float = 0.8
const POST_DELAY: float = 3.5
const MAX_WALLBANGS := 2
const WALLBANG_PEN_DEPTH := 0.12
const WALLBANG_VEL_MULT := 0.55
const WALLBANG_SPREAD_DEG := 4.0
const MUZZLE_SPEED := 500.0
const TRACER_LIFETIME := 0.25
const DECAL_LIFETIME := 5.0

@onready var cam: Camera3D = $CameraRig/Camera3D
@onready var rig: Node3D = $CameraRig

var fences: Node3D
var terrain: Node3D
var elapsed: float = 0.0
var fire_idx: int = 0
var next_fire_t: float = PRE_DELAY
var fire_points: Array = []
var ready_done: bool = false
var done: bool = false
var quit_t: float = -1.0
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	terrain = $TerrainStub
	fences = Node3D.new()
	fences.set_script(FENCES_SCRIPT)
	add_child(fences)
	fences.setup(terrain)
	fences.enable_collision(true)
	fences.set_variant("picket")
	fences.begin_drag(Vector3(0, 0, FENCE_Z), false, false, 2.36)
	fences.commit_drag(Vector3(RUN_LEN, 0, FENCE_Z), false, false, 2.36)
	# Build a concrete back-wall a few meters behind the fence. Each panel
	# is a StaticBody3D so bullets register normal impacts on it after
	# punching through the picket.
	_build_back_wall()
	# Pre-compute the bullet origins so each shot lines up with a picket.
	# Two-frame await: pickets are spawned synchronously but the physics
	# server only registers their colliders on the next physics tick.
	await get_tree().process_frame
	await get_tree().process_frame
	fire_points = _pick_fire_points()
	ready_done = true

func _build_back_wall() -> void:
	var holder := Node3D.new()
	add_child(holder)
	var box_size := Vector3(12.0, 2.4, 0.2)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.74, 0.66)
	mat.roughness = 0.95
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(RUN_LEN * 0.5, box_size.y * 0.5, WALL_Z)
	holder.add_child(mi)
	var body := StaticBody3D.new()
	body.position = mi.position
	var shape := CollisionShape3D.new()
	var col_box := BoxShape3D.new()
	col_box.size = box_size
	shape.shape = col_box
	body.add_child(shape)
	holder.add_child(body)

func _pick_fire_points() -> Array:
	# Sample picket bodies in left-to-right order, then turn each into a
	# {origin, target} pair where origin sits in front of the camera and
	# target points at the picket's chest height.
	var picks: Array = []
	for n in get_tree().get_nodes_in_group("fence_picket_destructible"):
		if not (n is StaticBody3D):
			continue
		picks.append(n)
	picks.sort_custom(func(a, b): return a.global_position.x < b.global_position.x)
	# Take every other picket so the camera has time to sweep between shots.
	var out: Array = []
	for i in range(picks.size()):
		if i % 2 != 0:
			continue
		var picket: StaticBody3D = picks[i]
		# picket.global_position is the body center (mid-picket Y) — aim there
		# directly so the ray hits the box, not above its top.
		var aim: Vector3 = picket.global_position
		var origin: Vector3 = Vector3(aim.x, aim.y + 0.4, -4.5)
		out.append({"origin": origin, "aim": aim})
	return out

func _process(delta: float) -> void:
	if not ready_done:
		return
	elapsed += delta
	# Camera follows the shooter — same X as the current shot, fixed Y/Z.
	var t01: float = clampf(elapsed / 9.0, 0.0, 1.0)
	var cx: float = lerpf(0.5, RUN_LEN - 0.5, smoothstep(0.0, 1.0, t01))
	rig.position = Vector3(cx, 1.7, -5.5)
	cam.look_at(Vector3(cx, 1.0, FENCE_Z + 1.0), Vector3.UP)
	if not done and elapsed >= next_fire_t and fire_idx < fire_points.size():
		var fp: Dictionary = fire_points[fire_idx]
		_fire_shot(fp["origin"], (fp["aim"] - fp["origin"]).normalized())
		fire_idx += 1
		next_fire_t = elapsed + FIRE_INTERVAL
	if not done and fire_idx >= fire_points.size():
		done = true
		quit_t = elapsed + POST_DELAY
	if done and elapsed >= quit_t:
		get_tree().quit()

func _fire_shot(origin: Vector3, pdir: Vector3) -> void:
	# Stripped clone of weapon.gd::_fire_pellet — straight-line raycast,
	# wallbang exit + scatter + dmg/velocity damping, repeats up to
	# MAX_WALLBANGS times. Spawns coloured tracers per segment + impact
	# decals at every hit point.
	var vel: Vector3 = pdir * MUZZLE_SPEED
	var space := get_world_3d().direct_space_state
	var pos: Vector3 = origin
	var seg_start: Vector3 = origin
	var penetrations: int = 0
	var excludes: Array[RID] = []
	while true:
		var step: Vector3 = vel.normalized() * 200.0
		var q := PhysicsRayQueryParameters3D.create(pos, pos + step)
		# Mask out the fence player-smoothing wall (layer 6 = bit 5) so the
		# bullet ignores it and resolves on the precise per-picket colliders
		# behind. Mirrors weapon.gd::_fire_pellet.
		q.collision_mask = 0xFFFFFFFF & ~(1 << 5)
		q.exclude = excludes
		var r := space.intersect_ray(q)
		var hit_pos: Vector3 = pos + step
		var has_hit := false
		var hit_normal := Vector3.UP
		var hit_collider: Object = null
		if r and r.has("position"):
			hit_pos = r.position
			hit_normal = r.get("normal", Vector3.UP)
			hit_collider = r.get("collider", null)
			has_hit = true
		_spawn_tracer(seg_start, hit_pos, penetrations)
		if not has_hit:
			return
		_spawn_impact_decal(hit_pos, hit_normal)
		_maybe_notify_picket(hit_collider, hit_pos, hit_normal)
		if penetrations >= MAX_WALLBANGS or not _is_wallbangable(hit_collider):
			return
		var dir_n: Vector3 = vel.normalized()
		var exit_pos: Vector3 = hit_pos + dir_n * WALLBANG_PEN_DEPTH
		_spawn_impact_decal(exit_pos, -hit_normal)
		vel = _scatter_dir(dir_n, WALLBANG_SPREAD_DEG) * (vel.length() * WALLBANG_VEL_MULT)
		pos = exit_pos
		seg_start = exit_pos
		if hit_collider is CollisionObject3D:
			excludes.append((hit_collider as CollisionObject3D).get_rid())
		penetrations += 1

func _maybe_notify_picket(collider: Object, hit_pos: Vector3, hit_normal: Vector3) -> void:
	# Only "kill" a picket on the FIRST penetration so the back-wall hit
	# still has something to punch through visually — otherwise the picket
	# disappears the frame the bullet passes, robbing the exit decal of a
	# surface to live on (decals would orphan). Skipping subsequent passes
	# avoids that race.
	if collider == null:
		return
	var n: Node = collider as Node
	if n == null or not n.is_in_group("fence_picket_destructible"):
		return
	if fences.has_method("notify_picket_hit"):
		fences.notify_picket_hit(n, hit_pos, hit_normal)

func _is_wallbangable(collider: Object) -> bool:
	if collider == null:
		return false
	var n: Node = collider as Node
	if n == null:
		return false
	if not n.is_in_group("fence_picket_destructible"):
		return false
	return bool(n.get_meta("wallbang", false))

func _scatter_dir(dir: Vector3, half_angle_deg: float) -> Vector3:
	var ang: float = sqrt(rng.randf()) * deg_to_rad(half_angle_deg)
	var axis := dir.cross(Vector3.UP)
	if axis.length_squared() < 0.001:
		axis = dir.cross(Vector3.RIGHT)
	axis = axis.normalized()
	var phi: float = rng.randf() * TAU
	return dir.rotated(axis, ang).rotated(dir, phi).normalized()

func _spawn_tracer(a: Vector3, b: Vector3, segment_idx: int) -> void:
	var im := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	im.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Colour-code segments: entry segment = bright yellow, post-wallbang segs fade orange→red.
	var cols: Array = [Color(1, 0.95, 0.4), Color(1, 0.6, 0.2), Color(1, 0.3, 0.2)]
	var c: Color = cols[clampi(segment_idx, 0, cols.size() - 1)]
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 4.0
	im.material_override = mat
	add_child(im)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(a)
	mesh.surface_add_vertex(b)
	mesh.surface_end()
	get_tree().create_timer(TRACER_LIFETIME).timeout.connect(func():
		if is_instance_valid(im):
			im.queue_free()
	)

func _spawn_impact_decal(world_pos: Vector3, normal: Vector3) -> void:
	# Small unshaded disc oriented to the surface. Persists DECAL_LIFETIME
	# seconds so back-to-back shots leave a visible trail of bullet holes.
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.07, 0.07)
	mi.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.05, 0.05, 0.05)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	add_child(mi)
	mi.global_position = world_pos + normal.normalized() * 0.003
	# Orient the quad's local +Z to the surface normal so the disc faces out.
	var n: Vector3 = normal.normalized()
	var up: Vector3 = Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT
	mi.look_at(mi.global_position + n, up)
	get_tree().create_timer(DECAL_LIFETIME).timeout.connect(func():
		if is_instance_valid(mi):
			mi.queue_free()
	)
