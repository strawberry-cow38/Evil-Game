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

const INTERACT_RANGE := 3.0
# Hit everything (1 << 32 - 1); we filter by meta below so walls properly block.
const INTERACT_MASK := 0xFFFFFFFF

const STARTING_WEAPONS: Array[String] = ["akm", "m16a2", "bizon", "mp5sd", "m249", "m60", "mgl"]

@export var menu_path: NodePath
@export var inventory_path: NodePath
@export var weapon_path: NodePath

@onready var _camera: Camera3D = $Camera3D
@onready var _weapon: Node = get_node(weapon_path) if weapon_path != NodePath() else null

var _yaw := 0.0
var _pitch := 0.0
var _crouched := false
var _ads := false
var _menu: Node
var _inventory: Node
var _interact_target: Node = null    # current Pickup the player is looking at, if any
var _prompt_label: Label

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if menu_path != NodePath():
		_menu = get_node(menu_path)
	if inventory_path != NodePath():
		_inventory = get_node(inventory_path)
	_build_prompt()
	_seed_starting_inventory()
	if _inventory != null and _inventory.has_signal("equipped_changed"):
		_inventory.equipped_changed.connect(_on_equipped_changed)

func _seed_starting_inventory() -> void:
	if _inventory == null or not _inventory.has_method("grant"):
		return
	for id in STARTING_WEAPONS:
		_inventory.grant(id, 1)
	# Auto-equip first weapon and bind digit defaults so the player isn't naked.
	if STARTING_WEAPONS.size() > 0:
		_inventory.set_equipped(STARTING_WEAPONS[0])
	for i in range(STARTING_WEAPONS.size()):
		var slot: int = i + 1
		if slot > 9:
			break
		_inventory.set_favorite(slot, STARTING_WEAPONS[i])

func _on_equipped_changed(id: String) -> void:
	if _weapon != null and _weapon.has_method("equip") and id != "":
		_weapon.equip(id)

func _build_prompt() -> void:
	# Tiny center-bottom hint label, lives on its own CanvasLayer so the HUD
	# scene doesn't have to know about it.
	var cl := CanvasLayer.new()
	cl.layer = 30
	add_child(cl)
	_prompt_label = Label.new()
	_prompt_label.add_theme_font_size_override("font_size", 18)
	_prompt_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_prompt_label.add_theme_constant_override("outline_size", 4)
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.offset_top = -90
	_prompt_label.offset_bottom = -60
	_prompt_label.offset_left = -200
	_prompt_label.offset_right = 200
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.text = ""
	cl.add_child(_prompt_label)

func is_crouched() -> bool:
	return _crouched

func is_ads() -> bool:
	return _ads

func is_menu_open() -> bool:
	return _menu != null and _menu.has_method("is_open") and _menu.is_open()

func has_interact_target() -> bool:
	return _interact_target != null

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * MOUSE_SENSITIVITY
		_pitch -= event.relative.y * MOUSE_SENSITIVITY
		_pitch = clamp(_pitch, -1.4, 1.4)
		rotation.y = _yaw
		_camera.rotation.x = _pitch
	elif event.is_action_pressed("ui_menu") and not is_menu_open():
		_menu.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		# Menu handles its own ESC when open; only the click-recapture flow runs here.
		if not is_menu_open():
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not is_menu_open():
		# Click anywhere in the window re-grabs the cursor; swallow the click
		# so the gun doesn't fire on the same press. Skip while menu is open
		# so clicking on tabs/list items doesn't capture the cursor.
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_update_interact_target()
	if not is_menu_open() and _interact_target != null and Input.is_action_just_pressed("interact"):
		_loot(_interact_target)
	if not is_menu_open():
		_check_equip_hotkeys()
	_ads = Input.is_action_pressed("ads") and not is_menu_open()

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
	if is_menu_open():
		# Hold position while menu is up — gravity still applies so we don't
		# float, but no input-driven movement.
		if not is_on_floor():
			velocity += get_gravity() * delta
		velocity.x = move_toward(velocity.x, 0.0, SPEED_FORWARD * 2.0)
		velocity.z = move_toward(velocity.z, 0.0, SPEED_FORWARD * 2.0)
		move_and_slide()
		return

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

func _update_interact_target() -> void:
	if is_menu_open():
		_interact_target = null
		_prompt_label.text = ""
		return
	# Short ray straight forward from the camera; only hits pickup bodies (layer 4).
	var origin: Vector3 = _camera.global_transform.origin
	var dir: Vector3 = -_camera.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * INTERACT_RANGE)
	q.collision_mask = INTERACT_MASK
	q.exclude = [get_rid()]
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	var pickup: Node = null
	if r and r.has("collider"):
		var col: Object = r.collider
		if col is Node and col.has_meta("pickup"):
			var p = col.get_meta("pickup")
			if is_instance_valid(p):
				pickup = p
	_interact_target = pickup
	if pickup != null and pickup.has_method("get_label"):
		_prompt_label.text = "[E] Pick up %s" % pickup.get_label()
	else:
		_prompt_label.text = ""

func _check_equip_hotkeys() -> void:
	if _inventory == null:
		return
	for slot in range(1, 10):
		if Input.is_action_just_pressed("equip_%d" % slot):
			var id: String = _inventory.favorite_id(slot)
			if id != "" and _inventory.has_item(id):
				_inventory.set_equipped(id)

func _loot(target: Node) -> void:
	if _inventory == null or target == null or not _inventory.has_method("add"):
		return
	var id: String = target.get("item_id")
	var count: int = int(target.get("count"))
	if _inventory.add(id, count):
		target.queue_free()
		_interact_target = null
		_prompt_label.text = ""
	else:
		_prompt_label.text = "Too heavy! (%s)" % target.get_label()
