extends RefCounted

# Master list of objects available to drop into the world. Mirrors the
# effects registry — props/static decoration vs. fx. Phase-1 entries are
# placeholder names; concrete scenes wire in via editor_objects_catalog.

const OBJECTS: Array = [
	{"id": "demo_crate",           "label": "Demo: Crate"},
	{"id": "obj_crate_small",      "label": "Crate (Small)"},
	{"id": "obj_crate_large",      "label": "Crate (Large)"},
	{"id": "obj_computer_station", "label": "Computer Station"},
	{"id": "obj_cctv_camera",      "label": "CCTV Camera"},
	{"id": "obj_plate",            "label": "Plate"},
	{"id": "obj_ball",             "label": "Ball (Physics Toy)"},
	{"id": "obj_glass_sheet",      "label": "Glass Sheet"},
	{"id": "obj_fence_post",       "label": "Fence Post"},
	{"id": "obj_fence_picket",     "label": "Fence Picket"},
	{"id": "obj_fence_rail",       "label": "Fence Rail"},
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
