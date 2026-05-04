extends Node3D

# Editor visual for an actor-spawn point. Filled cube tinted with the
# owning actor table's color so the user can see at a glance which
# preset feeds which spot. Slightly taller than item-spawn cubes so the
# two systems are visually distinct in the editor.

const SIZE := Vector3(0.7, 1.6, 0.7)
const SELECTED_TINT := Color(1.0, 0.95, 0.35, 1.0)

var table_id: String = ""
var color: Color = Color(1, 1, 1, 1)

var _mi: MeshInstance3D
var _wire: MeshInstance3D
var _mat: StandardMaterial3D
var _wire_mat: StandardMaterial3D

func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = color
	var bm := BoxMesh.new()
	bm.size = SIZE
	_mi = MeshInstance3D.new()
	_mi.mesh = bm
	_mi.material_override = _mat
	_mi.position = Vector3(0, SIZE.y * 0.5, 0)
	add_child(_mi)
	_wire_mat = StandardMaterial3D.new()
	_wire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wire_mat.albedo_color = SELECTED_TINT
	_wire_mat.no_depth_test = true
	_wire = MeshInstance3D.new()
	_wire.position = Vector3(0, SIZE.y * 0.5, 0)
	add_child(_wire)
	_rebuild_wire()
	_wire.visible = false

func set_color(c: Color) -> void:
	color = c
	if _mat != null:
		_mat.albedo_color = c

func set_selected(v: bool) -> void:
	if _wire != null:
		_wire.visible = v

func get_aabb_local() -> AABB:
	return AABB(Vector3(-SIZE.x * 0.5, 0.0, -SIZE.z * 0.5), SIZE)

func _rebuild_wire() -> void:
	var lo: Vector3 = -SIZE * 0.5
	var hi: Vector3 = SIZE * 0.5
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
	im.surface_begin(Mesh.PRIMITIVE_LINES, _wire_mat)
	for e in edges:
		im.surface_add_vertex(c[e[0]])
		im.surface_add_vertex(c[e[1]])
	im.surface_end()
	_wire.mesh = im
