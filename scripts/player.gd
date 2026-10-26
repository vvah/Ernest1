extends CharacterBody2D
## The little human. Origin is at the feet; drawn with primitives in _draw().
## Movement has momentum: it speeds up and slows down instead of snapping.
## Has health: hits knock the player back, leave visible injuries and, when
## health is low, make them limp. main.gd reacts to `hurt` and `died`.

signal landed(impact_speed: float)
signal hurt(amount: float, from: Vector2)
signal healed(amount: float)
signal died(cause: String)

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
const STUN_IMPACT := 800.0       # landing faster than this (a drop of ~2 blocks) hurts
const STUN_TIME := 0.4
const FALL_DAMAGE := 0.25        # health lost per px/s of impact above STUN_IMPACT
const HALF_WIDTH := 9.0

const MAX_HEALTH := 100.0
const HURT_TIME := 0.35          # flinch pose and red flash
const INVULNERABLE_TIME := 1.0   # no further damage right after a hit (flickers)
const KNOCKBACK := Vector2(230.0, -280.0)
const LIMP_HEALTH := 35.0        # below this the player limps and slows down
const LIMP_SPEED := 0.7

const SKIN := Color(0.93, 0.76, 0.62)
const PALE_SKIN := Color(0.84, 0.8, 0.76)
const SHIRT := Color(0.72, 0.22, 0.2)
const PANTS := Color(0.22, 0.28, 0.45)
const HAIR := Color(0.3, 0.19, 0.1)
const SHOE := Color(0.18, 0.14, 0.12)
const BRUISE := Color(0.42, 0.28, 0.52, 0.6)
const BLOOD := Color(0.5, 0.03, 0.04)
const DIRT := Color(0.4, 0.3, 0.2, 0.45)

var health := MAX_HEALTH

var _walk_time := 0.0
var _time := 0.0
var _facing := 1.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _squash := 0.0  # > 0 squashed (landing), < 0 stretched (jump)
var _stun := 0.0  # seconds left without control (hard landing, knockback)
var _hurt := 0.0  # seconds left of the flinch
var _invulnerable := 0.0
var _knock_dir := 0.0
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
	var push := _knock_dir if _knock_dir != 0.0 else -_facing
	velocity = Vector2(push * 120.0, -380.0)
	modulate = Color.WHITE


## Damage from a hit at `from` (global). Ignored while invulnerable or dead.
## `knockback` pushes the player away from `from` (off for fall damage).
func take_damage(amount: float, from: Vector2, cause: String, knockback := true) -> void:
	if _dead or _invulnerable > 0.0 or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	_hurt = HURT_TIME
	_invulnerable = INVULNERABLE_TIME
	_knock_dir = signf(global_position.x - from.x)
	if _knock_dir == 0.0:
		_knock_dir = -_facing
	if knockback:
		var strength := clampf(0.6 + amount / 40.0, 0.6, 1.4)
		velocity = Vector2(_knock_dir * KNOCKBACK.x, KNOCKBACK.y) * strength
		_stun = maxf(_stun, 0.25)
		_coyote = 0.0
	hurt.emit(amount, from)
	if health <= 0.0:
		died.emit(cause)


func heal(amount: float) -> void:
	if _dead:
		return
	health = minf(MAX_HEALTH, health + amount)
	healed.emit(amount)


func is_limping() -> bool:
	return health < LIMP_HEALTH and not _dead


func _process(delta: float) -> void:
	# Red flash on a hit, then flicker while invulnerable.
	_hurt = maxf(0.0, _hurt - delta)
	_invulnerable = maxf(0.0, _invulnerable - delta)
	if _dead:
		return
	var flash := _hurt / HURT_TIME
	modulate = Color(1.0, 1.0 - 0.6 * flash, 1.0 - 0.6 * flash)
	if _invulnerable > 0.0 and _hurt == 0.0 and fmod(_invulnerable, 0.14) < 0.07:
		modulate.a = 0.35


