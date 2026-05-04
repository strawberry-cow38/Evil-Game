extends PanelContainer

# Esc-toggled pause overlay for the editor. Three responsibilities:
#  - Save the current MapState to a named slot in user://maps/
#  - Load a previously-saved slot back into MapState
#  - Bail to the main menu without losing what's in the editor (the
#    autoload outlives the scene swap so the next launch can re-edit).
# Built at runtime by editor.gd so editor.tscn doesn't need a new node.

signal resume_pressed
signal save_pressed(name: String)
signal load_pressed(name: String)
signal delete_pressed(name: String)
signal main_menu_pressed
signal new_pressed

var _save_input: LineEdit
var _save_list: ItemList
var _status: Label
var _saves: Array = []

func _ready() -> void:
	custom_minimum_size = Vector2(540, 0)
	mouse_filter = MOUSE_FILTER_STOP
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 18)
	pad.add_theme_constant_override("margin_right", 18)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 16)
	add_child(pad)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pad.add_child(v)
	var title := Label.new()
	title.text = "Editor Menu"
	title.add_theme_font_size_override("font_size", 22)
	v.add_child(title)
	v.add_child(HSeparator.new())
	# Save row: name field + Save button.
	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 8)
	v.add_child(save_row)
	_save_input = LineEdit.new()
	_save_input.placeholder_text = "save name"
	_save_input.size_flags_horizontal = SIZE_EXPAND_FILL
	save_row.add_child(_save_input)
	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.pressed.connect(_on_save)
	save_row.add_child(save_btn)
	# Load list + buttons row.
	var lbl := Label.new()
	lbl.text = "Saved maps:"
	v.add_child(lbl)
	_save_list = ItemList.new()
	_save_list.custom_minimum_size = Vector2(0, 220)
	_save_list.allow_reselect = true
	_save_list.item_activated.connect(func(_i): _on_load())
	_save_list.item_selected.connect(_on_select)
	v.add_child(_save_list)
	var load_row := HBoxContainer.new()
	load_row.add_theme_constant_override("separation", 8)
	v.add_child(load_row)
	var load_btn := Button.new()
	load_btn.text = "Load Selected"
	load_btn.pressed.connect(_on_load)
	load_row.add_child(load_btn)
	var del_btn := Button.new()
	del_btn.text = "Delete Selected"
	del_btn.pressed.connect(_on_delete)
	load_row.add_child(del_btn)
	v.add_child(HSeparator.new())
	# Footer actions.
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	v.add_child(foot)
	var resume_btn := Button.new()
	resume_btn.text = "Resume [Esc]"
	resume_btn.pressed.connect(func(): resume_pressed.emit())
	foot.add_child(resume_btn)
	var new_btn := Button.new()
	new_btn.text = "New Map"
	new_btn.pressed.connect(func(): new_pressed.emit())
	foot.add_child(new_btn)
	var menu_btn := Button.new()
	menu_btn.text = "Main Menu"
	menu_btn.pressed.connect(func(): main_menu_pressed.emit())
	foot.add_child(menu_btn)
	_status = Label.new()
	_status.text = ""
	_status.modulate = Color(0.85, 0.85, 0.85)
	v.add_child(_status)

func open() -> void:
	visible = true
	refresh()
	_save_input.grab_focus()

func close() -> void:
	visible = false

func is_open() -> bool:
	return visible

func refresh() -> void:
	_saves = MapIO.list_saves()
	_save_list.clear()
	for s in _saves:
		_save_list.add_item(String(s.name))

func set_status(msg: String) -> void:
	_status.text = msg

func _selected_name() -> String:
	var sel: PackedInt32Array = _save_list.get_selected_items()
	if sel.size() == 0:
		return ""
	return String(_saves[sel[0]].name)

func _on_save() -> void:
	var save_name: String = _save_input.text.strip_edges()
	if save_name == "":
		set_status("Type a save name first.")
		return
	save_pressed.emit(save_name)

func _on_load() -> void:
	var n: String = _selected_name()
	if n == "":
		set_status("Pick a save first.")
		return
	load_pressed.emit(n)

func _on_delete() -> void:
	var n: String = _selected_name()
	if n == "":
		set_status("Pick a save first.")
		return
	delete_pressed.emit(n)

func _on_select(idx: int) -> void:
	# Pre-fill the save field with the selected name so re-saving over an
	# existing slot is a one-click thing.
	if idx >= 0 and idx < _saves.size():
		_save_input.text = String(_saves[idx].name)
