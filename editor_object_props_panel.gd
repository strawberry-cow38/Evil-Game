extends PanelContainer

# Per-placement object settings. Shown when a placed object_box is
# selected. Always shows No-Collide / Destructible / HP / Events; for
# specific object types (computer station, CCTV cam) shows an extra
# block of type-specific fields below those.

signal no_collide_changed(value: bool)
signal destructible_changed(value: bool)
signal hp_changed(value: int)
signal frozen_changed(value: bool)
# Emitted when the user picks one of the named-events from the dropdown.
signal event_focused(event_id: String)
# Emitted whenever a type-specific field in the extras section changes.
# Carries the FULL fresh state dict for the current object_id; editor
# mirrors it onto the selected box without trying to diff.
signal object_state_changed(state: Dictionary)

var _title: Label
var _no_collide_chk: CheckBox
var _destructible_chk: CheckBox
var _frozen_chk: CheckBox
var _hp_spin: SpinBox
var _events_btn: OptionButton
var _suppress: bool = false

# Extras container — child widgets swap per object_id. Stored state is
# kept here so we can emit the whole dict on any sub-edit.
var _extras: VBoxContainer
var _extras_object_id: String = ""
var _extras_state: Dictionary = {}
# Cached widget refs for the active extras layout.
var _ex_allow_add_chk: CheckBox = null
var _ex_cam_list: ItemList = null
var _ex_cam_input: LineEdit = null
var _ex_cam_id_edit: LineEdit = null
var _ex_ptz_chk: CheckBox = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(280, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	add_child(vb)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 16)
	_title.text = "Object"
	vb.add_child(_title)
	_no_collide_chk = CheckBox.new()
	_no_collide_chk.text = "No Collide"
	_no_collide_chk.toggled.connect(func(v: bool):
		if not _suppress:
			no_collide_changed.emit(v))
	vb.add_child(_no_collide_chk)
	_destructible_chk = CheckBox.new()
	_destructible_chk.text = "Destructible"
	_destructible_chk.toggled.connect(func(v: bool):
		if not _suppress:
			destructible_changed.emit(v)
		_hp_spin.editable = v)
	vb.add_child(_destructible_chk)
	_frozen_chk = CheckBox.new()
	_frozen_chk.text = "Frozen (no physics)"
	_frozen_chk.toggled.connect(func(v: bool):
		if not _suppress:
			frozen_changed.emit(v))
	vb.add_child(_frozen_chk)
	var hp_row := HBoxContainer.new()
	var hp_lbl := Label.new()
	hp_lbl.text = "HP"
	hp_lbl.custom_minimum_size = Vector2(80, 0)
	hp_row.add_child(hp_lbl)
	_hp_spin = SpinBox.new()
	_hp_spin.min_value = 1
	_hp_spin.max_value = 100000
	_hp_spin.step = 1
	_hp_spin.value = 100
	_hp_spin.editable = false
	_hp_spin.custom_minimum_size = Vector2(140, 0)
	_hp_spin.value_changed.connect(func(v: float):
		if not _suppress:
			hp_changed.emit(int(v)))
	hp_row.add_child(_hp_spin)
	vb.add_child(hp_row)
	var ev_row := HBoxContainer.new()
	var ev_lbl := Label.new()
	ev_lbl.text = "Events"
	ev_lbl.custom_minimum_size = Vector2(80, 0)
	ev_row.add_child(ev_lbl)
	_events_btn = OptionButton.new()
	_events_btn.custom_minimum_size = Vector2(160, 0)
	_events_btn.item_selected.connect(func(idx: int):
		if _suppress:
			return
		event_focused.emit(String(_events_btn.get_item_metadata(idx))))
	ev_row.add_child(_events_btn)
	vb.add_child(ev_row)
	_extras = VBoxContainer.new()
	_extras.add_theme_constant_override("separation", 4)
	vb.add_child(_extras)