func _physics_process(delta: float) -> void:
	_time += delta
	_squash = move_toward(_squash, 0.0, delta * 1.2)

	if _dead:
		velocity.y += GRAVITY * delta
		position += velocity * delta
		rotation += signf(velocity.x) * 7.0 * delta
		queue_redraw()
		return

	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)

	_stun = maxf(0.0, _stun - delta)
	_coyote = COYOTE_TIME if is_on_floor() else _coyote - delta
	_jump_buffer = JUMP_BUFFER if Input.is_action_just_pressed("jump") else _jump_buffer - delta
	if _jump_buffer > 0.0 and _coyote > 0.0 and _stun == 0.0:
		# An injured body cannot push off as hard.
		velocity.y = JUMP_VELOCITY * (0.94 if is_limping() else 1.0)
		_jump_buffer = 0.0
		_coyote = 0.0
		_squash = -0.15
	# Releasing jump early gives a shorter hop.
	if Input.is_action_just_released("jump") and velocity.y < 0.0 and _hurt == 0.0:
		velocity.y *= 0.5

	var dir := 0.0 if _stun > 0.0 else Input.get_axis("move_left", "move_right")
	var top_speed := SPEED * (LIMP_SPEED if is_limping() else 1.0)
	var accel: float
	if is_on_floor():
		var braking := dir == 0.0 or signf(dir) != signf(velocity.x)
		accel = GROUND_FRICTION if braking else GROUND_ACCEL
	else:
		accel = AIR_DRAG if dir == 0.0 else AIR_ACCEL
	velocity.x = move_toward(velocity.x, dir * top_speed, accel * delta)
	if dir != 0.0:
		_facing = signf(dir)

	var was_on_floor := is_on_floor()
	var fall_speed := velocity.y
	move_and_slide()
	if is_on_floor() and not was_on_floor:
		_squash = clampf(fall_speed / 3000.0, 0.05, 0.3)
		landed.emit(fall_speed)
		if fall_speed > STUN_IMPACT:
			take_damage((fall_speed - STUN_IMPACT) * FALL_DAMAGE, global_position + Vector2(0, 4), "Zu tief gefallen!", false)
			_stun = STUN_TIME

	var width := get_viewport_rect().size.x
	if position.x < HALF_WIDTH or position.x > width - HALF_WIDTH:
		position.x = clampf(position.x, HALF_WIDTH, width - HALF_WIDTH)
		velocity.x = 0.0

	if is_on_floor() and absf(velocity.x) > 5.0:
		_walk_time += delta * 14.0 * absf(velocity.x) / SPEED * (1.25 if is_limping() else 1.0)
	else:
		_walk_time = 0.0
	queue_redraw()


## Two-segment limb from `root`; angles are relative to straight down and
## positive angles point in the facing direction. Returns [joint, end].
func _limb(root: Vector2, angle: float, bend: float, length: float, color: Color, width: float) -> PackedVector2Array:
	var joint := root + Vector2(sin(angle) * _facing, cos(angle)) * length
	var end := joint + Vector2(sin(angle + bend) * _facing, cos(angle + bend)) * length
	draw_polyline(PackedVector2Array([root, joint, end]), color, width)
	draw_circle(joint, width / 2.0, color)
	return PackedVector2Array([joint, end])


