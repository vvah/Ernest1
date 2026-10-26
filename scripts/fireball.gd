extends Area2D
## Fireball spat by a dragon. Flies in a straight line through blocks; hitting
## the player burns (damage + sets them alight) and bursts into sparks.
## Set `velocity` and `camera` before adding.

const RADIUS := 7.0
const DAMAGE := 18.0

var velocity := Vector2.ZERO
var camera: Camera2D
var _time := 0.0


func _ready() -> void:
	var shape := CircleShape2D.new()
	shape.radius = RADIUS * 0.8
	var collision := CollisionShape2D.new()
	collision.shape = shape
	add_child(collision)
	body_entered.connect(_on_body_entered)

	# Embers left behind in world space.
	var embers := CPUParticles2D.new()
	embers.amount = 16
	embers.lifetime = 0.35
	embers.local_coords = false
	embers.spread = 180.0
	embers.initial_velocity_max = 25.0
	embers.gravity = Vector2(0, -40)
	embers.scale_amount_min = 1.5
	embers.scale_amount_max = 3.5
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 1.0])
	fade.colors = PackedColorArray([Color(1.0, 0.75, 0.2), Color(0.8, 0.1, 0.0, 0.0)])
	embers.color_ramp = fade
	add_child(embers)


func _physics_process(delta: float) -> void:
	_time += delta
	position += velocity * delta
	if position.distance_to(camera.position) > 900.0:
		queue_free()
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player") or is_queued_for_deletion():
		return
	body.take_damage(DAMAGE, global_position, "Verbrannt!")
	body.ignite()
	_burst()
	queue_free()


## Shower of sparks left behind where the fireball hit.
func _burst() -> void:
	var sparks := CPUParticles2D.new()
	sparks.position = position
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.amount = 24
	sparks.lifetime = 0.5
	sparks.spread = 180.0
	sparks.initial_velocity_min = 60.0
	sparks.initial_velocity_max = 200.0
	sparks.gravity = Vector2(0, 300)
	sparks.scale_amount_min = 1.5
	sparks.scale_amount_max = 4.0
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 1.0])
	fade.colors = PackedColorArray([Color(1.0, 0.9, 0.4), Color(0.7, 0.1, 0.0, 0.0)])
	sparks.color_ramp = fade
	sparks.finished.connect(sparks.queue_free)
	get_parent().add_child.call_deferred(sparks)
	sparks.set_deferred("emitting", true)


func _draw() -> void:
	var flicker := sin(_time * 40.0) * 1.2
	draw_circle(Vector2.ZERO, RADIUS + 4.0 + flicker, Color(1.0, 0.35, 0.0, 0.3))
	draw_circle(Vector2.ZERO, RADIUS + flicker * 0.5, Color(1.0, 0.45, 0.05))
	draw_circle(Vector2.ZERO, RADIUS * 0.55, Color(1.0, 0.85, 0.35))
