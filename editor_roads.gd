extends Node3D

# Road authoring module owned by the editor. A road is an ordered chain
# of nodes. Each node has in/out bezier tangents stored as local offsets
# from the node's position. Consecutive nodes are connected by a cubic
# bezier (P0=pos_i, P1=pos_i+out_i, P2=pos_{i+1}+in_{i+1}, P3=pos_{i+1}).
# Tangents start at zero — bezier degenerates to a straight line — and
# get auto-seeded the first time the user grabs a handle so the handle
# doesn't snap to the node centre.
#
# Selection model: a selection is (road_i, node_j, kind) where kind is
# 0 = the node itself, 1 = its in-handle, 2 = its out-handle. LMB picks
# whichever sphere the ray hits first. E toggles grab mode on whatever's
# selected; the picked sphere then follows the cursor until E again or
# LMB commits. RMB on empty space deselects (so the next LMB starts a
# new road instead of appending).
#
# Phase 3 will swap the polyline visuals for an extruded asphalt strip.

signal road_state_changed()

const KIND_NODE := 0
const KIND_IN := 1
const KIND_OUT := 2

const NODE_RADIUS := 0.6
const SUB_RADIUS := 0.35
const SELECTED_COLOR := Color(1.0, 0.85, 0.2, 1.0)
const NORMAL_COLOR := Color(0.25, 0.7, 1.0, 1.0)
# Visually green tracks the road's FORWARD direction (toward next node /
# extends past last endpoint), pink tracks BACKWARD (toward prev / extends
# past first endpoint). Storage layout (in_tangent / out_tangent) still
# follows standard bezier convention: in_tangent is the back-side control
# point at a node, out_tangent the forward-side. So the in-handle sphere
# always wears the pink colour and the out-handle the green.
const HANDLE_IN_COLOR := Color(1.0, 0.55, 0.85, 1.0)
const HANDLE_OUT_COLOR := Color(0.4, 1.0, 0.5, 1.0)
const HANDLE_LINE_COLOR := Color(0.7, 0.7, 0.75, 0.9)
const ROAD_LINE_COLOR := Color(0.9, 0.9, 0.95, 1.0)
const ROAD_RAISE := 0.25
const DEFAULT_TANGENT_LEN := 3.0  # used when seeding a zero tangent on first grab
const BEZIER_STEPS := 48
const LATERAL_SUBDIV := 4  # cross-strip quads — top vert count = +1
const DEFAULT_WIDTH := 6.0
const MIN_WIDTH := 1.0
const MAX_WIDTH := 20.0
const WIDTH_STEP := 0.5
const ASPHALT_COLOR := Color(0.12, 0.12, 0.13, 1.0)

# Surface palette. Each road carries one of these ids in its "surface"
# field; we cache one StandardMaterial3D per id and assign it to every
# strip mesh on the road. Add entries here to expose new surfaces — the
# panel's OptionButton enumerates this map at runtime.
const SURFACES := {
	"asphalt":       {"label": "Asphalt",       "color": Color(0.12, 0.12, 0.13), "roughness": 0.85},
	"dirt_road":     {"label": "Dirt road",     "color": Color(0.40, 0.28, 0.16), "roughness": 0.95},
	"dirt_footpath": {"label": "Dirt footpath", "color": Color(0.55, 0.42, 0.26), "roughness": 1.0},
	"gravel":        {"label": "Gravel",        "color": Color(0.48, 0.46, 0.42), "roughness": 0.95},
}
const DEFAULT_SURFACE := "asphalt"

# Lane-markings ride a few mm above the road slab as thin quad strips.
# Each decal entry on a road describes one stripe: a lateral offset (u),
# a stripe width in metres, a colour, and optional dash params. Multiple
# decals stack so the user can compose centre-lines + edge-lines + double
# yellows etc. Quick-add presets in editor_roads_panel.gd push canned
# entries onto this list.
const DECAL_LIFT := 0.012  # metres above slab top
const DECAL_DEFAULT := {
	"offset": 0.5,
	"width": 0.15,
	"color": Color(1.0, 1.0, 1.0, 1.0),
	"dash_length": 0.0,  # 0 = solid
	"gap_length": 0.0,
}

# Map-state shape (mirrored into MapState.roads on save):
#   road = { "id": String, "surface": String, "decals": Array[decal_dict],
#            "nodes": Array[node_dict] }
#   decal_dict = { "offset": float (0..1), "width": float (m), "color": Color,
#                  "dash_length": float (m, 0 = solid), "gap_length": float (m) }
#   node_dict = {
#     "pos": Vector3,
#     "in_tangent":  Vector3,   # offset from pos; (0,0,0) = straight bezier
#     "out_tangent": Vector3,
#     "ignore_terrain": bool,
#     "width": float,          # metres; per-node, lerped along bezier
#   }
var _roads: Array = []
var _selected_road: int = -1
var _selected_node: int = -1
var _selected_kind: int = KIND_NODE
var _grab_active: bool = false

var _terrain: Node3D = null

