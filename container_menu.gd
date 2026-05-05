extends CanvasLayer

# Full-screen looting menu: player inventory on the left, container on the
# right. Open with R while looking at a crate; close with R or Esc. Single
# E press / double-click transfers the highlighted row to the other side.
# T does a bulk take-or-store of every item matching the active category
# tab — direction is decided by which side has focus when T is pressed.

const Items = preload("res://items.gd")

# Mirrors menu.gd's category layout so the two menus feel consistent.
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
const NAMED_KINDS: Array = ["weapon", "apparel", "armor", "clothing", "ammo", "medical", "food", "resource", "building", "material"]

const SIDE_PLAYER := 0
const SIDE_CONTAINER := 1

var _inventory: Node = null
var _container: Node = null
var _open := false
# Each panel keeps its own active category so the player can browse one
# slice on their side and a different slice on the crate side.
var _player_category_idx := 0
var _container_category_idx := 0
var _hover_side := SIDE_PLAYER
# Closing the menu blocks immediate reopens for a short window so the same R
# press that closed the menu doesn't re-trigger the open path on the player.
var _close_locked_until_msec: int = 0

# Cached row metadata kept in parallel for the T-key bulk operation, which
# iterates the filtered category instead of the current selection.
var _player_rows: Array = []
var _container_rows: Array = []

var _root: Control
var _bg: ColorRect
var _player_category_buttons: Array[Button] = []
var _container_category_buttons: Array[Button] = []
var _player_title: Label
var _container_title: Label
var _player_list: Tree
var _container_list: Tree
var _player_root: TreeItem
var _container_root: TreeItem
var _status_label: Label
var _hint_label: Label

func _ready() -> void:
	layer = 50
	_build_ui()
	_root.visible = false

func is_open() -> bool:
	return _open

func open(inventory: Node, container: Node) -> void:
	if inventory == null or container == null:
		return
	# Listen so transfers initiated by the menu update both sides immediately.
	if _inventory != inventory and _inventory != null and _inventory.has_signal("changed"):
		if _inventory.changed.is_connected(_on_inv_changed):
			_inventory.changed.disconnect(_on_inv_changed)
	_inventory = inventory
	_container = container
	if _inventory.has_signal("changed") and not _inventory.changed.is_connected(_on_inv_changed):
		_inventory.changed.connect(_on_inv_changed)
	if _container.has_signal("changed") and not _container.changed.is_connected(_on_inv_changed):
		_container.changed.connect(_on_inv_changed)
	_open = true
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_status_label.text = ""
	_refresh()
	# Focus the player side by default so E does something sane out of the gate.
	_hover_side = SIDE_PLAYER
	if _player_root != null:
		var first: TreeItem = _player_root.get_first_child()
		if first != null:
			first.select(0)
			_player_list.grab_focus()

func close() -> void:
	_open = false
	_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _container != null and _container.has_signal("changed") and _container.changed.is_connected(_on_inv_changed):
		_container.changed.disconnect(_on_inv_changed)
	_container = null
	_close_locked_until_msec = Time.get_ticks_msec() + 250

func can_reopen() -> bool:
	return Time.get_ticks_msec() >= _close_locked_until_msec

func _on_inv_changed() -> void:
	if _open:
		_refresh()

# --- UI construction ------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_bg = ColorRect.new()
	_bg.color = Color(0, 0, 0, 0.78)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bg)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 60
	v.offset_right = -60
	v.offset_top = 30
	v.offset_bottom = -30
	v.add_theme_constant_override("separation", 8)
	_root.add_child(v)
	# --- Side-by-side panels (each owns its own category tab row).
	var sides := HBoxContainer.new()
	sides.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sides.add_theme_constant_override("separation", 16)
	v.add_child(sides)
	var left := _build_panel("YOU", true)
	var right := _build_panel("CRATE", false)
	sides.add_child(left)
	sides.add_child(right)
	# --- Footer hint + status.
	_hint_label = Label.new()
	_hint_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_hint_label.text = "[E / Dbl-click] Transfer one    [T] Take/Store all of category    [A/D] Category (focused side)    [R / Esc] Close"
	v.add_child(_hint_label)
	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", Color(1, 0.5, 0.4))
	v.add_child(_status_label)

