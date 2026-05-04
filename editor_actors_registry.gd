extends RefCounted

# Catalog of actor types the editor can spawn. Just the training dummy
# for now — proper enemies will get their own scripts later. The "kind"
# field is the play-mode bootstrap's switch for which scene/script to
# instantiate.

const ACTORS: Array = [
	{"id": "dummy", "label": "Damage Dummy", "kind": "dummy"},
]

# Clothing slot ids the per-actor clothing tables iterate over. Adding a
# new slot here automatically gets a tab in the actor-tables panel.
const SLOTS: Array = [
	{"id": "head",  "label": "Head"},
	{"id": "torso", "label": "Torso"},
	{"id": "legs",  "label": "Legs"},
	{"id": "feet",  "label": "Feet"},
	{"id": "hands", "label": "Hands"},
	{"id": "back",  "label": "Back"},
]

static func all_sorted() -> Array:
	var out: Array = []
	for a in ACTORS:
		out.append({"id": String(a.id), "label": String(a.label)})
	return out

static func label_for(id: String) -> String:
	for a in ACTORS:
		if String(a.id) == id:
			return String(a.label)
	return id

static func kind_for(id: String) -> String:
	for a in ACTORS:
		if String(a.id) == id:
			return String(a.kind)
	return ""

static func slot_label(slot_id: String) -> String:
	for s in SLOTS:
		if String(s.id) == slot_id:
			return String(s.label)
	return slot_id
