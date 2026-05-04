extends PanelContainer

# Sky + sun tuning panel. Shown when Environment → Lighting is active.
# Holds the in-flight lighting dict (same keys main_bootstrap reads on
# play start) and emits `lighting_changed(state)` on every edit so the
# editor can apply changes live and snapshot into MapState at F9.

signal lighting_changed(state: Dictionary)

# Default state mirrors editor.tscn's WorldEnvironment + Sun so the
# panel sliders read as "current" on first open with no prior edits.
const DEFAULTS := {
	"sun_energy":      1.0,
	"sun_pitch_deg":   45.0,
	"sun_yaw_deg":     30.0,
	"sun_color":       Color(1, 0.97, 0.92, 1),
	"sky_energy":      1.0,
	"sky_top":         Color(0.38, 0.55, 0.85, 1),
	"sky_horizon":     Color(0.6, 0.7, 0.85, 1),
	"ambient_energy":  0.5,
	"ambient_color":   Color(0.6, 0.65, 0.7, 1),
}

var state: Dictionary = {}
var _suppress_signals: bool = false
var _rows: Dictionary = {}  # key → control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(280, 0)
	if state.is_empty():
		state = DEFAULTS.duplicate(true)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	add_child(vb)
	var title := Label.new()
	title.text = "Lighting"
	title.add_theme_font_size_override("font_size", 16)
	vb.add_child(title)
	_add_slider(vb, "sun_energy",     "Sun Energy",     0.0, 3.0, 0.05)
	_add_slider(vb, "sun_pitch_deg",  "Sun Pitch (°)",  5.0, 85.0, 1.0)
	_add_slider(vb, "sun_yaw_deg",    "Sun Yaw (°)",    -180.0, 180.0, 1.0)
	_add_color (vb, "sun_color",      "Sun Color")
	_add_sep(vb)
	_add_slider(vb, "sky_energy",     "Sky Energy",     0.0, 3.0, 0.05)
	_add_color (vb, "sky_top",        "Sky Top")
	_add_color (vb, "sky_horizon",    "Sky Horizon")
	_add_sep(vb)
	_add_slider(vb, "ambient_energy", "Ambient Energy", 0.0, 2.0, 0.05)
	_add_color (vb, "ambient_color",  "Ambient Color")
	_add_sep(vb)
	var reset := Button.new()
	reset.text = "Reset to Defaults"
	reset.pressed.connect(_on_reset)
	vb.add_child(reset)
	_refresh_controls()

func set_state(s: Dictionary) -> void:
	# Merge over defaults so partial dicts (older saves) still drive every
	# field. Avoid emitting while we sync controls — caller already has the
	# state.
	var merged: Dictionary = DEFAULTS.duplicate(true)
	for k in s.keys():
		merged[k] = s[k]
	state = merged
	_refresh_controls()

func _add_slider(parent: VBoxContainer, key: String, label: String, lo: float, hi: float, step: float) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(120, 0)
	row.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = lo
	spin.max_value = hi
	spin.step = step
	spin.custom_minimum_size = Vector2(140, 0)
	row.add_child(spin)
	spin.value_changed.connect(func(v: float): _on_value_changed(key, v))
	parent.add_child(row)
	_rows[key] = spin

func _add_color(parent: VBoxContainer, key: String, label: String) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(120, 0)
	row.add_child(lbl)
	var btn := ColorPickerButton.new()
	btn.edit_alpha = false
	btn.custom_minimum_size = Vector2(140, 24)
	row.add_child(btn)
	btn.color_changed.connect(func(c: Color): _on_value_changed(key, c))
	parent.add_child(row)
	_rows[key] = btn

func _add_sep(parent: VBoxContainer) -> void:
	var s := HSeparator.new()
	parent.add_child(s)

func _refresh_controls() -> void:
	_suppress_signals = true
	for key in _rows.keys():
		var ctrl: Control = _rows[key]
		var v = state.get(key, DEFAULTS[key])
		if ctrl is SpinBox:
			(ctrl as SpinBox).value = float(v)
		elif ctrl is ColorPickerButton:
			(ctrl as ColorPickerButton).color = v
	_suppress_signals = false

func _on_value_changed(key: String, value) -> void:
	if _suppress_signals:
		return
	state[key] = value
	lighting_changed.emit(state.duplicate(true))

func _on_reset() -> void:
	state = DEFAULTS.duplicate(true)
	_refresh_controls()
	lighting_changed.emit(state.duplicate(true))
