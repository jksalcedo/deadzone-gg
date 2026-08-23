class_name Bomb
extends RigidBody3D

@export var fuse_time: float = 3.0
@export var blast_radius: float = 5.0
@export var blast_damage: float = 80.0
@export var throw_force: float = 12.0

var _thrower_id: int = 0
var _fuse_timer: float = 0.0
var _armed: bool = false
var _detonated: bool = false

@onready var blast_area: Area3D = get_node_or_null("BlastArea")

func throw_from(origin: Vector3, direction: Vector3, thrower_id: int) -> void:
	_thrower_id = thrower_id
	global_position = origin
	linear_velocity = direction * throw_force
	_armed = true

func _physics_process(delta: float) -> void:
	if not _armed or _detonated:
		return
	_fuse_timer += delta
	if _fuse_timer >= fuse_time:
		_detonate()

func _detonate() -> void:
	if _detonated:
		return
	_detonated = true
	
	var is_server_or_local = not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
	if is_server_or_local and blast_area:
		for body in blast_area.get_overlapping_bodies():
			if body.has_method("take_damage"):
				body.take_damage(blast_damage, _thrower_id)
	
	queue_free()
