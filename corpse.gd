extends "res://crate.gd"

# Lootable corpse — same inventory API as a crate so the player's
# interact raycast + loot UI work unchanged. Only the visual + the
# physical footprint differ: a flat-ish capsule lying on the ground
# tinted with the actor table's color so dead actors still read as
# "this came from that preset".

const CORPSE_SIZE := Vector3(0.5, 0.4, 1.6)   # x=width, y=height (laying flat), z=length
const CORPSE_MAX_WEIGHT := 200.0

var corpse_color: Color = Color(0.6, 0.4, 0.3, 1)

func _ready() -> void:
	# Override crate defaults before our parent's _ready builds visual/collision.
	size = CORPSE_SIZE
	max_weight = CORPSE_MAX_WEIGHT
	if label_name == "Crate":
		label_name = "Corpse"
	add_to_group("container")
	_build_visual()
	_build_collision()

func _build_visual() -> void:
	# Body: short capsule lying along Z so it looks like a slumped figure.
	var body_mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.22
	cap.height = CORPSE_SIZE.z * 0.8
	body_mi.mesh = cap
	var mat := StandardMaterial3D.new()
	mat.albedo_color = corpse_color
	mat.roughness = 0.85
	body_mi.material_override = mat
	# Capsule defaults vertical (Y); rotate 90° around X so its long axis is Z.
	body_mi.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	body_mi.position = Vector3(0, 0.22, 0)
	add_child(body_mi)
	# Head: smaller sphere offset toward +Z so the corpse has a recognizable end.
	var head_mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.18
	sph.height = 0.36
	head_mi.mesh = sph
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = corpse_color.lerp(Color(0.95, 0.7, 0.4, 1), 0.5)
	head_mat.roughness = 0.85
	head_mi.material_override = head_mat
	head_mi.position = Vector3(0, 0.22, CORPSE_SIZE.z * 0.45)
	add_child(head_mi)

func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.position = Vector3(0, CORPSE_SIZE.y * 0.5, 0)
	body.set_meta("container", self)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = CORPSE_SIZE
	shape.shape = box_shape
	body.add_child(shape)
	add_child(body)
