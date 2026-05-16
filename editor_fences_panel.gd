extends PanelContainer

# Side panel shown while the Fences tool is active. One control: post
# spacing along the run. Snap modifiers (alt = ignore all, shift = ignore
# hard) are keyboard-only and documented in the hint text.

signal post_spacing_changed(value: float)

const MIN_SPACING := 0.8
const MAX_SPACING := 6.0
const DEFAULT_SPACING := 2.36

var _spacing_spin: SpinBox
var _suppress: bool = false

func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(240, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	var header := Label.new()
	header.text = "Fences"
	vb.add_child(header)
	var row := HBoxContainer.new()
	vb.add_child(row)
	var lbl := Label.new()
	lbl.text = "Post spacing"
	lbl.custom_minimum_size = Vector2(90, 0)
	row.add_child(lbl)
	_spacing_spin = SpinBox.new()
	_spacing_spin.min_value = MIN_SPACING
	_spacing_spin.max_value = MAX_SPACING
	_spacing_spin.step = 0.04
	_spacing_spin.value = DEFAULT_SPACING
	_spacing_spin.suffix = "m"
	_spacing_spin.custom_minimum_size = Vector2(110, 0)
	_spacing_spin.value_changed.connect(_on_spin)
	row.add_child(_spacing_spin)
	var hint := Label.new()
	hint.text = "LMB drag to place a run.\nSnaps to nearest post.\nShift = no post snap.\nAlt = no snap at all.\nRMB / Esc to cancel."
	hint.modulate = Color(1, 1, 1, 0.65)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hint)

func get_post_spacing() -> float:
	return _spacing_spin.value

func set_post_spacing(v: float) -> void:
	_suppress = true
	_spacing_spin.value = clampf(v, MIN_SPACING, MAX_SPACING)
	_suppress = false

func _on_spin(v: float) -> void:
	if _suppress:
		return
	post_spacing_changed.emit(v)
