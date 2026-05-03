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
const RECOIL_RESET_DELAY := 0.40           # s of no-fire before pattern index resets
const RECOIL_SMOOTH_RATE := 22.0           # higher = snappier (per-shot kick exp-approaches over ~1/RATE s)
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
const CROUCH_RECOIL_MULT := 0.5
const HIP_RECOIL_MULT := 1.30      # extra kick when not ADS
const HIP_BLOOM_DEG := 1.8         # cone half-angle of random spread when hip-firing
const MOVE_BLOOM_DEG := 1.2        # extra bloom while moving on foot (uncrouched)
const AIR_BLOOM_DEG := 2.5         # extra bloom while airborne
const MOVE_SPEED_THRESHOLD := 0.5  # m/s of horizontal velocity to count as "moving"

const WEAPON_NAME := "AK-style Rifle"
const MAG_SIZE := 30
const BURST_COUNT := 3
const RELOAD_TIME := 2.0
enum FireMode { SEMI, BURST, AUTO }

@export var camera_path: NodePath
@export var player_path: NodePath

var _camera: Camera3D
var _player: Node    # CharacterBody3D w/ _yaw/_pitch
var _last_fire_time := -1000.0
var _recoil_index := 0
var _rng := RandomNumberGenerator.new()
# Smoothed recoil: shots add to *target*; _process exp-approaches it and applies the per-frame delta to the player view.
var _target_yaw := 0.0
var _target_pitch := 0.0
var _applied_yaw := 0.0
var _applied_pitch := 0.0
var _ammo := MAG_SIZE
var _fire_mode: FireMode = FireMode.AUTO
var _burst_remaining := 0
var _reloading := false
var _reload_remaining := 0.0

func _ready() -> void:
	_rng.randomize()
	if camera_path != NodePath():
		_camera = get_node(camera_path)
	if player_path != NodePath():
		_player = get_node(player_path)

func is_ads() -> bool:
	return _player != null and _player.has_method("is_ads") and _player.is_ads()

func get_weapon_name() -> String:
	return WEAPON_NAME

func get_ammo() -> int:
	return _ammo

func get_mag_size() -> int:
	return MAG_SIZE

func get_fire_mode_name() -> String:
	match _fire_mode:
		FireMode.SEMI: return "SEMI"
		FireMode.BURST: return "BURST"
		FireMode.AUTO: return "AUTO"
	return "?"

func is_reloading() -> bool:
	return _reloading

func get_reload_progress() -> float:
	if not _reloading or RELOAD_TIME <= 0.0:
		return 0.0
	return clampf(1.0 - _reload_remaining / RELOAD_TIME, 0.0, 1.0)

func get_current_bloom_deg() -> float:
	if _player == null:
		return 0.0
	var ads: bool = _player.has_method("is_ads") and _player.is_ads()
	var bloom_deg: float = 0.0
	if not ads:
		bloom_deg += HIP_BLOOM_DEG
	var crouched: bool = _player.has_method("is_crouched") and _player.is_crouched()
	var horiz_speed: float = Vector2(_player.velocity.x, _player.velocity.z).length()
	var moving: bool = horiz_speed > MOVE_SPEED_THRESHOLD
	var airborne: bool = not _player.is_on_floor()
	if moving and not crouched:
		bloom_deg += MOVE_BLOOM_DEG
	if airborne:
		bloom_deg += AIR_BLOOM_DEG
	return bloom_deg

