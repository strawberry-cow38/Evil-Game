extends Node

# Autoload that serializes/deserializes the editor's MapState to JSON
# files in user://maps/. JSON can't carry Godot's bespoke types directly
# (Vector3, Transform3D, Color, PackedFloat32Array), so each get a small
# round-trip helper. File schema is intentionally flat — one file per
# saved map, no sidecars. Schema version bumps when fields change so old
# saves can be rejected (or migrated) instead of silently misloading.

const SAVE_DIR := "user://maps"
const SCHEMA_VERSION := 6

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))

func save_map(map_name: String) -> bool:
	if map_name == "":
		return false
	var path: String = _path_for(map_name)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	var data: Dictionary = _snapshot_state()
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("MapIO: failed to open %s for write" % path)
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return true

func load_map(map_name: String) -> bool:
	if map_name == "":
		return false
	var path: String = _path_for(map_name)
	if not FileAccess.file_exists(path):
		return false
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var raw: String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw)
	if not parsed is Dictionary:
		push_error("MapIO: %s is not a JSON object" % path)
		return false
	var data: Dictionary = parsed
	if int(data.get("schema", 0)) != SCHEMA_VERSION:
		push_error("MapIO: schema mismatch for %s (got %d, expected %d)" % [map_name, int(data.get("schema", 0)), SCHEMA_VERSION])
		return false
	_apply_state(data)
	return true

func delete_save(map_name: String) -> bool:
	var path: String = _path_for(map_name)
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK

func list_saves() -> Array:
	# Returns [{name, mtime}] sorted newest-first so the picker UI can
	# show the most recent map at the top without extra sorting work.
	var out: Array = []
	var dir: DirAccess = DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			var nm: String = fname.get_basename()
			var abs: String = ProjectSettings.globalize_path(SAVE_DIR.path_join(fname))
			var mtime: int = FileAccess.get_modified_time(abs)
			out.append({"name": nm, "mtime": mtime})
		fname = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a, b): return int(a.mtime) > int(b.mtime))
	return out

func _path_for(map_name: String) -> String:
	# Strip any path separators / dotfiles a user might type into the save
	# field so we can never escape SAVE_DIR.
	var safe: String = map_name.replace("/", "_").replace("\\", "_").strip_edges()
	if safe.begins_with("."):
		safe = safe.substr(1)
	return SAVE_DIR.path_join("%s.json" % safe)

# --- State <-> JSON --------------------------------------------------------

