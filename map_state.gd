extends Node

# Autoload that ferries the in-editor map across the F9 scene swap.
# Editor writes whatever it has authored; play scene reads and applies.
# Empty heights (size 0) means "no edited map yet" — play scene falls
# back to its hardcoded flat ground.

var heights: PackedFloat32Array = PackedFloat32Array()
var grid_w: int = 0
var grid_h: int = 0
# Player spawn points authored in the editor. Empty = play scene falls
# back to its hardcoded spawn.
var player_spawns: Array[Vector3] = []
# Placed props authored in the editor. Each entry:
#   { "kind": "effect"|"object", "id": String, "xform": Transform3D }
# Play scene rebuilds the catalog content per entry and applies xform.
var placed_props: Array = []
# Item-spawn tables authored in the editor. Each entry:
#   { "id": String, "name": String, "color": Color,
#     "entries": Array[ { "id": String, "weight": float } ] }
# A "nothing" entry id means "roll-this-and-no-loot-spawns".
var item_tables: Array = []
# Placed item-spawn cubes. Each entry: { "table_id": String, "pos": Vector3 }.
# Play scene rolls the referenced table per entry to drop a single pickup.
var item_spawn_points: Array = []
# Actor presets authored in the editor. Each entry mirrors
# editor_actor_tables_panel's preset shape (name/color/actor_id/hp/level/
# weapon/drop_table_id/xp/regen/enemy/clothing). Play scene reads these
# when bootstrapping an actor spawn.
var actor_tables: Array = []
# Placed actor-spawn cubes. Each entry: { "table_id": String, "pos": Vector3 }.
# Play scene rolls clothing per slot and instantiates the actor of the
# preset's actor_id at this position.
var actor_spawn_points: Array = []
# Sky/sun/ambient state authored via Environment → Lighting. Empty dict
# = play scene uses main.tscn's hardcoded defaults. See
# editor_lighting_panel.gd DEFAULTS for key list.
var lighting: Dictionary = {}
# Roads authored via Environment → Roads. Each entry:
#   { "id": String, "nodes": Array[ {pos:Vector3, in_tangent:Vector3,
#     out_tangent:Vector3, ignore_terrain:bool} ] }
# Empty array = no roads, play scene draws nothing.
var roads: Array = []

func has_map() -> bool:
	return heights.size() > 0 and grid_w > 0 and grid_h > 0

func clear() -> void:
	heights = PackedFloat32Array()
	grid_w = 0
	grid_h = 0
	player_spawns.clear()
	placed_props.clear()
	item_tables.clear()
	item_spawn_points.clear()
	actor_tables.clear()
	actor_spawn_points.clear()
	lighting.clear()
	roads.clear()

func random_player_spawn() -> Vector3:
	if player_spawns.is_empty():
		return Vector3.ZERO
	return player_spawns[randi() % player_spawns.size()]
