extends CharacterBody3D

var current_pauser_id: int = 0
var is_dead: bool=false
var display_name: String = "Survivor"
var is_switching_weapons=false
var is_local_player: bool = false
var speed
const WALK_SPEED=5.0
const SPRINT_SPEED=8.0
const JUMP_VELOCITY=3
const BOB_FREQ=2.0
const BOB_AMP=0.08
var t_bob=0.0
const BASE_FOV=75.0
const FOV_CHANGE=1.5
const HIT_STAGGER=4.0
const SHOTGUN_RECOIL=3.0
var hover_check_timer=0.0
const HOVER_CHECK_INTERVAL=0.1
var zombie_kills:int=0
var damage_multiplier:float=1.0
var current_boss_shake:float=0.0
signal player_hit
var bullet=load("res://Models/bullet.tscn")
var shotgun_bullet=load("res://Models/shotgun_bullet.tscn")
var bullet_trail=load("res://Models/bullet_trail.tscn")
var instance
var SENSITIVITY=0.02
var rifle_mag=30
var rifle_reserve=90
const RIFLE_MAG_SIZE=30
var shotgun_mag=8
var shotgun_reserve=24
const SHOTGUN_MAG_SIZE=8
var is_reloading=false
var is_swinging_bat=false
const MAX_PLAYER_HEALTH=100
var score = 0
var player_health: int = MAX_PLAYER_HEALTH:
	set(value):
		player_health = clamp(value, 0, MAX_PLAYER_HEALTH)
		update_ui()
@onready var head=$Head
@onready var camera=$Head/Camera3D
@onready var gun_anim=$Head/Camera3D/GunPivot/rifle/AnimationPlayer
@onready var shotgun_anim=$Head/Camera3D/GunPivot/shotgun/AnimationPlayer
@onready var gun_barrel=$Head/Camera3D/GunPivot/rifle/RayCast3D
@onready var shotgun_barrel=$Head/Camera3D/GunPivot/shotgun/RayCast3D
@onready var rifle=$Head/Camera3D/GunPivot/rifle
@onready var shotgun=$Head/Camera3D/GunPivot/shotgun
@onready var aim_ray=$Head/Camera3D/AimRay
@onready var aim_ray_end=$Head/Camera3D/AimRayEnd
@onready var stats_label=$UI/StatsLabel
@onready var guns_anim=$Head/Camera3D/AnimationPlayer
@onready var rifle_sound=$Head/Camera3D/GunPivot/RifleSound
@onready var shotgun_sound=$Head/Camera3D/GunPivot/ShotgunSound
@onready var reload_sound=$Head/Camera3D/GunPivot/ReloadSound
@onready var switch_sound=$Head/Camera3D/GunPivot/SwitchSound
@onready var buff_label=$UI/BuffLabel
@onready var bat=$Head/Camera3D/GunPivot/BaseballBat
@onready var bat_switch=$Head/Camera3D/GunPivot/BatSwitchSound
@onready var bat_swing=$Head/Camera3D/GunPivot/BatSwingSound
@onready var bat_hit=$Head/Camera3D/GunPivot/BatHitSound
@onready var bat_ray=$Head/Camera3D/BatRay
@onready var scoreboard = $UI/Scoreboard
@onready var scoreboard_list = $UI/Scoreboard/VBoxContainer
@onready var health_bar_sprite=$HealthBarSprite
@onready var health_bar=$HealthBarSprite/SubViewport/TextureProgressBar
@onready var health_label=$HealthBarSprite/SubViewport/HealthLabel
@onready var spectator_label = $UI/SpectatorLabel
@onready var waiting_label = $UI/WaitingLabel
var pause_menu_scene=preload("res://Scenes/pause.tscn")
var pause_menu_instance=null
var last_zombie_hovered=null
var spectated_player = null
var spectate_index = 0

@rpc("any_peer","call_local")
func add_score(amount):
	score += amount
	if multiplayer.multiplayer_peer != null:
		if multiplayer.is_server():
			update_score_on_client.rpc(score)
	else:
		update_ui()

