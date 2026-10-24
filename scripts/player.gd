extends CharacterBody2D
## The little human. Origin is at the feet; drawn with primitives in _draw().

const SPEED := 220.0
const JUMP_VELOCITY := -560.0
const GRAVITY := 1400.0
const HALF_WIDTH := 9.0

const SKIN := Color(0.96, 0.8, 0.66)
const SHIRT := Color(0.85, 0.25, 0.25)
const PANTS := Color(0.2, 0.3, 0.6)
const HAIR := Color(0.35, 0.22, 0.12)

var _walk_time := 0.0
var _facing := 1.0


func _ready() -> void:
	add_to_group("player")


## Called by enemies when stomped.
func bounce() -> void:
	velocity.y = JUMP_VELOCITY * 0.75


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	# Releasing jump early gives a shorter hop.
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= 0.5

	var dir := Input.get_axis("move_left", "move_right")
	velocity.x = dir * SPEED
	if dir != 0.0:
		_facing = signf(dir)

	move_and_slide()

	var width := get_viewport_rect().size.x
	position.x = clampf(position.x, HALF_WIDTH, width - HALF_WIDTH)

	if is_on_floor() and dir != 0.0:
		_walk_time += delta * 14.0
	else:
		_walk_time = 0.0
	queue_redraw()


func _draw() -> void:
	var swing := sin(_walk_time) * 6.0
	var airborne := not is_on_floor()

	# Legs
	var hip := Vector2(0, -16)
	if airborne:
		draw_line(hip, Vector2(-5, -4), PANTS, 4.0)
		draw_line(hip, Vector2(5, -6), PANTS, 4.0)
	else:
		draw_line(hip, Vector2(-swing, 0), PANTS, 4.0)
		draw_line(hip, Vector2(swing, 0), PANTS, 4.0)

	# Body
	draw_rect(Rect2(-6, -32, 12, 17), SHIRT)

	# Arms
	var shoulder := Vector2(0, -30)
	if airborne:
		draw_line(shoulder, Vector2(-9, -40), SKIN, 3.0)
		draw_line(shoulder, Vector2(9, -40), SKIN, 3.0)
	else:
		draw_line(shoulder, Vector2(swing, -18), SKIN, 3.0)
		draw_line(shoulder, Vector2(-swing, -18), SKIN, 3.0)

	# Head
	draw_circle(Vector2(0, -38), 7.0, SKIN)
	draw_rect(Rect2(-7, -46, 14, 4), HAIR)
	draw_circle(Vector2(_facing * 3.0, -39), 1.4, Color.BLACK)
