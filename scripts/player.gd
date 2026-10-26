extends CharacterBody2D
## The little human. Origin is at the feet; drawn with primitives in _draw().
## Movement has momentum: it speeds up and slows down instead of snapping.
## Has health: hits knock the player back, leave visible injuries and, when
## health is low, make them limp. Where a hit lands matters: head hits concuss
## (dizzy, double vision), hard landings sprain an ankle, heavy hits bleed until
## bandaged by a medkit. Fireballs set them alight. On death the body goes limp
## as a verlet ragdoll that lands on ledges. main.gd reacts to `hurt` and `died`.

signal landed(impact_speed: float)
signal hurt(amount: float, from: Vector2, cause: String)
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
const BURN_TIME := 1.6           # seconds on fire after a fireball
const BURN_DPS := 7.0            # damage per second while burning
const HEAD_HEIGHT := 30.0        # hits from above this (px over the feet) strike the head
const HEAD_MULTIPLIER := 1.3
const CONCUSSION_MAX := 5.0      # seconds of dizziness at most
const SPRAIN_TIME := 6.0         # limping after a hard landing, whatever the health
const BLEED_MIN_DAMAGE := 15.0   # hits at least this hard open a bleeding wound
const BLEED_DPS := 1.5
const DEATH_BLEED := 2.5         # seconds the body keeps bleeding after death

# Ragdoll joints (indices into _rag) and the bone lengths that hold them together.
enum { HEAD, NECK, HIP, KNEE_F, FOOT_F, KNEE_B, FOOT_B, ELBOW_F, HAND_F, ELBOW_B, HAND_B }
const BONES := [
	[HEAD, NECK, 9.0], [NECK, HIP, 13.0], [HEAD, HIP, 21.5],
	[HIP, KNEE_F, 8.0], [KNEE_F, FOOT_F, 8.0], [HIP, KNEE_B, 8.0], [KNEE_B, FOOT_B, 8.0],
	[NECK, ELBOW_F, 6.5], [ELBOW_F, HAND_F, 6.5], [NECK, ELBOW_B, 6.5], [ELBOW_B, HAND_B, 6.5],
]

# Street look: green T-shirt, blue jeans, white sneakers, a gold chain,
# short buzzed black hair and a trimmed beard.
const SKIN := Color(0.42, 0.27, 0.18)
const ASHEN_SKIN := Color(0.46, 0.4, 0.36)  # loss of blood greys the skin
const SHIRT := Color(0.24, 0.55, 0.28)
const PANTS := Color(0.2, 0.3, 0.5)
const HAIR := Color(0.07, 0.06, 0.06)
const SHOE := Color(0.95, 0.95, 0.95)
const GOLD := Color(0.95, 0.78, 0.25)
const BRUISE := Color(0.22, 0.1, 0.22, 0.7)
const BLOOD := Color(0.5, 0.03, 0.04)
const DIRT := Color(0.4, 0.3, 0.2, 0.5)
const SOOT := Color(0.08, 0.07, 0.06, 0.75)
const BANDAGE := Color(0.94, 0.93, 0.89)

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
var _burn := 0.0  # seconds left on fire
var _scorched := false  # clothes singed by fire (stays for the run)
var _concussion := 0.0  # seconds of dizziness left after a head hit
var _sprain := 0.0  # seconds of limping left after a hard landing
var _bleed := 0.0  # seconds of bleeding left
var _bandaged := false  # a medkit wrapped the wounds (shown until the run ends)
var _dead := false
var _rag := PackedVector2Array()  # ragdoll joint positions (global), see BONES
var _rag_prev := PackedVector2Array()


func _ready() -> void:
	add_to_group("player")


## Called by enemies when stomped.
func bounce() -> void:
	velocity.y = JUMP_VELOCITY * 0.75
	_coyote = 0.0
	_squash = -0.12


