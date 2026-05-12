extends PanelContainer

# Bottom-left snap settings. Translation snap pulls width from each
# object's AABB so there's nothing to expose; scale snaps to integer
# multiples of the start scale, again no setting. Only rotation needs a
# user-tunable step (some users want 5°/45°/90° etc).
#
# Visible whenever a placement tool is active (Objects, Effects).
# Holding Ctrl during a gizmo drag in editor.gd is what actually triggers
# snapping; this panel just publishes the angle.

signal rotation_snap_changed(deg: float)

var _rot_spin: SpinBox
var _rot_label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	add_child(vb)
	var hdr := Label.new()
	hdr.text = "Snap (Ctrl)"
	hdr.add_theme_font_size_override("font_size", 14)
	vb.add_child(hdr)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	vb.add_child(row)
	_rot_label = Label.new()
	_rot_label.text = "Rotate"
	_rot_label.custom_minimum_size = Vector2(58, 0)
	_rot_label.add_theme_font_size_override("font_size", 13)
	row.add_child(_rot_label)
	_rot_spin = SpinBox.new()
	_rot_spin.min_value = 1.0
	_rot_spin.max_value = 180.0
	_rot_spin.step = 1.0
	_rot_spin.value = 15.0
	_rot_spin.suffix = "°"
	_rot_spin.custom_minimum_size = Vector2(96, 0)
	_rot_spin.value_changed.connect(_on_rot_changed)
	row.add_child(_rot_spin)
	var hint := Label.new()
	hint.text = "Move = obj width\nScale = 1x/2x/3x"
	hint.modulate = Color(1, 1, 1, 0.55)
	hint.add_theme_font_size_override("font_size", 11)
	vb.add_child(hint)

func get_rotation_snap_deg() -> float:
	return _rot_spin.value

func _on_rot_changed(v: float) -> void:
	rotation_snap_changed.emit(v)
