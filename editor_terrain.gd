extends Node3D

# Editor heightmap terrain. Backing data is a flat float array
# (heights[x + y*GRID_W]) sampled at 1m vertex spacing. The mesh and
# the StaticBody collider are rebuilt whenever heights change in a
# tool stroke. Brush operations take a world-space center + radius and
# walk only the affected vertex window for speed.

const GRID_W := 256            # vertices per side (255 quads)
const GRID_H := 256
const VERT_SPACING := 1.0      # metres between vertices
const ORIGIN_OFFSET := Vector3(-128.0, 0.0, -128.0)  # world pos of vertex (0,0)

var heights: PackedFloat32Array = PackedFloat32Array()
# Per-vertex paint weights — rgba = (dirt, grass, stone, sand). Sum
# kept ~1 by the brush; shader normalises just in case.
var paint: PackedColorArray = PackedColorArray()
# Per-vertex hole mask. 0 = solid, 1 = cut. Any triangle touching a
# cut vertex is dropped from both the rendered mesh and the collider,
# so the player falls through. Repair brush flips bytes back to 0.
var holes: PackedByteArray = PackedByteArray()

# Texture palette for the 4 paint channels. Order matches paint rgba.
# Tiled in world-space xz at TILE_SIZE metres per repeat — independent of
# the terrain's 1m vertex spacing, so paint blending stays smooth.
const PAINT_TEX_PATHS: Array = [
	"res://assets/textures/ground/ground_dirt.png",
	"res://assets/textures/ground/ground_grass.png",
	"res://assets/textures/ground/ground_stone.png",
	"res://assets/textures/ground/ground_sand.png",
]
const TILE_SIZE: float = 2.0

const PAINT_SHADER_CODE := """
shader_type spatial;
render_mode cull_back;
uniform sampler2D tex_dirt  : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_grass : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_stone : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_sand  : source_color, filter_linear_mipmap, repeat_enable;
uniform float tile_size = 2.0;
varying vec2 world_uv;
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_uv = wp.xz / tile_size;
}
void fragment() {
	vec4 w = COLOR;
	float s = max(0.001, w.r + w.g + w.b + w.a);
	w /= s;
	vec3 c =
		texture(tex_dirt,  world_uv).rgb * w.r +
		texture(tex_grass, world_uv).rgb * w.g +
		texture(tex_stone, world_uv).rgb * w.b +
		texture(tex_sand,  world_uv).rgb * w.a;
	ALBEDO = c;
	ROUGHNESS = 0.9;
}
"""

var _mesh_instance: MeshInstance3D
var _body: StaticBody3D
var _collision: CollisionShape3D
var _material: ShaderMaterial
# Pre-built static index buffer (vertex order is fixed; only positions
# move). Allocating it once kills the worst per-stroke cost.
var _indices: PackedInt32Array = PackedInt32Array()
var _uvs: PackedVector2Array = PackedVector2Array()
var _vertices: PackedVector3Array = PackedVector3Array()
var _normals: PackedVector3Array = PackedVector3Array()
var _colors: PackedColorArray = PackedColorArray()
var _array_mesh: ArrayMesh = null
# Filtered index buffer that drops triangles touching a hole vertex.
# Rebuilt only when `holes` changes; mesh + collider both consume this
# instead of the raw _indices buffer.
var _active_indices: PackedInt32Array = PackedInt32Array()
var _holes_dirty: bool = true
# Coalesced rebuild flags. Brush calls just mark these — actual mesh
# work happens in _process at most once per frame, and collision
# rebuild waits until end_stroke() is called. _dirty_min/_max bound
# the touched vertex window so the rebuild only walks the affected
# slice, not the whole 16k-vert grid.
var _mesh_dirty: bool = false
var _collision_dirty: bool = false
var _dirty_min: Vector2i = Vector2i.ZERO
var _dirty_max: Vector2i = Vector2i.ZERO
var _has_dirty_rect: bool = false

