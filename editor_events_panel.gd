extends PanelContainer

# Global named-events list. Lives in the Level → Triggers workflow but is
# its own panel so it can stay open while the user is editing a trigger
# or a prop. Each event has: id, name, kind ("destroy" for now), targets
# (Array[String] of prop_ids). The eyedropper toggle is per-event — when
# armed, clicks on placed props in the viewport add to that event's
# target list. Hovering an event row emits target_hover with the id list
# so the editor can tint those props.

signal events_changed
signal eyedropper_armed(event_id: String)
signal eyedropper_disarmed
signal target_hover(event_id: String)
signal target_unhover

const KINDS: Array = [
	{"id": "destroy", "label": "Destroy"},
]

var events: Array = []  # Array[Dictionary]
var _list: VBoxContainer
var _eyedropper_event_id: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(320, 0)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)
	var hdr := Label.new()
	hdr.text = "Events"
	hdr.add_theme_font_size_override("font_size", 16)
	outer.add_child(hdr)
	var add_btn := Button.new()
	add_btn.text = "+ New Event"
	add_btn.pressed.connect(_on_add_event)
	outer.add_child(add_btn)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 320)
	outer.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_refresh()

func set_events(arr: Array) -> void:
	events = arr.duplicate(true)
	_refresh()

func get_eyedropper_event_id() -> String:
	return _eyedropper_event_id

func add_target_to_armed(prop_id: String) -> void:
	if _eyedropper_event_id == "":
		return
	var ev: Dictionary = _find_event(_eyedropper_event_id)
	if ev.is_empty():
		return
	var targets: Array = ev.get("targets", [])
	if not targets.has(prop_id):
		targets.append(prop_id)
		ev["targets"] = targets
		events_changed.emit()
		_refresh()

# Returns the names of all events that target the given prop_id (so the
# object props panel can show a dropdown).
func events_for_prop(prop_id: String) -> Array:
	var out: Array = []
	for ev in events:
		var targets: Array = ev.get("targets", [])
		if targets.has(prop_id):
			out.append({"id": String(ev.get("id", "")), "name": String(ev.get("name", ""))})
	return out

func _on_add_event() -> void:
	var ev := {
		"id": "ev_%d_%d" % [Time.get_ticks_usec(), randi()],
		"name": "event_%d" % (events.size() + 1),
		"kind": "destroy",
		"targets": [],
	}
	events.append(ev)
	events_changed.emit()
	_refresh()

func _find_event(eid: String) -> Dictionary:
	for ev in events:
		if String(ev.get("id", "")) == eid:
			return ev
	return {}

func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	for ev in events:
		_list.add_child(_build_row(ev))

func _build_row(ev: Dictionary) -> Control:
	var row := PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	row.add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	vb.add_child(top)
	var name_edit := LineEdit.new()
	name_edit.text = String(ev.get("name", ""))
	name_edit.custom_minimum_size = Vector2(140, 0)
	name_edit.text_changed.connect(func(t: String):
		ev["name"] = t
		events_changed.emit())
	top.add_child(name_edit)
	var kind_btn := OptionButton.new()
	for k in KINDS:
		kind_btn.add_item(String(k.label))
		kind_btn.set_item_metadata(kind_btn.item_count - 1, String(k.id))
	for i in range(kind_btn.item_count):
		if kind_btn.get_item_metadata(i) == String(ev.get("kind", "destroy")):
			kind_btn.select(i)
			break
	kind_btn.item_selected.connect(func(idx: int):
		ev["kind"] = String(kind_btn.get_item_metadata(idx))
		events_changed.emit())
	top.add_child(kind_btn)
	var del := Button.new()
	del.text = "X"
	del.custom_minimum_size = Vector2(28, 0)
	del.pressed.connect(func():
		events.erase(ev)
		if _eyedropper_event_id == String(ev.get("id", "")):
			_eyedropper_event_id = ""
			eyedropper_disarmed.emit()
		events_changed.emit()
		_refresh())
	top.add_child(del)
	var bot := HBoxContainer.new()
	bot.add_theme_constant_override("separation", 4)
	vb.add_child(bot)
	var eye := CheckBox.new()
	eye.text = "Eyedropper"
	eye.button_pressed = (_eyedropper_event_id == String(ev.get("id", "")))
	eye.toggled.connect(func(v: bool):
		if v:
			_eyedropper_event_id = String(ev.get("id", ""))
			eyedropper_armed.emit(_eyedropper_event_id)
		else:
			if _eyedropper_event_id == String(ev.get("id", "")):
				_eyedropper_event_id = ""
				eyedropper_disarmed.emit()
		_refresh())
	bot.add_child(eye)
	var clear := Button.new()
	clear.text = "Clear Targets"
	clear.pressed.connect(func():
		ev["targets"] = []
		events_changed.emit()
		_refresh())
	bot.add_child(clear)
	var count := Label.new()
	count.text = "targets: %d" % int(ev.get("targets", []).size())
	bot.add_child(count)
	row.mouse_entered.connect(func(): target_hover.emit(String(ev.get("id", ""))))
	row.mouse_exited.connect(func(): target_unhover.emit())
	return row
