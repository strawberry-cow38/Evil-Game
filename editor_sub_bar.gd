extends PanelContainer

# Sub-bar shown directly under the top category bar. Contents change
# based on the selected category. For Terrain → Heights we expose the
# five height tools the user requested; other categories currently
# render an "(empty)" placeholder so the layout still makes sense.

signal tool_picked(tool_id: String)

const TOOLS_BY_CATEGORY: Dictionary = {
	"terrain": [
		# Heights group. Future groups (textures, foliage) get sibling rows.
		{"id": "t_raise",   "label": "Raise"},
		{"id": "t_lower",   "label": "Lower"},
		{"id": "t_flatten", "label": "Flatten"},
		{"id": "t_smooth",  "label": "Smooth"},
		{"id": "t_ramp",    "label": "Ramp"},
	],
	"environment": [],
	"spawns": [
		{"id": "s_player_place",  "label": "Place Player Spawn"},
		{"id": "s_player_delete", "label": "Delete Player Spawn"},
		{"id": "s_items",         "label": "Items"},
		{"id": "s_items_remove",  "label": "Remove Items"},
	],
	"objects": [
		{"id": "o_objects", "label": "Objects"},
	],
	"level": [
		{"id": "l_effects", "label": "Effects"},
	],
}

var _hbox: HBoxContainer
var _buttons: Dictionary = {}
var _selected: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_hbox = HBoxContainer.new()
	_hbox.add_theme_constant_override("separation", 4)
	add_child(_hbox)

func show_category(category: String) -> void:
	for c in _hbox.get_children():
		c.queue_free()
	_buttons.clear()
	var tools: Array = TOOLS_BY_CATEGORY.get(category, [])
	if tools.is_empty():
		var lbl := Label.new()
		lbl.text = "(no tools yet)"
		lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
		lbl.add_theme_font_size_override("font_size", 14)
		_hbox.add_child(lbl)
		return
	for t in tools:
		var b := Button.new()
		b.text = t.label
		b.custom_minimum_size = Vector2(96, 28)
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func(): _select(String(t.id)))
		_hbox.add_child(b)
		_buttons[t.id] = b

func _select(tool_id: String) -> void:
	_selected = tool_id
	for k in _buttons.keys():
		var btn: Button = _buttons[k]
		btn.modulate = Color(1, 1, 1, 1) if k == tool_id else Color(0.75, 0.75, 0.75, 1)
	tool_picked.emit(tool_id)
