extends CanvasLayer

# ESC settings overlay — built entirely in code so we don't need a .tscn.
# Reads/writes through the GameSettings autoload, which handles persistence
# (user://settings.cfg) and pushes values onto the scene's WorldEnvironment,
# Sun, and viewport.

const TONEMAP_OPTIONS: Array = [
	{"label": "Linear",   "value": int(Environment.TONE_MAPPER_LINEAR)},
	{"label": "Reinhard", "value": int(Environment.TONE_MAPPER_REINHARDT)},
	{"label": "Filmic",   "value": int(Environment.TONE_MAPPER_FILMIC)},
	{"label": "ACES",     "value": int(Environment.TONE_MAPPER_ACES)},
]

const MSAA_OPTIONS: Array = [
	{"label": "Off", "value": 0},
	{"label": "2x",  "value": 1},
	{"label": "4x",  "value": 2},
	{"label": "8x",  "value": 3},
]

const SCALING_OPTIONS: Array = [
	{"label": "Bilinear", "value": 0},
	{"label": "FSR 1.0",  "value": 1},
	{"label": "FSR 2.2",  "value": 2},
]

var _open := false
var _root: Control
var _captured_mouse_was: int = Input.MOUSE_MODE_VISIBLE

func _ready() -> void:
	layer = 100  # Above HUD + most UI.
	_build_ui()
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

func is_open() -> bool:
	return _open

func toggle() -> void:
	if _open:
		close()
	else:
		open()

func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	_captured_mouse_was = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	Input.mouse_mode = _captured_mouse_was

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.75)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 120)
	margin.add_theme_constant_override("margin_right", 120)
	margin.add_theme_constant_override("margin_top", 80)
	margin.add_theme_constant_override("margin_bottom", 80)
	_root.add_child(margin)

	var panel := PanelContainer.new()
	margin.add_child(panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 24)
	pad.add_theme_constant_override("margin_right", 24)
	pad.add_theme_constant_override("margin_top", 18)
	pad.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(pad)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	pad.add_child(vb)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 28)
	vb.add_child(title)

	vb.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)

	var grid := VBoxContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("separation", 4)
	scroll.add_child(grid)

	_section(grid, "Post-processing")
	_dropdown(grid, "Tonemap", "tonemap_mode", TONEMAP_OPTIONS)
	_checkbox(grid, "Bloom / Glow", "glow_enabled")
	_slider(grid, "Glow intensity", "glow_intensity", 0.0, 2.0, 0.05)
	_checkbox(grid, "SSAO (contact occlusion)", "ssao_enabled")
	_checkbox(grid, "SSIL (screen-space GI)", "ssil_enabled")
	_checkbox(grid, "SSR (reflections)", "ssr_enabled")
	_checkbox(grid, "SDFGI (real-time GI)", "sdfgi_enabled")
	_checkbox(grid, "Fog", "fog_enabled")

	_section(grid, "Sun & shadows")
	_checkbox(grid, "Sun shadows", "sun_shadow_enabled")
	_slider(grid, "Shadow distance (m)", "sun_shadow_distance", 20.0, 400.0, 5.0)
	_slider(grid, "Sun angular size (soft penumbra)", "sun_angular_distance", 0.0, 4.0, 0.1)

	_section(grid, "Anti-aliasing & scaling")
	_dropdown(grid, "MSAA", "msaa_3d", MSAA_OPTIONS)
	_checkbox(grid, "TAA", "taa")
	_checkbox(grid, "FXAA", "fxaa")
	_dropdown(grid, "Upscaling", "scaling_mode", SCALING_OPTIONS)
	_slider(grid, "Render scale", "render_scale", 0.5, 2.0, 0.05)

	vb.add_child(HSeparator.new())

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	vb.add_child(footer)

	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.pressed.connect(_on_reset)
	footer.add_child(reset)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = "Close [Esc]"
	close_btn.pressed.connect(close)
	footer.add_child(close_btn)

func _section(parent: Node, title: String) -> void:
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.modulate = Color(1.0, 0.9, 0.5)
	parent.add_child(lbl)

func _row(parent: Node, label_text: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	parent.add_child(hb)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(280, 0)
	hb.add_child(lbl)
	return hb

func _checkbox(parent: Node, label_text: String, key: String) -> void:
	var hb := _row(parent, label_text)
	var cb := CheckBox.new()
	cb.button_pressed = bool(GameSettings.get_value(key))
	cb.toggled.connect(func(v: bool): GameSettings.set_value(key, v))
	hb.add_child(cb)

func _slider(parent: Node, label_text: String, key: String, lo: float, hi: float, step: float) -> void:
	var hb := _row(parent, label_text)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = float(GameSettings.get_value(key))
	sl.custom_minimum_size = Vector2(260, 0)
	hb.add_child(sl)
	var val := Label.new()
	val.text = "%.2f" % sl.value
	val.custom_minimum_size = Vector2(60, 0)
	hb.add_child(val)
	sl.value_changed.connect(func(v: float):
		val.text = "%.2f" % v
		GameSettings.set_value(key, v)
	)

func _dropdown(parent: Node, label_text: String, key: String, options: Array) -> void:
	var hb := _row(parent, label_text)
	var ob := OptionButton.new()
	var selected_idx := 0
	var current = GameSettings.get_value(key)
	for i in range(options.size()):
		var opt: Dictionary = options[i]
		ob.add_item(String(opt["label"]), int(opt["value"]))
		if int(opt["value"]) == int(current):
			selected_idx = i
	ob.select(selected_idx)
	ob.item_selected.connect(func(idx: int):
		GameSettings.set_value(key, ob.get_item_id(idx))
	)
	hb.add_child(ob)

func _on_reset() -> void:
	GameSettings.reset_to_defaults()
	# Rebuild UI to reflect new defaults.
	for c in _root.get_children():
		c.queue_free()
	_build_ui()
