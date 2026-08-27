class_name AmmoPickup
extends Area3D

signal picked_up(label: String)

## Ammo added to reserve for each eligible weapon.
@export var ammo_per_weapon: int = 30
## If true, refills all weapons in inventory. If false, only the active weapon.
@export var refill_all: bool = true
## Label shown in the floating prompt.
@export var display_label: String = "Ammo"
@export var single_use: bool = true
@export var respawn_delay: float = 0.0

@onready var _label: Label3D = get_node_or_null("Label3D")

var _nearby_players: Array[Node] = []

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if _label:
		_label.text = "[ E ]  %s" % display_label
		_label.visible = false

func _process(delta: float) -> void:
	# Spin the crate
	rotation.y += delta * 0.8

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
	var weapon_manager := _find_weapon_manager(player)
	if not weapon_manager:
		return

	if refill_all:
		for w in weapon_manager.weapons:
			if w is Melee:
				continue
			w.reserve_ammo = mini(w.reserve_ammo + ammo_per_weapon, w.max_reserve_ammo)
			w.ammo_changed.emit(w.current_ammo, w.reserve_ammo)
	else:
		var w := weapon_manager.get_active_weapon()
		if w and not (w is Melee):
			w.reserve_ammo = mini(w.reserve_ammo + ammo_per_weapon, w.max_reserve_ammo)
			w.ammo_changed.emit(w.current_ammo, w.reserve_ammo)

	picked_up.emit(display_label)

	if single_use:
		if respawn_delay > 0.0:
			_hide_temporarily()
		else:
			queue_free()

func _hide_temporarily() -> void:
	visible = false
	monitoring = false
	_nearby_players.clear()
	await get_tree().create_timer(respawn_delay).timeout
	if is_inside_tree():
		visible = true
		monitoring = true

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
