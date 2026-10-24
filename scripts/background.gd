extends Node2D
## Sky behind everything, drawn in screen space (main.gd puts it on a CanvasLayer
## below the game). The sky darkens and stars appear the higher the camera climbs;
## mountains and clouds scroll slower than the world (parallax) and drop away below.
## Set `camera` before adding to the tree.

const LOW_TOP := Color(0.36, 0.58, 0.86)
const LOW_BOTTOM := Color(0.76, 0.86, 0.93)
const HIGH_TOP := Color(0.03, 0.04, 0.14)
const HIGH_BOTTOM := Color(0.2, 0.24, 0.45)
const FAR_MOUNTAIN := Color(0.42, 0.48, 0.6)
const NEAR_HILL := Color(0.24, 0.36, 0.28)
const SKY_DARK_CLIMB := 9000.0  # climb (px) at which the sky is fully dark

var camera: Camera2D

var _size := Vector2.ZERO
var _start_y := 0.0
var _far := PackedVector2Array()
var _near := PackedVector2Array()
var _clouds: Array[Dictionary] = []  # {pos, speed, scale}
var _stars := PackedVector2Array()
var _time := 0.0


func _ready() -> void:
	_size = get_viewport_rect().size
	_start_y = camera.position.y
	_far = _ridge(10, 90.0, 190.0)
	_near = _ridge(7, 25.0, 70.0)
	for i in 7:
		_clouds.append({
			"pos": Vector2(randf_range(0.0, _size.x + 160.0), randf_range(0.0, _size.y + 200.0)),
			"speed": randf_range(5.0, 16.0),
			"scale": randf_range(0.6, 1.3),
		})
	for i in 70:
		_stars.append(Vector2(randf() * _size.x, randf() * _size.y))


## Alternating peaks and valleys across the screen width; y is relative to the baseline.
func _ridge(points: int, min_h: float, max_h: float) -> PackedVector2Array:
	var ridge := PackedVector2Array()
	for i in points + 1:
		var h := randf_range(min_h, max_h) if i % 2 == 0 else randf_range(min_h * 0.3, min_h)
		ridge.append(Vector2(_size.x * i / points + randf_range(-15.0, 15.0), -h))
	ridge[0].x = 0.0
	ridge[points].x = _size.x
	return ridge


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var climb := maxf(0.0, _start_y - camera.position.y)
	var t := clampf(climb / SKY_DARK_CLIMB, 0.0, 1.0)
	var top := LOW_TOP.lerp(HIGH_TOP, t)
	var bottom := LOW_BOTTOM.lerp(HIGH_BOTTOM, t)
	draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(_size.x, 0), _size, Vector2(0, _size.y)]),
		PackedColorArray([top, top, bottom, bottom]))

	# Stars fade in high up.
	var star_alpha := clampf((climb - 3500.0) / 4000.0, 0.0, 1.0)
	if star_alpha > 0.0:
		for star in _stars:
			var twinkle := 0.6 + 0.4 * sin(_time * 2.0 + star.x)
			draw_circle(Vector2(star.x, fposmod(star.y + climb * 0.02, _size.y)), 1.1, Color(1, 1, 1, star_alpha * twinkle))

	# Mountains sink below the screen as you climb past them; distant ones are hazier.
	_draw_ridge(_far, 650.0 + climb * 0.05, FAR_MOUNTAIN.lerp(bottom, 0.35), true)
	_draw_ridge(_near, 650.0 + climb * 0.12, NEAR_HILL.lerp(bottom, 0.15), false)

	# Clouds thin out once you are above them.
	# Faded by blending into the sky colour (opaque, so overlapping puffs stay clean).
	var cloud_fade := clampf((climb - 5000.0) / 3000.0, 0.0, 1.0)
	if cloud_fade < 1.0:
		for cloud in _clouds:
			var pos := Vector2(
				fposmod(cloud.pos.x + _time * cloud.speed, _size.x + 160.0) - 80.0,
				fposmod(cloud.pos.y + climb * 0.3, _size.y + 200.0) - 100.0)
			var sky := top.lerp(bottom, clampf(pos.y / _size.y, 0.0, 1.0))
			_draw_cloud(pos, cloud.scale, Color(0.97, 0.98, 1.0).lerp(sky, 0.2 + 0.8 * cloud_fade))


func _draw_ridge(ridge: PackedVector2Array, baseline: float, color: Color, snow: bool) -> void:
	var poly := PackedVector2Array()
	var highest := baseline
	for p in ridge:
		poly.append(Vector2(p.x, baseline + p.y))
		highest = minf(highest, baseline + p.y)
	if highest > _size.y:
		return
	var floor_y := maxf(baseline, _size.y) + 1.0
	poly.append(Vector2(_size.x, floor_y))
	poly.append(Vector2(0, floor_y))
	draw_colored_polygon(poly, color)

	if not snow:
		return
	for i in range(1, ridge.size() - 1):
		var peak := poly[i]
		if ridge[i].y > -130.0 or peak.y < poly[i - 1].y or peak.y < poly[i + 1].y:
			continue
		var cap := PackedVector2Array([peak, peak.lerp(poly[i + 1], 0.22), peak.lerp(poly[i - 1], 0.22)])
		draw_colored_polygon(cap, Color(0.95, 0.96, 1.0).lerp(color, 0.25))


func _draw_cloud(pos: Vector2, scale_factor: float, color: Color) -> void:
	for puff in [Vector3(-22, 4, 13), Vector3(-6, -5, 17), Vector3(14, -2, 15), Vector3(28, 5, 11), Vector3(4, 6, 14)]:
		draw_circle(pos + Vector2(puff.x, puff.y) * scale_factor, puff.z * scale_factor, color)
