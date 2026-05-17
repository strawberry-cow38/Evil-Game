extends PanelContainer

# Side panel shown while the Fences tool is active. One control: post
# spacing along the run. Snap modifiers (alt = ignore all, shift = ignore
# hard) are keyboard-only and documented in the hint text.

signal post_spacing_changed(value: float)
signal variant_changed(name: String)
signal erase_mode_changed(enabled: bool)

const MIN_SPACING := 0.8
const MAX_SPACING := 6.0
const DEFAULT_SPACING := 2.36

# Display labels for each variant — must mirror the keys in
# editor_fences.gd VARIANTS. Order = display order in dropdown.
const VARIANT_OPTIONS: Array = [
	{"id": "picket",       "label": "White picket"},
	{"id": "tall_brown",   "label": "Tall brown board"},
	{"id": "log_vertical", "label": "Rustic log (vertical)"},
	{"id": "log_beam",     "label": "Rustic log (beam)"},
]

var _spacing_spin: SpinBox
var _variant_opt: OptionButton
var _erase_btn: CheckButton
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
	var vrow := HBoxContainer.new()
	vb.add_child(vrow)
	var vlbl := Label.new()
	vlbl.text = "Style"
	vlbl.custom_minimum_size = Vector2(90, 0)
	vrow.add_child(vlbl)
	_variant_opt = OptionButton.new()
	_variant_opt.custom_minimum_size = Vector2(110, 0)
	for opt in VARIANT_OPTIONS:
		_variant_opt.add_item(opt["label"])
	_variant_opt.select(0)
	_variant_opt.item_selected.connect(_on_variant_pick)
	vrow.add_child(_variant_opt)
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
	_erase_btn = CheckButton.new()
	_erase_btn.text = "Erase mode"
	_erase_btn.toggled.connect(_on_erase_toggled)
	vb.add_child(_erase_btn)
	var hint := Label.new()
	hint.text = "LMB drag to place a run.\nSnaps to existing posts + lines.\nShift = angle snap (15°).\nCtrl = distance snap (spacing).\nAlt = no snap.\nErase mode: LMB deletes one section."
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

func get_variant() -> String:
	return VARIANT_OPTIONS[_variant_opt.selected]["id"]

func set_variant(id: String) -> void:
	for i in range(VARIANT_OPTIONS.size()):
		if VARIANT_OPTIONS[i]["id"] == id:
			_suppress = true
			_variant_opt.select(i)
			_suppress = false
			return

func _on_variant_pick(idx: int) -> void:
	if _suppress:
		return
	variant_changed.emit(VARIANT_OPTIONS[idx]["id"])

func is_erase_mode() -> bool:
	return _erase_btn != null and _erase_btn.button_pressed

func _on_erase_toggled(on: bool) -> void:
	erase_mode_changed.emit(on)
