extends Area2D
## Dragon that flies across the screen in a wave. First a blinking arrow warns at the
## screen edge it will come from. When it passes over the player it spits one fireball.
## Stomping it from above knocks it out of the sky; any other contact rams the
## player (damage + knockback), at most once per `RAM_COOLDOWN`.
## Set `camera` before adding to the tree; side, height and colour are optional.

signal stomped(at: Vector2)

const Fireball := preload("res://scripts/fireball.gd")

const WARN_TIME := 1.2
const SPEED := 150.0
const FIREBALL_SPEED := 280.0
const RAM_DAMAGE := 28.0
const RAM_COOLDOWN := 1.0
const SIZE := Vector2(44, 18)  # hitbox (body only, not wings)
const SCALES := Color(0.3, 0.55, 0.25)
const BELLY := Color(0.85, 0.75, 0.4)
const WING := Color(0.55, 0.15, 0.15)

var camera: Camera2D
# Optional setup before adding to the tree (a flight of several dragons sets these):
var dir := 0.0            # 1 = flies right, -1 = left, 0 = random
var screen_y := NAN       # start height relative to the camera centre, NAN = random
var delay := 0.0          # extra warning time before setting off
var scales := SCALES
var _dir := 1.0           # flight direction: 1 = to the right
var _screen_y := 0.0      # height relative to the camera centre when it sets off
var _base_y := 0.0        # world height of the flight path
var _warn_left := WARN_TIME
var _time := 0.0
var _fired := false
var _dead := false
var _fall_speed := 0.0
var _width := 0.0
var _ram_cooldown := 0.0


func _ready() -> void:
	monitoring = false
	_width = get_viewport_rect().size.x
	_dir = dir if dir != 0.0 else (1.0 if randf() < 0.5 else -1.0)
	_warn_left = WARN_TIME + delay
	_screen_y = randf_range(-260.0, 60.0) if is_nan(screen_y) else screen_y
	position.x = -40.0 if _dir > 0.0 else _width + 40.0

	var shape := RectangleShape2D.new()
	shape.size = SIZE
	var collision := CollisionShape2D.new()
	collision.shape = shape
	add_child(collision)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_time += delta

	if _dead:
		_fall_speed += 900.0 * delta
		position.y += _fall_speed * delta
		rotation += _dir * 3.0 * delta
		if position.y > camera.position.y + 600.0:
			queue_free()
		queue_redraw()
		return

	if _warn_left > 0.0:
		# The warning stays on screen; once flying, the dragon keeps its height in the
		# world so it never rides the camera up into a player who is above it.
		_base_y = camera.position.y + _screen_y
		position.y = _base_y
		_warn_left -= delta
		if _warn_left <= 0.0:
			_time = 0.0
			set_deferred("monitoring", true)
		queue_redraw()
		return

	position.y = _base_y + sin(_time * 2.5) * 25.0
	position.x += _dir * SPEED * delta
	_ram_cooldown = maxf(0.0, _ram_cooldown - delta)
	if _ram_cooldown == 0.0 and monitoring:
		for body in get_overlapping_bodies():
			_on_body_entered(body)
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if not _fired and player and absf(player.position.x - position.x) < 60.0 and player.position.y > position.y:
		_spit_fire(player)
	if (_dir > 0.0 and position.x > _width + 60.0) or (_dir < 0.0 and position.x < -60.0):
		queue_free()
	queue_redraw()


func _spit_fire(player: Node2D) -> void:
	_fired = true
	var fireball := Fireball.new()
	fireball.camera = camera
	fireball.position = position + Vector2(_dir * 26.0, 4.0)
	fireball.velocity = (player.position + Vector2(0, -22) - fireball.position).normalized() * FIREBALL_SPEED
	get_parent().add_child(fireball)


func _on_body_entered(body: Node2D) -> void:
	if _dead or not body.is_in_group("player"):
		return
	var player := body as CharacterBody2D
	# Falling with feet above the lower body counts as a stomp. Overlaps are reported
	# a frame late, so the feet have usually sunk a few pixels into the hitbox by now.
	if player.velocity.y > 0.0 and player.global_position.y < global_position.y + SIZE.y * 0.25:
		_dead = true
		player.bounce()
		stomped.emit(global_position)
		set_deferred("monitoring", false)
	elif _ram_cooldown == 0.0:
		_ram_cooldown = RAM_COOLDOWN
		player.take_damage(RAM_DAMAGE, global_position, "Vom Drachen erwischt!")


