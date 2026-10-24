extends Area2D
## Beetle that patrols back and forth on top of its block. Origin is at its feet.
## Stomping it from above defeats it; touching it any other way emits player_hit.

signal player_hit
signal stomped(at: Vector2)

const SIZE := Vector2(22, 16)
const BODY := Color(0.32, 0.2, 0.12)
const LEG := Color(0.12, 0.08, 0.05)

var patrol_half_width := 30.0
var speed := 50.0
var _dir := 1.0
var _home_x := 0.0
var _time := 0.0
var _dead := false


func _ready() -> void:
	_home_x = position.x
	_dir = 1.0 if randf() < 0.5 else -1.0

	var shape := RectangleShape2D.new()
	shape.size = SIZE
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(0, -SIZE.y / 2.0)
	add_child(collision)

	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_time += delta
	position.x += _dir * speed * delta
	if absf(position.x - _home_x) > patrol_half_width:
		position.x = _home_x + signf(position.x - _home_x) * patrol_half_width
		_dir = -_dir
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if _dead or not body.is_in_group("player"):
		return
	# Falling onto the top half counts as a stomp.
	var player := body as CharacterBody2D
	if player.velocity.y > 0.0 and player.global_position.y < global_position.y - SIZE.y * 0.4:
		_dead = true
		player.bounce()
		stomped.emit(global_position)
		set_deferred("monitoring", false)
		var tween := create_tween()
		tween.tween_property(self, "scale", Vector2(1.5, 0.15), 0.15)
		tween.tween_callback(queue_free)
	else:
		player_hit.emit()


func _ellipse(center: Vector2, radii: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		points.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return points


func _draw() -> void:
	# Three scuttling legs, alternating like a real insect's tripod gait.
	for i in 3:
		var hip := Vector2((i - 1) * 6.0, -5.0)
		var step := sin(_time * 22.0 + i * PI) * 2.5
		var knee := hip + Vector2(step - 1.5, -2.0)
		draw_polyline(PackedVector2Array([hip, knee, Vector2(hip.x + step * 1.4, 0)]), LEG, 1.3)

	# Head, mandibles and antennae on the side it walks towards.
	var head := Vector2(_dir * 10.0, -6.0)
	draw_line(head, head + Vector2(_dir * 4.5, 2.0), LEG, 1.3)
	var twitch := sin(_time * 7.0) * 1.5
	draw_polyline(PackedVector2Array([head, head + Vector2(_dir * 4.0, -5.0), head + Vector2(_dir * 9.0, -6.0 + twitch)]), LEG, 1.0)
	draw_circle(head, 4.0, BODY.darkened(0.35))
	draw_circle(head + Vector2(_dir * 2.0, -1.0), 1.0, Color(0.9, 0.85, 0.6))

	# Glossy shell split down the middle.
	var shell := Vector2(-_dir * 1.0, -SIZE.y / 2.0 - 1.0)
	draw_colored_polygon(_ellipse(shell, Vector2(SIZE.x / 2.0, SIZE.y / 2.0)), BODY)
	draw_colored_polygon(_ellipse(shell + Vector2(-2.0, -3.0), Vector2(5.0, 2.0)), BODY.lightened(0.35))
	draw_line(shell + Vector2(_dir * SIZE.x / 2.0, 0), shell + Vector2(-_dir * 6.0, 0), BODY.darkened(0.5), 1.0)
	var closed := _ellipse(shell, Vector2(SIZE.x / 2.0, SIZE.y / 2.0))
	closed.append(closed[0])
	draw_polyline(closed, BODY.darkened(0.55), 1.0)
