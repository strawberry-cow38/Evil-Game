extends RefCounted

# Tabular row formatter shared by the player inventory menu and the
# container transfer menu. Renders one entry dict (from inventory.entries()
# or crate.entries()) into a fixed-width string with NAME / QTY / QUALITY /
# COND / WEIGHT / VALUE columns. Pair with make_mono_font() so the columns
# actually align in the UI; otherwise the proportional font ruins the grid.

const Items = preload("res://items.gd")

const COLUMNS: Array = [
	{"key": "name",    "label": "NAME",    "width": 22, "align": "L"},
	{"key": "qty",     "label": "QTY",     "width": 5,  "align": "R"},
	{"key": "quality", "label": "QUALITY", "width": 9,  "align": "L"},
	{"key": "cond",    "label": "COND",    "width": 5,  "align": "R"},
	{"key": "weight",  "label": "WEIGHT",  "width": 9,  "align": "R"},
	{"key": "value",   "label": "VALUE",   "width": 6,  "align": "R"},
]

# Two-space separator between columns reads better than a single space —
# easy to scan vertically without losing the row identity.
const SEP := "  "

# Build a SystemFont that picks the first installed monospace face. Falls
# through several common Linux/Windows/macOS names so the columns align on
# any host without shipping a font asset.
static func make_mono_font() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Liberation Mono", "DejaVu Sans Mono", "Menlo", "Monaco",
		"Consolas", "Courier New", "Courier", "Monospace",
	])
	return f

static func header_text() -> String:
	var parts: Array = []
	for c in COLUMNS:
		var s: String = String(c.label)
		var w: int = int(c.width)
		if String(c.align) == "R":
			parts.append(s.lpad(w))
		else:
			parts.append(s.rpad(w))
	return SEP.join(parts)

# Width of one rendered row in characters — header + every row will be
# this wide. Useful for sizing the Label that holds the header so it
# matches the list width with the same font.
static func row_char_width() -> int:
	var n: int = 0
	for c in COLUMNS:
		n += int(c.width)
	return n + SEP.length() * (COLUMNS.size() - 1)

# entry: one entry dict (id, name, kind, count, is_instance, quality,
# condition, weight_total, value_each, ...).
# suffix: appended inside the Name cell before padding — used by the
# player menu to tag the equipped row with " [E]".
static func row_text(entry: Dictionary, suffix: String = "") -> String:
	var is_inst: bool = bool(entry.get("is_instance", false))
	var name: String = String(entry.get("name", ""))
	if suffix != "":
		name += suffix
	var qty: String = ""
	if not is_inst:
		qty = "x%d" % int(entry.get("count", 1))
	var quality: String = ""
	var cond: String = ""
	if is_inst:
		quality = Items.quality_name(int(entry.get("quality", Items.QUALITY_NORMAL)))
		cond = "%d%%" % int(round(float(entry.get("condition", 1.0)) * 100.0))
	var weight: String = "%.2f kg" % float(entry.get("weight_total", 0.0))
	var value: String = "¢%d" % int(entry.get("value_each", 0))
	var values: Dictionary = {
		"name": name, "qty": qty, "quality": quality,
		"cond": cond, "weight": weight, "value": value,
	}
	var parts: Array = []
	for c2 in COLUMNS:
		var k: String = String(c2.key)
		var v: String = String(values.get(k, ""))
		var w: int = int(c2.width)
		if v.length() > w:
			v = v.substr(0, w)
		if String(c2.align) == "R":
			parts.append(v.lpad(w))
		else:
			parts.append(v.rpad(w))
	return SEP.join(parts)