func _ready() -> void:
	heights.resize(GRID_W * GRID_H)
	for i in heights.size():
		heights[i] = 0.0
	paint.resize(GRID_W * GRID_H)
	for i in paint.size():
		paint[i] = Color(0.0, 1.0, 0.0, 0.0)  # default to full grass
	holes.resize(GRID_W * GRID_H)
	for i in holes.size():
		holes[i] = 0
	var sh := Shader.new()
	sh.code = PAINT_SHADER_CODE
	_material = ShaderMaterial.new()
	_material.shader = sh
	# Runtime-load via Image — source-pull launcher pulls the repo as plain
	# files, so .png.import sidecars aren't present and load() returns null.
	# Image.load + ImageTexture.create_from_image skips Godot's import step.
	_material.set_shader_parameter("tex_dirt",  _load_runtime_texture(PAINT_TEX_PATHS[0]))
	_material.set_shader_parameter("tex_grass", _load_runtime_texture(PAINT_TEX_PATHS[1]))
	_material.set_shader_parameter("tex_stone", _load_runtime_texture(PAINT_TEX_PATHS[2]))
	_material.set_shader_parameter("tex_sand",  _load_runtime_texture(PAINT_TEX_PATHS[3]))
	_material.set_shader_parameter("tile_size", TILE_SIZE)
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

func _load_runtime_texture(res_path: String) -> ImageTexture:
	var fs_path := ProjectSettings.globalize_path(res_path)
	var img := Image.new()
	var err := img.load(fs_path)
	if err != OK:
		push_warning("ground texture load failed: %s (err %d)" % [res_path, err])
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

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
	_colors.resize(GRID_W * GRID_H)
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

func raise_brush(center: Vector3, radius: float, strength: float, delta: float) -> void:
	# Inlined window walk + smoothstep falloff. Lambda dispatch was a
	# real per-vertex cost in GDScript, so brush ops write heights
	# directly here.
	var amount: float = strength * delta
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
			f = f * f * (3.0 - 2.0 * f)
			heights[x + y * GRID_W] += amount * f
	_mark_region_dirty(x0, y0, x1, y1)

func lower_brush(center: Vector3, radius: float, strength: float, delta: float) -> void:
	raise_brush(center, radius, -strength, delta)

func flatten_brush(center: Vector3, radius: float, target_h: float, strength: float, delta: float) -> void:
	var rate: float = clampf(strength * delta, 0.0, 1.0)
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
			f = f * f * (3.0 - 2.0 * f)
			var i: int = x + y * GRID_W
			heights[i] = lerpf(heights[i], target_h, rate * f)
	_mark_region_dirty(x0, y0, x1, y1)

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
	_mark_region_dirty(x0, y0, x1, y1)

# Paint per-vertex material weights. `mat_id` ∈ [0..3] picks an rgba
# channel; the brush pushes that channel toward 1.0 by (strength*delta*falloff)
# and scales the remaining channels down so the four weights still sum to 1.
# `shape` is "circle" or "square" — square uses a Chebyshev distance so the
# brush footprint is a flat box of side 2*radius.
func paint_brush(center: Vector3, radius: float, strength: float, delta: float, mat_id: int, shape: String) -> void:
	if mat_id < 0 or mat_id > 3:
		return
	var rate: float = clampf(strength * delta, 0.0, 1.0)
	if rate <= 0.0:
		return
	var g := world_to_grid(center)
	var rg: float = radius / VERT_SPACING
	var x0: int = max(0, int(floor(g.x - rg)))
	var x1: int = min(GRID_W - 1, int(ceil(g.x + rg)))
	var y0: int = max(0, int(floor(g.y - rg)))
	var y1: int = min(GRID_H - 1, int(ceil(g.y + rg)))
	var is_square: bool = shape == "square"
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx: float = float(x) - g.x
			var dy: float = float(y) - g.y
			var f: float
			if is_square:
				var dm: float = max(absf(dx), absf(dy))
				if dm > rg:
					continue
				f = 1.0 - (dm / rg)
			else:
				var d: float = sqrt(dx * dx + dy * dy)
				if d > rg:
					continue
				f = 1.0 - (d / rg)
			f = f * f * (3.0 - 2.0 * f)
			var i: int = _idx(x, y)
			var c: Color = paint[i]
			var old_t: float = c[mat_id]
			var new_t: float = lerpf(old_t, 1.0, rate * f)
			var rem_old: float = 1.0 - old_t
			var rem_new: float = 1.0 - new_t
			var scale_others: float = (rem_new / rem_old) if rem_old > 0.0001 else 0.0
			for ch in range(4):
				if ch == mat_id:
					c[ch] = new_t
				else:
					c[ch] = c[ch] * scale_others
			paint[i] = c
	# Painting doesn't touch heights → collision is unchanged. Only mark the
	# mesh dirty so colors get re-uploaded; skip collider rebuild.
	_mark_paint_dirty(x0, y0, x1, y1)

