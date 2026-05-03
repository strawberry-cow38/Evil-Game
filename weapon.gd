extends Node3D

# Hitscan-with-physics rifle. Each shot:
#   1. Adds recoil pattern offset (with jitter) to aim
#   2. Step-marches a virtual bullet (velocity + gravity drop)
#   3. Schedules damage at impact_time = distance / muzzle_velocity
#   4. Renders a tracer line for the full path

const MAX_RPM := 600.0
const FIRE_INTERVAL := 60.0 / MAX_RPM      # hard-clamped at 600 RPM
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
const FIRE_SOUND_PATH := "res://assets/audio/Shot_GTEK762mmSoviet.ogg"
const FIRE_PITCH_MIN := 0.94
const FIRE_PITCH_MAX := 1.06
const FIRE_VOL_DB := -4.0
const FIRE_HOLD_TIME := 0.22    # full-volume window before fade kicks in
const FIRE_FADE_TIME := 0.32    # fade-out length, kills the tail echo
const FIRE_FADE_DB := -50.0
const FIRE_VOICES := 4
const IMPACT_DIRT_PATH := "res://assets/audio/impact_dirt.ogg"
const IMPACT_CONCRETE_PATH := "res://assets/audio/impact_concrete.ogg"
const IMPACT_VOL_DB := -6.0
const IMPACT_PITCH_MIN := 0.92
const IMPACT_PITCH_MAX := 1.08
const IMPACT_VOICES := 6
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
var _audio_voices: Array[AudioStreamPlayer3D] = []
var _audio_tweens: Array[Tween] = []
var _audio_idx := 0
var _fire_stream: AudioStream
var _impact_streams: Dictionary = {}    # "dirt"/"concrete" -> AudioStream
var _impact_voices: Array[AudioStreamPlayer3D] = []
var _impact_idx := 0

func _ready() -> void:
	_rng.randomize()
	if camera_path != NodePath():
		_camera = get_node(camera_path)
	if player_path != NodePath():
		_player = get_node(player_path)
	_setup_audio()

func _setup_audio() -> void:
	# .import is gitignored on this source-pull repo, so res:// won't resolve the
	# .ogg via GD.Load. Load the file straight off disk at runtime.
	var abs_path: String = ProjectSettings.globalize_path(FIRE_SOUND_PATH)
	if FileAccess.file_exists(abs_path):
		_fire_stream = AudioStreamOggVorbis.load_from_file(abs_path)
	# Voice pool so fast-fire shots don't restart each other mid-fade —
	# the fade-out on shot N keeps ringing while shot N+1 starts on a fresh voice.
	for i in range(FIRE_VOICES):
		var p := AudioStreamPlayer3D.new()
		p.stream = _fire_stream
		p.volume_db = FIRE_VOL_DB
		p.unit_size = 14.0
		p.max_distance = 120.0
		p.bus = "Master"
		add_child(p)
		_audio_voices.append(p)
		_audio_tweens.append(null)
	# Impact streams (loaded at runtime — same .import-gitignored reason).
	_impact_streams["dirt"] = _load_wav(IMPACT_DIRT_PATH)
	_impact_streams["concrete"] = _load_wav(IMPACT_CONCRETE_PATH)
	# Roving impact voices live on the scene root so they play at the world
	# position of the hit, not at the gun.
	for i in range(IMPACT_VOICES):
		var ip := AudioStreamPlayer3D.new()
		ip.bus = "Master"
		ip.volume_db = IMPACT_VOL_DB
		ip.unit_size = 14.0
		ip.max_distance = 120.0
		_impact_voices.append(ip)

func _load_wav(res_path: String) -> AudioStream:
	var abs_path: String = ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(abs_path):
		return null
	return AudioStreamOggVorbis.load_from_file(abs_path)

func _play_fire_sound() -> void:
	if _fire_stream == null or _audio_voices.is_empty():
		return
	var idx: int = _audio_idx
	_audio_idx = (_audio_idx + 1) % _audio_voices.size()
	var voice: AudioStreamPlayer3D = _audio_voices[idx]
	# Cancel any in-flight fade on this voice before reusing it.
	var prev: Tween = _audio_tweens[idx]
	if prev != null and prev.is_valid():
		prev.kill()
	voice.volume_db = FIRE_VOL_DB
	voice.pitch_scale = _rng.randf_range(FIRE_PITCH_MIN, FIRE_PITCH_MAX)
	voice.play()
	# Hold full volume briefly, then fade the tail to silence and stop the voice.
	var t: Tween = create_tween()
	t.tween_interval(FIRE_HOLD_TIME)
	t.tween_property(voice, "volume_db", FIRE_FADE_DB, FIRE_FADE_TIME)
	t.tween_callback(voice.stop)
	_audio_tweens[idx] = t

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

	_play_fire_sound()

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
	var hit_normal := Vector3.UP
	var hit_collider: Object = null
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
			hit_normal = r.get("normal", Vector3.UP)
			hit_collider = r.get("collider", null)
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
		var material := _classify_material(hit_collider)
		_schedule_impact(hit_pos, hit_normal, material, impact_delay)

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

