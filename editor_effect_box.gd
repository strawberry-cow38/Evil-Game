extends Node3D

# Wireframe-box visual for a placed effect. Renders 12 line segments
# making up an axis-aligned box (in local space) of `box_size`. Color
# changes when selected. Stores its source effect id so the editor can
# tell what's at this slot when finalising the map.

const COLOR_NORMAL := Color(0.4, 0.85, 1.0, 1.0)
const COLOR_SELECTED := Color(1.0, 0.95, 0.35, 1.0)

var effect_id: String = ""
var box_size: Vector3 = Vector3(2.0, 2.0, 2.0)

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
	_rebuild()

func set_selected(v: bool) -> void:
	_selected = v
	if _material != null:
		_material.albedo_color = COLOR_SELECTED if v else COLOR_NORMAL

func get_aabb_local() -> AABB:
	# Half-extents from box_size.
	var h: Vector3 = box_size * 0.5
	return AABB(-h, box_size)

func _rebuild() -> void:
	var h: Vector3 = box_size * 0.5
	var c: Array = [
		Vector3(-h.x, -h.y, -h.z),
		Vector3( h.x, -h.y, -h.z),
		Vector3( h.x, -h.y,  h.z),
		Vector3(-h.x, -h.y,  h.z),
		Vector3(-h.x,  h.y, -h.z),
		Vector3( h.x,  h.y, -h.z),
		Vector3( h.x,  h.y,  h.z),
		Vector3(-h.x,  h.y,  h.z),
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
