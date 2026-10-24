extends Node2D
## Mountain valley behind everything, drawn in screen space (main.gd puts it on a
## CanvasLayer below the game). Back to front: sky, sun/moon, stars, three mountain
## ranges fading into haze, clouds, forested hills, rock cliffs with pines on both
## sides, snowfall. Everything scrolls slower than the world (parallax); the sky
## darkens and snow sets in the higher the camera climbs. Set `camera` before adding.

const Block := preload("res://scripts/block.gd")

const LOW_TOP := Color(0.33, 0.56, 0.86)
const LOW_BOTTOM := Color(0.8, 0.87, 0.93)
const HIGH_TOP := Color(0.03, 0.04, 0.14)
const HIGH_BOTTOM := Color(0.2, 0.24, 0.45)
const FAR_RANGE := Color(0.52, 0.58, 0.72)
const MID_RANGE := Color(0.38, 0.43, 0.52)
const HILLS := Color(0.2, 0.34, 0.24)
const PINE := Color(0.1, 0.24, 0.15)
const CLIFF := Color(0.56, 0.52, 0.48)
const SNOW := Color(0.96, 0.97, 1.0)
const SNOW_SHADE := Color(0.72, 0.78, 0.92)
const SKY_DARK_CLIMB := 9000.0    # climb (px) at which the sky is fully dark
const SNOW_START_CLIMB := 3200.0  # ~ height 40, where main.gd starts putting snow on ledges
const WIND := 25.0
const CLIFF_PARALLAX := 0.5
const STEP := 8.0                 # horizontal resolution of the mountain ridges

var camera: Camera2D

var _size := Vector2.ZERO
var _start_y := 0.0
var _noise := FastNoiseLite.new()
var _rock_tex: NoiseTexture2D
var _far := PackedFloat32Array()   # ridge heights above each layer's baseline
var _mid := PackedFloat32Array()
var _hills := PackedFloat32Array()
var _pines := PackedFloat32Array() # tree height per hill ridge point (0 = none)
var _clouds: Array[Dictionary] = []  # {pos, speed, scale}
var _stars := PackedVector2Array()
var _flakes := PackedVector3Array()  # x, y, z = depth (0 far .. 1 near)
var _time := 0.0
var _night := 0.0  # 0 day .. 1 night; dims mountains and cliffs


func _ready() -> void:
	_size = get_viewport_rect().size
	_start_y = camera.position.y
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_noise.seed = randi()
	_noise.frequency = 1.0
	_rock_tex = Block.noise_texture(0.025, 5, 0.5)

	_far = _ridge(0.0, 250.0, 0.006, true)
	_mid = _ridge(10.0, 170.0, 0.009, true)
	_hills = _ridge(20.0, 55.0, 0.012, false)
	for i in _hills.size():
		_pines.append(randf_range(9.0, 20.0) if randf() < 0.8 else 0.0)

	for i in 6:
		_clouds.append({
			"pos": Vector2(randf_range(0.0, _size.x + 200.0), randf_range(0.0, _size.y + 200.0)),
			"speed": randf_range(5.0, 14.0),
			"scale": randf_range(0.7, 1.4),
		})
	for i in 70:
		_stars.append(Vector2(randf() * _size.x, randf() * _size.y))
	for i in 120:
		_flakes.append(Vector3(randf() * _size.x, randf() * _size.y, randf()))


## Ridge heights across the screen; `peaky` uses ridged noise for sharp summits.
func _ridge(layer: float, amplitude: float, frequency: float, peaky: bool) -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	for i in int(_size.x / STEP) + 2:
		var x := i * STEP
		var n := _noise.get_noise_2d(x * frequency, layer)
		var detail := _noise.get_noise_2d(x * frequency * 5.0, layer + 3.0)
		var h := pow(1.0 - absf(n), 2.0) if peaky else 0.5 + 0.5 * n
		heights.append(amplitude * (0.25 + 0.75 * h) + amplitude * 0.025 * detail)
	return heights


