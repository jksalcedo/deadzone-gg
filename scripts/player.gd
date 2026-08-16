class_name Player
extends CharacterBody3D

enum CameraMode {
	FPS,
	TPS
}

@export_group("Movement")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 4.5
@export var acceleration: float = 12.0
@export var deceleration: float = 10.0

@export_group("Camera")
@export var mouse_sensitivity: float = 0.0025
@export var default_camera_mode: CameraMode = CameraMode.FPS
@export var tps_distance: float = 3.0
@export var tps_offset: Vector3 = Vector3(0.4, 0.2, 0.0)
@export var min_pitch: float = -89.0
@export var max_pitch: float = 89.0

@export_group("Node References")
@export var camera_pivot: Node3D
@export var spring_arm: SpringArm3D
@export var camera: Camera3D
@export var body_mesh: MeshInstance3D
@export var eyes_node: Node3D

var current_camera_mode: CameraMode = CameraMode.FPS
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

# Multiplayer sync variables
@export var sync_position: Vector3 = Vector3.ZERO
@export var sync_rotation_y: float = 0.0
@export var sync_pitch: float = 0.0

func _ready() -> void:
	if not camera_pivot:
		camera_pivot = get_node_or_null("CameraPivot")
	if not spring_arm and camera_pivot:
		spring_arm = camera_pivot.get_node_or_null("SpringArm3D")
	if not camera:
		if spring_arm:
			camera = spring_arm.get_node_or_null("Camera3D")
		elif camera_pivot:
			camera = camera_pivot.get_node_or_null("Camera3D")

	if spring_arm:
		spring_arm.add_excluded_object(get_rid())

	if not _is_local_authority():
		if camera:
			camera.current = false
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

	if event.is_action_pressed("toggle_perspective") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V):
		toggle_camera_mode()

	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if not _is_local_authority():
		# Client interpolation for remote players
		global_position = global_position.lerp(sync_position, delta * 15.0)
		rotation.y = lerp_angle(rotation.y, sync_rotation_y, delta * 15.0)
		if camera_pivot:
			camera_pivot.rotation.x = lerp_angle(camera_pivot.rotation.x, sync_pitch, delta * 15.0)
		return

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
	else:
		velocity.x = lerp(velocity.x, 0.0, deceleration * delta)
		velocity.z = lerp(velocity.z, 0.0, deceleration * delta)

	move_and_slide()

	# Update sync properties for MultiplayerSynchronizer
	sync_position = global_position
	sync_rotation_y = rotation.y
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

func toggle_camera_mode() -> void:
	if current_camera_mode == CameraMode.FPS:
		set_camera_mode(CameraMode.TPS)
	else:
		set_camera_mode(CameraMode.FPS)

func set_camera_mode(mode: CameraMode) -> void:
	current_camera_mode = mode
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
