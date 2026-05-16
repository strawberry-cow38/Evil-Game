extends PanelContainer

# Sub-bar shown directly under the top category bar. Contents change
# based on the selected category. Each entry is a TOOL GROUP — one
# button representing a family of related modes (e.g. Heights covers
# raise/lower/flatten/smooth/ramp). The sub-bar only knows about the
# top-level group; the editor maps the group to a default sub-tool and
# binds Q/W/E/R hotkeys to swap mode within it.

signal tool_picked(tool_id: String)

const TOOLS_BY_CATEGORY: Dictionary = {
	"terrain": [
		{"id": "g_heights",   "label": "Heights"},
		{"id": "g_materials", "label": "Materials"},
		{"id": "g_foliage",   "label": "Foliage"},
	],
	"environment": [
		{"id": "e_lighting", "label": "Lighting"},
		{"id": "e_roads",    "label": "Roads"},
		{"id": "e_fences",   "label": "Fences"},
	],
	"spawns": [
		{"id": "g_spawn_player", "label": "Player Spawn"},
		{"id": "g_spawn_items",  "label": "Items"},
		{"id": "g_spawn_actors", "label": "Actors"},
	],
	"objects": [
		{"id": "o_objects", "label": "Objects"},
	],
	"level": [
		{"id": "l_effects",  "label": "Effects"},
		{"id": "l_triggers", "label": "Triggers"},
	],
}

var _hbox: HBoxContainer
var _buttons: Dictionary = {}
var _selected: String = ""
var _current_category: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_hbox = HBoxContainer.new()
	_hbox.add_theme_constant_override("separation", 4)
	add_child(_hbox)

func show_category(category: String) -> void:
	_current_category = category
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
	for i in range(tools.size()):
		var t: Dictionary = tools[i]
		var b := Button.new()
		b.text = "%d  %s" % [i + 1, t.label]
		b.custom_minimum_size = Vector2(110, 28)
		b.add_theme_font_size_override("font_size", 14)
		var tid: String = String(t.id)
		b.pressed.connect(func(): _select(tid))
		_hbox.add_child(b)
		_buttons[tid] = b

func tool_id_at(index: int) -> String:
	# 1-based lookup matching the number-key shown on each button. Returns
	# "" if the index is out of range for the current category.
	var tools: Array = TOOLS_BY_CATEGORY.get(_current_category, [])
	if index < 1 or index > tools.size():
		return ""
	return String(tools[index - 1].id)

func select_tool(tool_id: String) -> void:
	# External entry point: highlight + emit as if the user clicked.
	if _buttons.has(tool_id):
		_select(tool_id)

func _select(tool_id: String) -> void:
	_selected = tool_id
	for k in _buttons.keys():
		var btn: Button = _buttons[k]
		btn.modulate = Color(1, 1, 1, 1) if k == tool_id else Color(0.75, 0.75, 0.75, 1)
	tool_picked.emit(tool_id)