# Visuals — fully rebuilt on each edit. Cheap enough for the node counts
# we expect; revisit if a road grows past a few hundred nodes.
# Split into overlay vs. mesh so F1 can hide the editing dots without
# also hiding the actual road.
var _overlay_visuals: Array[Node3D] = []
var _mesh_visuals: Array[Node3D] = []
var _overlays_visible: bool = true
var _node_mat_normal: StandardMaterial3D
var _node_mat_selected: StandardMaterial3D
var _handle_in_mat: StandardMaterial3D
var _handle_in_mat_selected: StandardMaterial3D
var _handle_out_mat: StandardMaterial3D
var _handle_out_mat_selected: StandardMaterial3D
var _line_mat: StandardMaterial3D
var _handle_line_mat: StandardMaterial3D
var _surface_mats: Dictionary = {}  # surface id → StandardMaterial3D
var _node_mesh: SphereMesh
var _handle_mesh: SphereMesh

func setup(terrain: Node3D) -> void:
	_terrain = terrain
	_node_mat_normal = _unshaded(NORMAL_COLOR)
	_node_mat_selected = _unshaded(SELECTED_COLOR)
	_handle_in_mat = _unshaded(HANDLE_IN_COLOR)
	_handle_in_mat_selected = _unshaded(SELECTED_COLOR)
	_handle_out_mat = _unshaded(HANDLE_OUT_COLOR)
	_handle_out_mat_selected = _unshaded(SELECTED_COLOR)
	_line_mat = _unshaded(ROAD_LINE_COLOR)
	_handle_line_mat = _unshaded(HANDLE_LINE_COLOR)
	for sid in SURFACES.keys():
		var spec: Dictionary = SURFACES[sid]
		var m := StandardMaterial3D.new()
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		m.albedo_color = spec.get("color", ASPHALT_COLOR)
		m.roughness = float(spec.get("roughness", 0.9))
		m.metallic = 0.0
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_surface_mats[sid] = m
	_node_mesh = SphereMesh.new()
	_node_mesh.radius = NODE_RADIUS
	_node_mesh.height = NODE_RADIUS * 2.0
	_handle_mesh = SphereMesh.new()
	_handle_mesh.radius = SUB_RADIUS
	_handle_mesh.height = SUB_RADIUS * 2.0

# --- State queries (used by save/load + UI) --------------------------------

func get_state() -> Array:
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
				"width": float(n.get("width", DEFAULT_WIDTH)),
			})
		var sid: String = String(r.get("surface", DEFAULT_SURFACE))
		if not SURFACES.has(sid):
			sid = DEFAULT_SURFACE
		var decals_in: Array = r.get("decals", [])
		var decals_out: Array = []
		for d in decals_in:
			decals_out.append(_sanitise_decal(d))
		_roads.append({"id": String(r.get("id", _new_id())), "surface": sid, "decals": decals_out, "nodes": nodes_out})
	_selected_road = -1
	_selected_node = -1
	_selected_kind = KIND_NODE
	_grab_active = false
	_rebuild_visuals()

func clear_all() -> void:
	_roads.clear()
	_selected_road = -1
	_selected_node = -1
	_selected_kind = KIND_NODE
	_grab_active = false
	_rebuild_visuals()

# --- Input-driven actions (called by editor.gd) ----------------------------

# Click on terrain at world_pos. If a sphere (node or handle) was hit,
# pick.x >= 0 and the click selects it.
#
# Subhandle interaction: clicking a handle SELECTS it (highlights). The
# next terrain click while a handle is selected then places a new node
# along the road line — extending past the endpoint for the off-end
# handle of an end node, or splitting the adjacent segment otherwise.
# E starts cursor-follow drag on the selected handle.
func on_click(world_pos: Vector3, picked: Vector3i) -> void:
	if picked.x >= 0:
		_selected_road = picked.x
		_selected_node = picked.y
		_selected_kind = picked.z
		_grab_active = false
		_rebuild_visuals()
		road_state_changed.emit()
		return
	# Empty-terrain click with a subhandle selected → place a new node
	# along the road via that handle's role (extend past endpoint or split
	# the adjacent segment, landing the new node at the click location).
	if _selected_road >= 0 and _selected_node >= 0 and _selected_kind != KIND_NODE:
		_place_via_selected_handle(world_pos)
		return
	var pos := _snap_to_terrain(world_pos, false)
	if _selected_road < 0:
		_roads.append({"id": _new_id(), "surface": DEFAULT_SURFACE, "decals": [], "nodes": []})
		_selected_road = _roads.size() - 1
	var nodes: Array = _roads[_selected_road]["nodes"]
	# Inherit width from the chain end so extending a wide road past its
	# tip doesn't reset back to DEFAULT_WIDTH. The end we're extending from
	# depends on which node is currently selected (or last node if none).
	var inherit_width: float = DEFAULT_WIDTH
	if not nodes.is_empty():
		var src_idx: int = _selected_node if _selected_node >= 0 else nodes.size() - 1
		src_idx = clamp(src_idx, 0, nodes.size() - 1)
		inherit_width = float(nodes[src_idx].get("width", DEFAULT_WIDTH))
	nodes.append({
		"pos": pos,
		"in_tangent": Vector3.ZERO,
		"out_tangent": Vector3.ZERO,
		"ignore_terrain": false,
		"width": inherit_width,
	})
	_selected_node = nodes.size() - 1
	_selected_kind = KIND_NODE
	_rebuild_visuals()
	road_state_changed.emit()

