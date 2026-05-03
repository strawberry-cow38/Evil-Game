extends RefCounted
class_name EditorEffectsRegistry

# Master list of effects available to drop into the world. Phase-1
# entries are placeholder names — actual particle/decal scenes get
# wired in once the gizmo system lands. Each entry is {id, label}.

const EFFECTS: Array = [
	{"id": "demo_cube",       "label": "Demo: Cube"},
	{"id": "fx_fire_small",   "label": "Fire (Small)"},
	{"id": "fx_fire_large",   "label": "Fire (Large)"},
	{"id": "fx_smoke_column", "label": "Smoke Column"},
	{"id": "fx_smoke_thin",   "label": "Smoke (Thin)"},
	{"id": "fx_steam",        "label": "Steam"},
	{"id": "fx_mist",         "label": "Mist"},
	{"id": "fx_dust_motes",   "label": "Dust Motes"},
	{"id": "fx_sparks",       "label": "Sparks"},
	{"id": "fx_embers",       "label": "Embers"},
	{"id": "fx_fog_volume",   "label": "Fog Volume"},
	{"id": "fx_godrays",      "label": "God Rays"},
	{"id": "fx_water_spray",  "label": "Water Spray"},
	{"id": "fx_blood_pool",   "label": "Blood Pool"},
	{"id": "fx_decal_burn",   "label": "Decal: Burn"},
	{"id": "fx_decal_crack",  "label": "Decal: Crack"},
	{"id": "fx_decal_blood",  "label": "Decal: Blood"},
	{"id": "fx_light_torch",  "label": "Light: Torch"},
	{"id": "fx_light_lamp",   "label": "Light: Lamp"},
	{"id": "fx_light_neon",   "label": "Light: Neon"},
	{"id": "fx_sound_ambient","label": "Sound: Ambient"},
	{"id": "fx_sound_loop",   "label": "Sound: Loop"},
	{"id": "fx_wind_zone",    "label": "Wind Zone"},
	{"id": "fx_radiation",    "label": "Radiation Zone"},
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
