extends Node3D

const SPEED = 40.0

@onready var ray = $bullet/RayCast3D
@onready var ray2 = $bullet2/RayCast3D
@onready var ray3 = $bullet3/RayCast3D
@onready var ray4 = $bullet4/RayCast3D
@onready var ray5 = $bullet5/RayCast3D
@onready var ray6 = $bullet6/RayCast3D
@onready var mesh = $bullet/MeshInstance3D
@onready var mesh2 = $bullet2/MeshInstance3D
@onready var mesh3 = $bullet3/MeshInstance3D
@onready var mesh4 = $bullet4/MeshInstance3D
@onready var mesh5 = $bullet5/MeshInstance3D
@onready var mesh6 = $bullet6/MeshInstance3D

@onready var particles = $bullet/GPUParticles3D
@onready var particles2 = $bullet2/GPUParticles3D
@onready var particles3 = $bullet3/GPUParticles3D
@onready var particles4 = $bullet4/GPUParticles3D
@onready var particles5 = $bullet5/GPUParticles3D
@onready var particles6 = $bullet6/GPUParticles3D

func _process(delta):
	position += transform.basis * Vector3(0, 0, -SPEED) * delta
	if ray.is_colliding():
		mesh.visible = false
		particles.emitting = true
		ray.enabled = false
		await get_tree().create_timer(1.0).timeout
		queue_free()
	if ray2.is_colliding():
		mesh2.visible = false
		particles2.emitting = true
		ray2.enabled = false
		await get_tree().create_timer(1.0).timeout
		queue_free()
	if ray3.is_colliding():
		mesh3.visible = false
		particles3.emitting = true
		ray3.enabled = false
		await get_tree().create_timer(1.0).timeout
		queue_free()
	if ray4.is_colliding():
		mesh4.visible = false
		particles4.emitting = true
		ray4.enabled = false
		await get_tree().create_timer(1.0).timeout
		queue_free()
	if ray5.is_colliding():
		mesh5.visible = false
		particles5.emitting = true
		ray5.enabled = false
		await get_tree().create_timer(1.0).timeout
		queue_free()
	if ray6.is_colliding():
		mesh6.visible = false
		particles6.emitting = true
		ray6.enabled = false
		await get_tree().create_timer(1.0).timeout
		queue_free()

func _on_timer_timeout() -> void:
	queue_free()
