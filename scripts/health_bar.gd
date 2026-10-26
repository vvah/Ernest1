extends Node2D
## HUD health bar (main.gd puts it on the HUD layer and sets `health` each frame).
## Recent damage stays visible as a pale segment that drains after a short delay;
## the heart beats faster the lower the health. Icons below the bar show the
## player's conditions (main.gd sets the flags): bleeding, burning, dazed, sprained.

const WIDTH := 150.0
const HEIGHT := 14.0
const MAX_HEALTH := 100.0
const DRAIN_DELAY := 0.45
const DRAIN_SPEED := 45.0

var health := MAX_HEALTH
var bleeding := false
var burning := false
var dazed := false
var sprained := false

var _shown := MAX_HEALTH  # lagging value for the damage segment
var _delay := 0.0
var _last := MAX_HEALTH
var _beat := 0.0


func _process(delta: float) -> void:
	if health < _last:
		_delay = DRAIN_DELAY
	elif health > _shown:
		_shown = health  # healing fills immediately
	_last = health
	if _delay > 0.0:
		_delay -= delta
	else:
		_shown = move_toward(_shown, health, DRAIN_SPEED * delta)
	_beat += delta * lerpf(1.2, 3.2, 1.0 - health / MAX_HEALTH)
	queue_redraw()


func _draw() -> void:
	var frac := health / MAX_HEALTH
	var bar := Rect2(22, 0, WIDTH, HEIGHT)
	draw_rect(bar.grow(2.0), Color(0, 0, 0, 0.55))
	draw_rect(bar, Color(0.18, 0.05, 0.05))
	draw_rect(Rect2(bar.position, Vector2(WIDTH * _shown / MAX_HEALTH, HEIGHT)), Color(1.0, 0.85, 0.7))
	var fill := Color(0.85, 0.12, 0.1).lerp(Color(0.95, 0.8, 0.15), clampf(frac * 2.0, 0.0, 1.0))
	fill = fill.lerp(Color(0.25, 0.75, 0.25), clampf(frac * 2.0 - 1.0, 0.0, 1.0))
	draw_rect(Rect2(bar.position, Vector2(WIDTH * frac, HEIGHT)), fill)
	draw_rect(Rect2(bar.position, Vector2(WIDTH * frac, 4.0)), Color(1, 1, 1, 0.25))  # shine
	for i in range(1, 4):
		var x := bar.position.x + WIDTH * i / 4.0
		draw_line(Vector2(x, 1), Vector2(x, HEIGHT - 1), Color(0, 0, 0, 0.3), 1.0)

	# Heart: a quick double thump each beat.
	var phase := fmod(_beat, 1.0)
	var thump := maxf(0.0, 1.0 - absf(phase - 0.1) * 12.0) + 0.6 * maxf(0.0, 1.0 - absf(phase - 0.3) * 12.0)
	var s := 1.0 + 0.18 * thump
	var center := Vector2(9, HEIGHT / 2.0)
	var red := Color(0.9, 0.12, 0.15)
	draw_circle(center + Vector2(-3.2, -1.5) * s, 4.0 * s, red)
	draw_circle(center + Vector2(3.2, -1.5) * s, 4.0 * s, red)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-7.0, 0.0) * s, center + Vector2(7.0, 0.0) * s, center + Vector2(0, 7.5) * s]), red)
	draw_circle(center + Vector2(-3.5, -2.8) * s, 1.3 * s, Color(1, 1, 1, 0.5))
	_draw_conditions()


## One small icon per active condition, in a row under the bar.
func _draw_conditions() -> void:
	var x := 30.0
	var y := HEIGHT + 14.0
	var t := Time.get_ticks_msec() / 1000.0
	if bleeding:
		var pulse := 1.0 + 0.15 * sin(t * 8.0)
		var c := Vector2(x, y + 2.0)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8) * pulse, c + Vector2(-4, -1) * pulse, c + Vector2(4, -1) * pulse]), Color(0.85, 0.05, 0.08))
		draw_circle(c, 4.3 * pulse, Color(0.85, 0.05, 0.08))
		draw_circle(c + Vector2(-1.5, -1.5), 1.2, Color(1, 1, 1, 0.5))
		x += 18.0
	if burning:
		for i in 3:
			var h := 9.0 + 3.0 * sin(t * 20.0 + i * 2.0)
			var bx := x - 4.0 + i * 4.0
			draw_colored_polygon(PackedVector2Array([Vector2(bx - 2.5, y + 5), Vector2(bx + 2.5, y + 5), Vector2(bx, y + 5 - h)]), Color(1.0, 0.45 + i * 0.15, 0.05))
		x += 18.0
	if dazed:
		# Stars circling.
		for i in 3:
			var a := t * 4.0 + TAU * i / 3.0
			var p := Vector2(x, y) + Vector2(cos(a) * 6.0, sin(a) * 2.5)
			draw_circle(p, 1.8, Color(1.0, 0.9, 0.3))
		x += 18.0
	if sprained:
		# A bone with a crack.
		draw_line(Vector2(x - 6, y + 3), Vector2(x + 6, y - 3), Color(0.95, 0.93, 0.85), 2.5)
		for end in [Vector2(x - 6, y + 3), Vector2(x + 6, y - 3)]:
			draw_circle(end + Vector2(-1, -1), 1.7, Color(0.95, 0.93, 0.85))
			draw_circle(end + Vector2(1, 1), 1.7, Color(0.95, 0.93, 0.85))
		draw_polyline(PackedVector2Array([Vector2(x - 1, y - 3), Vector2(x + 1, y), Vector2(x - 1, y + 3)]), Color(0.85, 0.1, 0.1), 1.2)
