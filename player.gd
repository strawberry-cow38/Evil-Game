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
const TP_BACK_DIST := 4.0    # camera pull-back along +z (behind head) in third-person
const TP_UP_BOOST := 0.5     # extra height in third-person
const TP_BLEND_RATE := 12.0  # ease-in/out rate for the tp blend
const CROUCH_LERP_RATE := 14.0   # exp-approach per second

const FOV_HIP := 80.0
const FOV_ADS := 55.0
const ADS_LERP_RATE := 18.0

const INTERACT_RANGE := 3.0
# Hit everything (1 << 32 - 1); we filter by meta below so walls properly block.
const INTERACT_MASK := 0xFFFFFFFF

const Items = preload("res://items.gd")
const PICKUP_SCRIPT := preload("res://pickup.gd")
const CONTAINER_HOVER := preload("res://container_hover.gd")
const CONTAINER_MENU := preload("res://container_menu.gd")
const DROP_FORWARD := 1.1            # m in front of player center
const DROP_SPREAD := 0.45            # m random radius around drop anchor
const DROP_HEIGHT := 0.35            # m above floor
const DROP_WALL_BUFFER := 0.30       # m back-off from wall hit point

const STARTING_WEAPONS: Array[String] = ["akm", "sks", "m16a2", "bizon", "mp5sd", "p90", "makarov", "m700", "m249", "m60", "mgl", "shotgun_combat"]
# Quality + condition demo seed — varied so every tier color shows up in the
# inventory list right at game start.
const STARTING_WEAPON_INSTANCES: Array = [
	{"id": "akm",     "condition": 1.00, "quality": 2},  # Normal Pristine
	{"id": "sks",     "condition": 0.83, "quality": 5},  # Masterwork Pristine
	{"id": "m16a2",   "condition": 0.92, "quality": 3},  # Good Pristine
	{"id": "aug",     "condition": 0.94, "quality": 4},  # Excellent Pristine
	{"id": "bizon",   "condition": 0.65, "quality": 1},  # Poor Worn
	{"id": "mp5sd",   "condition": 0.88, "quality": 4},  # Excellent Pristine
	{"id": "ppsh41",  "condition": 0.72, "quality": 2},  # Normal Worn
	{"id": "thompson","condition": 0.80, "quality": 3},  # Good Pristine
	{"id": "m1911",   "condition": 0.95, "quality": 4},  # Excellent Pristine
	{"id": "p90",     "condition": 0.91, "quality": 3},  # Good Pristine
	{"id": "makarov", "condition": 0.42, "quality": 2},  # Normal Damaged
	{"id": "m700",    "condition": 0.97, "quality": 5},  # Masterwork Pristine
	{"id": "fal",     "condition": 0.86, "quality": 3},  # Good Pristine
	{"id": "g3",      "condition": 0.84, "quality": 3},  # Good Pristine
	{"id": "m14",     "condition": 0.89, "quality": 4},  # Excellent Pristine
	{"id": "stg57",   "condition": 0.91, "quality": 4},  # Excellent Pristine
	{"id": "mac10",   "condition": 0.74, "quality": 2},  # Normal Worn
	{"id": "uzi",     "condition": 0.86, "quality": 3},  # Good Pristine
	{"id": "m1903",   "condition": 0.92, "quality": 4},  # Excellent Pristine
	{"id": "garand",  "condition": 0.88, "quality": 3},  # Good Pristine
	{"id": "bar",     "condition": 0.81, "quality": 3},  # Good Pristine
	{"id": "ks23",    "condition": 0.85, "quality": 3},  # Good Pristine
	{"id": "lever_4570",  "condition": 0.90, "quality": 4},  # Excellent Pristine
	{"id": "pistol_4570", "condition": 0.78, "quality": 3},  # Good Pristine
	{"id": "python",      "condition": 0.95, "quality": 5},  # Masterwork Pristine
	{"id": "m249",    "condition": 0.78, "quality": 3},  # Good Worn
	{"id": "m60",     "condition": 0.20, "quality": 0},  # Awful Ruined
	{"id": "mgl",     "condition": 1.00, "quality": 6},  # Legendary Pristine
	{"id": "shotgun_combat", "condition": 0.95, "quality": 4},  # Excellent Pristine
	{"id": "aa12",    "condition": 0.88, "quality": 4},  # Excellent Pristine
]
const STARTING_AMMO: Dictionary = {
	"ammo_762x39":  200,
	"ammo_556nato": 200,
	"ammo_9mm":     200,
	"ammo_57x28":   200,
	"ammo_9x18":    200,
	"ammo_762nato": 200,
	"ammo_75x55":   200,
	"ammo_762x25":  300,
	"ammo_45acp":   200,
	"ammo_40mm":    200,
	"ammo_12ga":    100,
	"ammo_12ga_slug": 50,
	"ammo_3006":    200,
	"ammo_23x75":    40,
	"ammo_4570":    100,
	"ammo_357":     150,
	"att_m1903_scope": 1,
	"att_ak_scope":    1,
	"att_ak_silencer": 1,
	"att_ak_mag_40":   1,
	"att_ak_drum_75":  1,
	"att_m16_scope":    1,
	"att_m16_silencer": 1,
	"att_m16_mag_40":   1,
	"att_m16_drum_90":  1,
	"att_aug_mag_40":   1,
	"att_762nato_silencer": 1,
	"att_fal_scope":   1,
	"att_fal_mag_30":  1,
	"att_xm_choke":     1,
	"att_xm_ext_tube":  1,
	"att_lmg_bipod":    2,
}