func _build_panel(title: String, is_player: bool) -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	var t := Label.new()
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", Color(1, 0.95, 0.6))
	t.text = title
	col.add_child(t)
	# Per-side category tab row — each panel filters independently so the
	# player can browse, say, Ammo on their side and Weapons on the crate side.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	col.add_child(tabs)
	var side_id := SIDE_PLAYER if is_player else SIDE_CONTAINER
	var buttons: Array[Button] = []
	for i in range(CATEGORIES.size()):
		var b := Button.new()
		b.toggle_mode = true
		b.text = String(CATEGORIES[i].label)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_category_pressed.bind(side_id, i))
		tabs.add_child(b)
		buttons.append(b)
	buttons[0].button_pressed = true
	# Tree with fixed-width columns matching menu.gd. Same column widths +
	# alignments so the two menus feel like the same surface.
	var lst := Tree.new()
	lst.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lst.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lst.columns = 6
	lst.column_titles_visible = true
	lst.hide_root = true
	lst.select_mode = Tree.SELECT_ROW
	lst.allow_reselect = true
	lst.add_theme_font_size_override("font_size", 16)
	# Cell padding so empty Quality/Cond cells still hold their column space
	# instead of letting neighbours bleed across.
	lst.add_theme_constant_override("inner_item_margin_left", 10)
	lst.add_theme_constant_override("inner_item_margin_right", 10)
	lst.set_column_title(0, "Name")
	lst.set_column_expand(0, true)
	lst.set_column_expand_ratio(0, 2)
	lst.set_column_clip_content(0, true)
	lst.set_column_custom_minimum_width(0, 260)
	lst.set_column_title(1, "Qty")
	lst.set_column_expand(1, false)
	lst.set_column_custom_minimum_width(1, 80)
	lst.set_column_title_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
	lst.set_column_title(2, "Quality")
	lst.set_column_expand(2, false)
	lst.set_column_custom_minimum_width(2, 130)
	lst.set_column_title(3, "Cond")
	lst.set_column_expand(3, false)
	lst.set_column_custom_minimum_width(3, 90)
	lst.set_column_title_alignment(3, HORIZONTAL_ALIGNMENT_RIGHT)
	lst.set_column_title(4, "Weight")
	lst.set_column_expand(4, false)
	lst.set_column_custom_minimum_width(4, 110)
	lst.set_column_title_alignment(4, HORIZONTAL_ALIGNMENT_RIGHT)
	lst.set_column_title(5, "Value")
	lst.set_column_expand(5, false)
	lst.set_column_custom_minimum_width(5, 100)
	lst.set_column_title_alignment(5, HORIZONTAL_ALIGNMENT_RIGHT)
	lst.focus_entered.connect(_on_list_focus.bind(side_id))
	lst.cell_selected.connect(_on_list_focus.bind(side_id))
	lst.item_activated.connect(_on_list_activated.bind(side_id))
	col.add_child(lst)
	if is_player:
		_player_title = t
		_player_list = lst
		_player_category_buttons = buttons
	else:
		_container_title = t
		_container_list = lst
		_container_category_buttons = buttons
	return col

# --- Filter / refresh -----------------------------------------------------

func _matches_category(kind: String, category_idx: int) -> bool:
	var kinds: Array = CATEGORIES[category_idx].kinds
	if kinds.is_empty():
		return true
	if kinds.has("__misc__"):
		return not NAMED_KINDS.has(kind)
	return kinds.has(kind)

