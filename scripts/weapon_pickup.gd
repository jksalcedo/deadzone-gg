class_name WeaponPickup
extends Area3D

signal picked_up(weapon_name: String)

@export var weapon_scene: PackedScene
@export var weapon_name_label: String = "Weapon"
## If true, the pickup disappears after the first player picks it up.
## If false, each player can pick it up independently (respawning).
@export var single_use: bool = true

var _picked_up_by: Array[int] = []

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if not body.has_method("_is_player"):
		return
	var peer_id := _get_peer_id(body)
	if peer_id in _picked_up_by:
		return

	if multiplayer.is_server():
		_grant_weapon.rpc(peer_id)

func _get_peer_id(player: Node) -> int:
	if player.has_meta("peer_id"):
		return player.get_meta("peer_id")
	if player.get("player_id") != null:
		return player.player_id
	return 1

@rpc("authority", "call_local", "reliable")
func _grant_weapon(peer_id: int) -> void:
	if not multiplayer.get_unique_id() == peer_id and not multiplayer.is_server():
		return

	var local_id := multiplayer.get_unique_id()
	if local_id != peer_id:
		return

	var player := _find_local_player()
	if not player:
		return

	var weapon_manager := _find_weapon_manager(player)
	if not weapon_manager or not weapon_scene:
		return

	weapon_manager.pickup_weapon(weapon_scene)
	picked_up.emit(weapon_name_label)

	_picked_up_by.append(peer_id)
	if single_use:
		queue_free()

func _find_local_player() -> Node:
	for child in get_tree().get_nodes_in_group("players"):
		if child.get("player_id") == multiplayer.get_unique_id():
			return child
	return null

func _find_weapon_manager(player: Node) -> WeaponManager:
	for child in player.get_children():
		var r := _search_weapon_manager(child)
		if r:
			return r
	return null

func _search_weapon_manager(node: Node) -> WeaponManager:
	if node is WeaponManager:
		return node
	for child in node.get_children():
		var r := _search_weapon_manager(child)
		if r:
			return r
	return null
