extends StaticBody3D

# Head hitbox child of a Dummy. Forwards hits to parent with headshot flag
# so the parent can apply the multiplier + flag the popup as a crit.

func take_damage(amount: int) -> void:
	var p: Node = get_parent()
	if p != null and p.has_method("take_damage"):
		p.call("take_damage", amount, true)
