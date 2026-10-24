extends CharacterBody2D
## The little human. Origin is at the feet; drawn with primitives in _draw().
## Movement has momentum: it speeds up and slows down instead of snapping.

signal landed(impact_speed: float)

const SPEED := 220.0
const GROUND_ACCEL := 1600.0
const GROUND_FRICTION := 2200.0  # also used when turning around
const AIR_ACCEL := 1000.0
const AIR_DRAG := 150.0          # keeps most of the momentum in the air
const JUMP_VELOCITY := -560.0
const GRAVITY := 1400.0
const MAX_FALL_SPEED := 900.0
const COYOTE_TIME := 0.08        # can still jump shortly after leaving an edge
const JUMP_BUFFER := 0.1         # jump pressed shortly before landing still counts
const STUN_IMPACT := 800.0       # landing faster than this (a drop of ~2 blocks) knocks the wind out
const STUN_TIME := 0.4
const HALF_WIDTH := 9.0

const SKIN := Color(0.93, 0.76, 0.62)
const SHIRT := Color(0.72, 0.22, 0.2)
const PANTS := Color(0.22, 0.28, 0.45)
const HAIR := Color(0.3, 0.19, 0.1)
const SHOE := Color(0.18, 0.14, 0.12)

var _walk_time := 0.0
var _time := 0.0
var _facing := 1.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _squash := 0.0  # > 0 squashed (landing), < 0 stretched (jump)
var _stun := 0.0  # seconds left without control after a hard landing
var _dead := false


func _ready() -> void:
	add_to_group("player")


## Called by enemies when stomped.
func bounce() -> void:
	velocity.y = JUMP_VELOCITY * 0.75
	_coyote = 0.0
	_squash = -0.12


## Knocked out: tumbles off the screen, ignoring blocks.
func die() -> void:
	_dead = true
	collision_layer = 0
	collision_mask = 0
	velocity = Vector2(-_facing * 110.0, -380.0)


func _physics_process(delta: float) -> void:
	_time += delta
	_squash = move_toward(_squash, 0.0, delta * 1.2)

	if _dead:
		velocity.y += GRAVITY * delta
		position += velocity * delta
		rotation -= _facing * 7.0 * delta
		queue_redraw()
		return

	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)

	_stun = maxf(0.0, _stun - delta)
	_coyote = COYOTE_TIME if is_on_floor() else _coyote - delta
	_jump_buffer = JUMP_BUFFER if Input.is_action_just_pressed("jump") else _jump_buffer - delta
	if _jump_buffer > 0.0 and _coyote > 0.0 and _stun == 0.0:
		velocity.y = JUMP_VELOCITY
		_jump_buffer = 0.0
		_coyote = 0.0
		_squash = -0.15
	# Releasing jump early gives a shorter hop.
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= 0.5

	var dir := 0.0 if _stun > 0.0 else Input.get_axis("move_left", "move_right")
	var accel: float
	if is_on_floor():
		var braking := dir == 0.0 or signf(dir) != signf(velocity.x)
		accel = GROUND_FRICTION if braking else GROUND_ACCEL
	else:
		accel = AIR_DRAG if dir == 0.0 else AIR_ACCEL
	velocity.x = move_toward(velocity.x, dir * SPEED, accel * delta)
	if dir != 0.0:
		_facing = signf(dir)

	var was_on_floor := is_on_floor()
	var fall_speed := velocity.y
	move_and_slide()
	if is_on_floor() and not was_on_floor:
		_squash = clampf(fall_speed / 3000.0, 0.05, 0.3)
		if fall_speed > STUN_IMPACT:
			_stun = STUN_TIME
		landed.emit(fall_speed)

	var width := get_viewport_rect().size.x
	if position.x < HALF_WIDTH or position.x > width - HALF_WIDTH:
		position.x = clampf(position.x, HALF_WIDTH, width - HALF_WIDTH)
		velocity.x = 0.0

	if is_on_floor() and absf(velocity.x) > 5.0:
		_walk_time += delta * 14.0 * absf(velocity.x) / SPEED
	else:
		_walk_time = 0.0
	queue_redraw()


## Two-segment limb from `root`; angles are relative to straight down and
## positive angles point in the facing direction. Returns the end point.
func _limb(root: Vector2, angle: float, bend: float, length: float, color: Color, width: float) -> Vector2:
	var joint := root + Vector2(sin(angle) * _facing, cos(angle)) * length
	var end := joint + Vector2(sin(angle + bend) * _facing, cos(angle + bend)) * length
	draw_polyline(PackedVector2Array([root, joint, end]), color, width)
	draw_circle(joint, width / 2.0, color)
	return end


