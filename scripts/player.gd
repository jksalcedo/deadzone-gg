class_name Player
extends CharacterBody3D

signal health_changed(current: float, max: float)
signal camera_mode_changed(mode: CameraMode)
signal bomb_count_changed(current: int, max_count: int)

enum CameraMode {
	FPS,
	TPS
}

@export_group("Movement")
@export var walk_speed: float = 8.0
@export var sprint_speed: float = 13.0
@export var crouch_speed: float = 4.5
@export var ground_accel: float = 20.0
@export var ground_decel: float = 22.0
@export var air_accel: float = 16.0
@export var air_decel: float = 12.0

@export_group("Jump & Gravity")
@export var jump_velocity: float = 8.5
@export var gravity: float = 24.0
@export var fall_gravity_multiplier: float = 1.3
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.1

@export_group("Crouch")
@export var crouch_height: float = 1.2
@export var stand_height: float = 2.0
@export var crouch_transition_speed: float = 10.0

@export_group("Camera")
@export var mouse_sensitivity: float = 0.0025
@export var default_camera_mode: CameraMode = CameraMode.TPS
@export var tps_distance: float = 3.5
@export var tps_offset: Vector3 = Vector3(0.5, 0.5, 0.0)
@export var min_pitch: float = -89.0
@export var max_pitch: float = 89.0
@export var base_fov: float = 80.0
@export var sprint_fov: float = 85.0
@export var fov_lerp_speed: float = 6.0

@export_group("Head Bob")
@export var bob_enabled: bool = true
@export var bob_frequency: float = 2.2
@export var bob_h_amplitude: float = 0.04
@export var bob_v_amplitude: float = 0.025
@export var sprint_bob_multiplier: float = 1.4

@export_group("Landing & Sway")
@export var landing_impact_strength: float = 0.06
@export var landing_recovery_speed: float = 8.0
@export var weapon_sway_amount: float = 0.003
@export var weapon_sway_speed: float = 10.0

@export_group("Health")
@export var max_health: float = 100.0
var health: float = 100.0

@export_group("Node References")
@export var camera_pivot: Node3D
@export var spring_arm: SpringArm3D
@export var camera: Camera3D
@export var body_mesh: MeshInstance3D
@export var eyes_node: Node3D
@export var weapon_manager: WeaponManager
@export var hud: CanvasLayer
@export var right_hand_attach: Marker3D
@export var anim_player: AnimationPlayer

@export_group("Bomb")
@export var bomb_scene: PackedScene
@export var bomb_spawn_marker: Marker3D
@export var bomb_count: int = 3
@export var bomb_cooldown: float = 0.5
@export var crosshair: Crosshair

var current_camera_mode: CameraMode = CameraMode.TPS

# Movement state
var _is_crouching: bool = false
var _was_on_floor: bool = true
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _fall_velocity: float = 0.0

# Bomb state
var _bombs_remaining: int = 0
var _bomb_cooldown_timer: float = 0.0

# Camera state
var _bob_timer: float = 0.0
var _camera_pivot_base_y: float = 0.0
var _landing_offset: float = 0.0
var _weapon_holder_base_pos: Vector3 = Vector3.ZERO
var _mouse_delta: Vector2 = Vector2.ZERO

# Collision
var _collision_shape: CollisionShape3D
var _capsule_shape: CapsuleShape3D

# Multiplayer sync variables
@export var sync_position: Vector3 = Vector3.ZERO
@export var sync_rotation_y: float = 0.0
@export var sync_pitch: float = 0.0
@export var sync_weapon_index: int = 0

var player_id: int = 1