func _draw() -> void:
	if _warn_left > 0.0:
		_draw_warning()
		return

	# Everything is drawn facing right and mirrored by _dir.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(_dir, 1.0))
	var flap := sin(_time * 9.0)

	# Back wing
	draw_colored_polygon(PackedVector2Array([Vector2(-4, -6), Vector2(6, -6), Vector2(-6, -18 - flap * 14.0)]), WING.darkened(0.3))

	# Tail with a spade tip
	var tail_end := Vector2(-38, -4 + sin(_time * 4.0) * 4.0)
	draw_polyline(PackedVector2Array([Vector2(-18, 0), Vector2(-28, 3), tail_end]), scales.darkened(0.15), 4.0)
	draw_colored_polygon(PackedVector2Array([tail_end + Vector2(2, 0), tail_end + Vector2(-5, -4), tail_end + Vector2(-5, 4)]), WING)

	# Body, belly and legs
	var body := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		body.append(Vector2(cos(a) * 20.0, sin(a) * 8.0))
	draw_colored_polygon(body, scales)
	draw_colored_polygon(PackedVector2Array([Vector2(-14, 4), Vector2(14, 4), Vector2(8, 7.5), Vector2(-8, 7.5)]), BELLY)
	draw_line(Vector2(-8, 6), Vector2(-10, 13), scales.darkened(0.3), 2.5)
	draw_line(Vector2(8, 6), Vector2(7, 13), scales.darkened(0.3), 2.5)

	# Spikes along the back
	for i in 4:
		var x := -12.0 + i * 7.0
		draw_colored_polygon(PackedVector2Array([Vector2(x - 2.5, -7), Vector2(x + 2.5, -7), Vector2(x, -12)]), WING.lightened(0.1))

	# Neck and head with horn, eye and nostril
	draw_line(Vector2(14, -2), Vector2(22, -8), scales, 6.0)
	var head := Vector2(26, -9)
	draw_colored_polygon(PackedVector2Array([head + Vector2(-5, -5), head + Vector2(4, -4), head + Vector2(10, 0), head + Vector2(4, 4), head + Vector2(-5, 4)]), scales)
	draw_line(head + Vector2(-4, -4), head + Vector2(-9, -10), BELLY, 2.0)
	if _dead:
		draw_line(head + Vector2(0, -3), head + Vector2(3, 0), Color.BLACK, 1.0)
		draw_line(head + Vector2(0, 0), head + Vector2(3, -3), Color.BLACK, 1.0)
	else:
		draw_circle(head + Vector2(1.5, -1.5), 1.8, Color(1.0, 0.85, 0.1))
		draw_circle(head + Vector2(2.0, -1.5), 0.8, Color.BLACK)
	draw_circle(head + Vector2(8, 0), 0.8, Color.BLACK)

	# Front wing over the body
	draw_colored_polygon(PackedVector2Array([Vector2(-8, -5), Vector2(8, -5), Vector2(-2, -20 - flap * 12.0), Vector2(-12, -24 - flap * 16.0)]), WING)
	draw_set_transform(Vector2.ZERO)


## Blinking arrow at the edge the dragon enters from, pointing into the screen.
func _draw_warning() -> void:
	if fmod(_warn_left, 0.3) < 0.12:
		return
	var edge_x := 18.0 - position.x if _dir > 0.0 else _width - 18.0 - position.x
	var tip := Vector2(edge_x + _dir * 12.0, 0)
	var back := Vector2(edge_x - _dir * 10.0, 0)
	draw_colored_polygon(PackedVector2Array([tip, back + Vector2(0, -12), back + Vector2(0, 12)]), Color(0.9, 0.15, 0.1))
	draw_line(back + Vector2(-_dir * 8.0, 0), back, Color(0.9, 0.15, 0.1), 5.0)
