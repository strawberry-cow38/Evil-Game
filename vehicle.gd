extends VehicleBody3D

# Drivable car with 4 seats (driver + 3 passengers). Built entirely
# programmatically so it has no scene-file dependency — the play scene
# just adds an instance and gives it a position.
#
# Controls (driver only):
#   move_forward / move_back  — accelerate / brake-reverse
#   move_left / move_right    — steer
#   E                         — exit vehicle
#
# Player hand-off avoids reparenting (CharacterBody3D doesn't like
# riding inside another physics body). On enter we disable the player's
# script processing, hide its mesh, and switch the active camera to
# the vehicle's chase camera. On exit we pop the player out next to
# the driver door at the vehicle's current world position.

const ENGINE_FORCE := 2400.0
const REVERSE_FORCE := 1200.0
const BRAKE_FORCE := 14.0
const PASSIVE_BRAKE := 0.6   # mild drag when no input so the car coasts to a stop
const STEER_MAX := 0.55         # max wheel steer angle (radians) at low speed
const STEER_MAX_HIGH := 0.10    # max steer angle once cruising fast — prevents tip-overs
const STEER_SPEED_REF := 18.0   # m/s where steering authority bottoms out at STEER_MAX_HIGH
const STEER_SPEED := 4.0        # how fast steering eases toward target
const HANDBRAKE_FORCE := 32.0
const HANDBRAKE_TAP_S := 0.18  # space held shorter than this = toggle latched

# 90s-econobox manual. Final drive picked so each gear caps at a clearly
# different top speed: ~7, 11, 16, 22, 29 m/s (≈25 / 40 / 58 / 80 / 105 km/h).
const GEAR_RATIOS: Array[float] = [3.6, 2.4, 1.7, 1.25, 0.95]
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

const ENTER_RANGE := 4.0

# Local-space seat positions (relative to car body origin).
const SEAT_OFFSETS := [
	Vector3(-0.55, 0.45, -0.25),  # driver: left front
	Vector3( 0.55, 0.45, -0.25),  # passenger front
	Vector3(-0.55, 0.45,  0.65),  # rear left
	Vector3( 0.55, 0.45,  0.65),  # rear right
]
const SEAT_LABELS := ["Driver", "Front Passenger", "Rear Left", "Rear Right"]

# Driver-door eject offset (where the player gets dropped on exit).
const EJECT_OFFSET := Vector3(-1.6, 0.6, -0.25)

var _driver: Node = null
var _seat_markers: Array = []
var _camera: Camera3D = null
var _camera_pivot: Node3D = null
var _steer: float = 0.0
var _enter_locked_until: float = 0.0  # debounce E so it doesn't enter+exit same press
var _space_press_time: float = -1.0   # -1 = not pressed; otherwise wall-clock seconds
var _handbrake_latched: bool = false  # toggled by tap-release; held independently while space down
var _gear: int = 0                    # -1 = R, 0 = N, 1..GEAR_RATIOS.size() = forward gears
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
var _engine_on: bool = false          # car spawns with the engine cold
var _start_hold: float = 0.0          # how long N has been held this attempt
var _start_locked: bool = false       # true after a failed attempt until N is released
var _crank_player: AudioStreamPlayer3D = null
var _crank_playback: AudioStreamGeneratorPlayback = null
var _crank_phase: float = 0.0
var _crank_mod_phase: float = 0.0
var _crank_active: bool = false       # set in _physics_process, consumed by _fill_crank_buffer