func deselect() -> void:
	_selected_road = -1
	_selected_node = -1
	_selected_kind = KIND_NODE
	_grab_active = false
	_rebuild_visuals()
	road_state_changed.emit()

func set_overlays_visible(v: bool) -> void:
	# F1 toggle. Mesh stays visible — only the editing helpers fade out.
	_overlays_visible = v
	for n in _overlay_visuals:
		if is_instance_valid(n):
			n.visible = v

func overlays_visible() -> bool:
	return _overlays_visible

func selected_info() -> Dictionary:
	# Snapshot for the side panel. has=false means "nothing selected".
	if _selected_road < 0 or _selected_node < 0:
		return {"has": false}
	var road: Dictionary = _roads[_selected_road]
	var nodes: Array = road["nodes"]
	var n: Dictionary = nodes[_selected_node]
	var kind_label: String = "node"
	if _selected_kind == KIND_IN: kind_label = "in-handle"
	elif _selected_kind == KIND_OUT: kind_label = "out-handle"
	return {
		"has": true,
		"width": float(n.get("width", DEFAULT_WIDTH)),
		"ignore_terrain": bool(n.get("ignore_terrain", false)),
		"surface": String(road.get("surface", DEFAULT_SURFACE)),
		"label": "Road %d • node %d/%d (%s)" % [_selected_road + 1, _selected_node + 1, nodes.size(), kind_label],
	}

func set_selected_surface(sid: String) -> void:
	# Surface is per-road, so any selection on a road sets it for the whole
	# chain. No-op for unknown ids.
	if _selected_road < 0 or not SURFACES.has(sid):
		return
	_roads[_selected_road]["surface"] = sid
	_rebuild_visuals()
	road_state_changed.emit()

# Decals ---------------------------------------------------------------------

func selected_road_decals() -> Array:
	if _selected_road < 0:
		return []
	return _roads[_selected_road].get("decals", [])

func add_decal_to_selected(decal: Dictionary = {}) -> void:
	if _selected_road < 0:
		return
	var entry: Dictionary = _sanitise_decal(decal)
	var arr: Array = _roads[_selected_road].get("decals", [])
	arr.append(entry)
	_roads[_selected_road]["decals"] = arr
	_rebuild_visuals()
	road_state_changed.emit()

func remove_decal_from_selected(index: int) -> void:
	if _selected_road < 0:
		return
	var arr: Array = _roads[_selected_road].get("decals", [])
	if index < 0 or index >= arr.size():
		return
	arr.remove_at(index)
	_roads[_selected_road]["decals"] = arr
	_rebuild_visuals()
	road_state_changed.emit()

func update_decal_on_selected(index: int, field: String, value) -> void:
	if _selected_road < 0:
		return
	var arr: Array = _roads[_selected_road].get("decals", [])
	if index < 0 or index >= arr.size():
		return
	var d: Dictionary = arr[index]
	d[field] = value
	arr[index] = _sanitise_decal(d)
	_roads[_selected_road]["decals"] = arr
	_rebuild_visuals()
	road_state_changed.emit()

func _sanitise_decal(d: Dictionary) -> Dictionary:
	# Coerce numbers/colours and clamp into the ranges the renderer assumes
	# (offset in [0,1], non-negative widths/dashes). Saves the renderer from
	# checking each frame and means hand-edited JSON imports cleanly.
	var out: Dictionary = DECAL_DEFAULT.duplicate(true)
	for k in out.keys():
		if d.has(k):
			out[k] = d[k]
	out["offset"] = clamp(float(out.get("offset", 0.5)), 0.0, 1.0)
	out["width"] = max(0.02, float(out.get("width", 0.15)))
	out["dash_length"] = max(0.0, float(out.get("dash_length", 0.0)))
	out["gap_length"] = max(0.0, float(out.get("gap_length", 0.0)))
	var c = out.get("color", Color(1, 1, 1, 1))
	if c is Color:
		out["color"] = c
	else:
		out["color"] = Color(1, 1, 1, 1)
	return out

func set_selected_width(w: float) -> void:
	if _selected_road < 0 or _selected_node < 0:
		return
	var nodes: Array = _roads[_selected_road]["nodes"]
	var n: Dictionary = nodes[_selected_node]
	n["width"] = clamp(w, MIN_WIDTH, MAX_WIDTH)
	nodes[_selected_node] = n
	_rebuild_visuals()
	road_state_changed.emit()

func set_selected_ignore_terrain(b: bool) -> void:
	if _selected_road < 0 or _selected_node < 0:
		return
	var nodes: Array = _roads[_selected_road]["nodes"]
	var n: Dictionary = nodes[_selected_node]
	n["ignore_terrain"] = b
	nodes[_selected_node] = n
	_rebuild_visuals()
	road_state_changed.emit()

