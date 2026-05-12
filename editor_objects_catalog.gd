extends RefCounted

# Maps object ids → factory functions that build the actual visual /
# logic content for that object. Wireframe box (editor_object_box)
# stays as the editor handle; whatever this catalog returns is added
# *inside* the box so the box still acts as the bounds indicator.
#
# Container variants come back as crate.gd nodes pre-configured with the
# right footprint, capacity, and roll-count. main_bootstrap reads those
# values to seed loot from whichever table the editor assigned.

const CRATE := preload("res://crate.gd")

# Set of object ids whose build() returns a crate.gd node. Editor uses
# this to decide when to show the loot-table picker on the selected
# wireframe box.
const CONTAINER_IDS := ["obj_crate_small", "obj_crate_large"]

static func is_container(object_id: String) -> bool:
	return CONTAINER_IDS.has(object_id)

static func build(object_id: String) -> Node3D:
	match object_id:
		"demo_crate":
			return _build_demo_crate()
		"obj_crate_small":
			return _build_lootable_crate("Crate (Small)", Vector3(1.1, 1.0, 0.8), 60.0, 6)
		"obj_crate_large":
			return _build_lootable_crate("Crate (Large)", Vector3(1.7, 1.4, 1.2), 180.0, 14)
		_:
			return null

# Lootable crate factory. No placeholder seeding — bootstrap fills the
# crate by rolling whichever loot table the editor assigned to this slot.
static func _build_lootable_crate(label: String, size: Vector3, max_w: float, rolls: int) -> Node3D:
	var holder := Node3D.new()
	holder.set_script(CRATE)
	holder.set("label_name", label)
	holder.set("size", size)
	holder.set("max_weight", max_w)
	holder.set("roll_count", rolls)
	return holder

static func _build_demo_crate() -> Node3D:
	var holder := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.4, 1.2, 1.4)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
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
