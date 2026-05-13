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

	"akm":    {"name": "AKM",          "weight": 3.50, "value":  350, "color": Color(0.45, 0.30, 0.18), "kind": "weapon", "desc": "Soviet 7.62×39 assault rifle. Reliable, harsh climb.", "slots": [{"id":"Optic","tag":"ak_optic"},{"id":"Muzzle","tag":"ak_muzzle"},{"id":"Mag","tag":"ak_mag"}]},
	"sks":    {"name": "SKS",          "weight": 3.85, "value":  260, "color": Color(0.50, 0.35, 0.20), "kind": "weapon", "desc": "Soviet 7.62×39 carbine. Semi-auto only, 10-round internal mag.", "slots": [{"id":"Optic","tag":"ak_optic"},{"id":"Muzzle","tag":"ak_muzzle"}]},
	"m16a2":  {"name": "M16A2",        "weight": 3.40, "value":  420, "color": Color(0.20, 0.20, 0.22), "kind": "weapon", "desc": "5.56 NATO. Burst-capable. Cleaner than the AK.", "slots": [{"id":"Optic","tag":"m16_optic"},{"id":"Muzzle","tag":"m16_muzzle"},{"id":"Mag","tag":"m16_mag"}]},
	"aug":    {"name": "Steyr AUG",    "weight": 3.60, "value":  460, "color": Color(0.30, 0.40, 0.22), "kind": "weapon", "desc": "Austrian bullpup 5.56. Built-in 1.5× optic. Smooth, flat shooter.", "slots": [{"id":"Muzzle","tag":"m16_muzzle"},{"id":"Mag","tag":"aug_mag"}]},
	"bizon":  {"name": "PP-19 Bizon",  "weight": 2.50, "value":  280, "color": Color(0.30, 0.32, 0.30), "kind": "weapon", "desc": "9mm SMG with helical 64-round mag. Compact.", "slots": [{"id":"Optic","tag":"bizon_optic"},{"id":"Muzzle","tag":"bizon_muzzle"}]},
	"mp5sd":  {"name": "MP5",          "weight": 3.00, "value":  520, "color": Color(0.15, 0.15, 0.17), "kind": "weapon", "desc": "9mm roller-delayed SMG. Tight grouping, classic chatter.", "slots": [{"id":"Optic","tag":"mp5_optic"},{"id":"Mag","tag":"mp5_mag"}]},
	"m249":   {"name": "M249 SAW",     "weight": 7.50, "value":  900, "color": Color(0.28, 0.28, 0.25), "kind": "weapon", "desc": "5.56 belt-fed LMG. 100-round box. Heavy.", "slots": [{"id":"Optic","tag":"m249_optic"},{"id":"Bipod","tag":"lmg_bipod"}]},
	"m60":    {"name": "M60",          "weight": 10.50,"value": 1100, "color": Color(0.22, 0.22, 0.20), "kind": "weapon", "desc": "7.62 belt-fed LMG. Slow cyclic, devastating.", "slots": [{"id":"Optic","tag":"m60_optic"},{"id":"Bipod","tag":"lmg_bipod"}]},
	"minigun":{"name": "M134 Minigun", "weight": 30.00,"value": 4500, "color": Color(0.18, 0.18, 0.20), "kind": "weapon", "desc": "6-barrel 7.62 NATO Gatling. 1500 RPM cyclic. 300-round link box. Soft per-round kick, but spread is awful.", "slots": [{"id":"Bipod","tag":"lmg_bipod"}]},
	"mgl":    {"name": "Milkor MGL",   "weight": 5.50, "value":  800, "color": Color(0.18, 0.30, 0.20), "kind": "weapon", "desc": "40mm 6-round revolving grenade launcher. Goes boom.", "slots": [{"id":"Optic","tag":"mgl_optic"}]},
	"makarov":{"name": "PM Makarov",   "weight": 0.66, "value":  120, "color": Color(0.18, 0.18, 0.20), "kind": "weapon", "desc": "Soviet 9×18 service pistol. 8-round mag.", "slots": [{"id":"Muzzle","tag":"makarov_muzzle"}]},
	"ppsh41": {"name": "PPSh-41",      "weight": 4.00, "value":  260, "color": Color(0.40, 0.28, 0.18), "kind": "weapon", "desc": "Soviet WW2 SMG. 71-round drum, 7.62×25 Tokarev, blistering cyclic. Sloppy and loud.", "slots": []},
	"m1911":  {"name": "Colt M1911",   "weight": 1.10, "value":  200, "color": Color(0.18, 0.16, 0.14), "kind": "weapon", "desc": "Classic .45 ACP service pistol. 7-round mag. Heavy round, single-action.", "slots": []},
	"thompson":{"name": "Thompson",    "weight": 4.80, "value":  320, "color": Color(0.30, 0.20, 0.12), "kind": "weapon", "desc": "American WW2 SMG. .45 ACP, 30-round stick mag. Heavy, hard-hitting, classic.", "slots": []},
	"shotgun_combat": {"name": "SPAS-12",        "weight": 4.20, "value": 460, "color": Color(0.18, 0.16, 0.14), "kind": "weapon", "desc": "Italian Franchi SPAS-12. Semi-auto 12 gauge, 8-round tube, shell-by-shell reload. Folding stock, distinctive vent rib.", "slots": [{"id":"Optic","tag":"spas_optic"},{"id":"Muzzle","tag":"spas_muzzle"}]},
	"usas12":         {"name": "USAS-12",        "weight": 5.45, "value": 880, "color": Color(0.16, 0.16, 0.18), "kind": "weapon", "desc": "Korean Daewoo selective-fire 12 gauge. 20-round drum, semi/auto, gas-operated. Heavy block, real shoulder-shove on full auto.", "slots": []},
	"p90":            {"name": "FN P90",         "weight": 2.70, "value": 480, "color": Color(0.18, 0.18, 0.18), "kind": "weapon", "desc": "Bullpup PDW. 50-round top-mount mag in 5.7×28mm. High cyclic, flat recoil.", "slots": [{"id":"Optic","tag":"p90_optic"},{"id":"Muzzle","tag":"p90_muzzle"}]},
	"m700":           {"name": "Remington M700", "weight": 4.50, "value": 700, "color": Color(0.22, 0.16, 0.10), "kind": "weapon", "desc": "Bolt-action 7.62 NATO sniper. 5-round internal mag. 6× scope. Surgical.", "slots": [{"id":"Muzzle","tag":"762nato_muzzle"}]},
	"fal":            {"name": "FN FAL",         "weight": 4.30, "value": 620, "color": Color(0.18, 0.14, 0.10), "kind": "weapon", "desc": "Belgian battle rifle. 7.62 NATO, 20-round mag, semi/auto. The right arm of the free world.", "slots": [{"id":"Optic","tag":"fal_optic"},{"id":"Muzzle","tag":"762nato_muzzle"},{"id":"Mag","tag":"fal_mag"}]},
	"g3":             {"name": "HK G3",          "weight": 4.40, "value": 600, "color": Color(0.10, 0.10, 0.11), "kind": "weapon", "desc": "German roller-delayed battle rifle. 7.62 NATO, 20-round mag, semi/auto. Stamped, brutal, reliable.", "slots": [{"id":"Optic","tag":"g3_optic"},{"id":"Muzzle","tag":"762nato_muzzle"}]},
	"m14":            {"name": "M14",            "weight": 4.50, "value": 640, "color": Color(0.30, 0.20, 0.10), "kind": "weapon", "desc": "American 7.62 NATO service rifle. 20-round mag, semi/auto. Walnut and steel — climbs hard on full-auto.", "slots": [{"id":"Optic","tag":"m14_optic"},{"id":"Muzzle","tag":"762nato_muzzle"}]},
	"mac10":          {"name": "MAC-10",          "weight": 2.80, "value": 240, "color": Color(0.10, 0.10, 0.10), "kind": "weapon", "desc": "Compact .45 ACP SMG. 30-round mag, 1100 RPM, full-auto only. Spits the mag in two seconds.", "slots": []},
	"uzi":            {"name": "Uzi",             "weight": 3.50, "value": 380, "color": Color(0.20, 0.20, 0.20), "kind": "weapon", "desc": "Israeli 9mm SMG. 32-round mag, full-auto. Stamped, reliable, side-to-side drift.", "slots": []},
	"m1903":          {"name": "1903 Springfield","weight": 3.95, "value": 520, "color": Color(0.32, 0.18, 0.08), "kind": "weapon", "desc": "American bolt-action in .30-06. 5-round internal mag. Scope rail empty by default.", "slots": [{"id":"Optic","tag":"m1903_optic"}]},
	"garand":         {"name": "M1 Garand",       "weight": 4.30, "value": 580, "color": Color(0.28, 0.18, 0.08), "kind": "weapon", "desc": "Semi-auto .30-06 service rifle. 8-round en-bloc clip. Pings.", "slots": []},
	"bar":            {"name": "BAR",             "weight": 7.20, "value": 720, "color": Color(0.18, 0.14, 0.10), "kind": "weapon", "desc": "Browning Automatic Rifle. .30-06, 20-round mag, semi/auto. Slow cyclic, brutal climb.", "slots": []},
	"g11":            {"name": "HK G11",          "weight": 3.65, "value": 820, "color": Color(0.76, 0.74, 0.70), "kind": "weapon", "desc": "German caseless prototype. 50-round 4.7×33mm mag. Hyperburst dumps 3 rounds at 2160 RPM before the recoil arrives.", "slots": []},
	"ammo_47x33":     {"name": "4.7×33mm Caseless","weight": 0.008, "value":  3, "color": Color(0.55, 0.40, 0.20), "kind": "ammo", "damage": 36, "falloff_start": 140.0, "falloff_end": 360.0, "damage_min": 22, "desc": "Caseless rifle round. Polymer-bound propellant block, no brass to eject. Feeds the G11."},
	"lever_4570":     {"name": "Marlin 1895",     "weight": 3.40, "value": 540, "color": Color(0.30, 0.18, 0.08), "kind": "weapon", "desc": "Lever-action .45-70 rifle. 6-round tube, big-bore thump. Cowboy gun, modern teeth.", "slots": []},
	"pistol_4570":    {"name": "Hand Cannon",     "weight": 1.80, "value": 320, "color": Color(0.20, 0.16, 0.10), "kind": "weapon", "desc": "Single-shot break-action pistol in .45-70. One round, one apocalypse, then reload.", "slots": []},
	"python":         {"name": "Colt Python",     "weight": 1.10, "value": 380, "color": Color(0.18, 0.18, 0.20), "kind": "weapon", "desc": ".357 Magnum revolver. 6-shot cylinder, swing-out reload. Snake gun.", "slots": []},
	"ks23":           {"name": "KS-23",           "weight": 4.10, "value": 540, "color": Color(0.18, 0.18, 0.20), "kind": "weapon", "desc": "Soviet 23mm pump-action shotgun. 4-round tube. Each shell wallops 16 pellets — devastating up close.", "slots": []},
	"stg57":          {"name": "STG-57",         "weight": 5.55, "value": 580, "color": Color(0.16, 0.18, 0.14), "kind": "weapon", "desc": "Swiss SIG SG 510 battle rifle. Heavy, precise, 24-round mag in 7.5×55 Swiss GP11. Mass tames the kick.", "slots": []},

	"att_m1903_scope":  {"name": "1903 Hunting Scope",  "weight": 0.50, "value": 280, "color": Color(0.18, 0.14, 0.08), "kind": "attachment", "fits_tag": "m1903_optic", "mods": {"scope": true, "ads_fov": 14.0}, "desc": "Period hunting scope for the 1903. Long eye relief, narrow field. Surgical."},

	"att_ak_scope":    {"name": "AK Scope",          "weight": 0.45, "value": 220, "color": Color(0.20, 0.20, 0.22), "kind": "attachment", "fits_tag": "ak_optic",  "mods": {"scope": true, "ads_fov": 25.0}, "desc": "Side-rail optic for the AK. Standard reticle, no laser."},
	"att_ak_silencer": {"name": "7.62×39 Silencer",   "weight": 0.40, "value": 180, "color": Color(0.10, 0.10, 0.10), "kind": "attachment", "fits_tag": "ak_muzzle", "mods": {"velocity_mult": 0.80, "damage_mult": 0.80, "bloom_mult": 1.10}, "desc": "Threaded muzzle can. Quieter shots — but slower, weaker, sloppier."},
	"att_ak_mag_40":   {"name": "AK 40rd Magazine",   "weight": 0.55, "value": 150, "color": Color(0.30, 0.22, 0.14), "kind": "attachment", "fits_tag": "ak_mag",    "mods": {"mag_size": 40}, "desc": "Extended 40-round AK magazine."},
	"att_ak_drum_75":  {"name": "AK 75rd Drum",       "weight": 1.50, "value": 320, "color": Color(0.32, 0.24, 0.16), "kind": "attachment", "fits_tag": "ak_mag",    "mods": {"mag_size": 75}, "desc": "75-round drum magazine for the AK. Heavy, awkward, glorious."},

	"att_m16_scope":     {"name": "M16 4×20 Scope",      "weight": 0.40, "value": 240, "color": Color(0.20, 0.20, 0.22), "kind": "attachment", "fits_tag": "m16_optic",  "mods": {"scope": true, "ads_fov": 18.0}, "desc": "Carry-handle 4×20 optic for the M16. Black-ringed reticle."},
	"att_m16_silencer":  {"name": "5.56×45 Silencer",    "weight": 0.36, "value": 200, "color": Color(0.10, 0.10, 0.10), "kind": "attachment", "fits_tag": "m16_muzzle", "mods": {"velocity_mult": 0.80, "damage_mult": 0.80, "bloom_mult": 1.10}, "desc": "5.56 muzzle can. Quieter, but slower, weaker, sloppier."},
	"att_m16_mag_40":    {"name": "M16 40rd Magazine",   "weight": 0.50, "value": 160, "color": Color(0.18, 0.18, 0.20), "kind": "attachment", "fits_tag": "m16_mag",    "mods": {"mag_size": 40}, "desc": "Extended 40-round STANAG."},
	"att_m16_drum_90":   {"name": "M16 90rd Drum",       "weight": 1.40, "value": 340, "color": Color(0.18, 0.18, 0.20), "kind": "attachment", "fits_tag": "m16_mag",    "mods": {"mag_size": 90}, "desc": "90-round drum mag. Bulky, but feeds forever."},
	"att_aug_mag_40":    {"name": "AUG 40rd Magazine",   "weight": 0.55, "value": 170, "color": Color(0.30, 0.40, 0.22), "kind": "attachment", "fits_tag": "aug_mag",    "mods": {"mag_size": 40}, "desc": "Translucent 40-round AUG magazine. Bullpup-fed."},

	"att_762nato_silencer": {"name": "7.62 NATO Silencer", "weight": 0.55, "value": 260, "color": Color(0.10, 0.10, 0.10), "kind": "attachment", "fits_tag": "762nato_muzzle", "mods": {"velocity_mult": 0.80, "damage_mult": 0.80, "bloom_mult": 1.10}, "desc": "Heavy 7.62 NATO can. Quieter, but slower, weaker, sloppier. Fits the M700 and FAL."},
	"att_fal_scope":   {"name": "FAL 4× Scope",       "weight": 0.45, "value": 250, "color": Color(0.20, 0.20, 0.22), "kind": "attachment", "fits_tag": "fal_optic", "mods": {"scope": true, "ads_fov": 18.0}, "desc": "4× optic on a top-cover dovetail mount. Battle-rifle eyes."},
	"att_fal_mag_30":  {"name": "FAL 30rd Magazine",  "weight": 0.70, "value": 170, "color": Color(0.18, 0.14, 0.10), "kind": "attachment", "fits_tag": "fal_mag",   "mods": {"mag_size": 30}, "desc": "Extended 30-round FAL magazine."},

	"att_spas_choke":   {"name": "SPAS Choke Tube",     "weight": 0.20, "value": 120, "color": Color(0.18, 0.18, 0.18), "kind": "attachment", "fits_tag": "spas_muzzle", "mods": {"pellet_spread_mult": 0.50}, "desc": "Threaded choke for the SPAS-12. Tightens buckshot patterns. Slugs don't care."},

	"att_lmg_bipod":    {"name": "LMG Bipod",           "weight": 0.80, "value": 180, "color": Color(0.20, 0.20, 0.20), "kind": "attachment", "fits_tag": "lmg_bipod", "mods": {"recoil_crouch_mult": 0.50}, "desc": "Folding bipod. Half recoil while crouched, fits the M249 and M60."},

	"ammo_762x39":  {"name": "7.62×39mm",       "weight": 0.016, "value":  1, "color": Color(0.85, 0.65, 0.20), "kind": "ammo", "damage": 50, "falloff_start": 100.0, "falloff_end": 300.0, "damage_min": 30, "desc": "Soviet intermediate cartridge. Feeds the AKM."},
	"ammo_556nato": {"name": "5.56×45mm NATO",  "weight": 0.012, "value":  1, "color": Color(0.90, 0.78, 0.40), "kind": "ammo", "damage": 40, "falloff_start": 120.0, "falloff_end": 350.0, "damage_min": 22, "desc": "NATO standard. Feeds the M16A2 and M249."},
	"ammo_9mm":     {"name": "9×19mm",          "weight": 0.012, "value":  1, "color": Color(0.78, 0.72, 0.55), "kind": "ammo", "damage": 30, "falloff_start":  30.0, "falloff_end": 100.0, "damage_min": 12, "desc": "Pistol cartridge. Feeds the Bizon and MP5SD."},
	"ammo_57x28":   {"name": "5.7×28mm",        "weight": 0.011, "value":  2, "color": Color(0.85, 0.78, 0.42), "kind": "ammo", "damage": 35, "falloff_start":  60.0, "falloff_end": 180.0, "damage_min": 18, "desc": "High-velocity PDW round. Feeds the P90. Better range than 9mm."},
	"ammo_9x18":    {"name": "9×18mm Makarov",  "weight": 0.010, "value":  1, "color": Color(0.72, 0.66, 0.50), "kind": "ammo", "damage": 28, "falloff_start":  25.0, "falloff_end":  80.0, "damage_min": 10, "desc": "Soviet pistol round. Feeds the Makarov."},
	"ammo_762x25":  {"name": "7.62×25mm Tokarev", "weight": 0.011, "value":  1, "color": Color(0.85, 0.72, 0.30), "kind": "ammo", "damage": 32, "falloff_start":  40.0, "falloff_end": 130.0, "damage_min": 14, "desc": "Soviet bottlenecked pistol round. Feeds the PPSh-41. Hot and fast for a pistol cartridge."},
	"ammo_45acp":   {"name": ".45 ACP",         "weight": 0.015, "value":  1, "color": Color(0.78, 0.62, 0.32), "kind": "ammo", "damage": 45, "falloff_start":  20.0, "falloff_end":  70.0, "damage_min": 18, "desc": "Big slow pistol round. Hits hard up close, drops off fast. Feeds the 1911 and Thompson."},
	"ammo_75x55":   {"name": "7.5×55mm Swiss",  "weight": 0.024, "value":  3, "color": Color(0.82, 0.58, 0.20), "kind": "ammo", "damage": 58, "falloff_start": 220.0, "falloff_end": 520.0, "damage_min": 40, "desc": "Swiss GP11 service round. Niche, expensive, surgically accurate. Feeds the STG-57."},
	"ammo_762nato": {"name": "7.62×51mm NATO",  "weight": 0.025, "value":  2, "color": Color(0.80, 0.55, 0.18), "kind": "ammo", "damage": 55, "falloff_start": 200.0, "falloff_end": 500.0, "damage_min": 38, "desc": "Full-power NATO rifle round. Feeds the M60."},
	"ammo_40mm":    {"name": "40mm Grenade",    "weight": 0.230, "value": 15, "color": Color(0.30, 0.55, 0.30), "kind": "ammo", "damage":  0, "falloff_start": 9999.0, "falloff_end": 9999.0, "damage_min": 0, "desc": "Low-velocity 40mm HE grenade. Feeds the MGL."},
	"ammo_12ga":      {"name": "12 Gauge Buckshot", "weight": 0.045, "value":  3, "color": Color(0.65, 0.10, 0.10), "kind": "ammo", "damage": 18, "falloff_start":  12.0, "falloff_end":  50.0, "damage_min":  6, "pellets": 8, "pellet_spread_deg": 2.2, "desc": "12 gauge buckshot. 8 pellets, devastating up close, falls off fast."},
	"ammo_12ga_slug": {"name": "12 Gauge Slug",     "weight": 0.052, "value":  5, "color": Color(0.55, 0.40, 0.10), "kind": "ammo", "damage": 95, "falloff_start":  40.0, "falloff_end": 120.0, "damage_min": 55, "desc": "12 gauge solid slug. Single projectile, hits like a truck at range."},
	"ammo_3006":    {"name": ".30-06 Springfield", "weight": 0.027, "value":  3, "color": Color(0.78, 0.50, 0.16), "kind": "ammo", "damage": 60, "falloff_start": 220.0, "falloff_end": 540.0, "damage_min": 42, "desc": "Classic American full-power rifle round. Feeds the M1903, Garand, and BAR."},
	"ammo_4570":    {"name": ".45-70 Government", "weight": 0.038, "value":  4, "color": Color(0.78, 0.45, 0.14), "kind": "ammo", "damage": 95, "falloff_start": 100.0, "falloff_end": 320.0, "damage_min": 55, "desc": "Old-school big-bore lever-gun round. Hits like a freight train, drops off past 300m."},
	"ammo_357":     {"name": ".357 Magnum",       "weight": 0.013, "value":  2, "color": Color(0.85, 0.65, 0.30), "kind": "ammo", "damage": 50, "falloff_start":  40.0, "falloff_end": 130.0, "damage_min": 22, "desc": "Magnum revolver round. Stout thump, real reach for a sidearm."},
	"ammo_23x75":   {"name": "23×75mm Shell",      "weight": 0.080, "value":  8, "color": Color(0.30, 0.10, 0.10), "kind": "ammo", "damage": 26, "falloff_start":  14.0, "falloff_end":  55.0, "damage_min": 10, "pellets": 16, "pellet_spread_deg": 2.4, "desc": "Soviet 23mm shotgun shell. 16 heavy pellets — close-range obliteration. Feeds the KS-23."},
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

