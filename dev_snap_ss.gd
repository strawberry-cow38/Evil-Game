extends Node

# Dev-only: opens editor.tscn, places an object box, switches the gizmo
# into Scale mode so the new uniform-scale center ball is visible, then
# screencaps.

const OBJECT_BOX_SCRIPT := preload("res://editor_object_box.gd")

func _ready() -> void:
	var editor_packed: PackedScene = load("res://editor.tscn")
	var editor: Node = editor_packed.instantiate()
	add_child(editor)

	await get_tree().process_frame
	await get_tree().process_frame

	# Drop into Objects so the snap widget shows.
	var top_bar: Node = editor.get_node_or_null("UI/TopBar")
	var sub_bar: Node = editor.get_node_or_null("UI/SubBar")
	if top_bar and top_bar.has_method("select_category"):
		top_bar.select_category("objects")
	if sub_bar and sub_bar.has_method("show_category"):
		sub_bar.show_category("objects")
	if sub_bar and sub_bar.has_signal("tool_picked"):
		sub_bar.tool_picked.emit("o_objects")
	await get_tree().process_frame

	# Spawn a plain object_box manually so the gizmo has a target without
	# us having to drive a click through the picker UI.
	var box := Node3D.new()
	box.set_script(OBJECT_BOX_SCRIPT)
	box.name = "DemoObject"
	editor.add_child(box)
	box.global_position = Vector3(0, 1.0, 0)
	if box.has_method("set_aabb_size"):
		box.set_aabb_size(Vector3(2.0, 2.0, 2.0))
	if box.has_method("set_selected"):
		box.set_selected(true)
	# Wire it into the editor's selection machinery directly.
	editor._selected_prop = box
	editor._placed_props.append(box)
	var giz: Node = editor.get_node_or_null("Gizmo")
	if giz == null:
		giz = editor._gizmo
	if giz != null:
		giz.set_target(box)
		giz.set_mode(giz.MODE_SCALE)

	await get_tree().process_frame
	await get_tree().process_frame

	var cam: Camera3D = editor.get_node_or_null("EditorCamera")
	if cam:
		cam.global_position = Vector3(4.5, 3.5, 5.5)
		cam.look_at(Vector3(0, 1, 0), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var img: Image = get_viewport().get_texture().get_image()
	if img:
		var out: String = "user://snap_demo.png"
		img.save_png(out)
		print("SAVED: ", ProjectSettings.globalize_path(out))
	get_tree().quit()
