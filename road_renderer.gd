extends Node3D

# Play-mode road renderer. Reads MapState.roads + a terrain reference and
# extrudes the same asphalt slab the editor preview shows, minus all the
# overlay handles. Mirrors editor_roads.gd's geometry so a road authored
# in the editor renders identically in-game.

const ROAD_RAISE := 0.25
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
			tan = Vector3(0, 0, -1)
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

func _cubic(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var u: float = 1.0 - t
	return (u * u * u) * p0 + (3.0 * u * u * t) * p1 + (3.0 * u * t * t) * p2 + (t * t * t) * p3

func _cubic_tan(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var u: float = 1.0 - t
	return 3.0 * u * u * (p1 - p0) + 6.0 * u * t * (p2 - p1) + 3.0 * t * t * (p3 - p2)
