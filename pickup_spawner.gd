extends Node3D

const Pickup = preload("res://pickup.gd")

# (item_id, count, position)
const SPAWNS: Array = []

func _ready() -> void:
	for entry in SPAWNS:
		var p := Area3D.new()
		p.set_script(Pickup)
		p.item_id = entry[0]
		p.count = entry[1]
		p.position = entry[2]
		add_child(p)