# Reload-as-pie threshold: holding R longer than this opens the radial menu;
# tap-release reloads with the currently selected ammo.
const RELOAD_HOLD_THRESHOLD := 0.20

@export var menu_path: NodePath
@export var inventory_path: NodePath
@export var weapon_path: NodePath
@export var pie_menu_path: NodePath
@export var scope_overlay_path: NodePath

@onready var _camera: Camera3D = $Camera3D
@onready var _body_mesh: MeshInstance3D = $MeshInstance3D
@onready var _weapon: Node = get_node(weapon_path) if weapon_path != NodePath() else null

var _yaw := 0.0
var _pitch := 0.0
# Mouse motion accumulators applied in _physics_process. With physics
# interpolation enabled, setting rotation outside the physics tick lets
# the engine lerp between old and new transforms — feels like yaw lag.
# Buffering here and applying once per physics step keeps the prev/curr
# interpolation snapshots aligned with our intent.
var _yaw_delta := 0.0
var _pitch_delta := 0.0
var _crouched := false
var _ads := false
var _third_person := false
var _tp_blend: float = 0.0
var _menu: Node
var _inventory: Node
var _pie: Node
var _scope: Node
var _interact_target: Node = null    # current Pickup the player is looking at, if any
var _container_target: Node = null   # current crate the player is looking at, if any
var _container_hover: CanvasLayer    # right-side hover panel listing the crate's items
var _container_menu: CanvasLayer     # full-screen looting menu (opens with R)
var _prompt_label: Label
var _rng := RandomNumberGenerator.new()
var _reload_held: bool = false
var _reload_press_time: float = 0.0
var _pie_active: bool = false
var _vehicle: Node = null  # set when seated as driver; suppresses movement + interact

const FALL_SAFETY_Y := -40.0   # below this y → fell out of the map; respawn

var _initial_spawn: Vector3 = Vector3.ZERO

func _ready() -> void:
	_rng.randomize()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_initial_spawn = global_position
	if menu_path != NodePath():
		_menu = get_node(menu_path)
	if inventory_path != NodePath():
		_inventory = get_node(inventory_path)
	if pie_menu_path != NodePath():
		_pie = get_node(pie_menu_path)
	if scope_overlay_path != NodePath():
		_scope = get_node(scope_overlay_path)
	_build_prompt()
	_container_hover = CONTAINER_HOVER.new()
	add_child(_container_hover)
	_container_menu = CONTAINER_MENU.new()
	add_child(_container_menu)
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
	# Walk the freshly-spawned weapon instances and bind them to digit
	# slots 1..9. Player spawns unarmed — pressing a digit equips that
	# weapon (and pays its pullout cost).
	var slot := 1
	for inst in _inventory.instances:
		if Items.item_kind(String(inst.item_id)) != "weapon":
			continue
		if slot <= 9:
			_inventory.set_favorite(slot, int(inst.uid))
			slot += 1

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
		_weapon.equip(String(inst.item_id), uid)

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