static func attachment_fits_tag(id: String) -> String:
	return String(DEFS.get(id, {}).get("fits_tag", ""))

static func attachment_mods(id: String) -> Dictionary:
	return DEFS.get(id, {}).get("mods", {})

static func is_attachment(id: String) -> bool:
	return item_kind(id) == "attachment"

static func ammo_damage(id: String) -> int:
	return int(DEFS.get(id, {}).get("damage", 0))

static func ammo_pellets(id: String) -> int:
	return int(DEFS.get(id, {}).get("pellets", 1))

static func ammo_pellet_spread_deg(id: String) -> float:
	return float(DEFS.get(id, {}).get("pellet_spread_deg", 0.0))

# Range-attenuated damage. Linear interp between full damage (≤ falloff_start)
# and damage_min (≥ falloff_end). Caliber-specific values live on the ammo def.
static func ammo_damage_at(id: String, distance: float) -> int:
	var d: Dictionary = DEFS.get(id, {})
	var base: float = float(d.get("damage", 0))
	if base <= 0.0:
		return 0
	var fs: float = float(d.get("falloff_start", 50.0))
	var fe: float = float(d.get("falloff_end", 200.0))
	var dmin: float = float(d.get("damage_min", base * 0.4))
	if distance <= fs:
		return int(round(base))
	if distance >= fe or fe <= fs:
		return int(round(dmin))
	var t: float = (distance - fs) / (fe - fs)
	return int(round(lerpf(base, dmin, t)))

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
