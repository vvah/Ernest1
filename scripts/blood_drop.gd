extends Node2D
## A single drop of blood falling under gravity. When it crosses the top surface
## of a block (group "blocks") it leaves a stain there; otherwise it falls away
## and frees itself. Set `velocity` (and optionally `amount`) before adding.

const GRAVITY := 900.0
const COLOR := Color(0.6, 0.02, 0.04)

var velocity := Vector2.ZERO
var amount := 1.0  # stain size contribution
var _life := 0.0


func _physics_process(delta: float) -> void:
	_life += delta
	var before := global_position
	velocity.y += GRAVITY * delta
	global_position += velocity * delta
	if velocity.y > 0.0:
		for block in get_tree().get_nodes_in_group("blocks"):
			var top: float = block.top_y()
			if before.y <= top and global_position.y >= top and block.covers_x(global_position.x):
				block.add_stain(global_position.x, amount)
				queue_free()
				return
	if _life > 3.0:
		queue_free()
	queue_redraw()


func _draw() -> void:
	# Stretched along its motion like a real falling drop.
	var stretch := clampf(velocity.length() / 300.0, 1.0, 3.0)
	var dir := velocity.normalized() if velocity.length() > 1.0 else Vector2.DOWN
	draw_line(-dir * stretch * 1.2, Vector2.ZERO, COLOR, 1.6)
	draw_circle(Vector2.ZERO, 1.2, COLOR)