## Knocked out: the body goes limp as a ragdoll, thrown away from the last hit,
## and keeps bleeding for a moment where it comes to rest.
func die() -> void:
	_dead = true
	collision_layer = 0
	collision_mask = 0
	modulate = Color.WHITE
	_bleed = DEATH_BLEED
	var push := _knock_dir if _knock_dir != 0.0 else -_facing
	var f := _facing
	var pose := [Vector2(0, -38), Vector2(0, -29), Vector2(0, -16),
		Vector2(f * 2, -8), Vector2(f * 2, 0), Vector2(-f * 2, -8), Vector2(-f * 2, 0),
		Vector2(f * 3, -23), Vector2(f * 4, -17), Vector2(-f * 3, -23), Vector2(-f * 4, -17)]
	_rag.clear()
	_rag_prev.clear()
	var dt := 1.0 / Engine.physics_ticks_per_second
	for i in pose.size():
		var p: Vector2 = global_position + pose[i]
		# Upper body is thrown harder than the feet, so the body tips over.
		var lift: float = -pose[i].y / 38.0
		var v := Vector2(push * (60.0 + 160.0 * lift), -300.0 - 120.0 * lift) + Vector2(randf_range(-30, 30), randf_range(-30, 30))
		_rag.append(p)
		_rag_prev.append(p - v * dt)


## Damage from a hit at `from` (global). Ignored while invulnerable or dead.
## `knockback` pushes the player away from `from` (off for fall damage).
## Hits from above strike the head (more damage, concussion); hits from below
## the feet are landings (sprained ankle); hard hits open a bleeding wound.
func take_damage(amount: float, from: Vector2, cause: String, knockback := true) -> void:
	if _dead or _invulnerable > 0.0 or amount <= 0.0:
		return
	var height := global_position.y - from.y  # how far above the feet the hit came from
	if height > HEAD_HEIGHT:
		amount *= HEAD_MULTIPLIER
		_concussion = minf(CONCUSSION_MAX, _concussion + amount / 10.0)
	elif height < 0.0:
		_sprain = SPRAIN_TIME
	if amount >= BLEED_MIN_DAMAGE and height >= 0.0 and cause != "Verbrannt!":
		_bleed = maxf(_bleed, 4.0 + amount * 0.15)  # burns sear shut, landings bruise
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
	hurt.emit(amount, from, cause)
	if health <= 0.0:
		died.emit(cause)


## Sets the clothes alight: damage over time that ignores invulnerability.
func ignite() -> void:
	if _dead:
		return
	_burn = BURN_TIME
	_scorched = true


## A medkit: restores health, stops bleeding and bandages visible wounds.
func heal(amount: float) -> void:
	if _dead:
		return
	if health < 75.0 or _bleed > 0.0:
		_bandaged = true
	_bleed = 0.0
	health = minf(MAX_HEALTH, health + amount)
	healed.emit(amount)


func is_limping() -> bool:
	return (health < LIMP_HEALTH or _sprain > 0.0) and not _dead


func is_bleeding() -> bool:
	return _bleed > 0.0


func is_burning() -> bool:
	return _burn > 0.0


func is_sprained() -> bool:
	return _sprain > 0.0 and not _dead


## 0..1: how dizzy the player is (drives the double-vision shader in main.gd).
func daze() -> float:
	return 0.0 if _dead else clampf(_concussion / 2.0, 0.0, 1.0)


## Where blood drips from (the chest, following the ragdoll after death).
func bleed_point() -> Vector2:
	if _dead and not _rag.is_empty():
		return _rag[NECK].lerp(_rag[HIP], 0.4)
	return global_position + Vector2(_facing * 1.0, -22.0)


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

	_burn = maxf(0.0, _burn - delta)
	_bleed = maxf(0.0, _bleed - delta)
	_concussion = maxf(0.0, _concussion - delta)
	_sprain = maxf(0.0, _sprain - delta)

	if _dead:
		_step_ragdoll(delta)
		queue_redraw()
		return

	# Fire and open wounds keep draining health.
	if _burn > 0.0 or _bleed > 0.0:
		var drain := (BURN_DPS if _burn > 0.0 else 0.0) + (BLEED_DPS if _bleed > 0.0 else 0.0)
		health = maxf(0.0, health - drain * delta)
		if health <= 0.0:
			died.emit("Verbrannt!" if _burn > 0.0 else "Verblutet!")
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
	# Dizziness makes the player stagger slightly off course.
	var stagger := sin(_time * 1.7) * 45.0 * daze() if is_on_floor() and dir != 0.0 else 0.0
	velocity.x = move_toward(velocity.x, dir * top_speed + stagger, accel * delta)
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


