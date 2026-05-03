extends Node3D

# Transform gizmo for the currently-selected editor object. Renders
# handles (axis arrows / plane drag quads / ring rotators / scale boxes)
# in immediate-mode lines, and exposes hit-test helpers so the editor
# script can pick a handle under the cursor and run the corresponding
# drag.
#
# The editor swaps the gizmo between modes via set_mode(). Phase 3 ships
# the translate modes only — rotate/scale land in later phases but their
# slots are reserved.

const MODE_NONE := 0
const MODE_TRANSLATE_AXES := 1
const MODE_TRANSLATE_6 := 2
const MODE_ROTATE := 3
const MODE_SCALE := 4

const HANDLE_ROT_X := "rx"
const HANDLE_ROT_Y := "ry"
const HANDLE_ROT_Z := "rz"
const HANDLE_SCALE_X := "sx"
const HANDLE_SCALE_Y := "sy"
const HANDLE_SCALE_Z := "sz"

const RING_RADIUS := 1.6
const RING_THICKNESS := 0.18
const RING_SEGMENTS := 48
const SCALE_LEN := 1.4
const SCALE_BOX := 0.18

const HANDLE_NONE := ""
const HANDLE_X := "x"
const HANDLE_Y := "y"
const HANDLE_Z := "z"
const HANDLE_NEG_X := "-x"
const HANDLE_NEG_Y := "-y"
const HANDLE_NEG_Z := "-z"
const HANDLE_PLANE_XY := "pxy"
const HANDLE_PLANE_YZ := "pyz"
const HANDLE_PLANE_XZ := "pxz"

const COLOR_X := Color(1.0, 0.3, 0.3, 1.0)
const COLOR_Y := Color(0.4, 1.0, 0.45, 1.0)
const COLOR_Z := Color(0.35, 0.6, 1.0, 1.0)
const COLOR_HOVER := Color(1.0, 0.95, 0.35, 1.0)

const ARROW_LEN := 1.6
const ARROW_HEAD := 0.22
const PLANE_SIZE := 0.5     # square edge length — extends from origin out
                            # along each axis so two edges sit ON the
                            # corresponding axis arrows.
const PLANE_PICK_INSET := 0.08  # shrink pick area slightly so clicks ON
                                # an axis line still register as axis hits
                                # rather than getting eaten by the plane.
const HIT_RADIUS := 0.18    # axis pick distance threshold

var mode: int = MODE_NONE
var use_local: bool = false
var target: Node3D = null
var hover_handle: String = HANDLE_NONE

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D

func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.no_depth_test = true
	_mat.vertex_color_use_as_albedo = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh = MeshInstance3D.new()
	add_child(_mesh)
	visible = false

func set_target(t: Node3D) -> void:
	target = t
	if t == null:
		mode = MODE_NONE
		visible = false

func set_mode(m: int) -> void:
	mode = m
	visible = (mode != MODE_NONE) and target != null

func cycle_translate() -> void:
	# Off / non-translate → axes; axes ↔ 6-arrow toggle.
	if mode == MODE_TRANSLATE_AXES:
		set_mode(MODE_TRANSLATE_6)
	else:
		set_mode(MODE_TRANSLATE_AXES)

func set_use_local(v: bool) -> void:
	use_local = v

func _process(_delta: float) -> void:
	if target == null or mode == MODE_NONE:
		visible = false
		return
	if not is_instance_valid(target):
		target = null
		visible = false
		return
	visible = true
	global_position = target.global_position
	if use_local:
		global_transform.basis = target.global_transform.basis.orthonormalized()
	else:
		global_transform.basis = Basis()
	_rebuild()

