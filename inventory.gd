extends Node

const Items = preload("res://items.gd")

const MAX_WEIGHT := 50.0      # encumbrance ceiling, kg

signal changed

# item_id -> int count. No stack-size cap; encumbrance is the only limit.
var counts: Dictionary = {}

func can_add(id: String, n: int = 1) -> bool:
	if not Items.DEFS.has(id):
		return false
	return total_weight() + Items.get_weight(id) * n <= MAX_WEIGHT + 0.0001

func add(id: String, n: int = 1) -> bool:
	if n <= 0 or not can_add(id, n):
		return false
	counts[id] = counts.get(id, 0) + n
	changed.emit()
	return true

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

func total_weight() -> float:
	var w := 0.0
	for id in counts:
		w += Items.get_weight(id) * float(counts[id])
	return w

func encumbrance_ratio() -> float:
	if MAX_WEIGHT <= 0.0:
		return 0.0
	return clampf(total_weight() / MAX_WEIGHT, 0.0, 1.0)

# Returns [{id, count, name, weight_total, value_each}, ...]
func entries() -> Array:
	var out := []
	for id in counts:
		var c: int = counts[id]
		out.append({
			"id": id,
			"count": c,
			"name": Items.get_name(id),
			"weight_total": Items.get_weight(id) * float(c),
			"value_each": Items.get_value(id),
		})
	return out