# Picks the best spawn point and teleports there. Order:
#  1. random authored player_spawn marker (positioned at terrain
#     height + 1.2m so we don't clip)
#  2. fallback to the position the player started at this scene
func _respawn_at_safe_point() -> void:
	var target: Vector3 = _initial_spawn
	if MapState != null and not MapState.player_spawns.is_empty():
		var sp: Vector3 = MapState.random_player_spawn()
		var ground_h: float = sp.y
		var terrain := get_node_or_null("../EditorTerrain")
		if terrain != null and terrain.has_method("sample_height"):
			ground_h = terrain.sample_height(sp)
		target = Vector3(sp.x, ground_h + 1.2, sp.z)
	global_position = target
	velocity = Vector3.ZERO
	# Snap interpolation so the camera doesn't lerp from the old spot to
	# the spawn over a frame.
	reset_physics_interpolation()

func is_menu_open() -> bool:
	if _menu != null and _menu.has_method("is_open") and _menu.is_open():
		return true
	if _container_menu != null and _container_menu.has_method("is_open") and _container_menu.is_open():
		return true
	return false

func _toggle_third_person() -> void:
	if _vehicle != null and _vehicle.has_method("toggle_camera"):
		_vehicle.toggle_camera()
		return
	_third_person = not _third_person

func is_pie_open() -> bool:
	return _pie != null and _pie.has_method("is_open") and _pie.is_open()

func has_interact_target() -> bool:
	return _interact_target != null

func is_in_vehicle() -> bool:
	return _vehicle != null

func get_vehicle() -> Node:
	return _vehicle

