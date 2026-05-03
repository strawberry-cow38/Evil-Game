extends CanvasLayer

const Items = preload("res://items.gd")

const TAB_INVENTORY := "Inventory"
const TABS: Array = [TAB_INVENTORY]   # extensible — add stats/map/etc here later

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
var _sort_mode: SortMode = SortMode.NAME
var _sort_asc := true

# Cached order of item ids matching the current ItemList rows.
var _row_ids: Array[String] = []

# Favorite-binding mode: when true, next 1..9 press binds the selected item.
var _binding_mode := false

# UI nodes (built in _ready).
var _root: Control
var _tab_box: HBoxContainer
var _tab_buttons: Array[Button] = []
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
	_equip_btn.text = "Equip [Enter]"
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
	_hint_label.text = "[Enter/Click] equip  [X] inspect  [R] drop  [Q] favorite→1-9  [Z]/[V] sort  [WS/↑↓] nav  [Tab/Esc] close"
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
	_select_tab(0)

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
	entries.sort_custom(_compare_entries)

	var selected_id: String = ""
	var sel: PackedInt32Array = _list.get_selected_items()
	if sel.size() > 0 and sel[0] < _row_ids.size():
		selected_id = _row_ids[sel[0]]

	var equipped: String = String(_inventory.get("equipped"))
	_list.clear()
	_row_ids.clear()
	var new_select := -1
	for i in range(entries.size()):
		var e: Dictionary = entries[i]
		var slot: int = int(_inventory.find_favorite_slot(e.id))
		var fav_marker: String = "  ★%d" % slot if slot > 0 else ""
		var eq_marker: String = "  [E]" if e.id == equipped else ""
		var label: String = "%s   x%d   %.2f kg   ¢%d%s%s" % [
			e.name, e.count, e.weight_total, e.value_each, fav_marker, eq_marker,
		]
		_list.add_item(label)
		_list.set_item_icon(i, _swatch_icon(Items.item_color(e.id)))
		_row_ids.append(e.id)
		if e.id == selected_id:
			new_select = i
	if _list.item_count > 0:
		if new_select < 0:
			new_select = 0
		_list.select(new_select)

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

func _selected_id() -> String:
	var sel: PackedInt32Array = _list.get_selected_items()
	if sel.is_empty():
		return ""
	var idx: int = sel[0]
	if idx < 0 or idx >= _row_ids.size():
		return ""
	return _row_ids[idx]

func _refresh_preview() -> void:
	var id: String = _selected_id()
	if id == "":
		_preview_color.color = Color(0.2, 0.2, 0.2)
		_preview_name.text = "—"
		_preview_kind.text = ""
		_preview_per_weight.text = ""
		_preview_value.text = ""
		_preview_count.text = ""
		_equip_btn.disabled = true
		_equip_btn.text = "Equip [Enter]"
		return
	_preview_color.color = Items.item_color(id)
	_preview_name.text = Items.item_name(id)
	_preview_kind.text = Items.item_kind(id).capitalize()
	_preview_per_weight.text = "Weight: %.2f kg each" % Items.item_weight(id)
	_preview_value.text = "Value:  ¢%d each" % Items.item_value(id)
	var c: int = _inventory.counts.get(id, 0)
	_preview_count.text = "Held:    x%d  (%.2f kg total)" % [c, Items.item_weight(id) * c]
	var equippable: bool = Items.item_kind(id) == "weapon"
	_equip_btn.disabled = not equippable
	if equippable and String(_inventory.get("equipped")) == id:
		_equip_btn.text = "Equipped"
	else:
		_equip_btn.text = "Equip [Enter]"

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
	var id: String = _selected_id()
	if id == "":
		return
	if Items.item_kind(id) != "weapon":
		return
	# Toggle: clicking the already-equipped weapon unequips it.
	if String(_inventory.get("equipped")) == id:
		_inventory.set_equipped("")
	else:
		_inventory.set_equipped(id)

func _on_item_clicked(_idx: int, _pos: Vector2, btn: int) -> void:
	_refresh_preview()
	if btn == MOUSE_BUTTON_LEFT:
		_equip_selected()

func _on_item_activated(_idx: int) -> void:
	# Enter/double-click on row.
	_equip_selected()

func _open_inspect() -> void:
	var id: String = _selected_id()
	if id == "":
		return
	_inspect_color.color = Items.item_color(id)
	_inspect_name.text = Items.item_name(id)
	_inspect_desc.text = Items.item_desc(id)
	var c: int = _inventory.counts.get(id, 0)
	_inspect_stats.text = "Kind:    %s\nWeight:  %.2f kg each\nValue:   ¢%d each\nHeld:    x%d  (%.2f kg)" % [
		Items.item_kind(id).capitalize(),
		Items.item_weight(id),
		Items.item_value(id),
		c,
		Items.item_weight(id) * c,
	]
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
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			var name_lbl := Label.new()
			name_lbl.text = "• %s" % String(s)
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_lbl)
			var status := Label.new()
			status.text = "(empty)"
			status.modulate = Color(0.65, 0.65, 0.65)
			row.add_child(status)
			_inspect_slots_box.add_child(row)
	_inspect_root.visible = true

func _close_inspect() -> void:
	_inspect_root.visible = false

func _is_inspect_open() -> bool:
	return _inspect_root != null and _inspect_root.visible

func _input(event: InputEvent) -> void:
	if not _open:
		return

	# Inspect overlay swallows close + esc until dismissed.
	if _is_inspect_open():
		if event.is_action_pressed("inspect") or event.is_action_pressed("ui_cancel"):
			_close_inspect()
			get_viewport().set_input_as_handled()
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
				var id: String = _selected_id()
				if id != "":
					_inventory.set_favorite(slot, id)
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
		_drop_selected()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("favorite"):
		if _selected_id() != "":
			_binding_mode = true
			_refresh_status()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("nav_left"):
		_select_tab((_tab_idx - 1 + TABS.size()) % TABS.size())
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("nav_right"):
		_select_tab((_tab_idx + 1) % TABS.size())
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

func _drop_selected() -> void:
	var id: String = _selected_id()
	if id == "" or _inventory == null:
		return
	# Inventory is a child of the Player node — call drop_item there.
	var player: Node = _inventory.get_parent()
	if player == null or not player.has_method("drop_item"):
		return
	player.drop_item(id, 1)

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
