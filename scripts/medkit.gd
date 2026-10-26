extends Area2D
## First-aid kit lying on a block (spawned by main.gd as the block's child, so it
## is freed with it). Origin is at its bottom. Heals the player on touch, unless
## they are already at full health, in which case it stays for later.

const Player := preload("res://scripts/player.gd")

const HEAL := 35.0
const SIZE := Vector2(16, 12)

var _time := 0.0
var _taken := false


func _ready() -> void:
	_time = randf() * TAU
	var shape := RectangleShape2D.new()
	shape.size = SIZE + Vector2(6, 6)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(0, -SIZE.y / 2.0)
	add_child(collision)
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_time += delta
	if not _taken:
		for body in get_overlapping_bodies():
			_on_body_entered(body)
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if _taken or not body.is_in_group("player") or body.health >= Player.MAX_HEALTH:
		return
	_taken = true
	body.heal(HEAL)
	set_deferred("monitoring", false)
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "position:y", position.y - 24.0, 0.35)
	tween.tween_property(self, "modulate:a", 0.0, 0.35)
	tween.chain().tween_callback(queue_free)


func _draw() -> void:
	var lift := sin(_time * 2.0) * 1.0
	var box := Rect2(-SIZE.x / 2.0, -SIZE.y + lift, SIZE.x, SIZE.y)
	# Contact shadow, handle, case with a darker lid seam, red cross, glint.
	draw_circle(Vector2(0, 0.5), SIZE.x * 0.45, Color(0, 0, 0, 0.18))
	draw_arc(Vector2(0, box.position.y), 3.0, PI, TAU, 8, Color(0.55, 0.55, 0.55), 1.5)
	draw_rect(box, Color(0.95, 0.95, 0.93))
	draw_rect(Rect2(box.position + Vector2(0, box.size.y - 3.0), Vector2(box.size.x, 3.0)), Color(0.8, 0.8, 0.78))
	draw_rect(box, Color(0.45, 0.45, 0.45), false, 1.0)
	var c := box.get_center() + Vector2(0, -0.5)
	draw_rect(Rect2(c - Vector2(1.5, 4.0), Vector2(3.0, 8.0)), Color(0.85, 0.1, 0.1))
	draw_rect(Rect2(c - Vector2(4.0, 1.5), Vector2(8.0, 3.0)), Color(0.85, 0.1, 0.1))
	var glint := fposmod(_time * 0.6, 3.0)
	if glint < 1.0:
		var x := lerpf(box.position.x, box.end.x, glint)
		draw_line(Vector2(x, box.position.y + 1.0), Vector2(x - 3.0, box.end.y - 1.0), Color(1, 1, 1, 0.7), 1.5)
