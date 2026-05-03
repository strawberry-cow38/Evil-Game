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

const Items = preload("res://items.gd")
const PICKUP_SCRIPT := preload("res://pickup.gd")
const DROP_FORWARD := 1.1            # m in front of player center
const DROP_SPREAD := 0.45            # m random radius around drop anchor
const DROP_HEIGHT := 0.35            # m above floor
const DROP_WALL_BUFFER := 0.30       # m back-off from wall hit point

const STARTING_WEAPONS: Array[String] = ["akm", "m16a2", "bizon", "mp5sd", "makarov", "m249", "m60", "mgl"]
# Quality + condition demo seed — varied so every tier color shows up in the
# inventory list right at game start.
const STARTING_WEAPON_INSTANCES: Array = [
	{"id": "akm",     "condition": 1.00, "quality": 2},  # Normal Pristine
	{"id": "m16a2",   "condition": 0.92, "quality": 3},  # Good Pristine
	{"id": "bizon",   "condition": 0.65, "quality": 1},  # Poor Worn
	{"id": "mp5sd",   "condition": 0.88, "quality": 4},  # Excellent Pristine
	{"id": "makarov", "condition": 0.42, "quality": 2},  # Normal Damaged
	{"id": "m249",    "condition": 0.78, "quality": 3},  # Good Worn
	{"id": "m60",     "condition": 0.20, "quality": 0},  # Awful Ruined
	{"id": "mgl",     "condition": 1.00, "quality": 6},  # Legendary Pristine
]
const STARTING_AMMO: Dictionary = {
	"ammo_762x39":  200,
	"ammo_556nato": 200,
	"ammo_9mm":     200,
	"ammo_9x18":    200,
	"ammo_762nato": 200,
	"ammo_40mm":    200,
}

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
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
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
	for entry in STARTING_WEAPON_INSTANCES:
		_inventory.grant_instance(
			String(entry.id),
			float(entry.condition),
			int(entry.quality),
		)
	for id in STARTING_AMMO.keys():
		_inventory.grant(id, int(STARTING_AMMO[id]))
	# Walk the freshly-spawned weapon instances in grant order; auto-equip the
	# first and bind subsequent ones to digit slots 1..9 so the player isn't
	# naked.
	var slot := 1
	var first_uid := 0
	for inst in _inventory.instances:
		if Items.item_kind(String(inst.item_id)) != "weapon":
			continue
		if first_uid == 0:
			first_uid = int(inst.uid)
		if slot <= 9:
			_inventory.set_favorite(slot, int(inst.uid))
			slot += 1
	if first_uid != 0:
		_inventory.set_equipped(first_uid)

func _on_equipped_changed(uid: int) -> void:
	if _weapon == null:
		return
	if uid == 0:
		if _weapon.has_method("unequip"):
			_weapon.unequip()
		return
	var inst: Dictionary = _inventory.get_instance(uid)
	if inst.is_empty():
		return
	if _weapon.has_method("equip"):
		_weapon.equip(String(inst.item_id))

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
			var uid: int = _inventory.favorite_uid(slot)
			if uid != 0 and _inventory.has_uid(uid):
				_inventory.set_equipped(uid)

# Stackable drop path (ammo, food, etc).
func drop_item(id: String, count: int = 1) -> bool:
	if _inventory == null or count <= 0:
		return false
	if not _inventory.has_item(id):
		return false
	if not _inventory.remove(id, count):
		return false
	_spawn_drop(id, count, {})
	return true

# Instance drop path (weapons, apparel) — preserves condition + quality.
func drop_instance(uid: int) -> bool:
	if _inventory == null or uid == 0:
		return false
	var inst: Dictionary = _inventory.remove_instance(uid)
	if inst.is_empty():
		return false
	_spawn_drop(String(inst.item_id), 1, inst)
	return true

func _spawn_drop(id: String, count: int, instance: Dictionary) -> void:
	# Anchor in front of the player on the floor plane (ignore camera pitch).
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()

	var anchor: Vector3 = global_position + fwd * DROP_FORWARD
	# Random offset to scatter stacked drops so they don't overlap.
	var ang: float = _rng.randf() * TAU
	var rad: float = sqrt(_rng.randf()) * DROP_SPREAD
	anchor += Vector3(cos(ang) * rad, 0.0, sin(ang) * rad)

	# Wall-safety raycast at chest height: if the path from player to drop
	# anchor crosses geometry, pull the anchor back behind the hit point.
	var space := get_world_3d().direct_space_state
	var ray_from: Vector3 = global_position + Vector3(0.0, 0.9, 0.0)
	var ray_to: Vector3 = anchor + Vector3(0.0, 0.9, 0.0)
	var q := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	q.exclude = [get_rid()]
	q.collision_mask = 0xFFFFFFFF
	var r := space.intersect_ray(q)
	if r and r.has("position"):
		var hit: Vector3 = r.position
		var pull_back: Vector3 = (ray_from - hit).normalized() * DROP_WALL_BUFFER
		anchor = Vector3(hit.x + pull_back.x, anchor.y, hit.z + pull_back.z)

	anchor.y = DROP_HEIGHT

	var p := PICKUP_SCRIPT.new()
	p.item_id = id
	p.count = count
	if not instance.is_empty():
		p.instance = instance.duplicate(true)
	get_tree().current_scene.add_child(p)
	p.global_position = anchor

func _loot(target: Node) -> void:
	if _inventory == null or target == null:
		return
	var id: String = String(target.get("item_id"))
	var count: int = int(target.get("count"))
	var inst: Dictionary = target.get("instance") if target.get("instance") != null else {}
	var ok: bool
	if not inst.is_empty():
		ok = _inventory.add_instance(inst)
	else:
		ok = _inventory.add(id, count)
	if ok:
		target.queue_free()
		_interact_target = null
		_prompt_label.text = ""
	else:
		_prompt_label.text = "Too heavy! (%s)" % target.get_label()