func _draw() -> void:
	var injury := 1.0 - health / MAX_HEALTH
	var flinch := _hurt / HURT_TIME
	var limping := is_limping()

	# Lean into the run (or snap away from a hit) and squash/stretch around the feet.
	var lean := 0.0
	if not _dead:
		lean = velocity.x / SPEED * 0.12 - _knock_dir * 0.3 * flinch
		if limping:
			lean += _facing * 0.08
	draw_set_transform(Vector2.ZERO, lean, Vector2(1.0 + _squash, 1.0 - _squash))

	var airborne := not is_on_floor() or _dead
	var running := _walk_time > 0.0
	var breathe := 0.0
	if not running and not airborne:
		breathe = sin(_time * (6.0 if limping else 2.5)) * (0.9 if limping else 0.4)
	if _stun > 0.0 and not airborne:
		breathe = sin(_time * 14.0) * 0.8  # heaving (the hip drop below lowers the torso)
	var hip := Vector2(0, -16 + (6.0 if _stun > 0.0 and not airborne else 0.0))
	if limping and running:
		hip.y += maxf(0.0, sin(_walk_time)) * 1.8  # dips onto the bad leg
	var shoulder := Vector2(0, hip.y - 13 + breathe)
	var skin := SKIN.lerp(PALE_SKIN, injury * 0.7)
	var back_skin := skin.darkened(0.18)
	var back_pants := PANTS.darkened(0.25)

	# Leg/arm poses: [thigh angle, knee bend] per leg, [upper arm, elbow] per arm.
	var legs: Array
	var arms: Array
	if flinch > 0.0 and not _dead:
		# Thrown back by the hit: arms flung up, knees buckling.
		legs = [Vector2(0.5, -0.9), Vector2(-0.35, -0.4)]
		arms = [Vector2(2.3, -0.7), Vector2(2.7, -0.5)]
	elif airborne:
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
		# A limp shortens the stride of the injured (back) leg and keeps it stiff.
		var bad := 0.35 if limping else 1.0
		legs = [Vector2(s * 0.7, -maxf(0.0, c) * 1.2), Vector2(-s * 0.7 * bad, -maxf(0.0, -c) * 1.2 * bad)]
		arms = [Vector2(-s * 0.8, 1.0), Vector2(s * 0.8, 1.0)]
		if limping:
			arms[1] = Vector2(0.5, 1.4)  # hand pressed to the hurt side
	else:
		legs = [Vector2(0.08, -0.05), Vector2(-0.08, 0.0)]
		arms = [Vector2(0.15, 0.2), Vector2(-0.1, 0.15)]
		if limping:
			legs[1] = Vector2(-0.25, -0.5)  # weight off the bad leg
			arms[1] = Vector2(0.5, 1.4)

	# Back limbs first (darker, behind the body).
	_limb(shoulder + Vector2(-_facing, 0), arms[1].x, arms[1].y, 6.5, back_skin, 3.0)
	var back_leg := _limb(hip, legs[1].x, legs[1].y, 8.0, back_pants, 4.0)
	draw_line(back_leg[1], back_leg[1] + Vector2(_facing * 3.5, 0), SHOE.darkened(0.2), 3.0)
	var front_leg := _limb(hip, legs[0].x, legs[0].y, 8.0, PANTS, 4.0)
	draw_line(front_leg[1], front_leg[1] + Vector2(_facing * 3.5, 0), SHOE, 3.0)
	if health < 60.0:
		# Torn trouser knee with a graze showing through.
		draw_circle(front_leg[0], 1.8, skin.darkened(0.05))
		draw_circle(front_leg[0] + Vector2(0, 0.5), 0.9, BLOOD.lightened(0.15))
	if health < 90.0:
		draw_circle(hip + Vector2(_facing * 2.0, 5.0), 1.6, DIRT)
		draw_circle(back_leg[0], 1.4, DIRT)

	# Torso with a shaded back side and a belt.
	var torso := Rect2(-6, shoulder.y - 2, 12, hip.y - shoulder.y + 3)
	draw_rect(torso, SHIRT)
	var back_x := -6.0 if _facing > 0.0 else 3.0
	draw_rect(Rect2(back_x, torso.position.y, 3, torso.size.y), SHIRT.darkened(0.2))
	if health < 90.0:
		draw_circle(Vector2(_facing * 2.5, shoulder.y + 3.0), 1.8, DIRT)
	if health < 50.0:
		# Ripped hem showing skin, plus a frayed tear.
		var hem := hip.y - 3.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(_facing * 1.0, hem), Vector2(_facing * 5.5, hem), Vector2(_facing * 3.5, hem - 5.0)]), skin.darkened(0.1))
		draw_line(Vector2(-_facing * 3.0, shoulder.y + 2.0), Vector2(-_facing * 1.0, shoulder.y + 6.0), SHIRT.darkened(0.5), 1.0)
	if health < 30.0:
		# Blood soaking through the shirt, with a drip.
		var wound := Vector2(_facing * 0.5, shoulder.y + 7.0)
		draw_circle(wound, 2.6, BLOOD.lightened(0.05))
		draw_circle(wound + Vector2(0.8, -0.5), 1.6, BLOOD.darkened(0.2))
		draw_line(wound, wound + Vector2(0.3, 4.0 + sin(_time * 1.3) * 0.5), BLOOD, 1.2)
	draw_rect(Rect2(-6, hip.y - 3, 12, 3), PANTS.darkened(0.35))

	# Head: hair behind, face turned towards the facing direction; snaps back on a hit.
	var head := Vector2(_facing * 0.5 - _facing * 1.5 * flinch, shoulder.y - 9)
	draw_rect(Rect2(-2, shoulder.y - 4, 4, 3), skin.darkened(0.1))  # neck
	draw_circle(head + Vector2(-_facing * 1.0, -1.5), 7.2, HAIR)
	draw_circle(head + Vector2(_facing * 0.8, 0.5), 6.4, skin)
	draw_rect(Rect2(head.x - 6.5, head.y - 7.5, 13, 3.5), HAIR)
	draw_circle(head + Vector2(-_facing * 1.5, 0.5), 1.6, skin.darkened(0.12))  # ear
	_draw_face_injuries(head)

	var eye := head + Vector2(_facing * 3.5, -0.5)
	if _dead:
		draw_line(eye + Vector2(-1.3, -1.3), eye + Vector2(1.3, 1.3), Color.BLACK, 1.0)
		draw_line(eye + Vector2(-1.3, 1.3), eye + Vector2(1.3, -1.3), Color.BLACK, 1.0)
	elif flinch > 0.0:
		# Squeezed shut, mouth open in pain.
		draw_line(eye + Vector2(-1.4, -0.8), eye + Vector2(1.2, 0.2), Color(0.15, 0.1, 0.08), 1.0)
		draw_circle(head + Vector2(_facing * 4.2, 3.6), 1.3, Color(0.3, 0.08, 0.08))
	else:
		draw_circle(eye, 1.2, Color(0.15, 0.1, 0.08))
		if limping:
			draw_line(head + Vector2(_facing * 2.5, 3.8), head + Vector2(_facing * 5.0, 3.4), Color(0.35, 0.15, 0.12), 0.8)  # grimace
	draw_circle(head + Vector2(_facing * 6.6, 1.2), 1.3, skin.darkened(0.08))  # nose

	# Front arm over the body.
	var arm := _limb(shoulder + Vector2(_facing, 0), arms[0].x, arms[0].y, 6.5, skin, 3.0)
	if health < 75.0:
		# Scratches on the forearm.
		var along := (arm[1] - arm[0]).normalized()
		var across := along.orthogonal() * 1.5
		var mid := arm[0].lerp(arm[1], 0.5)
		draw_line(mid - across, mid + across + along, Color(0.7, 0.15, 0.12, 0.8), 0.8)
		if health < 45.0:
			draw_line(mid - across - along * 2.0, mid + across - along, Color(0.7, 0.15, 0.12, 0.8), 0.8)
	draw_set_transform(Vector2.ZERO)


func _draw_face_injuries(head: Vector2) -> void:
	if health < 70.0:
		draw_circle(head + Vector2(_facing * 2.8, 2.6), 1.9, BRUISE)  # cheek bruise
	if health < 55.0:
		draw_line(head + Vector2(_facing * -1.0, -3.5), head + Vector2(_facing * 2.5, -2.2), Color(0.65, 0.12, 0.1, 0.9), 0.9)  # forehead cut
	if health < 40.0:
		draw_circle(head + Vector2(_facing * 3.5, -0.5), 2.4, Color(0.32, 0.18, 0.4, 0.75))  # black eye
	if health < 20.0:
		# Blood trickling down from the hairline.
		var top := head + Vector2(_facing * 0.5, -4.0)
		draw_polyline(PackedVector2Array([top, top + Vector2(_facing * 0.6, 3.0), top + Vector2(_facing * 0.3, 6.5)]), BLOOD, 1.1)