func _rebuild() -> void:
	var im := ImmediateMesh.new()
	if mode == MODE_TRANSLATE_AXES:
		_axis_arrow(im, Vector3.RIGHT, COLOR_X, HANDLE_X)
		_axis_arrow(im, Vector3.UP, COLOR_Y, HANDLE_Y)
		_axis_arrow(im, Vector3.BACK, COLOR_Z, HANDLE_Z)
		_plane_quad(im, Vector3.RIGHT, Vector3.UP, COLOR_Z, HANDLE_PLANE_XY)
		_plane_quad(im, Vector3.UP, Vector3.BACK, COLOR_X, HANDLE_PLANE_YZ)
		_plane_quad(im, Vector3.RIGHT, Vector3.BACK, COLOR_Y, HANDLE_PLANE_XZ)
	elif mode == MODE_TRANSLATE_6:
		_axis_arrow(im, Vector3.RIGHT, COLOR_X, HANDLE_X)
		_axis_arrow(im, Vector3.LEFT, COLOR_X, HANDLE_NEG_X)
		_axis_arrow(im, Vector3.UP, COLOR_Y, HANDLE_Y)
		_axis_arrow(im, Vector3.DOWN, COLOR_Y, HANDLE_NEG_Y)
		_axis_arrow(im, Vector3.BACK, COLOR_Z, HANDLE_Z)
		_axis_arrow(im, Vector3.FORWARD, COLOR_Z, HANDLE_NEG_Z)
	elif mode == MODE_ROTATE:
		_ring(im, Vector3.RIGHT, Vector3.UP, Vector3.BACK, COLOR_X, HANDLE_ROT_X)
		_ring(im, Vector3.UP, Vector3.RIGHT, Vector3.BACK, COLOR_Y, HANDLE_ROT_Y)
		_ring(im, Vector3.BACK, Vector3.RIGHT, Vector3.UP, COLOR_Z, HANDLE_ROT_Z)
	elif mode == MODE_SCALE:
		_scale_handle(im, Vector3.RIGHT, COLOR_X, HANDLE_SCALE_X)
		_scale_handle(im, Vector3.UP, COLOR_Y, HANDLE_SCALE_Y)
		_scale_handle(im, Vector3.BACK, COLOR_Z, HANDLE_SCALE_Z)
	_mesh.mesh = im

func _axis_arrow(im: ImmediateMesh, dir: Vector3, color: Color, handle_id: String) -> void:
	var c: Color = COLOR_HOVER if handle_id == hover_handle else color
	var tip: Vector3 = dir * ARROW_LEN
	im.surface_begin(Mesh.PRIMITIVE_LINES, _mat)
	im.surface_set_color(c)
	im.surface_add_vertex(Vector3.ZERO)
	im.surface_add_vertex(tip)
	im.surface_end()
	# Arrow head — 4-segment fan around the tip.
	var perp1: Vector3 = dir.cross(Vector3.UP)
	if perp1.length() < 0.001:
		perp1 = dir.cross(Vector3.RIGHT)
	perp1 = perp1.normalized()
	var perp2: Vector3 = dir.cross(perp1).normalized()
	var base: Vector3 = tip - dir * ARROW_HEAD
	im.surface_begin(Mesh.PRIMITIVE_LINES, _mat)
	im.surface_set_color(c)
	for k in range(8):
		var ang: float = (float(k) / 8.0) * TAU
		var p: Vector3 = base + (perp1 * cos(ang) + perp2 * sin(ang)) * (ARROW_HEAD * 0.55)
		im.surface_add_vertex(tip)
		im.surface_add_vertex(p)
	im.surface_end()

func _ring(im: ImmediateMesh, axis: Vector3, u: Vector3, v: Vector3, color: Color, handle_id: String) -> void:
	# Circle in the plane spanned by (u, v), perpendicular to axis.
	var c: Color = COLOR_HOVER if handle_id == hover_handle else color
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _mat)
	im.surface_set_color(c)
	for k in range(RING_SEGMENTS + 1):
		var ang: float = (float(k) / float(RING_SEGMENTS)) * TAU
		var p: Vector3 = (u * cos(ang) + v * sin(ang)) * RING_RADIUS
		im.surface_add_vertex(p)
	im.surface_end()

