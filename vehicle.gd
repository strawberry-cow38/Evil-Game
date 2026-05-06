extends VehicleBody3D

# Drivable vehicle. The same script powers three variants (car, motorcycle,
# countach) — set the `variant` property before add_child() and the per-
# variant tunables in VARIANTS overwrite the runtime members.
#
# Controls (driver only):
#   move_forward / move_back  — accelerate / brake-reverse
#   move_left / move_right    — steer
#   F                         — exit vehicle
#
# Player hand-off avoids reparenting (CharacterBody3D doesn't like
# riding inside another physics body). On enter we disable the player's
# script processing, hide its mesh, and switch the active camera to
# the vehicle's chase camera. On exit we pop the player out next to
# the driver door at the vehicle's current world position.

# Original car-default constants — kept as the "car" baseline. Per-variant
# overrides live in VARIANTS below and copy onto the runtime _foo members.
const ENGINE_FORCE := 2400.0
const REVERSE_FORCE := 1800.0
const BRAKE_FORCE := 14.0
const PASSIVE_BRAKE := 0.6   # mild drag when no input so the car coasts to a stop
const STEER_MAX := 0.55         # max wheel steer angle (radians) at low speed
const STEER_MAX_HIGH := 0.06    # max steer angle once cruising fast — prevents tip-overs
const STEER_SPEED_REF := 14.0   # m/s where steering authority bottoms out at STEER_MAX_HIGH
const STEER_SPEED := 4.0        # how fast steering eases toward target
const HANDBRAKE_FORCE := 32.0
const HANDBRAKE_TAP_S := 0.18  # space held shorter than this = toggle latched

# 90s-econobox manual. Final drive picked so each gear caps at a clearly
# different top speed: ~7, 11, 16, 22, 29 m/s (≈25 / 40 / 58 / 80 / 105 km/h).
const GEAR_RATIOS_DEFAULT: Array[float] = [3.6, 2.4, 1.7, 1.25, 0.95]
const REVERSE_RATIO := 3.6
const FINAL_DRIVE := 7.8
const WHEEL_RADIUS := 0.34
const IDLE_RPM := 700.0
const REDLINE_RPM := 6200.0
const REV_LIMITER_CUT := 6300.0   # engine_force gates above this until RPM drops back
const RPM_HARD_CAP := 6500.0      # absolute ceiling on displayed RPM, even from downshifts
const RPM_FOLLOW_RATE := 9.0      # how fast displayed RPM eases toward target each second
const NEUTRAL_REV_RATE := 14.0    # how fast RPM tracks throttle in neutral
const RPM_OFF_DECAY := 6.0        # how fast RPM falls toward 0 when engine is off
const ENGINE_BRAKE := 4.0         # brake force applied off-throttle in gear (engine drag)
const STALL_RPM := 450.0          # RPM below which an in-gear engine cuts out
const ENGINE_START_HOLD_S := 0.9  # how long N must be held to attempt a start
const ENGINE_START_SUCCESS := 0.65 # chance per attempt of catching
# Shift "bump": clutch-disengaged window after every shift where engine_force
# drops to zero and a small drag pulses through, so the driver feels the gear
# change as a momentum hiccup rather than a silent torque tweak.
const SHIFT_COOLDOWN_S := 0.45
const SHIFT_BUMP_BRAKE := 3.0

# Procedural audio constants. Engine fundamental sweeps from a low rumble at
# idle up to a higher honk at redline; the second oscillator one octave up
# adds the rasp.
const AUDIO_SAMPLE_RATE := 22050
const ENGINE_BASE_HZ := 38.0
const ENGINE_TOP_HZ := 230.0
const SHIFT_SOUND_S := 0.16
const DIE_SOUND_S := 0.75   # engine-cut splutter envelope length

const ENTER_RANGE := 4.0

# Default car layout. Variants override most of this via VARIANTS.
const SEAT_OFFSETS_DEFAULT := [
	Vector3(-0.55, 0.45, -0.25),  # driver: left front
	Vector3( 0.55, 0.45, -0.25),  # passenger front
	Vector3(-0.55, 0.45,  0.65),  # rear left
	Vector3( 0.55, 0.45,  0.65),  # rear right
]
const SEAT_LABELS_DEFAULT := ["Driver", "Front Passenger", "Rear Left", "Rear Right"]

# Driver-door eject offset (where the player gets dropped on exit).
const EJECT_OFFSET_DEFAULT := Vector3(-1.6, 0.6, -0.25)

