class_name Weapon
extends Node3D

signal fired
signal reloaded
signal ammo_changed(current: int, reserve: int)

@export_group("Weapon Stats")
@export var weapon_name: String = "Rifle"
@export var damage: float = 25.0
@export var fire_rate: float = 0.1
@export var is_automatic: bool = true
@export var mag_capacity: int = 30
@export var max_reserve_ammo: int = 120
@export var reload_time: float = 2.0
@export var max_range: float = 200.0
@export var spread: float = 0.01
@export var recoil_kick: float = 0.015

@export_group("Nodes")
@export var muzzle_point: Node3D

var current_ammo: int = 30
var reserve_ammo: int = 120
var can_fire: bool = true
var is_reloading: bool = false
var _reload_timer: SceneTreeTimer

func _ready() -> void:
	current_ammo = mag_capacity
	reserve_ammo = max_reserve_ammo
	if not muzzle_point:
		muzzle_point = get_node_or_null("Muzzle")

func can_shoot() -> bool:
	return can_fire and not is_reloading and current_ammo > 0

func shoot() -> bool:
	if not can_shoot():
		if current_ammo == 0 and not is_reloading:
			reload()
		return false

	current_ammo -= 1
	can_fire = false
	ammo_changed.emit(current_ammo, reserve_ammo)
	fired.emit()

	get_tree().create_timer(fire_rate).timeout.connect(func(): can_fire = true)
	return true

func reload() -> void:
	if is_reloading or current_ammo == mag_capacity or reserve_ammo <= 0:
		return

	is_reloading = true
	_reload_timer = get_tree().create_timer(reload_time)
	_reload_timer.timeout.connect(_on_reload_complete)

func _on_reload_complete() -> void:
	if not is_reloading:
		return

	var needed: int = mag_capacity - current_ammo
	var to_load: int = mini(needed, reserve_ammo)
	current_ammo += to_load
	reserve_ammo -= to_load
	is_reloading = false
	ammo_changed.emit(current_ammo, reserve_ammo)
	reloaded.emit()

func cancel_reload() -> void:
	is_reloading = false
