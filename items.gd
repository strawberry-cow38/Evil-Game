extends RefCounted

# Item definitions. weight is per-unit kg, value is per-unit currency.
# color is the placeholder visual swatch — used both for the world pickup
# mesh and for the preview tile in the inventory menu.
const DEFS := {
	"apple":      {"name": "Apple",      "weight": 0.20, "value":   5, "color": Color(0.92, 0.20, 0.18), "kind": "food", "desc": "Crisp red apple. Slightly bruised."},
	"banana":     {"name": "Banana",     "weight": 0.15, "value":   3, "color": Color(0.95, 0.86, 0.20), "kind": "food", "desc": "Yellow banana. Surprisingly heavy for fruit."},
	"orange":     {"name": "Orange",     "weight": 0.25, "value":   6, "color": Color(0.98, 0.55, 0.10), "kind": "food", "desc": "Citrus. Smells nice."},
	"grape":      {"name": "Grape",      "weight": 0.05, "value":   1, "color": Color(0.50, 0.20, 0.55), "kind": "food", "desc": "A single grape. Lonely."},
	"lemon":      {"name": "Lemon",      "weight": 0.18, "value":   4, "color": Color(0.95, 0.92, 0.30), "kind": "food", "desc": "Sour. Don't eat raw."},
	"strawberry": {"name": "Strawberry", "weight": 0.03, "value":   2, "color": Color(0.95, 0.20, 0.30), "kind": "food", "desc": "Tiny red strawberry. *purrs*"},
	"pineapple":  {"name": "Pineapple",  "weight": 1.50, "value":  20, "color": Color(0.85, 0.78, 0.20), "kind": "food", "desc": "Spiky tropical fruit. Heavy."},
	"watermelon": {"name": "Watermelon", "weight": 4.00, "value":  30, "color": Color(0.20, 0.55, 0.25), "kind": "food", "desc": "Big juicy watermelon. Encumbering."},

	"akm":    {"name": "AKM",          "weight": 3.50, "value":  350, "color": Color(0.45, 0.30, 0.18), "kind": "weapon", "desc": "Soviet 7.62×39 assault rifle. Reliable, harsh climb.", "slots": ["Optic", "Muzzle", "Mag"]},
	"m16a2":  {"name": "M16A2",        "weight": 3.40, "value":  420, "color": Color(0.20, 0.20, 0.22), "kind": "weapon", "desc": "5.56 NATO. Burst-capable. Cleaner than the AK.", "slots": ["Optic", "Muzzle", "Mag", "Grip"]},
	"bizon":  {"name": "PP-19 Bizon",  "weight": 2.50, "value":  280, "color": Color(0.30, 0.32, 0.30), "kind": "weapon", "desc": "9mm SMG with helical 64-round mag. Compact.", "slots": ["Optic", "Muzzle"]},
	"mp5sd":  {"name": "MP5SD",        "weight": 3.00, "value":  520, "color": Color(0.15, 0.15, 0.17), "kind": "weapon", "desc": "Integrally suppressed 9mm SMG. Very quiet, sloppy bloom.", "slots": ["Optic", "Mag"]},
	"m249":   {"name": "M249 SAW",     "weight": 7.50, "value":  900, "color": Color(0.28, 0.28, 0.25), "kind": "weapon", "desc": "5.56 belt-fed LMG. 100-round box. Heavy.", "slots": ["Optic", "Bipod"]},
	"m60":    {"name": "M60",          "weight": 10.50,"value": 1100, "color": Color(0.22, 0.22, 0.20), "kind": "weapon", "desc": "7.62 belt-fed LMG. Slow cyclic, devastating.", "slots": ["Optic", "Bipod"]},
	"mgl":    {"name": "Milkor MGL",   "weight": 5.50, "value":  800, "color": Color(0.18, 0.30, 0.20), "kind": "weapon", "desc": "40mm 6-round revolving grenade launcher. Goes boom.", "slots": ["Optic"]},
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

static func item_kind(id: String) -> String:
	return DEFS.get(id, {}).get("kind", "misc")

static func item_desc(id: String) -> String:
	return DEFS.get(id, {}).get("desc", "")

static func item_slots(id: String) -> Array:
	return DEFS.get(id, {}).get("slots", [])
