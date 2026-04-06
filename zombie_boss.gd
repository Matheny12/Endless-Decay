extends CharacterBody3D

var is_frozen: bool = false
var is_dead: bool = false
var last_attacker:String=""
var player=null
var state_machine
var health: int = 0
var base_max_health: int = 100
var max_health: int = 100
var current_speed=6.0
const SPEED=6.0
const ATTACK_RANGE=3.5
var attack_damage = 20
@export var is_boss:bool=true
@export var player_path:="/root/World/Player"
@onready var nav_agent=$NavigationAgent3D
@onready var anim_tree=$AnimationTree
@export var ammo_box=preload("res://Scenes/ammo_box.tscn")
@export var medkit=preload("res://Scenes/medkit.tscn")
@export var drop_chance=1
@onready var health_bar_sprite=$HealthBarSprite
@onready var health_bar=$HealthBarSprite/SubViewport/TextureProgressBar
@onready var zombie_mesh=$Armature/Skeleton/ZombieBody
@onready var health_label=$HealthBarSprite/SubViewport/HealthLabel
var dead:bool=false
signal zombie_hit

func _ready():
	player=get_node(player_path)
	state_machine=anim_tree.get("parameters/playback")
	current_speed=SPEED+randf_range(-0.5,1.5)
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	GlobalStats.zombie_count_changed.connect(_on_global_kills_updated)
	if GlobalStats.game_difficulty == "Easy":
		base_max_health = 50
		attack_damage = 15
	elif GlobalStats.game_difficulty == "Normal":
		base_max_health = 100
		attack_damage = 20
	elif GlobalStats.game_difficulty == "Hard":
		base_max_health = 200
		attack_damage = 25
	max_health = base_max_health
	health = max_health
	_apply_buffs(GlobalStats.total_zombies_killed)

func _process(delta):
	if is_frozen: 
		return
	if is_instance_valid(health_bar) and health_bar_sprite.visible:
		health_bar.value=health
		if is_instance_valid(health_label):health_label.text="Zombie Boss: "+str(health)+" / "+str(max_health)
	if not multiplayer.is_server() or dead:return
	player=_get_closest_player()
	if player==null or not is_instance_valid(player):
		state_machine.travel("idle")
		velocity=Vector3.ZERO
		return
	match state_machine.get_current_node():
		"run":
			nav_agent.set_target_position(player.global_position)
			var next_nav_point=nav_agent.get_next_path_position()
			var new_velocity=(next_nav_point-global_position).normalized()*current_speed
			if nav_agent.avoidance_enabled:nav_agent.set_velocity(new_velocity)
			else:_on_velocity_computed(new_velocity)
			rotation.y=lerp_angle(rotation.y,atan2(-new_velocity.x,-new_velocity.z),delta*10.0)
		"hit":
			velocity=Vector3.ZERO
			look_at(Vector3(player.global_position.x,global_position.y,player.global_position.z),Vector3.UP)
		"idle":velocity=Vector3.ZERO
	if not is_on_floor():velocity.y-=9.8*delta
	anim_tree.set("parameters/conditions/hit",_target_in_range())
	anim_tree.set("parameters/conditions/run",!_target_in_range())
	var hp=float(health)/float(max_health)
	health_bar.modulate=Color(1.0-hp,hp,0,1.0)

func _on_velocity_computed(safe_velocity:Vector3):
	if dead:return
	velocity=safe_velocity
	move_and_slide()

func _get_closest_player():
	var ps=get_tree().get_nodes_in_group("player")
	var c=null
	var md=INF
	for p in ps:
		if p.get("is_dead"):continue
		var d=global_position.distance_to(p.global_position)
		if d<md:md=d;c=p
	return c

func _target_in_range():
	return player!=null and global_position.distance_to(player.global_position)<ATTACK_RANGE

func _hit_finished():
	if dead:return
	if player and is_instance_valid(player):
		if player.get("is_dead"):return
		if global_position.distance_to(player.global_position)<ATTACK_RANGE+1.0:
			player.attacked.rpc(global_position.direction_to(player.global_position),attack_damage)

func _on_area_3d_rifle_shot(dam):
	if dead:return
	health-=dam
	health_bar.value=health
	emit_signal("zombie_hit")
	if health<=0:_zombie_die()

func _on_area_3d_shotgun_shot(dam):
	if dead:return
	health-=dam
	health_bar.value=health
	emit_signal("zombie_hit")
	if health<=0:_zombie_die()

func _drop_item():
	var lp=[ammo_box,ammo_box,ammo_box,medkit,medkit,medkit]
	for s in lp:
		var i=s.instantiate()
		get_parent().add_child(i)
		i.global_position=global_position+Vector3(randf_range(-0.5,0.5),3.0,randf_range(-0.5,0.5))
		if i is RigidBody3D:i.apply_central_impulse(Vector3(randf_range(-1.5,1.5),3.0,randf_range(-1.5,1.5)).normalized()*4.0)

func _zombie_die():
	if dead: return
	dead = true
	velocity = Vector3.ZERO
	health_bar_sprite.visible = false
	if multiplayer.is_server():
		var kill_value = 500 if is_boss else 100
		if last_attacker != "":
			var killer = get_node_or_null(last_attacker)
			if killer:
				if killer.has_method("add_score"):
					killer.add_score.rpc(kill_value)
				if killer.has_method("add_zombie_kill"):
					killer.add_zombie_kill.rpc()
		GlobalStats.total_zombies_killed += 1
		for p in get_tree().get_nodes_in_group("player"):
			if p.has_method("sync_global_kills"):
				p.sync_global_kills.rpc(GlobalStats.total_zombies_killed)
		_drop_item() 
	$CollisionShape3D.set_deferred("disabled", true)
	remove_from_group("zombie")
	anim_tree.set("parameters/conditions/death", true)
	await get_tree().create_timer(4.0).timeout
	queue_free()

func set_health_bar_visible(v):
	if not dead:health_bar_sprite.visible=v

func _on_global_kills_updated(nc):
	_apply_buffs(nc)

func _apply_buffs(kc):
	var buff_multiplier = floor(kc / 20)
	var old_max = max_health
	var new_max = base_max_health + (buff_multiplier * 200)
	if new_max > old_max:
		max_health = new_max
		health += (new_max - old_max)
	if is_instance_valid(health_bar):
		health_bar.max_value = max_health
		health_bar.value = health

func change_skin(t):
	zombie_mesh.get_active_material(0).albedo_texture=t

func register_hit(dam,ih,sh):
	if dead:return
	health-=dam
	if is_instance_valid(health_bar):health_bar.value=health
	emit_signal("zombie_hit")
	if health<=0:_zombie_die()

@rpc("any_peer","call_local")
func set_last_attacker(id):
	last_attacker=id
	
@rpc("authority", "call_local", "reliable")
func freeze_zombie():
	is_frozen = true
	if has_node("NavigationAgent3D"):
		$NavigationAgent3D.set_velocity(Vector3.ZERO)
	velocity = Vector3.ZERO
	if has_node("AnimationPlayer"):
		$AnimationPlayer.pause()
	elif has_node("AnimationTree"):
		$AnimationTree.active = false
