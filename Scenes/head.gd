extends Area3D

signal shotgun_shot(dam)
signal rifle_shot(dam)

func shotgun_hit(damage: float):
	emit_signal("shotgun_shot", damage)
	
func rifle_hit(damage: float):
	emit_signal("rifle_shot", damage)
