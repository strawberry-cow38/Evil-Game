extends PanelContainer

# Horizontal bar of category buttons across the top of the editor.
# Emits category_picked(id) when one is clicked. The currently selected
# category gets highlighted; everything else is dimmed.

signal category_picked(id: String)

const CATEGORIES: Array = [
	{"id": "terrain",     "label": "Terrain"},
	{"id": "environment", "label": "Environment"},
	{"id": "spawns",      "label": "Spawns"},
	{"id": "objects",     "label": "Objects"},
	{"id": "level",       "label": "Level"},
]

var _buttons: Dictionary = {}
var _selected: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	add_child(hbox)
	for cat in CATEGORIES:
		var b := Button.new()
		b.text = cat.label
		b.custom_minimum_size = Vector2(110, 32)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(func(): _select(cat.id))
		hbox.add_child(b)
		_buttons[cat.id] = b

func select_category(id: String) -> void:
	_select(id)

func _select(id: String) -> void:
	_selected = id
	for k in _buttons.keys():
		var btn: Button = _buttons[k]
		btn.modulate = Color(1, 1, 1, 1) if k == id else Color(0.7, 0.7, 0.7, 1)
	category_picked.emit(id)
