extends CanvasLayer

const Items = preload("res://items.gd")

const TAB_INVENTORY := "Inventory"
const TABS: Array = [TAB_INVENTORY]   # extensible — add stats/map/etc here later

# Category filter for the inventory list. "All" matches anything; the rest
# match by item kind. "Misc" is the catch-all for anything not claimed by a
# named category.
const CATEGORIES: Array = [
	{"label": "All",       "kinds": []},
	{"label": "Weapons",   "kinds": ["weapon"]},
	{"label": "Ammo",      "kinds": ["ammo"]},
	{"label": "Medical",   "kinds": ["medical", "food"]},
	{"label": "Apparel",   "kinds": ["apparel", "armor", "clothing"]},
	{"label": "Resources", "kinds": ["resource"]},
	{"label": "Building",  "kinds": ["building", "material"]},
	{"label": "Misc",      "kinds": ["__misc__"]},
]
# Kinds claimed by named categories — anything outside this set falls into Misc.
const NAMED_KINDS: Array = ["weapon", "apparel", "armor", "clothing", "ammo", "medical", "food", "resource", "building", "material"]

# Stacks larger than this prompt for a split-drop count instead of dropping
# one at a time. Smaller stacks just drop a single unit on R press.
const SPLIT_PROMPT_THRESHOLD := 5

enum SortMode { NAME, WEIGHT_TOTAL, VALUE_EACH }
const SORT_LABELS := {
	SortMode.NAME: "Name",
	SortMode.WEIGHT_TOTAL: "Weight (stack)",
	SortMode.VALUE_EACH: "Value (each)",
}

@export var inventory_path: NodePath

var _inventory: Node
var _open := false
var _tab_idx := 0
var _category_idx := 0
var _sort_mode: SortMode = SortMode.NAME
var _sort_asc := true

# Cached row metadata keyed to current ItemList rows. Each entry mirrors the
# inventory entry dict (id, uid, is_instance, condition, quality, ...).
var _rows: Array[Dictionary] = []

# Favorite-binding mode: when true, next 1..9 press binds the selected item.
var _binding_mode := false

# UI nodes (built in _ready).
var _root: Control
var _tab_box: HBoxContainer
var _tab_buttons: Array[Button] = []
var _category_box: HBoxContainer
var _category_buttons: Array[Button] = []
var _list: ItemList
var _preview_color: ColorRect
var _preview_name: Label
var _preview_per_weight: Label
var _preview_value: Label
var _preview_count: Label
var _preview_kind: Label
var _equip_btn: Button
var _sort_label: Label
var _encumbrance_label: Label
var _hint_label: Label
var _status_label: Label

# Inspect overlay nodes.
var _inspect_root: Control
var _inspect_color: ColorRect
var _inspect_name: Label
var _inspect_desc: Label
var _inspect_stats: Label
var _inspect_slots_label: Label
var _inspect_slots_box: VBoxContainer

# Split-drop overlay nodes + active context.
var _split_root: Control
var _split_title: Label
var _split_slider: HSlider
var _split_spin: SpinBox
var _split_id: String = ""
var _split_max: int = 0
var _split_syncing: bool = false

func _ready() -> void:
	layer = 50
	if inventory_path != NodePath():
		_inventory = get_node(inventory_path)
	if _inventory != null:
		if _inventory.has_signal("changed"):
			_inventory.changed.connect(_on_inventory_changed)
		if _inventory.has_signal("favorites_changed"):
			_inventory.favorites_changed.connect(_on_inventory_changed)
		if _inventory.has_signal("equipped_changed"):
			_inventory.equipped_changed.connect(func(_id): _on_inventory_changed())
	_build_ui()
	_set_open(false)
	_refresh()

func is_open() -> bool:
	return _open

func toggle() -> void:
	_set_open(not _open)