## Verlet ragdoll: joints keep their momentum, fall under gravity, are pulled
## back to their bone lengths and come to rest on top of ledges (and the ground).
func _step_ragdoll(delta: float) -> void:
	if _rag.is_empty():
		return
	var blocks := get_tree().get_nodes_in_group("blocks")
	var width := get_viewport_rect().size.x
	for i in _rag.size():
		var p := _rag[i]
		var v := (p - _rag_prev[i]) * 0.995
		_rag_prev[i] = p
		_rag[i] = p + v + Vector2(0, GRAVITY) * delta * delta
	for iteration in 6:
		for bone in BONES:
			var a: int = bone[0]
			var b: int = bone[1]
			var d := _rag[b] - _rag[a]
			var dist := maxf(d.length(), 0.001)
			var length: float = bone[2]
			var push := d * (0.5 * (dist - length) / dist)
			_rag[a] += push
			_rag[b] -= push
		for i in _rag.size():
			var p := _rag[i]
			p.x = clampf(p.x, 2.0, width - 2.0)
			# Land on a ledge only when coming down onto it from above.
			for block in blocks:
				var top: float = block.top_y()
				if _rag_prev[i].y <= top + 0.5 and p.y > top and block.covers_x(p.x):
					p.y = top
					_rag_prev[i].x = p.x - (p.x - _rag_prev[i].x) * 0.5  # ground friction
					break
			_rag[i] = p


func _draw_ragdoll() -> void:
	var at := func(joint: int) -> Vector2: return _rag[joint] - global_position
	var skin := ASHEN_SKIN
	var shirt := SHIRT.lerp(Color(0.2, 0.22, 0.16), 0.35) if _scorched else SHIRT
	# Back limbs, then legs, torso, head, front arm — like the living pose.
	draw_polyline(PackedVector2Array([at.call(NECK), at.call(ELBOW_B), at.call(HAND_B)]), skin.darkened(0.18), 3.0)
	for leg in [[KNEE_B, FOOT_B, PANTS.darkened(0.25)], [KNEE_F, FOOT_F, PANTS]]:
		draw_polyline(PackedVector2Array([at.call(HIP), at.call(leg[0]), at.call(leg[1])]), leg[2], 4.0)
		draw_circle(at.call(leg[1]), 2.0, SHOE.darkened(0.3))
	draw_line(at.call(NECK), at.call(HIP), shirt, 11.0)
	var wound: Vector2 = at.call(NECK).lerp(at.call(HIP), 0.45)
	draw_circle(wound, 3.0, BLOOD)
	# The face points sideways from the neck-to-head axis, towards where they last looked.
	var head: Vector2 = at.call(HEAD)
	var neck: Vector2 = at.call(NECK)
	var up := (head - neck).normalized()
	var side := up.orthogonal() * -_facing
	draw_circle(head, 6.9, HAIR)
	draw_circle(head + side * 0.8, 6.2, skin)
	var eye := head + side * 3.5 + up * 0.5
	draw_line(eye + Vector2(-1.3, -1.3), eye + Vector2(1.3, 1.3), Color.BLACK, 1.0)
	draw_line(eye + Vector2(-1.3, 1.3), eye + Vector2(1.3, -1.3), Color.BLACK, 1.0)
	if _bandaged:
		draw_line(head + up * 3.5 - side * 6.0, head + up * 3.5 + side * 6.0, BANDAGE, 3.0)
	draw_polyline(PackedVector2Array([at.call(NECK), at.call(ELBOW_F), at.call(HAND_F)]), skin, 3.0)


