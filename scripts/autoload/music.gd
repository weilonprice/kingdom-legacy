extends Node
## Background music (autoload "Music"), composed in code. Instruments are
## synthesized once at startup (see Synth); a step sequencer plays them.
## Each mood has a key, mode, tempo, chord progression and a set of voices;
## the melody is re-rolled from a seed every loop so it never repeats
## exactly. Moods crossfade when the game's situation changes.
##   Music.set_mood("day" | "night" | "winter" | "raid" | "siege" | "title" | "")

const MODES := {
	"dorian": [0, 2, 3, 5, 7, 9, 10],
	"aeolian": [0, 2, 3, 5, 7, 8, 10],
	"mixolydian": [0, 2, 4, 5, 7, 9, 10],
	"phrygian": [0, 1, 3, 5, 7, 8, 10],
}
## Chords are scale degrees (0 = the key's root), one per bar.
const MOODS := {
	"title": {"root": 55, "mode": "mixolydian", "bpm": 90, "chords": [0, 3, 6, 0, 4, 3, 6, 0],
		"voices": ["lute", "melody", "bass", "pad"], "db": -6.0},
	"day": {"root": 62, "mode": "dorian", "bpm": 100, "chords": [0, 6, 0, 4, 2, 6, 3, 0],
		"voices": ["lute", "melody", "bass"], "db": -8.0},
	"night": {"root": 57, "mode": "dorian", "bpm": 70, "chords": [0, 3, 0, 6, 0, 3, 4, 0],
		"voices": ["pad", "sparse"], "db": -10.0},
	"winter": {"root": 57, "mode": "aeolian", "bpm": 64, "chords": [0, 5, 2, 6, 0, 3, 4, 0],
		"voices": ["pad", "bells"], "db": -9.0},
	"raid": {"root": 50, "mode": "dorian", "bpm": 132, "chords": [0, 0, 6, 6, 5, 5, 6, 4],
		"voices": ["drums", "ostinato", "brass"], "db": -6.0},
	"siege": {"root": 45, "mode": "phrygian", "bpm": 120, "chords": [0, 1, 0, 6, 5, 1, 0, 0],
		"voices": ["drums", "ostinato", "brass", "pad"], "db": -5.0},
}
const STEPS_PER_BAR := 8   # eighth notes in 4/4
const BASE_MIDI := 60      # the instruments are rendered at middle C
const POOL := 10

var mood := ""
## Notes played so far (for tests).
var notes_played := 0

var _instruments := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _pattern: Array = []   # per step: Array of [instrument, midi, volume_db]
var _step := 0
var _cycle := 0
var _next_step_usec := 0
var _pending := ""
var _fade := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index("Music") < 0:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Music")
		AudioServer.set_bus_send(idx, "Master")
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		add_child(p)
		_players.append(p)
	_build_instruments()


func set_mood(new_mood: String) -> void:
	if new_mood == mood and _pending == "":
		return
	if new_mood == _pending:
		return
	_pending = new_mood


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	# Fade out before switching moods, then start the new one on a bar line.
	if _pending != "" or (_pending == "" and mood == "" and _fade < 1.0):
		_fade = maxf(_fade - _delta / maxf(Engine.time_scale, 0.001) / 1.5, 0.0)
		if _fade <= 0.0 or mood == "":
			mood = _pending
			_pending = ""
			_step = 0
			_cycle += 1
			_pattern = _compose(mood, _cycle) if mood != "" else []
			_fade = 1.0
			_next_step_usec = now
	if mood == "" or _pattern.is_empty() or now < _next_step_usec:
		return
	var def: Dictionary = MOODS[mood]
	var step_usec := int(60.0 / def.bpm / 2.0 * 1_000_000.0)
	_next_step_usec += step_usec
	if now - _next_step_usec > step_usec * 4:
		_next_step_usec = now + step_usec  # we fell behind (e.g. a hitch): resync
	for note: Array in _pattern[_step]:
		_play(note[0], note[1], note[2] + def.db + linear_to_db(maxf(_fade, 0.001)))
	_step += 1
	if _step >= _pattern.size():
		_step = 0
		_cycle += 1
		_pattern = _compose(mood, _cycle)


func _play(inst: String, midi: int, db: float) -> void:
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _instruments[inst]
	p.pitch_scale = pow(2.0, (midi - BASE_MIDI) / 12.0)
	p.volume_db = db
	p.play()
	notes_played += 1


# --- Composing ------------------------------------------------------------------