## Cheap deterministic random in [0, 1) for things placed along the endless cliffs.
func _hash(n: int) -> float:
	return fposmod(sin(n * 12.9898) * 43758.5453, 1.0)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var climb := maxf(0.0, _start_y - camera.position.y)
	var night := clampf(climb / SKY_DARK_CLIMB, 0.0, 1.0)
	_night = night
	var snow := clampf((climb - SNOW_START_CLIMB) / 3000.0, 0.0, 1.0)
	var top := LOW_TOP.lerp(HIGH_TOP, night)
	var bottom := LOW_BOTTOM.lerp(HIGH_BOTTOM, night)
	draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(_size.x, 0), _size, Vector2(0, _size.y)]),
		PackedColorArray([top, top, bottom, bottom]))

	_draw_sun_and_moon(climb, night)

	var star_alpha := clampf((climb - 3500.0) / 4000.0, 0.0, 1.0)
	if star_alpha > 0.0:
		for star in _stars:
			var twinkle := 0.6 + 0.4 * sin(_time * 2.0 + star.x)
			draw_circle(Vector2(star.x, fposmod(star.y + climb * 0.02, _size.y)), 1.1, Color(1, 1, 1, star_alpha * twinkle))

	# Mountains sink below the screen as you climb past them; distant ones are hazier.
	_draw_range(_far, 600.0 + climb * 0.04, FAR_RANGE.lerp(bottom, 0.35), bottom, 150.0)
	_draw_clouds(climb, top, bottom)
	_draw_range(_mid, 640.0 + climb * 0.08, MID_RANGE.lerp(bottom, 0.2), bottom, 115.0)
	_draw_hills(650.0 + climb * 0.14, bottom, snow)
	_draw_cliffs(climb, bottom, snow)

	# Snowfall gets denser with height; nearer flakes are bigger, faster and sway more.
	for i in int(_flakes.size() * snow):
		var f := _flakes[i]
		var pos := Vector2(
			fposmod(f.x + _time * WIND * (0.5 + f.z) + sin(_time * 1.5 + f.y) * 8.0 * f.z, _size.x),
			fposmod(f.y + _time * (30.0 + 50.0 * f.z) + climb * (0.2 + 0.5 * f.z), _size.y))
		draw_circle(pos, 0.8 + 1.6 * f.z, Color(1, 1, 1, 0.5 + 0.4 * f.z))


func _draw_sun_and_moon(climb: float, night: float) -> void:
	# The sun sets behind the mountains (drawn after it) as night falls.
	var day := clampf(1.0 - night * 1.4, 0.0, 1.0)
	if day > 0.0:
		var sun := Vector2(_size.x * 0.74, 150.0 + climb * 0.015 + (1.0 - day) * 520.0)
		for i in range(6, 0, -1):
			draw_circle(sun, 22.0 + i * 13.0, Color(1.0, 0.95, 0.75, 0.05 * day))
		draw_circle(sun, 22.0, Color(1.0, 0.97, 0.86, day))
	var moon_alpha := clampf(night * 1.8 - 0.7, 0.0, 1.0)
	if moon_alpha > 0.0:
		var moon := Vector2(_size.x * 0.24, 120.0)
		for i in range(4, 0, -1):
			draw_circle(moon, 18.0 + i * 10.0, Color(0.8, 0.85, 1.0, 0.04 * moon_alpha))
		draw_circle(moon, 18.0, Color(0.92, 0.93, 0.88, moon_alpha))
		for crater in [Vector3(-5, -4, 4), Vector3(6, 3, 3), Vector3(-2, 7, 2.5)]:
			draw_circle(moon + Vector2(crater.x, crater.y), crater.z, Color(0.78, 0.79, 0.76, moon_alpha))


