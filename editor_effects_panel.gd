extends PanelContainer

# Right-side picker panel for the Level → Effects tool. Search bar at
# the top, scrollable A-Z list below. Emits effect_picked(id) when the
# user selects an entry. The editor uses that id to "arm" placement —
# subsequent E presses drop a wireframe box of that effect into the
# world.

signal effect_picked(id: String)

var _search: LineEdit
var _list_box: VBoxContainer
var _scroll: ScrollContainer
var _selected_id: String = ""
var _buttons: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(260, 0)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)
	var title := Label.new()
	title.text = "Effects"
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
	_rebuild_list("")

func get_selected_id() -> String:
	return _selected_id

func _on_search_changed(t: String) -> void:
	_rebuild_list(t)

func _rebuild_list(query: String) -> void:
	for c in _list_box.get_children():
		c.queue_free()
	_buttons.clear()
	for e in EditorEffectsRegistry.filtered(query):
		var b := Button.new()
		b.text = String(e.label)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 13)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var id: String = String(e.id)
		b.pressed.connect(func(): _on_pick(id))
		_list_box.add_child(b)
		_buttons[id] = b
	_apply_selection_highlight()

func _on_pick(id: String) -> void:
	_selected_id = id
	_apply_selection_highlight()
	effect_picked.emit(id)

func _apply_selection_highlight() -> void:
	for k in _buttons.keys():
		var btn: Button = _buttons[k]
		btn.modulate = Color(1.0, 1.0, 0.6, 1.0) if k == _selected_id else Color(1, 1, 1, 1)
