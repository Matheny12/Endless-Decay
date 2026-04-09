extends VBoxContainer

var matchmaker_url = "wss://endless-decay-server.onrender.com"
var my_peer_id = randi_range(2, 99999)
var settings_scene = preload("res://Scenes/settings.tscn")
var settings_instance = null
var ws_ready = false
var pending_action = ""
var pending_room_id = ""

@onready var loading_label = $LoadingLabel
@onready var server_list = $ScrollContainer/ServerList
@onready var server_label = $ServerLabel
@onready var host_button = $Host

func _ready():
	if not GlobalStats.rooms_received.is_connected(_display_rooms):
		GlobalStats.rooms_received.connect(_display_rooms)
	if loading_label:
		loading_label.hide()

func _display_rooms(rooms):
	for child in server_list.get_children():
		child.queue_free()
	if rooms.size() == 0:
		if server_label: server_label.text = "No rooms found"
		return
	if server_label: server_label.text = "Rooms found"
	for room in rooms:
		var btn = Button.new()
		btn.text = room.name + " [" + room.map + "] " + " [" + room.difficulty + "] "
		btn.pressed.connect(func(): _join_room(room.id))
		server_list.add_child(btn)

func _join_room(room_id: String):
	GlobalStats.ws.send_text(JSON.stringify({
		"type": "join",
		"peer_id": GlobalStats.my_peer_id,
		"room_id": room_id,
		"name": GlobalStats.player_name
	}))

func _on_host_pressed():
	save_player_name()
	if loading_label:
		loading_label.show()
	if host_button:
		host_button.disabled = true
	GlobalStats.hosted_lobby_id = str(randi())
	GlobalStats.my_peer_id = randi_range(2, 99999)
	if loading_label: loading_label.text = "Waking up server..."
	GlobalStats.connect_to_relay(matchmaker_url, "host")

func _on_join_pressed():
	save_player_name()
	if server_label: server_label.text = "Fetching rooms..."
	GlobalStats.connect_to_relay(matchmaker_url, "get_rooms")

func save_player_name():
	if $NameEntry.text.strip_edges() != "":
		GlobalStats.player_name = $NameEntry.text.strip_edges()
	else:
		GlobalStats.player_name = "Survivor_" + str(randi_range(100, 999))

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
	if GlobalStats.ws != null and GlobalStats.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		GlobalStats.ws.send_text(JSON.stringify({
			"type": "leave",
			"room_id": GlobalStats.hosted_lobby_id
		}))
		GlobalStats.ws.close()
	get_tree().quit()
