extends PanelContainer

# Side panel shown while the Foliage tools are active. Drives brush
# density (instances per tick), footprint shape (circle/square), the
# material-filter lock (Any / Dirt / Grass / Stone / Sand) so the spray
# can avoid non-matching terrain, and the spray/exact mode toggle.

signal density_changed(per_tick: int)
signal shape_changed(shape: String)
signal material_filter_changed(mat_id: int)  # -1 = any, 0..3 = paint channel
signal mode_changed(mode: String)            # "spray" or "exact"
signal wind_changed(dir: Vector2, lo: float, hi: float, speed: float)
signal preset_changed(preset_id: String)

const MATERIALS: Array = [
	{"id": -1, "label": "Any",   "color": Color(0.40, 0.40, 0.40, 1.0)},
	{"id":  0, "label": "Dirt",  "color": Color(0.42, 0.30, 0.18, 1.0)},
	{"id":  1, "label": "Grass", "color": Color(0.32, 0.55, 0.20, 1.0)},
	{"id":  2, "label": "Stone", "color": Color(0.55, 0.55, 0.55, 1.0)},
	{"id":  3, "label": "Sand",  "color": Color(0.84, 0.78, 0.55, 1.0)},
]

# Preset list mirrors editor_foliage.gd PRESETS. Tile colour drives the
# button background so the picker reads at a glance.
const PRESETS: Array = [
	{"id": "short_green", "label": "Short Green", "color": Color(0.45, 0.70, 0.30, 1.0)},
	{"id": "long_green",  "label": "Long Green",  "color": Color(0.35, 0.60, 0.22, 1.0)},
	{"id": "short_brown", "label": "Short Brown", "color": Color(0.65, 0.50, 0.28, 1.0)},
	{"id": "long_brown",  "label": "Long Brown",  "color": Color(0.55, 0.40, 0.20, 1.0)},
	{"id": "short_sand",  "label": "Short Sand",  "color": Color(0.85, 0.78, 0.55, 1.0)},
	{"id": "long_sand",   "label": "Long Sand",   "color": Color(0.75, 0.68, 0.45, 1.0)},
	{"id": "shrub_round",  "label": "Round Shrub",  "color": Color(0.30, 0.55, 0.22, 1.0)},
	{"id": "clover_patch", "label": "Clover Patch", "color": Color(0.30, 0.62, 0.22, 1.0)},
	{"id": "daisy",        "label": "Daisy",        "color": Color(0.95, 0.92, 0.70, 1.0)},
]

var _mat_buttons: Array[Button] = []
var _preset_buttons: Array[Button] = []
var _shape_buttons: Dictionary = {}
var _mode_buttons: Dictionary = {}
var _density_slider: HSlider = null
var _density_label: Label = null
var _selected_mat: int = 1     # grass by default
var _selected_preset: String = "short_green"
var _selected_shape: String = "circle"
var _selected_mode: String = "spray"
var _density: int = 12
# Wind controls — driven by the bottom section of the panel. Sliders push
# wind_changed on every value tick so the field reacts live.
var _wind_dir_deg: float = 0.0
var _wind_min: float = 0.04
var _wind_max: float = 0.18
var _wind_speed: float = 1.8
var _wind_dir_slider: HSlider = null
var _wind_min_slider: HSlider = null
var _wind_max_slider: HSlider = null
var _wind_speed_slider: HSlider = null
var _wind_dir_label: Label = null
var _wind_min_label: Label = null
var _wind_max_label: Label = null
var _wind_speed_label: Label = null