# Smooth each affected vertex's paint weights toward the local average
# of its 8 neighbours, weighted by brush falloff. Used by the Materials
# tool's blend mode to soften hard paint boundaries.
func mat_smooth_brush(center: Vector3, radius: float, strength: float, delta: float, shape: String) -> void:
	var rate: float = clampf(strength * delta, 0.0, 1.0)
	if rate <= 0.0:
		return
	var g := world_to_grid(center)
	var rg: float = radius / VERT_SPACING
	var x0: int = max(1, int(floor(g.x - rg)))
	var x1: int = min(GRID_W - 2, int(ceil(g.x + rg)))
	var y0: int = max(1, int(floor(g.y - rg)))
	var y1: int = min(GRID_H - 2, int(ceil(g.y + rg)))
	var is_square: bool = shape == "square"
	var src := paint.duplicate()
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx: float = float(x) - g.x
			var dy: float = float(y) - g.y
			var f: float
			if is_square:
				var dm: float = max(absf(dx), absf(dy))
				if dm > rg:
					continue
				f = 1.0 - (dm / rg)
			else:
				var d: float = sqrt(dx * dx + dy * dy)
				if d > rg:
					continue
				f = 1.0 - (d / rg)
			f = f * f * (3.0 - 2.0 * f)
			var avg := Color(0, 0, 0, 0)
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					avg += src[_idx(x + ox, y + oy)]
			avg /= 9.0
			var i: int = _idx(x, y)
			paint[i] = src[i].lerp(avg, rate * f)
	_mark_paint_dirty(x0, y0, x1, y1)

# Per-vertex hole brush. `value` is 1 to cut, 0 to repair. Triangles
# touching any cut vertex are skipped during the next mesh + collider
# rebuild, so the player falls through. Hole edits dirty BOTH mesh and
# collider — a hole stroke needs a collider rebuild on release.
func hole_brush(center: Vector3, radius: float, shape: String, value: int) -> void:
	var g := world_to_grid(center)
	var rg: float = radius / VERT_SPACING
	var x0: int = max(0, int(floor(g.x - rg)))
	var x1: int = min(GRID_W - 1, int(ceil(g.x + rg)))
	var y0: int = max(0, int(floor(g.y - rg)))
	var y1: int = min(GRID_H - 1, int(ceil(g.y + rg)))
	var v: int = clampi(value, 0, 1)
	var is_square: bool = shape == "square"
	var changed: bool = false
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx: float = float(x) - g.x
			var dy: float = float(y) - g.y
			var inside: bool
			if is_square:
				inside = max(absf(dx), absf(dy)) <= rg
			else:
				inside = (dx * dx + dy * dy) <= rg * rg
			if not inside:
				continue
			var i: int = _idx(x, y)
			if holes[i] != v:
				holes[i] = v
				changed = true
	if changed:
		_holes_dirty = true
		_mark_region_dirty(x0, y0, x1, y1)

