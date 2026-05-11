extends PanelContainer

# Side panel shown while the Roads tool is active. Exposes the per-node
# controls that don't fit into pure cursor/keyboard input: width spinner,
# ignore-terrain checkbox, per-road surface selector, and a stackable list
# of lane-marking decals.
#
# Decal model mirrors editor_roads.gd::DECAL_DEFAULT:
#   { offset (0..1 across road), width (m), color, dash_length, gap_length }

signal width_changed(value: float)
signal ignore_terrain_changed(value: bool)
signal surface_changed(surface_id: String)
signal decal_add_request(decal: Dictionary)
signal decal_remove_request(index: int)
signal decal_change_request(index: int, field: String, value)

var _label: Label
var _width_spin: SpinBox
var _ignore_check: CheckBox
var _surface_opt: OptionButton
var _surface_ids: PackedStringArray = PackedStringArray()  # index → id
var _decals_section: VBoxContainer
var _decal_rows_box: VBoxContainer
var _decal_presets_row: HBoxContainer
var _suppress: bool = false  # guard against feedback loops during refresh

func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(260, 0)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)
	_label = Label.new()
	_label.text = "Roads: nothing selected"
	vb.add_child(_label)
	var width_row := HBoxContainer.new()
	vb.add_child(width_row)
	var width_lbl := Label.new()
	width_lbl.text = "Width"
	width_lbl.custom_minimum_size = Vector2(60, 0)
	width_row.add_child(width_lbl)
	_width_spin = SpinBox.new()
	_width_spin.min_value = 1.0
	_width_spin.max_value = 20.0
	_width_spin.step = 0.5
	_width_spin.value = 6.0
	_width_spin.suffix = "m"
	_width_spin.custom_minimum_size = Vector2(120, 0)
	_width_spin.value_changed.connect(_on_width_spin)
	width_row.add_child(_width_spin)
	_ignore_check = CheckBox.new()
	_ignore_check.text = "Ignore terrain"
	_ignore_check.toggled.connect(_on_ignore_toggled)
	vb.add_child(_ignore_check)
	var surf_row := HBoxContainer.new()
	vb.add_child(surf_row)
	var surf_lbl := Label.new()
	surf_lbl.text = "Surface"
	surf_lbl.custom_minimum_size = Vector2(60, 0)
	surf_row.add_child(surf_lbl)
	_surface_opt = OptionButton.new()
	_surface_opt.custom_minimum_size = Vector2(140, 0)
	_surface_opt.item_selected.connect(_on_surface_selected)
	surf_row.add_child(_surface_opt)
	# Decals --------------------------------------------------------------
	_decals_section = VBoxContainer.new()
	_decals_section.add_theme_constant_override("separation", 4)
	vb.add_child(_decals_section)
	var sep := HSeparator.new()
	_decals_section.add_child(sep)
	var dec_hdr := Label.new()
	dec_hdr.text = "Lane decals"
	_decals_section.add_child(dec_hdr)
	_decal_presets_row = HBoxContainer.new()
	_decal_presets_row.add_theme_constant_override("separation", 4)
	_decals_section.add_child(_decal_presets_row)
	_add_preset_button("+ solid", _preset_solid_center)
	_add_preset_button("+ dashed", _preset_dashed_center)
	_add_preset_button("+ edges", _preset_edges)
	_add_preset_button("+ 2x yellow", _preset_double_yellow)
	_decal_rows_box = VBoxContainer.new()
	_decal_rows_box.add_theme_constant_override("separation", 4)
	_decals_section.add_child(_decal_rows_box)
	var hint := Label.new()
	hint.text = "[ / ] adjust width\nE grab • Del remove • RMB deselect"
	hint.modulate = Color(1, 1, 1, 0.6)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hint)

