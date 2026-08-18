class_name BulletTrail
extends Node3D

@export var _trail_mesh: MeshInstance3D
@export var _bullet_trail_speed: float = 80.0
@export var _bullet_trail_life_time: float = 1.0

var max_distance: float = 0.0
var _trail_mesh_height: float = 0.0

func _ready() -> void:
	if not _trail_mesh:
		_trail_mesh = get_node_or_null("MeshInstance3D")
	if _trail_mesh and _trail_mesh.mesh and "height" in _trail_mesh.mesh:
		_trail_mesh_height = _trail_mesh.mesh.height
	
	if max_distance == 0.0:
		_start_lifetime_timer()

func _process(delta: float) -> void:
	_move_trail(delta)
	
	if max_distance > 0.0 and _has_reached_max_distance():
		queue_free()

func _start_lifetime_timer() -> void:
	await get_tree().create_timer(_bullet_trail_life_time).timeout
	if is_inside_tree():
		queue_free()

func _move_trail(delta: float) -> void:
	if _trail_mesh:
		_trail_mesh.position += Vector3.FORWARD * _bullet_trail_speed * delta
	else:
		position += -global_transform.basis.z * _bullet_trail_speed * delta

func _has_reached_max_distance() -> bool:
	var mesh_pos = _trail_mesh.global_position if _trail_mesh else global_position
	var current_distance := global_position.distance_to(mesh_pos)
	var target_distance := max_distance - (_trail_mesh_height * 2.0)
	
	return current_distance >= target_distance