# Per-variant tuning. Anything missing here falls back to the const default.
const VARIANTS := {
	"car": {},  # defaults; nothing to override
	"motorcycle": {
		"display_name": "Motorcycle",
		"mass": 230.0,
		"body_size": Vector3(0.45, 0.55, 2.1),
		"body_color": Color(0.10, 0.10, 0.12),
		"body_pos_y": 0.55,
		"cabin_size": Vector3(0.40, 0.55, 0.70),
		"cabin_pos": Vector3(0, 1.05, 0.30),
		"cabin_color": Color(0.15, 0.15, 0.18),
		"wheel_layout": "tandem",       # 2 inline wheels; both drive, front steers
		"wheel_radius": 0.34,
		"engine_force": 4400.0,
		"reverse_force": 1400.0,
		"brake_force": 12.0,
		"gear_ratios": [3.0, 2.1, 1.55, 1.20, 0.95, 0.78],
		"final_drive": 6.4,
		"redline_rpm": 12000.0,
		"rev_limiter_cut": 12200.0,
		"rpm_hard_cap": 12500.0,
		"idle_rpm": 1300.0,
		"stall_rpm": 850.0,
		"engine_base_hz": 60.0,
		"engine_top_hz": 380.0,
		"steer_max": 0.65,
		"steer_max_high": 0.10,
		"seat_offsets": [Vector3(0, 0.55, 0.05)],   # rider only
		"seat_labels": ["Rider"],
		"eject_offset": Vector3(-1.0, 0.5, 0.0),
		"camera_offset": Vector3(0, 1.4, -4.5),
		"angular_damp": 4.0,                         # heavy damp keeps it upright
		"arrow_color": Color(0.95, 0.20, 0.10),
	},
	"countash": {
		"display_name": "Countash",
		"mass": 1450.0,
		"body_size": Vector3(2.00, 0.45, 4.40),
		"body_color": Color(1.00, 0.85, 0.05),
		"body_pos_y": 0.45,
		"cabin_size": Vector3(1.55, 0.45, 1.55),
		"cabin_pos": Vector3(0, 0.95, -0.20),
		"cabin_color": Color(0.10, 0.12, 0.15),
		"wheel_layout": "quad_wide",
		"wheel_radius": 0.36,
		"engine_force": 5800.0,
		"reverse_force": 2400.0,
		"brake_force": 18.0,
		"gear_ratios": [2.95, 2.05, 1.45, 1.10, 0.85],
		"final_drive": 5.4,
		"redline_rpm": 7800.0,
		"rev_limiter_cut": 7900.0,
		"rpm_hard_cap": 8200.0,
		"idle_rpm": 950.0,
		"stall_rpm": 600.0,
		"engine_base_hz": 50.0,
		"engine_top_hz": 320.0,
		"steer_max": 0.45,
		"steer_max_high": 0.05,
		"seat_offsets": [
			Vector3(-0.55, 0.40, -0.30),
			Vector3( 0.55, 0.40, -0.30),
		],
		"seat_labels": ["Driver", "Front Passenger"],
		"eject_offset": Vector3(-1.7, 0.6, -0.30),
		"camera_offset": Vector3(0, 1.3, -6.5),
		"angular_damp": 1.8,
		"arrow_color": Color(0.05, 0.05, 0.05),
	},
}

@export var variant: String = "car"

# Runtime-mutable copies of the per-variant tunables. _apply_variant() fills
# these from VARIANTS[variant] before _ready builds the visuals.
var _engine_force: float = ENGINE_FORCE
var _reverse_force: float = REVERSE_FORCE
var _brake_force: float = BRAKE_FORCE
var _steer_max: float = STEER_MAX
var _steer_max_high: float = STEER_MAX_HIGH
var _gear_ratios: Array[float] = GEAR_RATIOS_DEFAULT.duplicate()
var _final_drive: float = FINAL_DRIVE
var _wheel_radius: float = WHEEL_RADIUS
var _idle_rpm: float = IDLE_RPM
var _redline_rpm: float = REDLINE_RPM
var _rev_limiter_cut: float = REV_LIMITER_CUT
var _rpm_hard_cap: float = RPM_HARD_CAP
var _stall_rpm: float = STALL_RPM
var _engine_base_hz: float = ENGINE_BASE_HZ
var _engine_top_hz: float = ENGINE_TOP_HZ
var _seat_offsets: Array = SEAT_OFFSETS_DEFAULT.duplicate()
var _seat_labels: Array = SEAT_LABELS_DEFAULT.duplicate()
var _eject_offset: Vector3 = EJECT_OFFSET_DEFAULT