func _ready() -> void:
	mass = 900.0
	add_to_group("vehicle")
	# --- body collision + visual ---------------------------------------
	var body_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 0.7, 3.4)
	body_shape.shape = box
	body_shape.position = Vector3(0, 0.55, 0)
	add_child(body_shape)
	var body_mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.6, 0.7, 3.4)
	body_mesh.mesh = bm
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.85, 0.18, 0.18)
	body_mat.roughness = 0.4
	body_mat.metallic = 0.6
	body_mesh.material_override = body_mat
	body_mesh.position = Vector3(0, 0.55, 0)
	add_child(body_mesh)
	# Cabin (smaller box on top so the car reads as a car, not a brick).
	var cabin := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(1.4, 0.6, 1.8)
	cabin.mesh = cm
	var cabin_mat := StandardMaterial3D.new()
	cabin_mat.albedo_color = Color(0.2, 0.22, 0.28)
	cabin_mat.metallic = 0.2
	cabin_mat.roughness = 0.35
	cabin.material_override = cabin_mat
	cabin.position = Vector3(0, 1.15, 0.2)
	add_child(cabin)
	# --- big forward arrow on the roof --------------------------------
	# Shaft (long box) + head (prism via PrismMesh) so you can spot which way
	# the car will drive from any angle.
	var arrow_mat := StandardMaterial3D.new()
	arrow_mat.albedo_color = Color(1.0, 0.95, 0.1)
	arrow_mat.emission_enabled = true
	arrow_mat.emission = Color(1.0, 0.85, 0.0)
	arrow_mat.emission_energy_multiplier = 0.6
	var shaft := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.35, 0.08, 1.6)
	shaft.mesh = sm
	shaft.material_override = arrow_mat
	# Forward in Godot is -Z. Roof sits ~1.45y; centre shaft slightly behind so
	# the head pokes past the front of the cabin.
	shaft.position = Vector3(0, 1.55, -0.2)
	add_child(shaft)
	var head := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.9, 0.08, 0.7)
	head.mesh = pm
	head.material_override = arrow_mat
	# PrismMesh tip points along +Y by default; rotate so tip points -Z (forward).
	head.rotation = Vector3(deg_to_rad(-90.0), 0, 0)
	head.position = Vector3(0, 1.55, -1.35)
	add_child(head)
	# --- wheels --------------------------------------------------------
	# Layout: front-left, front-right, rear-left, rear-right.
	var wheel_specs: Array = [
		{"pos": Vector3(-0.78, 0.32,-1.25), "steer": true,  "drive": false},
		{"pos": Vector3( 0.78, 0.32,-1.25), "steer": true,  "drive": false},
		{"pos": Vector3(-0.78, 0.32, 1.25), "steer": false, "drive": true},
		{"pos": Vector3( 0.78, 0.32, 1.25), "steer": false, "drive": true},
	]
	for spec in wheel_specs:
		var w := VehicleWheel3D.new()
		w.position = spec["pos"]
		w.use_as_steering = spec["steer"]
		w.use_as_traction = spec["drive"]
		w.wheel_radius = 0.34
		w.wheel_friction_slip = 5.0
		w.suspension_stiffness = 48.0
		w.suspension_max_force = 8000.0
		w.damping_compression = 0.7
		w.damping_relaxation = 0.7
		var wm := MeshInstance3D.new()
		var wmesh := CylinderMesh.new()
		wmesh.top_radius = 0.34
		wmesh.bottom_radius = 0.34
		wmesh.height = 0.22
		wm.mesh = wmesh
		wm.rotation = Vector3(0, 0, PI / 2.0)  # cylinder default Y-up → roll on Z axis
		var wmat := StandardMaterial3D.new()
		wmat.albedo_color = Color(0.08, 0.08, 0.08)
		wmat.roughness = 0.95
		wm.material_override = wmat
		w.add_child(wm)
		add_child(w)
	# --- seats ---------------------------------------------------------
	for i in range(SEAT_OFFSETS.size()):
		var marker := Node3D.new()
		marker.name = "Seat_%s" % SEAT_LABELS[i].replace(" ", "")
		marker.position = SEAT_OFFSETS[i]
		add_child(marker)
		_seat_markers.append(marker)
	# --- camera (third-person chase) ----------------------------------
	# Pivot rides with the car body; camera is offset back+up. Only made
	# current when a player enters the driver seat.
	_camera_pivot = Node3D.new()
	_camera_pivot.position = Vector3(0, 1.6, -0.2)
	add_child(_camera_pivot)
	_camera = Camera3D.new()
	# Chase cam sits on the +Z side now (the side W drives away from), so the
	# driver looks toward -Z motion direction with the car ahead of them.
	_camera.position = Vector3(0, 1.4, -5.5)
	_camera.rotation = Vector3(deg_to_rad(-12.0), 0, 0)
	_camera.fov = 70.0
	_camera_pivot.add_child(_camera)
	# Mass on the body itself drags the centre of mass too high if the
	# default sits on the cabin. Bias it down so the car doesn't tip.
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.0, 0)
	# Damp body roll/yaw oscillations so the car settles after sharp turns
	# instead of fishtailing forever (but not too hard — the user wants some
	# visible body roll for character).
	angular_damp = 2.5
	# Procedural audio — engine loop + one-shot shift noise. Both use
	# AudioStreamGenerator so they pan + attenuate naturally in 3D.
	_setup_audio()

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

