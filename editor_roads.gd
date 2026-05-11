extends Node3D

# Road authoring module owned by the editor. A road is an ordered chain
# of nodes that the user lays down by clicking on the terrain. Each node
# also carries in/out tangent offsets (sub-handles) for a later bezier
# pass — phase 1 just stores them and draws straight grey lines between
# consecutive nodes. Phase 2 will wire the tangents into a sampled
# curve and phase 3 will extrude the asphalt strip.
#
# Selection model: clicking a node selects its road and that node. New
# clicks on empty terrain append a node to the SELECTED road. To start
# a brand new road, deselect first (right-click on empty space) and then
# click. E toggles "grab mode" on the selected node — the node follows
# the cursor until E is pressed again (or LMB clicks to commit).
#
# All visuals are children of this node, rebuilt cheaply on each edit.
# Selection/hover state lives here; the editor proxies input to us.

signal road_state_changed()

const NODE_RADIUS := 0.6
const SUB_RADIUS := 0.35
const SELECTED_COLOR := Color(1.0, 0.85, 0.2, 1.0)
const NORMAL_COLOR   := Color(0.25, 0.7, 1.0, 1.0)
const ROAD_LINE_COLOR := Color(0.9, 0.9, 0.95, 1.0)
const ROAD_RAISE := 0.15  # node visuals sit this far above the terrain

# Map-state shape (mirrored into MapState.roads on save):
#   road = { "id": String, "nodes": Array[ node_dict ] }
#   node_dict = {
#     "pos": Vector3,
#     "in_tangent":  Vector3,   # local offset, phase 2
#     "out_tangent": Vector3,   # local offset, phase 2
#     "ignore_terrain": bool,
#   }
var _roads: Array = []
var _selected_road: int = -1   # index into _roads
var _selected_node: int = -1   # index into _roads[i].nodes
var _grab_active: bool = false # node follows the cursor

var _terrain: Node3D = null

# Visual nodes — kept in sync with _roads on every edit.
var _node_visuals: Array[MeshInstance3D] = []  # parallel layout: road i node j
var _line_visuals: Array[MeshInstance3D] = []  # one per consecutive pair
var _node_mat_normal: StandardMaterial3D
var _node_mat_selected: StandardMaterial3D
var _line_mat: StandardMaterial3D
var _node_mesh: SphereMesh

func setup(terrain: Node3D) -> void:
	_terrain = terrain
	_node_mat_normal = StandardMaterial3D.new()
	_node_mat_normal.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_node_mat_normal.albedo_color = NORMAL_COLOR
	_node_mat_normal.no_depth_test = false
	_node_mat_selected = StandardMaterial3D.new()
	_node_mat_selected.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_node_mat_selected.albedo_color = SELECTED_COLOR
	_line_mat = StandardMaterial3D.new()
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.albedo_color = ROAD_LINE_COLOR
	_line_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_node_mesh = SphereMesh.new()
	_node_mesh.radius = NODE_RADIUS
	_node_mesh.height = NODE_RADIUS * 2.0

# --- State queries (used by save/load + UI) --------------------------------

func get_state() -> Array:
	# Returns a JSON-friendly Array snapshot of roads. Vector3s left as
	# Vector3 — map_io handles the dict round-trip.
	return _roads

func set_state(roads: Array) -> void:
	_roads.clear()
	for r in roads:
		var nodes_in: Array = r.get("nodes", [])
		var nodes_out: Array = []
		for n in nodes_in:
			nodes_out.append({
				"pos": n.get("pos", Vector3.ZERO),
				"in_tangent": n.get("in_tangent", Vector3.ZERO),
				"out_tangent": n.get("out_tangent", Vector3.ZERO),
				"ignore_terrain": bool(n.get("ignore_terrain", false)),
			})
		_roads.append({"id": String(r.get("id", _new_id())), "nodes": nodes_out})
	_selected_road = -1
	_selected_node = -1
	_grab_active = false
	_rebuild_visuals()

func clear_all() -> void:
	_roads.clear()
	_selected_road = -1
	_selected_node = -1
	_grab_active = false
	_rebuild_visuals()

# --- Input-driven actions (called by editor.gd) ----------------------------

# Click on terrain at world_pos. If a node was hit at the click point,
# selects that node + its road. Otherwise appends a new node to the
# selected road (or starts a new road if none selected).
func on_click(world_pos: Vector3, hit_node: Vector2i) -> void:
	if hit_node.x >= 0:
		_selected_road = hit_node.x
		_selected_node = hit_node.y
		_grab_active = false
		_refresh_colors()
		road_state_changed.emit()
		return
	# Empty-terrain click: append (or start a new road).
	var pos := _snap_to_terrain(world_pos, false)
	if _selected_road < 0:
		# Start a new road.
		_roads.append({"id": _new_id(), "nodes": []})
		_selected_road = _roads.size() - 1
	var nodes: Array = _roads[_selected_road]["nodes"]
	nodes.append({
		"pos": pos,
		"in_tangent": Vector3.ZERO,
		"out_tangent": Vector3.ZERO,
		"ignore_terrain": false,
	})
	_selected_node = nodes.size() - 1
	_rebuild_visuals()
	road_state_changed.emit()

func deselect() -> void:
	_selected_road = -1
	_selected_node = -1
	_grab_active = false
	_refresh_colors()

func toggle_grab() -> void:
	# E key. Only meaningful when a node is selected.
	if _selected_road < 0 or _selected_node < 0:
		return
	_grab_active = not _grab_active

