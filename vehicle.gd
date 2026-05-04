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

const ENGINE_FORCE := 320.0
const REVERSE_FORCE := 180.0
const BRAKE_FORCE := 6.0
const PASSIVE_BRAKE := 0.4   # mild drag when no input so the car coasts to a stop
const STEER_MAX := 0.55
const STEER_SPEED := 4.0     # how fast steering eases toward target

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
		w.wheel_friction_slip = 4.0
		w.suspension_stiffness = 35.0
		w.suspension_max_force = 6500.0
		w.damping_compression = 0.6
		w.damping_relaxation = 0.5
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
	_camera.position = Vector3(0, 1.4, 5.5)
	_camera.rotation = Vector3(deg_to_rad(-12.0), PI, 0)
	_camera.fov = 70.0
	_camera_pivot.add_child(_camera)
	# Mass on the body itself drags the centre of mass too high if the
	# default sits on the cabin. Bias it down so the car doesn't tip.
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.2, 0)

func _physics_process(delta: float) -> void:
	# Driver input drives engine + steering. Brake is applied to all
	# wheels via the VehicleBody3D `brake` property.
	if _driver != null:
		var fwd: float = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
		var steer_in: float = Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
		var target_engine: float = 0.0
		var target_brake: float = PASSIVE_BRAKE
		if fwd > 0.0:
			target_engine = ENGINE_FORCE * fwd
			target_brake = 0.0
		elif fwd < 0.0:
			# Reverse if nearly stopped, otherwise brake.
			var local_v: Vector3 = global_transform.basis.transposed() * linear_velocity
			if local_v.z > -0.5:
				target_engine = -REVERSE_FORCE * absf(fwd)
				target_brake = 0.0
			else:
				target_brake = BRAKE_FORCE * absf(fwd)
		engine_force = target_engine
		brake = target_brake
		# Steering eases toward target so the wheels don't snap.
		var alpha: float = 1.0 - exp(-STEER_SPEED * delta)
		_steer = lerpf(_steer, steer_in * STEER_MAX, alpha)
		steering = _steer
	else:
		# Passive: no throttle, light drag so the car settles.
		engine_force = 0.0
		brake = PASSIVE_BRAKE
		_steer = lerpf(_steer, 0.0, 1.0 - exp(-STEER_SPEED * delta))
		steering = _steer

func _process(_delta: float) -> void:
	# E to exit. Entering is driven from main_bootstrap (or any other
	# system that calls try_enter_driver) so we don't race the player's
	# own E handling for pickups.
	if _driver != null and Input.is_action_just_pressed("interact"):
		if Time.get_ticks_msec() / 1000.0 >= _enter_locked_until:
			exit_driver()

func is_driver_seat_open() -> bool:
	return _driver == null

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
	_enter_locked_until = Time.get_ticks_msec() / 1000.0 + 0.3

func _find_camera(n: Node) -> Camera3D:
	if n is Camera3D:
		return n
	for c in n.get_children():
		var found: Camera3D = _find_camera(c)
		if found != null:
			return found
	return null
