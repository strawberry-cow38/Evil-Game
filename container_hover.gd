extends CanvasLayer

# Hover panel that pops up while the player is looking at a crate. Lists the
# crate's contents, lets the player scroll through entries, and shows the
# loot/open hints. The actual loot + open actions are driven by player.gd —
# this node is just the read-out + selection state.

const MAX_VISIBLE_ROWS := 8

var _container: Node = null
var _selected_index: int = 0

var _root: Control
var _bg: ColorRect
var _title: Label
var _list: VBoxContainer
var _footer: Label
var _empty_label: Label

func _ready() -> void:
	layer = 25
	_build()
	visible = false

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	# Top-right anchored panel so it doesn't fight with the center crosshair
	# or the bottom prompt.
	_root.offset_left = -340
	_root.offset_right = -16
	_root.offset_top = 90
	_root.offset_bottom = 380
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_bg = ColorRect.new()
	_bg.color = Color(0, 0, 0, 0.55)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bg)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_right = -12
	v.offset_top = 8
	v.offset_bottom = -8
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(v)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	_title.add_theme_color_override("font_color", Color(1, 0.95, 0.6))
	v.add_child(_title)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	v.add_child(_list)
	_empty_label = Label.new()
	_empty_label.text = "(empty)"
	_empty_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	v.add_child(_empty_label)
	_footer = Label.new()
	_footer.add_theme_font_size_override("font_size", 13)
	_footer.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_footer.text = "[E] Take  [R] Open  [Wheel] Scroll"
	v.add_child(_footer)

func show_for(container: Node) -> void:
	if container == null:
		hide_panel()
		return
	if container != _container:
		_selected_index = 0
	_container = container
	visible = true
	_refresh()

func hide_panel() -> void:
	_container = null
	visible = false

func current_container() -> Node:
	return _container

# Returns the entry dict the player is currently pointing at, or {} if the
# crate is empty / hover not active.
func selected_entry() -> Dictionary:
	if _container == null or not _container.has_method("entries"):
		return {}
	var es: Array = _container.entries()
	if es.is_empty():
		return {}
	var i: int = clampi(_selected_index, 0, es.size() - 1)
	return es[i]

func cycle(delta_i: int) -> void:
	if _container == null or not _container.has_method("entries"):
		return
	var es: Array = _container.entries()
	if es.is_empty():
		return
	_selected_index = posmod(_selected_index + delta_i, es.size())
	_refresh()

func refresh() -> void:
	_refresh()

func _refresh() -> void:
	if _container == null:
		return
	var label_name: String = "Container"
	if "label_name" in _container:
		label_name = String(_container.label_name)
	var es: Array = _container.entries()
	_title.text = "%s — %d item%s" % [label_name, es.size(), "" if es.size() == 1 else "s"]
	for c in _list.get_children():
		c.queue_free()
	if es.is_empty():
		_empty_label.visible = true
		return
	_empty_label.visible = false
	_selected_index = clampi(_selected_index, 0, es.size() - 1)
	# Window the list around the selected index so long crates stay readable.
	var start: int = clampi(_selected_index - MAX_VISIBLE_ROWS / 2, 0, max(0, es.size() - MAX_VISIBLE_ROWS))
	var end: int = mini(es.size(), start + MAX_VISIBLE_ROWS)
	for i in range(start, end):
		var e: Dictionary = es[i]
		var row := Label.new()
		var prefix: String = "▶ " if i == _selected_index else "   "
		var qty: String = "" if bool(e.get("is_instance", false)) else "  x%d" % int(e.get("count", 1))
		row.text = "%s%s%s" % [prefix, String(e.get("name", "")), qty]
		if i == _selected_index:
			row.add_theme_color_override("font_color", Color(1, 0.95, 0.4))
		_list.add_child(row)
	if es.size() > MAX_VISIBLE_ROWS:
		var more := Label.new()
		more.add_theme_font_size_override("font_size", 12)
		more.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		more.text = "(%d / %d)" % [_selected_index + 1, es.size()]
		_list.add_child(more)