func toggle_grab() -> void:
	if _selected_road < 0 or _selected_node < 0:
		return
	if not _grab_active:
		if _selected_kind != KIND_NODE:
			_seed_tangent_if_zero()
	_grab_active = not _grab_active

func toggle_grab_at_cursor(ray_origin: Vector3, ray_dir: Vector3) -> void:
	# E hotkey entry point. If the cursor is hovering a handle, swap the
	# selection to that handle before toggling grab. This is how the user
	# picks WHICH handle to bend — clicking a handle inserts a node, so
	# hover-pick is the only way to drag one.
	if not _grab_active:
		var hover: Vector3i = pick_node(ray_origin, ray_dir)
		if hover.x >= 0 and hover.z != KIND_NODE:
			_selected_road = hover.x
			_selected_node = hover.y
			_selected_kind = hover.z
			_seed_tangent_if_zero()
			_grab_active = true
			_rebuild_visuals()
			return
	toggle_grab()
	_rebuild_visuals()

func is_grabbing() -> bool:
	return _grab_active

func on_cursor_world(world_pos: Vector3) -> void:
	if not _grab_active:
		return
	if _selected_road < 0 or _selected_node < 0:
		return
	var nodes: Array = _roads[_selected_road]["nodes"]
	var n: Dictionary = nodes[_selected_node]
	if _selected_kind == KIND_NODE:
		var ignore: bool = bool(n.get("ignore_terrain", false))
		n["pos"] = _snap_to_terrain(world_pos, ignore)
	else:
		# Handles store an offset from the node position. Cursor world pos
		# is on the terrain plane; subtract node pos to get the offset.
		var node_pos: Vector3 = n.get("pos", Vector3.ZERO)
		var offset: Vector3 = world_pos - node_pos
		# Cursor rides the terrain, so y-component is noisy. Keep handles
		# horizontal w.r.t. their node; bezier samples re-snap y anyway.
		offset.y = 0.0
		if _selected_kind == KIND_IN:
			n["in_tangent"] = offset
		else:
			n["out_tangent"] = offset
	nodes[_selected_node] = n
	_rebuild_visuals()

func commit_grab() -> void:
	if _grab_active:
		_grab_active = false
		road_state_changed.emit()

func adjust_selected_width(delta: float) -> void:
	# Per-node width control. Bracket keys [/] in the editor call this on
	# the currently selected node (or the node owning a selected handle).
	if _selected_road < 0 or _selected_node < 0:
		return
	var nodes: Array = _roads[_selected_road]["nodes"]
	var n: Dictionary = nodes[_selected_node]
	var w: float = float(n.get("width", DEFAULT_WIDTH)) + delta
	n["width"] = clamp(w, MIN_WIDTH, MAX_WIDTH)
	nodes[_selected_node] = n
	_rebuild_visuals()
	road_state_changed.emit()

func selected_node_width() -> float:
	if _selected_road < 0 or _selected_node < 0:
		return -1.0
	var nodes: Array = _roads[_selected_road]["nodes"]
	return float(nodes[_selected_node].get("width", DEFAULT_WIDTH))

func delete_selected_node() -> void:
	if _selected_road < 0 or _selected_node < 0:
		return
	# Delete deletes the whole node even if a handle is selected — handles
	# can't exist without their parent. Same convention as most DCC tools.
	var nodes: Array = _roads[_selected_road]["nodes"]
	nodes.remove_at(_selected_node)
	if nodes.is_empty():
		_roads.remove_at(_selected_road)
		_selected_road = -1
		_selected_node = -1
	else:
		_selected_node = clamp(_selected_node, 0, nodes.size() - 1)
	_selected_kind = KIND_NODE
	_grab_active = false
	_rebuild_visuals()
	road_state_changed.emit()

# Picks a sphere under the cursor. Returns Vector3i(road, node, kind) or
# (-1,-1,-1) on a miss. Handles are only pickable on the currently
# selected node + the chained-to neighbours of the selected road, to keep
# the scene from being a forest of grabbable dots.
func pick_node(ray_origin: Vector3, ray_dir: Vector3) -> Vector3i:
	var best_t: float = INF
	var best := Vector3i(-1, -1, -1)
	for ri in range(_roads.size()):
		var nodes: Array = _roads[ri]["nodes"]
		for ni in range(nodes.size()):
			var n: Dictionary = nodes[ni]
			var c: Vector3 = n.get("pos", Vector3.ZERO)
			c.y += ROAD_RAISE
			var t: float = _ray_sphere(ray_origin, ray_dir, c, NODE_RADIUS * 1.4)
			if t > 0.0 and t < best_t:
				best_t = t
				best = Vector3i(ri, ni, KIND_NODE)
			var hi: Vector3 = c + _effective_tangent_at(nodes, ni, KIND_IN)
			var ho: Vector3 = c + _effective_tangent_at(nodes, ni, KIND_OUT)
			var ti: float = _ray_sphere(ray_origin, ray_dir, hi, SUB_RADIUS * 1.6)
			if ti > 0.0 and ti < best_t:
				best_t = ti
				best = Vector3i(ri, ni, KIND_IN)
			var to: float = _ray_sphere(ray_origin, ray_dir, ho, SUB_RADIUS * 1.6)
			if to > 0.0 and to < best_t:
				best_t = to
				best = Vector3i(ri, ni, KIND_OUT)
	return best