func _set_open(v: bool) -> void:
	_open = v
	_root.visible = v
	if v:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_refresh()
		if _list.item_count > 0:
			var sel: PackedInt32Array = _list.get_selected_items()
			var idx: int = sel[0] if sel.size() > 0 else 0
			_list.select(min(idx, _list.item_count - 1))
		_list.grab_focus()
	else:
		_close_inspect()
		_binding_mode = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_bottom", 60)
	_root.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	margin.add_child(vb)

	# Tab bar.
	_tab_box = HBoxContainer.new()
	_tab_box.add_theme_constant_override("separation", 6)
	vb.add_child(_tab_box)
	for i in range(TABS.size()):
		var b := Button.new()
		b.text = TABS[i]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 18)
		var idx := i
		b.pressed.connect(func(): _select_tab(idx))
		_tab_box.add_child(b)
		_tab_buttons.append(b)

	# Category bar (All / Weapons / Ammo / etc).
	_category_box = HBoxContainer.new()
	_category_box.add_theme_constant_override("separation", 4)
	vb.add_child(_category_box)
	for i in range(CATEGORIES.size()):
		var cb := Button.new()
		cb.text = String(CATEGORIES[i].label)
		cb.toggle_mode = true
		cb.focus_mode = Control.FOCUS_NONE
		cb.add_theme_font_size_override("font_size", 16)
		var cidx := i
		cb.pressed.connect(func(): _select_category(cidx))
		_category_box.add_child(cb)
		_category_buttons.append(cb)

	vb.add_child(HSeparator.new())

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(content)

	_list = ItemList.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(400, 300)
	_list.fixed_icon_size = Vector2i(32, 32)
	_list.icon_mode = ItemList.ICON_MODE_LEFT
	_list.max_columns = 1
	_list.same_column_width = true
	_list.auto_height = false
	_list.allow_reselect = true
	_list.add_theme_font_size_override("font_size", 18)
	_list.item_selected.connect(func(_i): _refresh_preview())
	_list.item_clicked.connect(_on_item_clicked)
	_list.item_activated.connect(_on_item_activated)
	_list.gui_input.connect(_on_list_gui_input)
	content.add_child(_list)

	var preview_panel := PanelContainer.new()
	preview_panel.custom_minimum_size = Vector2(320, 0)
	content.add_child(preview_panel)

	var pv_margin := MarginContainer.new()
	pv_margin.add_theme_constant_override("margin_left", 12)
	pv_margin.add_theme_constant_override("margin_right", 12)
	pv_margin.add_theme_constant_override("margin_top", 12)
	pv_margin.add_theme_constant_override("margin_bottom", 12)
	preview_panel.add_child(pv_margin)

	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 8)
	pv_margin.add_child(pv)

	_preview_color = ColorRect.new()
	_preview_color.custom_minimum_size = Vector2(0, 140)
	_preview_color.color = Color(0.2, 0.2, 0.2)
	pv.add_child(_preview_color)

	_preview_name = Label.new()
	_preview_name.add_theme_font_size_override("font_size", 22)
	_preview_name.text = "—"
	pv.add_child(_preview_name)

	_preview_kind = Label.new()
	_preview_kind.modulate = Color(0.75, 0.85, 1.0)
	_preview_kind.text = ""
	pv.add_child(_preview_kind)

	_preview_per_weight = Label.new()
	_preview_per_weight.text = ""
	pv.add_child(_preview_per_weight)

	_preview_value = Label.new()
	_preview_value.text = ""
	pv.add_child(_preview_value)

	_preview_count = Label.new()
	_preview_count.text = ""
	pv.add_child(_preview_count)

	_equip_btn = Button.new()
	_equip_btn.text = "Equip [Enter / Dbl-Click]"
	_equip_btn.add_theme_font_size_override("font_size", 18)
	_equip_btn.pressed.connect(_equip_selected)
	pv.add_child(_equip_btn)

	vb.add_child(HSeparator.new())

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 24)
	vb.add_child(footer)

	_sort_label = Label.new()
	_sort_label.text = ""
	footer.add_child(_sort_label)

	_hint_label = Label.new()
	_hint_label.text = "[Enter/Dbl-Click] equip  [X] inspect  [R] drop / [Shift+R] drop all  [Q] favorite→1-9  [←/→] category  [Z]/[V] sort  [WS/↑↓] nav  [Tab/Esc] close"
	_hint_label.modulate = Color(0.75, 0.75, 0.75)
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_child(_hint_label)

	_encumbrance_label = Label.new()
	_encumbrance_label.text = ""
	_encumbrance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(_encumbrance_label)

	# Status banner (binding-mode prompt etc) sits just above the footer.
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 20)
	_status_label.modulate = Color(1.0, 0.85, 0.4)
	_status_label.visible = false
	vb.add_child(_status_label)

	_build_inspect_overlay()
	_build_split_overlay()
	_select_tab(0)
	_select_category(0)

