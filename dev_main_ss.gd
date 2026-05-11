extends Node

# Seeds MapState with a hilly terrain + three winding roads, then loads
# main.tscn so we can screenshot the play-mode road renderer.

func _ready() -> void:
	_seed_map_state()
	await get_tree().process_frame
	var main_packed: PackedScene = load("res://main.tscn")
	var main: Node = main_packed.instantiate()
	add_child(main)
	# Wait for bootstrap + first physics frames so terrain mesh + roads
	# settle before snapping.
	for i in range(30):
		await get_tree().process_frame
	var cam := _find_camera(main)
	if cam:
		cam.global_position = Vector3(-10, 6, 48)
		cam.look_at(Vector3(10, 2, 30), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	if img:
		var out: String = "user://road_main_demo.png"
		img.save_png(out)
		print("SAVED: ", ProjectSettings.globalize_path(out))
	get_tree().quit()

func _seed_map_state() -> void:
	MapState.clear()
	# Reuse the terrain grid constants by loading editor_terrain script.
	var et := preload("res://editor_terrain.gd")
	var w: int = et.GRID_W
	var h: int = et.GRID_H
	var heights := PackedFloat32Array()
	heights.resize(w * h)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = 1337
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	for y in range(h):
		for x in range(w):
			heights[x + y * w] = noise.get_noise_2d(float(x), float(y)) * 8.0
	MapState.heights = heights
	MapState.grid_w = w
	MapState.grid_h = h
	# Player spawn so bootstrap doesn't bail on missing spawns.
	MapState.player_spawns.append(Vector3(0, 0, 60))
	# Three winding roads.
	var lanes := [
		{"surface": "asphalt",       "z_offset": 30.0, "width": 8.0,  "amp": 18.0},
		{"surface": "dirt_road",     "z_offset":  0.0, "width": 5.5,  "amp": 14.0},
		{"surface": "dirt_footpath", "z_offset":-30.0, "width": 2.5,  "amp": 22.0},
	]
	var xs: Array = [-100.0, -60.0, -20.0, 20.0, 60.0, 100.0]
	for lane in lanes:
		var nodes: Array = []
		for x in xs:
			var zwave: float = sin(x * 0.04) * float(lane["amp"]) + float(lane["z_offset"])
			nodes.append({"pos": Vector3(float(x), 0.0, zwave), "in_tangent": Vector3.ZERO, "out_tangent": Vector3.ZERO, "ignore_terrain": false, "width": float(lane["width"])})
		for i in range(nodes.size()):
			var prev_pos: Vector3 = nodes[max(i - 1, 0)]["pos"]
			var next_pos: Vector3 = nodes[min(i + 1, nodes.size() - 1)]["pos"]
			var chord: Vector3 = (next_pos - prev_pos)
			chord.y = 0.0
			var tan: Vector3 = chord * 0.33
			nodes[i]["in_tangent"] = -tan
			nodes[i]["out_tangent"] = tan
		var decals: Array = []
		var sid: String = String(lane["surface"])
		if sid == "asphalt":
			# Highway-style: solid edge lines + dashed centre.
			decals.append({"offset": 0.08, "width": 0.15, "color": Color(1, 1, 1, 1), "dash_length": 0.0, "gap_length": 0.0})
			decals.append({"offset": 0.92, "width": 0.15, "color": Color(1, 1, 1, 1), "dash_length": 0.0, "gap_length": 0.0})
			decals.append({"offset": 0.5,  "width": 0.18, "color": Color(0.95, 0.78, 0.15, 1.0), "dash_length": 3.0, "gap_length": 4.0})
		elif sid == "dirt_road":
			# Single off-centre tyre track in faded tan.
			decals.append({"offset": 0.5, "width": 0.6, "color": Color(0.25, 0.18, 0.10, 0.7), "dash_length": 0.0, "gap_length": 0.0})
		elif sid == "dirt_footpath":
			# Dashed cream centreline.
			decals.append({"offset": 0.5, "width": 0.10, "color": Color(0.85, 0.78, 0.55, 1.0), "dash_length": 0.6, "gap_length": 1.2})
		MapState.roads.append({"id": "dev_%s" % lane["surface"], "surface": String(lane["surface"]), "decals": decals, "nodes": nodes})

func _find_camera(root: Node) -> Camera3D:
	if root is Camera3D:
		return root
	for c in root.get_children():
		var found := _find_camera(c)
		if found != null:
			return found
	return null
