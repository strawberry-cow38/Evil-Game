extends PanelContainer

# Per-placement object settings. Shown when a placed object_box is
# selected. Toggles for No-Collide and Destructible, plus an HP spinbox
# that's disabled when destructible is off. Editor wires bind() on
# selection change and listens to the three signals to mirror the
# values back onto the selected box.

signal no_collide_changed(value: bool)
signal destructible_changed(value: bool)
signal hp_changed(value: int)

var _title: Label
var _no_collide_chk: CheckBox
var _destructible_chk: CheckBox
var _hp_spin: SpinBox
var _suppress: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(260, 0)
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

func bind(label_text: String, no_collide: bool, destructible: bool, hp: int) -> void:
	_suppress = true
	_title.text = label_text
	_no_collide_chk.button_pressed = no_collide
	_destructible_chk.button_pressed = destructible
	_hp_spin.value = hp
	_hp_spin.editable = destructible
	_suppress = false