func _filtered(entries: Array, category_idx: int) -> Array:
	var out: Array = []
	for e in entries:
		if _matches_category(String(e.get("kind", "")), category_idx):
			out.append(e)
	out.sort_custom(func(a, b): return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	return out

func _refresh() -> void:
	if _inventory == null or _container == null:
		return
	# Player side.
	_player_rows = _filtered(_inventory.entries(), _player_category_idx)
	_fill_tree(_player_list, _player_rows, true)
	_player_root = _player_list.get_root()
	var enc: float = _inventory.total_weight() if _inventory.has_method("total_weight") else 0.0
	var max_w: float = float(_inventory.MAX_WEIGHT)
	_player_title.text = "YOU — %.1f / %.1f kg" % [enc, max_w]
	# Container side.
	_container_rows = _filtered(_container.entries(), _container_category_idx)
	_fill_tree(_container_list, _container_rows, false)
	_container_root = _container_list.get_root()
	var label_name: String = "CRATE"
	if "label_name" in _container:
		label_name = String(_container.label_name).to_upper()
	var total: int = _container.total_count() if _container.has_method("total_count") else _container_rows.size()
	# Show fill / capacity so the player can see when the crate is nearly
	# full before they try to dump more into it.
	var w_str: String = ""
	if _container.has_method("total_weight") and "max_weight" in _container:
		w_str = "  (%.1f / %.1f kg)" % [_container.total_weight(), float(_container.max_weight)]
	_container_title.text = "%s — %d item%s%s" % [label_name, total, "" if total == 1 else "s", w_str]

func _fill_tree(tree: Tree, rows: Array, is_player: bool) -> void:
	# Preserve selection by uid (instance) or id (stackable) before clearing.
	var prev: Dictionary = {}
	var cur_item: TreeItem = tree.get_selected()
	if cur_item != null:
		var meta = cur_item.get_metadata(0)
		if meta is Dictionary:
			prev = meta
	tree.clear()
	var root: TreeItem = tree.create_item()
	var equipped_uid: int = 0
	if is_player and _inventory != null:
		equipped_uid = int(_inventory.get("equipped_uid"))
	var to_select: TreeItem = null
	for e in rows:
		var item: TreeItem = tree.create_item(root)
		_fill_row(item, e, equipped_uid)
		item.set_metadata(0, e)
		if not prev.is_empty() and to_select == null:
			if bool(e.get("is_instance", false)) and bool(prev.get("is_instance", false)):
				if int(e.get("uid", 0)) == int(prev.get("uid", 0)):
					to_select = item
			elif not bool(e.get("is_instance", false)) and not bool(prev.get("is_instance", false)):
				if String(e.get("id", "")) == String(prev.get("id", "")):
					to_select = item
	if to_select == null:
		to_select = root.get_first_child()
	if to_select != null:
		to_select.select(0)
		tree.scroll_to_item(to_select)

func _fill_row(item: TreeItem, e: Dictionary, equipped_uid: int) -> void:
	var id: String = String(e.get("id", ""))
	var is_inst: bool = bool(e.get("is_instance", false))
	var name: String = String(e.get("name", ""))
	if is_inst and equipped_uid != 0 and int(e.get("uid", 0)) == equipped_uid:
		name += " [E]"
	var icon_color: Color = Items.item_color(id)
	if is_inst:
		icon_color = icon_color.lerp(Items.quality_color(int(e.get("quality", 0))), 0.45)
	item.set_icon(0, _swatch_icon(icon_color))
	item.set_icon_max_width(0, 22)
	item.set_text(0, name)
	if is_inst:
		item.set_text(1, "")
		var qual: int = int(e.get("quality", 0))
		item.set_text(2, Items.quality_name(qual))
		item.set_custom_color(2, Items.quality_color(qual))
		item.set_text(3, "%d%%" % int(round(float(e.get("condition", 1.0)) * 100.0)))
	else:
		item.set_text(1, "x%d" % int(e.get("count", 1)))
		item.set_text(2, "")
		item.set_text(3, "")
	item.set_text(4, "%.2f kg" % float(e.get("weight_total", 0.0)))
	item.set_text(5, "¢%d" % int(e.get("value_each", 0)))
	for col in [1, 3, 4, 5]:
		item.set_text_alignment(col, HORIZONTAL_ALIGNMENT_RIGHT)

func _swatch_icon(color: Color) -> ImageTexture:
	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)

