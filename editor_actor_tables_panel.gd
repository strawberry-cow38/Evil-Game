extends PanelContainer

# Right-side panel for the Spawns → Actors tool. Owns the canonical list
# of actor presets. Each preset =
#   { id, name, color, actor_id, hp, level, weapon, drop_table_id,
#     xp, regen, enemy, clothing: { slot_id: [ {id, weight}, ... ] } }
# Mirrors the item-tables panel shape so editor.gd can wire both
# uniformly. Per-slot clothing tables behave like loot tables (weight
# sliders + Nothing entry + add via picker).
#
# Settings are stubs for the wider RPG layer that doesn't exist yet
# (level / weapon / xp / regen / enemy flag) — captured here so the
# framework is in place when those systems land.

const ACTORS := preload("res://editor_actors_registry.gd")
const CLOTHING := preload("res://editor_clothing_registry.gd")

const SAVE_PATH := "user://actor_spawn_tables.json"

signal active_table_changed(table_index: int)

var tables: Array = []

var _next_id: int = 1
var _active_index: int = -1
var _active_slot: String = "head"
# Item tables list — pushed in by editor.gd whenever the item-tables
# panel changes so the Drop dropdown stays in sync.
var _item_tables_for_drop: Array = []
var _picker: Node = null  # editor_clothing_picker_panel

# UI refs
var _list_box: VBoxContainer
var _name_edit: LineEdit
var _r_slider: HSlider
var _g_slider: HSlider
var _b_slider: HSlider
var _swatch: ColorRect
var _delete_btn: Button
var _settings_box: VBoxContainer
var _clothing_box: VBoxContainer
var _slot_tab_box: HBoxContainer
var _slot_tab_buttons: Dictionary = {}
var _entries_box: VBoxContainer
var _add_clothing_btn: Button
# Settings field refs (refreshed each table switch)
var _hp_slider: HSlider
var _hp_label: Label
var _level_slider: HSlider
var _level_label: Label
var _weapon_label: Label
var _drop_btn: Button
var _drop_menu: PopupMenu
var _xp_slider: HSlider
var _xp_label: Label
var _regen_slider: HSlider
var _regen_label: Label
var _enemy_check: CheckBox
# Per-row sliders/labels for the active slot's clothing entries.
var _entry_buttons: Dictionary = {}
var _pct_labels: Dictionary = {}
var _sliders: Dictionary = {}

const HP_MAX := 5000
const LEVEL_MAX := 99
const XP_MAX := 10000
const REGEN_MAX := 1000.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(320, 0)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	var title := Label.new()
	title.text = "Actor Tables"
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)
	# Tables list -----------------------------------------------------
	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(0, 110)
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(list_scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(_list_box)
	# Name + colour ---------------------------------------------------
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
	# Create / Delete -------------------------------------------------
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
	vbox.add_child(HSeparator.new())
	# Per-table settings ---------------------------------------------
	_settings_box = VBoxContainer.new()
	_settings_box.add_theme_constant_override("separation", 4)
	vbox.add_child(_settings_box)
	# Clothing slots -------------------------------------------------
	vbox.add_child(HSeparator.new())
	var clothing_title := Label.new()
	clothing_title.text = "Clothing"
	clothing_title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(clothing_title)
	_slot_tab_box = HBoxContainer.new()
	_slot_tab_box.add_theme_constant_override("separation", 4)
	vbox.add_child(_slot_tab_box)
	for s in ACTORS.SLOTS:
		var sb := Button.new()
		sb.text = String(s.label)
		sb.add_theme_font_size_override("font_size", 12)
		sb.toggle_mode = true
		var sid: String = String(s.id)
		sb.pressed.connect(func(): _select_slot(sid))
		_slot_tab_box.add_child(sb)
		_slot_tab_buttons[sid] = sb
	_clothing_box = VBoxContainer.new()
	_clothing_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_clothing_box)
	_entries_box = VBoxContainer.new()
	_entries_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clothing_box.add_child(_entries_box)
	_add_clothing_btn = Button.new()
	_add_clothing_btn.text = "Add Clothing"
	_add_clothing_btn.pressed.connect(_on_add_clothing_pressed)
	_clothing_box.add_child(_add_clothing_btn)
	_load()
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
		_picker.items_picked.connect(_on_clothing_picked)

