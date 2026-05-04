extends Node3D

# Wireframe-box visual for a placed object (prop / static decor).
# Mirrors editor_effect_box but tinted green so effects vs. objects are
# distinguishable in the viewport. Stores its source object id so the
# editor can tell what's at this slot when finalising the map.

const CATALOG := preload("res://editor_objects_catalog.gd")

const COLOR_NORMAL := Color(0.45, 1.0, 0.6, 1.0)
const COLOR_SELECTED := Color(1.0, 0.95, 0.35, 1.0)

const PAD := 0.0  # strict fit — wireframe sits exactly on the content's AABB
const FALLBACK_SIZE := Vector3(2.0, 2.0, 2.0)

var object_id: String = ""
# Container objects (crates) read this at play-mode bootstrap to roll
# their starting loot. Empty string = no table = empty crate.
var loot_table_id: String = ""
# Per-placement override for the crate's roll count. -1 = use the catalog
# default for this object id (e.g. 6 for small / 14 for large). Anything
# >= 0 wins so the editor can drop a one-item stash next to a stuffed
# bonanza without forking the catalog.
var roll_count_override: int = -1
var _local_aabb: AABB = AABB(-FALLBACK_SIZE * 0.5, FALLBACK_SIZE)

var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D
var _selected: bool = false

func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = COLOR_NORMAL
	_material.no_depth_test = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)
	var content: Node3D = CATALOG.build(object_id)
	if content != null:
		add_child(content)
		var aabb: AABB = _compute_content_aabb(content)
		if aabb.size.length_squared() > 0.0:
			_local_aabb = aabb.grow(PAD)
	_rebuild()
	# Objects hide their bounds wireframe when not selected — they're real
	# props that should look like the prop alone in the viewport. Effects
	# keep theirs (they're often invisible/sparse, need the box as a hint).
	_mesh_instance.visible = false

func set_selected(v: bool) -> void:
	_selected = v
	if _material != null:
		_material.albedo_color = COLOR_SELECTED if v else COLOR_NORMAL
	if _mesh_instance != null:
		_mesh_instance.visible = v

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

func _relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var xform: Transform3D = Transform3D.IDENTITY
	var cur: Node3D = node
	while cur != null and cur != root:
		xform = cur.transform * xform
		cur = cur.get_parent() as Node3D
	return xform