@rpc("any_peer","call_local")
func update_score_on_client(new_score):
	score = new_score
	update_ui()

func _enter_tree()->void:
	set_multiplayer_authority(str(name).to_int())

func _ready():
	add_to_group("player")
	if is_multiplayer_authority():
		is_local_player = true
		camera.make_current()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		if has_node("HealthBarSprite"): $HealthBarSprite.hide()
		if has_node("UI"): $UI.show()
		display_name = GlobalStats.player_name
		_broadcast_name_safely()
	else:
		if has_node("UI"): $UI.hide()
		if has_node("HealthBarSprite"): $HealthBarSprite.show()
		camera.current = false
	if is_instance_valid(health_bar):
		health_bar.max_value = MAX_PLAYER_HEALTH
		health_bar.value = player_health
	update_ui()

func _broadcast_name_safely():
	await get_tree().create_timer(0.5).timeout
	sync_name.rpc(display_name)

@rpc("any_peer", "call_local", "reliable")
func sync_name(p_name: String):
	display_name = p_name
	update_ui()
	if is_instance_valid(scoreboard) and scoreboard.visible:
		update_scoreboard()

func _unhandled_input(event)->void:
	if get_tree().paused: return
	if not is_multiplayer_authority(): return
	if event.is_action_pressed("pause"):
		toggle_pause()
	if is_dead and event.is_action_pressed("shoot"):
		switch_spectator()
		return
	if is_dead: return 
	if event is InputEventMouseMotion:
		head.rotate_y(-event.relative.x*SENSITIVITY)
		var new_x_rot=camera.rotation.x+(-event.relative.y*SENSITIVITY)
		camera.rotation.x=clamp(new_x_rot,deg_to_rad(-60),deg_to_rad(60))

func _physics_process(delta:float)->void:
	if is_local_player:
		GlobalStats.ws.send_text(JSON.stringify({
			"type": "player_moved",
			"room_id": GlobalStats.hosted_lobby_id,
			"peer_id": GlobalStats.my_peer_id,
			"pos": {"x": global_position.x, "y": global_position.y}
		}))
	if get_tree().paused: return
	update_ui()
	if not is_multiplayer_authority():return
	if Input.is_action_just_pressed("scores"):
		update_scoreboard()
		scoreboard.show()
	elif Input.is_action_just_released("scores"):
		scoreboard.hide()
	if is_dead:
		if spectated_player == null or spectated_player.is_dead:
			switch_spectator()
		return
	if not is_on_floor():
		velocity+=get_gravity()*delta
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y=JUMP_VELOCITY
	if Input.is_action_pressed("sprint"):
		speed=SPRINT_SPEED
	else:
		speed=WALK_SPEED
	if Input.is_action_pressed("reload"):
		_reload.rpc()
	var input_dir=Input.get_vector("right","left","back","forward")
	var direction=(head.transform.basis*Vector3(input_dir.x,0,input_dir.y)).normalized()
	if is_on_floor():
		if direction:
			velocity.x=direction.x*speed
			velocity.z=direction.z*speed
		else:
			velocity.x=lerp(velocity.x,direction.x*speed,delta*7.0)
			velocity.z=lerp(velocity.z,direction.z*speed,delta*7.0)
	else:
		velocity.x=lerp(velocity.x,direction.x*speed,delta*3.0)
		velocity.z=lerp(velocity.z,direction.z*speed,delta*3.0)
	t_bob+=delta*velocity.length()*float(is_on_floor())
	camera.transform.origin=_headbob(t_bob)
	var velocity_clamped=clamp(velocity.length(),0.5,SPRINT_SPEED*2)
	var target_fov=BASE_FOV+FOV_CHANGE*velocity_clamped
	camera.fov=lerp(camera.fov,target_fov,delta*8.0)
	if Input.is_action_just_pressed("rifle") and not rifle.visible:
		_switch_weapon.rpc("rifle")
	if Input.is_action_just_pressed("shotgun") and not shotgun.visible:
		_switch_weapon.rpc("shotgun")
	if Input.is_action_just_pressed("bat") and not bat.visible:
		_switch_weapon.rpc("bat")
	if Input.is_action_pressed("shoot"):
		if Input.get_mouse_mode()==Input.MOUSE_MODE_CAPTURED:
			if shotgun.visible==true:
				_shoot_shotgun.rpc()
			if rifle.visible==true:
				_shoot_rifle.rpc()
			if bat.visible==true:
				_swing_bat.rpc()
	hover_check_timer+=delta
	if hover_check_timer>=HOVER_CHECK_INTERVAL:
		handle_zombie_hover()
		hover_check_timer=0.0
	move_and_slide()