func set_item_tables_for_drop(item_tables: Array) -> void:
	# Pushed by editor.gd whenever the loot-table list changes so the Drop
	# dropdown stays in sync. Stored as a shallow ref — the dict-build for
	# the popup happens at refresh time.
	_item_tables_for_drop = item_tables
	_refresh_settings()

func set_tables(new_tables: Array) -> void:
	tables = []
	var max_id: int = 0
	for t in new_tables:
		tables.append(t.duplicate(true))
		var sid: String = String(t.get("id", ""))
		if sid.begins_with("atbl_"):
			var n: int = int(sid.substr(5))
			if n > max_id:
				max_id = n
	_next_id = max_id + 1
	_active_index = 0 if tables.size() > 0 else -1
	_save()
	_refresh_all()

func get_active_table() -> Dictionary:
	if _active_index < 0 or _active_index >= tables.size():
		return {}
	return tables[_active_index]

func get_active_index() -> int:
	return _active_index

# Roll the clothing for a given table — returns dict of slot_id -> item_id
# (or "" / nothing). main_bootstrap calls this when spawning the actor.
func roll_clothing(table_index: int) -> Dictionary:
	if table_index < 0 or table_index >= tables.size():
		return {}
	var t: Dictionary = tables[table_index]
	var clothing: Dictionary = t.get("clothing", {})
	var out: Dictionary = {}
	for s in ACTORS.SLOTS:
		var sid: String = String(s.id)
		var entries: Array = clothing.get(sid, [])
		out[sid] = _roll_slot(entries)
	return out

func _roll_slot(entries: Array) -> String:
	if entries.is_empty():
		return ""
	var total: float = 0.0
	for e in entries:
		var w: float = float(e.get("weight", 0.0))
		if w < 0.0:
			w = 0.0
		total += w
	if total <= 0.0:
		return ""
	var roll: float = randf() * total
	var acc: float = 0.0
	for e in entries:
		var w: float = maxf(float(e.get("weight", 0.0)), 0.0)
		acc += w
		if roll <= acc:
			var id: String = String(e.get("id", ""))
			if id == CLOTHING.NOTHING_ID:
				return ""
			return id
	return ""

# --- persistence -----------------------------------------------------

