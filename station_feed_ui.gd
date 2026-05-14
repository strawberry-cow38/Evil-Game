extends CanvasLayer

# Fullscreen UI shown while the player is mounted at a Computer Station.
# Lists the station's pre-added cam IDs, lets the player pick one (the
# selected CCTV camera becomes the current Camera3D), optionally accepts
# new cam IDs if the station's `allow_add` flag is on, and exposes PTZ
# controls for cams whose `ptz_enabled` is true.
#
# Controls:
#   click a cam id        → swap active feed
#   type id + click Add   → append to the station's cam list (if allowed)
#   arrow keys            → pan/tilt active cam (if ptz_enabled)
#   Z / X                 → zoom in / out (if ptz_enabled)
#   F                     → dismount the station

const PTZ_YAW_RATE := 0.9      # radians/sec
const PTZ_PITCH_RATE := 0.7
const PTZ_ZOOM_RATE := 30.0    # deg/sec (FOV)

var _station: Node = null
var _player: Node = null
var _active_cam: Node = null   # cctv_camera.gd instance

var _root: Control
var _no_feed_overlay: ColorRect
var _no_feed_label: Label
var _status_label: Label
var _cam_list: ItemList
var _add_input: LineEdit
var _add_btn: Button
var _add_row: HBoxContainer
var _ptz_hint: Label

func _ready() -> void:
	layer = 100
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_root)
	# Fullscreen darkening shown only when no feed is selected. Becomes
	# transparent (visible=false) when a cam is active so the camera view
	# fills the screen.
	_no_feed_overlay = ColorRect.new()
	_no_feed_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_no_feed_overlay.color = Color(0.03, 0.03, 0.05, 0.9)
	_no_feed_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_no_feed_overlay)
	_no_feed_label = Label.new()
	_no_feed_label.set_anchors_preset(Control.PRESET_CENTER)
	_no_feed_label.offset_left = -240
	_no_feed_label.offset_right = 240
	_no_feed_label.offset_top = -40
	_no_feed_label.offset_bottom = 40
	_no_feed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_no_feed_label.add_theme_font_size_override("font_size", 22)
	_no_feed_label.text = "No feed selected"
	_no_feed_overlay.add_child(_no_feed_label)
	# Left-edge control panel. Sits over the (live) camera image when a
	# feed is active. Semi-opaque so the feed bleeds through.
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = 24
	panel.offset_top = 24
	panel.offset_bottom = -24
	panel.offset_right = 304
	panel.add_theme_constant_override("margin_left", 12)
	panel.add_theme_constant_override("margin_right", 12)
	panel.add_theme_constant_override("margin_top", 12)
	panel.add_theme_constant_override("margin_bottom", 12)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.06, 0.08, 0.85)
	bg.border_color = Color(0.4, 0.7, 1.0, 0.8)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", bg)
	_root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "Computer Station"
	title.add_theme_font_size_override("font_size", 18)
	vb.add_child(title)
	_status_label = Label.new()
	_status_label.text = "No feed"
	_status_label.add_theme_font_size_override("font_size", 12)
	vb.add_child(_status_label)
	_cam_list = ItemList.new()
	_cam_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cam_list.custom_minimum_size = Vector2(0, 200)
	_cam_list.item_selected.connect(_on_cam_selected)
	vb.add_child(_cam_list)
	_add_row = HBoxContainer.new()
	_add_input = LineEdit.new()
	_add_input.placeholder_text = "cam_id"
	_add_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_input.text_submitted.connect(func(_t: String): _on_add_pressed())
	_add_row.add_child(_add_input)
	_add_btn = Button.new()
	_add_btn.text = "Add"
	_add_btn.pressed.connect(_on_add_pressed)
	_add_row.add_child(_add_btn)
	vb.add_child(_add_row)
	_ptz_hint = Label.new()
	_ptz_hint.add_theme_font_size_override("font_size", 12)
	_ptz_hint.text = ""
	vb.add_child(_ptz_hint)
	var exit_lbl := Label.new()
	exit_lbl.text = "[F] Exit"
	exit_lbl.add_theme_font_size_override("font_size", 13)
	vb.add_child(exit_lbl)

