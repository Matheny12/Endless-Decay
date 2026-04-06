extends Node3D

func _on_area_3d_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		body.rifle_reserve += 30
		body.shotgun_reserve += 8
		queue_free()
