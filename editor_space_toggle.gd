extends PanelContainer

# Bottom-left "Global / Local" toggle. Tells the gizmo whether translate
# axes/handles align with world axes (Global) or the selected target's
# own basis (Local). Persists for the session.

signal space_changed(use_local: bool)

var _btn_global: Button = null
var _btn_local: Button = null
var _use_local: bool = false

func _ready() -> void:
	var hb := HBoxContainer.new()
	add_child(hb)
	_btn_global = Button.new()
	_btn_global.text = "Global"
	_btn_global.toggle_mode = true
	_btn_global.button_pressed = true
	_btn_global.pressed.connect(func(): _set_local(false))
	hb.add_child(_btn_global)
	_btn_local = Button.new()
	_btn_local.text = "Local"
	_btn_local.toggle_mode = true
	_btn_local.pressed.connect(func(): _set_local(true))
	hb.add_child(_btn_local)

func _set_local(v: bool) -> void:
	_use_local = v
	if _btn_global != null:
		_btn_global.button_pressed = not v
	if _btn_local != null:
		_btn_local.button_pressed = v
	emit_signal("space_changed", v)

func is_local() -> bool:
	return _use_local