func _ready() -> void:
	player_id = get_multiplayer_authority() if multiplayer.has_multiplayer_peer() else 1
	add_to_group("players")
	health = max_health
	_bombs_remaining = bomb_count
	bomb_count_changed.emit(_bombs_remaining, bomb_count)

	if not camera_pivot:
		camera_pivot = get_node_or_null("CameraPivot")
	if not spring_arm and camera_pivot:
		spring_arm = camera_pivot.get_node_or_null("SpringArm3D")
	if not camera:
		if spring_arm:
			camera = spring_arm.get_node_or_null("Camera3D")
		elif camera_pivot:
			camera = camera_pivot.get_node_or_null("Camera3D")
	if not weapon_manager:
		if camera_pivot and camera_pivot.has_node("WeaponHolder"):
			weapon_manager = camera_pivot.get_node("WeaponHolder") as WeaponManager
		elif has_node("WeaponManager"):
			weapon_manager = get_node("WeaponManager") as WeaponManager

	if not bomb_spawn_marker:
		if weapon_manager and weapon_manager.has_node("Marker3D"):
			bomb_spawn_marker = weapon_manager.get_node("Marker3D") as Marker3D
		elif has_node("CameraPivot/WeaponHolder/Marker3D"):
			bomb_spawn_marker = get_node("CameraPivot/WeaponHolder/Marker3D") as Marker3D
		else:
			bomb_spawn_marker = find_child("Marker3D", true, false) as Marker3D

	if not hud:
		hud = get_node_or_null("HUD")
	if not crosshair and hud:
		crosshair = hud.get_node_or_null("Crosshair")

	_collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _collision_shape:
		_capsule_shape = _collision_shape.shape as CapsuleShape3D

	if not anim_player:
		anim_player = get_node_or_null("character-a2/AnimationPlayer") as AnimationPlayer

	if camera_pivot:
		_camera_pivot_base_y = camera_pivot.position.y

	if weapon_manager:
		weapon_manager.recoil_requested.connect(_on_recoil_requested)
		weapon_manager.weapon_switched.connect(_on_weapon_switched_melee)
		weapon_manager.weapon_fired.connect(_on_weapon_fired_anim)
		weapon_manager.weapon_picked_up.connect(_on_weapon_picked_up_anim)
		_weapon_holder_base_pos = weapon_manager.position
		_sync_melee_visual(weapon_manager.get_active_weapon())

	if anim_player:
		anim_player.animation_finished.connect(_on_anim_finished)

	if hud and hud.has_method("initialize"):
		hud.initialize(self, weapon_manager)

	if spring_arm:
		spring_arm.add_excluded_object(get_rid())

	if not _is_local_authority():
		if camera:
			camera.current = false
		if hud:
			hud.visible = false
		set_process_unhandled_input(false)
		return

	if camera:
		camera.current = true
		camera.fov = base_fov

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	set_camera_mode(default_camera_mode, true)

func _is_local_authority() -> bool:
	return not multiplayer.has_multiplayer_peer() or is_multiplayer_authority()

func _on_weapon_switched_melee(weapon: Weapon) -> void:
	_current_anim = ""  # force re-evaluate pose on next frame
	_sync_melee_visual(weapon)

func _sync_melee_visual(weapon: Weapon) -> void:
	if not right_hand_attach or not weapon_manager:
		return
	var is_melee := weapon is Melee
	for w in weapon_manager.weapons:
		if w is Melee:
			w.visible = false
	right_hand_attach.visible = is_melee

var _current_anim: String = ""
var _is_oneshot: bool = false

func _play_anim(name: String) -> void:
	if not anim_player or _current_anim == name:
		return
	_current_anim = name
	anim_player.play(name)

func _play_oneshot(name: String) -> void:
	if not anim_player:
		return
	_is_oneshot = true
	_current_anim = name
	anim_player.play(name)

func _on_anim_finished(anim_name: String) -> void:
	if _is_oneshot and anim_name == _current_anim:
		_is_oneshot = false
		_current_anim = ""  # let _update_animation pick the right base pose next frame

func _on_weapon_fired_anim(weapon: Weapon) -> void:
	if weapon is Melee:
		_play_oneshot("attack-melee-right")
	else:
		_play_oneshot("holding-both-shoot")