var _driver: Node = null
var _seat_markers: Array = []
var _camera: Camera3D = null
var _camera_pivot: Node3D = null
var _steer: float = 0.0
var _enter_locked_until: float = 0.0  # debounce E so it doesn't enter+exit same press
var _space_press_time: float = -1.0   # -1 = not pressed; otherwise wall-clock seconds
var _handbrake_latched: bool = false  # toggled by tap-release; held independently while space down
var _gear: int = 0                    # -1 = R, 0 = N, 1.._gear_ratios.size() = forward gears
var _rpm: float = IDLE_RPM            # displayed RPM, eased toward _target_rpm each frame
var _rev_limited: bool = false        # true while the limiter is currently cutting fuel
var _shift_cooldown: float = 0.0      # seconds remaining in clutch-disengaged window
var _throttle: float = 0.0            # last frame's W input, used by the engine sound generator
# Procedural audio state.
var _engine_player: AudioStreamPlayer3D = null
var _engine_playback: AudioStreamGeneratorPlayback = null
var _engine_phase: float = 0.0
var _engine_phase2: float = 0.0
var _shift_player: AudioStreamPlayer3D = null
var _shift_playback: AudioStreamGeneratorPlayback = null
var _shift_frames_remaining: int = 0  # frames left in current shift-noise burst
var _shift_burst_total: int = 1       # frames in the burst (for envelope normalization)
# Engine on/off + start procedure.
var _engine_on: bool = false          # vehicle spawns with the engine cold
var _start_hold: float = 0.0          # how long N has been held this attempt
var _start_locked: bool = false       # true after a failed attempt until N is released
var _crank_player: AudioStreamPlayer3D = null
var _crank_playback: AudioStreamGeneratorPlayback = null
var _crank_phase: float = 0.0
var _crank_mod_phase: float = 0.0
var _crank_active: bool = false       # set in _physics_process, consumed by _fill_crank_buffer
var _die_player: AudioStreamPlayer3D = null
var _die_playback: AudioStreamGeneratorPlayback = null
var _die_phase: float = 0.0
var _die_frames_remaining: int = 0     # frames left in current die-splutter burst
var _die_burst_total: int = 1

func _ready() -> void:
	_apply_variant()
	_rpm = _idle_rpm
	add_to_group("vehicle")
	_build_body_and_visuals()
	_build_wheels()
	_build_seats()
	_build_camera()
	# Mass on the body itself drags the centre of mass too high if the
	# default sits on the cabin. Bias it down so the vehicle doesn't tip.
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.0, 0)
	# Procedural audio — engine loop + one-shot shift noise. Both use
	# AudioStreamGenerator so they pan + attenuate naturally in 3D.
	_setup_audio()

func _apply_variant() -> void:
	var cfg: Dictionary = VARIANTS.get(variant, {})
	# Driving constants
	_engine_force   = float(cfg.get("engine_force", ENGINE_FORCE))
	_reverse_force  = float(cfg.get("reverse_force", REVERSE_FORCE))
	_brake_force    = float(cfg.get("brake_force", BRAKE_FORCE))
	_steer_max      = float(cfg.get("steer_max", STEER_MAX))
	_steer_max_high = float(cfg.get("steer_max_high", STEER_MAX_HIGH))
	if cfg.has("gear_ratios"):
		var arr: Array = cfg["gear_ratios"]
		_gear_ratios = []
		for f in arr:
			_gear_ratios.append(float(f))
	_final_drive    = float(cfg.get("final_drive", FINAL_DRIVE))
	_wheel_radius   = float(cfg.get("wheel_radius", WHEEL_RADIUS))
	_idle_rpm       = float(cfg.get("idle_rpm", IDLE_RPM))
	_redline_rpm    = float(cfg.get("redline_rpm", REDLINE_RPM))
	_rev_limiter_cut = float(cfg.get("rev_limiter_cut", REV_LIMITER_CUT))
	_rpm_hard_cap   = float(cfg.get("rpm_hard_cap", RPM_HARD_CAP))
	_stall_rpm      = float(cfg.get("stall_rpm", STALL_RPM))
	_engine_base_hz = float(cfg.get("engine_base_hz", ENGINE_BASE_HZ))
	_engine_top_hz  = float(cfg.get("engine_top_hz", ENGINE_TOP_HZ))
	_eject_offset   = cfg.get("eject_offset", EJECT_OFFSET_DEFAULT)
	# Seats: copy out of cfg or use defaults
	if cfg.has("seat_offsets"):
		_seat_offsets = (cfg["seat_offsets"] as Array).duplicate()
		_seat_labels = (cfg.get("seat_labels", ["Driver"]) as Array).duplicate()
	mass = float(cfg.get("mass", 900.0))
	angular_damp = float(cfg.get("angular_damp", 1.5))

