extends RefCounted

# Clothing items pickable by per-slot loot tables on actor presets.
# Real clothing systems don't exist yet, so these are stubbed
# placeholders — the framework is in place so once items.gd grows real
# clothing entries we can wire them in by id without touching panel code.

const NOTHING_ID := "nothing"
const NOTHING_LABEL := "Nothing"

# Stub catalog — tagged by slot so the picker can filter. Ids prefixed
# with `cl_` so they don't collide with future items.gd entries.
const ITEMS: Array = [
	{"id": "cl_cap",      "slot": "head",  "label": "Cap (stub)"},
	{"id": "cl_helmet",   "slot": "head",  "label": "Helmet (stub)"},
	{"id": "cl_shirt",    "slot": "torso", "label": "Shirt (stub)"},
	{"id": "cl_jacket",   "slot": "torso", "label": "Jacket (stub)"},
	{"id": "cl_pants",    "slot": "legs",  "label": "Pants (stub)"},
	{"id": "cl_shorts",   "slot": "legs",  "label": "Shorts (stub)"},
	{"id": "cl_boots",    "slot": "feet",  "label": "Boots (stub)"},
	{"id": "cl_sneakers", "slot": "feet",  "label": "Sneakers (stub)"},
	{"id": "cl_gloves",   "slot": "hands", "label": "Gloves (stub)"},
	{"id": "cl_backpack", "slot": "back",  "label": "Backpack (stub)"},
]

static func for_slot(slot_id: String) -> Array:
	var out: Array = []
	out.append({"id": NOTHING_ID, "label": NOTHING_LABEL})
	for it in ITEMS:
		if String(it.slot) == slot_id:
			out.append({"id": String(it.id), "label": String(it.label)})
	return out

static func filtered(slot_id: String, query: String) -> Array:
	var q: String = query.strip_edges().to_lower()
	if q.is_empty():
		return for_slot(slot_id)
	var out: Array = []
	for e in for_slot(slot_id):
		if String(e.label).to_lower().find(q) != -1 or String(e.id).to_lower().find(q) != -1:
			out.append(e)
	return out

static func label_for(id: String) -> String:
	if id == NOTHING_ID:
		return NOTHING_LABEL
	for it in ITEMS:
		if String(it.id) == id:
			return String(it.label)
	return id