func _on_weapon_picked_up_anim(_weapon: Weapon) -> void:
	_play_oneshot("pick-up")

func _update_animation(direction: Vector3, sprinting: bool, on_floor: bool) -> void:
	if not anim_player or _is_oneshot:
		return

	var active_w := weapon_manager.get_active_weapon() if weapon_manager else null
	var is_melee := active_w is Melee
	var moving := direction.length_squared() > 0.01 and on_floor

	if moving:
		_play_anim("sprint" if sprinting else "walk")
	elif is_melee:
		_play_anim("idle")
	else:
		_play_anim("holding-both")

func _unhandled_input(event: InputEvent) -> void:
	if not _is_local_authority():
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_delta += event.relative
		rotate_y(-event.relative.x * mouse_sensitivity)
		if camera_pivot:
			camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
			camera_pivot.rotation.x = clamp(
				camera_pivot.rotation.x,
				deg_to_rad(min_pitch),
				deg_to_rad(max_pitch)
			)

	# Firing & Weapon cycling
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and event.pressed:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				if weapon_manager:
					weapon_manager.is_firing_held = event.pressed
					if event.pressed:
						weapon_manager.try_fire(camera, crosshair)
		elif event.pressed and weapon_manager:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				weapon_manager.cycle_weapon(-1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				weapon_manager.cycle_weapon(1)

	if event is InputEventKey and event.pressed and not event.echo:
		# Weapon selection
		if event.keycode >= KEY_1 and event.keycode <= KEY_9 and weapon_manager:
			weapon_manager.set_active_weapon(event.keycode - KEY_1)
		elif (event.keycode == KEY_R or event.is_action_pressed("reload")) and weapon_manager:
			weapon_manager.reload_active()
		# Crouch toggle
		elif event.keycode == KEY_C:
			_toggle_crouch()

	# Jump buffer
	if event.is_action_pressed("jump") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE):
		_jump_buffer_timer = jump_buffer_time

	# Throw bomb
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_G:
		_throw_bomb()

	# Perspective toggle
	if event.is_action_pressed("toggle_perspective") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V):
		toggle_camera_mode()

	# Mouse release
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _throw_bomb() -> void:
	if not bomb_scene or _bombs_remaining <= 0 or _bomb_cooldown_timer > 0.0:
		return
	_bombs_remaining -= 1
	_bomb_cooldown_timer = bomb_cooldown
	bomb_count_changed.emit(_bombs_remaining, bomb_count)
	
	var origin: Vector3 = global_position + Vector3(0, 1.4, 0)
	if bomb_spawn_marker:
		origin = bomb_spawn_marker.global_position
	elif weapon_manager and weapon_manager.has_node("Marker3D"):
		origin = weapon_manager.get_node("Marker3D").global_position
	elif camera_pivot:
		origin = camera_pivot.global_position
		
	var direction: Vector3 = -global_transform.basis.z
	if camera:
		direction = -camera.global_transform.basis.z
	elif camera_pivot:
		direction = -camera_pivot.global_transform.basis.z
		
	var thrower_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			rpc("sync_spawn_bomb", origin, direction, thrower_id)
		else:
			rpc_id(1, "request_throw_bomb", origin, direction, thrower_id)
	else:
		_do_spawn_bomb(origin, direction, thrower_id)

@rpc("any_peer", "call_local", "reliable")
func request_throw_bomb(origin: Vector3, direction: Vector3, thrower_id: int) -> void:
	if not multiplayer.is_server():
		return
	rpc("sync_spawn_bomb", origin, direction, thrower_id)

@rpc("any_peer", "call_local", "reliable")
func sync_spawn_bomb(origin: Vector3, direction: Vector3, thrower_id: int) -> void:
	_do_spawn_bomb(origin, direction, thrower_id)

func _do_spawn_bomb(origin: Vector3, direction: Vector3, thrower_id: int) -> void:
	if not bomb_scene:
		return
	var bomb = bomb_scene.instantiate()
	get_tree().root.add_child(bomb)
	bomb.throw_from(origin, direction, thrower_id)