func _physics_process(delta: float) -> void:
	# Driver input drives engine + steering. Brake is applied to all
	# wheels via the VehicleBody3D `brake` property.
	if _driver != null:
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
							_rpm = IDLE_RPM
							_start_hold = 0.0
						else:
							_start_locked = true   # need to release & retry
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
		var wheel_rps: float = absf(fwd_speed) / (TAU * WHEEL_RADIUS)
		var ratio: float = _current_ratio()
		var target_rpm: float
		if not _engine_on:
			_rpm = lerpf(_rpm, 0.0, 1.0 - exp(-RPM_OFF_DECAY * delta))
		elif _gear == 0:
			# Neutral: throttle directly drives RPM. Faster follow rate so the
			# engine "barks" when blipped, and falls back fast when released.
			target_rpm = lerpf(IDLE_RPM, REDLINE_RPM * 0.95, _throttle)
			var na: float = 1.0 - exp(-NEUTRAL_REV_RATE * delta)
			_rpm = lerpf(_rpm, target_rpm, na)
		else:
			target_rpm = wheel_rps * 60.0 * absf(ratio) * FINAL_DRIVE
			# Idle controller only props RPM up to idle while the throttle is
			# touched. Off-throttle the engine is allowed to bog below idle
			# (and stall) instead of pretending it can hold 700 with no fuel.
			if fwd > 0.0:
				target_rpm = max(target_rpm, IDLE_RPM + (REDLINE_RPM - IDLE_RPM) * 0.18 * fwd)
			# Hard cap so a downshift from 5th to 1st can't paint 14k on the gauge.
			target_rpm = min(target_rpm, RPM_HARD_CAP)
			# Asymmetric follow: rises at the standard rate, falls faster so
			# letting off the gas drops the needle quickly toward idle.
			var rate: float = RPM_FOLLOW_RATE if target_rpm > _rpm else RPM_FOLLOW_RATE * 2.0
			_rpm = lerpf(_rpm, target_rpm, 1.0 - exp(-rate * delta))
		_rev_limited = _engine_on and _rpm >= REV_LIMITER_CUT
		# Stall: in-gear, off-throttle, RPM dropped below idle (engine couldn't
		# sustain itself). Neutral never stalls — engine spins free.
		if _engine_on and _gear != 0 and _throttle <= 0.0 and _rpm < STALL_RPM:
			_engine_on = false
		# Torque magnitude scales by ratio relative to first gear. Reverse gets
		# its own dedicated force constant, sign-flipped vs the +Z forward
		# convention so it pushes the car -Z.
		var torque_mult: float = absf(ratio) / GEAR_RATIOS[0]
		# Shift cooldown: clutch is "in", no power reaches the wheels and a small
		# drag bleeds momentum so the driver feels the gear change.
		if _shift_cooldown > 0.0:
			_shift_cooldown -= delta
			target_engine = 0.0
			target_brake = max(target_brake, SHIFT_BUMP_BRAKE)
		elif not _engine_on:
			# Coast — no torque, very mild rolling resistance only.
			target_engine = 0.0
			target_brake = PASSIVE_BRAKE * 0.4
		elif _gear == 0:
			# Neutral: no engine force at the wheels regardless of throttle.
			target_engine = 0.0
		elif _gear == -1:
			# Reverse: W accelerates backward, S brakes (no auto-direction flip).
			if fwd > 0.0 and not _rev_limited:
				target_engine = REVERSE_FORCE * fwd
				target_brake = 0.0
			elif fwd <= 0.0:
				# Engine braking off-throttle, scales with reverse ratio (low).
				target_brake = max(target_brake, ENGINE_BRAKE * 0.6)
		elif fwd > 0.0 and not _rev_limited:
			target_engine = -ENGINE_FORCE * fwd * torque_mult
			target_brake = 0.0
		else:
			# In a forward gear, off throttle: engine drag bleeds wheel speed
			# (and hence RPM) so the gauge falls naturally. Lower gears brake
			# harder — that's where engine braking is most felt in real cars.
			target_brake = max(target_brake, ENGINE_BRAKE * torque_mult)
		# S is now a brake-only input — no automatic reverse, the player must
		# shift to R to back up. Brake strength scales with how hard S is held.
		if fwd < 0.0:
			target_brake = max(target_brake, BRAKE_FORCE * absf(fwd))
		# Handbrake: tap space toggles latched on/off, hold space forces it on
		# while held regardless of latched state.
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
		# Steering eases toward target so the wheels don't snap, and the max
		# wheel angle shrinks with speed so the car can't be flicked into a
		# barrel-roll on the highway.
		var speed_mag: float = linear_velocity.length()
		var speed_t: float = clampf(speed_mag / STEER_SPEED_REF, 0.0, 1.0)
		var max_steer: float = lerpf(STEER_MAX, STEER_MAX_HIGH, speed_t)
		var alpha: float = 1.0 - exp(-STEER_SPEED * delta)
		_steer = lerpf(_steer, steer_in * max_steer, alpha)
		steering = _steer
	else:
		# Passive: no throttle, light drag so the car settles.
		engine_force = 0.0
		brake = PASSIVE_BRAKE
		_steer = lerpf(_steer, 0.0, 1.0 - exp(-STEER_SPEED * delta))
		steering = _steer
		_throttle = 0.0
		_crank_active = false
		# Engine RPM follows whether it's running: idle if on, decay to 0 if off.
		var passive_target: float = IDLE_RPM if _engine_on else 0.0
		var passive_rate: float = RPM_FOLLOW_RATE if _engine_on else RPM_OFF_DECAY
		_rpm = lerpf(_rpm, passive_target, 1.0 - exp(-passive_rate * delta))