## A mountain range: rock fading into mist at its foot, sunlit slopes facing the
## top-left light, and snow above `snow_line` (shaded on the slopes facing away).
func _draw_range(heights: PackedFloat32Array, baseline: float, color: Color, haze: Color, snow_line: float) -> void:
	var ridge := PackedVector2Array()
	var highest := INF
	for i in heights.size():
		ridge.append(Vector2(i * STEP, baseline - heights[i]))
		highest = minf(highest, ridge[i].y)
	if highest > _size.y:
		return
	var floor_y := maxf(baseline, _size.y) + 1.0

	# Per-point light from the smoothed slope (rising to the right = faces the
	# top-left sun), so neighbouring segments blend instead of striping.
	var light := PackedFloat32Array()
	var snow_low := PackedVector2Array()
	for i in ridge.size():
		var rise := heights[mini(i + 6, heights.size() - 1)] - heights[maxi(i - 6, 0)]
		light.append(clampf(rise / 90.0, -1.0, 1.0))
		# Cap depth grows with how far the summit pokes above the snow line.
		var above := heights[i] - snow_line + 8.0 * _noise.get_noise_1d(ridge[i].x * 0.05)
		snow_low.append(ridge[i] + Vector2(0, clampf(above * 0.7, 0.0, 40.0)))

	color = color.lerp(haze, 0.4 * _night)
	var foot := color.lerp(haze, 0.65)
	var snow_tint := 0.2 + 0.5 * _night
	var none := PackedVector2Array()
	for i in ridge.size() - 1:
		var a := ridge[i]
		var b := ridge[i + 1]
		var top_a := color.lightened(0.18 * light[i]) if light[i] > 0.0 else color.darkened(-0.15 * light[i])
		var top_b := color.lightened(0.18 * light[i + 1]) if light[i + 1] > 0.0 else color.darkened(-0.15 * light[i + 1])
		var a_floor := Vector2(a.x, floor_y)
		var b_floor := Vector2(b.x, floor_y)
		draw_primitive(PackedVector2Array([a, b, b_floor]), PackedColorArray([top_a, top_b, foot]), none)
		draw_primitive(PackedVector2Array([a, b_floor, a_floor]), PackedColorArray([top_a, foot, foot]), none)

		if snow_low[i].y <= a.y and snow_low[i + 1].y <= b.y:
			continue
		# Snow cap fading out towards the snow line.
		var white_a := SNOW.lerp(SNOW_SHADE, 0.5 - 0.5 * light[i]).lerp(haze, snow_tint)
		var white_b := SNOW.lerp(SNOW_SHADE, 0.5 - 0.5 * light[i + 1]).lerp(haze, snow_tint)
		var fade_a := Color(white_a, 0.0)
		var fade_b := Color(white_b, 0.0)
		draw_primitive(PackedVector2Array([a, b, snow_low[i + 1]]), PackedColorArray([white_a, white_b, fade_b]), none)
		draw_primitive(PackedVector2Array([a, snow_low[i + 1], snow_low[i]]), PackedColorArray([white_a, fade_b, fade_a]), none)


func _draw_clouds(climb: float, top: Color, bottom: Color) -> void:
	# Faded by blending into the sky colour (opaque, so overlapping puffs stay clean).
	var fade := clampf((climb - 5000.0) / 3000.0, 0.0, 1.0)
	if fade >= 1.0:
		return
	var puffs := [Vector3(-24, 5, 13), Vector3(-8, -5, 17), Vector3(12, -3, 15), Vector3(28, 5, 11), Vector3(4, 6, 14)]
	for cloud in _clouds:
		var pos := Vector2(
			fposmod(cloud.pos.x + _time * cloud.speed, _size.x + 200.0) - 100.0,
			fposmod(cloud.pos.y + climb * 0.3, _size.y + 200.0) - 100.0)
		var sky := top.lerp(bottom, clampf(pos.y / _size.y, 0.0, 1.0))
		var dim := maxf(fade, _night * 0.6)
		var white := Color(0.98, 0.98, 1.0).lerp(sky, 0.1 + 0.9 * dim)
		var shadow := Color(0.78, 0.82, 0.9).lerp(sky, 0.3 + 0.7 * dim)
		var s: float = cloud.scale
		# Grey underside, white body, bright sunlit crowns.
		for puff in puffs:
			draw_circle(pos + Vector2(puff.x, puff.y + 4.0) * s, puff.z * s, shadow)
		for puff in puffs:
			draw_circle(pos + Vector2(puff.x, puff.y) * s, puff.z * 0.92 * s, white)
		for puff in puffs:
			draw_circle(pos + Vector2(puff.x - 3.0, puff.y - 4.0) * s, puff.z * 0.5 * s, white.lightened(0.5))


