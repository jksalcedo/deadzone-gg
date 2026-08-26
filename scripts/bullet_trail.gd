class_name BulletTrail
extends Node3D

@export var gpu_particles: GPUParticles3D
## Visual tracer speed in units/sec. Bullet damage is instant (raycast).
## Keep low enough so the trail spans multiple frames (60-120 is good).
@export var tracer_speed: float = 80.0

var _total_lifetime: float = 0.5
var _timer: float = 0.0

func init(start_pos: Vector3, target_pos: Vector3) -> void:
	if not gpu_particles:
		gpu_particles = get_node_or_null("GPUParticles3D") as GPUParticles3D
	if not gpu_particles:
		return

	var dist := start_pos.distance_to(target_pos)
	if dist < 0.01:
		queue_free()
		return

	var world_dir := (target_pos - start_pos).normalized()
	# Minimum 0.08s so the trail spans at least ~5 frames at 60fps
	var travel_time := maxf(dist / tracer_speed, 0.08)
	var speed := dist / travel_time

	# Position + orient atomically
	var up := Vector3.UP if abs(world_dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	global_transform = Transform3D(Basis.looking_at(world_dir, up), start_pos)

	var mat := gpu_particles.process_material.duplicate() as ParticleProcessMaterial
	mat.direction = Vector3(0.0, 0.0, -1.0)   # local -Z = world_dir (via look_at)
	mat.spread = 0.0
	mat.gravity = Vector3.ZERO
	mat.initial_velocity_min = speed
	mat.initial_velocity_max = speed
	gpu_particles.process_material = mat
	gpu_particles.lifetime = travel_time

	# Keep the node alive until the trail has fully faded
	_total_lifetime = travel_time + gpu_particles.trail_lifetime + 0.05
	gpu_particles.emitting = true

func _ready() -> void:
	if not gpu_particles:
		gpu_particles = get_node_or_null("GPUParticles3D") as GPUParticles3D

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= _total_lifetime:
		queue_free()