## Two-segment limb from `root`; angles are relative to straight down and
## positive angles point in the facing direction. `lower` colours the second
## segment (sleeve/skin, shorts/sock). Returns [joint, end].
func _limb(root: Vector2, angle: float, bend: float, length: float, upper: Color, lower: Color, width: float) -> PackedVector2Array:
	var joint := root + Vector2(sin(angle) * _facing, cos(angle)) * length
	var end := joint + Vector2(sin(angle + bend) * _facing, cos(angle + bend)) * length
	draw_line(joint, end, lower, width)
	draw_circle(joint, width / 2.0, lower)
	draw_line(root, joint, upper, width)
	return PackedVector2Array([joint, end])


func _draw() -> void:
	if _dead and not _rag.is_empty():
		_draw_ragdoll()
		return
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
	var skin := SKIN.lerp(ASHEN_SKIN, injury * 0.6)
	var shirt := SHIRT.lerp(Color(0.2, 0.22, 0.16), 0.35) if _scorched else SHIRT
	var back_skin := skin.darkened(0.18)
	var back_pants := PANTS.darkened(0.25)
	var back_shirt := shirt.darkened(0.2)

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
	elif _burn > 0.0:
		# Frantically patting out the flames.
		var pat := sin(_time * 30.0) * 0.5
		legs = [Vector2(0.15, -0.2), Vector2(-0.15, -0.1)]
		arms = [Vector2(1.0 + pat, 1.6), Vector2(1.2 - pat, 1.5)]
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
	_limb(shoulder + Vector2(-_facing, 0), arms[1].x, arms[1].y, 6.5, back_shirt, back_skin, 3.0)
	var back_leg := _limb(hip, legs[1].x, legs[1].y, 8.0, back_pants, back_pants, 4.0)
	draw_line(back_leg[1], back_leg[1] + Vector2(_facing * 4.0, 0), SHOE.darkened(0.25 + 0.3 * injury), 3.5)
	var front_leg := _limb(hip, legs[0].x, legs[0].y, 8.0, PANTS, PANTS, 4.0)
	draw_line(front_leg[1], front_leg[1] + Vector2(_facing * 4.0, 0), SHOE.darkened(0.3 * injury), 3.5)  # sneakers get grubby
	if health < 60.0:
		# Torn jeans knee with a graze showing through.
		draw_circle(front_leg[0], 1.8, skin.darkened(0.05))
		draw_circle(front_leg[0] + Vector2(0, 0.5), 0.9, BLOOD.lightened(0.15))
	if health < 90.0:
		draw_circle(hip + Vector2(_facing * 2.0, 5.0), 1.6, DIRT)
		draw_circle(back_leg[0], 1.4, DIRT)

	# T-shirt with a shaded back side, jeans waist and a gold chain.
	var torso := Rect2(-6, shoulder.y - 2, 12, hip.y - shoulder.y + 1)
	draw_rect(torso, shirt)
	var back_x := -6.0 if _facing > 0.0 else 3.0
	draw_rect(Rect2(back_x, torso.position.y, 3, torso.size.y), Color(0, 0, 0, 0.18))
	if health < 90.0:
		draw_circle(Vector2(_facing * 2.5, shoulder.y + 4.0), 1.8, DIRT)
	if _scorched:
		# Singed holes with charred edges.
		draw_circle(Vector2(-_facing * 2.0, shoulder.y + 6.0), 2.2, SOOT)
		draw_circle(Vector2(_facing * 3.0, hip.y - 4.0), 1.5, SOOT)
	if health < 50.0:
		# Ripped hem showing skin, plus a frayed tear.
		var hem := hip.y - 2.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(_facing * 1.0, hem), Vector2(_facing * 5.5, hem), Vector2(_facing * 3.5, hem - 5.0)]), skin.darkened(0.1))
		draw_line(Vector2(-_facing * 3.0, shoulder.y + 2.0), Vector2(-_facing * 1.0, shoulder.y + 6.0), shirt.darkened(0.5), 1.0)
	if health < 30.0 or _bleed > 0.0:
		# Blood soaking through the shirt, with a drip.
		var wound := Vector2(_facing * 0.5, shoulder.y + 7.0)
		draw_circle(wound, 2.6, BLOOD.lightened(0.05))
		draw_circle(wound + Vector2(0.8, -0.5), 1.6, BLOOD.darkened(0.2))
		draw_line(wound, wound + Vector2(0.3, 4.0 + sin(_time * 1.3) * 0.5), BLOOD, 1.2)
	draw_rect(Rect2(-6, hip.y - 2, 12, 3), PANTS)
	# The chain snaps when badly hurt and dangles from one side.
	if health >= 30.0:
		draw_polyline(PackedVector2Array([Vector2(-2.5, shoulder.y - 1.5), Vector2(_facing * 1.0, shoulder.y + 3.0), Vector2(3.0, shoulder.y - 1.5)]), GOLD, 1.0)
	else:
		draw_polyline(PackedVector2Array([Vector2(-2.5, shoulder.y - 1.5), Vector2(-2.0, shoulder.y + 4.0)]), GOLD, 1.0)

	# Head: face turned towards the facing direction; snaps back on a hit.
	var head := Vector2(_facing * 0.5 - _facing * 1.5 * flinch, shoulder.y - 9)
	head += Vector2(sin(_time * 3.1), cos(_time * 2.3) * 0.5) * 1.3 * daze()  # concussed: head lolls
	draw_rect(Rect2(-2, shoulder.y - 4, 4, 3), skin.darkened(0.1))  # neck
	draw_circle(head + Vector2(-_facing * 0.5, -0.5), 6.9, HAIR)  # buzz cut shows round the back
	draw_circle(head + Vector2(_facing * 0.8, 0.5), 6.4, skin)
	draw_rect(Rect2(head.x - 6.0, head.y - 6.8, 12, 2.2), HAIR)  # short hairline
	# Trimmed beard: thin line along the jaw into a chin beard, plus a moustache.
	var face := head + Vector2(_facing * 0.8, 0.5)
	var jaw := PackedVector2Array()
	for i in 7:
		var a := lerpf(0.15, PI * 0.55, i / 6.0)
		jaw.append(face + Vector2(_facing * cos(a) * 6.2, sin(a) * 6.3))
	draw_polyline(jaw, HAIR, 1.6)
	draw_line(head + Vector2(_facing * 3.5, 2.2), head + Vector2(_facing * 6.0, 2.0), HAIR, 1.2)  # moustache
	draw_circle(head + Vector2(-_facing * 1.5, 0.5), 1.6, skin.darkened(0.12))  # ear
	_draw_face_injuries(head)

	var eye := head + Vector2(_facing * 3.5, -0.5)
	if _dead:
		draw_line(eye + Vector2(-1.3, -1.3), eye + Vector2(1.3, 1.3), Color.BLACK, 1.0)
		draw_line(eye + Vector2(-1.3, 1.3), eye + Vector2(1.3, -1.3), Color.BLACK, 1.0)
	elif flinch > 0.0 or _burn > 0.0:
		# Squeezed shut, mouth open in pain.
		draw_line(eye + Vector2(-1.4, -0.8), eye + Vector2(1.2, 0.2), Color(0.1, 0.06, 0.05), 1.0)
		draw_circle(head + Vector2(_facing * 4.6, 3.6), 1.3, Color(0.25, 0.05, 0.05))
	else:
		draw_circle(eye, 1.2, Color(0.1, 0.06, 0.05))
		if limping:
			draw_line(head + Vector2(_facing * 3.6, 3.8), head + Vector2(_facing * 5.8, 3.2), skin.darkened(0.45), 1.0)  # grimace
		else:
			draw_line(head + Vector2(_facing * 3.8, 3.6), head + Vector2(_facing * 5.6, 3.4), skin.darkened(0.35), 1.0)  # mouth
	draw_circle(head + Vector2(_facing * 6.6, 1.2), 1.3, skin.darkened(0.08))  # nose

	# Front arm over the body.
	var arm := _limb(shoulder + Vector2(_facing, 0), arms[0].x, arms[0].y, 6.5, shirt, skin, 3.0)
	if health < 75.0:
		# Scratches on the forearm.
		var along := (arm[1] - arm[0]).normalized()
		var across := along.orthogonal() * 1.5
		var mid := arm[0].lerp(arm[1], 0.5)
		draw_line(mid - across, mid + across + along, Color(0.7, 0.12, 0.1, 0.9), 0.8)
		if health < 45.0:
			draw_line(mid - across - along * 2.0, mid + across - along, Color(0.7, 0.12, 0.1, 0.9), 0.8)
	if _bandaged:
		# Forearm and knee wrapped.
		draw_line(arm[0].lerp(arm[1], 0.25), arm[0].lerp(arm[1], 0.75), BANDAGE, 3.6)
		draw_circle(front_leg[0], 2.4, BANDAGE)

	if _burn > 0.0:
		_draw_flames(shoulder, hip)
	draw_set_transform(Vector2.ZERO)


