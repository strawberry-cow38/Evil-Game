extends PanelContainer

# Side panel shown while the Fences tool is active. Controls:
#   - Style dropdown (variant)
#   - Post spacing SpinBox
#   - Erase mode CheckButton (LMB deletes one section)
#   - Edit mode CheckButton  (LMB selects one segment, opens tweak panel)
#   - Tweak sub-panel (visible only when a segment is selected) with
#     destructible / respawn time / wallbang controls.
# Erase + Edit are mutually exclusive — turning one on turns the other off.
# Snap modifiers (alt = ignore all, shift = angle, ctrl = distance) are
# keyboard-only and documented in the hint text.

signal post_spacing_changed(value: float)
signal variant_changed(name: String)
signal erase_mode_changed(enabled: bool)
signal edit_mode_changed(enabled: bool)
signal seg_destructible_changed(enabled: bool)
signal seg_respawn_changed(value: float)
signal seg_wallbang_changed(enabled: bool)

const MIN_SPACING := 0.8
const MAX_SPACING := 6.0
const DEFAULT_SPACING := 2.36

const MIN_RESPAWN := 0.5
const MAX_RESPAWN := 120.0
const DEFAULT_RESPAWN := 10.0

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
var _edit_btn: CheckButton
var _tweak_vbox: VBoxContainer
var _tweak_status: Label
var _destructible_btn: CheckButton
var _respawn_spin: SpinBox
var _wallbang_btn: CheckButton
var _suppress: bool = false

func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(260, 0)
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
	_variant_opt.custom_minimum_size = Vector2(140, 0)
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
	_spacing_spin.custom_minimum_size = Vector2(140, 0)
	_spacing_spin.value_changed.connect(_on_spin)
	row.add_child(_spacing_spin)
	_erase_btn = CheckButton.new()
	_erase_btn.text = "Erase mode"
	_erase_btn.toggled.connect(_on_erase_toggled)
	vb.add_child(_erase_btn)
	_edit_btn = CheckButton.new()
	_edit_btn.text = "Edit mode"
	_edit_btn.toggled.connect(_on_edit_toggled)
	vb.add_child(_edit_btn)
	_tweak_vbox = VBoxContainer.new()
	_tweak_vbox.add_theme_constant_override("separation", 4)
	_tweak_vbox.visible = false
	vb.add_child(_tweak_vbox)
	var tweak_header := Label.new()
	tweak_header.text = "Segment"
	tweak_header.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	_tweak_vbox.add_child(tweak_header)
	_tweak_status = Label.new()
	_tweak_status.text = "—"
	_tweak_status.modulate = Color(1, 1, 1, 0.6)
	_tweak_vbox.add_child(_tweak_status)
	_destructible_btn = CheckButton.new()
	_destructible_btn.text = "Destructible (pickets)"
	_destructible_btn.toggled.connect(_on_destructible_toggled)
	_tweak_vbox.add_child(_destructible_btn)
	var rrow := HBoxContainer.new()
	_tweak_vbox.add_child(rrow)
	var rlbl := Label.new()
	rlbl.text = "Respawn"
	rlbl.custom_minimum_size = Vector2(90, 0)
	rrow.add_child(rlbl)
	_respawn_spin = SpinBox.new()
	_respawn_spin.min_value = MIN_RESPAWN
	_respawn_spin.max_value = MAX_RESPAWN
	_respawn_spin.step = 0.5
	_respawn_spin.value = DEFAULT_RESPAWN
	_respawn_spin.suffix = "s"
	_respawn_spin.custom_minimum_size = Vector2(140, 0)
	_respawn_spin.value_changed.connect(_on_respawn_spin)
	rrow.add_child(_respawn_spin)
	_wallbang_btn = CheckButton.new()
	_wallbang_btn.text = "Allow wallbang"
	_wallbang_btn.toggled.connect(_on_wallbang_toggled)
	_tweak_vbox.add_child(_wallbang_btn)
	var hint := Label.new()
	hint.text = "LMB drag to place a run.\nSnaps to existing posts + pickets.\nShift = angle snap (15°).\nCtrl = distance snap (spacing).\nAlt = no snap.\nErase: LMB deletes one section.\nEdit: LMB selects a section."
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

func is_edit_mode() -> bool:
	return _edit_btn != null and _edit_btn.button_pressed

func _on_erase_toggled(on: bool) -> void:
	if on and _edit_btn != null and _edit_btn.button_pressed:
		_suppress = true
		_edit_btn.button_pressed = false
		_suppress = false
		edit_mode_changed.emit(false)
		hide_segment_panel()
	if _suppress:
		return
	erase_mode_changed.emit(on)

func _on_edit_toggled(on: bool) -> void:
	if on and _erase_btn != null and _erase_btn.button_pressed:
		_suppress = true
		_erase_btn.button_pressed = false
		_suppress = false
		erase_mode_changed.emit(false)
	if not on:
		hide_segment_panel()
	if _suppress:
		return
	edit_mode_changed.emit(on)

func show_segment_panel(props: Dictionary) -> void:
	_suppress = true
	_destructible_btn.button_pressed = bool(props.get("destructible", false))
	_respawn_spin.value = clampf(float(props.get("respawn_time", DEFAULT_RESPAWN)), MIN_RESPAWN, MAX_RESPAWN)
	_wallbang_btn.button_pressed = bool(props.get("wallbang", false))
	var fence_idx: int = int(props.get("fence", -1))
	var seg_idx: int = int(props.get("seg", -1))
	_tweak_status.text = "Fence %d  · Section %d" % [fence_idx, seg_idx]
	_tweak_vbox.visible = true
	_suppress = false

func hide_segment_panel() -> void:
	_tweak_vbox.visible = false

func _on_destructible_toggled(on: bool) -> void:
	if _suppress:
		return
	seg_destructible_changed.emit(on)

func _on_respawn_spin(v: float) -> void:
	if _suppress:
		return
	seg_respawn_changed.emit(v)

func _on_wallbang_toggled(on: bool) -> void:
	if _suppress:
		return
	seg_wallbang_changed.emit(on)