func _build_inspect_overlay() -> void:
	_inspect_root = Control.new()
	_inspect_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inspect_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_inspect_root.visible = false
	_root.add_child(_inspect_root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_inspect_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inspect_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 520)
	center.add_child(panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 24)
	pad.add_theme_constant_override("margin_right", 24)
	pad.add_theme_constant_override("margin_top", 20)
	pad.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(pad)

	var ix := HBoxContainer.new()
	ix.add_theme_constant_override("separation", 24)
	pad.add_child(ix)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.custom_minimum_size = Vector2(280, 0)
	ix.add_child(left)

	_inspect_color = ColorRect.new()
	_inspect_color.custom_minimum_size = Vector2(280, 280)
	_inspect_color.color = Color(0.2, 0.2, 0.2)
	left.add_child(_inspect_color)

	_inspect_stats = Label.new()
	_inspect_stats.add_theme_font_size_override("font_size", 16)
	_inspect_stats.text = ""
	left.add_child(_inspect_stats)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ix.add_child(right)

	_inspect_name = Label.new()
	_inspect_name.add_theme_font_size_override("font_size", 28)
	_inspect_name.text = ""
	right.add_child(_inspect_name)

	_inspect_desc = Label.new()
	_inspect_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inspect_desc.text = ""
	right.add_child(_inspect_desc)

	right.add_child(HSeparator.new())

	_inspect_slots_label = Label.new()
	_inspect_slots_label.add_theme_font_size_override("font_size", 18)
	_inspect_slots_label.text = "Slots"
	right.add_child(_inspect_slots_label)

	_inspect_slots_box = VBoxContainer.new()
	_inspect_slots_box.add_theme_constant_override("separation", 4)
	right.add_child(_inspect_slots_box)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)

	var close_hint := Label.new()
	close_hint.text = "[X / Esc] close"
	close_hint.modulate = Color(0.7, 0.7, 0.7)
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(close_hint)

func _select_tab(i: int) -> void:
	_tab_idx = clampi(i, 0, TABS.size() - 1)
	for j in range(_tab_buttons.size()):
		_tab_buttons[j].button_pressed = (j == _tab_idx)

func _select_category(i: int) -> void:
	_category_idx = clampi(i, 0, CATEGORIES.size() - 1)
	for j in range(_category_buttons.size()):
		_category_buttons[j].button_pressed = (j == _category_idx)
	if _open:
		_refresh_list()
		_refresh_preview()

func _category_matches(kind: String) -> bool:
	var kinds: Array = CATEGORIES[_category_idx].kinds
	if kinds.is_empty():
		return true
	if kinds.has("__misc__"):
		return not NAMED_KINDS.has(kind)
	return kinds.has(kind)

func _on_inventory_changed() -> void:
	if _open:
		_refresh()

func _refresh() -> void:
	_refresh_list()
	_refresh_preview()
	_refresh_sort_label()
	_refresh_encumbrance()
	_refresh_status()