func _process(_delta: float) -> void:
	# F to exit (E is shift-up while seated). Entering is handled by player.gd.
	if _driver != null and Input.is_action_just_pressed("vehicle_exit"):
		if Time.get_ticks_msec() / 1000.0 >= _enter_locked_until:
			exit_driver()
	_fill_engine_buffer()
	_fill_shift_buffer()
	_fill_crank_buffer()

func _fill_engine_buffer() -> void:
	if _engine_playback == null:
		return
	# Frequency rises linearly with RPM. Two oscillators (fundamental + octave)
	# layered for a fuller tone; throttle adds a touch more amplitude on top of
	# the RPM-driven base.
	var rpm_t: float = clampf(_rpm / REDLINE_RPM, 0.0, 1.2)
	var freq: float = lerpf(ENGINE_BASE_HZ, ENGINE_TOP_HZ, rpm_t)
	var omega: float = TAU * freq / float(AUDIO_SAMPLE_RATE)
	var omega2: float = omega * 2.0
	# Idle hum is always present while the engine is running. When off the
	# generator goes silent (no rumble) so the car reads as dead.
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
		# Sawtooth scaled to [-1, 1]. Octave layered for rasp.
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
			# t goes 0 → 1 across the burst; envelope decays exponentially so the
			# noise reads as a percussive "thunk" rather than a flat hiss.
			var t: float = 1.0 - (float(_shift_frames_remaining) / float(_shift_burst_total))
			var env: float = exp(-t * 6.0)
			var noise: float = randf() * 2.0 - 1.0
			# Mix in a low rumble component (40Hz sine) so it has body, not just hiss.
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
	# Cranking sound = a deep ~60Hz square wave amplitude-modulated at 4Hz so
	# it pulses like a starter motor, plus some grit from layered noise. Goes
	# silent when not cranking.
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

