extends Node3D

# Play-mode road renderer. Reads MapState.roads + a terrain reference and
# extrudes the same asphalt slab the editor preview shows, minus all the
# overlay handles. Mirrors editor_roads.gd's geometry so a road authored
# in the editor renders identically in-game.

const ROAD_RAISE := 0.25
const DECAL_LIFT := 0.012
const BEZIER_STEPS := 48
const LATERAL_SUBDIV := 4  # cross-strip quads — top vert count = +1
const DEFAULT_WIDTH := 6.0
const DEFAULT_SURFACE := "asphalt"
const SURFACES := {
	"asphalt":       {"color": Color(0.12, 0.12, 0.13), "roughness": 0.85},
	"dirt_road":     {"color": Color(0.40, 0.28, 0.16), "roughness": 0.95},
	"dirt_footpath": {"color": Color(0.55, 0.42, 0.26), "roughness": 1.0},
	"gravel":        {"color": Color(0.48, 0.46, 0.42), "roughness": 0.95},
}

var _surface_mats: Dictionary = {}

func build(terrain: Node3D, roads: Array) -> void:
	for c in get_children():
		c.queue_free()
	_surface_mats.clear()
	for sid in SURFACES.keys():
		var spec: Dictionary = SURFACES[sid]
		var m := StandardMaterial3D.new()
		m.albedo_color = spec.get("color", Color(0.12, 0.12, 0.13))
		m.roughness = float(spec.get("roughness", 0.9))
		m.metallic = 0.0
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_surface_mats[sid] = m
	for r in roads:
		var nodes: Array = r.get("nodes", [])
		if nodes.size() < 2:
			continue
		var sid: String = String(r.get("surface", DEFAULT_SURFACE))
		var mat: StandardMaterial3D = _surface_mats.get(sid, _surface_mats[DEFAULT_SURFACE])
		for i in range(nodes.size() - 1):
			_spawn_strip(terrain, nodes[i], nodes[i + 1], mat)
		var decals: Array = r.get("decals", [])
		for d in decals:
			for i in range(nodes.size() - 1):
				_spawn_decal_strip(terrain, nodes[i], nodes[i + 1], d)

func _spawn_strip(terrain: Node3D, a: Dictionary, b: Dictionary, mat: StandardMaterial3D) -> void:
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
	# Vertex layout per longitudinal sample: (LATERAL_SUBDIV + 1) top verts
	# spanning the cross-section + 2 bottom corner verts (lb, rb). Each top
	# vert samples terrain at its own XZ so the strip drapes laterally over
	# cross-slopes instead of stretching a flat plane between just two edges.
	var top_count: int = LATERAL_SUBDIV + 1
	var verts_per_sample: int = top_count + 2
	for i in range(BEZIER_STEPS + 1):
		var t: float = float(i) / float(BEZIER_STEPS)
		var c: Vector3 = _cubic(p0, p1, p2, p3, t)
		var tan: Vector3 = _cubic_tan(p0, p1, p2, p3, t)
		tan.y = 0.0
		if tan.length_squared() < 0.0001:
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
		# Sample terrain at each lateral position. y_min is used to anchor
		# the bottom corner verts so the slab still looks chunky from the side.
		var top_ys: PackedFloat32Array = PackedFloat32Array()
		top_ys.resize(top_count)
		var y_min: float = INF
		for k in range(top_count):
			var u: float = float(k) / float(LATERAL_SUBDIV)
			var sxz: Vector3 = l_xz.lerp(r_xz, u)
			var sy: float = c.y
			if not ignore and terrain != null:
				sy = terrain.sample_height(sxz)
			top_ys[k] = sy
			y_min = min(y_min, sy)
		for k in range(top_count):
			var u2: float = float(k) / float(LATERAL_SUBDIV)
			var pos: Vector3 = l_xz.lerp(r_xz, u2)
			verts.append(Vector3(pos.x, top_ys[k] + ROAD_RAISE, pos.z))
			normals.append(Vector3.UP)
			uvs.append(Vector2(u2, t))
		# Bottom corners — only at the two outer edges. Side strips connect
		# the outermost top vert down to its bottom corner.
		verts.append(Vector3(l_xz.x, y_min - 0.05, l_xz.z))
		verts.append(Vector3(r_xz.x, y_min - 0.05, r_xz.z))
		normals.append(Vector3.DOWN); normals.append(Vector3.DOWN)
		uvs.append(Vector2(0.0, t)); uvs.append(Vector2(1.0, t))
	for i in range(BEZIER_STEPS):
		var ba: int = i * verts_per_sample
		var bb: int = (i + 1) * verts_per_sample
		# Top: stitch consecutive lateral verts with two triangles per quad.
		for k in range(LATERAL_SUBDIV):
			var a0: int = ba + k;     var b0: int = ba + k + 1
			var a1: int = bb + k;     var b1: int = bb + k + 1
			indices.append(a0); indices.append(a1); indices.append(b0)
			indices.append(b0); indices.append(a1); indices.append(b1)
		# Left side (top[0] down to lb).
		var lt0: int = ba
		var lb0: int = ba + top_count
		var lt1: int = bb
		var lb1: int = bb + top_count
		indices.append(lt0); indices.append(lb0); indices.append(lt1)
		indices.append(lt1); indices.append(lb0); indices.append(lb1)
		# Right side (top[LAT] down to rb).
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

