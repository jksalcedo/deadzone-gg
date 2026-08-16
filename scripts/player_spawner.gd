class_name PlayerSpawner
extends MultiplayerSpawner

enum SpawnMode {
	RANDOM,
	ROUND_ROBIN,
	FARTHEST_FROM_PLAYERS
}

@export var player_scene: PackedScene = preload("res://scenes/player.tscn")
@export var spawn_points_parent: Node3D
@export var spawn_mode: SpawnMode = SpawnMode.RANDOM
@export var auto_spawn_on_connect: bool = true

var _round_robin_index: int = 0
var _spawn_points: Array[Node3D] = []

func _ready() -> void:
	spawn_function = _custom_spawn
	_cache_spawn_points()
	
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		
		if auto_spawn_on_connect:
			spawn_player(multiplayer.get_unique_id())

func _cache_spawn_points() -> void:
	_spawn_points.clear()
	if spawn_points_parent:
		for child in spawn_points_parent.get_children():
			if child is Node3D:
				_spawn_points.append(child)
	else:
		var grouped = get_tree().get_nodes_in_group("spawn_points")
		for node in grouped:
			if node is Node3D:
				_spawn_points.append(node)

func get_spawn_points() -> Array[Node3D]:
	if _spawn_points.is_empty():
		_cache_spawn_points()
	return _spawn_points

func get_next_spawn_point() -> Node3D:
	var points = get_spawn_points()
	if points.is_empty():
		return null
	
	match spawn_mode:
		SpawnMode.RANDOM:
			return points[randi() % points.size()]
		SpawnMode.ROUND_ROBIN:
			var point = points[_round_robin_index % points.size()]
			_round_robin_index = (_round_robin_index + 1) % points.size()
			return point
		SpawnMode.FARTHEST_FROM_PLAYERS:
			return _get_farthest_spawn_point(points)
		_:
			return points[0]

func _get_farthest_spawn_point(points: Array[Node3D]) -> Node3D:
	var container = get_node_or_null(spawn_path)
	if not container:
		return points[randi() % points.size()]
		
	var active_players = container.get_children()
	if active_players.is_empty():
		return points[randi() % points.size()]
	
	var best_point: Node3D = points[0]
	var max_min_dist: float = -1.0
	
	for point in points:
		var min_dist_to_player: float = INF
		for player in active_players:
			if player is Node3D:
				var dist = point.global_position.distance_squared_to(player.global_position)
				if dist < min_dist_to_player:
					min_dist_to_player = dist
		
		if min_dist_to_player > max_min_dist:
			max_min_dist = min_dist_to_player
			best_point = point
			
	return best_point

func spawn_player(peer_id: int) -> Node:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return null
		
	var container = get_node_or_null(spawn_path)
	if container and container.has_node(str(peer_id)):
		return container.get_node(str(peer_id))
	
	var spawn_point = get_next_spawn_point()
	var spawn_transform = spawn_point.global_transform if spawn_point else Transform3D.IDENTITY
	
	var spawn_data = {
		"peer_id": peer_id,
		"transform": spawn_transform
	}
	
	return spawn(spawn_data)

func _custom_spawn(data: Variant) -> Node:
	var player = player_scene.instantiate()
	var peer_id: int = data.get("peer_id", 1)
	var spawn_transform: Transform3D = data.get("transform", Transform3D.IDENTITY)
	
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	player.global_transform = spawn_transform
	return player

func respawn_player(peer_id: int) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
		
	var container = get_node_or_null(spawn_path)
	if container and container.has_node(str(peer_id)):
		var player = container.get_node(str(peer_id))
		var spawn_point = get_next_spawn_point()
		if spawn_point and player is Node3D:
			player.global_transform = spawn_point.global_transform
			if player is CharacterBody3D:
				player.velocity = Vector3.ZERO
	else:
		spawn_player(peer_id)

func remove_player(peer_id: int) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
		
	var container = get_node_or_null(spawn_path)
	if container and container.has_node(str(peer_id)):
		var player = container.get_node(str(peer_id))
		player.queue_free()

func _on_peer_connected(id: int) -> void:
	if auto_spawn_on_connect:
		spawn_player(id)

func _on_peer_disconnected(id: int) -> void:
	remove_player(id)
