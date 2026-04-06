extends VBoxContainer

var settings_instance = null
var settings_scene = preload("res://Scenes/settings.tscn")
var ws: WebSocketPeer

func _ready() -> void:
	GlobalStats.map_name = "Neighborhood"
	GlobalStats.game_difficulty = "Normal"
	ws = GlobalStats.ws

func _on_host_pressed() -> void:
	if ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		print("WebSocket not connected to Render")
		return
	GlobalStats.my_peer_id = 1 
	GlobalStats.host_peer_id = 1
	var data = {
		"type": "host",
		"peer_id": GlobalStats.my_peer_id,
		"room_id": GlobalStats.hosted_lobby_id,
		"name": GlobalStats.player_name,
		"map": GlobalStats.map_name,
		"port": GlobalStats.current_port,
		"difficulty": GlobalStats.game_difficulty
	}
	ws.send_text(JSON.stringify(data))
	var mp_peer = WebSocketMultiplayerPeer.new()
	var err = mp_peer.create_server(GlobalStats.current_port)
	if err == OK:
		multiplayer.multiplayer_peer = mp_peer
		print("Local Host Server started on: ", GlobalStats.current_port)
	else:
		print("Server Port Error: ", err)

func _on_difficulty_item_selected(index: int) -> void:
	match index:
		0: GlobalStats.game_difficulty = "Easy"
		1: GlobalStats.game_difficulty = "Normal"
		2: GlobalStats.game_difficulty = "Hard"

func _on_map_2_item_selected(index: int) -> void:
	match index:
		0: GlobalStats.map_name = "Neighborhood"
		1: GlobalStats.map_name = "Desert"

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

func _on_quit_to_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/menu.tscn")