func _build_body_and_visuals() -> void:
	var cfg: Dictionary = VARIANTS.get(variant, {})
	var body_size: Vector3 = cfg.get("body_size", Vector3(1.6, 0.7, 3.4))
	var body_color: Color = cfg.get("body_color", Color(0.85, 0.18, 0.18))
	var body_y: float = float(cfg.get("body_pos_y", 0.55))
	var body_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = body_size
	body_shape.shape = box
	body_shape.position = Vector3(0, body_y, 0)
	add_child(body_shape)
	var body_mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = body_size
	body_mesh.mesh = bm
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = body_color
	body_mat.roughness = 0.4
	body_mat.metallic = 0.6
	body_mesh.material_override = body_mat
	body_mesh.position = Vector3(0, body_y, 0)
	add_child(body_mesh)
	# Cabin (smaller box on top so the silhouette reads as a vehicle).
	var cabin_size: Vector3 = cfg.get("cabin_size", Vector3(1.4, 0.6, 1.8))
	var cabin_pos: Vector3 = cfg.get("cabin_pos", Vector3(0, 1.15, 0.2))
	var cabin_color: Color = cfg.get("cabin_color", Color(0.2, 0.22, 0.28))
	var cabin := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = cabin_size
	cabin.mesh = cm
	var cabin_mat := StandardMaterial3D.new()
	cabin_mat.albedo_color = cabin_color
	cabin_mat.metallic = 0.2
	cabin_mat.roughness = 0.35
	cabin.material_override = cabin_mat
	cabin.position = cabin_pos
	add_child(cabin)
	# Roof arrow so you can spot which way the vehicle will drive from any
	# angle. Smaller/red on the bike so it doesn't dwarf the body.
	var arrow_color: Color = cfg.get("arrow_color", Color(1.0, 0.95, 0.1))
	var arrow_mat := StandardMaterial3D.new()
	arrow_mat.albedo_color = arrow_color
	arrow_mat.emission_enabled = true
	arrow_mat.emission = arrow_color
	arrow_mat.emission_energy_multiplier = 0.6
	var arrow_y: float = cabin_pos.y + cabin_size.y * 0.5 + 0.15
	var arrow_scale: float = 0.6 if variant == "motorcycle" else 1.0
	var shaft := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.35, 0.08, 1.6) * arrow_scale
	shaft.mesh = sm
	shaft.material_override = arrow_mat
	shaft.position = Vector3(0, arrow_y, -0.2 * arrow_scale)
	add_child(shaft)
	var head := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.9, 0.08, 0.7) * arrow_scale
	head.mesh = pm
	head.material_override = arrow_mat
	head.rotation = Vector3(deg_to_rad(-90.0), 0, 0)
	head.position = Vector3(0, arrow_y, -1.35 * arrow_scale)
	add_child(head)

func _build_wheels() -> void:
	var cfg: Dictionary = VARIANTS.get(variant, {})
	var layout: String = String(cfg.get("wheel_layout", "quad"))
	var specs: Array = []
	match layout:
		"tandem":
			# Two wheels inline (motorcycle). Front steers and drives, rear drives.
			# Wide-ish track stand-in (offset slightly +/-X) avoids tipping.
			specs = [
				{"pos": Vector3(0, _wheel_radius - 0.02, -0.95), "steer": true,  "drive": true},
				{"pos": Vector3(0, _wheel_radius - 0.02,  0.95), "steer": false, "drive": true},
			]
		"quad_wide":
			specs = [
				{"pos": Vector3(-0.95, _wheel_radius - 0.02, -1.55), "steer": true,  "drive": false},
				{"pos": Vector3( 0.95, _wheel_radius - 0.02, -1.55), "steer": true,  "drive": false},
				{"pos": Vector3(-0.95, _wheel_radius - 0.02,  1.55), "steer": false, "drive": true},
				{"pos": Vector3( 0.95, _wheel_radius - 0.02,  1.55), "steer": false, "drive": true},
			]
		_:
			specs = [
				{"pos": Vector3(-0.78, _wheel_radius - 0.02, -1.25), "steer": true,  "drive": false},
				{"pos": Vector3( 0.78, _wheel_radius - 0.02, -1.25), "steer": true,  "drive": false},
				{"pos": Vector3(-0.78, _wheel_radius - 0.02,  1.25), "steer": false, "drive": true},
				{"pos": Vector3( 0.78, _wheel_radius - 0.02,  1.25), "steer": false, "drive": true},
			]
	for spec in specs:
		var w := VehicleWheel3D.new()
		w.position = spec["pos"]
		w.use_as_steering = spec["steer"]
		w.use_as_traction = spec["drive"]
		w.wheel_radius = _wheel_radius
		w.wheel_friction_slip = 5.0
		w.suspension_stiffness = 48.0
		w.suspension_max_force = 8000.0
		w.damping_compression = 0.7
		w.damping_relaxation = 0.7
		var wm := MeshInstance3D.new()
		var wmesh := CylinderMesh.new()
		wmesh.top_radius = _wheel_radius
		wmesh.bottom_radius = _wheel_radius
		wmesh.height = 0.22
		wm.mesh = wmesh
		wm.rotation = Vector3(0, 0, PI / 2.0)
		var wmat := StandardMaterial3D.new()
		wmat.albedo_color = Color(0.08, 0.08, 0.08)
		wmat.roughness = 0.95
		wm.material_override = wmat
		w.add_child(wm)
		add_child(w)

