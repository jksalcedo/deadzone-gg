class_name WeaponManager
extends Node3D

signal weapon_switched(weapon: Weapon)
signal weapon_fired(weapon: Weapon)
signal weapon_reloaded(weapon: Weapon)
signal ammo_changed(current: int, reserve: int)
signal recoil_requested(pitch_kick: float)

@export var weapons: Array[Weapon] = []
@export var active_weapon_index: int = 0
@export var is_firing_held: bool = false

var _player: CharacterBody3D

func _ready() -> void:
	_player = _find_parent_character()
	_collect_child_weapons()
	if not weapons.is_empty():
		set_active_weapon(0)

func _find_parent_character() -> CharacterBody3D:
	var current: Node = get_parent()
	while current:
		if current is CharacterBody3D:
			return current
		current = current.get_parent()
	return null

func _collect_child_weapons() -> void:
	if not weapons.is_empty():
		return
	for child in get_children():
		if child is Weapon:
			weapons.append(child)

func get_active_weapon() -> Weapon:
	if weapons.is_empty() or active_weapon_index < 0 or active_weapon_index >= weapons.size():
		return null
	return weapons[active_weapon_index]

func set_active_weapon(index: int) -> void:
	if index < 0 or index >= weapons.size():
		return

	var current = get_active_weapon()
	if current and current.is_reloading:
		current.cancel_reload()

	active_weapon_index = index
	for i in range(weapons.size()):
		weapons[i].visible = (i == index)

	var new_w = get_active_weapon()
	if new_w:
		weapon_switched.emit(new_w)
		ammo_changed.emit(new_w.current_ammo, new_w.reserve_ammo)

func cycle_weapon(step: int) -> void:
	if weapons.is_empty():
		return
	var next_idx = posmod(active_weapon_index + step, weapons.size())
	set_active_weapon(next_idx)

func reload_active() -> void:
	var active_w = get_active_weapon()
	if active_w:
		active_w.reload()

func process_firing(camera: Camera3D, crosshair: Crosshair = null) -> void:
	if not is_firing_held:
		return
	var active_w = get_active_weapon()
	if active_w and active_w.is_automatic:
		try_fire(camera, crosshair)

func try_fire(camera: Camera3D, crosshair: Crosshair = null) -> bool:
	var active_w = get_active_weapon()
	if not active_w or not active_w.can_shoot():
		return false

	if not active_w.shoot():
		return false

	if crosshair:
		crosshair.add_spread(4.0)

	recoil_requested.emit(active_w.recoil_kick)
	weapon_fired.emit(active_w)
	_perform_raycast(camera, active_w)
	return true

func _perform_raycast(camera: Camera3D, weapon: Weapon) -> void:
	if not camera:
		return

	var ray_origin: Vector3 = camera.global_position
	var ray_dir: Vector3 = -camera.global_transform.basis.z

	if weapon.spread > 0.0:
		var spread_x = randf_range(-weapon.spread, weapon.spread)
		var spread_y = randf_range(-weapon.spread, weapon.spread)
		ray_dir = (ray_dir + camera.global_transform.basis.x * spread_x + camera.global_transform.basis.y * spread_y).normalized()

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_dir * weapon.max_range
	)
	if _player:
		query.exclude = [_player.get_rid()]

	var result = space_state.intersect_ray(query)
	var target_pos: Vector3 = result.position if result else (ray_origin + ray_dir * weapon.max_range)
	_spawn_visual_effects(weapon, target_pos)

	if result:
		var collider = result.collider
		if collider and collider.has_method("take_damage"):
			if multiplayer.has_multiplayer_peer():
				rpc_id(1, "server_apply_damage", collider.get_path(), weapon.damage)
			else:
				var attacker_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0
				collider.take_damage(weapon.damage, attacker_id)

func _spawn_visual_effects(weapon: Weapon, hit_point: Vector3) -> void:
	if weapon.muzzle_flash_scene and weapon.muzzle_point:
		var flash = weapon.muzzle_flash_scene.instantiate()
		weapon.muzzle_point.add_child(flash)

	if weapon.bullet_trail_scene:
		var trail = weapon.bullet_trail_scene.instantiate()
		var start_pos: Vector3 = weapon.muzzle_point.global_position if weapon.muzzle_point else global_position
		get_tree().root.add_child(trail)
		trail.global_position = start_pos
		if start_pos.distance_squared_to(hit_point) > 0.001:
			trail.look_at(hit_point, Vector3.UP)
		if "max_distance" in trail:
			trail.max_distance = start_pos.distance_to(hit_point)

@rpc("any_peer", "call_local", "reliable")
func server_apply_damage(target_path: NodePath, amount: float) -> void:
	if not multiplayer.is_server():
		return
	var target = get_node_or_null(target_path)
	if target and target.has_method("take_damage"):
		var sender_id = multiplayer.get_remote_sender_id()
		target.take_damage(amount, sender_id)
