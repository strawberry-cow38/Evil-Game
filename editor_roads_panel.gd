extends PanelContainer

# Side panel shown while the Roads tool is active. Exposes the per-node
# controls that don't fit into pure cursor/keyboard input: width spinner
# and an ignore-terrain checkbox. Read-only when nothing is selected.

signal width_changed(value: float)
signal ignore_terrain_changed(value: bool)
signal surface_changed(surface_id: String)

var _label: Label
var _width_spin: SpinBox
var _ignore_check: CheckBox
var _surface_opt: OptionButton
var _surface_ids: PackedStringArray = PackedStringArray()  # index → id
var _suppress: bool = false  # guard against feedback loops during refresh

func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(220, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
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
	var hint := Label.new()
	hint.text = "[ / ] adjust width\nE grab • Del remove • RMB deselect"
	hint.modulate = Color(1, 1, 1, 0.6)
	vb.add_child(hint)

# Called once from editor.gd right after instantiation with the surface
# palette pulled from editor_roads.gd. We keep the id list locally so
# item_selected (which gives us an index) can be mapped back to an id.
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

# Called by editor.gd whenever the road tool's state changes (selection
# or per-node mutation). Pass -1.0 for `width` to mark "no selection".
func refresh(width: float, ignore_terrain: bool, label_text: String, surface_id: String = "") -> void:
	_suppress = true
	_label.text = label_text
	var has_sel: bool = width >= 0.0
	_width_spin.editable = has_sel
	_ignore_check.disabled = not has_sel
	_surface_opt.disabled = not has_sel
	if has_sel:
		_width_spin.value = width
		_ignore_check.button_pressed = ignore_terrain
		var idx: int = _surface_ids.find(surface_id)
		if idx >= 0:
			_surface_opt.select(idx)
	_suppress = false

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