func _build_seats() -> void:
	for i in range(_seat_offsets.size()):
		var marker := Node3D.new()
		var lbl: String = String(_seat_labels[i]) if i < _seat_labels.size() else ("Seat_%d" % i)
		marker.name = "Seat_%s" % lbl.replace(" ", "")
		marker.position = _seat_offsets[i]
		add_child(marker)
		_seat_markers.append(marker)

func _build_camera() -> void:
	var cfg: Dictionary = VARIANTS.get(variant, {})
	var cam_offset: Vector3 = cfg.get("camera_offset", Vector3(0, 1.4, -5.5))
	_camera_pivot = Node3D.new()
	_camera_pivot.position = Vector3(0, 1.6, -0.2)
	add_child(_camera_pivot)
	_camera = Camera3D.new()
	_camera.position = cam_offset
	_camera.rotation = Vector3(deg_to_rad(-12.0), 0, 0)
	_camera.fov = 70.0
	_camera_pivot.add_child(_camera)

func _setup_audio() -> void:
	_engine_player = AudioStreamPlayer3D.new()
	var eg := AudioStreamGenerator.new()
	eg.mix_rate = AUDIO_SAMPLE_RATE
	eg.buffer_length = 0.10
	_engine_player.stream = eg
	_engine_player.volume_db = -6.0
	_engine_player.unit_size = 8.0
	_engine_player.max_distance = 60.0
	add_child(_engine_player)
	_engine_player.play()
	_engine_playback = _engine_player.get_stream_playback()
	_shift_player = AudioStreamPlayer3D.new()
	var sg := AudioStreamGenerator.new()
	sg.mix_rate = AUDIO_SAMPLE_RATE
	sg.buffer_length = 0.20
	_shift_player.stream = sg
	_shift_player.volume_db = -4.0
	_shift_player.unit_size = 6.0
	_shift_player.max_distance = 40.0
	add_child(_shift_player)
	_shift_player.play()
	_shift_playback = _shift_player.get_stream_playback()
	_crank_player = AudioStreamPlayer3D.new()
	var cg := AudioStreamGenerator.new()
	cg.mix_rate = AUDIO_SAMPLE_RATE
	cg.buffer_length = 0.10
	_crank_player.stream = cg
	_crank_player.volume_db = -3.0
	_crank_player.unit_size = 7.0
	_crank_player.max_distance = 50.0
	add_child(_crank_player)
	_crank_player.play()
	_crank_playback = _crank_player.get_stream_playback()
	_die_player = AudioStreamPlayer3D.new()
	var dg := AudioStreamGenerator.new()
	dg.mix_rate = AUDIO_SAMPLE_RATE
	dg.buffer_length = 0.10
	_die_player.stream = dg
	_die_player.volume_db = -3.0
	_die_player.unit_size = 7.0
	_die_player.max_distance = 50.0
	add_child(_die_player)
	_die_player.play()
	_die_playback = _die_player.get_stream_playback()

