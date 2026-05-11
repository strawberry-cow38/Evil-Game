extends Node

# Dev-only: opens editor.tscn, picks Environment → Roads, generates
# smooth heightmap noise into the terrain, then drops long curving roads
# of different surfaces across the hills.

const ROADS_TOOL := "e_roads"

func _ready() -> void:
	var editor_packed: PackedScene = load("res://editor.tscn")
	var editor: Node = editor_packed.instantiate()
	add_child(editor)

	await get_tree().process_frame
	await get_tree().process_frame

	var top_bar: Node = editor.get_node_or_null("UI/TopBar")
	var sub_bar: Node = editor.get_node_or_null("UI/SubBar")
	if top_bar and top_bar.has_method("select_category"):
		top_bar.select_category("environment")
	if sub_bar and sub_bar.has_method("show_category"):
		sub_bar.show_category("environment")
	if sub_bar and sub_bar.has_signal("tool_picked"):
		sub_bar.tool_picked.emit(ROADS_TOOL)

	await get_tree().process_frame

	var terrain: Node3D = editor.get_node_or_null("Terrain")
	if terrain:
		_sculpt_smooth_hills(terrain)

	await get_tree().process_frame

	var roads: Node = null
	for c in editor.get_children():
		if c.get_script() != null and String(c.get_script().resource_path).ends_with("editor_roads.gd"):
			roads = c
			break

	if roads:
		# Three long roads winding across the hills. Each one is six nodes
		# spanning ~200m along X with z varying to make the curve obvious.
		var lanes := [
			{"surface": "asphalt",       "z_offset": 30.0, "width": 8.0,  "amp": 18.0},
			{"surface": "dirt_road",     "z_offset":  0.0, "width": 5.5,  "amp": 14.0},
			{"surface": "dirt_footpath", "z_offset":-30.0, "width": 2.5,  "amp": 22.0},
		]
		var xs: Array = [-100.0, -60.0, -20.0, 20.0, 60.0, 100.0]
		for lane in lanes:
			roads.deselect()
			for x in xs:
				var zwave: float = sin(x * 0.04) * float(lane["amp"]) + float(lane["z_offset"])
				roads.on_click(Vector3(float(x), 0, zwave), Vector3i(-1, -1, -1))
			var state: Array = roads.get_state().duplicate(true)
			var road_idx: int = state.size() - 1
			var nodes: Array = state[road_idx]["nodes"]
			# Auto-tangent each interior node along its neighbour chord so the
			# spline reads as a continuous swoop instead of straight segments.
			for i in range(nodes.size()):
				var w: float = float(lane["width"])
				nodes[i]["width"] = w
				var prev_pos: Vector3 = nodes[max(i - 1, 0)].get("pos", Vector3.ZERO)
				var next_pos: Vector3 = nodes[min(i + 1, nodes.size() - 1)].get("pos", Vector3.ZERO)
				var chord: Vector3 = (next_pos - prev_pos)
				chord.y = 0.0
				var tan: Vector3 = chord * 0.33
				nodes[i]["in_tangent"] = -tan
				nodes[i]["out_tangent"] = tan
			roads.set_state(state)
			# Re-select first node so set_selected_surface targets this road.
			roads.on_click(Vector3.ZERO, Vector3i(road_idx, 0, 0))
			roads.set_selected_surface(String(lane["surface"]))
		roads.deselect()

	await get_tree().process_frame
	await get_tree().process_frame

	var cam: Camera3D = editor.get_node_or_null("EditorCamera")
	if cam:
		cam.global_position = Vector3(0, 90, 130)
		cam.look_at(Vector3(0, 0, 0), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame

	var img: Image = get_viewport().get_texture().get_image()
	if img:
		var out: String = "user://road_tool_demo.png"
		img.save_png(out)
		print("SAVED: ", ProjectSettings.globalize_path(out))
	get_tree().quit()

func _sculpt_smooth_hills(terrain: Node3D) -> void:
	# Write low-frequency noise directly into the heights array, then ask
	# the terrain node to rebuild its mesh. Smooth-everywhere — no sharp
	# edges, no plateaus.
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = 1337
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.45
	var w: int = terrain.GRID_W
	var h: int = terrain.GRID_H
	for y in range(h):
		for x in range(w):
			var n: float = noise.get_noise_2d(float(x), float(y))
			terrain.heights[x + y * w] = n * 8.0
	if terrain.has_method("_rebuild_mesh_now"):
		terrain._rebuild_mesh_now()
