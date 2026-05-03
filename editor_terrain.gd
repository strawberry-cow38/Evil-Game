extends Node3D

# Editor heightmap terrain. Backing data is a flat float array
# (heights[x + y*GRID_W]) sampled at 1m vertex spacing. The mesh and
# the StaticBody collider are rebuilt whenever heights change in a
# tool stroke. Brush operations take a world-space center + radius and
# walk only the affected vertex window for speed.

const GRID_W := 128            # vertices per side (127 quads)
const GRID_H := 128
const VERT_SPACING := 1.0      # metres between vertices
const ORIGIN_OFFSET := Vector3(-64.0, 0.0, -64.0)  # world pos of vertex (0,0)

var heights: PackedFloat32Array = PackedFloat32Array()

var _mesh_instance: MeshInstance3D
var _body: StaticBody3D
var _collision: CollisionShape3D
var _material: StandardMaterial3D
# Pre-built static index buffer (vertex order is fixed; only positions
# move). Allocating it once kills the worst per-stroke cost.
var _indices: PackedInt32Array = PackedInt32Array()
var _uvs: PackedVector2Array = PackedVector2Array()
var _vertices: PackedVector3Array = PackedVector3Array()
var _normals: PackedVector3Array = PackedVector3Array()
var _array_mesh: ArrayMesh = null
# Coalesced rebuild flags. Brush calls just mark these — actual mesh
# work happens in _process at most once per frame, and collision
# rebuild waits until end_stroke() is called.
var _mesh_dirty: bool = false
var _collision_dirty: bool = false

func _ready() -> void:
	heights.resize(GRID_W * GRID_H)
	for i in heights.size():
		heights[i] = 0.0
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.42, 0.55, 0.35, 1.0)
	_material.roughness = 0.9
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)
	_body = StaticBody3D.new()
	add_child(_body)
	_collision = CollisionShape3D.new()
	_body.add_child(_collision)
	_init_static_buffers()
	_array_mesh = ArrayMesh.new()
	_mesh_instance.mesh = _array_mesh
	_rebuild_mesh_now()
	_rebuild_collision_now()

func _process(_delta: float) -> void:
	if _mesh_dirty:
		_rebuild_mesh_now()
		_mesh_dirty = false

func _init_static_buffers() -> void:
	# Index + UV buffers depend only on grid topology, so build once.
	_indices.resize((GRID_W - 1) * (GRID_H - 1) * 6)
	_uvs.resize(GRID_W * GRID_H)
	_vertices.resize(GRID_W * GRID_H)
	_normals.resize(GRID_W * GRID_H)
	var k: int = 0
	for y in range(GRID_H - 1):
		for x in range(GRID_W - 1):
			var i: int     = _idx(x,     y)
			var i_r: int   = _idx(x + 1, y)
			var i_d: int   = _idx(x,     y + 1)
			var i_dr: int  = _idx(x + 1, y + 1)
			# CCW winding viewed from +Y → top face is the front face.
			_indices[k]     = i
			_indices[k + 1] = i_r
			_indices[k + 2] = i_d
			_indices[k + 3] = i_r
			_indices[k + 4] = i_dr
			_indices[k + 5] = i_d
			k += 6
	for y in range(GRID_H):
		for x in range(GRID_W):
			_uvs[_idx(x, y)] = Vector2(
				float(x) / float(GRID_W - 1),
				float(y) / float(GRID_H - 1),
			)

func world_to_grid(p: Vector3) -> Vector2:
	var local := p - global_position - ORIGIN_OFFSET
	return Vector2(local.x / VERT_SPACING, local.z / VERT_SPACING)

func grid_to_world(gx: int, gy: int) -> Vector3:
	return global_position + ORIGIN_OFFSET + Vector3(gx * VERT_SPACING, heights[gx + gy * GRID_W], gy * VERT_SPACING)

func _idx(x: int, y: int) -> int:
	return x + y * GRID_W

func _in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < GRID_W and y >= 0 and y < GRID_H

# Walk every vertex inside `radius` of `center` (XZ distance), call
# `op` with (idx, falloff[0..1]). op mutates heights directly.
func _stamp(center: Vector3, radius: float, op: Callable) -> void:
	var g := world_to_grid(center)
	var rg: float = radius / VERT_SPACING
	var x0: int = max(0, int(floor(g.x - rg)))
	var x1: int = min(GRID_W - 1, int(ceil(g.x + rg)))
	var y0: int = max(0, int(floor(g.y - rg)))
	var y1: int = min(GRID_H - 1, int(ceil(g.y + rg)))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx: float = float(x) - g.x
			var dy: float = float(y) - g.y
			var d: float = sqrt(dx * dx + dy * dy)
			if d > rg:
				continue
			var f: float = 1.0 - (d / rg)
			f = f * f * (3.0 - 2.0 * f)  # smoothstep falloff
			op.call(_idx(x, y), f)

func raise_brush(center: Vector3, radius: float, strength: float, delta: float) -> void:
	var amount: float = strength * delta
	_stamp(center, radius, func(i, f): heights[i] += amount * f)
	_mark_dirty()

func lower_brush(center: Vector3, radius: float, strength: float, delta: float) -> void:
	raise_brush(center, radius, -strength, delta)

func flatten_brush(center: Vector3, radius: float, target_h: float, strength: float, delta: float) -> void:
	var rate: float = clampf(strength * delta, 0.0, 1.0)
	_stamp(center, radius, func(i, f):
		heights[i] = lerpf(heights[i], target_h, rate * f)
	)
	_mark_dirty()

