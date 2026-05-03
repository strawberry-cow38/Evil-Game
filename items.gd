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
	"sks":    {"name": "SKS",          "weight": 3.85, "value":  260, "color": Color(0.50, 0.35, 0.20), "kind": "weapon", "desc": "Soviet 7.62×39 carbine. Semi-auto only, 10-round internal mag.", "slots": ["Optic", "Muzzle"]},
	"m16a2":  {"name": "M16A2",        "weight": 3.40, "value":  420, "color": Color(0.20, 0.20, 0.22), "kind": "weapon", "desc": "5.56 NATO. Burst-capable. Cleaner than the AK.", "slots": ["Optic", "Muzzle", "Mag", "Grip"]},
	"bizon":  {"name": "PP-19 Bizon",  "weight": 2.50, "value":  280, "color": Color(0.30, 0.32, 0.30), "kind": "weapon", "desc": "9mm SMG with helical 64-round mag. Compact.", "slots": ["Optic", "Muzzle"]},
	"mp5sd":  {"name": "MP5SD",        "weight": 3.00, "value":  520, "color": Color(0.15, 0.15, 0.17), "kind": "weapon", "desc": "Integrally suppressed 9mm SMG. Very quiet, sloppy bloom.", "slots": ["Optic", "Mag"]},
	"m249":   {"name": "M249 SAW",     "weight": 7.50, "value":  900, "color": Color(0.28, 0.28, 0.25), "kind": "weapon", "desc": "5.56 belt-fed LMG. 100-round box. Heavy.", "slots": ["Optic", "Bipod"]},
	"m60":    {"name": "M60",          "weight": 10.50,"value": 1100, "color": Color(0.22, 0.22, 0.20), "kind": "weapon", "desc": "7.62 belt-fed LMG. Slow cyclic, devastating.", "slots": ["Optic", "Bipod"]},
	"mgl":    {"name": "Milkor MGL",   "weight": 5.50, "value":  800, "color": Color(0.18, 0.30, 0.20), "kind": "weapon", "desc": "40mm 6-round revolving grenade launcher. Goes boom.", "slots": ["Optic"]},
	"makarov":{"name": "PM Makarov",   "weight": 0.66, "value":  120, "color": Color(0.18, 0.18, 0.20), "kind": "weapon", "desc": "Soviet 9×18 service pistol. 8-round mag.", "slots": ["Muzzle"]},

	"ammo_762x39":  {"name": "7.62×39mm",       "weight": 0.016, "value":  1, "color": Color(0.85, 0.65, 0.20), "kind": "ammo", "desc": "Soviet intermediate cartridge. Feeds the AKM."},
	"ammo_556nato": {"name": "5.56×45mm NATO",  "weight": 0.012, "value":  1, "color": Color(0.90, 0.78, 0.40), "kind": "ammo", "desc": "NATO standard. Feeds the M16A2 and M249."},
	"ammo_9mm":     {"name": "9×19mm",          "weight": 0.012, "value":  1, "color": Color(0.78, 0.72, 0.55), "kind": "ammo", "desc": "Pistol cartridge. Feeds the Bizon and MP5SD."},
	"ammo_9x18":    {"name": "9×18mm Makarov",  "weight": 0.010, "value":  1, "color": Color(0.72, 0.66, 0.50), "kind": "ammo", "desc": "Soviet pistol round. No weapon uses it yet."},
	"ammo_762nato": {"name": "7.62×51mm NATO",  "weight": 0.025, "value":  2, "color": Color(0.80, 0.55, 0.18), "kind": "ammo", "desc": "Full-power NATO rifle round. Feeds the M60."},
	"ammo_40mm":    {"name": "40mm Grenade",    "weight": 0.230, "value": 15, "color": Color(0.30, 0.55, 0.30), "kind": "ammo", "desc": "Low-velocity 40mm HE grenade. Feeds the MGL."},
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

# --- Instance system -------------------------------------------------------
# Kinds whose items are unstackable: each pickup is a unique instance with
# its own Condition (% wear) and Quality (craftsmanship tier).
const INSTANCE_KINDS: Array = ["weapon", "apparel", "armor", "clothing"]

const QUALITY_AWFUL := 0
const QUALITY_POOR := 1
const QUALITY_NORMAL := 2
const QUALITY_GOOD := 3
const QUALITY_EXCELLENT := 4
const QUALITY_MASTERWORK := 5
const QUALITY_LEGENDARY := 6

const QUALITY := {
	0: {"name": "Awful",      "color": Color(0.55, 0.50, 0.45)},
	1: {"name": "Poor",       "color": Color(0.75, 0.70, 0.65)},
	2: {"name": "Normal",     "color": Color(0.95, 0.95, 0.95)},
	3: {"name": "Good",       "color": Color(0.50, 0.95, 0.55)},
	4: {"name": "Excellent",  "color": Color(0.40, 0.80, 1.00)},
	5: {"name": "Masterwork", "color": Color(0.85, 0.45, 0.95)},
	6: {"name": "Legendary",  "color": Color(1.00, 0.65, 0.18)},
}

static func is_instance_kind(id: String) -> bool:
	return INSTANCE_KINDS.has(item_kind(id))

static func quality_name(q: int) -> String:
	return String(QUALITY.get(clampi(q, 0, 6), QUALITY[QUALITY_NORMAL])["name"])

static func quality_color(q: int) -> Color:
	return QUALITY.get(clampi(q, 0, 6), QUALITY[QUALITY_NORMAL])["color"]

# Returns {"name": String, "color": Color}. Uses "Tattered" for soft goods,
# "Damaged" for weapons/armor at the same tier band.
static func condition_tier(condition: float, kind: String) -> Dictionary:
	var c: float = clampf(condition, 0.0, 1.0)
	if c < 0.25:
		return {"name": "Ruined", "color": Color(0.95, 0.20, 0.18)}
	if c < 0.50:
		var soft: bool = kind == "apparel" or kind == "clothing"
		var nm: String = "Tattered" if soft else "Damaged"
		return {"name": nm, "color": Color(0.95, 0.55, 0.15)}
	if c < 0.80:
		return {"name": "Worn", "color": Color(0.90, 0.85, 0.25)}
	return {"name": "Pristine", "color": Color(0.30, 0.95, 0.35)}
