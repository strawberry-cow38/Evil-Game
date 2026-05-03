extends PanelContainer

# Bottom-left brush controls. Two stacked slider rows: brush radius
# (metres) and brush strength (0–1 multiplier the editor applies on
# top of each tool's base rate).

signal radius_changed(r: float)
signal strength_changed(s: float)

const RADIUS_MIN := 1.0
const RADIUS_MAX := 30.0

var _radius_slider: HSlider
var _radius_label: Label
var _strength_slider: HSlider
var _strength_label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	_radius_label = Label.new()
	_radius_label.add_theme_font_size_override("font_size", 14)
	_radius_label.text = "Brush radius: 4.0 m"
	vbox.add_child(_radius_label)
	_radius_slider = HSlider.new()
	_radius_slider.min_value = RADIUS_MIN
	_radius_slider.max_value = RADIUS_MAX
	_radius_slider.step = 0.5
	_radius_slider.value = 4.0
	_radius_slider.custom_minimum_size = Vector2(240, 18)
	_radius_slider.value_changed.connect(_on_radius)
	vbox.add_child(_radius_slider)

	_strength_label = Label.new()
	_strength_label.add_theme_font_size_override("font_size", 14)
	_strength_label.text = "Brush strength: 1.00"
	vbox.add_child(_strength_label)
	_strength_slider = HSlider.new()
	_strength_slider.min_value = 0.05
	_strength_slider.max_value = 100.0
	_strength_slider.step = 0.05
	_strength_slider.value = 1.0
	_strength_slider.custom_minimum_size = Vector2(240, 18)
	_strength_slider.value_changed.connect(_on_strength)
	vbox.add_child(_strength_slider)

func set_radius(r: float) -> void:
	_radius_slider.value = r

func set_strength(s: float) -> void:
	_strength_slider.value = s

func _on_radius(v: float) -> void:
	_radius_label.text = "Brush radius: %.1f m" % v
	radius_changed.emit(v)

func _on_strength(v: float) -> void:
	_strength_label.text = "Brush strength: %.2f" % v
	strength_changed.emit(v)