func _physics_process(delta: float) -> void:
	# Driver input drives engine + steering. Brake is applied to all
	# wheels via the VehicleBody3D `brake` property.
	if _driver != null:
		# Park the driver at the seat marker each tick so the in-car first-person
		# camera (player camera) tracks the vehicle instead of staying world-static.
		if _driver is Node3D and not _seat_markers.is_empty():
			(_driver as Node3D).global_transform = (_seat_markers[0] as Node3D).global_transform
		# Gear shifts (edge-triggered). Guarded by the same enter-debounce so the
		# E press that seated the player doesn't immediately shift to gear 2.
		var unlocked: bool = Time.get_ticks_msec() / 1000.0 >= _enter_locked_until
		if unlocked and Input.is_action_just_pressed("interact"):
			_shift_up()
		if unlocked and Input.is_action_just_pressed("vehicle_shift_down"):
			_shift_down()
		var fwd: float = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
		var steer_in: float = Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
		_throttle = clampf(fwd, 0.0, 1.0)
		# Engine start procedure. Hold N for ENGINE_START_HOLD_S; one chance to
		# catch per press. Failed attempts lock out until release.
		_crank_active = false
		if _engine_on:
			_start_hold = 0.0
			_start_locked = false
		else:
			if Input.is_action_just_pressed("vehicle_restart"):
				_start_hold = 0.0
				_start_locked = false
			if Input.is_action_pressed("vehicle_restart"):
				if not _start_locked:
					_start_hold += delta
					_crank_active = true
					if _start_hold >= ENGINE_START_HOLD_S:
						if randf() < ENGINE_START_SUCCESS:
							_engine_on = true
							_rpm = _idle_rpm
							_start_hold = 0.0
						else:
							_start_locked = true
			else:
				_start_hold = 0.0
				_start_locked = false
		var target_engine: float = 0.0
		var target_brake: float = PASSIVE_BRAKE
		# Compute current RPM. Three paths:
		#  - engine off: RPM falls to 0 (gauge dead)
		#  - neutral: engine free-revs to throttle position
		#  - in gear (incl. reverse): RPM follows wheel speed * ratio * final drive
		var local_v: Vector3 = global_transform.basis.transposed() * linear_velocity
		var fwd_speed: float = local_v.z
		var wheel_rps: float = absf(fwd_speed) / (TAU * _wheel_radius)
		var ratio: float = _current_ratio()
		var target_rpm: float
		if not _engine_on:
			_rpm = lerpf(_rpm, 0.0, 1.0 - exp(-RPM_OFF_DECAY * delta))
		elif _gear == 0:
			target_rpm = lerpf(_idle_rpm, _redline_rpm * 0.95, _throttle)
			var na: float = 1.0 - exp(-NEUTRAL_REV_RATE * delta)
			_rpm = lerpf(_rpm, target_rpm, na)
		else:
			target_rpm = wheel_rps * 60.0 * absf(ratio) * _final_drive
			if absf(fwd_speed) < 0.8:
				target_rpm = max(target_rpm, _idle_rpm)
			if fwd > 0.0:
				target_rpm = max(target_rpm, _idle_rpm + (_redline_rpm - _idle_rpm) * 0.18 * fwd)
			target_rpm = min(target_rpm, _rpm_hard_cap)
			var rate: float = RPM_FOLLOW_RATE if target_rpm > _rpm else RPM_FOLLOW_RATE * 2.0
			_rpm = lerpf(_rpm, target_rpm, 1.0 - exp(-rate * delta))
		_rev_limited = _engine_on and _rpm >= _rev_limiter_cut
		if _engine_on and _gear != 0 and _throttle <= 0.0 and _rpm < _stall_rpm:
			_engine_on = false
			_trigger_die_sound()
		var torque_mult: float = absf(ratio) / _gear_ratios[0]
		if _shift_cooldown > 0.0:
			_shift_cooldown -= delta
			target_engine = 0.0
			target_brake = max(target_brake, SHIFT_BUMP_BRAKE)
		elif not _engine_on:
			target_engine = 0.0
			target_brake = PASSIVE_BRAKE * 0.4
		elif _gear == 0:
			target_engine = 0.0
		elif _gear == -1:
			if fwd > 0.0 and not _rev_limited:
				target_engine = _reverse_force * fwd
				target_brake = 0.0
			elif fwd <= 0.0:
				target_brake = max(target_brake, ENGINE_BRAKE * 0.6)
		elif fwd > 0.0 and not _rev_limited:
			target_engine = -_engine_force * fwd * torque_mult
			target_brake = 0.0
		else:
			target_brake = max(target_brake, ENGINE_BRAKE * torque_mult)
		if fwd < 0.0:
			target_brake = max(target_brake, _brake_force * absf(fwd))
		var now_s: float = Time.get_ticks_msec() / 1000.0
		if Input.is_action_just_pressed("jump"):
			_space_press_time = now_s
		if Input.is_action_just_released("jump"):
			if _space_press_time >= 0.0 and (now_s - _space_press_time) < HANDBRAKE_TAP_S:
				_handbrake_latched = not _handbrake_latched
			_space_press_time = -1.0
		var handbrake_on: bool = _handbrake_latched or Input.is_action_pressed("jump")
		if handbrake_on:
			target_brake = max(target_brake, HANDBRAKE_FORCE)
			target_engine = 0.0
		engine_force = target_engine
		brake = target_brake
		var speed_mag: float = linear_velocity.length()
		var speed_t: float = clampf(speed_mag / STEER_SPEED_REF, 0.0, 1.0)
		var max_steer: float = lerpf(_steer_max, _steer_max_high, speed_t)
		var alpha: float = 1.0 - exp(-STEER_SPEED * delta)
		_steer = lerpf(_steer, steer_in * max_steer, alpha)
		steering = _steer
	else:
		engine_force = 0.0
		brake = PASSIVE_BRAKE
		_steer = lerpf(_steer, 0.0, 1.0 - exp(-STEER_SPEED * delta))
		steering = _steer
		_throttle = 0.0
		_crank_active = false
		var passive_target: float = _idle_rpm if _engine_on else 0.0
		var passive_rate: float = RPM_FOLLOW_RATE if _engine_on else RPM_OFF_DECAY
		_rpm = lerpf(_rpm, passive_target, 1.0 - exp(-passive_rate * delta))

