extends Node3D

# Attached to main.tscn root. If the player just came from the editor
# (MapState.has_map() is true), swap the hardcoded flat Ground for an
# editor_terrain instance carrying the authored heights. Otherwise
# leave the legacy ground intact so launching straight into Play from
# the menu still works.

const EDITOR_TERRAIN := preload("res://editor_terrain.gd")
const EFFECT_CATALOG := preload("res://editor_effect_catalog.gd")
const OBJECT_CATALOG := preload("res://editor_objects_catalog.gd")
const PICKUP := preload("res://pickup.gd")
const VEHICLE := preload("res://vehicle.gd")
const NOTHING_ITEM_ID := "nothing"

# Fixed vehicle spawn — sits a few meters off the player spawn so it's findable.
const VEHICLE_SPAWN_OFFSET := Vector3(6.0, 0.0, 0.0)

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
	# Item-spawn rolls. For each placed cube, look up its table, roll the
	# weighted entries (including the implicit "nothing" entry), and drop
	# a pickup if the result isn't nothing.
	if not MapState.item_spawn_points.is_empty():
		var spawn_root := Node3D.new()
		spawn_root.name = "ItemSpawns"
		add_child(spawn_root)
		var tables_by_id: Dictionary = {}
		for t in MapState.item_tables:
			tables_by_id[String(t.get("id", ""))] = t
		for sp in MapState.item_spawn_points:
			var tid: String = String(sp.get("table_id", ""))
			var pos: Vector3 = sp.get("pos", Vector3.ZERO)
			var result: Dictionary = _roll_table(tables_by_id.get(tid, {}))
			var rolled: String = String(result.get("id", ""))
			if rolled == "" or rolled == NOTHING_ITEM_ID:
				continue
			var pickup := Area3D.new()
			pickup.set_script(PICKUP)
			pickup.item_id = rolled
			pickup.count = int(result.get("count", 1))
			pickup.position = pos + Vector3(0, 0.3, 0)
			spawn_root.add_child(pickup)

	# Always-spawn vehicle. Sit it slightly off the player spawn at terrain
	# height + clearance so it lands on the ground rather than clipping in.
	var v := VehicleBody3D.new()
	v.set_script(VEHICLE)
	v.name = "Vehicle"
	var spawn_xz: Vector3 = Vector3.ZERO
	var player_node := get_node_or_null("Player")
	if player_node != null and player_node is Node3D:
		spawn_xz = (player_node as Node3D).global_position
	spawn_xz += VEHICLE_SPAWN_OFFSET
	var ground_y: float = spawn_xz.y
	if terrain_node != null and terrain_node.has_method("sample_height"):
		ground_y = terrain_node.sample_height(spawn_xz)
	v.position = Vector3(spawn_xz.x, ground_y + 1.0, spawn_xz.z)
	add_child(v)

func _roll_table(table: Dictionary) -> Dictionary:
	if table.is_empty():
		return {"id": "", "count": 1}
	var entries: Array = table.get("entries", [])
	var has_nothing: bool = false
	var total: float = 0.0
	for e in entries:
		var w: float = float(e.get("weight", 1.0))
		if w < 0.0:
			w = 0.0
		total += w
		if String(e.get("id", "")) == NOTHING_ITEM_ID:
			has_nothing = true
	# Tables without an explicit nothing entry still get a baseline 1.0
	# nothing-weight so a table with one item at weight 0 doesn't divide
	# by zero or always spawn.
	if not has_nothing:
		total += 1.0
	if total <= 0.0:
		return {"id": "", "count": 1}
	var roll: float = randf() * total
	var acc: float = 0.0
	for e in entries:
		var w2: float = float(e.get("weight", 1.0))
		if w2 < 0.0:
			w2 = 0.0
		acc += w2
		if roll <= acc:
			var id: String = String(e.get("id", ""))
			var min_c: int = int(e.get("min_count", 1))
			var max_c: int = int(e.get("max_count", 1))
			if min_c < 1:
				min_c = 1
			if max_c < min_c:
				max_c = min_c
			var count: int = randi_range(min_c, max_c)
			return {"id": id, "count": count}
	return {"id": NOTHING_ITEM_ID, "count": 1}

func _input(event: InputEvent) -> void:
	# F9 toggles back to the editor with the current map intact.
	# Action OR raw-key, but not both — change_scene_to_file frees self.
	var is_f9: bool = event.is_action_pressed("editor_play") \
		or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9)
	if is_f9:
		get_tree().change_scene_to_file("res://editor.tscn")