# Called by computer_station.gd right after _ready so we know who we
# belong to. Refreshes the cam-list immediately.
func bind(station: Node, player: Node) -> void:
	_station = station
	_player = player
	refresh_cam_list()
	_apply_allow_add()

func refresh_cam_list() -> void:
	if _cam_list == null:
		return
	_cam_list.clear()
	var cams: Array = []
	if _station != null and "pre_added_cams" in _station:
		cams = _station.pre_added_cams
	for c in cams:
		_cam_list.add_item(String(c))

func _apply_allow_add() -> void:
	var allow: bool = true
	if _station != null and "allow_add" in _station:
		allow = bool(_station.allow_add)
	_add_row.visible = allow

func _on_cam_selected(idx: int) -> void:
	if _station == null or not "pre_added_cams" in _station:
		return
	var cams: Array = _station.pre_added_cams
	if idx < 0 or idx >= cams.size():
		return
	_switch_to(String(cams[idx]))

func _on_add_pressed() -> void:
	if _station == null or not bool(_station.get("allow_add")):
		return
	var raw: String = _add_input.text.strip_edges()
	if raw == "" or not _is_alnum(raw):
		return
	var cams: Array = _station.pre_added_cams
	if not cams.has(raw):
		cams.append(raw)
		_station.pre_added_cams = cams
		_cam_list.add_item(raw)
	_add_input.text = ""
	_switch_to(raw)

func _switch_to(cam_id: String) -> void:
	var found: Node = null
	for c in get_tree().get_nodes_in_group("cctv_camera"):
		if c == null:
			continue
		if String(c.get("cam_id")) == cam_id:
			found = c
			break
	if _active_cam != null and _active_cam.has_method("deactivate"):
		_active_cam.deactivate()
	_active_cam = found
	if found != null and found.has_method("activate"):
		found.activate()
		_status_label.text = "Feed: %s" % cam_id
		_no_feed_overlay.visible = false
		var ptz_on: bool = bool(found.get("ptz_enabled"))
		_ptz_hint.text = "PTZ: arrows + Z/X" if ptz_on else "PTZ disabled on this cam"
	else:
		_status_label.text = "No feed (cam_id %s not found)" % cam_id
		_no_feed_overlay.visible = true
		_ptz_hint.text = ""

func _process(delta: float) -> void:
	if _active_cam == null or not _active_cam.has_method("apply_ptz_delta"):
		return
	# Skip PTZ accumulation while the user is typing in the cam-id box,
	# otherwise the arrow keys would both move the caret AND tilt the cam.
	if _add_input != null and _add_input.has_focus():
		return
	var dyaw: float = 0.0
	var dpitch: float = 0.0
	var dfov: float = 0.0
	if Input.is_key_pressed(KEY_LEFT):
		dyaw += PTZ_YAW_RATE * delta
	if Input.is_key_pressed(KEY_RIGHT):
		dyaw -= PTZ_YAW_RATE * delta
	if Input.is_key_pressed(KEY_UP):
		dpitch += PTZ_PITCH_RATE * delta
	if Input.is_key_pressed(KEY_DOWN):
		dpitch -= PTZ_PITCH_RATE * delta
	if Input.is_key_pressed(KEY_Z):
		dfov -= PTZ_ZOOM_RATE * delta
	if Input.is_key_pressed(KEY_X):
		dfov += PTZ_ZOOM_RATE * delta
	if dyaw != 0.0 or dpitch != 0.0 or dfov != 0.0:
		_active_cam.apply_ptz_delta(dyaw, dpitch, dfov)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		# Only swallow F when no text field is focused, otherwise typing
		# 'f' into the add-cam box would dismount mid-keystroke.
		if _add_input != null and _add_input.has_focus():
			return
		if _station != null and _station.has_method("dismount"):
			_station.dismount()
		get_viewport().set_input_as_handled()

func teardown() -> void:
	if _active_cam != null and _active_cam.has_method("deactivate"):
		_active_cam.deactivate()
	_active_cam = null

func _is_alnum(s: String) -> bool:
	for ch in s:
		if not (ch.is_valid_int() or (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or ch == "_"):
			return false
	return true
