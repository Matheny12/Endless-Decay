extends Area3D

@export var damage := 1

signal body_part_hit(dam)
# Called when the node enters the scene tree for the first time.

func hit():
	emit_signal("body_part_hit", damage)
