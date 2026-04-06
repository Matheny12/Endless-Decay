extends VBoxContainer

@onready var ip_label = $IPLabel
@onready var player_list = $ScrollContainer/PlayerList
@onready var start_button = $StartButton

var settings_instance = null
var settings_scene = preload("res://Scenes/settings.tscn")
var ws: WebSocketPeer
var is_host = false

func _ready() -> void:
	ws = GlobalStats.ws
	if not GlobalStats.rooms_received.is_connected(update_player_list):
		GlobalStats.rooms_received.connect(update_player_list)
		
	if GlobalStats.my_peer_id == GlobalStats.host_peer_id:
		is_host = true
		start_button.show()
		ip_label.text = "Lobby Host: " + GlobalStats.player_name
	else:
		is_host = false
		start_button.hide()
		ip_label.text = "Waiting for Host to start..."
		ws.send_text(JSON.stringify({
			"type": "client_ready",
			"peer_id": GlobalStats.my_peer_id,
			"name": GlobalStats.player_name,
			"room_id": GlobalStats.hosted_lobby_id
		}))
		var mp_peer = WebSocketMultiplayerPeer.new()
		var url = "ws://127.0.0.1:" + str(GlobalStats.current_port)
		if mp_peer.create_client(url) == OK:
			multiplayer.multiplayer_peer = mp_peer
			print("JOINER: Handshaking with Host on Port: ", GlobalStats.current_port)
			
			multiplayer.connected_to_server.connect(_on_connected_to_host)
			
	update_player_list()

func _on_connected_to_host():
	sync_true_name_to_host.rpc_id(1, GlobalStats.my_peer_id, GlobalStats.player_name)

@rpc("any_peer", "call_remote", "reliable")
func sync_true_name_to_host(relay_peer_id: int, true_name: String):
	if multiplayer.is_server():
		var godot_id = multiplayer.get_remote_sender_id()
		GlobalStats.godot_to_relay_map[godot_id] = relay_peer_id
		broadcast_true_name.rpc(relay_peer_id, true_name)

@rpc("authority", "call_local", "reliable")
func broadcast_true_name(relay_peer_id: int, true_name: String):
	GlobalStats.network_names[relay_peer_id] = true_name
	update_player_list()


func update_player_list(_dummy = null):
	for child in player_list.get_children():
		child.queue_free()
		
	if GlobalStats.network_names.has(GlobalStats.host_peer_id):
		var host_label = Label.new()
		var host_name = GlobalStats.network_names[GlobalStats.host_peer_id]
		host_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		host_label.text = "- " + host_name + " (Host)"
		host_label.add_theme_color_override("font_color", Color(1, 1, 0))
		player_list.add_child(host_label)
		
	for id in GlobalStats.network_names:
		var int_id = int(id)
		if int_id == GlobalStats.host_peer_id:
			continue 
			
		var name_label = Label.new()
		var p_name = GlobalStats.network_names[id]
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_label.text = "- " + p_name
		player_list.add_child(name_label)

func _on_start_button_pressed():
	if is_host:
		ws.send_text(JSON.stringify({
			"type": "start_game",
			"room_id": GlobalStats.hosted_lobby_id,
			"map": GlobalStats.map_name
		}))

func _on_quit_to_menu_pressed():
	if ws and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify({
			"type": "leave",
			"peer_id": GlobalStats.my_peer_id,
			"room_id": GlobalStats.hosted_lobby_id
		}))
	multiplayer.multiplayer_peer = null
	GlobalStats.network_names.clear()
	get_tree().change_scene_to_file("res://Scenes/menu.tscn")

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
