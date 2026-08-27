class_name WeaponPickup
extends Area3D

signal picked_up(weapon_name: String)

@export var weapon_scene: PackedScene
@export var weapon_name_label: String = "Weapon"
@export var single_use: bool = true

@onready var _label: Label3D = get_node_or_null("Label3D")

var _nearby_players: Array[Node] = []
var _weapon_visual: Node3D = null

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_spawn_visual()
	if _label:
		_label.text = "[ E ]  %s" % weapon_name_label
		_label.visible = false

func _spawn_visual() -> void:
	if not weapon_scene:
		return
	_weapon_visual = weapon_scene.instantiate() as Node3D
	if not _weapon_visual:
		return
	_weapon_visual.set_script(null)
	add_child(_weapon_visual)

func _process(delta: float) -> void:
	if _weapon_visual:
		_weapon_visual.rotate_y(delta * 1.2)

	if _label:
		_label.visible = not _nearby_players.is_empty()

	if Input.is_action_just_pressed("interact"):
		for player in _nearby_players:
			if _is_local(player):
				_try_pickup(player)
				break

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("players"):
		_nearby_players.append(body)

func _on_body_exited(body: Node3D) -> void:
	_nearby_players.erase(body)

func _try_pickup(player: Node) -> void:
	var peer_id: int = player.get("player_id") if player.get("player_id") != null else 1
	_do_grant(player, peer_id)

func _do_grant(player: Node, peer_id: int) -> void:
	var weapon_manager := _find_weapon_manager(player)
	if not weapon_manager or not weapon_scene:
		return

	weapon_manager.pickup_weapon(weapon_scene)
	picked_up.emit(weapon_name_label)

	if single_use:
		queue_free()

func _is_local(player: Node) -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	var pid: int = player.get("player_id") if player.get("player_id") != null else 1
	return pid == multiplayer.get_unique_id()

func _find_weapon_manager(player: Node) -> WeaponManager:
	for child in player.get_children():
		var r := _search_wm(child)
		if r:
			return r
	return null

func _search_wm(node: Node) -> WeaponManager:
	if node is WeaponManager:
		return node
	for child in node.get_children():
		var r := _search_wm(child)
		if r:
			return r
	return null
