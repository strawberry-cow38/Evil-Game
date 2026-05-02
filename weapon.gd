extends Node3D

# Hitscan-with-physics rifle. Each shot:
#   1. Adds recoil pattern offset (with jitter) to aim
#   2. Step-marches a virtual bullet (velocity + gravity drop)
#   3. Schedules damage at impact_time = distance / muzzle_velocity
#   4. Renders a tracer line for the full path

const FIRE_INTERVAL := 0.10                # 600 RPM
const MUZZLE_VELOCITY := 500.0             # m/s
const BULLET_GRAVITY := 3.0                # m/s^2 (Rust-ish, gentle drop)
const STEP_DT := 0.01                      # trajectory sim step
const MAX_SIM_TIME := 4.0                  # cap (=2km @ 500m/s)
const RECOIL_RECOVER_DELAY := 0.40         # s of no-fire before pattern resets
const RECOIL_RECOVER_RATE := 6.0           # rad/s back toward zero
const TRACER_LIFETIME := 0.06              # s

# Recoil pattern: (yaw_deg, pitch_deg) per shot. Pitch is "kick up" so positive = up.
# Classic vertical climb with mild horizontal drift, AK-style.
const RECOIL_PATTERN: Array[Vector2] = [
	Vector2( 0.00, 0.45),
	Vector2( 0.05, 0.55),
	Vector2(-0.05, 0.65),
	Vector2( 0.10, 0.70),
	Vector2(-0.15, 0.65),
	Vector2( 0.20, 0.60),
	Vector2(-0.25, 0.55),
	Vector2( 0.35, 0.50),
	Vector2(-0.40, 0.45),
	Vector2( 0.45, 0.40),
	Vector2(-0.50, 0.40),
	Vector2( 0.55, 0.35),
]
const RECOIL_JITTER_DEG := 0.12

@export var camera_path: NodePath
@export var player_path: NodePath

var _camera: Camera3D
var _player: Node    # CharacterBody3D w/ _yaw/_pitch
var _last_fire_time := -1000.0
var _recoil_index := 0
var _accum_recoil_pitch := 0.0   # current applied (rad) so we can recover
var _accum_recoil_yaw := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	if camera_path != NodePath():
		_camera = get_node(camera_path)
	if player_path != NodePath():
		_player = get_node(player_path)

func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if Input.is_action_pressed("fire") and now - _last_fire_time >= FIRE_INTERVAL:
		_fire(now)
	# Recoil recovery: if not firing for a while, drift back to zero.
	if now - _last_fire_time > RECOIL_RECOVER_DELAY:
		_recoil_index = 0
		var step := RECOIL_RECOVER_RATE * delta
		_recover_recoil(step)

func _recover_recoil(step: float) -> void:
	if absf(_accum_recoil_pitch) > 0.0001:
		var dp = clampf(step, 0.0, absf(_accum_recoil_pitch))
		var sign_p = signf(_accum_recoil_pitch)
		_accum_recoil_pitch -= sign_p * dp
		_player._pitch -= sign_p * dp
		_player._camera.rotation.x = _player._pitch
	if absf(_accum_recoil_yaw) > 0.0001:
		var dy = clampf(step, 0.0, absf(_accum_recoil_yaw))
		var sign_y = signf(_accum_recoil_yaw)
		_accum_recoil_yaw -= sign_y * dy
		_player._yaw -= sign_y * dy
		_player.rotation.y = _player._yaw

func _fire(now: float) -> void:
	_last_fire_time = now
	if _camera == null or _player == null:
		return

	# Apply recoil to player view BEFORE computing the shot direction —
	# the bullet flies wherever the muzzle is now pointing (post-kick), like Rust.
	var pat := RECOIL_PATTERN[_recoil_index % RECOIL_PATTERN.size()]
	var jitter_yaw = _rng.randf_range(-RECOIL_JITTER_DEG, RECOIL_JITTER_DEG)
	var jitter_pitch = _rng.randf_range(-RECOIL_JITTER_DEG, RECOIL_JITTER_DEG)
	var d_yaw = deg_to_rad(pat.x + jitter_yaw)
	var d_pitch = deg_to_rad(pat.y + jitter_pitch)
	_player._yaw += d_yaw
	_player._pitch = clampf(_player._pitch + d_pitch, -1.4, 1.4)
	_player.rotation.y = _player._yaw
	_player._camera.rotation.x = _player._pitch
	_accum_recoil_yaw += d_yaw
	_accum_recoil_pitch += d_pitch
	_recoil_index += 1

	# Sim trajectory from camera origin in camera-forward direction.
	var origin: Vector3 = _camera.global_transform.origin
	var dir: Vector3 = -_camera.global_transform.basis.z
	dir = dir.normalized()
	var vel: Vector3 = dir * MUZZLE_VELOCITY
	var gravity := Vector3(0.0, -BULLET_GRAVITY, 0.0)

	var space := get_world_3d().direct_space_state
	var pos := origin
	var t := 0.0
	var hit_pos := Vector3.ZERO
	var has_hit := false
	while t < MAX_SIM_TIME:
		var next_pos := pos + vel * STEP_DT + gravity * 0.5 * STEP_DT * STEP_DT
		vel += gravity * STEP_DT
		var q := PhysicsRayQueryParameters3D.create(pos, next_pos)
		var ex: Array[RID] = []
		if _player is CollisionObject3D:
			ex.append((_player as CollisionObject3D).get_rid())
		q.exclude = ex
		var r := space.intersect_ray(q)
		if r and r.has("position"):
			hit_pos = r.position
			has_hit = true
			break
		pos = next_pos
		t += STEP_DT

	if not has_hit:
		hit_pos = pos

	var distance := origin.distance_to(hit_pos)
	var impact_delay := distance / MUZZLE_VELOCITY
	_spawn_tracer(origin, hit_pos)
	if has_hit:
		_schedule_impact(hit_pos, impact_delay)

func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(from)
	mesh.surface_add_vertex(to)
	mesh.surface_end()

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.4, 1.0)
	mat.disable_receive_shadows = true
	mi.material_override = mat
	get_tree().current_scene.add_child(mi)

	var timer := get_tree().create_timer(TRACER_LIFETIME)
	timer.timeout.connect(func(): if is_instance_valid(mi): mi.queue_free())

func _schedule_impact(world_pos: Vector3, delay: float) -> void:
	if delay <= 0.0:
		_apply_impact(world_pos)
		return
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func(): _apply_impact(world_pos))

func _apply_impact(world_pos: Vector3) -> void:
	# Placeholder hit marker — small short-lived sphere.
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.04
	sm.height = 0.08
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0.2, 0.2, 1)
	mi.material_override = mat
	mi.global_position = world_pos
	get_tree().current_scene.add_child(mi)
	var timer := get_tree().create_timer(0.6)
	timer.timeout.connect(func(): if is_instance_valid(mi): mi.queue_free())
