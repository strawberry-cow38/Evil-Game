extends PanelContainer

# Per-trigger settings. Shown when a placed editor_trigger_box is
# selected. Edits conditions, logic op, the event ids it fires, delays,
# and repeat settings. Pushes a single trigger_changed signal back up so
# editor.gd can copy the values onto the selected box.
#
# Condition row shape:
#   { "type": "player_in",                 # player_in | item_count | actor_count
#     "filter_id": "",                     # item/actor table id when applicable
#     "min_count": 1,                      # used by item_count / actor_count
#     "negate": false }

signal trigger_changed

const CONDITION_TYPES: Array = [
	{"id": "player_in",   "label": "Player in zone"},
	{"id": "item_count",  "label": "Items in zone (≥N, filtered)"},
	{"id": "actor_count", "label": "Actors in zone (≥N, filtered)"},
]

const LOGIC_OPS: Array = [
	{"id": "and", "label": "ALL (AND)"},
	{"id": "or",  "label": "ANY (OR)"},
	{"id": "xor", "label": "EXACTLY ONE (XOR)"},
]

const REPEAT_MODES: Array = [
	{"id": "once",     "label": "Once"},
	{"id": "n",        "label": "N times"},
	{"id": "infinite", "label": "Infinite"},
]

var _title: Label
var _cond_box: VBoxContainer
var _logic_btn: OptionButton
var _fire_box: VBoxContainer
var _delay_spin: SpinBox
var _between_spin: SpinBox
var _repeat_btn: OptionButton
var _repeat_count_spin: SpinBox
var _cooldown_spin: SpinBox
var _bound_box: Node = null
var _events_source: Node = null  # editor_events_panel; we read its events list
var _item_tables: Array = []
var _actor_tables: Array = []
var _suppress: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(320, 0)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320, 520)
	add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)
	_title = Label.new()
	_title.text = "Trigger"
	_title.add_theme_font_size_override("font_size", 16)
	vb.add_child(_title)
	var cond_hdr := Label.new()
	cond_hdr.text = "Conditions"
	vb.add_child(cond_hdr)
	_cond_box = VBoxContainer.new()
	_cond_box.add_theme_constant_override("separation", 2)
	vb.add_child(_cond_box)
	var add_cond := Button.new()
	add_cond.text = "+ Add Condition"
	add_cond.pressed.connect(_on_add_condition)
	vb.add_child(add_cond)
	var logic_row := HBoxContainer.new()
	logic_row.add_child(_label("Combine"))
	_logic_btn = OptionButton.new()
	for op in LOGIC_OPS:
		_logic_btn.add_item(String(op.label))
		_logic_btn.set_item_metadata(_logic_btn.item_count - 1, String(op.id))
	_logic_btn.item_selected.connect(func(_i): _push_change())
	logic_row.add_child(_logic_btn)
	vb.add_child(logic_row)
	var fire_hdr := Label.new()
	fire_hdr.text = "Fires Events"
	vb.add_child(fire_hdr)
	_fire_box = VBoxContainer.new()
	_fire_box.add_theme_constant_override("separation", 2)
	vb.add_child(_fire_box)
	var delay_row := HBoxContainer.new()
	delay_row.add_child(_label("Delay (s)"))
	_delay_spin = _spin(0.0, 600.0, 0.05, 0.0)
	_delay_spin.value_changed.connect(func(_v): _push_change())
	delay_row.add_child(_delay_spin)
	vb.add_child(delay_row)
	var between_row := HBoxContainer.new()
	between_row.add_child(_label("Between (s)"))
	_between_spin = _spin(0.0, 60.0, 0.05, 0.0)
	_between_spin.value_changed.connect(func(_v): _push_change())
	between_row.add_child(_between_spin)
	vb.add_child(between_row)
	var rep_row := HBoxContainer.new()
	rep_row.add_child(_label("Repeat"))
	_repeat_btn = OptionButton.new()
	for m in REPEAT_MODES:
		_repeat_btn.add_item(String(m.label))
		_repeat_btn.set_item_metadata(_repeat_btn.item_count - 1, String(m.id))
	_repeat_btn.item_selected.connect(func(_i): _push_change())
	rep_row.add_child(_repeat_btn)
	vb.add_child(rep_row)
	var rep_n_row := HBoxContainer.new()
	rep_n_row.add_child(_label("Count"))
	_repeat_count_spin = _spin(1.0, 999.0, 1.0, 1.0)
	_repeat_count_spin.value_changed.connect(func(_v): _push_change())
	rep_n_row.add_child(_repeat_count_spin)
	vb.add_child(rep_n_row)
	var cd_row := HBoxContainer.new()
	cd_row.add_child(_label("Cooldown (s)"))
	_cooldown_spin = _spin(0.0, 600.0, 0.05, 1.0)
	_cooldown_spin.value_changed.connect(func(_v): _push_change())
	cd_row.add_child(_cooldown_spin)
	vb.add_child(cd_row)

func set_events_source(panel: Node) -> void:
	_events_source = panel

func set_item_tables(arr: Array) -> void:
	_item_tables = arr.duplicate(true)
	_rebuild_conditions()

func set_actor_tables(arr: Array) -> void:
	_actor_tables = arr.duplicate(true)
	_rebuild_conditions()

