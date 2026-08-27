class_name WeaponSpawner
extends Node

## Pool of weapon scenes to randomly assign to spawn points.
@export var weapon_pool: Array[PackedScene] = []

## How many spawn points to actually fill (0 = fill all of them).
@export var max_spawns: int = 0

## Seconds before a picked-up weapon respawns at its point. 0 = no respawn.
@export var respawn_delay: float = 30.0

@export var pickup_scene: PackedScene = preload("res://scenes/weapon_pickup.tscn")

func _ready() -> void:
	if weapon_pool.is_empty() or not pickup_scene:
		return
	# Only the server spawns pickups (authoritative)
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	call_deferred("_spawn_all")

func _spawn_all() -> void:
	var points := get_tree().get_nodes_in_group("weapon_spawn_point")
	points.shuffle()

	var count := points.size() if max_spawns <= 0 else mini(max_spawns, points.size())
	for i in range(count):
		_spawn_at(points[i])

func _spawn_at(point: Node3D) -> void:
	if weapon_pool.is_empty():
		return
	var weapon_scene: PackedScene = weapon_pool[randi() % weapon_pool.size()]
	var pickup := pickup_scene.instantiate() as WeaponPickup
	pickup.weapon_scene = weapon_scene
	pickup.weapon_name_label = _scene_name(weapon_scene)
	pickup.single_use = true
	pickup.global_position = point.global_position

	get_tree().current_scene.add_child(pickup)

	if respawn_delay > 0.0:
		pickup.picked_up.connect(func(_n): _schedule_respawn(point), CONNECT_ONE_SHOT)

func _schedule_respawn(point: Node3D) -> void:
	await get_tree().create_timer(respawn_delay).timeout
	_spawn_at(point)

func _scene_name(scene: PackedScene) -> String:
	var path := scene.resource_path
	return path.get_file().get_basename().replace("-", " ").replace("_", " ").capitalize()
