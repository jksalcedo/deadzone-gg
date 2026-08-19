class_name Player
extends CharacterBody3D

signal health_changed(current: float, max: float)
signal camera_mode_changed(mode: CameraMode)

enum CameraMode {
	FPS,
	TPS
}

@export_group("Movement")
@export var walk_speed: float = 10.0
@export var sprint_speed: float = 15.0
@export var jump_velocity: float = 10.0
@export var acceleration: float = 12.0
@export var deceleration: float = 10.0

@export_group("Camera")
@export var mouse_sensitivity: float = 0.0025
@export var default_camera_mode: CameraMode = CameraMode.TPS
@export var tps_distance: float = 3.5
@export var tps_offset: Vector3 = Vector3(0.5, 0.5, 0.0)
@export var min_pitch: float = -89.0
@export var max_pitch: float = 89.0

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
@export var crosshair: Crosshair

var current_camera_mode: CameraMode = CameraMode.TPS
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

# Multiplayer sync variables
@export var sync_position: Vector3 = Vector3.ZERO
@export var sync_rotation_y: float = 0.0
@export var sync_pitch: float = 0.0
@export var sync_weapon_index: int = 0

func _ready() -> void:
	health = max_health

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

	if not hud:
		hud = get_node_or_null("HUD")
	if not crosshair and hud:
		crosshair = hud.get_node_or_null("Crosshair")

	if weapon_manager:
		weapon_manager.recoil_requested.connect(_on_recoil_requested)

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
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	set_camera_mode(default_camera_mode)

func _is_local_authority() -> bool:
	return not multiplayer.has_multiplayer_peer() or is_multiplayer_authority()

func _unhandled_input(event: InputEvent) -> void:
	if not _is_local_authority():
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		if camera_pivot:
			camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
			camera_pivot.rotation.x = clamp(
				camera_pivot.rotation.x,
				deg_to_rad(min_pitch),
				deg_to_rad(max_pitch)
			)

	# Firing & Weapon cycling input
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

	# Weapon selection numbers & Reload
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_9 and weapon_manager:
			weapon_manager.set_active_weapon(event.keycode - KEY_1)
		elif (event.keycode == KEY_R or event.is_action_pressed("reload")) and weapon_manager:
			weapon_manager.reload_active()

	# Perspective toggle
	if event.is_action_pressed("toggle_perspective") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V):
		toggle_camera_mode()

	# Mouse release
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if not _is_local_authority():
		# Client interpolation for remote players
		global_position = global_position.lerp(sync_position, delta * 15.0)
		rotation.y = lerp_angle(rotation.y, sync_rotation_y, delta * 15.0)
		if camera_pivot:
			camera_pivot.rotation.x = lerp_angle(camera_pivot.rotation.x, sync_pitch, delta * 15.0)
		if weapon_manager and sync_weapon_index != weapon_manager.active_weapon_index:
			weapon_manager.set_active_weapon(sync_weapon_index)
		return

	# Continuous automatic firing
	if weapon_manager:
		weapon_manager.process_firing(camera, crosshair)

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta + 0.2

	# Jump
	var is_jumping: bool = Input.is_action_just_pressed("jump") or Input.is_key_pressed(KEY_SPACE)
	if is_jumping and is_on_floor():
		velocity.y = jump_velocity

	# Movement direction
	var input_dir: Vector2 = _get_movement_vector()
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var is_sprinting: bool = Input.is_action_pressed("sprint") or Input.is_key_pressed(KEY_SHIFT)
	var target_speed: float = sprint_speed if is_sprinting else walk_speed

	if direction:
		velocity.x = lerp(velocity.x, direction.x * target_speed, acceleration * delta)
		velocity.z = lerp(velocity.z, direction.z * target_speed, acceleration * delta)
		if crosshair:
			crosshair.add_spread(0.1)
	else:
		velocity.x = lerp(velocity.x, 0.0, deceleration * delta)
		velocity.z = lerp(velocity.z, 0.0, deceleration * delta)

	move_and_slide()

	# Update sync properties for MultiplayerSynchronizer
	sync_position = global_position
	sync_rotation_y = rotation.y
	if weapon_manager:
		sync_weapon_index = weapon_manager.active_weapon_index
	if camera_pivot:
		sync_pitch = camera_pivot.rotation.x

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

func _on_recoil_requested(pitch_kick: float) -> void:
	if camera_pivot:
		camera_pivot.rotation.x = clamp(
			camera_pivot.rotation.x + pitch_kick,
			deg_to_rad(min_pitch),
			deg_to_rad(max_pitch)
		)

func take_damage(amount: float, attacker_id: int = 0) -> void:
	health = maxf(0.0, health - amount)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_on_death(attacker_id)

func _on_death(attacker_id: int = 0) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		var spawner = get_tree().root.find_child("PlayerSpawner", true, false)
		if spawner and spawner.has_method("respawn_player"):
			spawner.respawn_player(get_multiplayer_authority())
	else:
		health = max_health
		health_changed.emit(health, max_health)

func toggle_camera_mode() -> void:
	if current_camera_mode == CameraMode.FPS:
		set_camera_mode(CameraMode.TPS)
	else:
		set_camera_mode(CameraMode.FPS)

func set_camera_mode(mode: CameraMode) -> void:
	current_camera_mode = mode
	camera_mode_changed.emit(current_camera_mode)
	if not spring_arm:
		return

	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	match current_camera_mode:
		CameraMode.FPS:
			tween.tween_property(spring_arm, "spring_length", 0.0, 0.15)
			tween.tween_property(spring_arm, "position", Vector3.ZERO, 0.15)
		CameraMode.TPS:
			tween.tween_property(spring_arm, "spring_length", tps_distance, 0.15)
			tween.tween_property(spring_arm, "position", tps_offset, 0.15)