func _headbob(time)->Vector3:
	var pos=Vector3.ZERO
	pos.y=sin(time*BOB_FREQ)*BOB_AMP
	pos.x=cos(time*BOB_FREQ/2)*BOB_AMP
	return pos

@rpc("any_peer", "call_local")
func attacked(dir, damage_amount: int):
	if multiplayer.is_server():
		player_health -= damage_amount
		sync_health.rpc(player_health)
		if player_health <= 0 and not is_dead:
			die.rpc()
	velocity += dir * HIT_STAGGER
	if is_multiplayer_authority():
		GameEvents.player_struck.emit()

@rpc("any_peer", "call_local")
func sync_health(new_health):
	player_health = new_health 

func _input(event):
	if not is_multiplayer_authority(): return
	if event.is_action_pressed("pause"):
		var my_id = multiplayer.get_unique_id()
		if not get_tree().paused:
			sync_pause.rpc(true, my_id)
		else:
			if current_pauser_id == my_id:
				sync_pause.rpc(false, 0)

@rpc("any_peer","call_local")
func _shoot_rifle():
	if rifle_mag>0 and not is_reloading:
		if not gun_anim.is_playing():
			rifle_mag-=1
			gun_anim.play("shoot")
			rifle_sound.play()
			instance=bullet_trail.instantiate()
			var new_bullet=bullet.instantiate()
			get_parent().add_child(new_bullet)
			new_bullet.global_transform=gun_barrel.global_transform
			if aim_ray.is_colliding() and aim_ray.get_collider().is_in_group("enemy"):
				var target=aim_ray.get_collider()
				var z_node = target
				while z_node != null and not z_node.has_method("set_last_attacker"):
					z_node = z_node.get_parent()
				if z_node != null:
					z_node.set_last_attacker.rpc(str(self.get_path()))
				instance.init(gun_barrel.global_position,aim_ray.get_collision_point())
				var rifle_base_damage=2.0
				var total_damage=rifle_base_damage*damage_multiplier
				target.rifle_hit(total_damage)
				if is_multiplayer_authority():
					GameEvents.zombie_hit.emit()
	elif rifle_mag<=0:
		if is_multiplayer_authority():
			_reload.rpc()

@rpc("any_peer","call_local")
func _shoot_shotgun():
	if shotgun_mag>0 and not is_reloading:
		if not shotgun_anim.is_playing():
			shotgun_mag-=1
			shotgun_anim.play("shoot")
			shotgun_sound.play()
			instance=bullet_trail.instantiate()
			var new_bullet2=shotgun_bullet.instantiate()
			get_parent().add_child(new_bullet2)
			new_bullet2.global_transform=shotgun_barrel.global_transform
			velocity-=head.transform.basis.z*SHOTGUN_RECOIL
			if aim_ray.is_colliding() and aim_ray.get_collider().is_in_group("enemy"):
				var target=aim_ray.get_collider()
				var z_node = target
				while z_node != null and not z_node.has_method("set_last_attacker"):
					z_node = z_node.get_parent()
				if z_node != null:
					z_node.set_last_attacker.rpc(str(self.get_path()))
				instance.init(shotgun_barrel.global_position,aim_ray.get_collision_point())
				var shotgun_base_damage=4.0
				var total_damage=shotgun_base_damage*damage_multiplier
				target.shotgun_hit(total_damage)
				if is_multiplayer_authority():
					GameEvents.zombie_hit.emit()
			else:
				get_parent().add_child(instance)
	elif shotgun_mag<=0:
		if is_multiplayer_authority():
			_reload.rpc()