func is_grabbing() -> bool:
	return _grab_active

func on_cursor_world(world_pos: Vector3) -> void:
	# Called each frame while a tool is active. Moves the grabbed node
	# to follow the cursor.
	if not _grab_active:
		return
	if _selected_road < 0 or _selected_node < 0:
		return
	var nodes: Array = _roads[_selected_road]["nodes"]
	var n: Dictionary = nodes[_selected_node]
	var ignore: bool = bool(n.get("ignore_terrain", false))
	n["pos"] = _snap_to_terrain(world_pos, ignore)
	nodes[_selected_node] = n
	_rebuild_visuals()

func commit_grab() -> void:
	# Bind via LMB click after E — drops the node where it currently sits.
	if _grab_active:
		_grab_active = false
		road_state_changed.emit()

func delete_selected_node() -> void:
	if _selected_road < 0 or _selected_node < 0:
		return
	var nodes: Array = _roads[_selected_road]["nodes"]
	nodes.remove_at(_selected_node)
	if nodes.is_empty():
		_roads.remove_at(_selected_road)
		_selected_road = -1
		_selected_node = -1
	else:
		_selected_node = clamp(_selected_node, 0, nodes.size() - 1)
	_grab_active = false
	_rebuild_visuals()
	road_state_changed.emit()

# Picks a (road_i, node_j) under a screen cursor by ray-vs-sphere test.
# Returns Vector2i(-1,-1) if nothing hit.
func pick_node(ray_origin: Vector3, ray_dir: Vector3) -> Vector2i:
	var best_t: float = INF
	var best := Vector2i(-1, -1)
	for ri in range(_roads.size()):
		var nodes: Array = _roads[ri]["nodes"]
		for ni in range(nodes.size()):
			var c: Vector3 = nodes[ni].get("pos", Vector3.ZERO)
			c.y += ROAD_RAISE
			var t: float = _ray_sphere(ray_origin, ray_dir, c, NODE_RADIUS * 1.4)
			if t > 0.0 and t < best_t:
				best_t = t
				best = Vector2i(ri, ni)
	return best

# --- Internals -------------------------------------------------------------

func _snap_to_terrain(world_pos: Vector3, ignore: bool) -> Vector3:
	var p := world_pos
	if not ignore and _terrain != null:
		p.y = _terrain.sample_height(p)
	return p

func _ray_sphere(ro: Vector3, rd: Vector3, c: Vector3, r: float) -> float:
	# Returns nearest positive hit t, or -1 if miss.
	var oc := ro - c
	var b: float = oc.dot(rd)
	var qc: float = oc.dot(oc) - r * r
	var disc: float = b * b - qc
	if disc < 0.0:
		return -1.0
	var sq: float = sqrt(disc)
	var t: float = -b - sq
	if t < 0.0:
		t = -b + sq
	return t

func _new_id() -> String:
	return "road_%d_%d" % [Time.get_ticks_msec(), randi() % 100000]

func _rebuild_visuals() -> void:
	for v in _node_visuals:
		v.queue_free()
	_node_visuals.clear()
	for l in _line_visuals:
		l.queue_free()
	_line_visuals.clear()
	for ri in range(_roads.size()):
		var nodes: Array = _roads[ri]["nodes"]
		for ni in range(nodes.size()):
			var n: Dictionary = nodes[ni]
			var v := MeshInstance3D.new()
			v.mesh = _node_mesh
			var is_sel: bool = (ri == _selected_road and ni == _selected_node)
			v.material_override = _node_mat_selected if is_sel else _node_mat_normal
			var p: Vector3 = n.get("pos", Vector3.ZERO)
			p.y += ROAD_RAISE
			v.position = p
			add_child(v)
			_node_visuals.append(v)
		# Lines between consecutive nodes (sampled with terrain follow for
		# clarity; phase 3 swaps these for the asphalt strip mesh).
		for ni in range(nodes.size() - 1):
			var a: Vector3 = nodes[ni].get("pos", Vector3.ZERO)
			var b: Vector3 = nodes[ni + 1].get("pos", Vector3.ZERO)
			var a_ignore: bool = bool(nodes[ni].get("ignore_terrain", false))
			var b_ignore: bool = bool(nodes[ni + 1].get("ignore_terrain", false))
			_line_visuals.append(_build_polyline(a, b, a_ignore, b_ignore))

func _build_polyline(a: Vector3, b: Vector3, a_ignore: bool, b_ignore: bool) -> MeshInstance3D:
	# Simple drape line: sample along the segment, snap each sample to
	# terrain unless the endpoint flagged ignore_terrain. Renders as a
	# 1px-style LINE_STRIP via ImmediateMesh.
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _line_mat)
	var steps := 24
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var p: Vector3 = a.lerp(b, t)
		var ignore: bool = a_ignore if t < 0.5 else b_ignore
		if not ignore and _terrain != null:
			p.y = _terrain.sample_height(p) + ROAD_RAISE
		else:
			p.y += ROAD_RAISE
		im.surface_add_vertex(p)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	add_child(mi)
	return mi

func _refresh_colors() -> void:
	# Re-color existing node visuals without rebuilding the whole list.
	var idx: int = 0
	for ri in range(_roads.size()):
		var nodes: Array = _roads[ri]["nodes"]
		for ni in range(nodes.size()):
			if idx >= _node_visuals.size():
				break
			var is_sel: bool = (ri == _selected_road and ni == _selected_node)
			_node_visuals[idx].material_override = _node_mat_selected if is_sel else _node_mat_normal
			idx += 1
