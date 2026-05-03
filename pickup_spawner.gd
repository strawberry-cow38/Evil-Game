extends Node3D

const Pickup = preload("res://pickup.gd")

# (item_id, count, position)
const SPAWNS: Array = [
	["apple",      1, Vector3( 4.0, 0.3,  3.0)],
	["apple",      1, Vector3( 6.5, 0.3,  3.5)],
	["banana",     1, Vector3(-3.0, 0.3,  2.0)],
	["banana",     1, Vector3(-3.8, 0.3,  4.5)],
	["orange",     1, Vector3( 8.0, 0.3, -4.0)],
	["grape",      1, Vector3(-6.0, 0.3, -1.0)],
	["grape",      1, Vector3(-7.2, 0.3, -2.5)],
	["grape",      1, Vector3(-8.0, 0.3, -1.5)],
	["lemon",      1, Vector3( 2.0, 0.3, -7.0)],
	["strawberry", 1, Vector3( 0.0, 0.3,  9.0)],
	["strawberry", 1, Vector3( 1.2, 0.3,  9.5)],
	["pineapple",  1, Vector3(-9.0, 0.4,  6.0)],
	["watermelon", 1, Vector3(10.0, 0.5, -8.0)],
	["watermelon", 1, Vector3(12.0, 0.5,  6.0)],
]

func _ready() -> void:
	for entry in SPAWNS:
		var p := Area3D.new()
		p.set_script(Pickup)
		p.item_id = entry[0]
		p.count = entry[1]
		p.position = entry[2]
		add_child(p)
