extends Node3D

# Visual ring laid on the terrain surface to show where the brush will
# act. Built from line segments — re-projected to the terrain height
# every frame via sample_height so it hugs hills.

const SEGMENTS := 48

var radius := 4.0
var terrain: Node = null
var color := Color(1.0, 0.9, 0.2, 1.0)
var shape: String = "circle"  # "circle" or "square"
# Optional concentric inner ring. inner_ratio in (0,1] = fraction of
# outer radius; 0 disables. inner_color lets callers re-tint it (e.g.
# red when Shift-erase is active). Inner ring is always a circle so it
# stays visually distinct from a square outer.
var inner_ratio: float = 0.0
var inner_color: Color = Color(1.0, 0.4, 0.3, 1.0)

var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D
var _inner_material: StandardMaterial3D
# When set (mode_flat = true), the ring renders as a flat circle at
# fixed world y instead of hugging the terrain surface. Used for the
# flatten target preview.
var _mode_flat: bool = false
var _flat_y: float = 0.0
# When true, _rebuild also draws a small "+" mark at every terrain
# vertex inside the brush footprint. Used by the Materials tools so
# the user can see which verts will get touched by paint / smooth /
# hole strokes. Requires terrain to expose VERT_SPACING + heights.
var _show_vert_dots: bool = false
var _vert_dot_color: Color = Color(0.2, 1.0, 0.5, 1.0)

func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = color
	_material.no_depth_test = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_inner_material = StandardMaterial3D.new()
	_inner_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_inner_material.albedo_color = inner_color
	_inner_material.no_depth_test = true
	_inner_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)

func set_radius(r: float) -> void:
	radius = max(0.25, r)

func set_shape(s: String) -> void:
	shape = s

func set_color(c: Color) -> void:
	color = c
	if _material != null:
		_material.albedo_color = c

func set_vert_dots(enabled: bool, c: Color = Color(0, 0, 0, 0)) -> void:
	_show_vert_dots = enabled
	if c.a > 0.0:
		_vert_dot_color = c

func set_inner(ratio: float, c: Color = Color(0, 0, 0, 0)) -> void:
	inner_ratio = clamp(ratio, 0.0, 1.0)
	if c.a > 0.0:
		inner_color = c
		if _inner_material != null:
			_inner_material.albedo_color = c

func place(center: Vector3) -> void:
	visible = true
	_mode_flat = false
	global_position = Vector3(center.x, 0.0, center.z)
	_rebuild()

func place_flat(center: Vector3, y: float) -> void:
	visible = true
	_mode_flat = true
	_flat_y = y
	global_position = Vector3(center.x, 0.0, center.z)
	_rebuild()

func hide_ring() -> void:
	visible = false

func _rebuild() -> void:
	if not _mode_flat and terrain == null:
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, _material)
	# Sampling 4*N points around the square's perimeter keeps the outline
	# hugging the terrain at the same resolution as the circle path.
	var segs: int = SEGMENTS
	for i in range(segs):
		var p0: Vector3
		var p1: Vector3
		if shape == "square":
			p0 = _square_point(i, segs)
			p1 = _square_point(i + 1, segs)
		else:
			var a0: float = (float(i)     / float(segs)) * TAU
			var a1: float = (float(i + 1) / float(segs)) * TAU
			p0 = Vector3(cos(a0) * radius, 0.0, sin(a0) * radius)
			p1 = Vector3(cos(a1) * radius, 0.0, sin(a1) * radius)
		if _mode_flat:
			p0.y = _flat_y - global_position.y
			p1.y = _flat_y - global_position.y
		else:
			p0.y = terrain.sample_height(global_position + p0) - global_position.y + 0.05
			p1.y = terrain.sample_height(global_position + p1) - global_position.y + 0.05
		im.surface_add_vertex(p0)
		im.surface_add_vertex(p1)
	im.surface_end()
	if inner_ratio > 0.001:
		var ir: float = radius * inner_ratio
		im.surface_begin(Mesh.PRIMITIVE_LINES, _inner_material)
		for j in range(segs):
			var a0: float = (float(j)     / float(segs)) * TAU
			var a1: float = (float(j + 1) / float(segs)) * TAU
			var ip0 := Vector3(cos(a0) * ir, 0.0, sin(a0) * ir)
			var ip1 := Vector3(cos(a1) * ir, 0.0, sin(a1) * ir)
			if _mode_flat:
				ip0.y = _flat_y - global_position.y
				ip1.y = _flat_y - global_position.y
			else:
				ip0.y = terrain.sample_height(global_position + ip0) - global_position.y + 0.05
				ip1.y = terrain.sample_height(global_position + ip1) - global_position.y + 0.05
			im.surface_add_vertex(ip0)
			im.surface_add_vertex(ip1)
		im.surface_end()
	# Vertex-dot preview: small "+" mark at every terrain grid vertex
	# inside the brush footprint, projected to the surface. Lets the user
	# see exactly which verts a paint / smooth / hole stroke will touch.
	if _show_vert_dots and not _mode_flat and terrain != null and "VERT_SPACING" in terrain:
		var vs: float = float(terrain.VERT_SPACING)
		var rg: int = int(ceil(radius / vs)) + 1
		var cgx: int = int(round((global_position.x - terrain.global_position.x - terrain.ORIGIN_OFFSET.x) / vs))
		var cgy: int = int(round((global_position.z - terrain.global_position.z - terrain.ORIGIN_OFFSET.z) / vs))
		var dot_mat := StandardMaterial3D.new()
		dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dot_mat.albedo_color = _vert_dot_color
		dot_mat.no_depth_test = true
		dot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		im.surface_begin(Mesh.PRIMITIVE_LINES, dot_mat)
		var mark: float = 0.12
		var r2: float = radius * radius
		var is_square: bool = (shape == "square")
		for dyi in range(-rg, rg + 1):
			for dxi in range(-rg, rg + 1):
				var wx: float = float(dxi) * vs
				var wz: float = float(dyi) * vs
				var inside: bool
				if is_square:
					inside = absf(wx) <= radius and absf(wz) <= radius
				else:
					inside = (wx * wx + wz * wz) <= r2
				if not inside:
					continue
				var world_pos := global_position + Vector3(wx, 0.0, wz)
				var y: float = terrain.sample_height(world_pos) - global_position.y + 0.06
				im.surface_add_vertex(Vector3(wx - mark, y, wz))
				im.surface_add_vertex(Vector3(wx + mark, y, wz))
				im.surface_add_vertex(Vector3(wx, y, wz - mark))
				im.surface_add_vertex(Vector3(wx, y, wz + mark))
		im.surface_end()
	_mesh_instance.mesh = im

func _square_point(i: int, segs: int) -> Vector3:
	# Walk perimeter of an axis-aligned square of side 2*radius. Each edge
	# gets segs/4 samples so the corners are sharp.
	var per_side: int = max(1, segs / 4)
	var side: int = (i / per_side) % 4
	var t: float = float(i % per_side) / float(per_side)
	var s: float = radius
	match side:
		0: return Vector3(-s + 2.0 * s * t, 0.0, -s)
		1: return Vector3( s, 0.0, -s + 2.0 * s * t)
		2: return Vector3( s - 2.0 * s * t, 0.0,  s)
		_: return Vector3(-s, 0.0,  s - 2.0 * s * t)
