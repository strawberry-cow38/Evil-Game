extends Node3D

# Attached to main.tscn root. If the player just came from the editor
# (MapState.has_map() is true), swap the hardcoded flat Ground for an
# editor_terrain instance carrying the authored heights. Otherwise
# leave the legacy ground intact so launching straight into Play from
# the menu still works.

const EDITOR_TERRAIN := preload("res://editor_terrain.gd")
const EFFECT_CATALOG := preload("res://editor_effect_catalog.gd")
const OBJECT_CATALOG := preload("res://editor_objects_catalog.gd")

func _ready() -> void:
	var terrain_node: Node = null
	if MapState.has_map():
		var ground := get_node_or_null("Ground")
		if ground != null:
			ground.queue_free()
		var terrain := Node3D.new()
		terrain.set_script(EDITOR_TERRAIN)
		terrain.name = "EditorTerrain"
		add_child(terrain)
		# editor_terrain._ready already created the mesh from a zeroed
		# array; overwrite + rebuild with the real heights.
		terrain.heights = MapState.heights.duplicate()
		terrain.rebuild()
		terrain_node = terrain
	# Player spawn override: pick a random authored marker and drop the
	# Player there. Sit them slightly above the terrain so they don't
	# clip through the new mesh.
	if not MapState.player_spawns.is_empty():
		var player := get_node_or_null("Player")
		if player != null:
			var sp: Vector3 = MapState.random_player_spawn()
			var ground_h: float = sp.y
			if terrain_node != null and terrain_node.has_method("sample_height"):
				ground_h = terrain_node.sample_height(sp)
			player.global_position = Vector3(sp.x, ground_h + 1.2, sp.z)
	# Rebuild placed effects + objects from the catalog. Wireframe boxes
	# stay in the editor — play mode only spawns the visual content.
	var props_root: Node3D = null
	if not MapState.placed_props.is_empty():
		props_root = Node3D.new()
		props_root.name = "PlacedProps"
		add_child(props_root)
		for entry in MapState.placed_props:
			var kind: String = String(entry.get("kind", ""))
			var id: String = String(entry.get("id", ""))
			var xform: Transform3D = entry.get("xform", Transform3D.IDENTITY)
			var content: Node3D = null
			if kind == "effect":
				content = EFFECT_CATALOG.build(id)
			elif kind == "object":
				content = OBJECT_CATALOG.build(id)
			if content == null:
				continue
			props_root.add_child(content)
			content.global_transform = xform

func _input(event: InputEvent) -> void:
	# F9 toggles back to the editor with the current map intact.
	# Action OR raw-key, but not both — change_scene_to_file frees self.
	var is_f9: bool = event.is_action_pressed("editor_play") \
		or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9)
	if is_f9:
		get_tree().change_scene_to_file("res://editor.tscn")
