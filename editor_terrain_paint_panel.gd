extends PanelContainer

# Side panel shown while the terrain Paint tool is active. Exposes the
# material palette (dirt / grass / stone / sand) and brush footprint
# shape (circle / square). Brush radius + strength live on the shared
# radius widget, same as the other terrain tools.

signal material_changed(mat_id: int)
signal shape_changed(shape: String)

const MATERIALS: Array = [
	{"id": 0, "label": "Dirt",  "color": Color(0.42, 0.30, 0.18, 1.0)},
	{"id": 1, "label": "Grass", "color": Color(0.32, 0.55, 0.20, 1.0)},
	{"id": 2, "label": "Stone", "color": Color(0.55, 0.55, 0.55, 1.0)},
	{"id": 3, "label": "Sand",  "color": Color(0.84, 0.78, 0.55, 1.0)},
]

var _mat_buttons: Array[Button] = []
var _shape_buttons: Dictionary = {}
var _selected_mat: int = 1
var _selected_shape: String = "circle"

func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(220, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	var hdr := Label.new()
	hdr.text = "Terrain paint"
	vb.add_child(hdr)
	var mat_lbl := Label.new()
	mat_lbl.text = "Material"
	mat_lbl.modulate = Color(1, 1, 1, 0.7)
	vb.add_child(mat_lbl)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	vb.add_child(grid)
	for m in MATERIALS:
		var b := Button.new()
		b.text = m.label
		b.custom_minimum_size = Vector2(96, 36)
		var sb := StyleBoxFlat.new()
		sb.bg_color = m.color
		sb.border_width_left = 2
		sb.border_width_right = 2
		sb.border_width_top = 2
		sb.border_width_bottom = 2
		sb.border_color = Color(0, 0, 0, 0.6)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.add_theme_color_override("font_color", Color(1, 1, 1, 1) if _luminance(m.color) < 0.55 else Color(0, 0, 0, 1))
		var mid: int = int(m.id)
		b.pressed.connect(func(): _on_mat_picked(mid))
		grid.add_child(b)
		_mat_buttons.append(b)
	var shape_lbl := Label.new()
	shape_lbl.text = "Brush shape"
	shape_lbl.modulate = Color(1, 1, 1, 0.7)
	vb.add_child(shape_lbl)
	var shape_row := HBoxContainer.new()
	shape_row.add_theme_constant_override("separation", 4)
	vb.add_child(shape_row)
	for s in ["circle", "square"]:
		var sb := Button.new()
		sb.text = s.capitalize()
		sb.custom_minimum_size = Vector2(96, 28)
		var sid: String = s
		sb.pressed.connect(func(): _on_shape_picked(sid))
		shape_row.add_child(sb)
		_shape_buttons[s] = sb
	_refresh_highlight()

func _luminance(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b

func _on_mat_picked(mat_id: int) -> void:
	_selected_mat = mat_id
	_refresh_highlight()
	material_changed.emit(mat_id)

func _on_shape_picked(s: String) -> void:
	_selected_shape = s
	_refresh_highlight()
	shape_changed.emit(s)

func _refresh_highlight() -> void:
	for i in range(_mat_buttons.size()):
		_mat_buttons[i].modulate = Color(1, 1, 1, 1) if i == _selected_mat else Color(0.7, 0.7, 0.7, 1)
	for k in _shape_buttons.keys():
		var btn: Button = _shape_buttons[k]
		btn.modulate = Color(1, 1, 1, 1) if k == _selected_shape else Color(0.7, 0.7, 0.7, 1)

func get_material_id() -> int:
	return _selected_mat

func get_shape() -> String:
	return _selected_shape
