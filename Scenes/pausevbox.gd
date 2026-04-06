extends VBoxContainer

var settings_scene = preload("res://Scenes/settings.tscn")
var settings_instance = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS 
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
func _on_continue_pressed() -> void:
	var local_player = _get_local_player()
	if local_player != null:
		local_player.sync_pause.rpc(false, 0)
	else:
		get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	owner.queue_free()

func _on_settings_pressed() -> void:
	if settings_instance == null:
		settings_instance = settings_scene.instantiate()
		add_child(settings_instance)
		if not GameEvents.request_back_to_pause.is_connected(_on_settings_back_pressed):
			GameEvents.request_back_to_pause.connect(_on_settings_back_pressed)
	self.hide()
	settings_instance.show()

func _on_settings_back_pressed():
	if settings_instance:
		settings_instance.hide()
	self.show()

func _on_quit_pressed() -> void:
	var local_player = _get_local_player()
	if local_player == null: return
	if local_player.has_method("sync_pause"):
		local_player.sync_pause.rpc(false)
	var menu_root = self
	while menu_root.get_parent() and menu_root.get_parent().name != "UI" and menu_root.get_parent() != get_tree().root:
		menu_root = menu_root.get_parent()
	menu_root.queue_free()
	if multiplayer.is_server():
		local_player.force_quit_to_everyone.rpc()
	else:
		local_player.request_quit_sequence.rpc()

func _get_local_player():
	var current_node = self
	while current_node != null and current_node != get_tree().root:
		if current_node.has_method("force_quit_to_everyone") and current_node.is_multiplayer_authority():
			return current_node
		current_node = current_node.get_parent()
	for p in get_tree().get_nodes_in_group("player"):
		if p.is_multiplayer_authority():
			return p
	return null
