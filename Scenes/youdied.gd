extends VBoxContainer

@onready var score_list = $ScoreboardList

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_quit_to_menu_pressed() -> void:
	multiplayer.multiplayer_peer = null
	get_tree().change_scene_to_file("res://Scenes/menu.tscn")