func _draw_face_injuries(head: Vector2) -> void:
	if health < 70.0:
		draw_circle(head + Vector2(_facing * 2.8, 2.0), 1.9, BRUISE)  # cheek bruise
	if health < 55.0:
		draw_line(head + Vector2(_facing * -1.0, -3.5), head + Vector2(_facing * 2.5, -2.2), Color(0.7, 0.1, 0.08, 0.95), 0.9)  # forehead cut
	if health < 40.0:
		draw_circle(head + Vector2(_facing * 3.5, -0.5), 2.4, Color(0.15, 0.05, 0.15, 0.8))  # swollen black eye
	if health < 20.0:
		# Blood trickling down from the hairline.
		var top := head + Vector2(_facing * 0.5, -4.0)
		draw_polyline(PackedVector2Array([top, top + Vector2(_facing * 0.6, 3.0), top + Vector2(_facing * 0.3, 6.5)]), BLOOD, 1.1)
	if _scorched:
		draw_circle(head + Vector2(-_facing * 2.0, 2.5), 1.6, Color(0.05, 0.04, 0.04, 0.5))  # soot smudge
	if _bandaged:
		# Gauze wrapped round the forehead, a spot of blood seeping through.
		draw_rect(Rect2(head.x - 6.4, head.y - 5.2, 12.8, 2.8), BANDAGE)
		draw_line(Vector2(head.x - 6.4, head.y - 3.9), Vector2(head.x + 6.4, head.y - 3.9), BANDAGE.darkened(0.12), 0.6)
		draw_circle(head + Vector2(_facing * 1.5, -3.8), 0.9, BLOOD.lightened(0.2))