func _classify_material(collider: Object) -> String:
	if collider == null:
		return "concrete"
	var n: String = ""
	if collider is Node:
		n = (collider as Node).name
	if n == "Ground":
		return "dirt"
	if n.begins_with("Wall"):
		return "concrete"
	return "concrete"

func _schedule_impact(world_pos: Vector3, normal: Vector3, material: String, delay: float) -> void:
	if delay <= 0.0:
		_apply_impact(world_pos, normal, material)
		return
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func(): _apply_impact(world_pos, normal, material))

const BULLET_HOLE_HOLD := 4.0
const BULLET_HOLE_FADE := 2.5
const BULLET_HOLE_SIZE := 0.08

func _apply_impact(world_pos: Vector3, normal: Vector3, material: String) -> void:
	_play_impact_sound(world_pos, material)
	_spawn_impact_particles(world_pos, normal, material)
	_spawn_bullet_hole(world_pos, normal, material)

func _spawn_bullet_hole(world_pos: Vector3, normal: Vector3, material: String) -> void:
	var n: Vector3 = normal.normalized()
	var quad := QuadMesh.new()
	quad.size = Vector2(BULLET_HOLE_SIZE, BULLET_HOLE_SIZE)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	match material:
		"dirt":
			mat.albedo_color = Color(0.08, 0.05, 0.03, 0.95)
		"concrete":
			mat.albedo_color = Color(0.10, 0.10, 0.10, 0.95)
		_:
			mat.albedo_color = Color(0.05, 0.05, 0.05, 0.95)
	quad.material = mat

	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mi)
	# Orient quad so its +Z faces along the surface normal, then nudge it
	# slightly off the surface to avoid z-fighting.
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	mi.global_transform = Transform3D(Basis.looking_at(-n, up), world_pos + n * 0.005)

	var tween := create_tween()
	tween.tween_interval(BULLET_HOLE_HOLD)
	tween.tween_property(mat, "albedo_color:a", 0.0, BULLET_HOLE_FADE)
	tween.tween_callback(func(): if is_instance_valid(mi): mi.queue_free())

func _play_impact_sound(world_pos: Vector3, material: String) -> void:
	if not _impact_streams.has(material):
		return
	var stream: AudioStream = _impact_streams[material]
	if stream == null or _impact_voices.is_empty():
		return
	var idx: int = _impact_idx
	_impact_idx = (_impact_idx + 1) % _impact_voices.size()
	var voice: AudioStreamPlayer3D = _impact_voices[idx]
	if voice.is_inside_tree():
		voice.get_parent().remove_child(voice)
	get_tree().current_scene.add_child(voice)
	voice.global_position = world_pos
	voice.stream = stream
	voice.pitch_scale = _rng.randf_range(IMPACT_PITCH_MIN, IMPACT_PITCH_MAX)
	voice.volume_db = IMPACT_VOL_DB
	voice.play()

func _spawn_impact_particles(world_pos: Vector3, normal: Vector3, material: String) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_receive_shadows = true
	match material:
		"dirt":
			mat.albedo_color = Color(0.42, 0.28, 0.18, 1.0)
		"concrete":
			mat.albedo_color = Color(0.85, 0.83, 0.78, 1.0)
		_:
			mat.albedo_color = Color(0.7, 0.7, 0.7, 1.0)
	var mesh := SphereMesh.new()
	mesh.radius = 0.03
	mesh.height = 0.06
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = mat

	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 22
	p.lifetime = 0.6
	p.local_coords = false
	p.direction = normal.normalized()
	p.spread = 42.0
	p.initial_velocity_min = 1.8
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0.0, -7.0, 0.0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.damping_min = 1.0
	p.damping_max = 3.0
	# Cast/receive flags off so unshaded specks don't blow out shadow maps.
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	get_tree().current_scene.add_child(p)
	p.global_position = world_pos + normal.normalized() * 0.02   # nudge off the surface
	# Trigger emission after the node is in the tree + positioned.
	p.restart()
	p.emitting = true

	var timer := get_tree().create_timer(p.lifetime + 0.4)
	timer.timeout.connect(func(): if is_instance_valid(p): p.queue_free())
