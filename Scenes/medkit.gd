extends Node3D

func _on_area_3d_body_entered(body: Node3D) -> void:
	if "player_health" in body:
		if body.player_health < body.MAX_PLAYER_HEALTH:
			body.player_health = min(body.player_health + 20, body.MAX_PLAYER_HEALTH)
			queue_free()