func _process(_delta: float) -> void:
	if _driver != null and Input.is_action_just_pressed("vehicle_exit"):
		if Time.get_ticks_msec() / 1000.0 >= _enter_locked_until:
			exit_driver()
	_fill_engine_buffer()
	_fill_shift_buffer()
	_fill_crank_buffer()
	_fill_die_buffer()

func _fill_engine_buffer() -> void:
	if _engine_playback == null:
		return
	var rpm_t: float = clampf(_rpm / _redline_rpm, 0.0, 1.2)
	var freq: float = lerpf(_engine_base_hz, _engine_top_hz, rpm_t)
	var omega: float = TAU * freq / float(AUDIO_SAMPLE_RATE)
	var omega2: float = omega * 2.0
	var amp: float = 0.0
	if _engine_on:
		amp = 0.10 + 0.16 * rpm_t + 0.08 * _throttle
	var frames: int = _engine_playback.get_frames_available()
	for i in range(frames):
		_engine_phase += omega
		_engine_phase2 += omega2
		if _engine_phase > TAU:
			_engine_phase -= TAU
		if _engine_phase2 > TAU:
			_engine_phase2 -= TAU
		var saw1: float = (_engine_phase / PI) - 1.0
		var saw2: float = (_engine_phase2 / PI) - 1.0
		var s: float = (saw1 * 0.7 + saw2 * 0.3) * amp
		_engine_playback.push_frame(Vector2(s, s))

func _fill_shift_buffer() -> void:
	if _shift_playback == null:
		return
	var frames: int = _shift_playback.get_frames_available()
	for i in range(frames):
		var s: float = 0.0
		if _shift_frames_remaining > 0:
			var t: float = 1.0 - (float(_shift_frames_remaining) / float(_shift_burst_total))
			var env: float = exp(-t * 6.0)
			var noise: float = randf() * 2.0 - 1.0
			var rumble: float = sin(t * TAU * 40.0 * SHIFT_SOUND_S)
			s = (noise * 0.5 + rumble * 0.5) * env * 0.35
			_shift_frames_remaining -= 1
		_shift_playback.push_frame(Vector2(s, s))

func _trigger_shift_sound() -> void:
	_shift_burst_total = int(float(AUDIO_SAMPLE_RATE) * SHIFT_SOUND_S)
	_shift_frames_remaining = _shift_burst_total

func _fill_crank_buffer() -> void:
	if _crank_playback == null:
		return
	var freq: float = 55.0
	var mod_freq: float = 4.0
	var d_phase: float = TAU * freq / float(AUDIO_SAMPLE_RATE)
	var d_mod: float = TAU * mod_freq / float(AUDIO_SAMPLE_RATE)
	var amp: float = 0.30 if _crank_active else 0.0
	var frames: int = _crank_playback.get_frames_available()
	for i in range(frames):
		var s: float = 0.0
		if amp > 0.0:
			_crank_phase += d_phase
			_crank_mod_phase += d_mod
			if _crank_phase > TAU:
				_crank_phase -= TAU
			if _crank_mod_phase > TAU:
				_crank_mod_phase -= TAU
			var sq: float = 1.0 if sin(_crank_phase) > 0.0 else -1.0
			var env: float = (sin(_crank_mod_phase) + 1.0) * 0.5
			var noise: float = randf() * 2.0 - 1.0
			s = (sq * 0.65 + noise * 0.35) * env * amp
		_crank_playback.push_frame(Vector2(s, s))