func get_bombs_remaining() -> int:
	return _bombs_remaining

func _physics_process(delta: float) -> void:
	if _bomb_cooldown_timer > 0.0:
		_bomb_cooldown_timer -= delta
	if not _is_local_authority():
		global_position = global_position.lerp(sync_position, delta * 15.0)
		rotation.y = lerp_angle(rotation.y, sync_rotation_y, delta * 15.0)
		if camera_pivot:
			camera_pivot.rotation.x = lerp_angle(camera_pivot.rotation.x, sync_pitch, delta * 15.0)
		if weapon_manager and sync_weapon_index != weapon_manager.active_weapon_index:
			weapon_manager.set_active_weapon(sync_weapon_index)
		return

	if weapon_manager:
		weapon_manager.process_firing(camera, crosshair)

	var on_floor = is_on_floor()

	# --- Coyote time ---
	if on_floor:
		_coyote_timer = coyote_time
	elif _was_on_floor and _coyote_timer > 0.0:
		_coyote_timer -= delta
	else:
		_coyote_timer = 0.0

	# --- Track fall velocity for landing impact ---
	if not on_floor:
		_fall_velocity = minf(_fall_velocity, velocity.y)

	# --- Landing detection ---
	if on_floor and not _was_on_floor:
		var impact = absf(_fall_velocity)
		if impact > 3.0:
			var strength = clampf((impact - 3.0) / 12.0, 0.0, 1.0) * landing_impact_strength
			_landing_offset = -strength
		_fall_velocity = 0.0

	# --- Gravity ---
	if not on_floor:
		var current_gravity = gravity * (fall_gravity_multiplier if velocity.y < 0.0 else 1.0)
		velocity.y -= current_gravity * delta

	# --- Jump (with buffer + coyote) ---
	_jump_buffer_timer = maxf(0.0, _jump_buffer_timer - delta)
	var can_jump = on_floor or _coyote_timer > 0.0
	if _jump_buffer_timer > 0.0 and can_jump and not _is_crouching:
		velocity.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0

	# --- Movement ---
	var input_dir: Vector2 = _get_movement_vector()
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var is_sprinting: bool = (Input.is_action_pressed("sprint") or Input.is_key_pressed(KEY_SHIFT)) and not _is_crouching
	var target_speed: float
	if _is_crouching:
		target_speed = crouch_speed
	elif is_sprinting:
		target_speed = sprint_speed
	else:
		target_speed = walk_speed

	var accel: float
	var decel: float
	if on_floor:
		accel = ground_accel
		decel = ground_decel
	else:
		accel = air_accel
		decel = air_decel

	if direction:
		velocity.x = lerp(velocity.x, direction.x * target_speed, accel * delta)
		velocity.z = lerp(velocity.z, direction.z * target_speed, accel * delta)
		if crosshair:
			crosshair.add_spread(0.05 if not is_sprinting else 0.12)
	else:
		velocity.x = lerp(velocity.x, 0.0, decel * delta)
		velocity.z = lerp(velocity.z, 0.0, decel * delta)

	move_and_slide()
	_was_on_floor = on_floor

	# --- Animations ---
	_update_animation(direction, is_sprinting, on_floor)

	# --- Camera effects ---
	var h_speed = Vector2(velocity.x, velocity.z).length()
	_update_head_bob(delta, h_speed, is_sprinting, on_floor)
	_update_landing_recovery(delta)
	_update_fov(delta, is_sprinting, on_floor)
	_update_weapon_sway(delta)

	# --- Crouch interpolation ---
	_update_crouch(delta)

	# --- Sync ---
	sync_position = global_position
	sync_rotation_y = rotation.y
	if weapon_manager:
		sync_weapon_index = weapon_manager.active_weapon_index
	if camera_pivot:
		sync_pitch = camera_pivot.rotation.x

	_mouse_delta = Vector2.ZERO

