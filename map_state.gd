extends Node

# Autoload that ferries the in-editor map across the F9 scene swap.
# Editor writes whatever it has authored; play scene reads and applies.
# Empty heights (size 0) means "no edited map yet" — play scene falls
# back to its hardcoded flat ground.

var heights: PackedFloat32Array = PackedFloat32Array()
var grid_w: int = 0
var grid_h: int = 0

func has_map() -> bool:
	return heights.size() > 0 and grid_w > 0 and grid_h > 0

func clear() -> void:
	heights = PackedFloat32Array()
	grid_w = 0
	grid_h = 0
