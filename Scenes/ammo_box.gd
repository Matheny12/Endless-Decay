extends Area3D

@export var rifle_ammo_to_give: int = 30
@export var shotgun_ammo_to_give: int = 8

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if not multiplayer.is_server(): 
		return 
	if body.is_in_group("player"):
		if body.has_method("add_ammo"):
			body.add_ammo.rpc(rifle_ammo_to_give, shotgun_ammo_to_give)
			delete_box.rpc()

@rpc("call_local", "authority", "reliable")
func delete_box():
	queue_free()