func bind(label_text: String, no_collide: bool, destructible: bool, hp: int, events: Array = [], object_id: String = "", object_state: Dictionary = {}, frozen: bool = true) -> void:
	_suppress = true
	_title.text = label_text
	_no_collide_chk.button_pressed = no_collide
	_destructible_chk.button_pressed = destructible
	_frozen_chk.button_pressed = frozen
	_hp_spin.value = hp
	_hp_spin.editable = destructible
	_events_btn.clear()
	if events.is_empty():
		_events_btn.add_item("(no events target this prop)")
		_events_btn.set_item_metadata(0, "")
		_events_btn.disabled = true
	else:
		_events_btn.disabled = false
		_events_btn.add_item("(%d event%s)" % [events.size(), "s" if events.size() != 1 else ""])
		_events_btn.set_item_metadata(0, "")
		for ev in events:
			_events_btn.add_item(String(ev.get("name", "?")))
			_events_btn.set_item_metadata(_events_btn.item_count - 1, String(ev.get("id", "")))
		_events_btn.select(0)
	_rebuild_extras(object_id, object_state)
	_suppress = false

func _rebuild_extras(object_id: String, state: Dictionary) -> void:
	# Tear down whatever extras layout the previous selection used and
	# build the one matching the new object_id. Widgets cached at the
	# top of the file are reset to null when not used so we never
	# accidentally read a stale reference from the previous prop.
	for c in _extras.get_children():
		c.queue_free()
	_ex_allow_add_chk = null
	_ex_cam_list = null
	_ex_cam_input = null
	_ex_cam_id_edit = null
	_ex_ptz_chk = null
	_extras_object_id = object_id
	_extras_state = state.duplicate(true)
	match object_id:
		"obj_computer_station":
			_build_station_extras()
		"obj_cctv_camera":
			_build_camera_extras()
		"obj_glass_sheet":
			_build_glass_extras()

func _emit_state() -> void:
	if _suppress:
		return
	object_state_changed.emit(_extras_state.duplicate(true))

func _build_station_extras() -> void:
	var hdr := Label.new()
	hdr.text = "Computer Station"
	hdr.add_theme_font_size_override("font_size", 14)
	_extras.add_child(hdr)
	_ex_allow_add_chk = CheckBox.new()
	_ex_allow_add_chk.text = "Allow Add Cams (at runtime)"
	_ex_allow_add_chk.button_pressed = bool(_extras_state.get("allow_add", true))
	_ex_allow_add_chk.toggled.connect(func(v: bool):
		_extras_state["allow_add"] = v
		_emit_state())
	_extras.add_child(_ex_allow_add_chk)
	var lbl := Label.new()
	lbl.text = "Pre-added Cam IDs:"
	_extras.add_child(lbl)
	_ex_cam_list = ItemList.new()
	_ex_cam_list.custom_minimum_size = Vector2(0, 120)
	_ex_cam_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cams: Array = _extras_state.get("pre_added_cams", [])
	for c in cams:
		_ex_cam_list.add_item(String(c))
	_extras.add_child(_ex_cam_list)
	var row := HBoxContainer.new()
	_ex_cam_input = LineEdit.new()
	_ex_cam_input.placeholder_text = "cam_id (alnum)"
	_ex_cam_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_ex_cam_input)
	var add_btn := Button.new()
	add_btn.text = "Add"
	add_btn.pressed.connect(_on_station_add_cam_pressed)
	row.add_child(add_btn)
	var rm_btn := Button.new()
	rm_btn.text = "Remove"
	rm_btn.pressed.connect(_on_station_remove_cam_pressed)
	row.add_child(rm_btn)
	_extras.add_child(row)

func _on_station_add_cam_pressed() -> void:
	if _ex_cam_input == null or _ex_cam_list == null:
		return
	var raw: String = _ex_cam_input.text.strip_edges()
	if raw == "" or not raw.is_valid_identifier() and not _is_alnum(raw):
		return
	var cams: Array = _extras_state.get("pre_added_cams", [])
	if cams.has(raw):
		return
	cams.append(raw)
	_extras_state["pre_added_cams"] = cams
	_ex_cam_list.add_item(raw)
	_ex_cam_input.text = ""
	_emit_state()