func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(240, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)

	var hdr := Label.new()
	hdr.text = "Foliage"
	vb.add_child(hdr)

	# Preset picker — height + tint per blade. Each preset is its own
	# MultiMesh bucket on the foliage node, so saved maps remember which
	# variant was placed where.
	var p_lbl := Label.new()
	p_lbl.text = "Preset"
	p_lbl.modulate = Color(1, 1, 1, 0.7)
	vb.add_child(p_lbl)
	var p_grid := GridContainer.new()
	p_grid.columns = 2
	p_grid.add_theme_constant_override("h_separation", 4)
	p_grid.add_theme_constant_override("v_separation", 4)
	vb.add_child(p_grid)
	for p in PRESETS:
		var pb := Button.new()
		pb.text = p.label
		pb.custom_minimum_size = Vector2(108, 28)
		var sbp := StyleBoxFlat.new()
		sbp.bg_color = p.color
		sbp.border_width_left = 2
		sbp.border_width_right = 2
		sbp.border_width_top = 2
		sbp.border_width_bottom = 2
		sbp.border_color = Color(0, 0, 0, 0.6)
		pb.add_theme_stylebox_override("normal", sbp)
		pb.add_theme_stylebox_override("hover", sbp)
		pb.add_theme_stylebox_override("pressed", sbp)
		pb.add_theme_color_override("font_color", Color(1, 1, 1, 1) if _luminance(p.color) < 0.55 else Color(0, 0, 0, 1))
		var pid: String = String(p.id)
		pb.pressed.connect(func(): _on_preset_picked(pid))
		p_grid.add_child(pb)
		_preset_buttons.append(pb)

	# Mode toggle: spray (Q) / exact (W). Hold Shift while spraying to
	# remove inside a 50%-radius inner circle (visualised by a second
	# concentric ring on the brush).
	var mode_lbl := Label.new()
	mode_lbl.text = "Mode  (Q=spray, W=exact, Shift=remove inner)"
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

	# Wind section. Global feel — once tuned, the same numbers carry into
	# the play scene via MapState, so authoring + preview match.
	var wind_hdr := Label.new()
	wind_hdr.text = "Wind"
	wind_hdr.modulate = Color(1, 1, 0.7, 1.0)
	vb.add_child(wind_hdr)

	_wind_dir_label = Label.new()
	_wind_dir_label.modulate = Color(1, 1, 1, 0.7)
	vb.add_child(_wind_dir_label)
	_wind_dir_slider = HSlider.new()
	_wind_dir_slider.min_value = 0.0
	_wind_dir_slider.max_value = 360.0
	_wind_dir_slider.step = 1.0
	_wind_dir_slider.value = _wind_dir_deg
	_wind_dir_slider.value_changed.connect(_on_wind_dir)
	vb.add_child(_wind_dir_slider)

	_wind_min_label = Label.new()
	_wind_min_label.modulate = Color(1, 1, 1, 0.7)
	vb.add_child(_wind_min_label)
	_wind_min_slider = HSlider.new()
	_wind_min_slider.min_value = 0.0
	_wind_min_slider.max_value = 1.0
	_wind_min_slider.step = 0.01
	_wind_min_slider.value = _wind_min
	_wind_min_slider.value_changed.connect(_on_wind_min)
	vb.add_child(_wind_min_slider)

	_wind_max_label = Label.new()
	_wind_max_label.modulate = Color(1, 1, 1, 0.7)
	vb.add_child(_wind_max_label)
	_wind_max_slider = HSlider.new()
	_wind_max_slider.min_value = 0.0
	_wind_max_slider.max_value = 2.0
	_wind_max_slider.step = 0.01
	_wind_max_slider.value = _wind_max
	_wind_max_slider.value_changed.connect(_on_wind_max)
	vb.add_child(_wind_max_slider)

	_wind_speed_label = Label.new()
	_wind_speed_label.modulate = Color(1, 1, 1, 0.7)
	vb.add_child(_wind_speed_label)
	_wind_speed_slider = HSlider.new()
	_wind_speed_slider.min_value = 0.0
	_wind_speed_slider.max_value = 8.0
	_wind_speed_slider.step = 0.1
	_wind_speed_slider.value = _wind_speed
	_wind_speed_slider.value_changed.connect(_on_wind_speed)
	vb.add_child(_wind_speed_slider)
	_refresh_wind_labels()

func _refresh_wind_labels() -> void:
	if _wind_dir_label != null:
		_wind_dir_label.text = "Dir: %d°" % int(round(_wind_dir_deg))
	if _wind_min_label != null:
		_wind_min_label.text = "Calm sway: %.2f" % _wind_min
	if _wind_max_label != null:
		_wind_max_label.text = "Gust sway: %.2f" % _wind_max
	if _wind_speed_label != null:
		_wind_speed_label.text = "Speed: %.1f" % _wind_speed

func _on_wind_dir(v: float) -> void:
	_wind_dir_deg = v
	_refresh_wind_labels()
	_emit_wind()

func _on_wind_min(v: float) -> void:
	_wind_min = v
	# Keep max >= min so the lerp never inverts.
	if _wind_max < _wind_min:
		_wind_max = _wind_min
		if _wind_max_slider != null:
			_wind_max_slider.set_value_no_signal(_wind_max)
	_refresh_wind_labels()
	_emit_wind()

func _on_wind_max(v: float) -> void:
	_wind_max = max(v, _wind_min)
	if _wind_max_slider != null and v < _wind_min:
		_wind_max_slider.set_value_no_signal(_wind_max)
	_refresh_wind_labels()
	_emit_wind()

func _on_wind_speed(v: float) -> void:
	_wind_speed = v
	_refresh_wind_labels()
	_emit_wind()

func _emit_wind() -> void:
	var rad: float = deg_to_rad(_wind_dir_deg)
	wind_changed.emit(Vector2(cos(rad), sin(rad)), _wind_min, _wind_max, _wind_speed)

func set_wind(dir: Vector2, lo: float, hi: float, speed: float) -> void:
	# Used during state hydrate so opening the panel reflects the persisted
	# wind feel without a hand re-tune.
	var d: Vector2 = dir.normalized() if dir.length() > 0.0001 else Vector2(1, 0)
	_wind_dir_deg = rad_to_deg(atan2(d.y, d.x))
	if _wind_dir_deg < 0.0:
		_wind_dir_deg += 360.0
	_wind_min = lo
	_wind_max = max(hi, lo)
	_wind_speed = speed
	if _wind_dir_slider != null:
		_wind_dir_slider.set_value_no_signal(_wind_dir_deg)
		_wind_min_slider.set_value_no_signal(_wind_min)
		_wind_max_slider.set_value_no_signal(_wind_max)
		_wind_speed_slider.set_value_no_signal(_wind_speed)
	_refresh_wind_labels()

func _luminance(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b

func _on_mat_picked(mat_id: int) -> void:
	_selected_mat = mat_id
	_refresh_highlight()
	material_filter_changed.emit(mat_id)

func _on_preset_picked(pid: String) -> void:
	_selected_preset = pid
	_refresh_highlight()
	preset_changed.emit(pid)

func get_preset() -> String:
	return _selected_preset

func set_preset(pid: String) -> void:
	_selected_preset = pid
	_refresh_highlight()

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
	for i in range(_preset_buttons.size()):
		var want_pid: String = String(PRESETS[i].id)
		_preset_buttons[i].modulate = Color(1, 1, 1, 1) if want_pid == _selected_preset else Color(0.65, 0.65, 0.65, 1)
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
