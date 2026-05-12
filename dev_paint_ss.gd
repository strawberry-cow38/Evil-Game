extends Node

# Dev-only: opens editor.tscn, picks Environment → Paint, sculpts smooth
# hills, then paints four material patches (dirt, grass, stone, sand)
# across them to show the blending shader in action.

const PAINT_TOOL := "e_paint"

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
		sub_bar.tool_picked.emit(PAINT_TOOL)

	await get_tree().process_frame

	var terrain: Node3D = editor.get_node_or_null("Terrain")
	if terrain:
		_sculpt_smooth_hills(terrain)

	await get_tree().process_frame

	if terrain:
		# Paint four overlapping patches so the blends between them read.
		# mat_id: 0=dirt, 1=grass (default), 2=stone, 3=sand
		# Two overlapping circles — dirt on the left, sand on the right.
		# They share a ~10m wide overlap strip down the middle where the
		# shader blends the two colors together.
		var patches: Array = [
			{"center": Vector3(-12, 0, 0), "radius": 26.0, "mat": 0, "shape": "circle"},
			{"center": Vector3( 12, 0, 0), "radius": 26.0, "mat": 3, "shape": "circle"},
		]
		for p in patches:
			# Burn the paint in over many sub-steps so weights actually
			# pin to ~1 (paint_brush rate is clamped to delta).
			for _i in range(60):
				terrain.paint_brush(p["center"], float(p["radius"]), 12.0, 0.05, int(p["mat"]), String(p["shape"]))
		terrain._rebuild_mesh_now()

	await get_tree().process_frame
	await get_tree().process_frame

	var cam: Camera3D = editor.get_node_or_null("EditorCamera")
	if cam:
		cam.global_position = Vector3(0, 35, 55)
		cam.look_at(Vector3(0, 0, 0), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var img: Image = get_viewport().get_texture().get_image()
	if img:
		var out: String = "user://paint_tool_demo.png"
		img.save_png(out)
		print("SAVED: ", ProjectSettings.globalize_path(out))
	get_tree().quit()

func _sculpt_smooth_hills(terrain: Node3D) -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = 4242
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.45
	var w: int = terrain.GRID_W
	var h: int = terrain.GRID_H
	for y in range(h):
		for x in range(w):
			var n: float = noise.get_noise_2d(float(x), float(y))
			terrain.heights[x + y * w] = n * 6.0
	if terrain.has_method("_rebuild_mesh_now"):
		terrain._rebuild_mesh_now()
