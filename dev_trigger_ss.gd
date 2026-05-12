extends Node

# Dev demo: open editor, switch to Level → Triggers, place a trigger
# volume + a demo prop, add a named event targeting the prop, and snap
# the viewport. Smoke-tests the new trigger pipeline end-to-end.

const TRIGGER_BOX_SCRIPT := preload("res://editor_trigger_box.gd")
const OBJECT_BOX_SCRIPT := preload("res://editor_object_box.gd")

func _ready() -> void:
	var editor_packed: PackedScene = load("res://editor.tscn")
	var editor: Node = editor_packed.instantiate()
	add_child(editor)
	await get_tree().process_frame
	await get_tree().process_frame

	var top_bar: Node = editor.get_node_or_null("UI/TopBar")
	var sub_bar: Node = editor.get_node_or_null("UI/SubBar")
	if top_bar and top_bar.has_method("select_category"):
		top_bar.select_category("level")
	if sub_bar and sub_bar.has_method("show_category"):
		sub_bar.show_category("level")
	if sub_bar and sub_bar.has_signal("tool_picked"):
		sub_bar.tool_picked.emit("l_triggers")
	await get_tree().process_frame
	await get_tree().process_frame

	# Place a demo object_box that the trigger will eventually destroy.
	var box := Node3D.new()
	box.set_script(OBJECT_BOX_SCRIPT)
	box.name = "DemoObject"
	editor.add_child(box)
	box.global_position = Vector3(4, 1, 0)
	if box.has_method("set_aabb_size"):
		box.set_aabb_size(Vector3(2, 2, 2))
	editor._placed_props.append(box)

	# Place a trigger box at the origin.
	var tb := Node3D.new()
	tb.set_script(TRIGGER_BOX_SCRIPT)
	tb.name = "DemoTrigger"
	editor.add_child(tb)
	tb.global_position = Vector3(-2, 0, 0)
	editor._placed_props.append(tb)
	await get_tree().process_frame

	# Add a named event targeting the demo prop.
	if editor._events_panel != null:
		editor._events_panel._on_add_event()
		var ev: Dictionary = editor._events_panel.events[0]
		ev["name"] = "BlowUpDemo"
		ev["targets"] = [box.prop_id]
		editor._events_panel.set_events(editor._events_panel.events)
		# Wire trigger to fire that event when player walks in.
		tb.fire_event_ids = [String(ev["id"])]
		tb.conditions = [{"type": "player_in", "filter_id": "", "min_count": 1, "negate": false}]

	# Select the trigger so the trigger panel binds.
	editor._select_prop(tb)
	await get_tree().process_frame
	await get_tree().process_frame

	var cam: Camera3D = editor.get_node_or_null("EditorCamera")
	if cam:
		cam.global_position = Vector3(6, 5, 8)
		cam.look_at(Vector3(0, 1.5, 0), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var img: Image = get_viewport().get_texture().get_image()
	if img:
		var out: String = "user://trigger_demo.png"
		img.save_png(out)
		print("SAVED: ", ProjectSettings.globalize_path(out))
	get_tree().quit()
