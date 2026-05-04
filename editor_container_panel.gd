extends PanelContainer

# Loot-table picker shown when a container object box (crate) is selected
# in the editor. Reads the live tables list from editor_item_tables_panel
# and emits table_chosen(id) when the user picks one. The actual write to
# the box's loot_table_id field is done by editor.gd in the handler.

signal table_chosen(table_id: String)

var _title: Label
var _info: Label
var _option: OptionButton
# Cache of the current option-index → table-id mapping so the changed
# signal can resolve back to a stable id (option indices reshuffle every
# rebuild).
var _index_to_id: Array[String] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(280, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	_title = Label.new()
	_title.text = "Container"
	_title.add_theme_font_size_override("font_size", 16)
	v.add_child(_title)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 12)
	_info.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	v.add_child(_info)
	var lbl := Label.new()
	lbl.text = "Loot table"
	v.add_child(lbl)
	_option = OptionButton.new()
	_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_option.item_selected.connect(_on_option_selected)
	v.add_child(_option)

# Populate the dropdown with `(none)` + every defined table. Selection is
# driven from the currently-bound box's loot_table_id.
func bind(label: String, current_table_id: String, tables: Array, info_text: String) -> void:
	_title.text = label
	_info.text = info_text
	_option.clear()
	_index_to_id.clear()
	_option.add_item("(none)")
	_index_to_id.append("")
	var sel_idx: int = 0
	for i in range(tables.size()):
		var t: Dictionary = tables[i]
		var id: String = String(t.get("id", ""))
		var name: String = String(t.get("name", id))
		_option.add_item(name)
		_index_to_id.append(id)
		if id == current_table_id:
			sel_idx = _index_to_id.size() - 1
	_option.select(sel_idx)

func _on_option_selected(idx: int) -> void:
	if idx < 0 or idx >= _index_to_id.size():
		return
	table_chosen.emit(_index_to_id[idx])
