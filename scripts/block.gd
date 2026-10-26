extends StaticBody2D
## A one-way rock ledge: the player can jump up through it and land on top.
## Set `size`, `color` (and `ground` / `snowy`) before adding to the tree.
## The rock shape hangs below the collision box and is only drawn; the collision
## stays a rectangle. Surfaces use noise textures generated in code (no image files).

const MOSS := Color(0.3, 0.47, 0.18)
const GRASS := Color(0.3, 0.55, 0.2)
const DIRT := Color(0.55, 0.4, 0.27)
const SNOW := Color(0.94, 0.96, 1.0)
const ICE := Color(0.75, 0.88, 0.98, 0.9)
const GROUND_DEPTH := 600.0  # dirt drawn below the ground so no sky shows under it
const UV_SCALE := 1.0 / 192.0
const FRESH_BLOOD := Color(0.62, 0.02, 0.04, 0.95)
const DRIED_BLOOD := Color(0.3, 0.06, 0.04, 0.9)
const DRY_TIME := 8.0      # seconds for a blood stain to darken fully
const MAX_STAINS := 24

static var _stone_tex: NoiseTexture2D
static var _dirt_tex: NoiseTexture2D

var size := Vector2(100, 20)
var color := Color(0.65, 0.62, 0.58)
var ground := false
var snowy := false  # high up: snow cap and icicles instead of moss
var fragile := false  # cracked ledge: breaks on the second landing (see crack())

signal broken

var _collision: CollisionShape2D
var _hits := 0
var _wobble := 0.0  # seconds of shaking left after a landing
var _fault_lines: Array[PackedVector2Array] = []  # big cracks of a fragile ledge

var _outline := PackedVector2Array()
var _shade := PackedColorArray()
var _uvs := PackedVector2Array()
var _bottom_first := 0  # index range of the underside points in _outline
var _bottom_last := 0
var _pebbles: Array[PackedVector2Array] = []
var _cracks: Array[PackedVector2Array] = []
var _tufts := PackedVector2Array()  # x = position, y = size
var _vines := PackedVector2Array()  # x = position, y = length
var _mossy := true
var _stains: Array[Dictionary] = []  # {x, r, born, drip, dots}: blood on the top surface