func _draw_hills(baseline: float, haze: Color, snow: float) -> void:
	var color := HILLS.lerp(haze, 0.15).lerp(SNOW_SHADE, snow * 0.5)
	var pine := PINE.lerp(haze, 0.15)
	var ridge := PackedVector2Array()
	for i in _hills.size():
		ridge.append(Vector2(i * STEP, baseline - _hills[i]))
	if ridge[0].y - 60.0 > _size.y and baseline - 80.0 > _size.y:
		return
	var poly := ridge.duplicate()
	var floor_y := maxf(baseline, _size.y) + 1.0
	poly.append(Vector2(ridge[ridge.size() - 1].x, floor_y))
	poly.append(Vector2(0, floor_y))
	draw_colored_polygon(poly, color)
	for i in ridge.size():
		if _pines[i] > 0.0:
			_draw_pine(ridge[i] + Vector2(fmod(i * 3.7, 4.0), 3.0), _pines[i], pine, snow)


func _draw_pine(root: Vector2, height: float, color: Color, snow: float) -> void:
	var w := height * 0.32
	draw_line(root, root + Vector2(0, -height * 0.2), color.darkened(0.3), maxf(1.0, w * 0.25))
	for tier in 3:
		var base_y := root.y - height * (0.15 + tier * 0.25)
		var tier_w := w * (1.0 - tier * 0.25)
		var tip := Vector2(root.x, base_y - height * 0.45)
		draw_colored_polygon(PackedVector2Array([Vector2(root.x - tier_w, base_y), Vector2(root.x + tier_w, base_y), tip]), color.lightened(tier * 0.04))
		if snow > 0.0:
			var cap := Color(SNOW, snow)
			draw_colored_polygon(PackedVector2Array([tip.lerp(Vector2(root.x - tier_w, base_y), 0.35), tip.lerp(Vector2(root.x + tier_w, base_y), 0.35), tip]), cap)


## Endless rock walls on both screen edges, textured with noise, with pines on ledges.
func _draw_cliffs(climb: float, haze: Color, snow: float) -> void:
	var scroll := climb * CLIFF_PARALLAX
	var color := CLIFF.lerp(haze, 0.25 + 0.35 * _night)
	var pine := PINE.lerp(haze, 0.1)
	for side in [0, 1]:
		var poly := PackedVector2Array()
		var colors := PackedColorArray()
		var uvs := PackedVector2Array()
		var edge := PackedVector2Array()
		var outer_x := -2.0 if side == 0 else _size.x + 2.0
		poly.append(Vector2(outer_x, -24.0))
		var y := -24.0
		while y <= _size.y + 24.0:
			var x := _cliff_width(y - scroll, side)
			edge.append(Vector2(x if side == 0 else _size.x - x, y))
			y += 12.0
		poly.append_array(edge)
		poly.append(Vector2(outer_x, edge[edge.size() - 1].y))
		for p in poly:
			var inner := p.x != outer_x
			colors.append(color if inner else color.darkened(0.45))
			uvs.append(Vector2(p.x, p.y - scroll) / 160.0)
		draw_polygon(poly, colors, uvs, _rock_tex)
		draw_polyline(edge, color.darkened(0.5), 2.0, true)
		if snow > 0.0:
			# Snow clinging to the cliff edge.
			for i in range(0, edge.size(), 2):
				draw_circle(edge[i], 3.0 + 2.0 * _hash(i + int(scroll / 12.0)), Color(SNOW, snow * 0.9))

	# Pines on ledges, one slot every 110 px of cliff.
	var first := floori((-scroll - 60.0) / 110.0)
	var last := ceili((_size.y - scroll + 60.0) / 110.0)
	for n in range(first, last + 1):
		if _hash(n) < 0.35:
			continue
		var side := 0 if _hash(n * 3 + 1) < 0.5 else 1
		var v := n * 110.0 + _hash(n * 7 + 2) * 50.0
		var x := _cliff_width(v, side) - 3.0
		var root := Vector2(x if side == 0 else _size.x - x, v + scroll)
		var dir := 1.0 if side == 0 else -1.0
		draw_line(root - Vector2(dir * 6.0, 0), root + Vector2(dir * 5.0, 1.0), color.darkened(0.55), 3.0)
		_draw_pine(root, 18.0 + _hash(n * 5 + 3) * 16.0, pine, snow)


func _cliff_width(v: float, side: int) -> float:
	var broad := _noise.get_noise_2d(v * 0.004, 50.0 + side * 40.0)
	var detail := _noise.get_noise_2d(v * 0.03, 60.0 + side * 40.0)
	return maxf(14.0, 44.0 + 34.0 * broad + 9.0 * detail)