# Called by vehicle.gd on enter (with the vehicle node) and on exit (with null).
# We just stash a reference; _physics_process / _process check it and early-out.
func set_in_vehicle(v: Node) -> void:
	_vehicle = v
	if v != null:
		velocity = Vector3.ZERO
		_prompt_label.text = ""
		_interact_target = null
		_container_target = null
		if _container_hover != null:
			_container_hover.hide_panel()
	visible = v == null

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not is_pie_open():
		# Scale sensitivity with current FOV so ADS (and especially scoped ADS)
		# slows mouselook proportionally to the zoom level. tan(fov/2) keeps
		# pixels-per-degree consistent at any zoom.
		var sens: float = MOUSE_SENSITIVITY
		if _camera != null:
			sens *= tan(deg_to_rad(_camera.fov) * 0.5) / tan(deg_to_rad(FOV_HIP) * 0.5)
		_yaw_delta -= event.relative.x * sens
		_pitch_delta -= event.relative.y * sens
	elif event.is_action_pressed("ui_menu") and not is_menu_open():
		_menu.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_view") and not is_menu_open():
		_toggle_third_person()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		# Menu handles its own ESC when open; only the click-recapture flow runs here.
		if not is_menu_open():
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed and _container_target != null and not is_menu_open():
		# Mouse wheel scrolls the highlighted item in the hover panel. Swallow
		# the event so the weapon doesn't see it.
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _container_hover != null:
				_container_hover.cycle(-1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _container_hover != null:
				_container_hover.cycle(1)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not is_menu_open():
		# Click anywhere in the window re-grabs the cursor; swallow the click
		# so the gun doesn't fire on the same press. Skip while menu is open
		# so clicking on tabs/list items doesn't capture the cursor.
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	# Driving: vehicle.gd owns input + camera, so nothing for the player to do.
	if _vehicle != null:
		return
	_update_interact_target()
	# E priority: try entering a nearby vehicle BEFORE looting a pickup, so the
	# player can stand near a car+item and have E mean "drive" rather than "loot".
	if not is_menu_open() and Input.is_action_just_pressed("interact"):
		if _try_enter_nearby_vehicle():
			return
		if _container_target != null:
			_loot_from_container()
			return
		if _interact_target != null:
			_loot(_interact_target)
	# R while looking at a crate opens the full transfer menu. Steals R from the
	# weapon reload path so reload can't fire on the same press. The
	# can_reopen() check stops the same R press from immediately reopening
	# right after the menu's own _input handled the close.
	if not is_menu_open() and _container_target != null and Input.is_action_just_pressed("reload") \
			and (_container_menu == null or _container_menu.can_reopen()):
		_open_container_menu()
		return
	if not is_menu_open():
		_check_equip_hotkeys()
		_handle_reload_input()
	# Reloading kicks the player out of ADS — can't aim down sights with the
	# weapon torn open. Holding the ADS button is also ignored mid-reload.
	var weapon_reloading: bool = _weapon != null and _weapon.has_method("is_reloading") and _weapon.is_reloading()
	# Bolt-action rifles force the player out of ADS for the cycle window so
	# the scope kicks off the screen between shots.
	var ads_locked: bool = _weapon != null and _weapon.has_method("is_ads_locked") and _weapon.is_ads_locked()
	_ads = Input.is_action_pressed("ads") and not is_menu_open() and not is_pie_open() and not weapon_reloading and not ads_locked

	# ADS FOV zoom. Sniper scopes override the default ADS FOV via profile.
	var ads_fov: float = FOV_ADS
	if _weapon != null and _weapon.has_method("get_ads_fov"):
		ads_fov = _weapon.get_ads_fov(FOV_ADS)
	var target_fov: float = ads_fov if _ads else FOV_HIP
	var fov_alpha: float = 1.0 - exp(-ADS_LERP_RATE * delta)
	_camera.fov = lerpf(_camera.fov, target_fov, fov_alpha)

	# Scope overlay visible only when ADS on a scoped weapon. Wait until the
	# zoom is most of the way in so the black mask doesn't appear pre-zoom.
	if _scope != null:
		var scoped: bool = _weapon != null and _weapon.has_method("has_scope") and _weapon.has_scope()
		var zoomed_in: bool = absf(_camera.fov - ads_fov) < 5.0
		if _ads and scoped and zoomed_in:
			_scope.show_scope()
		else:
			_scope.hide_scope()

func _physics_process(delta: float) -> void:
	# Drain mouse-look deltas accumulated since the last physics tick.
	# Applied here so the engine's prev/curr interpolation snapshots
	# bracket each yaw/pitch change cleanly — setting rotation outside
	# physics would visibly lerp the rotation across the next render
	# frames.
	if _yaw_delta != 0.0 or _pitch_delta != 0.0:
		_yaw += _yaw_delta
		_pitch += _pitch_delta
		_pitch = clamp(_pitch, -1.4, 1.4)
		rotation.y = _yaw
		_camera.rotation.x = _pitch
		_yaw_delta = 0.0
		_pitch_delta = 0.0
	# Crouch height lerp lives in physics so the interpolated camera doesn't
	# warn about transform changes outside the physics tick.
	var base_y: float = CAMERA_HEIGHT_CROUCH if _crouched else CAMERA_HEIGHT_STAND
	var blend_alpha: float = 1.0 - exp(-TP_BLEND_RATE * delta)
	var scope_lock: bool = _ads and _weapon != null and _weapon.has_method("has_scope") and _weapon.has_scope()
	var tp_target: float = 1.0 if _third_person and _vehicle == null and not scope_lock else 0.0
	_tp_blend = lerpf(_tp_blend, tp_target, blend_alpha)
	var crouch_alpha: float = 1.0 - exp(-CROUCH_LERP_RATE * delta)
	var cam_pos := _camera.position
	cam_pos.y = lerpf(cam_pos.y, base_y + TP_UP_BOOST * _tp_blend, crouch_alpha)
	cam_pos.z = TP_BACK_DIST * _tp_blend
	_camera.position = cam_pos
	if _body_mesh != null:
		_body_mesh.visible = _tp_blend > 0.05 and _vehicle == null
	# Driving: vehicle parks us at the seat marker each frame (effectively),
	# but we still run zero physics so we don't fall away or eat collisions.
	if _vehicle != null:
		velocity = Vector3.ZERO
		return
	# Fall-out-of-the-world safety net — teleport back to spawn before
	# the player falls forever.
	if global_position.y < FALL_SAFETY_Y:
		_respawn_at_safe_point()
		return
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
		_container_target = null
		_prompt_label.text = ""
		if _container_hover != null:
			_container_hover.hide_panel()
		return
	# Short ray straight forward from the camera. The collider's meta tells us
	# whether it's a pickup, a container, or just geometry.
	var origin: Vector3 = _camera.global_transform.origin
	var dir: Vector3 = -_camera.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * INTERACT_RANGE)
	q.collision_mask = INTERACT_MASK
	q.exclude = [get_rid()]
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	var pickup: Node = null
	var container: Node = null
	if r and r.has("collider"):
		var col: Object = r.collider
		if col is Node:
			if col.has_meta("pickup"):
				var p = col.get_meta("pickup")
				if is_instance_valid(p):
					pickup = p
			elif col.has_meta("container"):
				var c = col.get_meta("container")
				if is_instance_valid(c):
					container = c
	_interact_target = pickup
	_container_target = container
	if container != null:
		_prompt_label.text = ""
		if _container_hover != null:
			_container_hover.show_for(container)
	elif pickup != null and pickup.has_method("get_label"):
		_prompt_label.text = "[E] Pick up %s" % pickup.get_label()
		if _container_hover != null:
			_container_hover.hide_panel()
	else:
		_prompt_label.text = ""
		if _container_hover != null:
			_container_hover.hide_panel()
	# Container contents may have changed (we just transferred items, or some
	# other path mutated them) — keep the panel readout fresh.
	if container != null and _container_hover != null:
		_container_hover.refresh()

