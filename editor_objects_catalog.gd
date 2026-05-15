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
const COMPUTER_STATION := preload("res://computer_station.gd")
const CCTV_CAMERA := preload("res://cctv_camera.gd")

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
		"obj_computer_station":
			return _build_computer_station()
		"obj_cctv_camera":
			return _build_cctv_camera()
		"obj_plate":
			return _build_glb_prop("res://assets/models/plate.glb")
		_:
			return null

# Computer Station: a low desk + monitor. Player can mount it at
# runtime to view CCTV feeds. Per-instance cam list + allow_add flag
# live on the resulting node (see computer_station.gd).
static func _build_computer_station() -> Node3D:
	var holder := Node3D.new()
	holder.set_script(COMPUTER_STATION)
	var desk := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(1.2, 0.85, 0.7)
	desk.mesh = dm
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.22, 0.22, 0.26, 1.0)
	dmat.roughness = 0.7
	desk.material_override = dmat
	desk.position = Vector3(0, 0.425, 0)
	holder.add_child(desk)
	var monitor := MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(0.9, 0.55, 0.06)
	monitor.mesh = mm
	var screen_mat := StandardMaterial3D.new()
	screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen_mat.albedo_color = Color(0.15, 0.55, 0.85, 1.0)
	screen_mat.emission_enabled = true
	screen_mat.emission = Color(0.05, 0.35, 0.55, 1.0)
	screen_mat.emission_energy_multiplier = 0.6
	monitor.material_override = screen_mat
	monitor.position = Vector3(0, 1.15, -0.28)
	holder.add_child(monitor)
	var body := StaticBody3D.new()
	body.position = Vector3(0, 0.425, 0)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.2, 0.85, 0.7)
	shape.shape = bs
	body.add_child(shape)
	holder.add_child(body)
	return holder

# CCTV Camera: sphere with a forward-facing protrusion so the user can
# read where it points. cam_id + ptz_enabled stored on the node.
static func _build_cctv_camera() -> Node3D:
	var holder := Node3D.new()
	holder.set_script(CCTV_CAMERA)
	var bracket := MeshInstance3D.new()
	var brm := CylinderMesh.new()
	brm.top_radius = 0.04
	brm.bottom_radius = 0.04
	brm.height = 0.25
	bracket.mesh = brm
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.32, 0.32, 0.35, 1.0)
	grey.roughness = 0.55
	bracket.material_override = grey
	bracket.position = Vector3(0, 0.125, 0)
	holder.add_child(bracket)
	var sphere := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	sphere.mesh = sm
	var housing := StandardMaterial3D.new()
	housing.albedo_color = Color(0.18, 0.18, 0.2, 1.0)
	housing.roughness = 0.4
	sphere.material_override = housing
	sphere.position = Vector3(0, 0.32, 0)
	holder.add_child(sphere)
	var lens := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.07
	lm.bottom_radius = 0.06
	lm.height = 0.12
	lens.mesh = lm
	var lens_mat := StandardMaterial3D.new()
	lens_mat.albedo_color = Color(0.05, 0.05, 0.07, 1.0)
	lens_mat.metallic = 0.5
	lens_mat.roughness = 0.2
	lens.material_override = lens_mat
	# Protrusion points along +Z (forward). Cylinder is Y-aligned by
	# default; rotate 90deg around X so its axis lies along Z.
	lens.rotation = Vector3(deg_to_rad(90.0), 0, 0)
	lens.position = Vector3(0, 0.32, 0.18)
	holder.add_child(lens)
	return holder

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

static func _build_glb_prop(path: String) -> Node3D:
	# Launcher source-pull does not include Godot's .import sidecars, so
	# load(path) returns null on a fresh checkout. Load the glb at runtime
	# via GLTFDocument so the prop works without an editor preprocess pass.
	var holder := Node3D.new()
	var abs_path: String = ProjectSettings.globalize_path(path)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(abs_path, state)
	if err != OK:
		push_warning("editor_objects_catalog: glb load failed (%d) at %s" % [err, abs_path])
		return holder
	var inst := doc.generate_scene(state)
	if inst == null:
		push_warning("editor_objects_catalog: glb produced no scene: %s" % abs_path)
		return holder
	holder.add_child(inst)
	var body := StaticBody3D.new()
	holder.add_child(body)
	for mi in _find_mesh_instances(inst):
		var shape := CollisionShape3D.new()
		shape.shape = mi.mesh.create_trimesh_shape()
		shape.transform = mi.transform
		body.add_child(shape)
	return holder

static func _find_mesh_instances(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D and node.mesh != null:
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_mesh_instances(c))
	return out

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
