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
var _sort_label: Label
var _encumbrance_label: Label

func _ready() -> void:
	layer = 50
	if inventory_path != NodePath():
		_inventory = get_node(inventory_path)
	if _inventory != null and _inventory.has_signal("changed"):
		_inventory.changed.connect(_on_inventory_changed)
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
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# Dark backdrop.
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

	# Content (inventory tab — list left, preview right).
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
	_list.item_clicked.connect(func(_i, _pos, _btn): _refresh_preview())
	content.add_child(_list)

	var preview_panel := PanelContainer.new()
	preview_panel.custom_minimum_size = Vector2(280, 0)
	content.add_child(preview_panel)

	var pv_margin := MarginContainer.new()
	pv_margin.add_theme_constant_override("margin_left", 12)
	pv_margin.add_theme_constant_override("margin_right", 12)
	pv_margin.add_theme_constant_override("margin_top", 12)
	pv_margin.add_theme_constant_override("margin_bottom", 12)
	preview_panel.add_child(pv_margin)

	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	pv_margin.add_child(pv)

	_preview_color = ColorRect.new()
	_preview_color.custom_minimum_size = Vector2(0, 140)
	_preview_color.color = Color(0.2, 0.2, 0.2)
	pv.add_child(_preview_color)

	_preview_name = Label.new()
	_preview_name.add_theme_font_size_override("font_size", 22)
	_preview_name.text = "—"
	pv.add_child(_preview_name)

	_preview_per_weight = Label.new()
	_preview_per_weight.text = ""
	pv.add_child(_preview_per_weight)

	_preview_value = Label.new()
	_preview_value.text = ""
	pv.add_child(_preview_value)

	_preview_count = Label.new()
	_preview_count.text = ""
	pv.add_child(_preview_count)

	vb.add_child(HSeparator.new())

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 24)
	vb.add_child(footer)

	_sort_label = Label.new()
	_sort_label.text = ""
	footer.add_child(_sort_label)

	var hint := Label.new()
	hint.text = "[Z] sort mode  [V] direction  [↑↓ / W S / scroll] navigate  [← →] tabs  [Tab/Esc] close"
	hint.modulate = Color(0.75, 0.75, 0.75)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_child(hint)

	_encumbrance_label = Label.new()
	_encumbrance_label.text = ""
	_encumbrance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(_encumbrance_label)

	_select_tab(0)

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

func _refresh_list() -> void:
	if _inventory == null:
		push_warning("menu: _inventory null")
		return
	var entries: Array = _inventory.entries()
	entries.sort_custom(_compare_entries)

	# Try to keep the current selection on the same item id.
	var selected_id: String = ""
	var sel: PackedInt32Array = _list.get_selected_items()
	if sel.size() > 0 and sel[0] < _row_ids.size():
		selected_id = _row_ids[sel[0]]

	_list.clear()
	_row_ids.clear()
	var new_select := -1
	for i in range(entries.size()):
		var e: Dictionary = entries[i]
		var label: String = "%s   x%d   %.2f kg   ¢%d" % [
			e.name, e.count, e.weight_total, e.value_each,
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

func _refresh_preview() -> void:
	var sel: PackedInt32Array = _list.get_selected_items()
	if sel.is_empty():
		_preview_color.color = Color(0.2, 0.2, 0.2)
		_preview_name.text = "—"
		_preview_per_weight.text = ""
		_preview_value.text = ""
		_preview_count.text = ""
		return
	var idx: int = sel[0]
	if idx < 0 or idx >= _row_ids.size():
		return
	var id: String = _row_ids[idx]
	_preview_color.color = Items.item_color(id)
	_preview_name.text = Items.item_name(id)
	_preview_per_weight.text = "Weight: %.2f kg each" % Items.item_weight(id)
	_preview_value.text = "Value:  ¢%d each" % Items.item_value(id)
	var c: int = _inventory.counts.get(id, 0)
	_preview_count.text = "Held:    x%d  (%.2f kg total)" % [c, Items.item_weight(id) * c]

func _refresh_sort_label() -> void:
	var arrow := "↑" if _sort_asc else "↓"
	_sort_label.text = "Sort: %s %s" % [SORT_LABELS[_sort_mode], arrow]

func _refresh_encumbrance() -> void:
	if _inventory == null:
		return
	_encumbrance_label.text = "Encumbrance: %.2f / %.2f kg" % [
		_inventory.total_weight(), _inventory.MAX_WEIGHT,
	]

# Build a tiny solid-color icon so the ItemList row carries a swatch.
func _swatch_icon(color: Color) -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)

func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_menu") or event.is_action_pressed("ui_cancel"):
		_set_open(false)
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
	# W/S nav forwarded to ItemList (since W/S are bound to movement, not ui_*).
	if event.is_action_pressed("move_forward"):
		_move_selection(-1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("move_back"):
		_move_selection(1)
		get_viewport().set_input_as_handled()
		return

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
