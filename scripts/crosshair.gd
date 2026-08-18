class_name Crosshair
extends Control

@export var crosshair_color: Color = Color.WHITE
@export var dot_color: Color = Color.WHITE
@export var line_length: float = 8.0
@export var line_thickness: float = 2.0
@export var base_gap: float = 5.0
@export var draw_center_dot: bool = true
@export var dot_radius: float = 1.5

var current_spread: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _draw() -> void:
	var center: Vector2 = size / 2.0
	var gap: float = base_gap + current_spread

	if draw_center_dot:
		draw_circle(center, dot_radius, dot_color)

	# Top
	draw_line(center - Vector2(0, gap), center - Vector2(0, gap + line_length), crosshair_color, line_thickness)
	# Bottom
	draw_line(center + Vector2(0, gap), center + Vector2(0, gap + line_length), crosshair_color, line_thickness)
	# Left
	draw_line(center - Vector2(gap, 0), center - Vector2(gap + line_length, 0), crosshair_color, line_thickness)
	# Right
	draw_line(center + Vector2(gap, 0), center + Vector2(gap + line_length, 0), crosshair_color, line_thickness)

func _process(delta: float) -> void:
	if current_spread > 0.01:
		current_spread = lerpf(current_spread, 0.0, delta * 12.0)
		queue_redraw()

func add_spread(amount: float) -> void:
	current_spread = clampf(current_spread + amount, 0.0, 30.0)
	queue_redraw()
