extends Node3D

@onready var players_folder = $Players
@onready var hit_rect = $UI/HitRect
@onready var spawns = $spawns
@onready var navigation_region = $NavigationRegion3D
@onready var crosshair = $UI/CrossHair
@onready var hitmarker = $UI/HitMarker
@onready var server_status = $UI/ServerStatus

const MAX_DISTANCE = 300.0

const Player = preload("res://Scenes/player.tscn")
const Zombie = preload("res://Scenes/zombie.tscn")
const BossScene = preload("res://zombie_boss.tscn")

var instance
var boss_active: bool = false
var boss_kill_threshold: int = 20
var spawn_limit

func _ready() -> void:
	randomize()
	crosshair.position.x = get_viewport().size.x / 2 - 32
	crosshair.position.y = get_viewport().size.y / 2 - 32
	hitmarker.position.x = get_viewport().size.x / 2 - 32
	hitmarker.position.y = get_viewport().size.y / 2 - 32
	GameEvents.player_struck.connect(_on_player_player_hit)
	GlobalStats.zombie_count_changed.connect(_on_zombie_killed)
	if GameEvents.has_signal("zombie_hit"):
		GameEvents.zombie_hit.connect(_on_enemy_hit)
	match GlobalStats.game_difficulty:
		"Easy": spawn_limit = 10
		"Normal": spawn_limit = 15
		"Hard": spawn_limit = 20
	for child in players_folder.get_children():
		child.queue_free()
	if multiplayer.is_server():
		GlobalStats.total_zombies_killed = 0
		multiplayer.peer_disconnected.connect(remove_player)
		add_player(1)
		fetch_ip_address()
	else:
		get_tree().process_frame.connect(func(): player_loaded.rpc_id(1), CONNECT_ONE_SHOT)

@rpc("any_peer", "call_local", "reliable")
func player_loaded():
	if multiplayer.is_server():
		var peer_id = multiplayer.get_remote_sender_id()
		await get_tree().create_timer(2).timeout 
		print("Server: Spawning body for Joiner ", peer_id)
		add_player(peer_id)

func add_player(peer_id):
	if players_folder.has_node(str(peer_id)): 
		return
	var player_instance = Player.instantiate()
	player_instance.name = str(peer_id)
	player_instance.add_to_group("player") 
	players_folder.add_child(player_instance)

func _process(_delta: float) -> void:
	pass

func _get_random_child(parent_node):
	var random_id = randi() % parent_node.get_child_count()
	return parent_node.get_child(random_id)

func _on_zombie_spawn_timer_timeout() -> void:
	_handle_spawn_logic(spawns)

func _on_player_player_hit() -> void:
	hit_rect.visible = true
	await get_tree().create_timer(0.2).timeout
	hit_rect.visible = false

func _on_enemy_hit():
	hitmarker.visible = true
	await get_tree().create_timer(0.05).timeout
	hitmarker.visible = false

func spawn_zombie(pos: Vector3):
	var new_zombie = Zombie.instantiate()
	new_zombie.add_to_group("zombie")
	new_zombie.add_to_group("enemy")
	new_zombie.zombie_hit.connect(_on_enemy_hit)
	add_child(new_zombie, true) 
	new_zombie.global_position = pos

func fetch_ip_address():
	var local_ip = ""
	var addresses = IP.get_local_addresses()
	for address in addresses:
		if address.count(".") == 3 and not address.begins_with("127.") and not address.begins_with("169.254"):
			local_ip = address
			break
	var current_port = str(GlobalStats.current_port)
	if local_ip != "":
		var full_address = local_ip + ":" + current_port
		server_status.text = "\n    Port: " + current_port
		DisplayServer.clipboard_set(full_address)
	else:
		server_status.text = "IP not found. Port: " + current_port

func _handle_spawn_logic(spawn_container):
	if not multiplayer.is_server(): return
	if boss_active: return 
	var all_players = get_tree().get_nodes_in_group("player")
	if all_players.is_empty(): return
	var valid_spawn_points = []
	var spawn_range = 75.0
	var min_spawn_dist = 5.0
	for spawn_point in spawn_container.get_children():
		for p in all_players:
			var dist = spawn_point.global_position.distance_to(p.global_position)
			if dist < spawn_range and dist > min_spawn_dist:
				valid_spawn_points.append(spawn_point)
				break
	var zombie_count = get_tree().get_nodes_in_group("zombie").size()
	if not valid_spawn_points.is_empty() and zombie_count <= spawn_limit:
		var chosen_spawn = valid_spawn_points.pick_random()
		spawn_zombie(chosen_spawn.global_position)

func _on_zombie_killed(total_kills: int):
	if not multiplayer.is_server(): return
	if total_kills > 0 and total_kills % boss_kill_threshold == 0 and not boss_active:
		spawn_boss()

func spawn_boss():
	if not multiplayer.is_server(): return
	var all_players = get_tree().get_nodes_in_group("player")
	if all_players.is_empty(): return
	var valid_spawn_points = []
	var spawn_range = 75.0
	var min_spawn_dist = 5.0
	for spawn_point in spawns.get_children():
		for p in all_players:
			var dist = spawn_point.global_position.distance_to(p.global_position)
			if dist < spawn_range and dist > min_spawn_dist:
				valid_spawn_points.append(spawn_point)
				break
	var chosen_spawn_pos: Vector3
	if not valid_spawn_points.is_empty():
		chosen_spawn_pos = valid_spawn_points.pick_random().global_position
	else:
		chosen_spawn_pos = spawns.get_children().pick_random().global_position
	boss_active = true
	var boss = BossScene.instantiate()
	boss.add_to_group("zombie")
	boss.add_to_group("enemy")
	if boss.has_signal("zombie_hit"):
		boss.zombie_hit.connect(_on_enemy_hit)
	boss.tree_exited.connect(_on_boss_defeated)
	add_child(boss, true)
	boss.global_position = chosen_spawn_pos

func _on_boss_defeated():
	boss_active = false

func remove_player(peer_id):
	var p = players_folder.get_node_or_null(str(peer_id))
	if p:
		p.queue_free()

func start_exit_timer(scene_path: String):
	if is_instance_valid(crosshair): crosshair.hide()
	if is_instance_valid(hitmarker): hitmarker.hide()
	var timer_val = 10.5 if multiplayer.is_server() else 10.0
	await get_tree().create_timer(timer_val).timeout
	multiplayer.multiplayer_peer = null
	get_tree().change_scene_to_file(scene_path)
	
func spawn_player(id: int, p_name: String, spawn_pos: Vector2):
	var p_scene = Player.instantiate()
	p_scene.name = str(id)
	p_scene.global_position = spawn_pos
	add_child(p_scene)