# --- Internals -------------------------------------------------------------

func _place_via_selected_handle(world_pos: Vector3) -> void:
	# With a subhandle currently selected, an empty-terrain click inserts a
	# new node at the click location and threads it into the chain on the
	# handle's side: in-handle inserts BEFORE the selected node, out-handle
	# inserts AFTER. Endpoint extends fall out of this rule for free — the
	# in-handle of node 0 inserts at index 0 (prepend), the out-handle of
	# the last node inserts at size (append). Tangents stay zero so the
	# curve doesn't develop a kink until the user grabs a handle.
	var road_i: int = _selected_road
	var node_i: int = _selected_node
	var kind: int = _selected_kind
	var nodes: Array = _roads[road_i]["nodes"]
	var src: Dictionary = nodes[node_i]
	var new_pos: Vector3 = _snap_to_terrain(world_pos, false)
	var new_node: Dictionary = {
		"pos": new_pos,
		"in_tangent": Vector3.ZERO,
		"out_tangent": Vector3.ZERO,
		"ignore_terrain": false,
		"width": float(src.get("width", DEFAULT_WIDTH)),
	}
	var insert_at: int = node_i if kind == KIND_IN else node_i + 1
	nodes.insert(insert_at, new_node)
	_selected_node = insert_at
	_selected_kind = KIND_NODE
	_grab_active = false
	_rebuild_visuals()
	road_state_changed.emit()

func _seed_tangent_if_zero() -> void:
	var nodes: Array = _roads[_selected_road]["nodes"]
	var n: Dictionary = nodes[_selected_node]
	var key: String = "in_tangent" if _selected_kind == KIND_IN else "out_tangent"
	var cur: Vector3 = n.get(key, Vector3.ZERO)
	if cur.length_squared() > 0.0001:
		return
	# Seed from neighbour chord direction when available, otherwise +X.
	var dir := Vector3.RIGHT
	if _selected_kind == KIND_IN and _selected_node > 0:
		var prev_pos: Vector3 = nodes[_selected_node - 1].get("pos", Vector3.ZERO)
		var here: Vector3 = n.get("pos", Vector3.ZERO)
		dir = (prev_pos - here).normalized()
	elif _selected_kind == KIND_OUT and _selected_node < nodes.size() - 1:
		var next_pos: Vector3 = nodes[_selected_node + 1].get("pos", Vector3.ZERO)
		var here2: Vector3 = n.get("pos", Vector3.ZERO)
		dir = (next_pos - here2).normalized()
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3.RIGHT
	n[key] = dir.normalized() * DEFAULT_TANGENT_LEN
	nodes[_selected_node] = n

func _effective_tangent_at(nodes: Array, ni: int, kind: int) -> Vector3:
	# Tangent used for visuals + handle-picking. If the stored tangent is
	# zero we still expose the handle slightly off the node so a future
	# click can grab it. Fallback direction is derived from chord-to-
	# neighbours so the in-handle always sits along the road behind the
	# node and the out-handle ahead of it — independent of which way the
	# road runs in world space.
	var n: Dictionary = nodes[ni]
	var key: String = "in_tangent" if kind == KIND_IN else "out_tangent"
	var t: Vector3 = n.get(key, Vector3.ZERO)
	if t.length_squared() > 0.0001:
		return t
	var here: Vector3 = n.get("pos", Vector3.ZERO)
	var dir := Vector3.ZERO
	if kind == KIND_IN:
		if ni > 0:
			dir = nodes[ni - 1].get("pos", here) - here
		elif ni < nodes.size() - 1:
			# First node with no prev: project the in-handle BACKWARD past
			# the start by mirroring the chord to the next node.
			dir = here - nodes[ni + 1].get("pos", here)
		else:
			dir = Vector3.LEFT
	else:
		if ni < nodes.size() - 1:
			dir = nodes[ni + 1].get("pos", here) - here
		elif ni > 0:
			# Last node with no next: project FORWARD past the end by
			# mirroring the chord from the previous node.
			dir = here - nodes[ni - 1].get("pos", here)
		else:
			dir = Vector3.RIGHT
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3.RIGHT if kind == KIND_OUT else Vector3.LEFT
	return dir.normalized() * (DEFAULT_TANGENT_LEN * 0.5)

func _effective_tangent(n: Dictionary, kind: int) -> Vector3:
	# Legacy single-node form kept for sites that don't have an index handy.
	# Falls back to a world-axis direction; prefer _effective_tangent_at.
	var key: String = "in_tangent" if kind == KIND_IN else "out_tangent"
	var t: Vector3 = n.get(key, Vector3.ZERO)
	if t.length_squared() > 0.0001:
		return t
	var fallback := Vector3.RIGHT if kind == KIND_OUT else Vector3.LEFT
	return fallback * (DEFAULT_TANGENT_LEN * 0.5)

func _snap_to_terrain(world_pos: Vector3, ignore: bool) -> Vector3:
	var p := world_pos
	if not ignore and _terrain != null:
		p.y = _terrain.sample_height(p)
	return p

