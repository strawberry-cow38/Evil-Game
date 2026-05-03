extends PanelContainer

# Right-side panel for the Spawns → Items tool. Owns the canonical list
# of item-spawn tables. Each table = { name, color, entries:[{id, weight}] }.
# A "nothing" entry is always present so the user can dial in empty rolls.
#
# Layout:
#   [tables list]              ← right column
#   [name field]
#   [R/G/B sliders + swatch]
#   [Create] [Delete]
#   ----- selected table -----
#   [entries list w/ per-row weight slider + remove]
#   [Add Item]                  ← opens the picker
#
# Source of truth lives here for the lifetime of the editor scene; the
# editor pulls a snapshot into MapState on F9.

const REGISTRY := preload("res://editor_items_registry.gd")

signal active_table_changed(table_index: int)

# Dictionary entries:
#   { "id": String, "name": String, "color": Color,
#     "entries": Array[ { "id": String, "weight": float } ] }
var tables: Array = []

var _next_id: int = 1
var _active_index: int = -1

var _list_box: VBoxContainer
var _name_edit: LineEdit
var _r_slider: HSlider
var _g_slider: HSlider
var _b_slider: HSlider
var _swatch: ColorRect
var _delete_btn: Button
var _entries_box: VBoxContainer
var _add_item_btn: Button
var _picker: Node = null  # editor_item_picker_panel — wired via set_picker()
# Per-row "X%" labels keyed by entry index. Refreshed every time any
# weight slider moves (or entries are added/removed) so the displayed
# percentages always sum to 100% relative to the table's current weights.
var _pct_labels: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(280, 0)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)
	var title := Label.new()
	title.text = "Item Tables"
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)
	# Tables list (scrollable) ------------------------------------------
	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(0, 120)
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(list_scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(_list_box)
	# Editor row: name + RGB sliders ------------------------------------
	var name_row := HBoxContainer.new()
	vbox.add_child(name_row)
	var name_lbl := Label.new()
	name_lbl.text = "Name"
	name_lbl.custom_minimum_size = Vector2(48, 0)
	name_row.add_child(name_lbl)
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(_on_name_changed)
	name_row.add_child(_name_edit)
	_r_slider = _make_color_slider(vbox, "R")
	_g_slider = _make_color_slider(vbox, "G")
	_b_slider = _make_color_slider(vbox, "B")
	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(0, 18)
	_swatch.color = Color(1, 1, 1, 1)
	vbox.add_child(_swatch)
	# Create / Delete row ----------------------------------------------
	var btn_row := HBoxContainer.new()
	vbox.add_child(btn_row)
	var create_btn := Button.new()
	create_btn.text = "Create"
	create_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_btn.pressed.connect(_on_create_pressed)
	btn_row.add_child(create_btn)
	_delete_btn = Button.new()
	_delete_btn.text = "Delete"
	_delete_btn.pressed.connect(_on_delete_pressed)
	btn_row.add_child(_delete_btn)
	# Separator --------------------------------------------------------
	var sep := HSeparator.new()
	vbox.add_child(sep)
	var entries_title := Label.new()
	entries_title.text = "Spawn List"
	entries_title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(entries_title)
	# Entries list (scroll) -------------------------------------------
	var entries_scroll := ScrollContainer.new()
	entries_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	entries_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(entries_scroll)
	_entries_box = VBoxContainer.new()
	_entries_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entries_scroll.add_child(_entries_box)
	_add_item_btn = Button.new()
	_add_item_btn.text = "Add Item"
	_add_item_btn.pressed.connect(_on_add_item_pressed)
	vbox.add_child(_add_item_btn)
	_refresh_all()

func _make_color_slider(parent: Container, label_text: String) -> HSlider:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(48, 0)
	row.add_child(lbl)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.01
	s.value = 1.0
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(_on_color_changed)
	row.add_child(s)
	return s

func set_picker(p: Node) -> void:
	_picker = p
	if _picker != null and _picker.has_signal("items_picked"):
		_picker.items_picked.connect(_on_items_picked)

func get_active_table() -> Dictionary:
	if _active_index < 0 or _active_index >= tables.size():
		return {}
	return tables[_active_index]

# Roll the active table; returns "" for nothing or no-table.
func roll_table(table_index: int) -> String:
	if table_index < 0 or table_index >= tables.size():
		return ""
	var t: Dictionary = tables[table_index]
	var entries: Array = t.get("entries", [])
	# Always include nothing (default weight 1.0 if missing).
	var has_nothing: bool = false
	var total: float = 0.0
	for e in entries:
		var w: float = float(e.get("weight", 1.0))
		if w < 0.0:
			w = 0.0
		total += w
		if String(e.get("id", "")) == REGISTRY.NOTHING_ID:
			has_nothing = true
	if not has_nothing:
		total += 1.0
	if total <= 0.0:
		return ""
	var roll: float = randf() * total
	var acc: float = 0.0
	for e in entries:
		acc += float(e.get("weight", 1.0))
		if roll <= acc:
			var id: String = String(e.get("id", ""))
			if id == REGISTRY.NOTHING_ID:
				return ""
			return id
	return ""

# --- table list management -------------------------------------------

func _on_create_pressed() -> void:
	var nm: String = _name_edit.text.strip_edges()
	if nm.is_empty():
		nm = "Table %d" % _next_id
	var col := Color(_r_slider.value, _g_slider.value, _b_slider.value, 1.0)
	var t: Dictionary = {
		"id": "tbl_%d" % _next_id,
		"name": nm,
		"color": col,
		"entries": [
			{"id": REGISTRY.NOTHING_ID, "weight": 1.0},
		],
	}
	_next_id += 1
	tables.append(t)
	_active_index = tables.size() - 1
	_refresh_all()
	_emit_active_changed()

func _on_delete_pressed() -> void:
	if _active_index < 0 or _active_index >= tables.size():
		return
	tables.remove_at(_active_index)
	if _active_index >= tables.size():
		_active_index = tables.size() - 1
	_refresh_all()
	_emit_active_changed()

func _select_table(idx: int) -> void:
	_active_index = idx
	_refresh_all()
	_emit_active_changed()

func _emit_active_changed() -> void:
	active_table_changed.emit(_active_index)

func get_active_index() -> int:
	return _active_index

func _refresh_all() -> void:
	_refresh_table_list()
	_refresh_color_inputs()
	_refresh_entries()
	_delete_btn.disabled = (_active_index < 0)
	_add_item_btn.disabled = (_active_index < 0)

func _refresh_table_list() -> void:
	for c in _list_box.get_children():
		c.queue_free()
	for i in range(tables.size()):
		var t: Dictionary = tables[i]
		var row := HBoxContainer.new()
		var cr := ColorRect.new()
		cr.custom_minimum_size = Vector2(18, 18)
		cr.color = t.get("color", Color.WHITE)
		row.add_child(cr)
		var b := Button.new()
		b.text = String(t.get("name", "?"))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.modulate = Color(1.0, 1.0, 0.6, 1.0) if i == _active_index else Color(1, 1, 1, 1)
		var idx: int = i
		b.pressed.connect(func(): _select_table(idx))
		row.add_child(b)
		_list_box.add_child(row)

func _refresh_color_inputs() -> void:
	if _active_index < 0:
		_name_edit.editable = true
		_swatch.color = Color(_r_slider.value, _g_slider.value, _b_slider.value, 1.0)
		return
	var t: Dictionary = tables[_active_index]
	var c: Color = t.get("color", Color.WHITE)
	# Avoid feedback loops while we drive the inputs.
	_r_slider.set_block_signals(true); _g_slider.set_block_signals(true); _b_slider.set_block_signals(true)
	_name_edit.set_block_signals(true)
	_r_slider.value = c.r
	_g_slider.value = c.g
	_b_slider.value = c.b
	_name_edit.text = String(t.get("name", ""))
	_r_slider.set_block_signals(false); _g_slider.set_block_signals(false); _b_slider.set_block_signals(false)
	_name_edit.set_block_signals(false)
	_swatch.color = c

func _on_color_changed(_v: float) -> void:
	var c := Color(_r_slider.value, _g_slider.value, _b_slider.value, 1.0)
	_swatch.color = c
	if _active_index >= 0:
		tables[_active_index]["color"] = c
		_refresh_table_list()
		_emit_active_changed()  # editor recolors live cubes

func _on_name_changed(t: String) -> void:
	if _active_index >= 0:
		tables[_active_index]["name"] = t
		_refresh_table_list()

# --- entries (items in the active table) -----------------------------

func _refresh_entries() -> void:
	for c in _entries_box.get_children():
		c.queue_free()
	_pct_labels.clear()
	if _active_index < 0:
		return
	var entries: Array = tables[_active_index].get("entries", [])
	for i in range(entries.size()):
		var e: Dictionary = entries[i]
		var id: String = String(e.get("id", ""))
		var w: float = float(e.get("weight", 1.0))
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = REGISTRY.label_for(id)
		lbl.custom_minimum_size = Vector2(80, 0)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 100.0
		slider.step = 1.0
		slider.value = w
		slider.custom_minimum_size = Vector2(80, 0)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var entry_idx: int = i
		slider.value_changed.connect(func(v: float): _on_weight_changed(entry_idx, v))
		row.add_child(slider)
		var pct_lbl := Label.new()
		pct_lbl.custom_minimum_size = Vector2(40, 0)
		pct_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(pct_lbl)
		_pct_labels[entry_idx] = pct_lbl
		# "Nothing" can't be removed — every table always has it.
		if id != REGISTRY.NOTHING_ID:
			var rm := Button.new()
			rm.text = "x"
			rm.custom_minimum_size = Vector2(24, 0)
			rm.pressed.connect(func(): _on_entry_remove(entry_idx))
			row.add_child(rm)
		_entries_box.add_child(row)
	_refresh_pcts()

func _refresh_pcts() -> void:
	if _active_index < 0:
		return
	var entries: Array = tables[_active_index].get("entries", [])
	var total: float = 0.0
	for e in entries:
		var w: float = float(e.get("weight", 1.0))
		if w < 0.0:
			w = 0.0
		total += w
	for i in range(entries.size()):
		var lbl: Label = _pct_labels.get(i, null)
		if lbl == null:
			continue
		if total <= 0.0:
			lbl.text = "0%"
		else:
			var w2: float = maxf(float(entries[i].get("weight", 1.0)), 0.0)
			var pct: float = (w2 / total) * 100.0
			lbl.text = "%d%%" % int(round(pct))

func _on_weight_changed(entry_idx: int, v: float) -> void:
	if _active_index < 0:
		return
	var entries: Array = tables[_active_index].get("entries", [])
	if entry_idx < 0 or entry_idx >= entries.size():
		return
	entries[entry_idx]["weight"] = v
	_refresh_pcts()

func _on_entry_remove(entry_idx: int) -> void:
	if _active_index < 0:
		return
	var entries: Array = tables[_active_index].get("entries", [])
	if entry_idx < 0 or entry_idx >= entries.size():
		return
	entries.remove_at(entry_idx)
	_refresh_entries()

func _on_add_item_pressed() -> void:
	if _active_index < 0 or _picker == null:
		return
	_picker.open()

func _on_items_picked(ids: Array) -> void:
	if _active_index < 0:
		return
	var entries: Array = tables[_active_index].get("entries", [])
	var existing: Dictionary = {}
	for e in entries:
		existing[String(e.get("id", ""))] = true
	for id in ids:
		var sid: String = String(id)
		if existing.has(sid):
			continue
		entries.append({"id": sid, "weight": 10.0})
	_refresh_entries()
