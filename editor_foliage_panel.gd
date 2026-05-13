extends PanelContainer

# Side panel shown while the Foliage tools are active. Drives brush
# density (instances per tick), footprint shape (circle/square), the
# material-filter lock (Any / Dirt / Grass / Stone / Sand) so the spray
# can avoid non-matching terrain, and the spray/exact mode toggle.

signal density_changed(per_tick: int)
signal shape_changed(shape: String)
signal material_filter_changed(mat_id: int)  # -1 = any, 0..3 = paint channel
signal mode_changed(mode: String)            # "spray" or "exact"

const MATERIALS: Array = [
	{"id": -1, "label": "Any",   "color": Color(0.40, 0.40, 0.40, 1.0)},
	{"id":  0, "label": "Dirt",  "color": Color(0.42, 0.30, 0.18, 1.0)},
	{"id":  1, "label": "Grass", "color": Color(0.32, 0.55, 0.20, 1.0)},
	{"id":  2, "label": "Stone", "color": Color(0.55, 0.55, 0.55, 1.0)},
	{"id":  3, "label": "Sand",  "color": Color(0.84, 0.78, 0.55, 1.0)},
]

var _mat_buttons: Array[Button] = []
var _shape_buttons: Dictionary = {}
var _mode_buttons: Dictionary = {}
var _density_slider: HSlider = null
var _density_label: Label = null
var _selected_mat: int = 1     # grass by default
var _selected_shape: String = "circle"
var _selected_mode: String = "spray"
var _density: int = 12

func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(240, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)

	var hdr := Label.new()
	hdr.text = "Foliage"
	vb.add_child(hdr)

	# Mode toggle: spray (R) / exact (W). Keys mirror the gizmo letters
	# users already know from the prop tools.
	var mode_lbl := Label.new()
	mode_lbl.text = "Mode  (R=spray, W=exact)"
	mode_lbl.modulate = Color(1, 1, 1, 0.7)
	vb.add_child(mode_lbl)
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 4)
	vb.add_child(mode_row)
	for m in ["spray", "exact"]:
		var b := Button.new()
		b.text = m.capitalize()
		b.custom_minimum_size = Vector2(96, 28)
		var mid: String = m
		b.pressed.connect(func(): _on_mode_picked(mid))
		mode_row.add_child(b)
		_mode_buttons[m] = b

	# Density (spray only — exact mode places one at a time so the
	# slider gets greyed but stays visible for orientation).
	var d_lbl := Label.new()
	d_lbl.text = "Spray density"
	d_lbl.modulate = Color(1, 1, 1, 0.7)
	vb.add_child(d_lbl)
	_density_label = Label.new()
	_density_label.text = "%d / tick" % _density
	vb.add_child(_density_label)
	_density_slider = HSlider.new()
	_density_slider.min_value = 1
	_density_slider.max_value = 40
	_density_slider.step = 1
	_density_slider.value = _density
	_density_slider.value_changed.connect(_on_density)
	vb.add_child(_density_slider)

	# Shape (circle/square) — square is handy for tight orthogonal tiles.
	var shape_lbl := Label.new()
	shape_lbl.text = "Brush shape"
	shape_lbl.modulate = Color(1, 1, 1, 0.7)
	vb.add_child(shape_lbl)
	var shape_row := HBoxContainer.new()
	shape_row.add_theme_constant_override("separation", 4)
	vb.add_child(shape_row)
	for s in ["circle", "square"]:
		var sb := Button.new()
		sb.text = s.capitalize()
		sb.custom_minimum_size = Vector2(96, 28)
		var sid: String = s
		sb.pressed.connect(func(): _on_shape_picked(sid))
		shape_row.add_child(sb)
		_shape_buttons[s] = sb

	# Material lock. Reads the terrain paint at each candidate sample
	# point; mat_id -1 means "no filter, spray everywhere".
	var mat_lbl := Label.new()
	mat_lbl.text = "Lock to material"
	mat_lbl.modulate = Color(1, 1, 1, 0.7)
	vb.add_child(mat_lbl)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	vb.add_child(grid)
	for m in MATERIALS:
		var b2 := Button.new()
		b2.text = m.label
		b2.custom_minimum_size = Vector2(108, 30)
		var sb2 := StyleBoxFlat.new()
		sb2.bg_color = m.color
		sb2.border_width_left = 2
		sb2.border_width_right = 2
		sb2.border_width_top = 2
		sb2.border_width_bottom = 2
		sb2.border_color = Color(0, 0, 0, 0.6)
		b2.add_theme_stylebox_override("normal", sb2)
		b2.add_theme_stylebox_override("hover", sb2)
		b2.add_theme_stylebox_override("pressed", sb2)
		b2.add_theme_color_override("font_color", Color(1, 1, 1, 1) if _luminance(m.color) < 0.55 else Color(0, 0, 0, 1))
		var mid_id: int = int(m.id)
		b2.pressed.connect(func(): _on_mat_picked(mid_id))
		grid.add_child(b2)
		_mat_buttons.append(b2)
	_refresh_highlight()

func _luminance(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b

func _on_mat_picked(mat_id: int) -> void:
	_selected_mat = mat_id
	_refresh_highlight()
	material_filter_changed.emit(mat_id)

func _on_shape_picked(s: String) -> void:
	_selected_shape = s
	_refresh_highlight()
	shape_changed.emit(s)

func _on_mode_picked(m: String) -> void:
	set_mode(m)

func set_mode(m: String) -> void:
	# Public so the R / W keyboard shortcuts can flip mode without
	# touching the panel internals.
	if m != "spray" and m != "exact":
		return
	_selected_mode = m
	_refresh_highlight()
	mode_changed.emit(m)

func _on_density(v: float) -> void:
	_density = int(v)
	if _density_label != null:
		_density_label.text = "%d / tick" % _density
	density_changed.emit(_density)

func _refresh_highlight() -> void:
	for i in range(_mat_buttons.size()):
		var want_id: int = int(MATERIALS[i].id)
		_mat_buttons[i].modulate = Color(1, 1, 1, 1) if want_id == _selected_mat else Color(0.7, 0.7, 0.7, 1)
	for k in _shape_buttons.keys():
		var btn: Button = _shape_buttons[k]
		btn.modulate = Color(1, 1, 1, 1) if k == _selected_shape else Color(0.7, 0.7, 0.7, 1)
	for k in _mode_buttons.keys():
		var btn2: Button = _mode_buttons[k]
		btn2.modulate = Color(1, 1, 1, 1) if k == _selected_mode else Color(0.7, 0.7, 0.7, 1)

func get_density() -> int:
	return _density

func get_shape() -> String:
	return _selected_shape

func get_material_filter() -> int:
	return _selected_mat

func get_mode() -> String:
	return _selected_mode