func _add_preset_button(label: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.pressed.connect(cb)
	_decal_presets_row.add_child(b)

# Called once from editor.gd right after instantiation with the surface
# palette pulled from editor_roads.gd.
func populate_surfaces(entries: Array) -> void:
	_suppress = true
	_surface_opt.clear()
	_surface_ids.clear()
	for e in entries:
		var id: String = String(e.get("id", ""))
		var label: String = String(e.get("label", id))
		_surface_opt.add_item(label)
		_surface_ids.append(id)
	_suppress = false

# Called by editor.gd whenever the road tool's state changes.
# Pass -1.0 for `width` to mark "no selection". `decals` is the live array
# from editor_roads.gd for the selected road (empty if no selection).
func refresh(width: float, ignore_terrain: bool, label_text: String, surface_id: String = "", decals: Array = []) -> void:
	_suppress = true
	_label.text = label_text
	var has_sel: bool = width >= 0.0
	_width_spin.editable = has_sel
	_ignore_check.disabled = not has_sel
	_surface_opt.disabled = not has_sel
	_decals_section.visible = has_sel
	if has_sel:
		_width_spin.value = width
		_ignore_check.button_pressed = ignore_terrain
		var idx: int = _surface_ids.find(surface_id)
		if idx >= 0:
			_surface_opt.select(idx)
		_rebuild_decal_rows(decals)
	_suppress = false

func _rebuild_decal_rows(decals: Array) -> void:
	for c in _decal_rows_box.get_children():
		c.queue_free()
	for i in range(decals.size()):
		_decal_rows_box.add_child(_build_decal_row(i, decals[i]))

func _build_decal_row(index: int, d: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var head := HBoxContainer.new()
	box.add_child(head)
	var tag := Label.new()
	tag.text = "#%d" % (index + 1)
	tag.custom_minimum_size = Vector2(30, 0)
	head.add_child(tag)
	var picker := ColorPickerButton.new()
	picker.color = d.get("color", Color(1, 1, 1, 1))
	picker.custom_minimum_size = Vector2(60, 0)
	picker.color_changed.connect(func(c): _emit_change(index, "color", c))
	head.add_child(picker)
	var rm := Button.new()
	rm.text = "x"
	rm.custom_minimum_size = Vector2(28, 0)
	rm.pressed.connect(func(): decal_remove_request.emit(index))
	head.add_child(rm)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 4)
	box.add_child(row1)
	_add_field(row1, "off", float(d.get("offset", 0.5)), 0.0, 1.0, 0.005, func(v): _emit_change(index, "offset", v))
	_add_field(row1, "w", float(d.get("width", 0.15)), 0.005, 2.0, 0.005, func(v): _emit_change(index, "width", v))
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 4)
	box.add_child(row2)
	_add_field(row2, "dash", float(d.get("dash_length", 0.0)), 0.0, 60.0, 0.05, func(v): _emit_change(index, "dash_length", v))
	_add_field(row2, "gap", float(d.get("gap_length", 0.0)), 0.0, 60.0, 0.05, func(v): _emit_change(index, "gap_length", v))
	var spacer := HSeparator.new()
	box.add_child(spacer)
	return box

func _add_field(parent: Control, label: String, value: float, mn: float, mx: float, step: float, cb: Callable) -> void:
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(28, 0)
	parent.add_child(l)
	var sb := SpinBox.new()
	sb.min_value = mn
	sb.max_value = mx
	sb.step = step
	sb.value = value
	sb.custom_minimum_size = Vector2(70, 0)
	sb.value_changed.connect(cb)
	parent.add_child(sb)

func _emit_change(index: int, field: String, value) -> void:
	if _suppress:
		return
	decal_change_request.emit(index, field, value)

# Preset callbacks — each one pushes one or more decal dicts onto the road.
# The editor.gd handler resolves preset requests into add_decal_to_selected
# calls; we just emit the dict(s) here so the panel stays UI-only.
func _preset_solid_center() -> void:
	decal_add_request.emit({"offset": 0.5, "width": 0.15, "color": Color(1, 1, 1, 1), "dash_length": 0.0, "gap_length": 0.0})

func _preset_dashed_center() -> void:
	decal_add_request.emit({"offset": 0.5, "width": 0.15, "color": Color(1, 1, 1, 1), "dash_length": 3.0, "gap_length": 6.0})

func _preset_edges() -> void:
	decal_add_request.emit({"offset": 0.05, "width": 0.15, "color": Color(1, 1, 1, 1), "dash_length": 0.0, "gap_length": 0.0})
	decal_add_request.emit({"offset": 0.95, "width": 0.15, "color": Color(1, 1, 1, 1), "dash_length": 0.0, "gap_length": 0.0})

func _preset_double_yellow() -> void:
	var yellow := Color(0.95, 0.78, 0.15, 1.0)
	decal_add_request.emit({"offset": 0.46, "width": 0.12, "color": yellow, "dash_length": 0.0, "gap_length": 0.0})
	decal_add_request.emit({"offset": 0.54, "width": 0.12, "color": yellow, "dash_length": 0.0, "gap_length": 0.0})

func _on_width_spin(v: float) -> void:
	if _suppress:
		return
	width_changed.emit(v)

func _on_ignore_toggled(pressed: bool) -> void:
	if _suppress:
		return
	ignore_terrain_changed.emit(pressed)

func _on_surface_selected(idx: int) -> void:
	if _suppress or idx < 0 or idx >= _surface_ids.size():
		return
	surface_changed.emit(_surface_ids[idx])