func _trigger_die_sound() -> void:
	_die_burst_total = int(float(AUDIO_SAMPLE_RATE) * DIE_SOUND_S)
	_die_frames_remaining = _die_burst_total
	_die_phase = 0.0

func _fill_die_buffer() -> void:
	if _die_playback == null:
		return
	var frames: int = _die_playback.get_frames_available()
	for i in range(frames):
		var s: float = 0.0
		if _die_frames_remaining > 0:
			var t: float = 1.0 - (float(_die_frames_remaining) / float(_die_burst_total))
			var freq: float = lerpf(80.0, 25.0, t)
			var d_phase: float = TAU * freq / float(AUDIO_SAMPLE_RATE)
			_die_phase += d_phase
			if _die_phase > TAU:
				_die_phase -= TAU
			var sq: float = 1.0 if sin(_die_phase) > 0.0 else -1.0
			var noise: float = randf() * 2.0 - 1.0
			var coughs: float = 0.5 + 0.5 * sin(t * TAU * 3.0)
			var env: float = exp(-t * 2.5) * coughs
			s = (sq * 0.55 + noise * 0.45) * env * 0.45
			_die_frames_remaining -= 1
		_die_playback.push_frame(Vector2(s, s))

func toggle_camera() -> void:
	if _driver == null:
		return
	var pcam: Camera3D = _find_camera(_driver)
	if _camera.current:
		if pcam != null:
			pcam.current = true
		_camera.current = false
	else:
		_camera.current = true

func is_driver_seat_open() -> bool:
	return _driver == null

func get_rpm() -> float:
	return _rpm

func get_gear() -> int:
	return _gear

func get_gear_count() -> int:
	return _gear_ratios.size()

func get_gear_label() -> String:
	if _gear == -1:
		return "R"
	if _gear == 0:
		return "N"
	return str(_gear)

func get_redline() -> float:
	return _redline_rpm

func is_rev_limited() -> bool:
	return _rev_limited

func is_engine_on() -> bool:
	return _engine_on

func get_start_progress() -> float:
	if _engine_on or _start_hold <= 0.0:
		return -1.0
	return clampf(_start_hold / ENGINE_START_HOLD_S, 0.0, 1.0)

func _shift_up() -> void:
	if _gear < _gear_ratios.size():
		_gear += 1
		_shift_cooldown = SHIFT_COOLDOWN_S
		_trigger_shift_sound()

func _shift_down() -> void:
	if _gear > -1:
		_gear -= 1
		_shift_cooldown = SHIFT_COOLDOWN_S
		_trigger_shift_sound()

func _current_ratio() -> float:
	if _gear == 0:
		return 0.0
	if _gear == -1:
		return -REVERSE_RATIO
	return _gear_ratios[_gear - 1]

func driver_seat_world() -> Vector3:
	if _seat_markers.is_empty():
		return global_position
	return (_seat_markers[0] as Node3D).global_position

func try_enter_driver(player: Node) -> bool:
	if _driver != null or player == null:
		return false
	if player.global_position.distance_to(driver_seat_world()) > ENTER_RANGE:
		return false
	_driver = player
	if player.has_method("set_in_vehicle"):
		player.set_in_vehicle(self)
	player.global_transform = (_seat_markers[0] as Node3D).global_transform
	if player.has_method("reset_physics_interpolation"):
		player.reset_physics_interpolation()
	_camera.current = true
	_enter_locked_until = Time.get_ticks_msec() / 1000.0 + 0.3
	return true

func exit_driver() -> void:
	if _driver == null:
		return
	var player: Node = _driver
	_driver = null
	if player is Node3D:
		var eject_world: Vector3 = global_transform * _eject_offset
		(player as Node3D).global_position = eject_world
		(player as Node3D).reset_physics_interpolation()
	if player.has_method("set_in_vehicle"):
		player.set_in_vehicle(null)
	var pcam: Camera3D = _find_camera(player)
	if pcam != null:
		pcam.current = true
	_camera.current = false
	engine_force = 0.0
	brake = _brake_force
	_steer = 0.0
	steering = 0.0
	_handbrake_latched = false
	_space_press_time = -1.0
	_gear = 0
	_rpm = _idle_rpm
	_rev_limited = false
	_shift_cooldown = 0.0
	_enter_locked_until = Time.get_ticks_msec() / 1000.0 + 0.3

func _find_camera(n: Node) -> Camera3D:
	if n is Camera3D:
		return n
	for c in n.get_children():
		var found: Camera3D = _find_camera(c)
		if found != null:
			return found
	return null