func _refresh_list() -> void:
	if _inventory == null:
		return
	var entries: Array = _inventory.entries()
	# Filter by current category before sort.
	var filtered: Array = []
	for e in entries:
		if _category_matches(String(e.kind)):
			filtered.append(e)
	entries = filtered
	entries.sort_custom(_compare_entries)

	# Try to keep the current selection across refresh by matching uid first
	# (instances are unique) then id (stackables). If the prior selection is
	# gone (drop, full stack consumed), fall back to the row that was *below*
	# it — same index in the new list, clamped — so the user's scroll position
	# stays put. If they were on the last row, that clamp puts them on the
	# new last row, which is the row that was previously above.
	var prev: Dictionary = _selected_row()
	var prev_idx: int = -1
	var sel: PackedInt32Array = _list.get_selected_items()
	if sel.size() > 0:
		prev_idx = sel[0]
	_list.clear()
	_rows.clear()
	var new_select := -1
	var equipped_uid: int = int(_inventory.get("equipped_uid"))
	for i in range(entries.size()):
		var e: Dictionary = entries[i]
		var label: String = _row_label(e, equipped_uid)
		_list.add_item(label)
		var icon_color: Color = Items.item_color(String(e.id))
		if bool(e.is_instance):
			# Tint the swatch toward quality color so legendary stuff pops.
			var qc: Color = Items.quality_color(int(e.quality))
			icon_color = icon_color.lerp(qc, 0.45)
		_list.set_item_icon(i, _swatch_icon(icon_color))
		_rows.append(e)
		if not prev.is_empty():
			if bool(e.is_instance) and bool(prev.get("is_instance", false)):
				if int(e.uid) == int(prev.get("uid", 0)):
					new_select = i
			elif not bool(e.is_instance) and not bool(prev.get("is_instance", false)):
				if String(e.id) == String(prev.get("id", "")):
					new_select = i
	if _list.item_count > 0:
		if new_select < 0:
			new_select = clampi(prev_idx, 0, _list.item_count - 1) if prev_idx >= 0 else 0
		_list.select(new_select)
		_list.ensure_current_is_visible()

func _row_label(e: Dictionary, equipped_uid: int) -> String:
	if bool(e.is_instance):
		var slot: int = int(_inventory.find_favorite_slot_for_uid(int(e.uid)))
		var fav_marker: String = "  ★%d" % slot if slot > 0 else ""
		var eq_marker: String = "  [E]" if int(e.uid) == equipped_uid else ""
		var qual: String = Items.quality_name(int(e.quality))
		var tier: Dictionary = Items.condition_tier(float(e.condition), String(e.kind))
		return "%s %s   %.2f kg   ¢%d   %s %d%%%s%s" % [
			qual, e.name, e.weight_total, e.value_each,
			tier.name, int(round(float(e.condition) * 100.0)),
			fav_marker, eq_marker,
		]
	return "%s   x%d   %.2f kg   ¢%d" % [
		e.name, e.count, e.weight_total, e.value_each,
	]

func _compare_entries(a: Dictionary, b: Dictionary) -> bool:
	var lt := false
	match _sort_mode:
		SortMode.NAME:
			lt = a.name.naturalnocasecmp_to(b.name) < 0
		SortMode.WEIGHT_TOTAL:
			lt = a.weight_total < b.weight_total
		SortMode.VALUE_EACH:
			lt = a.value_each < b.value_each
	return lt if _sort_asc else not lt

func _selected_row() -> Dictionary:
	var sel: PackedInt32Array = _list.get_selected_items()
	if sel.is_empty():
		return {}
	var idx: int = sel[0]
	if idx < 0 or idx >= _rows.size():
		return {}
	return _rows[idx]

func _selected_id() -> String:
	var r: Dictionary = _selected_row()
	return String(r.get("id", ""))

func _selected_uid() -> int:
	var r: Dictionary = _selected_row()
	return int(r.get("uid", 0))

func _selected_is_instance() -> bool:
	var r: Dictionary = _selected_row()
	return bool(r.get("is_instance", false))