## One loop (8 bars) of a mood as a list of steps, each a list of notes.
func _compose(m: String, cycle: int) -> Array:
	var def: Dictionary = MOODS[m]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(m) + cycle * 7919
	var scale: Array = MODES[def.mode]
	var root: int = def.root
	var steps: Array = []
	for i in def.chords.size() * STEPS_PER_BAR:
		steps.append([])
	var prev_melody := root + 12
	for bar in def.chords.size():
		var degree: int = int(def.chords[bar])
		var chord := [_note(root, scale, degree), _note(root, scale, degree + 2), _note(root, scale, degree + 4)]
		var at: int = bar * STEPS_PER_BAR
		for voice: String in def.voices:
			match voice:
				"lute":
					var arp := [0, 1, 2, 1, 3, 1, 2, 1]
					for s in STEPS_PER_BAR:
						var n: int = chord[arp[s]] if arp[s] < 3 else chord[0] + 12
						steps[at + s].append(["lute", n, -4.0 if s % 2 == 0 else -7.0])
				"bass":
					steps[at].append(["bass", chord[0] - 12, -3.0])
					steps[at + 4].append(["bass", chord[0] - 12 + (7 if rng.randf() < 0.5 else 0), -5.0])
				"pad":
					for n: int in chord:
						steps[at].append(["pad", n, -9.0])
				"melody":
					# Strong beats on chord tones, a passing tone now and then.
					for s in [0, 2, 3, 4, 6]:
						if s != 0 and rng.randf() < 0.35:
							continue
						var target: int = chord[rng.randi_range(0, 2)] + 12
						if s % 2 == 1 and rng.randf() < 0.5:
							target = _nearest_scale(prev_melody + (1 if rng.randf() < 0.5 else -1), root, scale)
						if target > 84:
							target -= 12  # keep the recorder out of the shrill range
						prev_melody = target
						steps[at + s].append(["recorder", target, -5.0])
				"sparse":
					for s in STEPS_PER_BAR:
						if rng.randf() < 0.22:
							steps[at + s].append(["lute", chord[rng.randi_range(0, 2)] + 12, -8.0])
				"bells":
					for s in [0, 4]:
						if rng.randf() < 0.6:
							steps[at + s].append(["bell", chord[rng.randi_range(0, 2)] + 12, -8.0])
				"drums":
					for s in STEPS_PER_BAR:
						if s % 4 == 0:
							steps[at + s].append(["drum", 48, -2.0])
						elif s % 2 == 0:
							steps[at + s].append(["tom", 52, -6.0])
						elif rng.randf() < 0.3:
							steps[at + s].append(["tom", 55, -10.0])
				"ostinato":
					for s in STEPS_PER_BAR:
						var n2: int = chord[0] - 12 + (7 if s in [6, 7] else 0)
						steps[at + s].append(["bass", n2, -6.0])
				"brass":
					for s in [0, 3]:
						for n: int in chord:
							steps[at + s].append(["brass", n, -10.0])
	return steps


func _note(root: int, scale: Array, degree: int) -> int:
	return root + scale[degree % 7] + 12 * int(degree / 7)


func _nearest_scale(midi: int, root: int, scale: Array) -> int:
	var rel := posmod(midi - root, 12)
	var best: int = scale[0]
	for s: int in scale:
		if absi(s - rel) < absi(best - rel):
			best = s
	return midi - rel + best


# --- Instruments -------------------------------------------------------------

func _build_instruments() -> void:
	var c4 := 261.63
	_instruments = {
		"lute": Synth.make([{"wave": "saw", "freq": c4, "dur": 1.2, "vol": 0.5, "attack": 0.003,
				"release": 1.15, "lowpass": 0.22},
			{"wave": "triangle", "freq": c4 * 2.0, "dur": 0.6, "vol": 0.15, "attack": 0.003, "release": 0.55}]),
		"recorder": Synth.make([{"wave": "sine", "freq": c4, "dur": 0.8, "vol": 0.5, "attack": 0.05,
				"release": 0.25, "vibrato": 5.0, "vib_depth": 0.006},
			{"wave": "sine", "freq": c4 * 2.0, "dur": 0.8, "vol": 0.08, "attack": 0.05, "release": 0.25}]),
		"pad": Synth.make([{"wave": "triangle", "freq": c4, "dur": 5.0, "vol": 0.4, "attack": 0.6, "release": 2.0},
			{"wave": "sine", "freq": c4 * 2.0, "dur": 5.0, "vol": 0.12, "attack": 0.8, "release": 2.0}]),
		"bass": Synth.make([{"wave": "triangle", "freq": c4, "dur": 0.5, "vol": 0.6, "attack": 0.005, "release": 0.35}]),
		"bell": Synth.make([{"wave": "sine", "freq": c4, "dur": 2.0, "vol": 0.4, "attack": 0.002, "release": 1.9},
			{"wave": "sine", "freq": c4 * 2.76, "dur": 1.2, "vol": 0.15, "attack": 0.002, "release": 1.1}]),
		"brass": Synth.make([{"wave": "saw", "freq": c4, "dur": 0.45, "vol": 0.4, "attack": 0.03, "release": 0.2,
				"lowpass": 0.3}]),
		"drum": Synth.make([{"wave": "sine", "freq": 110, "freq_end": 45, "dur": 0.3, "vol": 0.9, "release": 0.25},
			{"wave": "noise", "dur": 0.08, "vol": 0.3, "lowpass": 0.2}]),
		"tom": Synth.make([{"wave": "sine", "freq": 220, "freq_end": 140, "dur": 0.2, "vol": 0.6, "release": 0.18}]),
	}