func _get_movement_vector() -> Vector2:
	var dir: Vector2 = Vector2.ZERO
	if Input.is_action_pressed("move_left") or Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_action_pressed("move_right") or Input.is_key_pressed(KEY_D):
		dir.x += 1.0
	if Input.is_action_pressed("move_forward") or Input.is_key_pressed(KEY_W):
		dir.y -= 1.0
	if Input.is_action_pressed("move_back") or Input.is_key_pressed(KEY_S):
		dir.y += 1.0
	return dir.normalized()

# --- Crouch ---

func _toggle_crouch() -> void:
	if _is_crouching:
		# Check headroom before standing
		if _has_headroom():
			_is_crouching = false
	else:
		_is_crouching = true

func _has_headroom() -> bool:
	if not _collision_shape:
		return true
	var space = get_world_3d().direct_space_state
	var params = PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, crouch_height * 0.5, 0),
		global_position + Vector3(0, stand_height, 0)
	)
	params.exclude = [get_rid()]
	return not space.intersect_ray(params)

func _update_crouch(delta: float) -> void:
	if not _capsule_shape or not _collision_shape or not camera_pivot:
		return

	var target_height = crouch_height if _is_crouching else stand_height
	var current_height = _capsule_shape.height

	_capsule_shape.height = lerpf(current_height, target_height, crouch_transition_speed * delta)
	_collision_shape.position.y = _capsule_shape.height * 0.5

	var target_cam_y = (target_height - 0.5) if not _is_crouching else (target_height - 0.3)
	_camera_pivot_base_y = lerpf(_camera_pivot_base_y, target_cam_y, crouch_transition_speed * delta)

	if body_mesh:
		body_mesh.position.y = _capsule_shape.height * 0.5

# --- Head Bob ---

func _update_head_bob(delta: float, speed: float, sprinting: bool, on_floor: bool) -> void:
	if not camera_pivot or not bob_enabled:
		return

	var target_y = _camera_pivot_base_y + _landing_offset

	if on_floor and speed > 0.5:
		var freq = bob_frequency
		var v_amp = bob_v_amplitude
		var h_amp = bob_h_amplitude
		if sprinting:
			freq *= sprint_bob_multiplier
			v_amp *= sprint_bob_multiplier
			h_amp *= sprint_bob_multiplier

		var intensity = clampf(speed / walk_speed, 0.0, 1.5)
		_bob_timer += delta * freq * TAU
		target_y += sin(_bob_timer) * v_amp * intensity
		var bob_x = cos(_bob_timer * 0.5) * h_amp * intensity
		camera_pivot.position.x = lerpf(camera_pivot.position.x, bob_x, 12.0 * delta)
	else:
		_bob_timer = 0.0
		camera_pivot.position.x = lerpf(camera_pivot.position.x, 0.0, 8.0 * delta)

	camera_pivot.position.y = lerpf(camera_pivot.position.y, target_y, 12.0 * delta)

# --- Landing ---

func _update_landing_recovery(delta: float) -> void:
	if _landing_offset < 0.0:
		_landing_offset = lerpf(_landing_offset, 0.0, landing_recovery_speed * delta)
		if absf(_landing_offset) < 0.001:
			_landing_offset = 0.0

# --- FOV ---

func _update_fov(delta: float, sprinting: bool, on_floor: bool) -> void:
	if not camera:
		return
	var target_fov = sprint_fov if (sprinting and on_floor) else base_fov
	camera.fov = lerpf(camera.fov, target_fov, fov_lerp_speed * delta)

# --- Weapon Sway ---

func _update_weapon_sway(delta: float) -> void:
	if not weapon_manager:
		return
	var sway_x = -_mouse_delta.x * weapon_sway_amount
	var sway_y = -_mouse_delta.y * weapon_sway_amount
	sway_x = clampf(sway_x, -0.03, 0.03)
	sway_y = clampf(sway_y, -0.03, 0.03)

	var target = _weapon_holder_base_pos + Vector3(sway_x, sway_y, 0.0)
	weapon_manager.position = weapon_manager.position.lerp(target, weapon_sway_speed * delta)

