extends AudioStreamPlayer
## Background music: an original 2000s-style hip-hop beat (kick, snare, hi-hats,
## sub bass and a dark synth riff in E minor). No audio files: every drum hit and
## pitch is synthesized once on a worker thread, then a 16th-note step sequencer mixes
## them live into an AudioStreamGenerator. Runs as the `Music` autoload, so it keeps
## playing across scene reloads.

const RATE := 22050.0
const BPM := 92.0
const STEPS_PER_BAR := 16
const OUTPUT_GAIN := 0.7

# 2-bar patterns on a 16th-note grid (32 steps). Drums: step lists.
const KICK := [0, 6, 10, 16, 19, 24, 26]
const SNARE := [4, 12, 20, 28]
const HAT := [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 29, 30]
const OPEN_HAT := [14, 31]
const FILL_SNARE := [26, 27, 29, 30, 31]  # snare roll at the end of the loop
# Pitched parts: step -> midi note.
const BASS := {0: 40, 6: 40, 10: 43, 16: 45, 19: 45, 24: 43, 26: 38}
const RIFF := {0: 76, 3: 79, 6: 78, 8: 76, 11: 74, 14: 71, 16: 76, 19: 79, 22: 81, 24: 79, 27: 78, 30: 74}

const LOOP_BARS := 8  # bars 1-2: drums + bass only, 3-8 with riff, fill at the end
const GAINS := {"kick": 0.95, "snare": 0.6, "hat": 0.22, "open_hat": 0.2, "bass": 0.55, "riff": 0.24}

static var _tables := {}  # name or "bass:<midi>" / "riff:<midi>" -> PackedFloat32Array
static var _task := -1

var _playback: AudioStreamGeneratorPlayback
var _samples_per_step := int(RATE * 60.0 / BPM / 4.0)
var _step := 0                 # step within the whole loop
var _step_left := 0            # samples until the next step
var _voices: Array = []        # [table, position, gain]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = RATE
	generator.buffer_length = 0.25
	stream = generator
	volume_db = -3.0
	if _tables.is_empty() and _task == -1:
		_task = WorkerThreadPool.add_task(render_tables)


func _process(_delta: float) -> void:
	if not playing:
		if _task != -1 and WorkerThreadPool.is_task_completed(_task):
			WorkerThreadPool.wait_for_task_completion(_task)
			_task = -1
		if _task == -1 and not _tables.is_empty():
			play()
			_playback = get_stream_playback()
		return
	fill(_playback, _playback.get_frames_available())


func toggle() -> void:
	stream_paused = not stream_paused


## Mixes `frames` frames into `target` (anything with push_frame(Vector2)).
func fill(target: Object, frames: int) -> void:
	for i in frames:
		_step_left -= 1
		if _step_left <= 0:
			_step_left += _samples_per_step
			_trigger_step()
			_step = (_step + 1) % (LOOP_BARS * STEPS_PER_BAR)

		var sample := 0.0
		var v := _voices.size() - 1
		while v >= 0:
			var voice: Array = _voices[v]
			var table: PackedFloat32Array = voice[0]
			sample += table[voice[1]] * voice[2]
			voice[1] += 1
			if voice[1] >= table.size():
				_voices.remove_at(v)
			v -= 1
		sample *= OUTPUT_GAIN
		sample = sample / (1.0 + absf(sample))  # soft clip
		target.push_frame(Vector2(sample, sample))


func _trigger_step() -> void:
	var bar := _step / STEPS_PER_BAR
	var s := _step % (STEPS_PER_BAR * 2)  # position in the 2-bar pattern
	var last_bars := bar >= LOOP_BARS - 2
	if s in KICK:
		_play("kick")
	if s in SNARE or (last_bars and s in FILL_SNARE):
		_play("snare")
	if s in OPEN_HAT:
		_play("open_hat")
	elif s in HAT:
		_play("hat")
	if BASS.has(s):
		_play("bass", BASS[s])
	if bar >= 2 and RIFF.has(s):
		_play("riff", RIFF[s])


func _play(instrument: String, midi := -1) -> void:
	var key := instrument if midi < 0 else "%s:%d" % [instrument, midi]
	_voices.append([_tables[key], 0, GAINS[instrument]])


## Runs on a worker thread (or directly in tests).
static func render_tables() -> void:
	var tables := {
		"kick": _kick(),
		"snare": _snare(),
		"hat": _hat(0.05),
		"open_hat": _hat(0.22),
	}
	for midi in BASS.values():
		tables["bass:%d" % midi] = _bass(_hz(midi))
	for midi in RIFF.values():
		tables["riff:%d" % midi] = _riff(_hz(midi))
	_tables = tables


static func _hz(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)


static func _buffer(seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(seconds * RATE))
	return out


## Pitch-swept sine: the deep "boom".
static func _kick() -> PackedFloat32Array:
	var out := _buffer(0.4)
	var phase := 0.0
	for i in out.size():
		var t := i / RATE
		phase += TAU * (45.0 + 110.0 * exp(-t * 28.0)) / RATE
		out[i] = sin(phase) * exp(-t * 7.0) + (0.4 * exp(-t * 300.0) if i < 60 else 0.0)
	return out


## Noise crack plus a short tone body.
static func _snare() -> PackedFloat32Array:
	var out := _buffer(0.22)
	var prev := 0.0
	for i in out.size():
		var t := i / RATE
		var noise := randf_range(-1.0, 1.0)
		var bright := noise - prev * 0.6  # crude high-pass
		prev = noise
		out[i] = bright * exp(-t * 16.0) * 0.7 + sin(TAU * 185.0 * t) * exp(-t * 30.0) * 0.6
	return out


static func _hat(seconds: float) -> PackedFloat32Array:
	var out := _buffer(seconds)
	var prev := 0.0
	var decay := 4.0 / seconds
	for i in out.size():
		var noise := randf_range(-1.0, 1.0)
		out[i] = (noise - prev) * 0.5 * exp(-i / RATE * decay)
		prev = noise
	return out


## Round sub bass with a little grit.
static func _bass(freq: float) -> PackedFloat32Array:
	var out := _buffer(0.55)
	for i in out.size():
		var t := i / RATE
		var x := sin(TAU * freq * t) + 0.35 * sin(TAU * freq * 2.0 * t)
		var env := minf(1.0, t * 200.0) * exp(-t * 3.5)
		x *= env * 1.6
		out[i] = x / (1.0 + absf(x))
	return out


## Two detuned, filtered square waves: a dark synth stab.
static func _riff(freq: float) -> PackedFloat32Array:
	var out := _buffer(0.4)
	var low := 0.0
	for i in out.size():
		var t := i / RATE
		var sq := signf(sin(TAU * freq * t)) + signf(sin(TAU * freq * 1.007 * t))
		low = lerpf(low, sq * 0.5, 0.18)
		out[i] = low * minf(1.0, t * 300.0) * exp(-t * 6.0)
	return out
