extends RefCounted

# Item definitions. weight is per-unit kg, value is per-unit currency.
# color is the placeholder visual swatch — used both for the world pickup
# mesh and for the preview tile in the inventory menu.
const DEFS := {
	"apple":      {"name": "Apple",      "weight": 0.20, "value":  5, "color": Color(0.92, 0.20, 0.18)},
	"banana":     {"name": "Banana",     "weight": 0.15, "value":  3, "color": Color(0.95, 0.86, 0.20)},
	"orange":     {"name": "Orange",     "weight": 0.25, "value":  6, "color": Color(0.98, 0.55, 0.10)},
	"grape":      {"name": "Grape",      "weight": 0.05, "value":  1, "color": Color(0.50, 0.20, 0.55)},
	"lemon":      {"name": "Lemon",      "weight": 0.18, "value":  4, "color": Color(0.95, 0.92, 0.30)},
	"strawberry": {"name": "Strawberry", "weight": 0.03, "value":  2, "color": Color(0.95, 0.20, 0.30)},
	"pineapple":  {"name": "Pineapple",  "weight": 1.50, "value": 20, "color": Color(0.85, 0.78, 0.20)},
	"watermelon": {"name": "Watermelon", "weight": 4.00, "value": 30, "color": Color(0.20, 0.55, 0.25)},
}

static func item_def(id: String) -> Dictionary:
	return DEFS.get(id, {})

static func item_name(id: String) -> String:
	return DEFS.get(id, {}).get("name", id)

static func item_weight(id: String) -> float:
	return float(DEFS.get(id, {}).get("weight", 0.0))

static func item_value(id: String) -> int:
	return int(DEFS.get(id, {}).get("value", 0))

static func item_color(id: String) -> Color:
	return DEFS.get(id, {}).get("color", Color(1, 1, 1))
