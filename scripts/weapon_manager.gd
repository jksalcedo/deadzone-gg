class_name WeaponManager
extends Node3D

signal weapon_switched(weapon: Weapon)
signal weapon_fired(weapon: Weapon)
signal weapon_reloaded(weapon: Weapon)
signal weapon_reload_started(weapon: Weapon, duration: float)
signal weapon_reload_finished(weapon: Weapon)
signal weapon_reload_canceled(weapon: Weapon)
signal ammo_changed(current: int, reserve: int)
signal recoil_requested(pitch_kick: float)
signal hit_target(collider: Object, damage: float)

@export var weapons: Array[Weapon] = []
@export var active_weapon_index: int = 0
@export var is_firing_held: bool = false

var _player: CharacterBody3D
var _muzzle_marker: Marker3D

func _ready() -> void:
	_player = _find_parent_character()
	_collect_child_weapons()
	for w in weapons:
		_connect_weapon_signals(w)
	if not weapons.is_empty():
		set_active_weapon(0)
	_muzzle_marker = get_node_or_null("BulletPoint") as Marker3D

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

func _connect_weapon_signals(w: Weapon) -> void:
	if not w:
		return
	if not w.ammo_changed.is_connected(_on_weapon_ammo_changed.bind(w)):
		w.ammo_changed.connect(_on_weapon_ammo_changed.bind(w))
	if not w.reload_started.is_connected(_on_weapon_reload_started.bind(w)):
		w.reload_started.connect(_on_weapon_reload_started.bind(w))
	if not w.reloaded.is_connected(_on_weapon_reloaded.bind(w)):
		w.reloaded.connect(_on_weapon_reloaded.bind(w))
	if not w.reload_canceled.is_connected(_on_weapon_reload_canceled.bind(w)):
		w.reload_canceled.connect(_on_weapon_reload_canceled.bind(w))

func _on_weapon_ammo_changed(c: int, r: int, w: Weapon) -> void:
	if get_active_weapon() == w:
		ammo_changed.emit(c, r)

func _on_weapon_reload_started(duration: float, w: Weapon) -> void:
	if get_active_weapon() == w:
		weapon_reload_started.emit(w, duration)

func _on_weapon_reloaded(w: Weapon) -> void:
	if get_active_weapon() == w:
		weapon_reloaded.emit(w)
		weapon_reload_finished.emit(w)

func _on_weapon_reload_canceled(w: Weapon) -> void:
	if get_active_weapon() == w:
		weapon_reload_canceled.emit(w)

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

func pickup_weapon(scene: PackedScene) -> void:
	if not scene:
		return
	var instance := scene.instantiate() as Weapon
	if not instance:
		return
	add_child(instance)
	weapons.append(instance)
	_connect_weapon_signals(instance)
	# Hide all then switch to the new weapon
	set_active_weapon(weapons.size() - 1)
	weapon_switched.emit(instance)

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
			hit_target.emit(collider, weapon.damage)
			var attacker_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0
			collider.take_damage(weapon.damage, attacker_id)

func _spawn_visual_effects(weapon: Weapon, hit_point: Vector3) -> void:
	var muzzle: Marker3D = _muzzle_marker
	if not muzzle and weapon and weapon.muzzle_point:
		muzzle = weapon.muzzle_point

	var start_pos: Vector3 = muzzle.global_position if muzzle else global_position

	if weapon and weapon.muzzle_flash_scene:
		var flash = weapon.muzzle_flash_scene.instantiate()
		if muzzle:
			muzzle.add_child(flash)
		else:
			add_child(flash)

	if weapon and weapon.bullet_trail_scene:
		var trail = weapon.bullet_trail_scene.instantiate()
		get_tree().root.add_child(trail)
		if trail.has_method("init"):
			
			
			trail.init(start_pos, hit_point)
		else:
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
