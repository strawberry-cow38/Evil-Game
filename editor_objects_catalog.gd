extends RefCounted

# Maps object ids → factory functions that build the actual visual /
# logic content for that object. Wireframe box (editor_object_box)
# stays as the editor handle; whatever this catalog returns is added
# *inside* the box so the box still acts as the bounds indicator.
#
# Phase-1 only ships the demo crate. Real props (furniture, debris,
# terminals, vehicles) wire in over time — each new id just needs an
# entry here.

static func build(object_id: String) -> Node3D:
	match object_id:
		"demo_crate":
			return _build_demo_crate()
		_:
			return null

static func _build_demo_crate() -> Node3D:
	var holder := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.4, 1.2, 1.4)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.38, 0.22, 1.0)
	mat.roughness = 0.85
	mi.material_override = mat
	mi.position = Vector3(0, 0.6, 0)
	holder.add_child(mi)
	var body := StaticBody3D.new()
	body.position = Vector3(0, 0.6, 0)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(1.4, 1.2, 1.4)
	shape.shape = box_shape
	body.add_child(shape)
	holder.add_child(body)
	return holder