func _mark_paint_dirty(x0: int, y0: int, x1: int, y1: int) -> void:
	if not _has_dirty_rect:
		_dirty_min = Vector2i(x0, y0)
		_dirty_max = Vector2i(x1, y1)
		_has_dirty_rect = true
	else:
		_dirty_min.x = min(_dirty_min.x, x0)
		_dirty_min.y = min(_dirty_min.y, y0)
		_dirty_max.x = max(_dirty_max.x, x1)
		_dirty_max.y = max(_dirty_max.y, y1)
	_mesh_dirty = true

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
	_mark_region_dirty(sx, sy, ex, ey)

# March a ray against the *live* heightmap (not the collider, which
# only updates on stroke release). Returns the world-space hit point
# or Vector3.INF on miss. Used by the editor's cursor pick so brush
# tools track the freshly-modified surface frame-by-frame instead of
# riding the stale ConcavePolygon.
func ray_pick(from: Vector3, dir: Vector3, max_dist: float = 500.0) -> Vector3:
	var d: Vector3 = dir.normalized()
	if absf(d.length()) < 0.001:
		return Vector3.INF
	# Skip ahead to the first time the ray crosses into the terrain
	# AABB on Y so we don't waste steps in empty sky.
	var step: float = 0.4
	var t: float = 0.0
	var p: Vector3 = from
	var prev_dy: float = p.y - sample_height(p)
	while t < max_dist:
		t += step
		p = from + d * t
		# Out of grid bounds — keep marching but treat as "no surface here".
		var g := world_to_grid(p)
		if g.x < 0.0 or g.x > float(GRID_W - 1) or g.y < 0.0 or g.y > float(GRID_H - 1):
			prev_dy = 1.0
			continue
		var th: float = sample_height(p)
		var dy: float = p.y - th
		if dy <= 0.0 and prev_dy > 0.0:
			# Crossed surface — refine via linear interp between the
			# previous and current step.
			var frac: float = prev_dy / (prev_dy - dy)
			var hit_t: float = (t - step) + step * frac
			var hit_p: Vector3 = from + d * hit_t
			hit_p.y = sample_height(hit_p)
			return hit_p
		prev_dy = dy
	return Vector3.INF

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

# Sample the dominant paint channel at a world position. Returns the rgba
# index that wins after bilinearly blending the four surrounding paint
# weights — 0=dirt, 1=grass, 2=stone, 3=sand. Out-of-bounds samples fall
# back to grass (the editor's default fill).
func sample_material(world_pos: Vector3) -> int:
	var g := world_to_grid(world_pos)
	if g.x < 0.0 or g.y < 0.0 or g.x > float(GRID_W - 1) or g.y > float(GRID_H - 1):
		return 1
	var x0: int = clampi(int(floor(g.x)), 0, GRID_W - 2)
	var y0: int = clampi(int(floor(g.y)), 0, GRID_H - 2)
	var fx: float = clampf(g.x - x0, 0.0, 1.0)
	var fy: float = clampf(g.y - y0, 0.0, 1.0)
	var c00: Color = paint[_idx(x0,     y0)]
	var c10: Color = paint[_idx(x0 + 1, y0)]
	var c01: Color = paint[_idx(x0,     y0 + 1)]
	var c11: Color = paint[_idx(x0 + 1, y0 + 1)]
	var cx0: Color = c00.lerp(c10, fx)
	var cx1: Color = c01.lerp(c11, fx)
	var c: Color = cx0.lerp(cx1, fy)
	var w: Array = [c.r, c.g, c.b, c.a]
	var best: int = 0
	var best_v: float = w[0]
	for i in range(1, 4):
		if w[i] > best_v:
			best_v = w[i]
			best = i
	return best

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
	# Whole-grid dirty (used by rebuild() shim after a full restore).
	_dirty_min = Vector2i.ZERO
	_dirty_max = Vector2i(GRID_W - 1, GRID_H - 1)
	_has_dirty_rect = true
	_mesh_dirty = true
	_collision_dirty = true