# --- Input ----------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("reload"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("nav_left"):
		_cycle_focused_category(-1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("nav_right"):
		_cycle_focused_category(1)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		# T = take/store category (Tab not bound by the project, so no conflict).
		if event.keycode == KEY_T:
			_take_or_store_category()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("interact"):
			# E transfers focused row from focused side.
			_transfer_focused()
			get_viewport().set_input_as_handled()

func _cycle_focused_category(dir: int) -> void:
	var n: int = CATEGORIES.size()
	if n <= 0:
		return
	if _hover_side == SIDE_PLAYER:
		var i: int = (_player_category_idx + dir + n) % n
		_on_category_pressed(SIDE_PLAYER, i)
	else:
		var j: int = (_container_category_idx + dir + n) % n
		_on_category_pressed(SIDE_CONTAINER, j)

func _on_category_pressed(side: int, idx: int) -> void:
	var buttons: Array[Button] = _player_category_buttons if side == SIDE_PLAYER else _container_category_buttons
	for i in range(buttons.size()):
		buttons[i].button_pressed = (i == idx)
	if side == SIDE_PLAYER:
		_player_category_idx = idx
	else:
		_container_category_idx = idx
	_hover_side = side
	_refresh()

func _on_list_focus(side: int) -> void:
	_hover_side = side

func _on_list_activated(side: int) -> void:
	_hover_side = side
	_transfer_focused()

# --- Transfer logic -------------------------------------------------------

func _selected_entry(side: int) -> Dictionary:
	var tree: Tree = _player_list if side == SIDE_PLAYER else _container_list
	var item: TreeItem = tree.get_selected()
	if item == null:
		return {}
	var meta = item.get_metadata(0)
	return meta if meta is Dictionary else {}

func _transfer_focused() -> void:
	if _inventory == null or _container == null:
		return
	var entry: Dictionary = _selected_entry(_hover_side)
	if entry.is_empty():
		return
	if _hover_side == SIDE_PLAYER:
		_store(entry)
	else:
		_take(entry)

# Player → container. Weight-checked: containers now have a finite cap,
# so peel back the count until it fits (or bail) the same way _take does
# for the inventory side. Never remove from the source until we know the
# destination will accept the same quantity.
func _store(entry: Dictionary) -> void:
	if bool(entry.get("is_instance", false)):
		var uid: int = int(entry.get("uid", 0))
		if uid == 0:
			return
		var inst: Dictionary = _inventory.remove_instance(uid)
		if inst.is_empty():
			return
		if not _container.add_instance(inst):
			# Crate refused — restore so the player isn't punished for trying.
			_inventory.add_instance(inst)
			_status_label.text = "Crate full: %s" % String(entry.get("name", ""))
		else:
			_status_label.text = ""
	else:
		var id: String = String(entry.get("id", ""))
		var want: int = int(entry.get("count", 1))
		if id == "" or want <= 0:
			return
		var fits: int = want
		while fits > 0 and not _container.can_add(id, fits):
			fits -= 1
		if fits <= 0:
			_status_label.text = "Crate full: %s" % String(entry.get("name", ""))
			return
		if _inventory.remove(id, fits):
			_container.add(id, fits)
			_status_label.text = "" if fits == want else "Partial: %d / %d" % [fits, want]

# Container → player. Weight-checked: peel back the count until it fits, or
# bail with a status if even one unit can't be carried.
func _take(entry: Dictionary) -> void:
	if bool(entry.get("is_instance", false)):
		var uid: int = int(entry.get("uid", 0))
		if uid == 0:
			return
		var inst: Dictionary = _container.remove_instance(uid)
		if inst.is_empty():
			return
		if not _inventory.add_instance(inst):
			_container.add_instance(inst)
			_status_label.text = "Too heavy: %s" % String(entry.get("name", ""))
		else:
			_status_label.text = ""
	else:
		var id: String = String(entry.get("id", ""))
		var want: int = int(entry.get("count", 1))
		if id == "" or want <= 0:
			return
		var fits: int = want
		while fits > 0 and not _inventory.can_add(id, fits):
			fits -= 1
		if fits <= 0:
			_status_label.text = "Too heavy: %s" % String(entry.get("name", ""))
			return
		if _container.remove(id, fits):
			_inventory.add(id, fits)
			_status_label.text = "" if fits == want else "Partial: %d / %d" % [fits, want]

func _take_or_store_category() -> void:
	if _inventory == null or _container == null:
		return
	if _hover_side == SIDE_PLAYER:
		# Store every player row matching the current category.
		var rows: Array = _player_rows.duplicate()
		for entry in rows:
			_store(entry)
		_status_label.text = "Stored: %s" % String(CATEGORIES[_player_category_idx].label)
	else:
		var rows2: Array = _container_rows.duplicate()
		var any_skipped: bool = false
		for entry in rows2:
			var before: float = _inventory.total_weight() if _inventory.has_method("total_weight") else 0.0
			_take(entry)
			# Detect skip — _take leaves the container row in place if too heavy.
			if _inventory.has_method("total_weight") and is_equal_approx(_inventory.total_weight(), before):
				any_skipped = true
		_status_label.text = "Took: %s%s" % [
			String(CATEGORIES[_container_category_idx].label),
			"  (some too heavy)" if any_skipped else ""
		]