func _snapshot_state() -> Dictionary:
	var heights_arr: Array = []
	heights_arr.resize(MapState.heights.size())
	for i in range(MapState.heights.size()):
		heights_arr[i] = MapState.heights[i]
	# Paint serialised as flat float quads (r,g,b,a per vertex) so the JSON
	# stays plain numbers; Godot's PackedColorArray can't survive JSON.stringify
	# without a per-element helper anyway.
	var paint_arr: Array = []
	paint_arr.resize(MapState.terrain_paint.size() * 4)
	for i in range(MapState.terrain_paint.size()):
		var c: Color = MapState.terrain_paint[i]
		paint_arr[i * 4    ] = c.r
		paint_arr[i * 4 + 1] = c.g
		paint_arr[i * 4 + 2] = c.b
		paint_arr[i * 4 + 3] = c.a
	var spawns: Array = []
	for sp in MapState.player_spawns:
		spawns.append(_v3_to_dict(sp))
	var props: Array = []
	for entry in MapState.placed_props:
		var dup: Dictionary = entry.duplicate()
		if dup.has("xform"):
			dup["xform"] = _xform_to_dict(dup["xform"])
		props.append(dup)
	var tables: Array = []
	for t in MapState.item_tables:
		var td: Dictionary = t.duplicate()
		if td.has("color"):
			td["color"] = _color_to_dict(td["color"])
		tables.append(td)
	var spawn_pts: Array = []
	for sp in MapState.item_spawn_points:
		var spd: Dictionary = sp.duplicate()
		if spd.has("pos"):
			spd["pos"] = _v3_to_dict(spd["pos"])
		spawn_pts.append(spd)
	var lighting: Dictionary = {}
	for k in MapState.lighting.keys():
		var v = MapState.lighting[k]
		if v is Color:
			lighting[k] = _color_to_dict(v)
		else:
			lighting[k] = v
	var atables: Array = []
	for t in MapState.actor_tables:
		var atd: Dictionary = t.duplicate(true)
		if atd.has("color"):
			atd["color"] = _color_to_dict(atd["color"])
		atables.append(atd)
	var aspawn_pts: Array = []
	for sp in MapState.actor_spawn_points:
		var aspd: Dictionary = sp.duplicate()
		if aspd.has("pos"):
			aspd["pos"] = _v3_to_dict(aspd["pos"])
		aspawn_pts.append(aspd)
	var roads_out: Array = []
	for r in MapState.roads:
		var rd: Dictionary = {"id": String(r.get("id", "")), "surface": String(r.get("surface", "asphalt")), "nodes": [], "decals": []}
		for n in r.get("nodes", []):
			rd["nodes"].append({
				"pos": _v3_to_dict(n.get("pos", Vector3.ZERO)),
				"in_tangent": _v3_to_dict(n.get("in_tangent", Vector3.ZERO)),
				"out_tangent": _v3_to_dict(n.get("out_tangent", Vector3.ZERO)),
				"ignore_terrain": bool(n.get("ignore_terrain", false)),
				"width": float(n.get("width", 6.0)),
			})
		for d in r.get("decals", []):
			rd["decals"].append({
				"offset": float(d.get("offset", 0.5)),
				"width": float(d.get("width", 0.15)),
				"color": _color_to_dict(d.get("color", Color(1, 1, 1, 1))),
				"dash_length": float(d.get("dash_length", 0.0)),
				"gap_length": float(d.get("gap_length", 0.0)),
			})
		roads_out.append(rd)
	var triggers_out: Array = []
	for tr in MapState.placed_triggers:
		var tdup: Dictionary = tr.duplicate(true)
		if tdup.has("xform"):
			tdup["xform"] = _xform_to_dict(tdup["xform"])
		triggers_out.append(tdup)
	var events_out: Array = []
	for ev in MapState.map_events:
		events_out.append(ev.duplicate(true))
	# Foliage — Vector3 needs the dict round-trip; scale + rot_y are plain floats.
	# Preset id selects which blade variant (height + tint) the foliage node
	# replays into; missing preset on load falls back to short_green.
	var foliage_out: Array = []
	for inst in MapState.foliage_instances:
		foliage_out.append({
			"preset": String(inst.get("preset", "short_green")),
			"pos": _v3_to_dict(inst.get("pos", Vector3.ZERO)),
			"scale": float(inst.get("scale", 1.0)),
			"rot_y": float(inst.get("rot_y", 0.0)),
		})
	var holes_arr: Array = []
	holes_arr.resize(MapState.terrain_holes.size())
	for i in range(MapState.terrain_holes.size()):
		holes_arr[i] = int(MapState.terrain_holes[i])
	return {
		"schema": SCHEMA_VERSION,
		"heights": heights_arr,
		"terrain_paint": paint_arr,
		"terrain_holes": holes_arr,
		"grid_w": MapState.grid_w,
		"grid_h": MapState.grid_h,
		"player_spawns": spawns,
		"placed_props": props,
		"item_tables": tables,
		"item_spawn_points": spawn_pts,
		"actor_tables": atables,
		"actor_spawn_points": aspawn_pts,
		"lighting": lighting,
		"roads": roads_out,
		"placed_triggers": triggers_out,
		"map_events": events_out,
		"foliage_instances": foliage_out,
		"foliage_wind": MapState.foliage_wind.duplicate(),
	}

