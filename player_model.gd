extends CharacterBody3D

var speed
const WALK_SPEED = 5.0
const SPRINT_SPEED = 8.0
const JUMP_VELOCITY = 3
const SENSITIVITY = 0.02
const BOB_FREQ = 2.0
const BOB_AMP = 0.08
var t_bob = 0.0
const BASE_FOV = 75.0
const FOV_CHANGE = 1.5
const HIT_STAGGER = 4.0
const SHOTGUN_RECOIL = 3.0

signal player_hit

var bullet = load("res://Models/bullet.tscn")
var shotgun_bullet = load("res://Models/shotgun_bullet.tscn")
var bullet_trail = load("res://Models/bullet_trail.tscn")
var instance

var rifle_mag = 30
var rifle_reserve = 90
const RIFLE_MAG_SIZE = 30

var shotgun_mag = 8
var shotgun_reserve = 24
const SHOTGUN_MAG_SIZE = 8

var is_reloading = false

const MAX_PLAYER_HEALTH = 100
var player_health
var score = 0

@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var gun_anim = $Head/Camera3D/GunPivot/rifle/AnimationPlayer
@onready var shotgun_anim = $Head/Camera3D/GunPivot/shotgun/AnimationPlayer
@onready var gun_barrel = $Head/Camera3D/GunPivot/rifle/RayCast3D
@onready var shotgun_barrel = $Head/Camera3D/GunPivot/shotgun/RayCast3D
@onready var rifle = $Head/Camera3D/GunPivot/rifle
@onready var shotgun = $Head/Camera3D/GunPivot/shotgun
@onready var aim_ray = $Head/Camera3D/AimRay
@onready var aim_ray_end = $Head/Camera3D/AimRayEnd
@onready var guns_anim = $Head/Camera3D/AnimationPlayer
@onready var stats_label = $UI/StatsLabel

var pause_menu_scene = preload("res://Scenes/pause.tscn")
var pause_menu_instance = null

func add_score(amount):
	score += amount
	

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	player_health = MAX_PLAYER_HEALTH

func _unhandled_input(event) -> void:
	if event is InputEventMouseMotion:
		head.rotate_y(-event.relative.x * SENSITIVITY)
		var new_x_rot = camera.rotation.x + (-event.relative.y * SENSITIVITY)
		camera.rotation.x = clamp(new_x_rot, deg_to_rad(-60), deg_to_rad(60))
		
func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		
	if Input.is_action_pressed("sprint"):
		speed = SPRINT_SPEED
	else:
		speed = WALK_SPEED
	if Input.is_action_pressed("reload"):
		_reload()

	
	var input_dir = Input.get_vector("right", "left", "back", "forward")
	
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if is_on_floor():
		if direction:
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
		else:
			velocity.x = lerp(velocity.x, direction.x * speed, delta * 7.0)
			velocity.z = lerp(velocity.z, direction.z * speed, delta * 7.0)

	else:
		velocity.x = lerp(velocity.x, direction.x * speed, delta * 3.0)
		velocity.z = lerp(velocity.z, direction.z * speed, delta * 3.0)
	
	t_bob += delta * velocity.length() * float(is_on_floor())
	camera.transform.origin = _headbob(t_bob)
	
	var velocity_clamped = clamp(velocity.length(), 0.5, SPRINT_SPEED * 2)
	var target_fov = BASE_FOV + FOV_CHANGE * velocity_clamped
	camera.fov = lerp(camera.fov, target_fov, delta * 8.0)
	
	if Input.is_action_pressed("rifle"):
		guns_anim.play("LowerShotgun")
		shotgun.visible = false
		rifle.visible = true
		guns_anim.play("RaiseRifle")
		is_reloading = false

		
	if Input.is_action_pressed("shotgun"):
		guns_anim.play("LowerRifle")
		rifle.visible = false
		shotgun.visible = true
		guns_anim.play("RaiseShotgun")
		is_reloading = false
	
	if Input.is_action_pressed("shoot"):
		if shotgun.visible == true:
			_shoot_shotgun()
		if rifle.visible == true:
			_shoot_rifle()
	
	move_and_slide()
	update_ui()

