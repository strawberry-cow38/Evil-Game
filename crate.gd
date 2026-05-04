extends Node3D

# Lootable storage container. Mirrors the inventory.gd surface (counts dict
# for stackables + instances array for weapons/apparel) but without the
# weight cap — crates are bottomless. Player.gd raycast picks these up via
# the "container" meta on the inner StaticBody3D, same pattern pickups use.

const Items = preload("res://items.gd")

const SIZE := Vector3(1.1, 1.0, 0.8)
const ALBEDO := Color(0.45, 0.30, 0.16, 1.0)
const BAND_ALBEDO := Color(0.20, 0.13, 0.08, 1.0)

signal changed

var counts: Dictionary = {}
var instances: Array[Dictionary] = []
var _next_uid: int = 1
# Display name shown in the hover/menu UI. Defaulted; could be made
# editor-assignable later.
var label_name: String = "Crate"

func _ready() -> void:
	add_to_group("container")
	_build_visual()
	_build_collision()

func _build_visual() -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = SIZE
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ALBEDO
	mat.roughness = 0.85
	mi.material_override = mat
	mi.position = Vector3(0, SIZE.y * 0.5, 0)
	add_child(mi)
	# Two darker bands wrapped around the crate so it reads as a "crate" not
	# just a brown box at a glance.
	for z in [-SIZE.z * 0.3, SIZE.z * 0.3]:
		var band := MeshInstance3D.new()
		var bbm := BoxMesh.new()
		bbm.size = Vector3(SIZE.x * 1.01, SIZE.y * 0.08, 0.04)
		band.mesh = bbm
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = BAND_ALBEDO
		bmat.roughness = 0.7
		band.material_override = bmat
		band.position = Vector3(0, SIZE.y * 0.5, z)
		add_child(band)

func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.position = Vector3(0, SIZE.y * 0.5, 0)
	# Meta lets the player's interact raycast discover us the same way it
	# discovers pickups (player.gd:_update_interact_target).
	body.set_meta("container", self)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = SIZE
	shape.shape = box_shape
	body.add_child(shape)
	add_child(body)

# --- Inventory API --------------------------------------------------------

# Stackable add: bumps the counts dict. Instance kinds get one fresh
# instance per n with default condition + quality (matches inventory.add).
func add(id: String, n: int = 1) -> bool:
	if n <= 0 or not Items.DEFS.has(id):
		return false
	if Items.is_instance_kind(id):
		for i in range(n):
			_spawn_instance(id, 1.0, Items.QUALITY_NORMAL)
	else:
		counts[id] = counts.get(id, 0) + n
	changed.emit()
	return true

# Insert a pre-existing instance dict (transferred from player inventory).
# Re-stamps uid so it doesn't collide.
func add_instance(inst: Dictionary) -> bool:
	var id: String = String(inst.get("item_id", ""))
	if id == "" or not Items.DEFS.has(id):
		return false
	var copy: Dictionary = inst.duplicate(true)
	copy.uid = _next_uid
	_next_uid += 1
	if not copy.has("condition"):
		copy.condition = 1.0
	if not copy.has("quality"):
		copy.quality = Items.QUALITY_NORMAL
	instances.append(copy)
	changed.emit()
	return true

# Removes n of an item id. For instance kinds removes the n oldest instances
# of that id. Returns true on success.
func remove(id: String, n: int = 1) -> bool:
	if n <= 0:
		return false
	if Items.is_instance_kind(id):
		var to_remove: Array[int] = []
		for inst in instances:
			if to_remove.size() >= n:
				break
			if String(inst.item_id) == id:
				to_remove.append(int(inst.uid))
		if to_remove.size() < n:
			return false
		for uid in to_remove:
			_remove_instance_internal(uid)
		changed.emit()
		return true
	var have: int = counts.get(id, 0)
	if have < n:
		return false
	have -= n
	if have <= 0:
		counts.erase(id)
	else:
		counts[id] = have
	changed.emit()
	return true

# Pop a specific instance + return its dict (so the player inventory can
# preserve condition/quality on the receiving side).
func remove_instance(uid: int) -> Dictionary:
	var found: Dictionary = {}
	for i in range(instances.size()):
		if int(instances[i].uid) == uid:
			found = instances[i]
			instances.remove_at(i)
			break
	if found.is_empty():
		return {}
	changed.emit()
	return found

func _spawn_instance(id: String, cond: float, qual: int) -> int:
	var uid := _next_uid
	_next_uid += 1
	instances.append({
		"uid": uid,
		"item_id": id,
		"condition": clampf(cond, 0.0, 1.0),
		"quality": clampi(qual, 0, 6),
	})
	return uid

func _remove_instance_internal(uid: int) -> void:
	for i in range(instances.size()):
		if int(instances[i].uid) == uid:
			instances.remove_at(i)
			break

# --- Queries --------------------------------------------------------------

func is_empty() -> bool:
	return counts.is_empty() and instances.is_empty()

func total_count() -> int:
	var n: int = instances.size()
	for id in counts:
		n += int(counts[id])
	return n

# Same shape as inventory.entries() so the menu can render either side
# with the same code path.
func entries() -> Array:
	var out: Array = []
	for inst in instances:
		var id: String = String(inst.item_id)
		out.append({
			"id": id,
			"uid": int(inst.uid),
			"count": 1,
			"name": Items.item_name(id),
			"kind": Items.item_kind(id),
			"weight_total": Items.item_weight(id),
			"value_each": Items.item_value(id),
			"condition": float(inst.condition),
			"quality": int(inst.quality),
			"is_instance": true,
		})
	for id in counts:
		var c: int = counts[id]
		out.append({
			"id": id,
			"uid": 0,
			"count": c,
			"name": Items.item_name(id),
			"kind": Items.item_kind(id),
			"weight_total": Items.item_weight(id) * float(c),
			"value_each": Items.item_value(id),
			"condition": 1.0,
			"quality": Items.QUALITY_NORMAL,
			"is_instance": false,
		})
	return out