# --- Recoil / Damage / Death ---

func _on_recoil_requested(pitch_kick: float) -> void:
	if camera_pivot:
		camera_pivot.rotation.x = clamp(
			camera_pivot.rotation.x + pitch_kick,
			deg_to_rad(min_pitch),
			deg_to_rad(max_pitch)
		)

func take_damage(amount: float, attacker_id: int = 0) -> void:
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			health = maxf(0.0, health - amount)
			rpc("sync_health", health)
			if health <= 0.0:
				_on_death(attacker_id)
		else:
			rpc_id(1, "request_take_damage", amount, attacker_id)
	else:
		health = maxf(0.0, health - amount)
		health_changed.emit(health, max_health)
		if health <= 0.0:
			_on_death(attacker_id)

@rpc("any_peer", "call_local", "reliable")
func request_take_damage(amount: float, attacker_id: int = 0) -> void:
	if not multiplayer.is_server():
		return
	take_damage(amount, attacker_id)

@rpc("any_peer", "call_local", "reliable")
func sync_health(new_health: float) -> void:
	health = new_health
	health_changed.emit(health, max_health)

func respawn(spawn_transform: Transform3D) -> void:
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			rpc("sync_respawn", spawn_transform)
		else:
			rpc_id(1, "request_respawn")
	else:
		sync_respawn(spawn_transform)

@rpc("any_peer", "call_local", "reliable")
func request_respawn() -> void:
	if not multiplayer.is_server():
		return
	var spawner = get_tree().root.find_child("PlayerSpawner", true, false)
	if spawner and spawner.has_method("respawn_player"):
		spawner.respawn_player(get_multiplayer_authority())

@rpc("any_peer", "call_local", "reliable")
func sync_respawn(spawn_transform: Transform3D) -> void:
	global_transform = spawn_transform
	velocity = Vector3.ZERO
	sync_position = spawn_transform.origin
	sync_rotation_y = spawn_transform.basis.get_euler().y
	health = max_health
	health_changed.emit(health, max_health)
	_bombs_remaining = bomb_count
	bomb_count_changed.emit(_bombs_remaining, bomb_count)

func _on_death(attacker_id: int = 0) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		var spawner = get_tree().root.find_child("PlayerSpawner", true, false)
		if spawner and spawner.has_method("respawn_player"):
			spawner.respawn_player(get_multiplayer_authority())
	else:
		health = max_health
		health_changed.emit(health, max_health)
		_bombs_remaining = bomb_count
		bomb_count_changed.emit(_bombs_remaining, bomb_count)

# --- Camera Mode ---

func toggle_camera_mode() -> void:
	if current_camera_mode == CameraMode.FPS:
		set_camera_mode(CameraMode.TPS)
	else:
		set_camera_mode(CameraMode.FPS)

func set_camera_mode(mode: CameraMode, instant: bool = false) -> void:
	current_camera_mode = mode
	camera_mode_changed.emit(current_camera_mode)
	if not spring_arm:
		return

	if instant:
		match current_camera_mode:
			CameraMode.FPS:
				spring_arm.spring_length = 0.0
				spring_arm.position = Vector3.ZERO
			CameraMode.TPS:
				spring_arm.spring_length = tps_distance
				spring_arm.position = tps_offset
		return

	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	match current_camera_mode:
		CameraMode.FPS:
			tween.tween_property(spring_arm, "spring_length", 0.0, 0.15)
			tween.tween_property(spring_arm, "position", Vector3.ZERO, 0.15)
		CameraMode.TPS:
			tween.tween_property(spring_arm, "spring_length", tps_distance, 0.15)
			tween.tween_property(spring_arm, "position", tps_offset, 0.15)