## Grey grain multiplied with the vertex colours, so one texture serves every rock tone.
static func noise_texture(frequency: float, octaves: int, dark: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	noise.seed = randi()
	var ramp := Gradient.new()
	ramp.set_color(0, Color(dark, dark, dark))
	ramp.set_color(1, Color.WHITE)
	ramp.add_point(0.5, Color(0.86, 0.86, 0.86))
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = ramp
	return tex


func _ready() -> void:
	var shape := RectangleShape2D.new()
	shape.size = size
	_collision = CollisionShape2D.new()
	_collision.shape = shape
	_collision.one_way_collision = true
	add_child(_collision)
	add_to_group("blocks")  # found by blood drops and the ragdoll (see top_y())
	set_process(false)

	if _stone_tex == null:
		_stone_tex = noise_texture(0.035, 5, 0.55)
		_dirt_tex = noise_texture(0.06, 4, 0.6)
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	if ground:
		color = DIRT
	if fragile:
		color = color.lerp(Color(0.78, 0.62, 0.45), 0.35)  # crumbly sandstone tint
		for i in 2:
			_add_fault_line()
	_build_look()


## Called when the player lands on this ledge. Fragile ledges crack on the first
## landing and break on the second.
func crack() -> void:
	if not fragile or _hits >= 2:
		return
	_hits += 1
	if _hits == 1:
		_wobble = 0.3
		for i in 2:
			_add_fault_line()
		set_process(true)
		queue_redraw()
	else:
		_break()


func _process(delta: float) -> void:
	_wobble = maxf(0.0, _wobble - delta)
	var drying := false
	for stain in _stains:
		drying = drying or _stain_age(stain) < DRY_TIME
	if _wobble == 0.0 and not drying:
		set_process(false)
	queue_redraw()


## World y of the walkable top surface.
func top_y() -> float:
	return global_position.y - size.y / 2.0


## True if world x lies over this ledge's top surface.
func covers_x(x: float) -> bool:
	return absf(x - global_position.x) <= size.x / 2.0


## Blood landing on the top surface at world x. Nearby drops pool together;
## stains near an edge run down the side.
func add_stain(world_x: float, amount: float) -> void:
	var half := size / 2.0
	var x := clampf(world_x - global_position.x, -half.x + 1.0, half.x - 1.0)
	for stain in _stains:
		if absf(stain.x - x) < stain.r + 1.5:
			stain.r = minf(stain.r + amount * 0.35, 9.0)
			stain.born = Time.get_ticks_msec()  # fresh blood on top
			if absf(x) > half.x - 5.0:
				stain.drip = minf(stain.drip + 2.0, size.y + 10.0)
			set_process(true)
			queue_redraw()
			return
	if _stains.size() >= MAX_STAINS:
		_stains.pop_front()
	var dots := PackedVector2Array()
	for i in randi_range(1, 3):
		dots.append(Vector2(x + randf_range(-6.0, 6.0), randf_range(0.4, 1.0)))
	_stains.append({
		"x": x, "r": 1.2 + amount * 0.5, "born": Time.get_ticks_msec(),
		"drip": randf_range(3.0, 7.0) if absf(x) > half.x - 5.0 else 0.0, "dots": dots,
	})
	set_process(true)
	queue_redraw()


func _stain_age(stain: Dictionary) -> float:
	return (Time.get_ticks_msec() - stain.born) / 1000.0


## A zigzag crack from the top surface down through the rock.
func _add_fault_line() -> void:
	var half := size / 2.0
	var p := Vector2(randf_range(-half.x * 0.7, half.x * 0.7), -half.y)
	var line := PackedVector2Array([p])
	for i in 4:
		p += Vector2(randf_range(-6.0, 6.0), (size.y + 10.0) / 4.0)
		line.append(p)
	_fault_lines.append(line)


func _break() -> void:
	_collision.set_deferred("disabled", true)
	var debris := CPUParticles2D.new()
	debris.position = position
	debris.one_shot = true
	debris.explosiveness = 1.0
	debris.amount = maxi(8, int(size.x / 5.0))
	debris.lifetime = 1.3
	debris.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	debris.emission_rect_extents = size / 2.0
	debris.direction = Vector2.UP
	debris.spread = 70.0
	debris.initial_velocity_min = 40.0
	debris.initial_velocity_max = 150.0
	debris.gravity = Vector2(0, 900)
	debris.angular_velocity_min = -360.0
	debris.angular_velocity_max = 360.0
	debris.scale_amount_min = 3.0
	debris.scale_amount_max = 8.0
	debris.color = color
	debris.finished.connect(debris.queue_free)
	get_parent().add_child(debris)
	debris.emitting = true
	broken.emit()
	queue_free()


func _build_look() -> void:
	var half := size / 2.0
	_mossy = ground or snowy or randf() < 0.75

	if ground:
		_outline = PackedVector2Array([
			Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
			Vector2(half.x, GROUND_DEPTH), Vector2(-half.x, GROUND_DEPTH)])
		# Stones embedded in the soil.
		for i in 14:
			_pebbles.append(_lumpy(Vector2(randf_range(-half.x, half.x), randf_range(half.y + 8.0, 260.0)), randf_range(4.0, 11.0), 0.6))
	else:
		# Flat top (you stand on it), rounded shoulders, then a lumpy underside
		# that hangs deepest in the middle like a boulder.
		var depth := half.y + randf_range(7.0, 13.0)
		_outline.append(Vector2(-half.x + 4.0, -half.y))
		_outline.append(Vector2(half.x - 4.0, -half.y))
		_outline.append(Vector2(half.x - 1.0, -half.y + 2.0))
		_outline.append(Vector2(half.x, -half.y + 6.0))
		var steps := maxi(4, int(size.x / 12.0))
		_bottom_first = _outline.size()
		for i in steps + 1:
			var f := float(i) / steps
			var sag := sin(f * PI)
			var x := lerpf(half.x - 1.5, -half.x + 1.5, f) * (1.0 - 0.12 * sag)
			_outline.append(Vector2(x, half.y - 3.0 + sag * (depth - half.y + 3.0) + randf_range(-2.0, 2.5)))
		_bottom_last = _outline.size() - 1
		_outline.append(Vector2(-half.x, -half.y + 6.0))
		_outline.append(Vector2(-half.x + 1.0, -half.y + 2.0))

		for i in 1 + int(size.x / 45.0):
			var start := _outline[randi_range(_bottom_first + 1, _bottom_last - 1)]
			var mid := start + Vector2(randf_range(-4.0, 4.0), -randf_range(5.0, 10.0))
			_cracks.append(PackedVector2Array([start, mid, mid + Vector2(randf_range(-6.0, 6.0), -randf_range(2.0, 6.0))]))

	# Lit from above: bright top, dark underside.
	var bottom_y := GROUND_DEPTH * 0.4 if ground else half.y + 12.0
	for p in _outline:
		var t := clampf(inverse_lerp(-half.y, bottom_y, p.y), 0.0, 1.0)
		_shade.append(color.lightened(0.12).lerp(color.darkened(0.55), t * t * 0.6 + t * 0.4))
		_uvs.append((p + position) * UV_SCALE)

	if _mossy:
		var x := -half.x + randf_range(0.0, 3.0)
		while x < half.x:
			_tufts.append(Vector2(x, randf_range(1.5, 6.0 if ground else 4.5)))
			x += randf_range(2.5, 5.5)
		if not ground and not snowy:
			for i in randi_range(1, 3):
				_vines.append(Vector2(randf_range(-half.x + 3.0, half.x - 3.0), randf_range(5.0, 14.0)))


## Irregular roundish stone outline.
func _lumpy(center: Vector2, radius: float, flatten: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 9:
		var dir := Vector2.from_angle(TAU * i / 9.0) * radius * randf_range(0.8, 1.1)
		points.append(center + Vector2(dir.x, dir.y * flatten))
	return points


func _draw() -> void:
	var half := size / 2.0
	if _wobble > 0.0:
		draw_set_transform(Vector2(sin(_wobble * 90.0) * 2.0, 0.0))
	draw_polygon(_outline, _shade, _uvs, _dirt_tex if ground else _stone_tex)

	for pebble in _pebbles:
		var uvs := PackedVector2Array()
		var shade := PackedColorArray()
		var top := pebble[0].y
		for p in pebble:
			top = minf(top, p.y)
		for p in pebble:
			uvs.append((p + position) * UV_SCALE)
			shade.append(Color(0.75, 0.72, 0.68).lerp(Color(0.35, 0.33, 0.3), clampf((p.y - top) / 12.0, 0.0, 1.0)))
		draw_polygon(pebble, shade, uvs, _stone_tex)

	if not ground:
		for crack in _cracks:
			draw_polyline(crack, color.darkened(0.65), 1.0)
		for line in _fault_lines:
			draw_polyline(line, color.darkened(0.8), 2.0)
		var closed := _outline.duplicate()
		closed.append(_outline[0])
		draw_polyline(closed, color.darkened(0.7), 1.5, true)
		# Sunlit top edge.
		draw_line(Vector2(-half.x + 3.0, -half.y + 1.0), Vector2(half.x - 3.0, -half.y + 1.0), Color(1, 1, 0.95, 0.35), 2.0)

	if _mossy:
		if snowy:
			_draw_snow(half)
		else:
			_draw_moss(half)
	_draw_stains(half)


## Blood soaking into the top surface: a flattened pool, spatter dots and,
## at the edges, a trickle down the side. Fresh blood is bright and darkens as it dries.
func _draw_stains(half: Vector2) -> void:
	for stain in _stains:
		var dry := clampf(_stain_age(stain) / DRY_TIME, 0.0, 1.0)
		var c := FRESH_BLOOD.lerp(DRIED_BLOOD, dry)
		var center := Vector2(stain.x, -half.y + 0.5)
		var pool := PackedVector2Array()
		for i in 12:
			var a := TAU * i / 12.0
			pool.append(center + Vector2(cos(a) * stain.r, sin(a) * stain.r * 0.32))
		draw_colored_polygon(pool, c)
		draw_circle(center + Vector2(-stain.r * 0.3, -0.3), stain.r * 0.2, Color(1, 0.6, 0.6, 0.3 * (1.0 - dry)))  # wet sheen, gone once dry
		for dot in stain.dots:
			draw_circle(Vector2(dot.x, -half.y + 0.5), dot.y, c)
		if stain.drip > 0.0:
			var side := signf(stain.x) * (half.x - 0.5)
			var top := Vector2(side, -half.y + 1.0)
			draw_line(top, top + Vector2(0, stain.drip), c, 1.6)
			draw_circle(top + Vector2(0, stain.drip), 1.3, c)


func _draw_moss(half: Vector2) -> void:
	var green := GRASS if ground else MOSS
	var band := 7.0 if ground else 3.0
	for vine in _vines:
		var top := Vector2(vine.x, -half.y)
		draw_line(top, top + Vector2(1.5, vine.y), green.darkened(0.25), 1.5)
		draw_circle(top + Vector2(1.5, vine.y), 1.4, green.darkened(0.1))
	draw_rect(Rect2(-half.x, -half.y - 1.0, size.x, band), green.darkened(0.15))
	for i in _tufts.size():
		var tuft := _tufts[i]
		var base := Vector2(tuft.x, -half.y)
		# Moss cushions spilling over the edge, grass blades on top.
		draw_circle(base + Vector2(0, band * 0.6), 1.2 + tuft.y * 0.3, green.darkened(0.25 if i % 3 == 0 else 0.05))
		draw_line(base, base + Vector2(tuft.y * 0.35, -tuft.y), green.lightened(0.15 if i % 2 == 0 else 0.0), 1.5)


func _draw_snow(half: Vector2) -> void:
	for i in range(0, _tufts.size(), 4):
		var tip := _outline[_bottom_first + 1 + (i * 7) % (_bottom_last - _bottom_first - 1)]
		draw_colored_polygon(PackedVector2Array([tip + Vector2(-1.5, -2), tip + Vector2(1.5, -2), tip + Vector2(0, _tufts[i].y + 3.0)]), ICE)
	draw_rect(Rect2(-half.x, -half.y - 2.0, size.x, 5.0), SNOW.darkened(0.12))
	for tuft in _tufts:
		draw_circle(Vector2(tuft.x, -half.y - 1.5), 1.2 + tuft.y * 0.35, SNOW)
