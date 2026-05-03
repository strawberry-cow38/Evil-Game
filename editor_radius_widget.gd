extends PanelContainer

# Bottom-left brush-radius control. Slider + numeric label. Emits
# radius_changed(meters) on every drag tick.

signal radius_changed(r: float)

const RADIUS_MIN := 1.0
const RADIUS_MAX := 30.0

var _slider: HSlider
var _label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var vbox := VBoxContainer.new()
	add_child(vbox)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	_label.text = "Brush radius: 4.0 m"
	vbox.add_child(_label)
	_slider = HSlider.new()
	_slider.min_value = RADIUS_MIN
	_slider.max_value = RADIUS_MAX
	_slider.step = 0.5
	_slider.value = 4.0
	_slider.custom_minimum_size = Vector2(220, 18)
	_slider.value_changed.connect(_on_value)
	vbox.add_child(_slider)

func set_radius(r: float) -> void:
	_slider.value = r

func _on_value(v: float) -> void:
	_label.text = "Brush radius: %.1f m" % v
	radius_changed.emit(v)
