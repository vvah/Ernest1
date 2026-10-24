# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A simple 2D endless climber built with Godot: a small human character jumps up an endless column of blocks.

## Architecture

- No image assets: the player and blocks draw themselves with `_draw()` primitives.
- `scenes/main.tscn` + `scripts/main.gd` — the game controller. It creates the input actions at runtime (`move_left`, `move_right`, `jump` via `InputMap`, not in `project.godot`), spawns blocks procedurally above the screen and frees them below, scrolls the `Camera2D` upward only, builds the HUD labels in code, and restarts with `reload_current_scene()` after the player falls off-screen.
- `scenes/player.tscn` + `scripts/player.gd` — `CharacterBody2D` whose origin is at the feet (collision shape offset upward).
- `scripts/block.gd` — `StaticBody2D` platform with no scene; `main.gd` preloads it, sets `size`/`color`, then adds it. Collision is one-way so the player jumps up through blocks.
- `scripts/enemy.gd` — `Area2D` beetle with no scene, spawned by `main.gd` as a child of a block (freed with it) and patrolling its width. Landing on it while falling stomps it (`player.bounce()`); any other contact emits `player_hit`, which ends the run. Enemies find the player via the `player` group.
- `scripts/rock.gd` — `Area2D` falling rock with no scene, spawned by `main.gd` on a timer once height ≥ `ROCK_START_HEIGHT`. It needs the `camera` reference: it first sits at the screen top as a blinking warning (collision off), then falls through blocks; contact emits `player_hit`. Frees itself below the screen.
- `scripts/background.gd` — sky drawn in screen space on a `CanvasLayer` (layer -1) that `main.gd` creates; needs the `camera` reference. Sky darkens and stars appear with height; mountains/clouds use parallax.
- Player movement has momentum (`GROUND_ACCEL`/`AIR_ACCEL`/friction), coyote time and jump buffering. It emits `landed(impact_speed)`, which `main.gd` uses for dust (`CPUParticles2D`) and camera shake (`camera.offset`). On a hit `main.gd` calls `player.die()` (tumbles off, collisions off); falling off-screen just stops its physics.
- Blocks look like rock ledges (rough underside, cracks, moss); that is drawing only — collision stays a rectangle. `ground = true` draws dirt and grass instead; `snowy = true` (chance rises between `SNOW_START_HEIGHT` and `SNOW_FULL_HEIGHT` in `main.gd`) draws snow and icicles.
- A `CanvasModulate` in `main.gd` dims the world with height (`NIGHT_CLIMB`, kept in step with `SKY_DARK_CLIMB` in `background.gd`); the sky and HUD live on their own `CanvasLayer`s and are unaffected. Landing faster than `STUN_IMPACT` stuns the player for `STUN_TIME` (no control).
- Reachability is coupled: `BLOCK_GAP_Y`/`MAX_STEP_X` in `main.gd` must stay within the jump arc from `JUMP_VELOCITY`/`GRAVITY`/`SPEED` in `player.gd` (peak ≈ 112 px).
- Viewport is 480×720 portrait; ground's top surface is at y = 0, so height = `-y / BLOCK_GAP_Y`.
- In-game text is German.

## Godot

- Version: Godot 4.7.2 stable, installed at `C:\Projects\Godot_v4.7.2\` (folder is on PATH).
- There is no plain `godot` command; call the exe by name:
  - `Godot_v4.7.2-stable_win64_console.exe` — use for all CLI/headless runs (prints to stdout).
  - `Godot_v4.7.2-stable_win64.exe` — the editor GUI.
- Target Godot 4.x APIs and GDScript 2.0 syntax (e.g. `@export`, `@onready`, typed signals); do not use Godot 3 idioms.

## Commands

Run from the repo root:

```sh
# Open the editor on this project
Godot_v4.7.2-stable_win64.exe --editor --path .

# Run the game
Godot_v4.7.2-stable_win64_console.exe --path .

# Run a specific scene
Godot_v4.7.2-stable_win64_console.exe --path . res://path/to/scene.tscn

# Import assets / check that scripts parse without opening a window
Godot_v4.7.2-stable_win64_console.exe --headless --path . --import

# Run a script headlessly (e.g. a test or tool script extending SceneTree)
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://path/to/script.gd
```

No test framework, linter, or export presets are set up yet.