## Flickering tongues of fire licking up from the clothes.
func _draw_flames(shoulder: Vector2, hip: Vector2) -> void:
	var strength := clampf(_burn / BURN_TIME * 1.5, 0.3, 1.0)
	for i in 5:
		var base := Vector2(lerpf(-5.0, 5.0, i / 4.0), lerpf(hip.y - 2.0, shoulder.y + 4.0, fmod(i * 0.37, 1.0)))
		var h := (6.0 + 4.0 * sin(_time * 23.0 + i * 1.7)) * strength
		var sway := sin(_time * 17.0 + i) * 1.5
		var outer := PackedVector2Array([base + Vector2(-2.2, 0), base + Vector2(2.2, 0), base + Vector2(sway, -h)])
		draw_colored_polygon(outer, Color(1.0, 0.4, 0.05, 0.85))
		var inner := PackedVector2Array([base + Vector2(-1.1, 0), base + Vector2(1.1, 0), base + Vector2(sway * 0.6, -h * 0.55)])
		draw_colored_polygon(inner, Color(1.0, 0.85, 0.3, 0.95))
	# Smoke wisps.
	for i in 2:
		var t := fmod(_time * 1.5 + i * 0.5, 1.0)
		draw_circle(Vector2(sin(_time * 3.0 + i) * 2.0, shoulder.y - 4.0 - t * 14.0), 2.0 + t * 3.0, Color(0.25, 0.25, 0.25, 0.4 * (1.0 - t) * strength))