func _save() -> void:
	var out: Dictionary = {"next_id": _next_id, "tables": []}
	for t in tables:
		out["tables"].append(_table_to_json(t))
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("actor_tables: could not write %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(out))

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var dict: Dictionary = parsed
	_next_id = int(dict.get("next_id", 1))
	tables.clear()
	for t in dict.get("tables", []):
		tables.append(_table_from_json(t))
	if tables.size() > 0:
		_active_index = 0

func _table_to_json(t: Dictionary) -> Dictionary:
	var c: Color = t.get("color", Color.WHITE)
	var clothing_out: Dictionary = {}
	var clothing_in: Dictionary = t.get("clothing", {})
	for sid in clothing_in.keys():
		var entries_out: Array = []
		for e in clothing_in[sid]:
			entries_out.append({
				"id": String(e.get("id", "")),
				"weight": float(e.get("weight", 0.0)),
			})
		clothing_out[sid] = entries_out
	return {
		"id": String(t.get("id", "")),
		"name": String(t.get("name", "")),
		"color": [c.r, c.g, c.b],
		"actor_id": String(t.get("actor_id", "dummy")),
		"hp": int(t.get("hp", 500)),
		"level": int(t.get("level", 1)),
		"weapon": String(t.get("weapon", "")),
		"drop_table_id": String(t.get("drop_table_id", "")),
		"xp": int(t.get("xp", 0)),
		"regen": float(t.get("regen", 0.0)),
		"enemy": bool(t.get("enemy", false)),
		"clothing": clothing_out,
	}

func _table_from_json(t: Dictionary) -> Dictionary:
	var col_arr: Array = t.get("color", [1.0, 1.0, 1.0])
	var col: Color = Color(1, 1, 1, 1)
	if col_arr.size() >= 3:
		col = Color(float(col_arr[0]), float(col_arr[1]), float(col_arr[2]), 1.0)
	var clothing_in: Dictionary = t.get("clothing", {})
	var clothing_out: Dictionary = {}
	for s in ACTORS.SLOTS:
		var sid: String = String(s.id)
		var entries_in: Array = clothing_in.get(sid, [])
		var entries_out: Array = []
		var has_nothing: bool = false
		for e in entries_in:
			entries_out.append({
				"id": String(e.get("id", "")),
				"weight": float(e.get("weight", 0.0)),
			})
			if String(e.get("id", "")) == CLOTHING.NOTHING_ID:
				has_nothing = true
		if not has_nothing:
			entries_out.push_front({"id": CLOTHING.NOTHING_ID, "weight": 100.0})
		clothing_out[sid] = entries_out
	return {
		"id": String(t.get("id", "")),
		"name": String(t.get("name", "")),
		"color": col,
		"actor_id": String(t.get("actor_id", "dummy")),
		"hp": int(t.get("hp", 500)),
		"level": int(t.get("level", 1)),
		"weapon": String(t.get("weapon", "")),
		"drop_table_id": String(t.get("drop_table_id", "")),
		"xp": int(t.get("xp", 0)),
		"regen": float(t.get("regen", 0.0)),
		"enemy": bool(t.get("enemy", false)),
		"clothing": clothing_out,
	}

# --- table list management -------------------------------------------

func _on_create_pressed() -> void:
	var nm: String = _name_edit.text.strip_edges()
	if nm.is_empty():
		nm = "Actor %d" % _next_id
	var col := Color(_r_slider.value, _g_slider.value, _b_slider.value, 1.0)
	var clothing: Dictionary = {}
	for s in ACTORS.SLOTS:
		clothing[String(s.id)] = [{"id": CLOTHING.NOTHING_ID, "weight": 100.0}]
	var t: Dictionary = {
		"id": "atbl_%d" % _next_id,
		"name": nm,
		"color": col,
		"actor_id": "dummy",
		"hp": 500,
		"level": 1,
		"weapon": "",
		"drop_table_id": "",
		"xp": 0,
		"regen": 0.0,
		"enemy": false,
		"clothing": clothing,
	}
	_next_id += 1
	tables.append(t)
	_active_index = tables.size() - 1
	_save()
	_refresh_all()
	_emit_active_changed()

func _on_delete_pressed() -> void:
	if _active_index < 0 or _active_index >= tables.size():
		return
	tables.remove_at(_active_index)
	if _active_index >= tables.size():
		_active_index = tables.size() - 1
	_save()
	_refresh_all()
	_emit_active_changed()

func _select_table(idx: int) -> void:
	_active_index = idx
	_refresh_all()
	_emit_active_changed()

func _emit_active_changed() -> void:
	active_table_changed.emit(_active_index)

func _refresh_all() -> void:
	_refresh_table_list()
	_refresh_color_inputs()
	_refresh_settings()
	_refresh_slot_tabs()
	_refresh_entries()
	_delete_btn.disabled = (_active_index < 0)
	_add_clothing_btn.disabled = (_active_index < 0)

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
		_swatch.color = Color(_r_slider.value, _g_slider.value, _b_slider.value, 1.0)
		return
	var t: Dictionary = tables[_active_index]
	var c: Color = t.get("color", Color.WHITE)
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
		_emit_active_changed()
		_save()

func _on_name_changed(t: String) -> void:
	if _active_index >= 0:
		tables[_active_index]["name"] = t
		_refresh_table_list()
		_save()

# --- per-table settings ----------------------------------------------

func _refresh_settings() -> void:
	for c in _settings_box.get_children():
		c.queue_free()
	if _active_index < 0:
		return
	var t: Dictionary = tables[_active_index]
	# Actor type — label only for now (only dummy exists).
	var actor_row := HBoxContainer.new()
	var alab := Label.new()
	alab.text = "Actor"
	alab.custom_minimum_size = Vector2(70, 0)
	actor_row.add_child(alab)
	var aval := Label.new()
	aval.text = ACTORS.label_for(String(t.get("actor_id", "dummy")))
	aval.modulate = Color(0.9, 0.9, 0.7, 1.0)
	actor_row.add_child(aval)
	_settings_box.add_child(actor_row)
	# HP slider
	_hp_slider = _build_int_slider("HP", int(t.get("hp", 500)), 1, HP_MAX)
	_hp_label = _last_value_label
	_hp_slider.value_changed.connect(func(v): _on_hp_changed(int(v)))
	# Level
	_level_slider = _build_int_slider("Level", int(t.get("level", 1)), 1, LEVEL_MAX)
	_level_label = _last_value_label
	_level_slider.value_changed.connect(func(v): _on_level_changed(int(v)))
	# Weapon stub
	var weap_row := HBoxContainer.new()
	var wlab := Label.new()
	wlab.text = "Weapon"
	wlab.custom_minimum_size = Vector2(70, 0)
	weap_row.add_child(wlab)
	_weapon_label = Label.new()
	_weapon_label.text = "(stub)"
	_weapon_label.modulate = Color(0.7, 0.7, 0.7, 1.0)
	weap_row.add_child(_weapon_label)
	_settings_box.add_child(weap_row)
	# Drop table dropdown
	var drop_row := HBoxContainer.new()
	var dlab := Label.new()
	dlab.text = "Drop"
	dlab.custom_minimum_size = Vector2(70, 0)
	drop_row.add_child(dlab)
	_drop_btn = Button.new()
	_drop_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drop_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_drop_btn.text = _drop_label_for(String(t.get("drop_table_id", "")))
	_drop_btn.pressed.connect(_open_drop_menu)
	drop_row.add_child(_drop_btn)
	_settings_box.add_child(drop_row)
	_drop_menu = PopupMenu.new()
	_drop_menu.id_pressed.connect(_on_drop_menu_picked)
	_drop_btn.add_child(_drop_menu)
	# XP
	_xp_slider = _build_int_slider("XP", int(t.get("xp", 0)), 0, XP_MAX)
	_xp_label = _last_value_label
	_xp_slider.value_changed.connect(func(v): _on_xp_changed(int(v)))
	# Regen
	_regen_slider = _build_float_slider("Regen", float(t.get("regen", 0.0)), 0.0, REGEN_MAX, 1.0, "%.0f hp/s")
	_regen_label = _last_value_label
	_regen_slider.value_changed.connect(func(v): _on_regen_changed(float(v)))
	# Enemy toggle
	_enemy_check = CheckBox.new()
	_enemy_check.text = "Enemy (hostile)"
	_enemy_check.button_pressed = bool(t.get("enemy", false))
	_enemy_check.toggled.connect(_on_enemy_toggled)
	_settings_box.add_child(_enemy_check)

# Tracks the last value-label built by _build_int_slider/_build_float_slider
# so the caller can stash it without juggling tuples.
var _last_value_label: Label = null

func _build_int_slider(label_text: String, initial: int, lo: int, hi: int) -> HSlider:
	var row := HBoxContainer.new()
	_settings_box.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(70, 0)
	row.add_child(lbl)
	var s := HSlider.new()
	s.min_value = float(lo)
	s.max_value = float(hi)
	s.step = 1.0
	s.value = float(initial)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(s)
	var v := Label.new()
	v.text = "%d" % initial
	v.custom_minimum_size = Vector2(48, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	s.value_changed.connect(func(val): v.text = "%d" % int(val))
	_last_value_label = v
	return s

func _build_float_slider(label_text: String, initial: float, lo: float, hi: float, step: float, fmt: String) -> HSlider:
	var row := HBoxContainer.new()
	_settings_box.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(70, 0)
	row.add_child(lbl)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = initial
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(s)
	var v := Label.new()
	v.text = fmt % initial
	v.custom_minimum_size = Vector2(70, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	s.value_changed.connect(func(val): v.text = fmt % val)
	_last_value_label = v
	return s

func _on_hp_changed(v: int) -> void:
	if _active_index < 0:
		return
	tables[_active_index]["hp"] = v
	_save()

func _on_level_changed(v: int) -> void:
	if _active_index < 0:
		return
	tables[_active_index]["level"] = v
	_save()

func _on_xp_changed(v: int) -> void:
	if _active_index < 0:
		return
	tables[_active_index]["xp"] = v
	_save()

func _on_regen_changed(v: float) -> void:
	if _active_index < 0:
		return
	tables[_active_index]["regen"] = v
	_save()

func _on_enemy_toggled(v: bool) -> void:
	if _active_index < 0:
		return
	tables[_active_index]["enemy"] = v
	_save()

func _drop_label_for(tid: String) -> String:
	if tid == "":
		return "(none)"
	for t in _item_tables_for_drop:
		if String(t.get("id", "")) == tid:
			return String(t.get("name", tid))
	return "(missing) %s" % tid

func _open_drop_menu() -> void:
	if _drop_menu == null:
		return
	_drop_menu.clear()
	_drop_menu.add_item("(none)", 0)
	var i: int = 1
	for t in _item_tables_for_drop:
		_drop_menu.add_item(String(t.get("name", t.get("id", "?"))), i)
		i += 1
	var p: Vector2 = _drop_btn.global_position + Vector2(0, _drop_btn.size.y)
	_drop_menu.position = Vector2i(int(p.x), int(p.y))
	_drop_menu.size = Vector2i(int(_drop_btn.size.x), 0)
	_drop_menu.popup()

func _on_drop_menu_picked(id: int) -> void:
	if _active_index < 0:
		return
	if id == 0:
		tables[_active_index]["drop_table_id"] = ""
	else:
		var idx: int = id - 1
		if idx >= 0 and idx < _item_tables_for_drop.size():
			tables[_active_index]["drop_table_id"] = String(_item_tables_for_drop[idx].get("id", ""))
	_drop_btn.text = _drop_label_for(String(tables[_active_index].get("drop_table_id", "")))
	_save()

# --- clothing slot tabs ----------------------------------------------

func _select_slot(slot_id: String) -> void:
	_active_slot = slot_id
	_refresh_slot_tabs()
	_refresh_entries()

func _refresh_slot_tabs() -> void:
	for k in _slot_tab_buttons.keys():
		var b: Button = _slot_tab_buttons[k]
		b.button_pressed = (k == _active_slot)
		b.modulate = Color(1.0, 1.0, 0.5, 1.0) if k == _active_slot else Color(1, 1, 1, 1)

func _refresh_entries() -> void:
	for c in _entries_box.get_children():
		c.queue_free()
	_pct_labels.clear()
	_sliders.clear()
	_entry_buttons.clear()
	if _active_index < 0:
		return
	var t: Dictionary = tables[_active_index]
	var clothing: Dictionary = t.get("clothing", {})
	var entries: Array = clothing.get(_active_slot, [])
	for i in range(entries.size()):
		var e: Dictionary = entries[i]
		var id: String = String(e.get("id", ""))
		var w: float = float(e.get("weight", 1.0))
		var row := HBoxContainer.new()
		var name_btn := Button.new()
		name_btn.text = CLOTHING.label_for(id)
		name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_btn.custom_minimum_size = Vector2(80, 0)
		name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_btn.disabled = true
		row.add_child(name_btn)
		_entry_buttons[i] = name_btn
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
		_sliders[entry_idx] = slider
		var pct_lbl := Label.new()
		pct_lbl.custom_minimum_size = Vector2(40, 0)
		pct_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(pct_lbl)
		_pct_labels[entry_idx] = pct_lbl
		if id != CLOTHING.NOTHING_ID:
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
	var entries: Array = tables[_active_index].get("clothing", {}).get(_active_slot, [])
	var total: float = 0.0
	for e in entries:
		var w: float = maxf(float(e.get("weight", 0.0)), 0.0)
		total += w
	for i in range(entries.size()):
		var lbl: Label = _pct_labels.get(i, null)
		if lbl == null:
			continue
		if total <= 0.0:
			lbl.text = "0%"
		else:
			var w2: float = maxf(float(entries[i].get("weight", 0.0)), 0.0)
			lbl.text = "%d%%" % int(round((w2 / total) * 100.0))

func _on_weight_changed(entry_idx: int, v: float) -> void:
	if _active_index < 0:
		return
	var entries: Array = tables[_active_index].get("clothing", {}).get(_active_slot, [])
	if entry_idx < 0 or entry_idx >= entries.size():
		return
	var v_clamped: float = clampf(v, 0.0, 100.0)
	entries[entry_idx]["weight"] = v_clamped
	_redistribute_others(entries, entry_idx, v_clamped)
	_push_slider_values(entries)
	_refresh_pcts()
	_save()

func _redistribute_others(entries: Array, changed_idx: int, changed_v: float) -> void:
	var remaining: float = maxf(100.0 - changed_v, 0.0)
	var other_sum: float = 0.0
	var other_count: int = 0
	for i in range(entries.size()):
		if i == changed_idx:
			continue
		other_sum += maxf(float(entries[i].get("weight", 0.0)), 0.0)
		other_count += 1
	if other_count == 0:
		return
	if other_sum > 0.0001:
		var scale: float = remaining / other_sum
		for i in range(entries.size()):
			if i == changed_idx:
				continue
			entries[i]["weight"] = maxf(float(entries[i].get("weight", 0.0)), 0.0) * scale
	else:
		var each: float = remaining / float(other_count)
		for i in range(entries.size()):
			if i == changed_idx:
				continue
			entries[i]["weight"] = each

func _push_slider_values(entries: Array) -> void:
	for i in range(entries.size()):
		var s: HSlider = _sliders.get(i, null)
		if s == null:
			continue
		s.set_block_signals(true)
		s.value = float(entries[i].get("weight", 0.0))
		s.set_block_signals(false)

func _normalize_to_100(entries: Array) -> void:
	if entries.is_empty():
		return
	var total: float = 0.0
	for e in entries:
		total += maxf(float(e.get("weight", 0.0)), 0.0)
	if total > 0.0001:
		var scale: float = 100.0 / total
		for e in entries:
			e["weight"] = maxf(float(e.get("weight", 0.0)), 0.0) * scale
	else:
		var each: float = 100.0 / float(entries.size())
		for e in entries:
			e["weight"] = each

func _on_entry_remove(entry_idx: int) -> void:
	if _active_index < 0:
		return
	var entries: Array = tables[_active_index].get("clothing", {}).get(_active_slot, [])
	if entry_idx < 0 or entry_idx >= entries.size():
		return
	entries.remove_at(entry_idx)
	_normalize_to_100(entries)
	_refresh_entries()
	_save()

func _on_add_clothing_pressed() -> void:
	if _active_index < 0 or _picker == null:
		return
	if _picker.has_method("open_for_slot"):
		_picker.open_for_slot(_active_slot)

func _on_clothing_picked(ids: Array) -> void:
	if _active_index < 0:
		return
	var entries: Array = tables[_active_index].get("clothing", {}).get(_active_slot, [])
	var existing: Dictionary = {}
	for e in entries:
		existing[String(e.get("id", ""))] = true
	for id in ids:
		var sid: String = String(id)
		if existing.has(sid):
			continue
		entries.append({"id": sid, "weight": 0.0})
	_refresh_entries()
	_save()
