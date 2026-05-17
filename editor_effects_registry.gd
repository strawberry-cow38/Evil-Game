extends RefCounted

# Master list of effects available to drop into the world. Phase-1
# entries are placeholder names — actual particle/decal scenes get
# wired in once the gizmo system lands. Each entry is {id, label}.

const EFFECTS: Array = [
	{"id": "demo_cube", "label": "Demo: Cube"},
]

static func all_sorted() -> Array:
	var out: Array = EFFECTS.duplicate()
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
