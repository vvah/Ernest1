extends Node2D
## Endless climb: spawns blocks above the player, scrolls the camera up,
## tracks the best height and ends the run when the player dies or falls off-screen.
## Also does the damage feedback: hit-stop, shake, blood, a full-screen shader
## (red flash, low-health heartbeat vignette and desaturation) and the health bar.

const Block := preload("res://scripts/block.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Rock := preload("res://scripts/rock.gd")
const Medkit := preload("res://scripts/medkit.gd")
const Background := preload("res://scripts/background.gd")
const HealthBar := preload("res://scripts/health_bar.gd")

const DAMAGE_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float hurt = 0.0;   // red flash right after a hit
uniform float low = 0.0;    // 0..1, how close to death
uniform float pulse = 0.0;  // heartbeat, 0..1
void fragment() {
	// Slight blur when dazed or badly hurt.
	vec2 px = SCREEN_PIXEL_SIZE * (1.5 * hurt + 1.2 * low);
	vec3 c = texture(screen_tex, SCREEN_UV).rgb * 0.4;
	c += texture(screen_tex, SCREEN_UV + vec2(px.x, 0.0)).rgb * 0.15;
	c += texture(screen_tex, SCREEN_UV - vec2(px.x, 0.0)).rgb * 0.15;
	c += texture(screen_tex, SCREEN_UV + vec2(0.0, px.y)).rgb * 0.15;
	c += texture(screen_tex, SCREEN_UV - vec2(0.0, px.y)).rgb * 0.15;
	// Colour drains out as health runs low.
	float grey = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(grey), low * 0.8);
	// Red at the edges: a flash on hits, a heartbeat when low (the dark
	// tunnel also closes in a little with each beat).
	float edge = smoothstep(0.25 - 0.06 * low * pulse, 0.8, length((UV - 0.5) * vec2(1.0, 0.75)) * 1.4);
	float red = edge * (hurt * 0.7 + low * (0.4 + 0.35 * pulse)) + hurt * 0.1;
	c = mix(c, vec3(0.45, 0.0, 0.02), clamp(red, 0.0, 0.75));
	COLOR = vec4(c, 1.0);
}
"""

const BLOCK_GAP_Y := 85.0       # vertical distance between blocks (jump peak is ~112)
const MAX_STEP_X := 170.0       # max horizontal shift from the previous block
const BLOCK_HEIGHT := 20.0
const SPAWN_AHEAD := 900.0      # keep blocks generated this far above the screen top
const DESPAWN_BELOW := 200.0    # free blocks this far below the screen bottom
const CAMERA_LEAD := 120.0      # camera keeps the player this far below centre
const ENEMY_START_BLOCK := 6    # no enemies on the first few blocks
const ENEMY_MIN_BLOCK_W := 60.0 # enemies need room to patrol
const ROCK_START_HEIGHT := 5    # rocks start falling once this height is reached
const ROCK_AIM_CHANCE := 0.35   # share of rocks dropped right above the player
const DUST := Color(0.82, 0.76, 0.66, 0.85)
const SNOW_START_HEIGHT := 40   # ledges start getting snow caps here...
const SNOW_FULL_HEIGHT := 70    # ...and all have them from here on
const NIGHT_CLIMB := 9000.0     # matches background.gd: world lighting is darkest here
const NIGHT_LIGHT := Color(0.55, 0.6, 0.82)
const MEDKIT_START_BLOCK := 10
const MEDKIT_CHANCE := 0.07
const LOW_HEALTH := 40.0        # heartbeat vignette and desaturation start here
const BLOOD := Color(0.55, 0.02, 0.03, 0.9)

@onready var player: CharacterBody2D = $Player
@onready var camera: Camera2D = $Camera2D

var _blocks: Array[Node2D] = []
var _next_y := 0.0
var _last_x := 0.0
var _blocks_spawned := 0
var _best_height := 0
var _game_over := false
var _width := 0.0
var _half_height := 0.0
var _rock_timer := 0.0
var _shake := 0.0  # camera shake strength in px, decays over time
var _light: CanvasModulate
var _time := 0.0
var _hurt_flash := 0.0
var _death_fade := 0.0
var _damage_fx: ShaderMaterial
var _health_bar: Node2D
var _score_label: Label
var _message_label: Label


func _ready() -> void:
	_setup_input()
	var view := get_viewport_rect().size
	_width = view.x
	_half_height = view.y / 2.0
	_last_x = _width / 2.0

	var sky := CanvasLayer.new()
	sky.layer = -1
	var background := Background.new()
	background.camera = camera
	sky.add_child(background)
	add_child(sky)
	# Tints only the world (not the sky or HUD layers), so it dims as the sky darkens.
	_light = CanvasModulate.new()
	add_child(_light)

	# Ground: top surface at y = 0.
	_spawn_block(Vector2(_width / 2.0, BLOCK_HEIGHT / 2.0), Vector2(_width, BLOCK_HEIGHT), Color.WHITE, true)
	_next_y = BLOCK_HEIGHT / 2.0 - BLOCK_GAP_Y

	Engine.time_scale = 1.0  # in case a restart happened during hit-stop
	player.landed.connect(_on_player_landed)
	player.hurt.connect(_on_player_hurt)
	player.healed.connect(func(_amount: float) -> void:
		_spawn_dust(player.position + Vector2(0, -20), 12, Color(0.5, 1.0, 0.55, 0.9)))
	player.died.connect(_end_game.bind(true))
	_build_ui()
	_message_label.text = "Klettere die Blöcke hoch!\nA/D oder Pfeiltasten zum Laufen, Leertaste/W/Hoch zum Springen"


func _process(delta: float) -> void:
	_shake *= exp(-10.0 * delta)
	camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake
	_light.color = Color.WHITE.lerp(NIGHT_LIGHT, clampf(-camera.position.y / NIGHT_CLIMB, 0.0, 1.0))
	_update_damage_fx(delta)

	if _game_over:
		if Input.is_action_just_pressed("jump"):
			get_tree().reload_current_scene()
		return

	# Camera only moves up.
	var target_y := player.position.y - CAMERA_LEAD
	if target_y < camera.position.y:
		camera.position.y = lerpf(camera.position.y, target_y, 1.0 - exp(-8.0 * delta))

	var screen_top := camera.position.y - _half_height
	var screen_bottom := camera.position.y + _half_height

	while _next_y > screen_top - SPAWN_AHEAD:
		_spawn_next_block()

	while not _blocks.is_empty() and _blocks[0].position.y > screen_bottom + DESPAWN_BELOW:
		_blocks.pop_front().queue_free()

	var height := maxi(0, int(-player.position.y / BLOCK_GAP_Y))
	if height > _best_height:
		_best_height = height
		_message_label.text = ""
	_score_label.text = "Höhe: %d" % _best_height

	if _best_height >= ROCK_START_HEIGHT:
		_rock_timer -= delta
		if _rock_timer <= 0.0:
			_spawn_rock()
			# Rocks come more often the higher you are.
			_rock_timer = randf_range(0.6, 1.2) * maxf(0.8, 3.0 - _best_height * 0.04)

	if player.position.y > screen_bottom + 40.0:
		_end_game("Abgestürzt!", false)


func _spawn_next_block() -> void:
	# Blocks get narrower the higher you go.
	var max_w := maxf(70.0, 130.0 - _blocks_spawned * 0.6)
	var w := randf_range(max_w - 40.0, max_w)
	var x := clampf(_last_x + randf_range(-MAX_STEP_X, MAX_STEP_X), w / 2.0, _width - w / 2.0)
	_last_x = x
	# Natural rock tones: greys with a hint of sandstone or slate.
	var rock_color := Color.from_hsv(randf_range(0.05, 0.11), randf_range(0.06, 0.22), randf_range(0.66, 0.84))
	var height := -_next_y / BLOCK_GAP_Y
	var snow_chance := inverse_lerp(SNOW_START_HEIGHT, SNOW_FULL_HEIGHT, height)
	var block := _spawn_block(Vector2(x, _next_y), Vector2(w, BLOCK_HEIGHT), rock_color, false, randf() < snow_chance)
	_next_y -= BLOCK_GAP_Y
	_blocks_spawned += 1

	# Enemies get more common and faster the higher you go.
	var enemy_chance := minf(0.4, 0.15 + _blocks_spawned * 0.004)
	if _blocks_spawned >= ENEMY_START_BLOCK and w >= ENEMY_MIN_BLOCK_W and randf() < enemy_chance:
		_spawn_enemy(block, minf(110.0, 40.0 + _blocks_spawned * 0.8))
	elif _blocks_spawned >= MEDKIT_START_BLOCK and randf() < MEDKIT_CHANCE:
		var kit := Medkit.new()
		kit.position = Vector2(randf_range(-w / 2.0 + 10.0, w / 2.0 - 10.0), -BLOCK_HEIGHT / 2.0)
		block.add_child(kit)


func _spawn_block(pos: Vector2, block_size: Vector2, block_color: Color, is_ground := false, is_snowy := false) -> Block:
	var block := Block.new()
	block.size = block_size
	block.color = block_color
	block.ground = is_ground
	block.snowy = is_snowy
	block.position = pos
	add_child(block)
	_blocks.append(block)
	return block


## Enemy is a child of its block, so it is freed together with it.
func _spawn_enemy(block: Block, speed: float) -> void:
	var enemy := Enemy.new()
	enemy.position = Vector2(randf_range(-10.0, 10.0), -block.size.y / 2.0)
	enemy.patrol_half_width = block.size.x / 2.0 - Enemy.SIZE.x / 2.0
	enemy.speed = speed
	enemy.stomped.connect(func(at: Vector2) -> void:
		_spawn_dust(at, 12, Color(Enemy.BODY.lightened(0.3), 0.8))
		_shake = maxf(_shake, 2.0))
	block.add_child(enemy)


func _spawn_rock() -> void:
	var rock := Rock.new()
	rock.camera = camera
	rock.radius = randf_range(10.0, 16.0)
	var x := player.position.x if randf() < ROCK_AIM_CHANCE else randf_range(0.0, _width)
	rock.position = Vector2(clampf(x, rock.radius, _width - rock.radius), camera.position.y - _half_height)
	rock.shattered.connect(func(_at: Vector2, hit_player: bool) -> void:
		if not hit_player:
			_shake = maxf(_shake, 1.5))
	add_child(rock)


## Hard landings kick up dust and shake the camera a little.
func _on_player_landed(impact_speed: float) -> void:
	if impact_speed < 250.0:
		return
	_spawn_dust(player.position, int(clampf(impact_speed / 60.0, 4.0, 14.0)), DUST)
	_shake = maxf(_shake, (impact_speed - 550.0) / 70.0)


func _spawn_dust(pos: Vector2, amount: int, dust_color: Color) -> void:
	var dust := CPUParticles2D.new()
	dust.position = pos
	dust.one_shot = true
	dust.explosiveness = 0.9
	dust.amount = amount
	dust.lifetime = 0.5
	dust.direction = Vector2.UP
	dust.spread = 75.0
	dust.initial_velocity_min = 30.0
	dust.initial_velocity_max = 90.0
	dust.gravity = Vector2(0, 150)
	dust.damping_min = 60.0
	dust.damping_max = 100.0
	dust.scale_amount_min = 2.0
	dust.scale_amount_max = 4.5
	var fade := Gradient.new()
	fade.set_color(0, dust_color)
	fade.set_color(1, Color(dust_color, 0.0))
	dust.color_ramp = fade
	dust.finished.connect(dust.queue_free)
	add_child(dust)
	dust.emitting = true


## Every hit: a brief freeze (hit-stop), camera shake, red flash and blood
## spraying away from where the hit came from — all scaled by the damage.
func _on_player_hurt(amount: float, from: Vector2) -> void:
	_shake = maxf(_shake, 3.0 + amount * 0.2)
	_hurt_flash = clampf(amount / 30.0, 0.5, 1.0)
	var away := (player.global_position + Vector2(0, -18) - from).normalized()
	if from.y > player.global_position.y:  # fall damage: no wound, dust instead
		_spawn_dust(player.position, 16, DUST)
	else:
		_spawn_blood(player.position + Vector2(0, -18), away, int(clampf(amount / 3.0, 4.0, 14.0)))
	_hit_stop(0.05 + amount * 0.002)


func _hit_stop(duration: float) -> void:
	Engine.time_scale = 0.05
	get_tree().create_timer(duration, true, false, true).timeout.connect(func() -> void:
		if not _game_over:
			Engine.time_scale = 1.0)


func _spawn_blood(pos: Vector2, dir: Vector2, amount: int) -> void:
	var blood := CPUParticles2D.new()
	blood.position = pos
	blood.one_shot = true
	blood.explosiveness = 0.95
	blood.amount = amount
	blood.lifetime = 0.7
	blood.direction = dir
	blood.spread = 35.0
	blood.initial_velocity_min = 60.0
	blood.initial_velocity_max = 170.0
	blood.gravity = Vector2(0, 700)
	blood.scale_amount_min = 1.2
	blood.scale_amount_max = 2.4
	var fade := Gradient.new()
	fade.set_color(0, BLOOD)
	fade.set_color(1, Color(BLOOD.darkened(0.3), 0.0))
	blood.color_ramp = fade
	blood.finished.connect(blood.queue_free)
	add_child(blood)
	blood.emitting = true


func _update_damage_fx(delta: float) -> void:
	_time += delta
	_hurt_flash = move_toward(_hurt_flash, 0.0, delta * 2.5)
	if _game_over and player.health <= 0.0:
		_death_fade = move_toward(_death_fade, 1.0, delta * 0.8)
	var low := sqrt(clampf((LOW_HEALTH - player.health) / LOW_HEALTH, 0.0, 1.0))
	# Heartbeat speeds up as health drops; sharp double thump.
	var beat := fmod(_time * lerpf(1.2, 2.6, low), 1.0)
	var pulse := maxf(0.0, 1.0 - absf(beat - 0.1) * 10.0) + 0.6 * maxf(0.0, 1.0 - absf(beat - 0.3) * 10.0)
	_damage_fx.set_shader_parameter("hurt", _hurt_flash)
	_damage_fx.set_shader_parameter("low", maxf(low, _death_fade))
	_damage_fx.set_shader_parameter("pulse", pulse)
	_health_bar.health = player.health


## `knockout`: the player was knocked out and tumbles off; otherwise they already fell off-screen.
func _end_game(reason: String, knockout: bool) -> void:
	if _game_over:
		return
	_game_over = true
	if knockout:
		player.die()
		_shake = 8.0
		# Slow-motion collapse, back to normal speed after a moment.
		Engine.time_scale = 0.3
		get_tree().create_timer(0.6, true, false, true).timeout.connect(func() -> void:
			Engine.time_scale = 1.0)
	else:
		player.set_physics_process(false)
	_message_label.text = "%s\nHöhe: %d\n\nLeertaste für neuen Versuch" % [reason, _best_height]


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)

	# Full-screen damage effect; it reads the screen, so it sits below the HUD.
	var fx := ColorRect.new()
	fx.size = get_viewport_rect().size
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = DAMAGE_SHADER
	_damage_fx = ShaderMaterial.new()
	_damage_fx.shader = shader
	fx.material = _damage_fx
	ui.add_child(fx)

	_health_bar = HealthBar.new()
	_health_bar.position = Vector2(_width - HealthBar.WIDTH - 36.0, 16)
	ui.add_child(_health_bar)

	_score_label = Label.new()
	_score_label.position = Vector2(12, 8)
	_score_label.add_theme_font_size_override("font_size", 26)
	_score_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_score_label.add_theme_constant_override("outline_size", 6)
	ui.add_child(_score_label)

	_message_label = Label.new()
	_message_label.position = Vector2(0, 240)
	_message_label.size = Vector2(_width, 200)
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_message_label.add_theme_font_size_override("font_size", 24)
	_message_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_message_label.add_theme_constant_override("outline_size", 6)
	ui.add_child(_message_label)


func _setup_input() -> void:
	_add_action("move_left", [KEY_LEFT, KEY_A])
	_add_action("move_right", [KEY_RIGHT, KEY_D])
	_add_action("jump", [KEY_SPACE, KEY_UP, KEY_W])


func _add_action(action: StringName, keys: Array[Key]) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)