func smooth_brush(center: Vector3, radius: float, strength: float, delta: float) -> void:
	# Box-blur each touched vertex with its 8 neighbours.
	var g := world_to_grid(center)
	var rg: float = radius / VERT_SPACING
	var x0: int = max(1, int(floor(g.x - rg)))
	var x1: int = min(GRID_W - 2, int(ceil(g.x + rg)))
	var y0: int = max(1, int(floor(g.y - rg)))
	var y1: int = min(GRID_H - 2, int(ceil(g.y + rg)))
	var rate: float = clampf(strength * delta, 0.0, 1.0)
	var src := heights.duplicate()
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx: float = float(x) - g.x
			var dy: float = float(y) - g.y
			var d: float = sqrt(dx * dx + dy * dy)
			if d > rg:
				continue
			var f: float = 1.0 - (d / rg)
			f = f * f * (3.0 - 2.0 * f)
			var sum: float = 0.0
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					sum += src[_idx(x + ox, y + oy)]
			var avg: float = sum / 9.0
			heights[_idx(x, y)] = lerpf(heights[_idx(x, y)], avg, rate * f)
	_mark_dirty()

# Two-point ramp: linearly slope between height(start) and height(end)
# for vertices inside a corridor of `radius` around the line segment.
func ramp_stroke(start: Vector3, end: Vector3, radius: float) -> void:
	var sg := world_to_grid(start)
	var eg := world_to_grid(end)
	var rg: float = radius / VERT_SPACING
	var sx: int = max(0, int(floor(min(sg.x, eg.x) - rg)))
	var ex: int = min(GRID_W - 1, int(ceil(max(sg.x, eg.x) + rg)))
	var sy: int = max(0, int(floor(min(sg.y, eg.y) - rg)))
	var ey: int = min(GRID_H - 1, int(ceil(max(sg.y, eg.y) + rg)))
	var seg: Vector2 = eg - sg
	var seg_len_sq: float = seg.length_squared()
	if seg_len_sq < 0.0001:
		return
	var h_start: float = sample_height(start)
	var h_end: float = sample_height(end)
	for y in range(sy, ey + 1):
		for x in range(sx, ex + 1):
			var p := Vector2(float(x), float(y))
			var t: float = clampf((p - sg).dot(seg) / seg_len_sq, 0.0, 1.0)
			var proj: Vector2 = sg + seg * t
			var d: float = (p - proj).length()
			if d > rg:
				continue
			var f: float = 1.0 - (d / rg)
			f = f * f * (3.0 - 2.0 * f)
			var target: float = lerpf(h_start, h_end, t)
			heights[_idx(x, y)] = lerpf(heights[_idx(x, y)], target, f)
	_mark_dirty()

func sample_height(world_pos: Vector3) -> float:
	var g := world_to_grid(world_pos)
	var x0: int = clampi(int(floor(g.x)), 0, GRID_W - 2)
	var y0: int = clampi(int(floor(g.y)), 0, GRID_H - 2)
	var fx: float = clampf(g.x - x0, 0.0, 1.0)
	var fy: float = clampf(g.y - y0, 0.0, 1.0)
	var h00: float = heights[_idx(x0,     y0)]
	var h10: float = heights[_idx(x0 + 1, y0)]
	var h01: float = heights[_idx(x0,     y0 + 1)]
	var h11: float = heights[_idx(x0 + 1, y0 + 1)]
	var hx0: float = lerpf(h00, h10, fx)
	var hx1: float = lerpf(h01, h11, fx)
	return lerpf(hx0, hx1, fy)

# Public entry — call after a brush stroke ends (LMB up) to rebuild
# the collider. Cheap enough to do once per stroke; far too slow per
# frame.
func end_stroke() -> void:
	# Make sure mesh is up to date before snapshotting collision.
	if _mesh_dirty:
		_rebuild_mesh_now()
		_mesh_dirty = false
	_rebuild_collision_now()

func _mark_dirty() -> void:
	_mesh_dirty = true
	_collision_dirty = true

func _rebuild_mesh_now() -> void:
	# Update vertex positions in-place from heights.
	for y in range(GRID_H):
		for x in range(GRID_W):
			_vertices[_idx(x, y)] = Vector3(
				ORIGIN_OFFSET.x + x * VERT_SPACING,
				heights[_idx(x, y)],
				ORIGIN_OFFSET.z + y * VERT_SPACING,
			)
	# Per-vertex normals from cardinal-neighbour height differences.
	# Cheap and good enough for an editor preview.
	for y in range(GRID_H):
		for x in range(GRID_W):
			var hl: float = heights[_idx(max(0, x - 1), y)]
			var hr: float = heights[_idx(min(GRID_W - 1, x + 1), y)]
			var hd: float = heights[_idx(x, max(0, y - 1))]
			var hu: float = heights[_idx(x, min(GRID_H - 1, y + 1))]
			_normals[_idx(x, y)] = Vector3(hl - hr, 2.0 * VERT_SPACING, hd - hu).normalized()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX]  = _indices
	_array_mesh.clear_surfaces()
	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_array_mesh.surface_set_material(0, _material)

func _rebuild_collision_now() -> void:
	var shape := ConcavePolygonShape3D.new()
	# Build face list directly from indices/vertices (avoids
	# Mesh.get_faces() which would re-walk the surface).
	var faces: PackedVector3Array = PackedVector3Array()
	faces.resize(_indices.size())
	for i in range(_indices.size()):
		faces[i] = _vertices[_indices[i]]
	shape.set_faces(faces)
	_collision.shape = shape
	_collision_dirty = false

# Backwards-compat shim — old callers (main_bootstrap, editor _ready
# restore) use rebuild() expecting both mesh + collision in one call.
func rebuild() -> void:
	_rebuild_mesh_now()
	_rebuild_collision_now()
	_mesh_dirty = false
	_collision_dirty = false