@rpc("any_peer","call_local")
func _swing_bat():
	if not is_swinging_bat:
		is_swinging_bat=true
		guns_anim.play("BatHit")
		bat_swing.play()
		await get_tree().create_timer(0.2).timeout
		aim_ray.force_raycast_update()
		if aim_ray.is_colliding() and aim_ray.get_collider().is_in_group("enemy"):
			var target=aim_ray.get_collider()
			var hit_point=aim_ray.get_collision_point()
			var distance=camera.global_position.distance_to(hit_point)
			if distance<=4.5:
				var z_node = target
				while z_node != null and not z_node.has_method("set_last_attacker"):
					z_node = z_node.get_parent()
				if z_node != null:
					z_node.set_last_attacker.rpc(str(self.get_path()))
				var bat_base_damage=1.0
				var total_damage=bat_base_damage*damage_multiplier
				target.rifle_hit(total_damage)
				if is_multiplayer_authority():
					GameEvents.zombie_hit.emit()
				bat_hit.play()
		await guns_anim.animation_finished
		is_swinging_bat=false

@rpc("any_peer","call_local")
func _reload():
	if is_reloading:return
	var current_mag=rifle_mag if rifle.visible else shotgun_mag
	var current_reserve=rifle_reserve if rifle.visible else shotgun_reserve
	var max_size=RIFLE_MAG_SIZE if rifle.visible else SHOTGUN_MAG_SIZE
	if current_mag==max_size or current_reserve<=0:return
	is_reloading=true
	if rifle.visible==true:
		guns_anim.play("reload_r")
		reload_sound.play()
	else:
		guns_anim.play("reload")
		reload_sound.play()
	await get_tree().create_timer(2.0).timeout
	var amount_needed=max_size-current_mag
	var reload_amount=min(current_reserve,amount_needed)
	if rifle.visible:
		rifle_mag+=reload_amount
		rifle_reserve-=reload_amount
	else:
		shotgun_mag+=reload_amount
		shotgun_reserve-=reload_amount
	is_reloading=false

func update_ui():
	if is_instance_valid(health_bar):
		var max_h = MAX_PLAYER_HEALTH if MAX_PLAYER_HEALTH > 0 else 100
		health_bar.max_value = max_h
		health_bar.value = player_health
		var health_percent = float(player_health) / float(max_h)
		health_percent = clamp(health_percent, 0.0, 1.0)
		health_bar.tint_progress = Color(1.0 - health_percent, health_percent, 0, 1.0)
		
		if is_instance_valid(health_label):
			var peer_id = str(name).to_int()
			var final_name = GlobalStats.network_names.get(peer_id, "Unknown")
			if final_name == "Unknown":
				if peer_id == GlobalStats.my_peer_id:
					final_name = GlobalStats.player_name
				elif peer_id == GlobalStats.host_peer_id:
					final_name = "Lobby Host"
			
			health_label.text = "%s: %d / %d" % [display_name, player_health, MAX_PLAYER_HEALTH]
			
	if stats_label == null: return
	var gun_name = "Baseball Bat"
	if rifle.visible: 
		gun_name = "Rifle"
	elif shotgun.visible: 
		gun_name = "Shotgun"
	var current_mag = rifle_mag if rifle.visible else (shotgun_mag if shotgun.visible else 0)
	var current_reserve = rifle_reserve if rifle.visible else (shotgun_reserve if shotgun.visible else 0)
	var max_mag = RIFLE_MAG_SIZE if rifle.visible else (SHOTGUN_MAG_SIZE if shotgun.visible else 0)
	var ui_text = "Gun: %s\n" % gun_name
	if gun_name != "Baseball Bat":
		ui_text += "Ammo: %d / %d\n" % [current_mag, current_reserve]
		ui_text += "Ammo Needed: %d\n" % [max_mag - current_mag]
	else:
		ui_text += "Ammo: N/A\n"
		ui_text += "Ammo Needed: 0\n"
	ui_text += "Health: %d / %d\n" % [player_health, MAX_PLAYER_HEALTH]
	stats_label.text = ui_text

