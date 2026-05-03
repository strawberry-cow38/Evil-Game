extends PanelContainer

# Item picker invoked by the item-tables panel. Search bar at top,
# scrollable list below, multi-select with shift-click. Confirm button
# emits items_picked(ids) and the panel hides itself; cancel just hides.

const REGISTRY := preload("res://editor_items_registry.gd")

signal items_picked(ids: Array)

var _search: LineEdit
var _list_box: VBoxContainer
var _scroll: ScrollContainer
var _selected_ids: Dictionary = {}  # id -> true
var _last_clicked_id: String = ""
var _row_buttons: Dictionary = {}   # id -> Button (for highlight)
var _row_order: Array = []          # current visible id order (shift-range)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(280, 0)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)
	var title := Label.new()
	title.text = "Pick Items"
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)
	_search = LineEdit.new()
	_search.placeholder_text = "search…"
	_search.text_changed.connect(_on_search_changed)
	vbox.add_child(_search)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list_box)
	var hb := HBoxContainer.new()
	vbox.add_child(hb)
	var add_btn := Button.new()
	add_btn.text = "Add Selected"
	add_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_btn.pressed.connect(_on_confirm)
	hb.add_child(add_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_on_cancel)
	hb.add_child(cancel_btn)
	_rebuild_list("")

func open() -> void:
	visible = true
	_selected_ids.clear()
	_last_clicked_id = ""
	_search.text = ""
	_rebuild_list("")
	_search.grab_focus()

func _on_search_changed(t: String) -> void:
	_rebuild_list(t)

func _rebuild_list(query: String) -> void:
	for c in _list_box.get_children():
		c.queue_free()
	_row_buttons.clear()
	_row_order.clear()
	for e in REGISTRY.filtered(query):
		var id: String = String(e.id)
		var b := Button.new()
		b.text = String(e.label)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 13)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): _on_row_pressed(id))
		_list_box.add_child(b)
		_row_buttons[id] = b
		_row_order.append(id)
	_apply_highlight()

func _on_row_pressed(id: String) -> void:
	var shift: bool = Input.is_key_pressed(KEY_SHIFT)
	if shift and _last_clicked_id != "" and _row_order.has(_last_clicked_id):
		var i0: int = _row_order.find(_last_clicked_id)
		var i1: int = _row_order.find(id)
		var lo: int = mini(i0, i1)
		var hi: int = maxi(i0, i1)
		for i in range(lo, hi + 1):
			_selected_ids[_row_order[i]] = true
	else:
		if _selected_ids.has(id):
			_selected_ids.erase(id)
		else:
			_selected_ids[id] = true
		_last_clicked_id = id
	_apply_highlight()

func _apply_highlight() -> void:
	for k in _row_buttons.keys():
		var btn: Button = _row_buttons[k]
		btn.modulate = Color(1.0, 1.0, 0.5, 1.0) if _selected_ids.has(k) else Color(1, 1, 1, 1)

func _on_confirm() -> void:
	var ids: Array = _selected_ids.keys()
	visible = false
	if not ids.is_empty():
		items_picked.emit(ids)

func _on_cancel() -> void:
	visible = false
