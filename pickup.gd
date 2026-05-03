extends Area3D

const Items = preload("res://items.gd")

@export var item_id: String = "apple"
@export var count: int = 1
# Optional instance payload for unstackable items (weapons/apparel). If
# non-empty, looter calls inventory.add_instance to preserve condition+quality.
var instance: Dictionary = {}

func _ready() -> void:
	add_to_group("pickup")
	collision_layer = 0
	collision_mask = 0
	monitorable = true
	monitoring = false

	var def: Dictionary = Items.item_def(item_id)
	var color: Color = def.get("color", Color(0.8, 0.8, 0.8))
	# Visual radius scales gently with weight so a watermelon looks chunkier
	# than a grape, but still capped to readable sizes.
	var weight: float = float(def.get("weight", 0.2))
	var radius: float = clampf(0.10 + sqrt(weight) * 0.10, 0.10, 0.32)

	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.5
	mat.metallic = 0.0
	mesh.material = mat

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)

	# Small static body so the player ray can hit it for prompt detection.
	# Lives as a child so the Area3D itself stays trigger-only.
	var body := StaticBody3D.new()
	body.collision_layer = 4   # bit 3 — "pickups"
	body.collision_mask = 0
	body.add_to_group("pickup_body")
	body.set_meta("pickup", self)
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius * 1.2
	col.shape = shape
	body.add_child(col)
	add_child(body)

func get_label() -> String:
	var n: String = Items.item_name(item_id)
	if not instance.is_empty():
		var q: int = int(instance.get("quality", Items.QUALITY_NORMAL))
		var cond: float = float(instance.get("condition", 1.0))
		var tier: Dictionary = Items.condition_tier(cond, Items.item_kind(item_id))
		return "%s %s (%s)" % [Items.quality_name(q), n, tier.name]
	if count > 1:
		return "%s x%d" % [n, count]
	return n
