extends PanelContainer

# Per-placement object settings. Shown when a placed object_box is
# selected. Toggles for No-Collide and Destructible, plus an HP spinbox
# that's disabled when destructible is off. Editor wires bind() on
# selection change and listens to the three signals to mirror the
# values back onto the selected box.

signal no_collide_changed(value: bool)
signal destructible_changed(value: bool)
signal hp_changed(value: int)
# Emitted when the user picks one of the named-events from the dropdown.
# event_id "" means the "(none)" entry — useful for jumping focus to the
# global events panel from here.
signal event_focused(event_id: String)

var _title: Label
var _no_collide_chk: CheckBox
var _destructible_chk: CheckBox
var _hp_spin: SpinBox
var _events_btn: OptionButton
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
	var ev_row := HBoxContainer.new()
	var ev_lbl := Label.new()
	ev_lbl.text = "Events"
	ev_lbl.custom_minimum_size = Vector2(80, 0)
	ev_row.add_child(ev_lbl)
	_events_btn = OptionButton.new()
	_events_btn.custom_minimum_size = Vector2(160, 0)
	_events_btn.item_selected.connect(func(idx: int):
		if _suppress:
			return
		event_focused.emit(String(_events_btn.get_item_metadata(idx))))
	ev_row.add_child(_events_btn)
	vb.add_child(ev_row)

func bind(label_text: String, no_collide: bool, destructible: bool, hp: int, events: Array = []) -> void:
	_suppress = true
	_title.text = label_text
	_no_collide_chk.button_pressed = no_collide
	_destructible_chk.button_pressed = destructible
	_hp_spin.value = hp
	_hp_spin.editable = destructible
	_events_btn.clear()
	if events.is_empty():
		_events_btn.add_item("(no events target this prop)")
		_events_btn.set_item_metadata(0, "")
		_events_btn.disabled = true
	else:
		_events_btn.disabled = false
		_events_btn.add_item("(%d event%s)" % [events.size(), "s" if events.size() != 1 else ""])
		_events_btn.set_item_metadata(0, "")
		for ev in events:
			_events_btn.add_item(String(ev.get("name", "?")))
			_events_btn.set_item_metadata(_events_btn.item_count - 1, String(ev.get("id", "")))
		_events_btn.select(0)
	_suppress = false
