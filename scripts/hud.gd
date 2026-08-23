class_name HUD
extends CanvasLayer

@export_group("Node References")
@export var health_bar: ProgressBar
@export var health_delay_bar: ProgressBar
@export var health_label: Label
@export var damage_vignette: TextureRect
@export var hitmarker: Control
@export var crosshair: Crosshair
@export var weapon_name_label: Label
@export var current_ammo_label: Label
@export var reserve_ammo_label: Label
@export var reload_container: Control
@export var reload_progress_bar: ProgressBar
@export var low_ammo_label: Label
@export var bomb_count_label: Label

var _player: Player
var _weapon_manager: WeaponManager
var _health_tween: Tween
var _damage_lag_tween: Tween
var _reload_tween: Tween
var _vignette_tween: Tween
var _hitmarker_tween: Tween
var _pulse_tween: Tween

var _is_low_health: bool = false
var _hitmarker_alpha: float = 0.0

func _ready() -> void:
	if hitmarker:
		hitmarker.draw.connect(_on_hitmarker_draw)
	if reload_container:
		reload_container.visible = false
	if low_ammo_label:
		low_ammo_label.visible = false
	if damage_vignette:
		damage_vignette.modulate.a = 0.0

func initialize(player: Player, weapon_mgr: WeaponManager) -> void:
	_player = player
	_weapon_manager = weapon_mgr

	if _player:
		if not _player.health_changed.is_connected(_on_health_changed):
			_player.health_changed.connect(_on_health_changed)
		if _player.has_signal("bomb_count_changed"):
			if not _player.bomb_count_changed.is_connected(_on_bomb_count_changed):
				_player.bomb_count_changed.connect(_on_bomb_count_changed)
		_on_health_changed(_player.health, _player.max_health)
		if _player.has_method("get_bombs_remaining"):
			_on_bomb_count_changed(_player.get_bombs_remaining(), _player.bomb_count)

	if _weapon_manager:
		if not _weapon_manager.weapon_switched.is_connected(_on_weapon_switched):
			_weapon_manager.weapon_switched.connect(_on_weapon_switched)
		if not _weapon_manager.ammo_changed.is_connected(_on_ammo_changed):
			_weapon_manager.ammo_changed.connect(_on_ammo_changed)
		if not _weapon_manager.weapon_reload_started.is_connected(_on_weapon_reload_started):
			_weapon_manager.weapon_reload_started.connect(_on_weapon_reload_started)
		if not _weapon_manager.weapon_reload_finished.is_connected(_on_weapon_reload_finished):
			_weapon_manager.weapon_reload_finished.connect(_on_weapon_reload_finished)
		if not _weapon_manager.weapon_reload_canceled.is_connected(_on_weapon_reload_canceled):
			_weapon_manager.weapon_reload_canceled.connect(_on_weapon_reload_canceled)
		if not _weapon_manager.hit_target.is_connected(_on_hit_target):
			_weapon_manager.hit_target.connect(_on_hit_target)
		var active_w = _weapon_manager.get_active_weapon()
		if active_w:
			_on_weapon_switched(active_w)

func _on_health_changed(current: float, max_val: float) -> void:
	var prev_val = health_bar.value if health_bar else current

	if health_bar:
		health_bar.max_value = max_val
		if _health_tween:
			_health_tween.kill()
		if current >= max_val:
			health_bar.value = current
		else:
			_health_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			_health_tween.tween_property(health_bar, "value", current, 0.1)

	if health_delay_bar:
		health_delay_bar.max_value = max_val
		if current < prev_val:
			if _damage_lag_tween:
				_damage_lag_tween.kill()
			_damage_lag_tween = create_tween()
			_damage_lag_tween.tween_interval(0.3)
			_damage_lag_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_damage_lag_tween.tween_property(health_delay_bar, "value", current, 0.5)
			_trigger_damage_flash()
		else:
			if _damage_lag_tween:
				_damage_lag_tween.kill()
			health_delay_bar.value = current

	if health_label:
		health_label.text = "%d" % [roundi(current)]

	var ratio = current / maxf(1.0, max_val)
	_update_health_colors(ratio)

	if ratio >= 1.0:
		reset_effects()
	elif ratio <= 0.25 and current > 0.0:
		if not _is_low_health:
			_is_low_health = true
			_start_low_health_pulse()
	else:
		_is_low_health = false
		if _pulse_tween:
			_pulse_tween.kill()
			_pulse_tween = null
		if _vignette_tween:
			_vignette_tween.kill()
			_vignette_tween = null
		if damage_vignette:
			damage_vignette.modulate.a = 0.0

func reset_effects() -> void:
	_is_low_health = false
	if _vignette_tween:
		_vignette_tween.kill()
		_vignette_tween = null
	if _pulse_tween:
		_pulse_tween.kill()
		_pulse_tween = null
	if _damage_lag_tween:
		_damage_lag_tween.kill()
		_damage_lag_tween = null
	if _hitmarker_tween:
		_hitmarker_tween.kill()
		_hitmarker_tween = null
	_hitmarker_alpha = 0.0
	if damage_vignette:
		damage_vignette.modulate.a = 0.0
	if hitmarker:
		hitmarker.queue_redraw()