func _ray_sphere(ro: Vector3, rd: Vector3, c: Vector3, r: float) -> float:
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

func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Editor overlay markers always render on top of road slab + terrain so
	# handles/lines/spheres can be clicked regardless of camera angle. The
	# road mesh itself uses a different material and still depth-tests.
	m.no_depth_test = true
	m.render_priority = 1
	return m

func _rebuild_visuals() -> void:
	for v in _overlay_visuals:
		v.queue_free()
	_overlay_visuals.clear()
	for v in _mesh_visuals:
		v.queue_free()
	_mesh_visuals.clear()
	for ri in range(_roads.size()):
		var nodes: Array = _roads[ri]["nodes"]
		var road_is_selected: bool = (ri == _selected_road)
		for ni in range(nodes.size()):
			var n: Dictionary = nodes[ni]
			var p: Vector3 = n.get("pos", Vector3.ZERO)
			p.y += ROAD_RAISE
			var is_node_sel: bool = (road_is_selected and ni == _selected_node and _selected_kind == KIND_NODE)
			_spawn_sphere(_node_mesh, p, _node_mat_selected if is_node_sel else _node_mat_normal)
			# Handles render for every road so a stale selection doesn't hide
			# the click targets that insert new nodes / drag tangents.
			var in_off: Vector3 = _effective_tangent_at(nodes, ni, KIND_IN)
			var out_off: Vector3 = _effective_tangent_at(nodes, ni, KIND_OUT)
			var hi: Vector3 = p + in_off
			var ho: Vector3 = p + out_off
			var is_in_sel: bool = (road_is_selected and ni == _selected_node and _selected_kind == KIND_IN)
			var is_out_sel: bool = (road_is_selected and ni == _selected_node and _selected_kind == KIND_OUT)
			_spawn_sphere(_handle_mesh, hi, _handle_in_mat_selected if is_in_sel else _handle_in_mat)
			_spawn_sphere(_handle_mesh, ho, _handle_out_mat_selected if is_out_sel else _handle_out_mat)
			_spawn_segment(p, hi, _handle_line_mat)
			_spawn_segment(p, ho, _handle_line_mat)
		# Surface strip mesh between consecutive nodes.
		var sid: String = String(_roads[ri].get("surface", DEFAULT_SURFACE))
		var mat: StandardMaterial3D = _surface_mats.get(sid, _surface_mats[DEFAULT_SURFACE])
		for ni in range(nodes.size() - 1):
			_spawn_road_strip(nodes[ni], nodes[ni + 1], mat)
		# Lane decals — one mesh per decal layer, sharing the slab's bezier
		# sampling but offset laterally + lifted slightly to avoid z-fight.
		var decals: Array = _roads[ri].get("decals", [])
		for d in decals:
			for ni in range(nodes.size() - 1):
				_spawn_decal_strip(nodes[ni], nodes[ni + 1], d)
		# Centreline polyline drawn on top of the slab so the bezier shape
		# stays readable through the surface.
		for ni in range(nodes.size() - 1):
			_spawn_bezier_polyline(nodes[ni], nodes[ni + 1])

func _spawn_sphere(mesh: SphereMesh, world_pos: Vector3, mat: StandardMaterial3D) -> void:
	var v := MeshInstance3D.new()
	v.mesh = mesh
	v.material_override = mat
	v.position = world_pos
	v.visible = _overlays_visible
	add_child(v)
	_overlay_visuals.append(v)

func _spawn_segment(a: Vector3, b: Vector3, mat: StandardMaterial3D) -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.visible = _overlays_visible
	add_child(mi)
	_overlay_visuals.append(mi)

func _spawn_bezier_polyline(a: Dictionary, b: Dictionary) -> void:
	# Sample the cubic between two node dicts and stitch consecutive samples
	# as ImmediateMesh line segments. Uses the overlay line material which
	# disables depth test, so the polyline reads on top of the slab.
	var a_pos: Vector3 = a.get("pos", Vector3.ZERO)
	var b_pos: Vector3 = b.get("pos", Vector3.ZERO)
	var a_out: Vector3 = a.get("out_tangent", Vector3.ZERO)
	var b_in: Vector3 = b.get("in_tangent", Vector3.ZERO)
	var p0 := a_pos
	var p1 := a_pos + a_out
	var p2 := b_pos + b_in
	var p3 := b_pos
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, _line_mat)
	var prev: Vector3 = p0
	prev.y += ROAD_RAISE
	for i in range(1, BEZIER_STEPS + 1):
		var t: float = float(i) / float(BEZIER_STEPS)
		var c: Vector3 = _cubic_bezier(p0, p1, p2, p3, t)
		c.y += ROAD_RAISE
		im.surface_add_vertex(prev)
		im.surface_add_vertex(c)
		prev = c
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.visible = _overlays_visible
	add_child(mi)
	_overlay_visuals.append(mi)

