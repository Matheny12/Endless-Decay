extends Node3D

func _on_area_3d_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		print("Player detected!")
		if "rifle_reserve" in body:
			body.rifle_reserve += 30
		if "shotgun_reserve" in body:
			body.shotgun_reserve += 8
		if get_parent():
			get_parent().queue_free()
		else:
			queue_free()