func _apply_state(data: Dictionary) -> void:
	MapState.clear()
	var heights_arr: Array = data.get("heights", [])
	var packed: PackedFloat32Array = PackedFloat32Array()
	packed.resize(heights_arr.size())
	for i in range(heights_arr.size()):
		packed[i] = float(heights_arr[i])
	MapState.heights = packed
	var paint_arr: Array = data.get("terrain_paint", [])
	var paint_packed: PackedColorArray = PackedColorArray()
	var paint_count: int = paint_arr.size() / 4
	paint_packed.resize(paint_count)
	for i in range(paint_count):
		paint_packed[i] = Color(
			float(paint_arr[i * 4    ]),
			float(paint_arr[i * 4 + 1]),
			float(paint_arr[i * 4 + 2]),
			float(paint_arr[i * 4 + 3]),
		)
	MapState.terrain_paint = paint_packed
	var holes_arr: Array = data.get("terrain_holes", [])
	var holes_packed: PackedByteArray = PackedByteArray()
	holes_packed.resize(holes_arr.size())
	for i in range(holes_arr.size()):
		holes_packed[i] = int(holes_arr[i]) & 0x01
	MapState.terrain_holes = holes_packed
	MapState.grid_w = int(data.get("grid_w", 0))
	MapState.grid_h = int(data.get("grid_h", 0))
	for sp in data.get("player_spawns", []):
		MapState.player_spawns.append(_dict_to_v3(sp))
	for entry in data.get("placed_props", []):
		var ed: Dictionary = entry.duplicate()
		if ed.has("xform"):
			ed["xform"] = _dict_to_xform(ed["xform"])
		MapState.placed_props.append(ed)
	for t in data.get("item_tables", []):
		var td: Dictionary = t.duplicate()
		if td.has("color"):
			td["color"] = _dict_to_color(td["color"])
		MapState.item_tables.append(td)
	for sp in data.get("item_spawn_points", []):
		var spd: Dictionary = sp.duplicate()
		if spd.has("pos"):
			spd["pos"] = _dict_to_v3(spd["pos"])
		MapState.item_spawn_points.append(spd)
	for t in data.get("actor_tables", []):
		var atd: Dictionary = t.duplicate(true)
		if atd.has("color"):
			atd["color"] = _dict_to_color(atd["color"])
		MapState.actor_tables.append(atd)
	for sp in data.get("actor_spawn_points", []):
		var aspd: Dictionary = sp.duplicate()
		if aspd.has("pos"):
			aspd["pos"] = _dict_to_v3(aspd["pos"])
		MapState.actor_spawn_points.append(aspd)
	var lighting: Dictionary = data.get("lighting", {})
	var out_lighting: Dictionary = {}
	for k in lighting.keys():
		var v = lighting[k]
		if v is Dictionary and v.has("r") and v.has("g") and v.has("b"):
			out_lighting[k] = _dict_to_color(v)
		else:
			out_lighting[k] = v
	MapState.lighting = out_lighting
	for r in data.get("roads", []):
		var rd: Dictionary = {"id": String(r.get("id", "")), "surface": String(r.get("surface", "asphalt")), "nodes": [], "decals": []}
		for n in r.get("nodes", []):
			rd["nodes"].append({
				"pos": _dict_to_v3(n.get("pos", {})),
				"in_tangent": _dict_to_v3(n.get("in_tangent", {})),
				"out_tangent": _dict_to_v3(n.get("out_tangent", {})),
				"ignore_terrain": bool(n.get("ignore_terrain", false)),
				"width": float(n.get("width", 6.0)),
			})
		for d in r.get("decals", []):
			var col_raw = d.get("color", {})
			var col: Color = _dict_to_color(col_raw) if col_raw is Dictionary else Color(1, 1, 1, 1)
			rd["decals"].append({
				"offset": float(d.get("offset", 0.5)),
				"width": float(d.get("width", 0.15)),
				"color": col,
				"dash_length": float(d.get("dash_length", 0.0)),
				"gap_length": float(d.get("gap_length", 0.0)),
			})
		MapState.roads.append(rd)
	for tr in data.get("placed_triggers", []):
		var tdup: Dictionary = tr.duplicate(true)
		if tdup.has("xform"):
			tdup["xform"] = _dict_to_xform(tdup["xform"])
		MapState.placed_triggers.append(tdup)
	for ev in data.get("map_events", []):
		MapState.map_events.append(ev.duplicate(true))
	for inst in data.get("foliage_instances", []):
		MapState.foliage_instances.append({
			"preset": String(inst.get("preset", "short_green")),
			"pos": _dict_to_v3(inst.get("pos", {})),
			"scale": float(inst.get("scale", 1.0)),
			"rot_y": float(inst.get("rot_y", 0.0)),
		})
	var wind: Dictionary = data.get("foliage_wind", {})
	if wind is Dictionary:
		MapState.foliage_wind = wind.duplicate()

# --- Type helpers ----------------------------------------------------------

func _v3_to_dict(v: Vector3) -> Dictionary:
	return {"x": v.x, "y": v.y, "z": v.z}

func _dict_to_v3(d: Dictionary) -> Vector3:
	return Vector3(float(d.get("x", 0.0)), float(d.get("y", 0.0)), float(d.get("z", 0.0)))

func _color_to_dict(c: Color) -> Dictionary:
	return {"r": c.r, "g": c.g, "b": c.b, "a": c.a}

func _dict_to_color(d: Dictionary) -> Color:
	return Color(float(d.get("r", 1.0)), float(d.get("g", 1.0)), float(d.get("b", 1.0)), float(d.get("a", 1.0)))

func _xform_to_dict(t: Transform3D) -> Dictionary:
	return {
		"basis": [
			t.basis.x.x, t.basis.x.y, t.basis.x.z,
			t.basis.y.x, t.basis.y.y, t.basis.y.z,
			t.basis.z.x, t.basis.z.y, t.basis.z.z,
		],
		"origin": _v3_to_dict(t.origin),
	}

func _dict_to_xform(d: Dictionary) -> Transform3D:
	var b: Array = d.get("basis", [])
	if b.size() != 9:
		return Transform3D.IDENTITY
	var basis := Basis(
		Vector3(float(b[0]), float(b[1]), float(b[2])),
		Vector3(float(b[3]), float(b[4]), float(b[5])),
		Vector3(float(b[6]), float(b[7]), float(b[8])),
	)
	var origin: Vector3 = _dict_to_v3(d.get("origin", {}))
	return Transform3D(basis, origin)