func bind(box: Node) -> void:
	_bound_box = box
	if box == null:
		return
	_suppress = true
	_title.text = "Trigger: %s" % String(box.prop_id).substr(0, 12)
	_select_option(_logic_btn, String(box.logic_op))
	_delay_spin.value = float(box.delay)
	_between_spin.value = float(box.inter_event_delay)
	_select_option(_repeat_btn, String(box.repeat_mode))
	_repeat_count_spin.value = float(box.repeat_count)
	_cooldown_spin.value = float(box.repeat_cooldown)
	_rebuild_conditions()
	_rebuild_fire_list()
	_suppress = false

func refresh_events() -> void:
	_rebuild_fire_list()

func _rebuild_conditions() -> void:
	for c in _cond_box.get_children():
		c.queue_free()
	if _bound_box == null:
		return
	for i in range(_bound_box.conditions.size()):
		var cond: Dictionary = _bound_box.conditions[i]
		_cond_box.add_child(_build_cond_row(cond, i))

func _rebuild_fire_list() -> void:
	for c in _fire_box.get_children():
		c.queue_free()
	if _bound_box == null or _events_source == null:
		return
	var events: Array = _events_source.events
	if events.is_empty():
		var none := Label.new()
		none.text = "(no events yet — add one in the Events panel)"
		none.modulate = Color(1, 1, 1, 0.55)
		_fire_box.add_child(none)
		return
	for ev in events:
		var row := CheckBox.new()
		row.text = String(ev.get("name", ""))
		row.button_pressed = _bound_box.fire_event_ids.has(String(ev.get("id", "")))
		var eid: String = String(ev.get("id", ""))
		row.toggled.connect(func(v: bool):
			if _suppress:
				return
			if v and not _bound_box.fire_event_ids.has(eid):
				_bound_box.fire_event_ids.append(eid)
			elif not v:
				_bound_box.fire_event_ids.erase(eid)
			trigger_changed.emit())
		_fire_box.add_child(row)

func _on_add_condition() -> void:
	if _bound_box == null:
		return
	_bound_box.conditions.append({
		"type": "player_in",
		"filter_id": "",
		"min_count": 1,
		"negate": false,
	})
	_rebuild_conditions()
	trigger_changed.emit()

func _build_cond_row(cond: Dictionary, idx: int) -> Control:
	var pc := PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	pc.add_child(vb)
	var top := HBoxContainer.new()
	var type_btn := OptionButton.new()
	for t in CONDITION_TYPES:
		type_btn.add_item(String(t.label))
		type_btn.set_item_metadata(type_btn.item_count - 1, String(t.id))
	_select_option(type_btn, String(cond.get("type", "player_in")))
	type_btn.item_selected.connect(func(i: int):
		cond["type"] = String(type_btn.get_item_metadata(i))
		_rebuild_conditions()
		trigger_changed.emit())
	top.add_child(type_btn)
	var neg := CheckBox.new()
	neg.text = "NOT"
	neg.button_pressed = bool(cond.get("negate", false))
	neg.toggled.connect(func(v: bool):
		cond["negate"] = v
		trigger_changed.emit())
	top.add_child(neg)
	var del := Button.new()
	del.text = "X"
	del.custom_minimum_size = Vector2(28, 0)
	del.pressed.connect(func():
		_bound_box.conditions.remove_at(idx)
		_rebuild_conditions()
		trigger_changed.emit())
	top.add_child(del)
	vb.add_child(top)
	var ctype: String = String(cond.get("type", "player_in"))
	if ctype == "item_count" or ctype == "actor_count":
		var f_row := HBoxContainer.new()
		f_row.add_child(_label("Filter"))
		var filter_btn := OptionButton.new()
		filter_btn.add_item("(any)")
		filter_btn.set_item_metadata(0, "")
		var src: Array = _item_tables if ctype == "item_count" else _actor_tables
		for t in src:
			filter_btn.add_item(String(t.get("name", t.get("id", "?"))))
			filter_btn.set_item_metadata(filter_btn.item_count - 1, String(t.get("id", "")))
		_select_option(filter_btn, String(cond.get("filter_id", "")))
		filter_btn.item_selected.connect(func(i: int):
			cond["filter_id"] = String(filter_btn.get_item_metadata(i))
			trigger_changed.emit())
		f_row.add_child(filter_btn)
		vb.add_child(f_row)
		var n_row := HBoxContainer.new()
		n_row.add_child(_label("Min Count"))
		var n_spin := _spin(1.0, 999.0, 1.0, float(cond.get("min_count", 1)))
		n_spin.value_changed.connect(func(v: float):
			cond["min_count"] = int(v)
			trigger_changed.emit())
		n_row.add_child(n_spin)
		vb.add_child(n_row)
	return pc

func _push_change() -> void:
	if _suppress or _bound_box == null:
		return
	_bound_box.logic_op = String(_logic_btn.get_item_metadata(_logic_btn.selected))
	_bound_box.delay = float(_delay_spin.value)
	_bound_box.inter_event_delay = float(_between_spin.value)
	_bound_box.repeat_mode = String(_repeat_btn.get_item_metadata(_repeat_btn.selected))
	_bound_box.repeat_count = int(_repeat_count_spin.value)
	_bound_box.repeat_cooldown = float(_cooldown_spin.value)
	trigger_changed.emit()

func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.custom_minimum_size = Vector2(90, 0)
	return l

func _spin(lo: float, hi: float, step: float, v: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = v
	s.custom_minimum_size = Vector2(110, 0)
	return s

func _select_option(opt: OptionButton, id: String) -> void:
	for i in range(opt.item_count):
		if String(opt.get_item_metadata(i)) == id:
			opt.select(i)
			return
	if opt.item_count > 0:
		opt.select(0)
