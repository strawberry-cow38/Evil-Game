extends Control

# Top-level entry point. Two paths into the app:
#  - Play: pick a saved map, then load main.tscn (the FPS sandbox)
#  - Editor: pick a saved map (or "Empty Map"), then load editor.tscn
# The picker is a runtime-built overlay so main_menu.tscn stays simple.

const EDITOR_SCENE := "res://editor.tscn"
const PLAY_SCENE := "res://main.tscn"

const MODE_PLAY := "play"
const MODE_EDITOR := "editor"

var _picker_root: Control
var _picker_title: Label
var _picker_list: ItemList
var _picker_play_empty_btn: Button
var _picker_open_btn: Button
var _picker_cancel_btn: Button
var _saves: Array = []
var _mode: String = MODE_PLAY

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	$Buttons/Play.pressed.connect(func(): _open_picker(MODE_PLAY))
	$Buttons/Editor.pressed.connect(func(): _open_picker(MODE_EDITOR))
	$Buttons/Quit.pressed.connect(_on_quit)
	_build_picker()

func _on_quit() -> void:
	get_tree().quit()

func _build_picker() -> void:
	_picker_root = Control.new()
	_picker_root.set_anchors_preset(PRESET_FULL_RECT)
	_picker_root.mouse_filter = MOUSE_FILTER_STOP
	_picker_root.visible = false
	add_child(_picker_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	dim.mouse_filter = MOUSE_FILTER_IGNORE
	_picker_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	_picker_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 20)
	pad.add_theme_constant_override("margin_right", 20)
	pad.add_theme_constant_override("margin_top", 20)
	pad.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(pad)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	pad.add_child(v)
	_picker_title = Label.new()
	_picker_title.add_theme_font_size_override("font_size", 24)
	_picker_title.text = "Select Map"
	v.add_child(_picker_title)
	v.add_child(HSeparator.new())
	_picker_list = ItemList.new()
	_picker_list.custom_minimum_size = Vector2(0, 280)
	_picker_list.allow_reselect = true
	_picker_list.item_activated.connect(func(_i): _on_picker_open())
	v.add_child(_picker_list)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	v.add_child(btns)
	_picker_play_empty_btn = Button.new()
	_picker_play_empty_btn.text = "Empty Map"
	_picker_play_empty_btn.pressed.connect(_on_picker_empty)
	btns.add_child(_picker_play_empty_btn)
	_picker_open_btn = Button.new()
	_picker_open_btn.text = "Open Selected"
	_picker_open_btn.pressed.connect(_on_picker_open)
	btns.add_child(_picker_open_btn)
	_picker_cancel_btn = Button.new()
	_picker_cancel_btn.text = "Cancel [Esc]"
	_picker_cancel_btn.pressed.connect(_close_picker)
	btns.add_child(_picker_cancel_btn)

func _open_picker(mode: String) -> void:
	_mode = mode
	_picker_title.text = "Pick a map for %s" % ("Play" if mode == MODE_PLAY else "Editor")
	# Empty Map only really makes sense for the editor (Play needs terrain
	# to stand on), but the play scene falls back to its hardcoded flat
	# ground when MapState is empty so it's still a valid path.
	_picker_play_empty_btn.text = "New Empty Map" if mode == MODE_EDITOR else "Default Map"
	_saves = MapIO.list_saves()
	_picker_list.clear()
	for s in _saves:
		_picker_list.add_item(String(s.name))
	if _saves.size() > 0:
		_picker_list.select(0)
	_picker_root.visible = true

func _close_picker() -> void:
	_picker_root.visible = false

func _on_picker_empty() -> void:
	# Wipe MapState so the target scene starts from defaults.
	MapState.clear()
	_enter_target()

func _on_picker_open() -> void:
	var sel: PackedInt32Array = _picker_list.get_selected_items()
	if sel.size() == 0:
		return
	var save_name: String = String(_saves[sel[0]].name)
	if not MapIO.load_map(save_name):
		_picker_title.text = "Load failed: %s" % save_name
		return
	_enter_target()

func _enter_target() -> void:
	if _mode == MODE_PLAY:
		get_tree().change_scene_to_file(PLAY_SCENE)
	else:
		get_tree().change_scene_to_file(EDITOR_SCENE)

func _input(event: InputEvent) -> void:
	if _picker_root != null and _picker_root.visible and event.is_action_pressed("ui_cancel"):
		_close_picker()
		get_viewport().set_input_as_handled()
