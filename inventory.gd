extends Node

const Items = preload("res://items.gd")

const MAX_WEIGHT := 200.0     # encumbrance ceiling, kg (room for full ammo loadout)
const FAVORITE_SLOTS := 9     # bind to digit keys 1..9

signal changed
signal favorites_changed
# Equipped now identifies an instance by uid. 0 = nothing equipped.
signal equipped_changed(uid: int)

# Stackable items: id -> int count.
var counts: Dictionary = {}
# Unstackable items (weapons, apparel) live here, each with its own condition
# + quality. Each entry: {uid:int, item_id:String, condition:float, quality:int}.
var instances: Array[Dictionary] = []

# Monotonic UID generator for instances.
var _next_uid: int = 1

# slot int (1..9) -> uid int  (or item_id String for stackables — currently unused)
var favorites: Dictionary = {}

# Currently equipped instance uid (0 = nothing).
var equipped_uid: int = 0

# --- Weight / capacity -----------------------------------------------------

func can_add(id: String, n: int = 1) -> bool:
	if not Items.DEFS.has(id):
		return false
	return total_weight() + Items.item_weight(id) * n <= MAX_WEIGHT + 0.0001

func total_weight() -> float:
	var w := 0.0
	for id in counts:
		w += Items.item_weight(id) * float(counts[id])
	for inst in instances:
		w += Items.item_weight(String(inst.item_id))
	return w

func encumbrance_ratio() -> float:
	if MAX_WEIGHT <= 0.0:
		return 0.0
	return clampf(total_weight() / MAX_WEIGHT, 0.0, 1.0)

# --- Add / remove ----------------------------------------------------------

# Adds n of an item, weight-checked. Instance kinds spawn n fresh instances
# at full condition + Normal quality; stackable kinds bump the counts dict.
func add(id: String, n: int = 1) -> bool:
	if n <= 0 or not can_add(id, n):
		return false
	if Items.is_instance_kind(id):
		for i in range(n):
			_spawn_instance(id, 1.0, Items.QUALITY_NORMAL)
	else:
		counts[id] = counts.get(id, 0) + n
	changed.emit()
	return true

# Bypasses weight check — used to seed starting loadout.
func grant(id: String, n: int = 1) -> void:
	if n <= 0 or not Items.DEFS.has(id):
		return
	if Items.is_instance_kind(id):
		for i in range(n):
			_spawn_instance(id, 1.0, Items.QUALITY_NORMAL)
	else:
		counts[id] = counts.get(id, 0) + n
	changed.emit()

# Spawn a single instance with explicit condition + quality. Used by the
# starting-loadout seed so the player sees the system in action.
func grant_instance(id: String, condition: float, quality: int) -> int:
	if not Items.DEFS.has(id) or not Items.is_instance_kind(id):
		return 0
	var uid: int = _spawn_instance(id, condition, quality)
	changed.emit()
	return uid

# Insert a pre-existing instance dict (from a world pickup we just looted).
# Re-stamps a fresh uid so it doesn't collide with anything else.
func add_instance(inst: Dictionary) -> bool:
	var id: String = String(inst.get("item_id", ""))
	if id == "" or not Items.DEFS.has(id):
		return false
	if not can_add(id, 1):
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

# Removes n of an item. For instance kinds removes the n oldest instances of
# that id (drop-by-id path; menu uses remove_instance for surgical drops).
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

# Removes the specific instance and returns its dict (so a drop spawn can
# preserve condition + quality on the world pickup). Returns {} on miss.
func remove_instance(uid: int) -> Dictionary:
	var found: Dictionary = {}
	for i in range(instances.size()):
		if int(instances[i].uid) == uid:
			found = instances[i]
			instances.remove_at(i)
			break
	if found.is_empty():
		return {}
	_purge_uid_refs(uid)
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
	_purge_uid_refs(uid)

func _purge_uid_refs(uid: int) -> void:
	if equipped_uid == uid:
		equipped_uid = 0
		equipped_changed.emit(0)
	var stale: Array = []
	for slot in favorites.keys():
		if int(favorites[slot]) == uid:
			stale.append(slot)
	if not stale.is_empty():
		for s in stale:
			favorites.erase(s)
		favorites_changed.emit()

# --- Queries ---------------------------------------------------------------

func has_item(id: String) -> bool:
	if Items.is_instance_kind(id):
		return _instance_count(id) > 0
	return counts.get(id, 0) > 0

func _instance_count(id: String) -> int:
	var n := 0
	for inst in instances:
		if String(inst.item_id) == id:
			n += 1
	return n

func has_uid(uid: int) -> bool:
	for inst in instances:
		if int(inst.uid) == uid:
			return true
	return false

func get_instance(uid: int) -> Dictionary:
	for inst in instances:
		if int(inst.uid) == uid:
			return inst
	return {}

func equipped_item_id() -> String:
	if equipped_uid == 0:
		return ""
	var inst: Dictionary = get_instance(equipped_uid)
	return String(inst.get("item_id", ""))

# Unified row list for the menu. One row per instance + one row per stack.
# Each row carries the fields the menu needs to render + dispatch.
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

# --- Equip -----------------------------------------------------------------

func set_equipped(uid: int) -> void:
	if uid != 0 and not has_uid(uid):
		return
	if uid == equipped_uid:
		return
	equipped_uid = uid
	equipped_changed.emit(uid)

# --- Favorites -------------------------------------------------------------

func set_favorite(slot: int, uid: int) -> void:
	if slot < 1 or slot > FAVORITE_SLOTS:
		return
	# One-uid-per-slot: clear any prior slot pointing at this uid.
	for s in favorites.keys():
		if int(favorites[s]) == uid and int(s) != slot:
			favorites.erase(s)
	if uid == 0:
		favorites.erase(slot)
	else:
		favorites[slot] = uid
	favorites_changed.emit()

func clear_favorite(slot: int) -> void:
	if favorites.erase(slot):
		favorites_changed.emit()

func find_favorite_slot_for_uid(uid: int) -> int:
	for s in favorites.keys():
		if int(favorites[s]) == uid:
			return int(s)
	return 0

func favorite_uid(slot: int) -> int:
	return int(favorites.get(slot, 0))
