extends Node3D

# CCTV Camera — placed via the Objects tool. Identified by `cam_id`,
# which a Computer Station feed picks up by string. When viewed, the
# play scene swaps the active Camera3D to the one this node owns.
#
# Per-instance fields:
#   cam_id      : String  — unique-per-map identifier. Stations switch
#                           to this cam by typing/loading the same id.
#   ptz_enabled : bool    — when true, mounted user can pan/tilt/zoom
#                           while this feed is active.

var cam_id: String = ""
var ptz_enabled: bool = false

func get_state() -> Dictionary:
	return {
		"cam_id": cam_id,
		"ptz_enabled": ptz_enabled,
	}

func apply_state(d: Dictionary) -> void:
	cam_id = String(d.get("cam_id", ""))
	ptz_enabled = bool(d.get("ptz_enabled", false))