func _scale_handle(im: ImmediateMesh, dir: Vector3, color: Color, handle_id: String) -> void:
	var c: Color = COLOR_HOVER if handle_id == hover_handle else color
	var tip: Vector3 = dir * SCALE_LEN
	im.surface_begin(Mesh.PRIMITIVE_LINES, _mat)
	im.surface_set_color(c)
	im.surface_add_vertex(Vector3.ZERO)
	im.surface_add_vertex(tip)
	im.surface_end()
	# Cube endcap — 12 line segments.
	var perp1: Vector3 = dir.cross(Vector3.UP)
	if perp1.length() < 0.001:
		perp1 = dir.cross(Vector3.RIGHT)
	perp1 = perp1.normalized()
	var perp2: Vector3 = dir.cross(perp1).normalized()
	var hb: float = SCALE_BOX * 0.5
	var corners: Array = []
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			for sz in [-1, 1]:
				corners.append(tip + dir * (hb * sz) + perp1 * (hb * sx) + perp2 * (hb * sy))
	var edges: Array = [
		[0,1],[2,3],[4,5],[6,7],
		[0,2],[1,3],[4,6],[5,7],
		[0,4],[1,5],[2,6],[3,7],
	]
	im.surface_begin(Mesh.PRIMITIVE_LINES, _mat)
	im.surface_set_color(c)
	for e in edges:
		im.surface_add_vertex(corners[e[0]])
		im.surface_add_vertex(corners[e[1]])
	im.surface_end()

func _plane_quad(im: ImmediateMesh, a: Vector3, b: Vector3, color: Color, handle_id: String) -> void:
	# Quad with corner at origin, extending PLANE_SIZE along each of (a, b).
	# This puts two edges of the quad directly on the corresponding axis
	# arrows so the plane handle visually touches them.
	var c: Color = COLOR_HOVER if handle_id == hover_handle else color
	c.a = 0.85
	var v0: Vector3 = Vector3.ZERO
	var v1: Vector3 = a * PLANE_SIZE
	var v2: Vector3 = a * PLANE_SIZE + b * PLANE_SIZE
	var v3: Vector3 = b * PLANE_SIZE
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _mat)
	im.surface_set_color(c)
	im.surface_add_vertex(v0)
	im.surface_add_vertex(v1)
	im.surface_add_vertex(v2)
	im.surface_add_vertex(v3)
	im.surface_add_vertex(v0)
	im.surface_end()