func toggle_pause():
	var new_pause_state = !get_tree().paused
	sync_pause.rpc(new_pause_state)

@rpc("any_peer", "call_local", "reliable")
func sync_pause(should_pause: bool, pauser_id: int):
	current_pauser_id = pauser_id
	get_tree().paused = should_pause
	var local_player = null
	for p in get_tree().get_nodes_in_group("player"):
		if p.is_multiplayer_authority():
			local_player = p
			break
	if local_player != null:
		var my_id = multiplayer.get_unique_id()
		if should_pause:
			if my_id == pauser_id:
				if local_player.pause_menu_instance == null:
					local_player.pause_menu_instance = local_player.pause_menu_scene.instantiate()
					local_player.get_node("UI").add_child(local_player.pause_menu_instance)
				local_player.pause_menu_instance.show()
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
				if is_instance_valid(local_player.waiting_label):
					var pauser_name = GlobalStats.network_names.get(pauser_id, "A Teammate")
					local_player.waiting_label.text = "Game paused by " + pauser_name + "\nWaiting for them to resume..."
					local_player.waiting_label.show()
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			if is_instance_valid(local_player.waiting_label):
				local_player.waiting_label.hide()
			if is_instance_valid(local_player.pause_menu_instance):
				local_player.pause_menu_instance.queue_free()
				local_player.pause_menu_instance = null
	if multiplayer.is_server():
		var sender_id = multiplayer.get_remote_sender_id()
		if sender_id == 0:
			sender_id = 1 
		for peer in multiplayer.get_peers():
			if peer != sender_id:
				sync_pause_relay.rpc_id(peer, should_pause, pauser_id)

@rpc("any_peer", "call_remote", "reliable")
func sync_pause_relay(should_pause: bool, pauser_id: int):
	sync_pause(should_pause, pauser_id)

func toggle_client_menu():
	if pause_menu_instance == null:
		pause_menu_instance = pause_menu_scene.instantiate()
		$UI.add_child(pause_menu_instance)
	if pause_menu_instance.visible:
		pause_menu_instance.hide()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		pause_menu_instance.show()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

@rpc("authority", "call_local", "reliable")
func force_quit_to_everyone():
	set_physics_process(false) 
	set_process_unhandled_input(false)
	var world_node = get_tree().current_scene
	if world_node.has_node("EndGameCam"):
		world_node.get_node("EndGameCam").make_current()
	if multiplayer.is_server():
		for z in get_tree().get_nodes_in_group("zombie"):
			if z.has_method("freeze_zombie"):
				z.freeze_zombie.rpc()
	GlobalStats.final_scores.clear()
	var parent_node = get_parent()
	if parent_node:
		for p in parent_node.get_children():
			if p.has_method("add_score"):
				var id_int = str(p.name).to_int()
				var display_name = GlobalStats.network_names.get(id_int, "Player")
				GlobalStats.final_scores.append({
					"name": display_name, "score": p.score, "kills": p.zombie_kills
				})
				if p.has_method("is_multiplayer_authority") and p.is_multiplayer_authority():
					if is_instance_valid(p.pause_menu_instance):
						p.pause_menu_instance.queue_free()
						p.pause_menu_instance = null
					if p.has_node("UI"):
						p.get_node("UI").visible = true
						if is_instance_valid(p.stats_label): p.stats_label.visible = false
					if "scoreboard" in p and is_instance_valid(p.scoreboard):
						p.update_scoreboard()
						p.scoreboard.show()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = false
	var world = get_tree().current_scene
	if world.has_method("start_exit_timer"):
		world.start_exit_timer("res://Scenes/menu.tscn")

func _on_continue_bonus_received():
	if rifle.visible==true:rifle_mag+=1
	else:shotgun_mag+=1

@rpc("any_peer","call_local")
func die():
	var is_online = multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if is_online:
		setup_spectator_mode()
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		get_tree().change_scene_to_file("res://Scenes/you_died.tscn")