func is_driver_seat_open() -> bool:
	return _driver == null

func get_rpm() -> float:
	return _rpm

func get_gear() -> int:
	return _gear

func get_gear_count() -> int:
	return GEAR_RATIOS.size()

# "R", "N", or "1".."5" for HUD display.
func get_gear_label() -> String:
	if _gear == -1:
		return "R"
	if _gear == 0:
		return "N"
	return str(_gear)

func get_redline() -> float:
	return REDLINE_RPM

func is_rev_limited() -> bool:
	return _rev_limited

func is_engine_on() -> bool:
	return _engine_on

# 0..1 progress through the current N-hold start attempt. -1 if no attempt
# is active or the engine is already running.
func get_start_progress() -> float:
	if _engine_on or _start_hold <= 0.0:
		return -1.0
	return clampf(_start_hold / ENGINE_START_HOLD_S, 0.0, 1.0)

func _shift_up() -> void:
	if _gear < GEAR_RATIOS.size():
		_gear += 1
		_shift_cooldown = SHIFT_COOLDOWN_S
		_trigger_shift_sound()

func _shift_down() -> void:
	if _gear > -1:
		_gear -= 1
		_shift_cooldown = SHIFT_COOLDOWN_S
		_trigger_shift_sound()

# Active gear ratio — magnitude is what RPM and torque math care about; sign is
# used by the engine_force branch to point reverse the right way.
func _current_ratio() -> float:
	if _gear == 0:
		return 0.0
	if _gear == -1:
		return -REVERSE_RATIO
	return GEAR_RATIOS[_gear - 1]

func driver_seat_world() -> Vector3:
	if _seat_markers.is_empty():
		return global_position
	return (_seat_markers[0] as Node3D).global_position

# Tries to seat `player` in the driver seat. Returns true on success.
func try_enter_driver(player: Node) -> bool:
	if _driver != null or player == null:
		return false
	if player.global_position.distance_to(driver_seat_world()) > ENTER_RANGE:
		return false
	_driver = player
	if player.has_method("set_in_vehicle"):
		player.set_in_vehicle(self)
	# Visually park the player at the driver seat marker so anyone
	# looking from outside sees the body in the car.
	player.global_transform = (_seat_markers[0] as Node3D).global_transform
	# Switch active camera to the vehicle chase cam.
	_camera.current = true
	# Debounce so the same E press that triggered entry doesn't immediately exit.
	_enter_locked_until = Time.get_ticks_msec() / 1000.0 + 0.3
	return true

func exit_driver() -> void:
	if _driver == null:
		return
	var player: Node = _driver
	_driver = null
	# Drop the player just off the driver door.
	if player is Node3D:
		var eject_world: Vector3 = global_transform * EJECT_OFFSET
		(player as Node3D).global_position = eject_world
	if player.has_method("set_in_vehicle"):
		player.set_in_vehicle(null)
	# Restore the player camera by walking the player tree for a Camera3D.
	var pcam: Camera3D = _find_camera(player)
	if pcam != null:
		pcam.current = true
	_camera.current = false
	engine_force = 0.0
	brake = BRAKE_FORCE
	_steer = 0.0
	steering = 0.0
	_handbrake_latched = false
	_space_press_time = -1.0
	_gear = 0
	_rpm = IDLE_RPM
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
