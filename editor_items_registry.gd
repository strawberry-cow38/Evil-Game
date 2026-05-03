extends RefCounted

# Pulls every item id from items.gd plus a synthetic "nothing" entry
# (used by item-spawn tables to model "roll-this-and-no-loot-drops").
# Mirrors the effects/objects registry shape so the picker panel can
# stay generic.

const ITEMS := preload("res://items.gd")

const NOTHING_ID := "nothing"
const NOTHING_LABEL := "Nothing"
const NOTHING_COLOR := Color(0.4, 0.4, 0.4, 1.0)

static func all_sorted() -> Array:
	var out: Array = []
	out.append({"id": NOTHING_ID, "label": NOTHING_LABEL})
	var ids: Array = ITEMS.DEFS.keys()
	ids.sort()
	for id in ids:
		out.append({
			"id": String(id),
			"label": String(ITEMS.item_name(id)),
		})
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

static func label_for(id: String) -> String:
	if id == NOTHING_ID:
		return NOTHING_LABEL
	return ITEMS.item_name(id)
