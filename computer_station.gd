extends Node3D

# Computer Station — placed via the Objects tool. At runtime, player
# walks within `mount_radius`, presses E, and switches into a CCTV
# feed UI driven by this station's per-instance camera list. F exits.
#
# Per-instance fields (mirrored through MapState so they survive save
# / load and F9 → play):
#   pre_added_cams : Array[String]  — IDs preloaded into the cam list
#   allow_add      : bool           — false locks the "Add Camera" box
#
# The editor wireframe box exposes these via the object-props panel.

var pre_added_cams: Array = []
var allow_add: bool = true
# Mount-prompt + mount radius are runtime knobs. Editor doesn't touch
# them — they exist here so the play-scene code has a single source.
var mount_radius: float = 1.8

func get_state() -> Dictionary:
	return {
		"pre_added_cams": pre_added_cams.duplicate(),
		"allow_add": allow_add,
	}

func apply_state(d: Dictionary) -> void:
	# Per-instance values restored from MapState. Arrays come through
	# as Variant-typed Array; copy into a fresh Array[String] so later
	# code can rely on the element type.
	pre_added_cams.clear()
	for c in d.get("pre_added_cams", []):
		pre_added_cams.append(String(c))
	allow_add = bool(d.get("allow_add", true))
