extends Node3D

# Visual ring laid on the terrain surface to show where the brush will
# act. Built from line segments — re-projected to the terrain height
# every frame via sample_height so it hugs hills.

const SEGMENTS := 48

var radius := 4.0
var terrain: Node = null
var color := Color(1.0, 0.9, 0.2, 1.0)

var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D
# When set (mode_flat = true), the ring renders as a flat circle at
# fixed world y instead of hugging the terrain surface. Used for the
# flatten target preview.
var _mode_flat: bool = false
var _flat_y: float = 0.0

func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = color
	_material.no_depth_test = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)

func set_radius(r: float) -> void:
	radius = max(0.25, r)

func set_color(c: Color) -> void:
	color = c
	if _material != null:
		_material.albedo_color = c

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
	for i in range(SEGMENTS):
		var a0: float = (float(i)     / float(SEGMENTS)) * TAU
		var a1: float = (float(i + 1) / float(SEGMENTS)) * TAU
		var p0 := Vector3(cos(a0) * radius, 0.0, sin(a0) * radius)
		var p1 := Vector3(cos(a1) * radius, 0.0, sin(a1) * radius)
		if _mode_flat:
			p0.y = _flat_y - global_position.y
			p1.y = _flat_y - global_position.y
		else:
			p0.y = terrain.sample_height(global_position + p0) - global_position.y + 0.05
			p1.y = terrain.sample_height(global_position + p1) - global_position.y + 0.05
		im.surface_add_vertex(p0)
		im.surface_add_vertex(p1)
	im.surface_end()
	_mesh_instance.mesh = im
