extends Node

const Items = preload("res://items.gd")

const MAX_WEIGHT := 50.0      # encumbrance ceiling, kg
const FAVORITE_SLOTS := 9     # bind to digit keys 1..9

signal changed
signal favorites_changed
signal equipped_changed(id: String)

# item_id -> int count. No stack-size cap; encumbrance is the only limit.
var counts: Dictionary = {}
# slot int (1..9) -> item_id
var favorites: Dictionary = {}
# Currently equipped weapon id (or "" if nothing).
var equipped: String = ""

func can_add(id: String, n: int = 1) -> bool:
	if not Items.DEFS.has(id):
		return false
	return total_weight() + Items.item_weight(id) * n <= MAX_WEIGHT + 0.0001

func add(id: String, n: int = 1) -> bool:
	if n <= 0 or not can_add(id, n):
		return false
	counts[id] = counts.get(id, 0) + n
	changed.emit()
	return true

# Bypass weight check — used to seed starting loadout.
func grant(id: String, n: int = 1) -> void:
	if n <= 0 or not Items.DEFS.has(id):
		return
	counts[id] = counts.get(id, 0) + n
	changed.emit()

func remove(id: String, n: int = 1) -> bool:
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

func has_item(id: String) -> bool:
	return counts.get(id, 0) > 0

func total_weight() -> float:
	var w := 0.0
	for id in counts:
		w += Items.item_weight(id) * float(counts[id])
	return w

func encumbrance_ratio() -> float:
	if MAX_WEIGHT <= 0.0:
		return 0.0
	return clampf(total_weight() / MAX_WEIGHT, 0.0, 1.0)

# Returns [{id, count, name, weight_total, value_each, kind}, ...]
func entries() -> Array:
	var out := []
	for id in counts:
		var c: int = counts[id]
		out.append({
			"id": id,
			"count": c,
			"name": Items.item_name(id),
			"kind": Items.item_kind(id),
			"weight_total": Items.item_weight(id) * float(c),
			"value_each": Items.item_value(id),
		})
	return out

func set_equipped(id: String) -> void:
	if id != "" and not has_item(id):
		return
	if id == equipped:
		return
	equipped = id
	equipped_changed.emit(id)

func set_favorite(slot: int, id: String) -> void:
	if slot < 1 or slot > FAVORITE_SLOTS:
		return
	# One-id-per-slot: clear any prior slot pointing at this id.
	for s in favorites.keys():
		if favorites[s] == id and s != slot:
			favorites.erase(s)
	if id == "":
		favorites.erase(slot)
	else:
		favorites[slot] = id
	favorites_changed.emit()

func clear_favorite(slot: int) -> void:
	if favorites.erase(slot):
		favorites_changed.emit()

func find_favorite_slot(id: String) -> int:
	for s in favorites.keys():
		if favorites[s] == id:
			return int(s)
	return 0

func favorite_id(slot: int) -> String:
	return String(favorites.get(slot, ""))