func _draw() -> void:
	# Lean into the run and squash/stretch around the feet.
	var lean := velocity.x / SPEED * 0.12 if not _dead else 0.0
	draw_set_transform(Vector2.ZERO, lean, Vector2(1.0 + _squash, 1.0 - _squash))

	var airborne := not is_on_floor() or _dead
	var running := _walk_time > 0.0
	var breathe := 0.0 if running or airborne else sin(_time * 2.5) * 0.4
	if _stun > 0.0:
		breathe = 6.0 + sin(_time * 14.0) * 0.8  # torso dropped and heaving
	var hip := Vector2(0, -16 + (6.0 if _stun > 0.0 else 0.0))
	var shoulder := Vector2(0, -29 + breathe)
	var back_skin := SKIN.darkened(0.18)
	var back_pants := PANTS.darkened(0.25)

	# Leg/arm poses: [thigh angle, knee bend] per leg, [upper arm, elbow] per arm.
	var legs: Array
	var arms: Array
	if airborne:
		var rising := velocity.y < 0.0
		legs = [Vector2(0.9, -1.4), Vector2(-0.2, -0.5)] if rising else [Vector2(0.4, -0.6), Vector2(-0.1, -0.2)]
		arms = [Vector2(2.6, 0.3), Vector2(-0.6, 0.5)] if rising else [Vector2(1.8, 0.3), Vector2(-1.4, 0.3)]
	elif _stun > 0.0:
		# Crouched, hands on knees, catching breath.
		legs = [Vector2(1.1, -1.9), Vector2(0.9, -1.7)]
		arms = [Vector2(0.9, -0.3), Vector2(0.7, -0.2)]
	elif running:
		var s := sin(_walk_time)
		var c := cos(_walk_time)
		legs = [Vector2(s * 0.7, -maxf(0.0, c) * 1.2), Vector2(-s * 0.7, -maxf(0.0, -c) * 1.2)]
		arms = [Vector2(-s * 0.8, 1.0), Vector2(s * 0.8, 1.0)]
	else:
		legs = [Vector2(0.08, -0.05), Vector2(-0.08, 0.0)]
		arms = [Vector2(0.15, 0.2), Vector2(-0.1, 0.15)]

	# Back limbs first (darker, behind the body).
	_limb(shoulder + Vector2(-_facing, 0), arms[1].x, arms[1].y, 6.5, back_skin, 3.0)
	var back_foot := _limb(hip, legs[1].x, legs[1].y, 8.0, back_pants, 4.0)
	draw_line(back_foot, back_foot + Vector2(_facing * 3.5, 0), SHOE.darkened(0.2), 3.0)
	var front_foot := _limb(hip, legs[0].x, legs[0].y, 8.0, PANTS, 4.0)
	draw_line(front_foot, front_foot + Vector2(_facing * 3.5, 0), SHOE, 3.0)

	# Torso with a shaded back side and a belt.
	draw_rect(Rect2(-6, shoulder.y - 2, 12, hip.y - shoulder.y + 3), SHIRT)
	var back_x := -6.0 if _facing > 0.0 else 3.0
	draw_rect(Rect2(back_x, shoulder.y - 2, 3, hip.y - shoulder.y + 3), SHIRT.darkened(0.2))
	draw_rect(Rect2(-6, hip.y - 3, 12, 3), PANTS.darkened(0.35))

	# Head: hair behind, face turned towards the facing direction.
	var head := Vector2(_facing * 0.5, shoulder.y - 9)
	draw_rect(Rect2(-2, shoulder.y - 4, 4, 3), SKIN.darkened(0.1))  # neck
	draw_circle(head + Vector2(-_facing * 1.0, -1.5), 7.2, HAIR)
	draw_circle(head + Vector2(_facing * 0.8, 0.5), 6.4, SKIN)
	draw_rect(Rect2(head.x - 6.5, head.y - 7.5, 13, 3.5), HAIR)
	draw_circle(head + Vector2(-_facing * 1.5, 0.5), 1.6, SKIN.darkened(0.12))  # ear
	if _dead:
		var e := head + Vector2(_facing * 3.5, -0.5)
		draw_line(e + Vector2(-1.3, -1.3), e + Vector2(1.3, 1.3), Color.BLACK, 1.0)
		draw_line(e + Vector2(-1.3, 1.3), e + Vector2(1.3, -1.3), Color.BLACK, 1.0)
	else:
		draw_circle(head + Vector2(_facing * 3.5, -0.5), 1.2, Color(0.15, 0.1, 0.08))
	draw_circle(head + Vector2(_facing * 6.6, 1.2), 1.3, SKIN.darkened(0.08))  # nose

	# Front arm over the body.
	_limb(shoulder + Vector2(_facing, 0), arms[0].x, arms[0].y, 6.5, SKIN, 3.0)
	draw_set_transform(Vector2.ZERO)
