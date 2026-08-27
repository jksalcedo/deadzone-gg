class_name Melee
extends Weapon

@export var attack_range: float = 2.2
@export var swing_duration: float = 0.35

var _is_swinging: bool = false

func _ready() -> void:
	weapon_name = "Fists"
	damage = 40.0
	max_range = attack_range
	spread = 0.0
	recoil_kick = 0.0
	muzzle_flash_scene = null
	bullet_trail_scene = null
	is_automatic = false
	mag_capacity = 0
	max_reserve_ammo = 0
	current_ammo = 1
	reserve_ammo = 0

func can_shoot() -> bool:
	return can_fire and not _is_swinging

func shoot() -> bool:
	if not can_shoot():
		return false
	_is_swinging = true
	can_fire = false
	fired.emit()
	get_tree().create_timer(swing_duration).timeout.connect(_on_swing_finished)
	return true

func _on_swing_finished() -> void:
	_is_swinging = false
	can_fire = true

func reload() -> void:
	pass