# Pick a handle under the mouse ray. Returns ("", info) if no hit.
# Info dict carries the world-space axis or plane-normal so the editor
# can drive the drag without re-deriving them.
func pick_handle(from: Vector3, dir: Vector3) -> Dictionary:
	if mode == MODE_NONE or target == null:
		return {"handle": HANDLE_NONE}
	var b: Basis = global_transform.basis
	var origin: Vector3 = global_position
	var best_handle: String = HANDLE_NONE
	var best_t: float = INF
	var best_axis: Vector3 = Vector3.ZERO
	var best_normal: Vector3 = Vector3.ZERO
	var axis_specs: Array = []
	if mode == MODE_TRANSLATE_AXES:
		axis_specs = [
			[HANDLE_X, b.x, ARROW_LEN],
			[HANDLE_Y, b.y, ARROW_LEN],
			[HANDLE_Z, b.z, ARROW_LEN],
		]
	elif mode == MODE_TRANSLATE_6:
		axis_specs = [
			[HANDLE_X,     b.x,  ARROW_LEN],
			[HANDLE_NEG_X, -b.x, ARROW_LEN],
			[HANDLE_Y,     b.y,  ARROW_LEN],
			[HANDLE_NEG_Y, -b.y, ARROW_LEN],
			[HANDLE_Z,     b.z,  ARROW_LEN],
			[HANDLE_NEG_Z, -b.z, ARROW_LEN],
		]
	elif mode == MODE_SCALE:
		axis_specs = [
			[HANDLE_SCALE_X, b.x, SCALE_LEN],
			[HANDLE_SCALE_Y, b.y, SCALE_LEN],
			[HANDLE_SCALE_Z, b.z, SCALE_LEN],
		]
	for spec in axis_specs:
		var name: String = spec[0]
		var ax: Vector3 = spec[1].normalized()
		var len: float = spec[2]
		var t: float = _ray_segment_dist(from, dir, origin, origin + ax * len)
		if t >= 0.0 and t < best_t:
			best_t = t
			best_handle = name
			best_axis = ax
	# Plane drag handles (only in axes-mode).
	if mode == MODE_TRANSLATE_AXES:
		var planes: Array = [
			[HANDLE_PLANE_XY, b.z, b.x, b.y],
			[HANDLE_PLANE_YZ, b.x, b.y, b.z],
			[HANDLE_PLANE_XZ, b.y, b.x, b.z],
		]
		for p in planes:
			var name2: String = p[0]
			var n: Vector3 = p[1].normalized()
			var u: Vector3 = p[2].normalized()
			var v: Vector3 = p[3].normalized()
			var hit: Dictionary = _ray_plane_hit(from, dir, origin, n)
			if hit.is_empty():
				continue
			var pt: Vector3 = hit.point
			var local: Vector3 = pt - origin
			var du: float = local.dot(u)
			var dv: float = local.dot(v)
			# Inset the pick bounds slightly so a click landing exactly on
			# an axis line (du or dv ≈ 0) still resolves as the axis pick
			# rather than being eaten by the plane that sits on top of it.
			if du >= PLANE_PICK_INSET and du <= PLANE_SIZE - PLANE_PICK_INSET \
				and dv >= PLANE_PICK_INSET and dv <= PLANE_SIZE - PLANE_PICK_INSET:
				if hit.t < best_t:
					best_t = hit.t
					best_handle = name2
					best_normal = n
	# Rotate rings — pick the closest ring whose hit lies within ring thickness.
	if mode == MODE_ROTATE:
		var rings: Array = [
			[HANDLE_ROT_X, b.x],
			[HANDLE_ROT_Y, b.y],
			[HANDLE_ROT_Z, b.z],
		]
		for r in rings:
			var rname: String = r[0]
			var n: Vector3 = r[1].normalized()
			var hit: Dictionary = _ray_plane_hit(from, dir, origin, n)
			if hit.is_empty():
				continue
			var local: Vector3 = hit.point - origin
			var d: float = absf(local.length() - RING_RADIUS)
			if d <= RING_THICKNESS and hit.t < best_t:
				best_t = hit.t
				best_handle = rname
				best_axis = n
	if best_handle == HANDLE_NONE:
		return {"handle": HANDLE_NONE}
	return {
		"handle": best_handle,
		"axis": best_axis,
		"normal": best_normal,
		"t": best_t,
	}

func set_hover(h: String) -> void:
	if hover_handle == h:
		return
	hover_handle = h

# Closest-approach distance between the mouse ray and a segment. Returns
# the distance if the closest point on the segment is within HIT_RADIUS
# of the ray, else -1. Distance metric is (ray t at closest), so smaller
# == nearer to camera (used to break ties).
func _ray_segment_dist(ro: Vector3, rd: Vector3, a: Vector3, b: Vector3) -> float:
	var u: Vector3 = b - a
	var v: Vector3 = rd
	var w: Vector3 = a - ro
	var a_uu: float = u.dot(u)
	var b_uv: float = u.dot(v)
	var c_vv: float = v.dot(v)
	var d_uw: float = u.dot(w)
	var e_vw: float = v.dot(w)
	var denom: float = a_uu * c_vv - b_uv * b_uv
	if absf(denom) < 1e-7:
		return -1.0
	var sc: float = (b_uv * e_vw - c_vv * d_uw) / denom  # along segment
	var tc: float = (a_uu * e_vw - b_uv * d_uw) / denom  # along ray
	if sc < 0.0 or sc > 1.0 or tc < 0.0:
		return -1.0
	var pa: Vector3 = a + u * sc
	var pb: Vector3 = ro + v * tc
	if pa.distance_to(pb) > HIT_RADIUS:
		return -1.0
	return tc

func _ray_plane_hit(ro: Vector3, rd: Vector3, p: Vector3, n: Vector3) -> Dictionary:
	var denom: float = rd.dot(n)
	if absf(denom) < 1e-6:
		return {}
	var t: float = (p - ro).dot(n) / denom
	if t < 0.0:
		return {}
	return {"point": ro + rd * t, "t": t}