func _spawn_decal_strip(a: Dictionary, b: Dictionary, decal: Dictionary) -> void:
	# Lays a single decal stripe along one bezier segment. Offset is u in
	# [0,1] across the road (0.5 = centre). Solid stripes emit one stitched
	# triangle strip; dashed stripes break the strip every `dash + gap` arc
	# metres so the gaps are visible holes, not z-fought slivers.
	var a_pos: Vector3 = a.get("pos", Vector3.ZERO)
	var b_pos: Vector3 = b.get("pos", Vector3.ZERO)
	var a_out: Vector3 = a.get("out_tangent", Vector3.ZERO)
	var b_in: Vector3 = b.get("in_tangent", Vector3.ZERO)
	var p0 := a_pos
	var p1 := a_pos + a_out
	var p2 := b_pos + b_in
	var p3 := b_pos
	var a_ignore: bool = bool(a.get("ignore_terrain", false))
	var b_ignore: bool = bool(b.get("ignore_terrain", false))
	var wa: float = float(a.get("width", DEFAULT_WIDTH))
	var wb: float = float(b.get("width", DEFAULT_WIDTH))
	var offset_u: float = clamp(float(decal.get("offset", 0.5)), 0.0, 1.0)
	var decal_half: float = max(0.01, float(decal.get("width", 0.15)) * 0.5)
	var dash_len: float = float(decal.get("dash_length", 0.0))
	var gap_len: float = float(decal.get("gap_length", 0.0))
	var dashed: bool = dash_len > 0.001 and gap_len > 0.001
	var col: Color = decal.get("color", Color(1, 1, 1, 1))
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var arc_len: float = 0.0
	var prev_c: Vector3 = _cubic_bezier(p0, p1, p2, p3, 0.0)
	var emit_indices_for: bool = true  # whether to stitch quad between previous and current sample
	var pair_count: int = 0  # how many (left, right) vert pairs we've emitted so far
	for i in range(BEZIER_STEPS + 1):
		var t: float = float(i) / float(BEZIER_STEPS)
		var c: Vector3 = _cubic_bezier(p0, p1, p2, p3, t)
		var tan: Vector3 = _cubic_bezier_tangent(p0, p1, p2, p3, t)
		var tan_flat := tan
		tan_flat.y = 0.0
		if tan_flat.length_squared() < 0.0001:
			var chord_xz: Vector3 = p3 - p0
			chord_xz.y = 0.0
			if chord_xz.length_squared() < 0.0001:
				tan_flat = Vector3(0, 0, -1)
			else:
				tan_flat = chord_xz
		tan_flat = tan_flat.normalized()
		var right_v: Vector3 = tan_flat.cross(Vector3.UP).normalized()
		var half_road: float = lerp(wa, wb, t) * 0.5
		var lateral: float = (offset_u - 0.5) * 2.0 * half_road
		var centre_xz: Vector3 = c + right_v * lateral
		var ignore: bool = a_ignore if t < 0.5 else b_ignore
		var y: float = c.y
		if not ignore and _terrain != null:
			y = _terrain.sample_height(centre_xz)
		var top_y: float = y + ROAD_RAISE + DECAL_LIFT
		# Cumulative arc length for dash logic.
		if i > 0:
			arc_len += c.distance_to(prev_c)
		prev_c = c
		var in_dash: bool = true
		if dashed:
			var cycle: float = dash_len + gap_len
			var mod_pos: float = fposmod(arc_len, cycle)
			in_dash = mod_pos < dash_len
		if dashed and not in_dash:
			emit_indices_for = false
			continue
		var l: Vector3 = Vector3(centre_xz.x - right_v.x * decal_half, top_y, centre_xz.z - right_v.z * decal_half)
		var r: Vector3 = Vector3(centre_xz.x + right_v.x * decal_half, top_y, centre_xz.z + right_v.z * decal_half)
		verts.append(l)
		verts.append(r)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		uvs.append(Vector2(0.0, t))
		uvs.append(Vector2(1.0, t))
		if emit_indices_for and pair_count > 0:
			# Stitch this pair to the previous emitted pair.
			var a0: int = (pair_count - 1) * 2
			var b1: int = pair_count * 2
			indices.append(a0); indices.append(b1); indices.append(a0 + 1)
			indices.append(a0 + 1); indices.append(b1); indices.append(b1 + 1)
		pair_count += 1
		emit_indices_for = true
	if verts.size() < 4 or indices.size() < 3:
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = indices
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var dm := StandardMaterial3D.new()
	dm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = col
	if col.a < 1.0:
		dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = dm
	add_child(mi)
	_mesh_visuals.append(mi)