func _refresh_preview() -> void:
	var row: Dictionary = _selected_row()
	if row.is_empty():
		_preview_color.color = Color(0.2, 0.2, 0.2)
		_preview_name.text = "—"
		_preview_kind.text = ""
		_preview_per_weight.text = ""
		_preview_value.text = ""
		_preview_count.text = ""
		_equip_btn.disabled = true
		_equip_btn.text = "Equip [Enter / Dbl-Click]"
		return
	var id: String = String(row.id)
	_preview_color.color = Items.item_color(id)
	_preview_name.text = Items.item_name(id)
	_preview_per_weight.text = "Weight: %.2f kg each" % Items.item_weight(id)
	_preview_value.text = "Value:  ¢%d each" % Items.item_value(id)
	if bool(row.is_instance):
		var qual: String = Items.quality_name(int(row.quality))
		var qcol: Color = Items.quality_color(int(row.quality))
		var tier: Dictionary = Items.condition_tier(float(row.condition), Items.item_kind(id))
		_preview_kind.text = "%s · %s · %s %d%%" % [
			Items.item_kind(id).capitalize(), qual,
			tier.name, int(round(float(row.condition) * 100.0)),
		]
		_preview_kind.modulate = qcol
		_preview_count.text = "Held:    1 instance  (%.2f kg)" % Items.item_weight(id)
	else:
		_preview_kind.text = Items.item_kind(id).capitalize()
		_preview_kind.modulate = Color(0.75, 0.85, 1.0)
		var c: int = _inventory.counts.get(id, 0)
		_preview_count.text = "Held:    x%d  (%.2f kg total)" % [c, Items.item_weight(id) * c]
	var equippable: bool = bool(row.is_instance) and Items.item_kind(id) == "weapon"
	_equip_btn.disabled = not equippable
	var equipped_uid: int = int(_inventory.get("equipped_uid"))
	if equippable and int(row.uid) == equipped_uid:
		_equip_btn.text = "Equipped"
	else:
		_equip_btn.text = "Equip [Enter / Dbl-Click]"

func _refresh_sort_label() -> void:
	var arrow := "↑" if _sort_asc else "↓"
	_sort_label.text = "Sort: %s %s" % [SORT_LABELS[_sort_mode], arrow]

func _refresh_encumbrance() -> void:
	if _inventory == null:
		return
	_encumbrance_label.text = "Encumbrance: %.2f / %.2f kg" % [
		_inventory.total_weight(), _inventory.MAX_WEIGHT,
	]

func _refresh_status() -> void:
	if _binding_mode:
		var id: String = _selected_id()
		var n: String = Items.item_name(id) if id != "" else "(nothing)"
		_status_label.text = "Bind %s to slot — press 1..9 (Esc cancels)" % n
		_status_label.visible = true
	else:
		_status_label.visible = false
		_status_label.text = ""

func _swatch_icon(color: Color) -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)

func _equip_selected() -> void:
	var row: Dictionary = _selected_row()
	if row.is_empty() or not bool(row.is_instance):
		return
	if Items.item_kind(String(row.id)) != "weapon":
		return
	var uid: int = int(row.uid)
	# Toggle: clicking the already-equipped weapon unequips it.
	if int(_inventory.get("equipped_uid")) == uid:
		_inventory.set_equipped(0)
	else:
		_inventory.set_equipped(uid)

func _on_item_clicked(_idx: int, _pos: Vector2, _btn: int) -> void:
	# Single click only selects + previews. Double-click (or Enter) equips so
	# the inspect/preview flow doesn't accidentally swap your weapon.
	_refresh_preview()

func _on_item_activated(_idx: int) -> void:
	# Enter / double-click on row → equip.
	_equip_selected()

func _on_list_gui_input(event: InputEvent) -> void:
	# Mouse wheel cycles row selection instead of scrolling the ItemList — the
	# list almost never overflows and selection-by-wheel matches how the rest
	# of the menu (W/S, ↑/↓) navigates.
	if event is InputEventMouseButton and event.pressed:
		var btn: int = (event as InputEventMouseButton).button_index
		if btn == MOUSE_BUTTON_WHEEL_UP:
			_move_selection(-1)
			_list.accept_event()
		elif btn == MOUSE_BUTTON_WHEEL_DOWN:
			_move_selection(1)
			_list.accept_event()

