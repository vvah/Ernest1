extends Node2D
## A rock breaking apart: tumbling shards under gravity, a dust cloud and a few
## sparks, all fading out. Set `color`, `radius` and `velocity` (the rock's speed,
## partly passed on to the shards) before adding; frees itself when done.

const GRAVITY := 900.0
const LIFETIME := 1.3

var color := Color(0.5, 0.47, 0.45)
var radius := 12.0
var velocity := Vector2.ZERO

var _shards: Array[Dictionary] = []  # {points, pos, vel, angle, spin, shade}
var _puffs: Array[Dictionary] = []   # {pos, vel, r}
var _sparks: Array[Dictionary] = []  # {pos, vel}
var _age := 0.0


func _ready() -> void:
	for i in randi_range(6, 9):
		var size := radius * randf_range(0.25, 0.5)
		# Corners spread evenly round the circle (with a little jitter) so the
		# outline never folds over itself.
		var points := PackedVector2Array()
		var corners := randi_range(3, 5)
		for k in corners:
			points.append(Vector2.from_angle(TAU * (k + randf_range(-0.25, 0.25)) / corners) * size * randf_range(0.6, 1.0))
		var out := Vector2.from_angle(randf_range(PI * 1.05, PI * 1.95))  # mostly upwards and sideways
		_shards.append({
			"points": points,
			"pos": out * radius * 0.4,
			"vel": out * randf_range(90.0, 260.0) + velocity * 0.15,
			"angle": randf() * TAU,
			"spin": randf_range(-14.0, 14.0),
			"shade": randf_range(-0.2, 0.25),
		})
	for i in 7:
		_puffs.append({
			"pos": Vector2(randf_range(-radius, radius), randf_range(-radius * 0.5, radius * 0.3)),
			"vel": Vector2(randf_range(-50.0, 50.0), randf_range(-45.0, -5.0)),
			"r": randf_range(radius * 0.4, radius * 0.8),
		})
	for i in 5:
		_sparks.append({"pos": Vector2.ZERO, "vel": Vector2.from_angle(randf_range(PI, TAU)) * randf_range(150.0, 320.0)})


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	for shard in _shards:
		shard.vel.y += GRAVITY * delta
		shard.pos += shard.vel * delta
		shard.angle += shard.spin * delta
	for puff in _puffs:
		puff.vel *= exp(-3.0 * delta)
		puff.pos += puff.vel * delta
		puff.r += 14.0 * delta
	for spark in _sparks:
		spark.vel.y += GRAVITY * 0.5 * delta
		spark.pos += spark.vel * delta
	queue_redraw()


func _draw() -> void:
	var t := _age / LIFETIME
	var dust := Color(0.78, 0.74, 0.68, 0.55 * (1.0 - t) * (1.0 - t))
	for puff in _puffs:
		draw_circle(puff.pos, puff.r, dust)

	if _age < 0.18:
		var glow := 1.0 - _age / 0.18
		for spark in _sparks:
			draw_line(spark.pos, spark.pos - spark.vel * 0.02, Color(1.0, 0.9, 0.6, glow), 1.5)

	var fade := clampf((LIFETIME - _age) / 0.4, 0.0, 1.0)
	for shard in _shards:
		var shape := PackedVector2Array()
		for p in shard.points:
			shape.append(shard.pos + p.rotated(shard.angle))
		var base: Color = color.lightened(shard.shade) if shard.shade > 0.0 else color.darkened(-shard.shade)
		base.a = fade
		draw_colored_polygon(shape, base)
		shape.append(shape[0])
		draw_polyline(shape, Color(base.darkened(0.5), fade), 1.0)
