extends Node2D
## Endless climb: spawns blocks above the player, scrolls the camera up,
## tracks the best height and ends the run when the player falls off-screen.

const Block := preload("res://scripts/block.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Rock := preload("res://scripts/rock.gd")
const Background := preload("res://scripts/background.gd")

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

	# Ground: top surface at y = 0.
	_spawn_block(Vector2(_width / 2.0, BLOCK_HEIGHT / 2.0), Vector2(_width, BLOCK_HEIGHT), Color.WHITE, true)
	_next_y = BLOCK_HEIGHT / 2.0 - BLOCK_GAP_Y

	player.landed.connect(_on_player_landed)
	_build_ui()
	_message_label.text = "Klettere die Blöcke hoch!\nA/D oder Pfeiltasten zum Laufen, Leertaste/W/Hoch zum Springen"


func _process(delta: float) -> void:
	_shake *= exp(-10.0 * delta)
	camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake

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
	var rock_color := Color.from_hsv(randf_range(0.04, 0.12), randf_range(0.08, 0.28), randf_range(0.42, 0.62))
	var block := _spawn_block(Vector2(x, _next_y), Vector2(w, BLOCK_HEIGHT), rock_color)
	_next_y -= BLOCK_GAP_Y
	_blocks_spawned += 1

	# Enemies get more common and faster the higher you go.
	var enemy_chance := minf(0.4, 0.15 + _blocks_spawned * 0.004)
	if _blocks_spawned >= ENEMY_START_BLOCK and w >= ENEMY_MIN_BLOCK_W and randf() < enemy_chance:
		_spawn_enemy(block, minf(110.0, 40.0 + _blocks_spawned * 0.8))


func _spawn_block(pos: Vector2, block_size: Vector2, block_color: Color, is_ground := false) -> Block:
	var block := Block.new()
	block.size = block_size
	block.color = block_color
	block.ground = is_ground
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
	enemy.player_hit.connect(_end_game.bind("Von einem Gegner erwischt!", true))
	enemy.stomped.connect(func(at: Vector2) -> void:
		_spawn_dust(at, 12, Color(Enemy.BODY, 0.8))
		_shake = maxf(_shake, 2.0))
	block.add_child(enemy)


func _spawn_rock() -> void:
	var rock := Rock.new()
	rock.camera = camera
	rock.radius = randf_range(10.0, 16.0)
	var x := player.position.x if randf() < ROCK_AIM_CHANCE else randf_range(0.0, _width)
	rock.position = Vector2(clampf(x, rock.radius, _width - rock.radius), camera.position.y - _half_height)
	rock.player_hit.connect(_end_game.bind("Von einem Stein getroffen!", true))
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


## `knockout`: the player was hit and tumbles off; otherwise they already fell off-screen.
func _end_game(reason: String, knockout: bool) -> void:
	if _game_over:
		return
	_game_over = true
	if knockout:
		player.die()
		_shake = 8.0
	else:
		player.set_physics_process(false)
	_message_label.text = "%s\nHöhe: %d\n\nLeertaste für neuen Versuch" % [reason, _best_height]


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)

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