func _open_inspect() -> void:
	var row: Dictionary = _selected_row()
	if row.is_empty():
		return
	var id: String = String(row.id)
	_inspect_color.color = Items.item_color(id)
	if bool(row.is_instance):
		var qual: String = Items.quality_name(int(row.quality))
		var qcol: Color = Items.quality_color(int(row.quality))
		var tier: Dictionary = Items.condition_tier(float(row.condition), Items.item_kind(id))
		_inspect_name.text = "%s %s" % [qual, Items.item_name(id)]
		_inspect_name.modulate = qcol
		_inspect_stats.text = "Kind:       %s\nQuality:    %s\nCondition:  %s (%d%%)\nWeight:     %.2f kg\nValue:      ¢%d" % [
			Items.item_kind(id).capitalize(), qual,
			tier.name, int(round(float(row.condition) * 100.0)),
			Items.item_weight(id), Items.item_value(id),
		]
	else:
		_inspect_name.text = Items.item_name(id)
		_inspect_name.modulate = Color(1, 1, 1)
		var c: int = _inventory.counts.get(id, 0)
		_inspect_stats.text = "Kind:    %s\nWeight:  %.2f kg each\nValue:   ¢%d each\nHeld:    x%d  (%.2f kg)" % [
			Items.item_kind(id).capitalize(),
			Items.item_weight(id),
			Items.item_value(id),
			c,
			Items.item_weight(id) * c,
		]
	_inspect_desc.text = Items.item_desc(id)
	for child in _inspect_slots_box.get_children():
		child.queue_free()
	var slots: Array = Items.item_slots(id)
	if slots.is_empty():
		var none := Label.new()
		none.text = "(no attachment slots)"
		none.modulate = Color(0.7, 0.7, 0.7)
		_inspect_slots_box.add_child(none)
	else:
		for s in slots:
			var slot_row := HBoxContainer.new()
			slot_row.add_theme_constant_override("separation", 12)
			var name_lbl := Label.new()
			name_lbl.text = "• %s" % String(s)
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slot_row.add_child(name_lbl)
			var status := Label.new()
			status.text = "(empty)"
			status.modulate = Color(0.65, 0.65, 0.65)
			slot_row.add_child(status)
			_inspect_slots_box.add_child(slot_row)
	_inspect_root.visible = true

func _close_inspect() -> void:
	_inspect_root.visible = false

func _is_inspect_open() -> bool:
	return _inspect_root != null and _inspect_root.visible