# Walk the "vehicle" group, pick the closest one with an open driver seat, and
# call try_enter_driver on it. Returns true if we actually got in.
func _try_enter_nearby_vehicle() -> bool:
	var best: Node = null
	var best_d: float = INF
	for v in get_tree().get_nodes_in_group("vehicle"):
		if v == null or not v.has_method("try_enter_driver"):
			continue
		if v.has_method("is_driver_seat_open") and not v.is_driver_seat_open():
			continue
		var seat: Vector3 = v.driver_seat_world() if v.has_method("driver_seat_world") else (v as Node3D).global_position
		var d: float = global_position.distance_to(seat)
		if d < best_d:
			best_d = d
			best = v
	if best == null:
		return false
	return best.try_enter_driver(self)

func _check_equip_hotkeys() -> void:
	if _inventory == null:
		return
	for slot in range(1, 10):
		if Input.is_action_just_pressed("equip_%d" % slot):
			var uid: int = _inventory.favorite_uid(slot)
			if uid != 0 and _inventory.has_uid(uid):
				_inventory.set_equipped(uid)

# Tap R reloads with currently selected ammo. Holding R past the threshold
# opens the radial pie menu listing every compatible cartridge for the equipped
# weapon; releasing R picks the highlighted segment and starts the reload.
# Single-ammo weapons skip the pie entirely and reload on press (no hold-to-pie
# delay since there's nothing to choose).
func _handle_reload_input() -> void:
	if _weapon == null:
		return
	var compat: Array = _weapon.get_compatible_ammo_ids() if _weapon.has_method("get_compatible_ammo_ids") else []
	var reloading: bool = _weapon.has_method("is_reloading") and _weapon.is_reloading()

	if Input.is_action_just_pressed("reload"):
		_reload_held = true
		_reload_press_time = Time.get_ticks_msec() / 1000.0
		# Single-ammo: trigger immediately, skip the hold-detection window.
		if compat.size() <= 1:
			if not reloading and _weapon.has_method("start_reload"):
				_weapon.start_reload()
			_reload_held = false
		return

	# Open the pie once the hold threshold elapses (only for multi-ammo weapons,
	# and only if we're not already mid-reload — pie can't switch ammo mid-cycle).
	if _reload_held and not _pie_active and _pie != null and compat.size() > 1 and not reloading:
		var held: float = (Time.get_ticks_msec() / 1000.0) - _reload_press_time
		if held >= RELOAD_HOLD_THRESHOLD:
			_open_reload_pie(compat)

	if Input.is_action_just_released("reload"):
		var was_held := _reload_held
		_reload_held = false
		if _pie_active:
			_close_reload_pie_and_apply()
		elif was_held:
			# Tap-release with multi-ammo: reload with current selection.
			if not reloading and _weapon.has_method("start_reload"):
				_weapon.start_reload()

