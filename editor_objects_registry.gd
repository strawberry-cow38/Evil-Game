extends RefCounted

# Master list of objects available to drop into the world. Mirrors the
# effects registry — props/static decoration vs. fx. Phase-1 entries are
# placeholder names; concrete scenes wire in via editor_objects_catalog.

const OBJECTS: Array = [
	{"id": "demo_crate",        "label": "Demo: Crate"},
	{"id": "obj_barrel_wood",   "label": "Barrel (Wood)"},
	{"id": "obj_barrel_metal",  "label": "Barrel (Metal)"},
	{"id": "obj_crate_small",   "label": "Crate (Small)"},
	{"id": "obj_crate_large",   "label": "Crate (Large)"},
	{"id": "obj_chair_wood",    "label": "Chair (Wood)"},
	{"id": "obj_table_wood",    "label": "Table (Wood)"},
	{"id": "obj_bed_simple",    "label": "Bed (Simple)"},
	{"id": "obj_bookshelf",     "label": "Bookshelf"},
	{"id": "obj_lamp_floor",    "label": "Lamp (Floor)"},
	{"id": "obj_lamp_ceiling",  "label": "Lamp (Ceiling)"},
	{"id": "obj_door_wood",     "label": "Door (Wood)"},
	{"id": "obj_door_metal",    "label": "Door (Metal)"},
	{"id": "obj_locker",        "label": "Locker"},
	{"id": "obj_filing_cabinet","label": "Filing Cabinet"},
	{"id": "obj_terminal",      "label": "Terminal"},
	{"id": "obj_workbench",     "label": "Workbench"},
	{"id": "obj_stove",         "label": "Stove"},
	{"id": "obj_fridge",        "label": "Fridge"},
	{"id": "obj_sink",          "label": "Sink"},
	{"id": "obj_toilet",        "label": "Toilet"},
	{"id": "obj_tv_old",        "label": "TV (Old)"},
	{"id": "obj_radio",         "label": "Radio"},
	{"id": "obj_vendor",        "label": "Vending Machine"},
	{"id": "obj_car_wreck",     "label": "Car (Wreck)"},
	{"id": "obj_tree_pine",     "label": "Tree (Pine)"},
	{"id": "obj_tree_dead",     "label": "Tree (Dead)"},
	{"id": "obj_rock_large",    "label": "Rock (Large)"},
	{"id": "obj_rock_small",    "label": "Rock (Small)"},
	{"id": "obj_fence_post",    "label": "Fence Post"},
	{"id": "obj_streetlight",   "label": "Streetlight"},
	{"id": "obj_dumpster",      "label": "Dumpster"},
]

static func all_sorted() -> Array:
	var out: Array = OBJECTS.duplicate()
	out.sort_custom(func(a, b): return String(a.label).naturalnocasecmp_to(String(b.label)) < 0)
	return out

static func filtered(query: String) -> Array:
	var q: String = query.strip_edges().to_lower()
	if q.is_empty():
		return all_sorted()
	var out: Array = []
	for e in all_sorted():
		if String(e.label).to_lower().find(q) != -1 or String(e.id).to_lower().find(q) != -1:
			out.append(e)
	return out
