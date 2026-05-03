extends RefCounted

# Maps effect ids → factory functions that build the actual visual /
# logic content for that effect. The wireframe box (editor_effect_box)
# stays as the editor handle; whatever this catalog returns is added
# *inside* the box so the box still acts as the bounds indicator.
#
# Phase-3 only ships the demo cube. Real fx (particles, decals, lights,
# audio) wire in over time — each new id just needs an entry here.

static func build(effect_id: String) -> Node3D:
	match effect_id:
		"demo_cube":
			return _build_demo_cube()
		_:
			return null

static func _build_demo_cube() -> Node3D:
	var holder := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 1.0, 1.0)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.45, 0.95, 1.0)
	mat.roughness = 0.55
	mi.material_override = mat
	holder.add_child(mi)
	return holder