func _open_reload_pie(compat: Array) -> void:
	if _pie == null:
		return
	var opts: Array = []
	for id in compat:
		var sid := String(id)
		var def: Dictionary = Items.item_def(sid)
		var count: int = int(_inventory.counts.get(sid, 0)) if _inventory != null else 0
		opts.append({
			"id": sid,
			"name": String(def.get("name", sid)),
			"count": count,
			"color": Color(def.get("color", Color(0.85, 0.85, 0.85))),
		})
	_pie.open(opts)
	_pie_active = true

func _close_reload_pie_and_apply() -> void:
	if _pie == null:
		_pie_active = false
		return
	var picked: String = _pie.get_picked()
	_pie.close()
	_pie_active = false
	if picked != "" and _weapon.has_method("set_selected_ammo"):
		# Switching cartridge types empties the mag back to inventory first —
		# shotgun tubes can't mix buckshot and slugs.
		var current: String = _weapon.get_selected_ammo() if _weapon.has_method("get_selected_ammo") else ""
		if picked != current and _weapon.has_method("unload_mag"):
			_weapon.unload_mag()
		_weapon.set_selected_ammo(picked)
	var reloading: bool = _weapon.has_method("is_reloading") and _weapon.is_reloading()
	if not reloading and _weapon.has_method("start_reload"):
		_weapon.start_reload()

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
# Weapons also carry their live mag count, selected ammo, and fire mode so
# re-picking up the dropped gun resumes where the player left it.
func drop_instance(uid: int) -> bool:
	if _inventory == null or uid == 0:
		return false
	# Capture weapon state BEFORE remove_instance — capture_state on the
	# currently-equipped uid reads live _ammo, which doesn't survive
	# unequip-on-removal.
	var weapon_state: Dictionary = {}
	if _weapon != null and _weapon.has_method("capture_state"):
		weapon_state = _weapon.capture_state(uid)
	var inst: Dictionary = _inventory.remove_instance(uid)
	if inst.is_empty():
		return false
	for k in weapon_state.keys():
		inst[k] = weapon_state[k]
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

func _open_container_menu() -> void:
	if _container_menu == null or _container_target == null or _inventory == null:
		return
	# Hide the hover panel while the full menu is up — they'd just stack.
	if _container_hover != null:
		_container_hover.hide_panel()
	_container_menu.open(_inventory, _container_target)

func _loot_from_container() -> void:
	if _inventory == null or _container_target == null or _container_hover == null:
		return
	var entry: Dictionary = _container_hover.selected_entry()
	if entry.is_empty():
		return
	if bool(entry.get("is_instance", false)):
		var uid: int = int(entry.get("uid", 0))
		if uid == 0:
			return
		var inst: Dictionary = _container_target.remove_instance(uid)
		if inst.is_empty():
			return
		if not _inventory.add_instance(inst):
			# Weight failed — restore to crate so nothing vanishes.
			_container_target.add_instance(inst)
			_prompt_label.text = "Too heavy! (%s)" % String(entry.get("name", ""))
	else:
		var id: String = String(entry.get("id", ""))
		var count: int = int(entry.get("count", 1))
		if id == "" or count <= 0:
			return
		# Try the whole stack first; fall back to as much as fits if the
		# player can't carry the lot.
		var fits: int = count
		while fits > 0 and not _inventory.can_add(id, fits):
			fits -= 1
		if fits <= 0:
			_prompt_label.text = "Too heavy! (%s)" % String(entry.get("name", ""))
			return
		if _container_target.remove(id, fits):
			_inventory.add(id, fits)
	# Refresh the hover panel so the new counts/list show immediately.
	_container_hover.refresh()

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
