extends StaticBody2D
## A one-way rock ledge: the player can jump up through it and land on top.
## Set `size`, `color` (and `ground` for the floor) before adding to the tree.
## The rough underside, cracks and moss are only drawn; the collision stays a rectangle.

const MOSS := Color(0.32, 0.48, 0.2)
const GRASS := Color(0.3, 0.55, 0.2)
const DIRT := Color(0.38, 0.27, 0.17)
const SNOW := Color(0.94, 0.96, 1.0)
const ICE := Color(0.75, 0.88, 0.98, 0.9)
const GROUND_DEPTH := 600.0  # dirt drawn below the ground so no sky shows under it

var size := Vector2(100, 20)
var color := Color(0.5, 0.47, 0.43)
var ground := false
var snowy := false  # high up: snow cap and icicles instead of moss

var _outline := PackedVector2Array()
var _spots: Array[Dictionary] = []  # {pos, r, color}
var _cracks: Array[PackedVector2Array] = []
var _tufts := PackedVector2Array()  # x = position, y = blade height
var _mossy := true


func _ready() -> void:
	var shape := RectangleShape2D.new()
	shape.size = size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.one_way_collision = true
	add_child(collision)

	if ground:
		color = DIRT
	_build_look()


func _build_look() -> void:
	var half := size / 2.0
	_mossy = ground or snowy or randf() < 0.7

	if ground:
		_outline = PackedVector2Array([
			Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
			Vector2(half.x, GROUND_DEPTH), Vector2(-half.x, GROUND_DEPTH)])
		for i in 70:
			var stone := randf() < 0.3
			_spots.append({
				"pos": Vector2(randf_range(-half.x, half.x), randf_range(half.y, 220.0)),
				"r": randf_range(2.0, 5.0) if stone else randf_range(1.0, 2.5),
				"color": Color(0.5, 0.48, 0.45) if stone else DIRT.darkened(randf_range(0.1, 0.3)),
			})
	else:
		# Flat top (you stand on it), rough rocky underside.
		_outline.append(Vector2(-half.x, -half.y))
		_outline.append(Vector2(half.x, -half.y))
		var steps := maxi(3, int(size.x / 12.0))
		for i in steps + 1:
			var x := lerpf(half.x, -half.x, float(i) / steps)
			var y := half.y + randf_range(-2.0, 7.0)
			if i == 0 or i == steps:
				x -= signf(x) * 3.0
				y = half.y - 2.0
			_outline.append(Vector2(x, y))

		for i in int(size.x * size.y / 140.0):
			_spots.append({
				"pos": Vector2(randf_range(-half.x + 4.0, half.x - 4.0), randf_range(-half.y + 4.0, half.y - 2.0)),
				"r": randf_range(0.8, 2.2),
				"color": color.lightened(0.2) if randf() < 0.5 else color.darkened(0.3),
			})
		for i in 1 + int(size.x / 60.0):
			var start := Vector2(randf_range(-half.x + 6.0, half.x - 6.0), half.y - 1.0)
			var mid := start + Vector2(randf_range(-4.0, 4.0), -randf_range(4.0, 8.0))
			_cracks.append(PackedVector2Array([start, mid, mid + Vector2(randf_range(-5.0, 5.0), -randf_range(2.0, 5.0))]))

	if _mossy:
		var x := -half.x + randf_range(0.0, 3.0)
		while x < half.x:
			_tufts.append(Vector2(x, randf_range(1.5, 6.0 if ground else 4.0)))
			x += randf_range(2.5, 6.0)


func _draw() -> void:
	var half := size / 2.0
	draw_colored_polygon(_outline, color.darkened(0.25))
	if not ground:
		# Lit upper face, shaded underside.
		draw_rect(Rect2(-half.x, -half.y, size.x, size.y * 0.55), color)
	for spot in _spots:
		draw_circle(spot.pos, spot.r, spot.color)
	for crack in _cracks:
		draw_polyline(crack, color.darkened(0.55), 1.0)
	var closed := _outline.duplicate()
	closed.append(_outline[0])
	draw_polyline(closed, color.darkened(0.55), 1.5)

	if not _mossy:
		draw_rect(Rect2(-half.x, -half.y, size.x, 2.5), color.lightened(0.25))
		return
	if snowy:
		for i in range(0, _tufts.size(), 4):
			# Hang from the rough underside (skip the two top corners and the end points).
			var tip := _outline[3 + (i * 7) % (_outline.size() - 4)]
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-1.5, -1), tip + Vector2(1.5, -1), tip + Vector2(0, _tufts[i].y + 2.0)]), ICE)
		draw_rect(Rect2(-half.x, -half.y - 2.0, size.x, 5.0), SNOW.darkened(0.08))
		for tuft in _tufts:
			draw_circle(Vector2(tuft.x, -half.y - 1.5), 1.2 + tuft.y * 0.35, SNOW)
		return
	var green := GRASS if ground else MOSS
	draw_rect(Rect2(-half.x, -half.y - 1.0, size.x, 7.0 if ground else 3.5), green)
	for tuft in _tufts:
		var base := Vector2(tuft.x, -half.y)
		draw_line(base, base + Vector2(tuft.y * 0.35, -tuft.y), green.lightened(0.12), 1.5)
