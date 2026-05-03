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
	rebuild()

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
	rebuild()

func lower_brush(center: Vector3, radius: float, strength: float, delta: float) -> void:
	raise_brush(center, radius, -strength, delta)

func flatten_brush(center: Vector3, radius: float, target_h: float, strength: float, delta: float) -> void:
	var rate: float = clampf(strength * delta, 0.0, 1.0)
	_stamp(center, radius, func(i, f):
		heights[i] = lerpf(heights[i], target_h, rate * f)
	)
	rebuild()

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
	rebuild()

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
	rebuild()

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

func rebuild() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Build vertex buffer + index buffer. Indices wired so each quad is
	# two CCW triangles when viewed from above (+Y).
	for y in range(GRID_H):
		for x in range(GRID_W):
			st.set_uv(Vector2(float(x) / float(GRID_W - 1), float(y) / float(GRID_H - 1)))
			st.add_vertex(Vector3(
				ORIGIN_OFFSET.x + x * VERT_SPACING,
				heights[_idx(x, y)],
				ORIGIN_OFFSET.z + y * VERT_SPACING,
			))
	for y in range(GRID_H - 1):
		for x in range(GRID_W - 1):
			var i: int = _idx(x, y)
			var i_r: int = _idx(x + 1, y)
			var i_d: int = _idx(x, y + 1)
			var i_dr: int = _idx(x + 1, y + 1)
			# CCW winding as viewed from +Y so the top face is the front face.
			st.add_index(i)
			st.add_index(i_r)
			st.add_index(i_d)
			st.add_index(i_r)
			st.add_index(i_dr)
			st.add_index(i_d)
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	mesh.surface_set_material(0, _material)
	_mesh_instance.mesh = mesh
	# Collision: rebuild from the same geometry. Cheap enough at 128².
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(mesh.get_faces())
	_collision.shape = shape
