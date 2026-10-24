extends Area2D
## Slime that patrols back and forth on top of its block. Origin is at its feet.
## Stomping it from above defeats it; touching it any other way emits player_hit.

signal player_hit

const SIZE := Vector2(22, 16)
const BODY := Color(0.55, 0.2, 0.7)

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
		set_deferred("monitoring", false)
		var tween := create_tween()
		tween.tween_property(self, "scale", Vector2(1.5, 0.15), 0.15)
		tween.tween_callback(queue_free)
	else:
		player_hit.emit()


func _draw() -> void:
	var wobble := sin(_time * 10.0) * 1.5
	var r := SIZE.x / 2.0
	draw_circle(Vector2(0, -SIZE.y + r - wobble * 0.5), r, BODY)
	draw_rect(Rect2(-r, -SIZE.y + r, SIZE.x, SIZE.y - r), BODY)

	for side in [-1.0, 1.0]:
		var eye := Vector2(side * 4.0 + _dir * 2.0, -SIZE.y + 7.0)
		draw_circle(eye, 3.0, Color.WHITE)
		draw_circle(eye + Vector2(_dir * 1.2, 0), 1.4, Color.BLACK)