func setup_spectator_mode():
	if not is_multiplayer_authority(): return
	sync_death_status.rpc(true)
	$Head/Camera3D/GunPivot.visible = false
	if is_instance_valid(stats_label): stats_label.visible = false
	switch_spectator()
	var living_players = []
	for p in get_tree().get_nodes_in_group("player"):
		if "is_dead" in p and not p.is_dead:
			living_players.append(p)
	if living_players.is_empty():
		if multiplayer.is_server():
			end_game_for_everyone.rpc()
		else:
			request_end_game.rpc()

func _start_end_game_timer():
	await get_tree().create_timer(10.0).timeout
	if multiplayer.is_server():
		end_game_for_everyone.rpc()

func handle_zombie_hover():
	if aim_ray.is_colliding():
		var collider=aim_ray.get_collider()
		if collider:
			var target=collider.get_parent() if collider is Area3D else collider
			if target.is_in_group("zombie") and target.has_method("set_health_bar_visible"):
				if last_zombie_hovered and last_zombie_hovered!=target:
					if is_instance_valid(last_zombie_hovered):last_zombie_hovered.set_health_bar_visible(false)
				target.set_health_bar_visible(true)
				last_zombie_hovered=target
				return
	if last_zombie_hovered:
		if is_instance_valid(last_zombie_hovered):last_zombie_hovered.set_health_bar_visible(false)
		last_zombie_hovered=null

@rpc("any_peer","call_local")
func _switch_weapon(weapon_name:String):
	if is_switching_weapons:return
	is_switching_weapons=true
	is_reloading=false
	if rifle.visible:
		guns_anim.play("LowerRifle")
		await guns_anim.animation_finished
		rifle.visible=false
	elif shotgun.visible:
		guns_anim.play("LowerShotgun")
		await guns_anim.animation_finished
		shotgun.visible=false
	elif bat.visible:
		guns_anim.play("LowerBat")
		await guns_anim.animation_finished
		bat.visible=false
	match weapon_name:
		"rifle":
			rifle.visible=true
			switch_sound.play()
			guns_anim.play("RaiseRifle")
		"shotgun":
			shotgun.visible=true
			switch_sound.play()
			guns_anim.play("RaiseShotgun")
		"bat":
			bat.visible=true
			bat_switch.play()
			guns_anim.play("RaiseBat")
	await guns_anim.animation_finished
	is_switching_weapons=false

@rpc("any_peer","call_local")
func add_zombie_kill():
	if not is_multiplayer_authority(): return
	zombie_kills += 1
	sync_kills.rpc(zombie_kills)
	update_ui()
	if zombie_kills % 10 == 0:
		damage_multiplier *= 1.2
		show_buff_popup()

@rpc("any_peer", "call_local")
func sync_kills(new_kill_count: int):
	zombie_kills = new_kill_count