func _build_split_overlay() -> void:
	_split_root = Control.new()
	_split_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_split_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_split_root.visible = false
	_root.add_child(_split_root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_split_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_split_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	center.add_child(panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 24)
	pad.add_theme_constant_override("margin_right", 24)
	pad.add_theme_constant_override("margin_top", 20)
	pad.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(pad)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	pad.add_child(box)

	_split_title = Label.new()
	_split_title.add_theme_font_size_override("font_size", 22)
	_split_title.text = "Drop how many?"
	box.add_child(_split_title)

	var sl_row := HBoxContainer.new()
	sl_row.add_theme_constant_override("separation", 12)
	box.add_child(sl_row)

	_split_slider = HSlider.new()
	_split_slider.min_value = 1
	_split_slider.max_value = 1
	_split_slider.step = 1
	_split_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_split_slider.value_changed.connect(_on_split_slider_changed)
	sl_row.add_child(_split_slider)

	_split_spin = SpinBox.new()
	_split_spin.min_value = 1
	_split_spin.max_value = 1
	_split_spin.step = 1
	_split_spin.custom_minimum_size = Vector2(110, 0)
	_split_spin.value_changed.connect(_on_split_spin_changed)
	sl_row.add_child(_split_spin)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	btns.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(btns)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel [R / Esc]"
	cancel_btn.add_theme_font_size_override("font_size", 16)
	cancel_btn.pressed.connect(_close_split)
	btns.add_child(cancel_btn)

	var drop_btn := Button.new()
	drop_btn.text = "Drop [E]"
	drop_btn.add_theme_font_size_override("font_size", 16)
	drop_btn.pressed.connect(_confirm_split)
	btns.add_child(drop_btn)

func _open_split(id: String, max_n: int) -> void:
	_split_id = id
	_split_max = max_n
	_split_syncing = true
	_split_slider.max_value = max_n
	_split_slider.value = max_n
	_split_spin.max_value = max_n
	_split_spin.value = max_n
	_split_syncing = false
	_split_title.text = "Drop how many %s?  (1..%d)" % [Items.item_name(id), max_n]
	_split_root.visible = true
	_split_spin.get_line_edit().grab_focus()
	_split_spin.get_line_edit().select_all()

func _close_split() -> void:
	if _split_root != null:
		_split_root.visible = false
	_split_id = ""
	_split_max = 0
	if _list != null:
		_list.grab_focus()

func _is_split_open() -> bool:
	return _split_root != null and _split_root.visible

func _on_split_slider_changed(v: float) -> void:
	if _split_syncing:
		return
	_split_syncing = true
	_split_spin.value = v
	_split_syncing = false

func _on_split_spin_changed(v: float) -> void:
	if _split_syncing:
		return
	_split_syncing = true
	_split_slider.value = v
	_split_syncing = false

func _confirm_split() -> void:
	if not _is_split_open():
		return
	var id: String = _split_id
	var n: int = clampi(int(round(_split_spin.value)), 1, _split_max)
	_close_split()
	if id == "" or _inventory == null:
		return
	var player: Node = _inventory.get_parent()
	if player != null and player.has_method("drop_item"):
		player.drop_item(id, n)

func _input(event: InputEvent) -> void:
	if not _open:
		return

	# Inspect overlay swallows close + esc until dismissed.
	if _is_inspect_open():
		if event.is_action_pressed("inspect") or event.is_action_pressed("ui_cancel"):
			_close_inspect()
			get_viewport().set_input_as_handled()
		return

	# Split-drop overlay: E confirms, R/Esc cancels. Eat other shortcuts so
	# the user can type into the spinbox without triggering sort/etc.
	if _is_split_open():
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("reload"):
			_close_split()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("interact"):
			_confirm_split()
			get_viewport().set_input_as_handled()
			return
		return

	# Favorite-binding mode: next 1-9 binds, Esc cancels.
	if _binding_mode:
		if event.is_action_pressed("ui_cancel"):
			_binding_mode = false
			_refresh_status()
			get_viewport().set_input_as_handled()
			return
		for slot in range(1, 10):
			if event.is_action_pressed("equip_%d" % slot):
				var uid: int = _selected_uid()
				if uid != 0:
					_inventory.set_favorite(slot, uid)
				_binding_mode = false
				_refresh_status()
				get_viewport().set_input_as_handled()
				return
		# Eat all other input while waiting so the player doesn't accidentally
		# also trigger sort/etc.
		if event is InputEventKey and event.pressed:
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_menu") or event.is_action_pressed("ui_cancel"):
		_set_open(false)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("inspect"):
		_open_inspect()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("reload"):
		var shift: bool = Input.is_key_pressed(KEY_SHIFT)
		_drop_selected(shift)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("favorite"):
		# Only instance items (weapons/apparel) get favorite slots — they're
		# the only things you'd want bound to a hotkey.
		if _selected_uid() != 0:
			_binding_mode = true
			_refresh_status()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("nav_left"):
		_select_category((_category_idx - 1 + CATEGORIES.size()) % CATEGORIES.size())
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("nav_right"):
		_select_category((_category_idx + 1) % CATEGORIES.size())
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("sort_mode"):
		var modes := SortMode.values()
		var i: int = modes.find(_sort_mode)
		_sort_mode = modes[(i + 1) % modes.size()]
		_refresh_list()
		_refresh_sort_label()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("sort_dir"):
		_sort_asc = not _sort_asc
		_refresh_list()
		_refresh_sort_label()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("move_forward"):
		_move_selection(-1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("move_back"):
		_move_selection(1)
		get_viewport().set_input_as_handled()
		return

func _drop_selected(shift: bool = false) -> void:
	var row: Dictionary = _selected_row()
	if row.is_empty() or _inventory == null:
		return
	var player: Node = _inventory.get_parent()
	if player == null:
		return
	if bool(row.is_instance) and player.has_method("drop_instance"):
		player.drop_instance(int(row.uid))
		return
	if not player.has_method("drop_item"):
		return
	var count: int = int(row.get("count", 1))
	# Shift-R always dumps the full stack — bypasses the split prompt entirely.
	if shift:
		player.drop_item(String(row.id), count)
		return
	if count > SPLIT_PROMPT_THRESHOLD:
		_open_split(String(row.id), count)
		return
	player.drop_item(String(row.id), 1)

func _move_selection(direction: int) -> void:
	if _list.item_count == 0:
		return
	var sel: PackedInt32Array = _list.get_selected_items()
	var cur: int = sel[0] if sel.size() > 0 else 0
	var nxt: int = clampi(cur + direction, 0, _list.item_count - 1)
	if nxt != cur:
		_list.select(nxt)
		_list.ensure_current_is_visible()
		_refresh_preview()
