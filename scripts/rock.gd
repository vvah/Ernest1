extends Area2D
## Falling rock. First shows a blinking warning at the top of the screen, then drops
## from just above it. Falls through blocks; touching the player emits player_hit.
## Set `camera` (and optionally `radius`) before adding to the tree.

signal player_hit

const WARN_TIME := 0.9
const GRAVITY := 900.0
const MAX_FALL_SPEED := 650.0
const COLOR := Color(0.5, 0.47, 0.45)

var camera: Camera2D
var radius := 12.0
var _fall_speed := 0.0
var _warn_left := WARN_TIME
var _spin := 0.0
var _angle := 0.0  # tumble; applied to the outline only so the lighting stays fixed
var _outline := PackedVector2Array()


func _ready() -> void:
	monitoring = false

	var shape := CircleShape2D.new()
	shape.radius = radius * 0.85  # slightly forgiving hitbox
	var collision := CollisionShape2D.new()
	collision.shape = shape
	add_child(collision)
	body_entered.connect(_on_body_entered)

	# Lumpy outline so each rock looks a bit different.
	for i in 9:
		_outline.append(Vector2.from_angle(TAU * i / 9.0) * radius * randf_range(0.8, 1.1))
	_spin = randf_range(-4.0, 4.0)


func _physics_process(delta: float) -> void:
	var half_height := get_viewport_rect().size.y / 2.0
	var screen_top := camera.position.y - half_height

	if _warn_left > 0.0:
		_warn_left -= delta
		position.y = screen_top + 28.0
		if _warn_left <= 0.0:
			position.y = screen_top - radius
			set_deferred("monitoring", true)
		queue_redraw()
		return

	_fall_speed = minf(_fall_speed + GRAVITY * delta, MAX_FALL_SPEED)
	position.y += _fall_speed * delta
	_angle += _spin * delta
	queue_redraw()
	if position.y > screen_top + half_height * 2.0 + 100.0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_hit.emit()


func _draw() -> void:
	if _warn_left > 0.0:
		if fmod(_warn_left, 0.3) > 0.12:
			var tri := PackedVector2Array([Vector2(0, -14), Vector2(13, 10), Vector2(-13, 10)])
			draw_colored_polygon(tri, Color(0.9, 0.15, 0.1))
			draw_line(Vector2(0, -6), Vector2(0, 2), Color.WHITE, 3.0)
			draw_circle(Vector2(0, 6), 1.8, Color.WHITE)
		return

	# Shaded body with a lit face towards the top left.
	var shape := PackedVector2Array()
	var lit := PackedVector2Array()
	for p in _outline:
		var q := p.rotated(_angle)
		shape.append(q)
		lit.append(q * 0.72 + Vector2(-radius, -radius) * 0.18)
	draw_colored_polygon(shape, COLOR.darkened(0.2))
	draw_colored_polygon(lit, COLOR)
	draw_circle(Vector2(-radius * 0.35, -radius * 0.35), radius * 0.22, COLOR.lightened(0.25))
	shape.append(shape[0])
	draw_polyline(shape, COLOR.darkened(0.5), 2.0)