func show_buff_popup():
	if buff_label==null:return
	buff_label.text="DAMAGE x"+str(damage_multiplier)+" & Zombie Health + 10!"
	buff_label.modulate.a=2.0
	buff_label.visible=true
	var original_y=buff_label.position.y
	var tween=create_tween()
	tween.tween_property(buff_label,"position:y",original_y-30,1.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(buff_label,"modulate:a",0.0,1.5)
	tween.tween_callback(func():buff_label.position.y=original_y)

@rpc("any_peer","call_local")
func sync_global_kills(total_kills):
	GlobalStats.total_zombies_killed=total_kills
	if GlobalStats.has_signal("zombie_count_changed"):
		GlobalStats.zombie_count_changed.emit(total_kills)

@rpc("any_peer","call_local", "reliable")
func sync_death_status(status:bool):
	is_dead = status
	if status:
		if is_in_group("player"): 
			remove_from_group("player")
		$CollisionShape3D.set_deferred("disabled", true)
		if has_node("HealthBarSprite"):
			$HealthBarSprite.visible = false
		$MeshInstance3D.visible = false
		$Head/Camera3D/GunPivot.visible = false

func _on_enemy_died(killer_path: String, amount: int):
	if not multiplayer.is_server(): return
	if killer_path == str(get_path()):
		score += amount
		update_score_on_client.rpc(score)
		
@rpc("any_peer", "call_local")
func sync_score_to_server(new_score):
	score = new_score
	
@rpc("any_peer", "call_local", "reliable")
func end_game_for_everyone():
	var world_node = get_tree().current_scene
	if world_node.has_node("EndGameCam"):
		world_node.get_node("EndGameCam").make_current()
	if multiplayer.is_server():
		for z in get_tree().get_nodes_in_group("zombie"):
			if z.has_method("freeze_zombie"):
				z.freeze_zombie.rpc()
	GlobalStats.final_scores.clear()
	var parent_node = get_parent()
	if parent_node:
		for p in parent_node.get_children():
			if p.has_method("add_score"):
				var id_int = str(p.name).to_int()
				var display_name = GlobalStats.network_names.get(id_int, "Player")
				GlobalStats.final_scores.append({
					"name": display_name, "score": p.score, "kills": p.zombie_kills
				})
				if p.has_method("is_multiplayer_authority") and p.is_multiplayer_authority():
					if p.has_node("UI"):
						p.get_node("UI").visible = true
						if is_instance_valid(p.stats_label): p.stats_label.visible = false
					if is_instance_valid(p.scoreboard):
						p.update_scoreboard()
						p.scoreboard.show()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var world = get_tree().current_scene
	if world.has_method("start_exit_timer"):
		world.start_exit_timer("res://Scenes/you_died.tscn")

func update_scoreboard():
	for child in scoreboard_list.get_children():
		child.queue_free()
	var header_row = HBoxContainer.new()
	scoreboard_list.add_child(header_row)
	var name_header = Label.new()
	name_header.text = "PLAYER"
	name_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_header.add_theme_color_override("font_color", Color(1, 1, 0))
	header_row.add_child(name_header)
	var score_header = Label.new()
	score_header.text = "SCORE"
	score_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_header.add_theme_color_override("font_color", Color(1, 1, 0))
	header_row.add_child(score_header)
	var kills_header = Label.new()
	kills_header.text = "KILLS"
	kills_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kills_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kills_header.add_theme_color_override("font_color", Color(1, 1, 0))
	header_row.add_child(kills_header)
	var spacer = Label.new()
	spacer.text = "--------------------------------------------------"
	spacer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scoreboard_list.add_child(spacer)
	var parent_node = get_parent()
	if not parent_node: return
	for p in parent_node.get_children():
		if p.has_method("add_score"):
			var row = HBoxContainer.new()
			scoreboard_list.add_child(row)
			var p_name = Label.new()
			p_name.text = p.display_name 
			p_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			p_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			row.add_child(p_name)
			var p_score = Label.new()
			p_score.text = str(p.score)
			p_score.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			p_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			row.add_child(p_score)
			var p_kills = Label.new()
			p_kills.text = str(p.zombie_kills)
			p_kills.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			p_kills.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			row.add_child(p_kills)

@rpc("any_peer", "call_local", "reliable")
func request_quit_sequence():
	if multiplayer.is_server():
		force_quit_to_everyone.rpc()

@rpc("any_peer", "call_local", "reliable")
func request_end_game():
	if multiplayer.is_server():
		end_game_for_everyone.rpc()

func switch_spectator():
	var living_players = []
	for p in get_tree().get_nodes_in_group("player"):
		if "is_dead" in p and not p.is_dead:
			living_players.append(p)
	if living_players.is_empty():
		if is_instance_valid(spectator_label):
			spectator_label.text = "Everyone is dead..."
		return 
	spectate_index = (spectate_index + 1) % living_players.size()
	spectated_player = living_players[spectate_index]
	if is_instance_valid(spectated_player) and is_instance_valid(spectated_player.camera):
		spectated_player.camera.make_current()
		if is_instance_valid(spectator_label):
			var peer_id = str(spectated_player.name).to_int()
			var display_name = GlobalStats.network_names.get(peer_id, "Teammate")
			spectator_label.text = "Spectating: " + display_name + "\nLeft-Click to switch players"
			spectator_label.show()