func _spawn_road_strip(a: Dictionary, b: Dictionary, mat: StandardMaterial3D) -> void:
	# Extrudes a flat ribbon along the cubic bezier between two nodes.
	# Width is lerped between the endpoints' per-node widths. Each sample
	# emits two verts (left/right of the centreline along the horizontal
	# normal of the curve tangent), and consecutive samples are stitched
	# with two triangles. Y is snapped to terrain unless the nearer
	# endpoint has ignore_terrain set.
	var a_pos: Vector3 = a.get("pos", Vector3.ZERO)
	var b_pos: Vector3 = b.get("pos", Vector3.ZERO)
	var a_out: Vector3 = a.get("out_tangent", Vector3.ZERO)
	var b_in: Vector3 = b.get("in_tangent", Vector3.ZERO)
	var p0 := a_pos
	var p1 := a_pos + a_out
	var p2 := b_pos + b_in
	var p3 := b_pos
	var a_ignore: bool = bool(a.get("ignore_terrain", false))
	var b_ignore: bool = bool(b.get("ignore_terrain", false))
	var wa: float = float(a.get("width", DEFAULT_WIDTH))
	var wb: float = float(b.get("width", DEFAULT_WIDTH))
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	# Per sample we emit FOUR verts: top-left, top-right, bottom-left,
	# bottom-right. The top surface drives the visible drive surface
	# (snapped to terrain + ROAD_RAISE at the edge). The bottom matches
	# terrain so the slab kisses the ground. Thin side strips connect top
	# to bottom so the road reads as a chunky slab from any angle.
	# Per longitudinal sample: (LATERAL_SUBDIV + 1) top verts spanning the
	# cross-section + 2 bottom corner verts. Each top vert samples terrain
	# at its own XZ so the strip drapes laterally over cross-slopes.
	var top_count: int = LATERAL_SUBDIV + 1
	var verts_per_sample: int = top_count + 2
	for i in range(BEZIER_STEPS + 1):
		var t: float = float(i) / float(BEZIER_STEPS)
		var c: Vector3 = _cubic_bezier(p0, p1, p2, p3, t)
		var tan: Vector3 = _cubic_bezier_tangent(p0, p1, p2, p3, t)
		tan.y = 0.0
		if tan.length_squared() < 0.0001:
			# Endpoints with zero stored tangents produce a zero bezier
			# derivative — fall back to the segment chord so the cross-
			# section stays aligned with the road's actual direction
			# instead of snapping to a world-axis and folding 180°.
			var chord_xz: Vector3 = p3 - p0
			chord_xz.y = 0.0
			if chord_xz.length_squared() < 0.0001:
				tan = Vector3(0, 0, -1)
			else:
				tan = chord_xz
		tan = tan.normalized()
		var right: Vector3 = tan.cross(Vector3.UP).normalized()
		var half: float = lerp(wa, wb, t) * 0.5
		var ignore: bool = a_ignore if t < 0.5 else b_ignore
		var l_xz: Vector3 = c - right * half
		var r_xz: Vector3 = c + right * half
		var top_ys: PackedFloat32Array = PackedFloat32Array()
		top_ys.resize(top_count)
		var y_min: float = INF
		for k in range(top_count):
			var u: float = float(k) / float(LATERAL_SUBDIV)
			var sxz: Vector3 = l_xz.lerp(r_xz, u)
			var sy: float = c.y
			if not ignore and _terrain != null:
				sy = _terrain.sample_height(sxz)
			top_ys[k] = sy
			y_min = min(y_min, sy)
		for k in range(top_count):
			var u2: float = float(k) / float(LATERAL_SUBDIV)
			var pos: Vector3 = l_xz.lerp(r_xz, u2)
			verts.append(Vector3(pos.x, top_ys[k] + ROAD_RAISE, pos.z))
			normals.append(Vector3.UP)
			uvs.append(Vector2(u2, t))
		verts.append(Vector3(l_xz.x, y_min - 0.05, l_xz.z))
		verts.append(Vector3(r_xz.x, y_min - 0.05, r_xz.z))
		normals.append(Vector3.DOWN); normals.append(Vector3.DOWN)
		uvs.append(Vector2(0.0, t)); uvs.append(Vector2(1.0, t))
	for i in range(BEZIER_STEPS):
		var ba: int = i * verts_per_sample
		var bb: int = (i + 1) * verts_per_sample
		for k in range(LATERAL_SUBDIV):
			var a0: int = ba + k;     var b0: int = ba + k + 1
			var a1: int = bb + k;     var b1: int = bb + k + 1
			indices.append(a0); indices.append(a1); indices.append(b0)
			indices.append(b0); indices.append(a1); indices.append(b1)
		var lt0: int = ba
		var lb0: int = ba + top_count
		var lt1: int = bb
		var lb1: int = bb + top_count
		indices.append(lt0); indices.append(lb0); indices.append(lt1)
		indices.append(lt1); indices.append(lb0); indices.append(lb1)
		var rt0: int = ba + LATERAL_SUBDIV
		var rb0: int = ba + top_count + 1
		var rt1: int = bb + LATERAL_SUBDIV
		var rb1: int = bb + top_count + 1
		indices.append(rt0); indices.append(rt1); indices.append(rb0)
		indices.append(rb0); indices.append(rt1); indices.append(rb1)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = indices
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = mat
	add_child(mi)
	_mesh_visuals.append(mi)

func _cubic_bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var u: float = 1.0 - t
	return (u * u * u) * p0 + (3.0 * u * u * t) * p1 + (3.0 * u * t * t) * p2 + (t * t * t) * p3

func _cubic_bezier_tangent(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var u: float = 1.0 - t
	return 3.0 * u * u * (p1 - p0) + 6.0 * u * t * (p2 - p1) + 3.0 * t * t * (p3 - p2)