func _update_health_colors(ratio: float) -> void:
	if not health_bar:
		return
	var fill_style: StyleBoxFlat = health_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if not fill_style:
		return
	if ratio > 0.5:
		fill_style.bg_color = Color(0.95, 0.95, 0.95, 0.9)
	elif ratio > 0.25:
		fill_style.bg_color = Color(0.9, 0.7, 0.2, 0.9)
	else:
		fill_style.bg_color = Color(0.85, 0.2, 0.15, 0.9)

func _trigger_damage_flash() -> void:
	if not damage_vignette:
		return
	if _vignette_tween:
		_vignette_tween.kill()
	damage_vignette.modulate.a = 0.6
	_vignette_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var end_alpha = 0.2 if _is_low_health else 0.0
	_vignette_tween.tween_property(damage_vignette, "modulate:a", end_alpha, 0.4)

func _start_low_health_pulse() -> void:
	if _pulse_tween:
		_pulse_tween.kill()
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if damage_vignette:
		_pulse_tween.tween_property(damage_vignette, "modulate:a", 0.3, 0.6)
		_pulse_tween.tween_property(damage_vignette, "modulate:a", 0.08, 0.6)

func _on_weapon_switched(weapon: Weapon) -> void:
	if not weapon:
		return
	if weapon_name_label:
		weapon_name_label.text = weapon.weapon_name

	if reload_container:
		reload_container.visible = false
	if _reload_tween:
		_reload_tween.kill()

	_on_ammo_changed(weapon.current_ammo, weapon.reserve_ammo)

func _on_ammo_changed(current: int, reserve: int) -> void:
	if current_ammo_label:
		current_ammo_label.text = str(current)
	if reserve_ammo_label:
		reserve_ammo_label.text = str(reserve)

	var active_w = _weapon_manager.get_active_weapon() if _weapon_manager else null
	var max_mag = active_w.mag_capacity if active_w else 30

	if low_ammo_label:
		if current == 0 and reserve > 0:
			low_ammo_label.text = "RELOAD"
			low_ammo_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.25, 0.9))
			low_ammo_label.visible = true
		elif current == 0 and reserve == 0:
			low_ammo_label.text = "NO AMMO"
			low_ammo_label.add_theme_color_override("font_color", Color(0.7, 0.15, 0.1, 0.85))
			low_ammo_label.visible = true
		elif current <= maxi(1, int(max_mag * 0.2)):
			low_ammo_label.text = "LOW"
			low_ammo_label.add_theme_color_override("font_color", Color(0.85, 0.6, 0.15, 0.8))
			low_ammo_label.visible = true
		else:
			low_ammo_label.visible = false

func _on_weapon_reload_started(_weapon: Weapon, duration: float) -> void:
	if not reload_container:
		return
	reload_container.visible = true
	if reload_progress_bar:
		reload_progress_bar.max_value = 1.0
		reload_progress_bar.value = 0.0
		if _reload_tween:
			_reload_tween.kill()
		_reload_tween = create_tween().set_trans(Tween.TRANS_LINEAR)
		_reload_tween.tween_property(reload_progress_bar, "value", 1.0, duration)

func _on_weapon_reload_finished(_weapon: Weapon) -> void:
	if reload_container:
		reload_container.visible = false
	if _reload_tween:
		_reload_tween.kill()

func _on_weapon_reload_canceled(_weapon: Weapon) -> void:
	if reload_container:
		reload_container.visible = false
	if _reload_tween:
		_reload_tween.kill()

func _on_hit_target(_collider: Object, _damage: float) -> void:
	if not hitmarker:
		return
	_hitmarker_alpha = 1.0
	hitmarker.queue_redraw()

	if _hitmarker_tween:
		_hitmarker_tween.kill()
	_hitmarker_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hitmarker_tween.tween_method(_set_hitmarker_alpha, 1.0, 0.0, 0.15)

func _set_hitmarker_alpha(val: float) -> void:
	_hitmarker_alpha = val
	if hitmarker:
		hitmarker.queue_redraw()

func _on_hitmarker_draw() -> void:
	if not hitmarker or _hitmarker_alpha <= 0.001:
		return
	var center = hitmarker.size / 2.0
	var hit_color = Color(1.0, 1.0, 1.0, _hitmarker_alpha)
	var len = 6.0
	var gap = 5.0
	var thick = 1.5
	hitmarker.draw_line(center + Vector2(-gap, -gap), center + Vector2(-gap - len, -gap - len), hit_color, thick)
	hitmarker.draw_line(center + Vector2(gap, -gap), center + Vector2(gap + len, -gap - len), hit_color, thick)
	hitmarker.draw_line(center + Vector2(-gap, gap), center + Vector2(-gap - len, gap + len), hit_color, thick)
	hitmarker.draw_line(center + Vector2(gap, gap), center + Vector2(gap + len, gap + len), hit_color, thick)

func _on_bomb_count_changed(current: int, _max_count: int) -> void:
	if bomb_count_label:
		bomb_count_label.text = str(current)
		if current <= 0:
			bomb_count_label.modulate = Color(0.4, 0.4, 0.4, 0.5)
		else:
			bomb_count_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
