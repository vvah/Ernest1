extends Node
## Damage sound effects synthesised in code (no audio files): impacts, cracking
## stone, bites, fire, a heartbeat for low health and a healing chime.
## The samples are built once and cached in a static table, so restarts are free.
## main.gd creates this node and calls play() / set_burning().

const RATE := 22050
const VOICES := 8

static var _sounds := {}

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _sizzle: AudioStreamPlayer


func _ready() -> void:
	if _sounds.is_empty():
		_sounds["thud"] = _make(0.25, _thud)
		_sounds["crack"] = _make(0.3, _crack)
		_sounds["bite"] = _make(0.1, _bite)
		_sounds["squish"] = _make(0.18, _squish)
		_sounds["burst"] = _make(0.4, _burst)
		_sounds["heartbeat"] = _make(0.42, _heartbeat)
		_sounds["heal"] = _make(0.7, _heal)
		_sounds["sizzle"] = _make(1.0, _sizzle_fn, true)
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	_sizzle = AudioStreamPlayer.new()
	_sizzle.stream = _sounds["sizzle"]
	_sizzle.volume_db = -9.0
	add_child(_sizzle)


## Plays a named sound on the next free voice, slightly varied each time.
func play(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	var player := _players[_next]
	_next = (_next + 1) % VOICES
	player.stream = _sounds[sound]
	player.volume_db = volume_db
	player.pitch_scale = pitch * randf_range(0.93, 1.07)
	player.play()


func set_burning(on: bool) -> void:
	if on and not _sizzle.playing:
		_sizzle.play()
	elif not on and _sizzle.playing:
		_sizzle.stop()


## Renders `length` seconds of `fn(t, state)` into a 16-bit mono sample.
## `state` is a scratch dictionary for oscillator phase and filter memory.
func _make(length: float, fn: Callable, loop := false) -> AudioStreamWAV:
	var count := int(length * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var state := {"phase": 0.0, "lp": 0.0, "lp2": 0.0}
	for i in count:
		var v: float = fn.call(float(i) / RATE, state)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = count
	return wav


## Sine whose pitch is driven by `freq`, keeping phase continuous.
static func _osc(state: Dictionary, freq: float) -> float:
	state.phase += TAU * freq / RATE
	return sin(state.phase)


## One-pole low-pass on white noise; `k` near 1 = bright, near 0 = muffled.
static func _noise_lp(state: Dictionary, k: float) -> float:
	state.lp += (randf_range(-1.0, 1.0) - state.lp) * k
	return state.lp


# Body blow: a deep thump dropping in pitch plus a short muffled smack.
func _thud(t: float, s: Dictionary) -> float:
	var body := _osc(s, 45.0 + 110.0 * exp(-t * 12.0)) * exp(-t * 16.0)
	var smack := _noise_lp(s, 0.35) * exp(-t * 70.0)
	return body * 0.9 + smack * 0.8


# Stone splitting: bright noise burst with random crackle spikes.
func _crack(t: float, s: Dictionary) -> float:
	var n := randf_range(-1.0, 1.0)
	s.lp += (n - s.lp) * 0.45
	var bright: float = n - s.lp
	var spike := randf_range(-1.0, 1.0) if randf() < 0.03 * exp(-t * 8.0) else 0.0
	return (bright * 0.55 + s.lp * 0.5) * exp(-t * 13.0) + spike * 0.7


# Mandibles snapping: two sharp clicks.
func _bite(t: float, s: Dictionary) -> float:
	var n := randf_range(-1.0, 1.0)
	s.lp += (n - s.lp) * 0.6
	var click := 0.0
	if t < 0.012:
		click = exp(-t * 300.0)
	elif t > 0.055 and t < 0.07:
		click = exp(-(t - 0.055) * 300.0) * 0.8
	return (n - s.lp) * click


# Wet squelch of a stomped beetle.
func _squish(t: float, s: Dictionary) -> float:
	var tone := _osc(s, 220.0 * exp(-t * 9.0) + 60.0) * 0.5
	return (tone + _noise_lp(s, 0.15) * 1.6) * exp(-t * 18.0)


# Fireball impact: a soft whoomp of rushing air.
func _burst(t: float, s: Dictionary) -> float:
	var attack := minf(1.0, t / 0.02)
	s.lp2 += (_noise_lp(s, 0.25) - s.lp2) * 0.5
	return s.lp2 * 2.2 * attack * exp(-t * 7.0)


# Lub-dub: two low thumps, the second slightly higher and softer.
func _heartbeat(t: float, s: Dictionary) -> float:
	var v := 0.0
	if t < 0.14:
		v = sin(TAU * (48.0 + 20.0 * exp(-t * 30.0)) * t) * exp(-t * 28.0)
	var t2 := t - 0.17
	if t2 > 0.0:
		v += sin(TAU * (58.0 + 22.0 * exp(-t2 * 30.0)) * t2) * exp(-t2 * 32.0) * 0.75
	return v


# Healing: a soft bell chord.
func _heal(t: float, _s: Dictionary) -> float:
	var bell := sin(TAU * 660.0 * t) + 0.6 * sin(TAU * 990.0 * t) + 0.3 * sin(TAU * 1320.0 * t)
	return bell * 0.3 * exp(-t * 5.0) * minf(1.0, t / 0.01)


# Burning clothes: flickering hiss with crackles (loops seamlessly over 1 s).
func _sizzle_fn(t: float, s: Dictionary) -> float:
	var n := randf_range(-1.0, 1.0)
	s.lp += (n - s.lp) * 0.5
	var flicker := 0.55 + 0.45 * absf(sin(TAU * 7.0 * t))
	var pop := randf_range(-1.0, 1.0) if randf() < 0.004 else 0.0
	return (n - s.lp) * 0.4 * flicker + pop * 0.6
