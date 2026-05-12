extends Node3D

# Wireframe-box visual for a placed effect. Renders 12 line segments
# making up an axis-aligned box (in local space) of `box_size`. Color
# changes when selected. Stores its source effect id so the editor can
# tell what's at this slot when finalising the map.

const CATALOG := preload("res://editor_effect_catalog.gd")

const COLOR_NORMAL := Color(0.4, 0.85, 1.0, 1.0)
const COLOR_SELECTED := Color(1.0, 0.95, 0.35, 1.0)

const PAD := 0.0  # strict fit — wireframe sits exactly on the content's AABB
const FALLBACK_SIZE := Vector3(2.0, 2.0, 2.0)  # used if catalog has no mesh

var effect_id: String = ""
var prop_id: String = ""
var _local_aabb: AABB = AABB(-FALLBACK_SIZE * 0.5, FALLBACK_SIZE)

var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D
var _selected: bool = false

func _ready() -> void:
	if prop_id == "":
		prop_id = "pr_%d_%d" % [Time.get_ticks_usec(), randi()]
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = COLOR_NORMAL
	_material.no_depth_test = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)
	# If the catalog knows this effect id, drop its content (the actual
	# visual) inside the box first — we need its bounds to size the box.
	var content: Node3D = CATALOG.build(effect_id)
	if content != null:
		add_child(content)
		var aabb: AABB = _compute_content_aabb(content)
		if aabb.size.length_squared() > 0.0:
			_local_aabb = aabb.grow(PAD)
	_rebuild()

func set_selected(v: bool) -> void:
	_selected = v
	if _material != null:
		_material.albedo_color = COLOR_SELECTED if v else COLOR_NORMAL

func get_aabb_local() -> AABB:
	return _local_aabb

func _rebuild() -> void:
	var lo: Vector3 = _local_aabb.position
	var hi: Vector3 = _local_aabb.position + _local_aabb.size
	var c: Array = [
		Vector3(lo.x, lo.y, lo.z),
		Vector3(hi.x, lo.y, lo.z),
		Vector3(hi.x, lo.y, hi.z),
		Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z),
		Vector3(hi.x, hi.y, lo.z),
		Vector3(hi.x, hi.y, hi.z),
		Vector3(lo.x, hi.y, hi.z),
	]
	var edges: Array = [
		[0,1],[1,2],[2,3],[3,0],
		[4,5],[5,6],[6,7],[7,4],
		[0,4],[1,5],[2,6],[3,7],
	]
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, _material)
	for e in edges:
		im.surface_add_vertex(c[e[0]])
		im.surface_add_vertex(c[e[1]])
	im.surface_end()
	_mesh_instance.mesh = im

# Walks `content` (a child of this box) and unions every MeshInstance3D's
# bounds, transformed up into this box's local space. Returns AABB() if
# no meshes found.
func _compute_content_aabb(content: Node3D) -> AABB:
	var meshes: Array = []
	_collect_meshes(content, meshes)
	if meshes.is_empty():
		return AABB()
	var first: bool = true
	var out: AABB = AABB()
	for mi in meshes:
		var rel: Transform3D = content.transform * _relative_transform(mi, content)
		var transformed: AABB = rel * mi.get_aabb()
		if first:
			out = transformed
			first = false
		else:
			out = out.merge(transformed)
	return out

func _collect_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)

# Transform that takes coords from `node`'s local space up to `root`'s
# local space (root not included). Used so we don't rely on
# global_transform during _ready.
func _relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var xform: Transform3D = Transform3D.IDENTITY
	var cur: Node3D = node
	while cur != null and cur != root:
		xform = cur.transform * xform
		cur = cur.get_parent() as Node3D
	return xform