func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0

	if Input.is_action_just_pressed("cycle_fire_mode") and not _reloading:
		_fire_mode = ((_fire_mode + 1) % FireMode.size()) as FireMode
		_burst_remaining = 0

	if Input.is_action_just_pressed("reload") and not _reloading and _ammo < MAG_SIZE:
		_reloading = true
		_reload_remaining = RELOAD_TIME
		_burst_remaining = 0

	if _reloading:
		_reload_remaining -= delta
		if _reload_remaining <= 0.0:
			_reload_remaining = 0.0
			_reloading = false
			_ammo = MAG_SIZE

	# Decide whether to fire this frame based on mode.
	var want_fire := false
	if not _reloading:
		match _fire_mode:
			FireMode.SEMI:
				want_fire = Input.is_action_just_pressed("fire")
			FireMode.AUTO:
				want_fire = Input.is_action_pressed("fire")
			FireMode.BURST:
				if Input.is_action_just_pressed("fire") and _burst_remaining == 0:
					_burst_remaining = BURST_COUNT
				want_fire = _burst_remaining > 0

	if want_fire and _ammo > 0 and now - _last_fire_time >= FIRE_INTERVAL:
		_fire(now)
		_ammo -= 1
		if _fire_mode == FireMode.BURST:
			_burst_remaining = max(_burst_remaining - 1, 0)
		if _ammo == 0:
			# Auto-reload when mag empties.
			_reloading = true
			_reload_remaining = RELOAD_TIME
			_burst_remaining = 0

	if now - _last_fire_time > RECOIL_RESET_DELAY:
		_recoil_index = 0
	_apply_smoothed_recoil(delta)

func _apply_smoothed_recoil(delta: float) -> void:
	if _player == null:
		return
	# Frame-rate-independent exponential approach.
	var alpha: float = 1.0 - exp(-RECOIL_SMOOTH_RATE * delta)
	var new_yaw: float = lerpf(_applied_yaw, _target_yaw, alpha)
	var new_pitch: float = lerpf(_applied_pitch, _target_pitch, alpha)
	var dy: float = new_yaw - _applied_yaw
	var dp: float = new_pitch - _applied_pitch
	if absf(dy) < 1e-6 and absf(dp) < 1e-6:
		return
	_player._yaw += dy
	_player._pitch = clampf(_player._pitch + dp, -1.4, 1.4)
	_player.rotation.y = _player._yaw
	_player._camera.rotation.x = _player._pitch
	_applied_yaw = new_yaw
	_applied_pitch = new_pitch

func _fire(now: float) -> void:
	_last_fire_time = now
	if _camera == null or _player == null:
		return

	var ads: bool = _player.has_method("is_ads") and _player.is_ads()

	# Bullet leaves at the *current* aim. The new kick goes into the smoothed
	# target — camera will lerp toward it over the next few frames, so the
	# crosshair drifts up smoothly instead of teleporting per shot.
	var pat := RECOIL_PATTERN[_recoil_index % RECOIL_PATTERN.size()]
	var jitter_yaw = _rng.randf_range(-RECOIL_JITTER_DEG, RECOIL_JITTER_DEG)
	var jitter_pitch = _rng.randf_range(-RECOIL_JITTER_DEG, RECOIL_JITTER_DEG)
	var mult: float = 1.0
	if _player.has_method("is_crouched") and _player.is_crouched():
		mult *= CROUCH_RECOIL_MULT
	if not ads:
		mult *= HIP_RECOIL_MULT
	_target_yaw += deg_to_rad(pat.x + jitter_yaw) * mult
	_target_pitch += deg_to_rad(pat.y + jitter_pitch) * mult
	_recoil_index += 1

	# Sim trajectory from camera origin in camera-forward direction.
	var origin: Vector3 = _camera.global_transform.origin
	var cam_basis: Basis = _camera.global_transform.basis
	var dir: Vector3 = -cam_basis.z
	dir = dir.normalized()
	# Bloom matches the on-screen crosshair (hip + movement + airborne).
	var bloom_deg: float = get_current_bloom_deg()
	if bloom_deg > 0.0:
		var ang: float = sqrt(_rng.randf()) * deg_to_rad(bloom_deg)
		var theta: float = _rng.randf() * TAU
		# Local offset in camera space (forward = -z).
		var local_offset := Vector3(sin(ang) * cos(theta), sin(ang) * sin(theta), -cos(ang))
		dir = (cam_basis * local_offset).normalized()
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
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	get_tree().current_scene.add_child(mi)
	mi.global_position = world_pos
	var timer := get_tree().create_timer(0.6)
	timer.timeout.connect(func(): if is_instance_valid(mi): mi.queue_free())
