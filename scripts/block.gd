extends StaticBody2D
## A one-way platform: the player can jump up through it and land on top.
## Set `size` and `color` before adding to the tree.

var size := Vector2(100, 20)
var color := Color(0.6, 0.4, 0.25)


func _ready() -> void:
	var shape := RectangleShape2D.new()
	shape.size = size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.one_way_collision = true
	add_child(collision)


func _draw() -> void:
	var rect := Rect2(-size / 2.0, size)
	draw_rect(rect, color)
	draw_rect(Rect2(rect.position, Vector2(size.x, 4)), color.lightened(0.35))
	draw_rect(rect, color.darkened(0.45), false, 2.0)
