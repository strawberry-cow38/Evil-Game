extends Camera3D

# Free-fly editor camera. Hold MMB to look around (mouse captured for the
# duration). WASD moves on the camera plane; Q/E dolly up/down in world
# space. Scroll wheel adjusts move speed (held MMB) so the same controls
# scale from inch-precision to map-spanning travel.

const SPEED_MIN := 1.0
const SPEED_MAX := 60.0
const SPEED_STEP := 1.15
const LOOK_SENS := 0.0030

var _yaw := 0.0
var _pitch := -0.4
var _move_speed := 12.0
var _looking := false

func _ready() -> void:
	current = true
	_yaw = rotation.y
	_pitch = rotation.x

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_looking = event.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _looking else Input.MOUSE_MODE_VISIBLE
		elif _looking and event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_move_speed = clampf(_move_speed * SPEED_STEP, SPEED_MIN, SPEED_MAX)
		elif _looking and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_move_speed = clampf(_move_speed / SPEED_STEP, SPEED_MIN, SPEED_MAX)
	elif event is InputEventMouseMotion and _looking:
		_yaw -= event.relative.x * LOOK_SENS
		_pitch -= event.relative.y * LOOK_SENS
		_pitch = clampf(_pitch, -1.4, 1.4)
		rotation = Vector3(_pitch, _yaw, 0.0)

func _process(delta: float) -> void:
	if not _looking:
		return
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir.z -= 1.0
	if Input.is_key_pressed(KEY_S): dir.z += 1.0
	if Input.is_key_pressed(KEY_A): dir.x -= 1.0
	if Input.is_key_pressed(KEY_D): dir.x += 1.0
	var up := 0.0
	if Input.is_key_pressed(KEY_E): up += 1.0
	if Input.is_key_pressed(KEY_Q): up -= 1.0
	var sprint := 1.0
	if Input.is_key_pressed(KEY_SHIFT): sprint = 3.0
	if dir.length() > 0.0:
		dir = dir.normalized()
	var basis_xz := transform.basis
	var motion: Vector3 = (basis_xz.x * dir.x + basis_xz.z * dir.z) * _move_speed * sprint * delta
	motion.y += up * _move_speed * sprint * delta
	position += motion

func is_looking() -> bool:
	return _looking

func get_move_speed() -> float:
	return _move_speed
