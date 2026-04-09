extends Node

var game_difficulty : String = ""
var map_name : String = ""
var connection_error_message : String = ""
var player_name: String = ""
var network_names: Dictionary = {}
var hosted_lobby_id : String = ""
var current_port: int = randi_range(4000, 8000)
var lootlocker_player_id : String = ""
var final_scores: Array = []
var godot_to_relay_map: Dictionary = {}
signal zombie_count_changed(total_kills)
signal rooms_received(rooms: Array)
signal peer_moved(peer_id: int, pos: Dictionary)

var ws: WebSocketPeer = WebSocketPeer.new()
var multiplayer_peer: WebSocketMultiplayerPeer = null
var my_peer_id: int = 0
var host_peer_id: int = 0
var pending_action: String = ""

var total_zombies_killed: int = 0:
	set(value):
		total_zombies_killed = value
		zombie_count_changed.emit(total_zombies_killed)

func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_native_peer_disconnected)
	
func _on_native_peer_disconnected(godot_id: int):
	if godot_to_relay_map.has(godot_id):
		var relay_id = godot_to_relay_map[godot_id]
		if network_names.has(relay_id):
			network_names.erase(relay_id)
		godot_to_relay_map.erase(godot_id)
		rooms_received.emit([])

func _process(_delta):
	var state = ws.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED: return
	ws.poll()
	
	if state == WebSocketPeer.STATE_OPEN:
		if pending_action != "":
			_perform_pending_action()
		while ws.get_available_packet_count() > 0:
			var packet = ws.get_packet()
			var data = packet.get_string_from_utf8()
			var msg = JSON.parse_string(data)
			
			if msg != null and typeof(msg) == TYPE_DICTIONARY:
				_handle_game_packet(msg)

func _perform_pending_action():
	if pending_action == "host":
		network_names.clear()
		if my_peer_id == 0:
			my_peer_id = randi_range(100000, 999999)
		host_peer_id = my_peer_id
		ws.send_text(JSON.stringify({
			"type": "host",
			"peer_id": my_peer_id,
			"room_id": hosted_lobby_id,
			"name": player_name,
			"map": map_name,
			"port": current_port,
			"difficulty": game_difficulty
		}))
	elif pending_action == "get_rooms":
		ws.send_text(JSON.stringify({"type": "get_rooms"}))
	pending_action = ""

func _handle_game_packet(msg):
	match msg.type:
		"hosted":
			print("Relay Server acknowledged the room!")
			network_names.clear()
			network_names[my_peer_id] = player_name
			var current_scene = get_tree().current_scene
			if current_scene != null and current_scene.name == "host_settings":
				get_tree().change_scene_to_file("res://Scenes/lobby.tscn")
			else:
				get_tree().change_scene_to_file("res://Scenes/host_settings.tscn")

		"rooms":
			rooms_received.emit(msg.rooms)
			
		"peer_joined":
			if not msg.has("peer_id"): return
			var pid = int(msg.peer_id)
			
			if pid == my_peer_id: return 
			
			network_names[pid] = msg.name
			
			if my_peer_id == host_peer_id:
				ws.send_text(JSON.stringify({
					"type": "broadcast_names",
					"room_id": hosted_lobby_id,
					"names": network_names
				}))
			rooms_received.emit([])

		"names_synced":
			for key in msg.names:
				var int_key = int(key)
				var p_name = msg.names[key]
				if not network_names.has(int_key):
					network_names[int_key] = p_name
			rooms_received.emit([])

		"start_game":
			map_name = msg.map
			var scene_path = "res://Scenes/" + msg.map.to_lower() + ".tscn"
			if msg.map == "Neighborhood":
				scene_path = "res://Scenes/world.tscn"
			get_tree().change_scene_to_file(scene_path)
			
		"joined":
			host_peer_id = int(msg["host_id"])
			hosted_lobby_id = msg["room_id"]
			network_names.clear()
			
			if msg.has("port"):
				current_port = int(msg["port"])
			if msg.has("names"):
				for key in msg["names"]:
					network_names[int(key)] = msg["names"][key]
					
			get_tree().change_scene_to_file("res://Scenes/lobby.tscn")

		"host_disconnected":
			connection_error_message = "Host disconnected."
			get_tree().change_scene_to_file("res://Scenes/menu.tscn")

		"peer_left":
			var left_id = int(msg.get("peer_id", 0))
			if left_id != 0 and network_names.has(left_id):
				network_names.erase(left_id)
			rooms_received.emit([])

func connect_to_relay(url: String, action: String):
	pending_action = action
	ws.connect_to_url(url)

func leave_matchmaking_lobby():
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify({
			"type": "leave",
			"room_id": hosted_lobby_id,
			"peer_id": my_peer_id
		}))
	ws.close()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	network_names.clear()
	hosted_lobby_id = ""
	pending_action = ""
	godot_to_relay_map.clear()
