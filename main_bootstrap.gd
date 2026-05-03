extends Node3D

# Attached to main.tscn root. If the player just came from the editor
# (MapState.has_map() is true), swap the hardcoded flat Ground for an
# editor_terrain instance carrying the authored heights. Otherwise
# leave the legacy ground intact so launching straight into Play from
# the menu still works.

const EDITOR_TERRAIN := preload("res://editor_terrain.gd")

func _ready() -> void:
	if not MapState.has_map():
		return
	var ground := get_node_or_null("Ground")
	if ground != null:
		ground.queue_free()
	var terrain := Node3D.new()
	terrain.set_script(EDITOR_TERRAIN)
	terrain.name = "EditorTerrain"
	add_child(terrain)
	# editor_terrain._ready already created the mesh from a zeroed
	# array; overwrite + rebuild with the real heights.
	terrain.heights = MapState.heights.duplicate()
	terrain.rebuild()
