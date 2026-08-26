class_name MuzzleFlash
extends Node3D

@export var _particles: GPUParticles3D
@export var _life_time: float = 0.3

func _ready() -> void:
	rotation.z = randf() * TAU
	if not _particles:
		_particles = get_node_or_null("GPUParticles3D")
	if _particles:
		_particles.emitting = true
	_start_lifetime_timer()

func _start_lifetime_timer() -> void:
	await get_tree().create_timer(_life_time).timeout
	if is_inside_tree():
		queue_free()
