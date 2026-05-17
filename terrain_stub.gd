extends Node3D

# Flat-ground stand-in that satisfies editor_fences.gd's terrain contract
# (just sample_height). Used by fence_usage_demo so we don't need the
# real terrain pipeline.

func sample_height(_world: Vector3) -> float:
	return 0.0