func _mark_region_dirty(x0: int, y0: int, x1: int, y1: int) -> void:
	if not _has_dirty_rect:
		_dirty_min = Vector2i(x0, y0)
		_dirty_max = Vector2i(x1, y1)
		_has_dirty_rect = true
	else:
		_dirty_min.x = min(_dirty_min.x, x0)
		_dirty_min.y = min(_dirty_min.y, y0)
		_dirty_max.x = max(_dirty_max.x, x1)
		_dirty_max.y = max(_dirty_max.y, y1)
	_mesh_dirty = true
	_collision_dirty = true

func _rebuild_mesh_now() -> void:
	# Walk only the touched window. Normals need a 1-vert padding ring
	# because they sample cardinal neighbours.
	var x0: int = 0
	var y0: int = 0
	var x1: int = GRID_W - 1
	var y1: int = GRID_H - 1
	if _has_dirty_rect:
		x0 = max(0, _dirty_min.x)
		y0 = max(0, _dirty_min.y)
		x1 = min(GRID_W - 1, _dirty_max.x)
		y1 = min(GRID_H - 1, _dirty_max.y)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_vertices[x + y * GRID_W] = Vector3(
				ORIGIN_OFFSET.x + x * VERT_SPACING,
				heights[x + y * GRID_W],
				ORIGIN_OFFSET.z + y * VERT_SPACING,
			)
	var nx0: int = max(0, x0 - 1)
	var ny0: int = max(0, y0 - 1)
	var nx1: int = min(GRID_W - 1, x1 + 1)
	var ny1: int = min(GRID_H - 1, y1 + 1)
	for y in range(ny0, ny1 + 1):
		for x in range(nx0, nx1 + 1):
			var hl: float = heights[max(0, x - 1) + y * GRID_W]
			var hr: float = heights[min(GRID_W - 1, x + 1) + y * GRID_W]
			var hd: float = heights[x + max(0, y - 1) * GRID_W]
			var hu: float = heights[x + min(GRID_H - 1, y + 1) * GRID_W]
			_normals[x + y * GRID_W] = Vector3(hl - hr, 2.0 * VERT_SPACING, hd - hu).normalized()
	for i in range(paint.size()):
		_colors[i] = paint[i]
	if _holes_dirty:
		_rebuild_active_indices()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_COLOR]  = _colors
	arrays[Mesh.ARRAY_INDEX]  = _active_indices
	_array_mesh.clear_surfaces()
	if _active_indices.size() > 0:
		_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_array_mesh.surface_set_material(0, _material)
	_has_dirty_rect = false

func _rebuild_active_indices() -> void:
	# Walk the static index buffer in triplets; drop any triangle that
	# uses a hole vertex. Cheap full-grid pass (~150k tris) — runs only
	# on hole edits, not every brush stroke.
	var has_any_holes: bool = false
	for h in holes:
		if h != 0:
			has_any_holes = true
			break
	if not has_any_holes:
		_active_indices = _indices
		_holes_dirty = false
		return
	var out: PackedInt32Array = PackedInt32Array()
	out.resize(_indices.size())
	var w: int = 0
	for t in range(0, _indices.size(), 3):
		var a: int = _indices[t]
		var b: int = _indices[t + 1]
		var c: int = _indices[t + 2]
		if holes[a] != 0 or holes[b] != 0 or holes[c] != 0:
			continue
		out[w]     = a
		out[w + 1] = b
		out[w + 2] = c
		w += 3
	out.resize(w)
	_active_indices = out
	_holes_dirty = false

func _rebuild_collision_now() -> void:
	if _holes_dirty:
		_rebuild_active_indices()
	var shape := ConcavePolygonShape3D.new()
	# Build face list directly from the hole-filtered index buffer so
	# player physics matches the rendered mesh — no invisible floor over
	# a cut hole.
	var faces: PackedVector3Array = PackedVector3Array()
	faces.resize(_active_indices.size())
	for i in range(_active_indices.size()):
		faces[i] = _vertices[_active_indices[i]]
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