func _headbob(time) -> Vector3:
	var pos = Vector3.ZERO
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = cos(time * BOB_FREQ / 2) * BOB_AMP
	return pos
	
func attacked(dir):
	emit_signal("player_hit")
	velocity += dir * HIT_STAGGER
	player_health -= 5

func _input(event):
	if event.is_action_pressed("pause"):
		toggle_pause()

func _shoot_rifle():
	if rifle_mag > 0 and not is_reloading:
		if not gun_anim.is_playing():
			rifle_mag -= 1
			gun_anim.play("shoot")
			instance = bullet_trail.instantiate()
			var new_bullet = bullet.instantiate()
			get_parent().add_child(new_bullet)
			new_bullet.global_transform = gun_barrel.global_transform
			if aim_ray.is_colliding() and aim_ray.get_collider().is_in_group("enemy"):
				instance.init(gun_barrel.global_position, aim_ray.get_collision_point())
				aim_ray.get_collider().rifle_hit()
			else:
				var _target_pos = aim_ray.get_collision_point() if aim_ray.is_colliding() else aim_ray_end.global_position
				get_parent().add_child(instance)
	elif rifle_mag <= 0:
		_reload()

func _shoot_shotgun():
	if shotgun_mag > 0 and not is_reloading:
		if not shotgun_anim.is_playing():
			shotgun_mag -= 1
			shotgun_anim.play("shoot")
			instance = bullet_trail.instantiate()
			var new_bullet2 = shotgun_bullet.instantiate()
			get_parent().add_child(new_bullet2)
			new_bullet2.global_transform = shotgun_barrel.global_transform
			velocity -= head.transform.basis.z * SHOTGUN_RECOIL
			if aim_ray.is_colliding() and aim_ray.get_collider().is_in_group("enemy"):
				instance.init(shotgun_barrel.global_position, aim_ray.get_collision_point())
				aim_ray.get_collider().shotgun_hit()
			else:
				get_parent().add_child(instance)
	elif shotgun_mag <= 0:
		_reload()


func _reload():
	if is_reloading: return
	var current_mag = rifle_mag if rifle.visible else shotgun_mag
	var current_reserve = rifle_reserve if rifle.visible else shotgun_reserve
	var max_size = RIFLE_MAG_SIZE if rifle.visible else SHOTGUN_MAG_SIZE
	if current_mag == max_size or current_reserve <= 0:
		return
	is_reloading = true
	if rifle.visible:
		guns_anim.play("reload_r")
	else:
		guns_anim.play("reload")
	await get_tree().create_timer(2.0).timeout
	var amount_needed = max_size - current_mag
	var reload_amount = min(current_reserve, amount_needed)
	if rifle.visible:
		rifle_mag += reload_amount
		rifle_reserve -= reload_amount
	else:
		shotgun_mag += reload_amount
		shotgun_reserve -= reload_amount
	is_reloading = false

func update_ui():
	if stats_label == null:
		return
	var gun_name = "Rifle" if rifle.visible else "Shotgun"
	var current_mag = rifle_mag if rifle.visible else shotgun_mag
	var current_reserve = rifle_reserve if rifle.visible else shotgun_reserve
	var max_mag = RIFLE_MAG_SIZE if rifle.visible else SHOTGUN_MAG_SIZE
	var ammo_needed = max_mag - current_mag
	var ui_text = "Gun: %s\n" % gun_name
	ui_text += "Ammo: %d / %d\n" % [current_mag, current_reserve]
	ui_text += "Ammo Needed: %d\n" % ammo_needed
	ui_text += "Health: %d / %d\n" % [player_health, MAX_PLAYER_HEALTH]
	ui_text += "Score: %d" % score
	stats_label.text = ui_text

func toggle_pause():
	get_tree().paused = !get_tree().paused
	if get_tree().paused:
		if pause_menu_instance == null:
			pause_menu_instance = pause_menu_scene.instantiate()
			$UI.add_child(pause_menu_instance) 
		pause_menu_instance.show()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		if pause_menu_instance:
			pause_menu_instance.hide()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