func _on_station_remove_cam_pressed() -> void:
	if _ex_cam_list == null:
		return
	var sel: PackedInt32Array = _ex_cam_list.get_selected_items()
	if sel.is_empty():
		return
	var idx: int = sel[0]
	var cams: Array = _extras_state.get("pre_added_cams", [])
	if idx >= 0 and idx < cams.size():
		cams.remove_at(idx)
		_extras_state["pre_added_cams"] = cams
		_ex_cam_list.remove_item(idx)
		_emit_state()

func _build_camera_extras() -> void:
	var hdr := Label.new()
	hdr.text = "CCTV Camera"
	hdr.add_theme_font_size_override("font_size", 14)
	_extras.add_child(hdr)
	var id_row := HBoxContainer.new()
	var id_lbl := Label.new()
	id_lbl.text = "Cam ID"
	id_lbl.custom_minimum_size = Vector2(80, 0)
	id_row.add_child(id_lbl)
	_ex_cam_id_edit = LineEdit.new()
	_ex_cam_id_edit.placeholder_text = "alnum id"
	_ex_cam_id_edit.text = String(_extras_state.get("cam_id", ""))
	_ex_cam_id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ex_cam_id_edit.text_changed.connect(func(t: String):
		_extras_state["cam_id"] = t.strip_edges()
		_emit_state())
	id_row.add_child(_ex_cam_id_edit)
	_extras.add_child(id_row)
	_ex_ptz_chk = CheckBox.new()
	_ex_ptz_chk.text = "Pan/Tilt/Zoom enabled"
	_ex_ptz_chk.button_pressed = bool(_extras_state.get("ptz_enabled", false))
	_ex_ptz_chk.toggled.connect(func(v: bool):
		_extras_state["ptz_enabled"] = v
		_emit_state())
	_extras.add_child(_ex_ptz_chk)

func _build_glass_extras() -> void:
	var hdr := Label.new()
	hdr.text = "Glass Sheet"
	hdr.add_theme_font_size_override("font_size", 14)
	_extras.add_child(hdr)
	# Variant — fancy (refractive PBR + clearcoat) or cheap (alpha only).
	var var_row := HBoxContainer.new()
	var var_lbl := Label.new()
	var_lbl.text = "Variant"
	var_lbl.custom_minimum_size = Vector2(80, 0)
	var_row.add_child(var_lbl)
	var var_btn := OptionButton.new()
	var_btn.add_item("Fancy (refractive)", 0)
	var_btn.add_item("Cheap (alpha)", 1)
	var current_variant: String = String(_extras_state.get("variant", "fancy"))
	var_btn.select(0 if current_variant == "fancy" else 1)
	var_btn.item_selected.connect(func(idx: int):
		_extras_state["variant"] = "fancy" if idx == 0 else "cheap"
		_emit_state())
	var_row.add_child(var_btn)
	_extras.add_child(var_row)
	# Tint — RGBA. ColorPickerButton handles its own popup.
	var tint_row := HBoxContainer.new()
	var tint_lbl := Label.new()
	tint_lbl.text = "Tint"
	tint_lbl.custom_minimum_size = Vector2(80, 0)
	tint_row.add_child(tint_lbl)
	var cpb := ColorPickerButton.new()
	cpb.color = _extras_state.get("tint", Color(0.75, 0.88, 0.95, 0.35))
	cpb.edit_alpha = true
	cpb.custom_minimum_size = Vector2(120, 0)
	cpb.color_changed.connect(func(c: Color):
		_extras_state["tint"] = c
		_emit_state())
	tint_row.add_child(cpb)
	_extras.add_child(tint_row)
	# Frosted toggle — bumps roughness, scales refraction for diffuse look.
	var frost := CheckBox.new()
	frost.text = "Frosted"
	frost.button_pressed = bool(_extras_state.get("frosted", false))
	frost.toggled.connect(func(v: bool):
		_extras_state["frosted"] = v
		_emit_state())
	_extras.add_child(frost)

func _is_alnum(s: String) -> bool:
	for ch in s:
		if not (ch.is_valid_int() or _is_letter(ch) or ch == "_"):
			return false
	return true

func _is_letter(ch: String) -> bool:
	return (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z")