func _spawn_decal_strip(terrain: Node3D, a: Dictionary, b: Dictionary, decal: Dictionary) -> void:
	# Mirror of editor_roads.gd::_spawn_decal_strip — same dash/offset/colour
	# logic so a road authored in the editor reads identically in play mode.
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
	var prev_c: Vector3 = _cubic(p0, p1, p2, p3, 0.0)
	var emit_link: bool = true
	var pair_count: int = 0
	for i in range(BEZIER_STEPS + 1):
		var t: float = float(i) / float(BEZIER_STEPS)
		var c: Vector3 = _cubic(p0, p1, p2, p3, t)
		var tan: Vector3 = _cubic_tan(p0, p1, p2, p3, t)
		tan.y = 0.0
		if tan.length_squared() < 0.0001:
			var chord_xz: Vector3 = p3 - p0
			chord_xz.y = 0.0
			if chord_xz.length_squared() < 0.0001:
				tan = Vector3(0, 0, -1)
			else:
				tan = chord_xz
		tan = tan.normalized()
		var right_v: Vector3 = tan.cross(Vector3.UP).normalized()
		var half_road: float = lerp(wa, wb, t) * 0.5
		var lateral: float = (offset_u - 0.5) * 2.0 * half_road
		var centre_xz: Vector3 = c + right_v * lateral
		var ignore: bool = a_ignore if t < 0.5 else b_ignore
		var y: float = c.y
		if not ignore and terrain != null:
			y = terrain.sample_height(centre_xz)
		var top_y: float = y + ROAD_RAISE + DECAL_LIFT
		if i > 0:
			arc_len += c.distance_to(prev_c)
		prev_c = c
		var in_dash: bool = true
		if dashed:
			var cycle: float = dash_len + gap_len
			var mod_pos: float = fposmod(arc_len, cycle)
			in_dash = mod_pos < dash_len
		if dashed and not in_dash:
			emit_link = false
			continue
		var l: Vector3 = Vector3(centre_xz.x - right_v.x * decal_half, top_y, centre_xz.z - right_v.z * decal_half)
		var r: Vector3 = Vector3(centre_xz.x + right_v.x * decal_half, top_y, centre_xz.z + right_v.z * decal_half)
		verts.append(l)
		verts.append(r)
		normals.append(Vector3.UP); normals.append(Vector3.UP)
		uvs.append(Vector2(0.0, t)); uvs.append(Vector2(1.0, t))
		if emit_link and pair_count > 0:
			var a0: int = (pair_count - 1) * 2
			var b1: int = pair_count * 2
			indices.append(a0); indices.append(b1); indices.append(a0 + 1)
			indices.append(a0 + 1); indices.append(b1); indices.append(b1 + 1)
		pair_count += 1
		emit_link = true
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
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = col
	if col.a < 1.0:
		dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = dm
	add_child(mi)

func _cubic(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var u: float = 1.0 - t
	return (u * u * u) * p0 + (3.0 * u * u * t) * p1 + (3.0 * u * t * t) * p2 + (t * t * t) * p3

func _cubic_tan(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var u: float = 1.0 - t
	return 3.0 * u * u * (p1 - p0) + 6.0 * u * t * (p2 - p1) + 3.0 * t * t * (p3 - p2)
