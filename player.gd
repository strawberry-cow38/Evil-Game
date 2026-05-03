extends CharacterBody3D

const SPEED_FORWARD := 6.0
const SPEED_SPRINT := 9.5
const SPEED_BACK := 3.6
const SPEED_STRAFE := 4.5
const CROUCH_SPEED_MULT := 0.5
const JUMP_VELOCITY := 5.0
const MOUSE_SENSITIVITY := 0.0025

const CAMERA_HEIGHT_STAND := 0.7
const CAMERA_HEIGHT_CROUCH := 0.3
const CROUCH_LERP_RATE := 14.0   # exp-approach per second

const FOV_HIP := 80.0
const FOV_ADS := 55.0
const ADS_LERP_RATE := 18.0

@onready var _camera: Camera3D = $Camera3D

var _yaw := 0.0
var _pitch := 0.0
var _crouched := false
var _ads := false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func is_crouched() -> bool:
	return _crouched

func is_ads() -> bool:
	return _ads

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * MOUSE_SENSITIVITY
		_pitch -= event.relative.y * MOUSE_SENSITIVITY
		_pitch = clamp(_pitch, -1.4, 1.4)
		rotation.y = _yaw
		_camera.rotation.x = _pitch
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		# Click anywhere in the window re-grabs the cursor; swallow the click
		# so the gun doesn't fire on the same press.
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_ads = Input.is_action_pressed("ads")

	# Smooth camera height between stand/crouch.
	var target_y: float = CAMERA_HEIGHT_CROUCH if _crouched else CAMERA_HEIGHT_STAND
	var alpha: float = 1.0 - exp(-CROUCH_LERP_RATE * delta)
	var pos := _camera.position
	pos.y = lerpf(pos.y, target_y, alpha)
	_camera.position = pos

	# ADS FOV zoom.
	var target_fov: float = FOV_ADS if _ads else FOV_HIP
	var fov_alpha: float = 1.0 - exp(-ADS_LERP_RATE * delta)
	_camera.fov = lerpf(_camera.fov, target_fov, fov_alpha)

func _physics_process(delta: float) -> void:
	_crouched = Input.is_action_pressed("crouch")

	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("jump") and is_on_floor() and not _crouched:
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var sprinting := Input.is_action_pressed("sprint") and input_dir.y < 0.0 and not _crouched
	var forward_speed := SPEED_FORWARD if input_dir.y < 0.0 else SPEED_BACK
	if sprinting:
		forward_speed = SPEED_SPRINT
	var strafe_speed := SPEED_STRAFE
	if _crouched:
		forward_speed *= CROUCH_SPEED_MULT
		strafe_speed *= CROUCH_SPEED_MULT
	var local_vel := Vector3(input_dir.x * strafe_speed, 0.0, input_dir.y * forward_speed)
	var world_vel := transform.basis * local_vel
	if input_dir != Vector2.ZERO:
		velocity.x = world_vel.x
		velocity.z = world_vel.z
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED_FORWARD)
		velocity.z = move_toward(velocity.z, 0.0, SPEED_FORWARD)

	move_and_slide()
