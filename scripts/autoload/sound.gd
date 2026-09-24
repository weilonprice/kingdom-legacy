extends Node
## Game audio (autoload "Sound"). Sound effects are synthesized at startup
## (see Synth); play(name, where) plays one, quieter the farther `where` is
## from the camera. Ambience (birds by day, crickets at night, wind in
## winter) is scheduled here too. Buses SFX, Ambience and Music under
## Master; their volumes come from Settings.

const BUSES := ["Master", "SFX", "Ambience", "Music"]
const POOL := 12
## Sounds farther than this many pixels from the view centre are silent.
const HEARING := 1400.0
## Minimum seconds between two plays of the same sound.
const COOLDOWN := {"chop": 0.12, "pick": 0.12, "hit": 0.08, "arrow": 0.06, "step": 0.1}

var volumes := {"Master": 0.8, "SFX": 0.8, "Ambience": 0.6, "Music": 0.5}
## Set by the game: where the camera is, the season and night.
var listener := Vector2.ZERO
var ambience_mode := ""   # "day", "night", "winter" or "" (silent)
## Off while a game is being built or loaded, so setup makes no noise.
var enabled := true
## How many times each sound has played (for tests and curiosity).
var played := {}

var _sounds := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last := {}
var _ambience_timer := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in range(1, BUSES.size()):
		if AudioServer.get_bus_index(BUSES[i]) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, BUSES[i])
			AudioServer.set_bus_send(idx, "Master")
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	for bus: String in volumes:
		_apply(bus)
	_build_sounds()


## Plays a sound; `where` (world position) makes it fade with distance.
func play(name: String, where: Variant = null, volume_db := 0.0, pitch_jitter := 0.06) -> void:
	var stream: AudioStreamWAV = _sounds.get(name)
	if stream == null or not enabled:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last.get(name, -10.0) < COOLDOWN.get(name, 0.0):
		return
	_last[name] = now
	var db := volume_db
	if where != null:
		var d := (where as Vector2).distance_to(listener)
		if d > HEARING:
			return
		db += linear_to_db(1.0 - d / HEARING * 0.85)
	played[name] = played.get(name, 0) + 1
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.bus = "Ambience" if name.begins_with("amb_") else "SFX"
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


## Makes every Button under `root` click when pressed (once per button).
func wire_buttons(root: Node) -> void:
	if root is BaseButton and not root.has_meta("click_sound"):
		root.set_meta("click_sound", true)
		root.pressed.connect(play.bind("click", null, -6.0, 0.0))
	for child in root.get_children():
		wire_buttons(child)


## Called by Settings.
func set_volume(bus: String, value: float) -> void:
	volumes[bus] = clampf(value, 0.0, 1.0)
	_apply(bus)


func _apply(bus: String) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(volumes[bus], 0.0001)))
		AudioServer.set_bus_mute(idx, volumes[bus] <= 0.001)


func _process(delta: float) -> void:
	if ambience_mode == "" or get_tree().paused:
		return
	_ambience_timer -= delta
	if _ambience_timer > 0.0:
		return
	match ambience_mode:
		"day":
			play("amb_bird_%d" % (randi() % 3), null, -10.0, 0.15)
			_ambience_timer = randf_range(1.5, 5.0)
		"night":
			play("amb_cricket", null, -14.0, 0.1)
			_ambience_timer = randf_range(0.8, 2.5)
		"winter":
			play("amb_wind", null, -12.0, 0.1)
			_ambience_timer = randf_range(4.0, 7.0)


# --- The sounds -----------------------------------------------------------------

func _build_sounds() -> void:
	var S := Synth
	_sounds = {
		# Work
		"chop": S.make([{"wave": "noise", "dur": 0.09, "vol": 0.7, "lowpass": 0.35, "release": 0.08},
			{"wave": "triangle", "freq": 180, "freq_end": 110, "dur": 0.07, "vol": 0.5}]),
		"pick": S.make([{"wave": "square", "freq": 1400, "freq_end": 900, "dur": 0.05, "vol": 0.25},
			{"wave": "noise", "dur": 0.06, "vol": 0.4, "lowpass": 0.6}]),
		"build": S.make([{"wave": "square", "freq": 520, "freq_end": 300, "dur": 0.06, "vol": 0.3},
			{"wave": "noise", "dur": 0.05, "vol": 0.4, "lowpass": 0.5},
			{"wave": "square", "freq": 560, "freq_end": 320, "dur": 0.06, "vol": 0.3, "delay": 0.14},
			{"wave": "noise", "dur": 0.05, "vol": 0.4, "lowpass": 0.5, "delay": 0.14}]),
		"road": S.make([{"wave": "noise", "dur": 0.12, "vol": 0.5, "lowpass": 0.15}]),
		"demolish": S.make([{"wave": "noise", "dur": 0.45, "vol": 0.8, "lowpass": 0.2, "release": 0.4},
			{"wave": "saw", "freq": 120, "freq_end": 40, "dur": 0.35, "vol": 0.3}]),
		"click": S.make([{"wave": "square", "freq": 900, "freq_end": 1200, "dur": 0.03, "vol": 0.2, "duty": 0.3}]),
		"coins": S.make([{"wave": "sine", "freq": 1320, "dur": 0.08, "vol": 0.35},
			{"wave": "sine", "freq": 1760, "dur": 0.12, "vol": 0.35, "delay": 0.07}]),
		# Raids and war
		"horn": S.make([{"wave": "saw", "freq": 146, "dur": 1.3, "vol": 0.5, "attack": 0.15, "release": 0.4,
				"vibrato": 5.0, "vib_depth": 0.01, "lowpass": 0.18},
			{"wave": "saw", "freq": 219, "dur": 1.3, "vol": 0.25, "attack": 0.2, "release": 0.4, "lowpass": 0.18}]),
		"arrow": S.make([{"wave": "noise", "dur": 0.1, "vol": 0.35, "lowpass": 0.8, "release": 0.09},
			{"wave": "sine", "freq": 1800, "freq_end": 900, "dur": 0.08, "vol": 0.12}]),
		"hit": S.make([{"wave": "noise", "dur": 0.07, "vol": 0.6, "lowpass": 0.3},
			{"wave": "square", "freq": 200, "freq_end": 90, "dur": 0.06, "vol": 0.3}]),
		"crash": S.make([{"wave": "noise", "dur": 0.8, "vol": 0.9, "lowpass": 0.12, "release": 0.7},
			{"wave": "saw", "freq": 90, "freq_end": 30, "dur": 0.6, "vol": 0.4}]),
		"fire": S.make([{"wave": "noise", "dur": 0.5, "vol": 0.5, "lowpass": 0.25, "attack": 0.1, "release": 0.3}]),
		"death": S.make([{"wave": "square", "freq": 440, "freq_end": 110, "dur": 0.35, "vol": 0.25, "duty": 0.25}]),
		"roar": S.make([{"wave": "saw", "freq": 110, "freq_end": 55, "dur": 1.4, "vol": 0.6, "attack": 0.1,
				"vibrato": 11.0, "vib_depth": 0.08, "lowpass": 0.3},
			{"wave": "noise", "dur": 1.4, "vol": 0.6, "lowpass": 0.15, "attack": 0.1}]),
		"breath": S.make([{"wave": "noise", "dur": 0.7, "vol": 0.7, "lowpass": 0.35, "attack": 0.05, "release": 0.5}]),
		# Moments
		"chime": _chord([523.25, 659.25, 783.99], 1.2, 0.0),
		"victory": _arpeggio([523.25, 659.25, 783.99, 1046.5], 0.16, 1.2),
		"defeat": _arpeggio([392.0, 329.63, 261.63, 196.0], 0.22, 1.0),
		"tier": _arpeggio([392.0, 523.25, 659.25, 783.99], 0.12, 0.8),
		# Ambience
		"amb_bird_0": _bird(2600, 3400, 3),
		"amb_bird_1": _bird(3100, 2500, 2),
		"amb_bird_2": _bird(2200, 2900, 4),
		"amb_cricket": _cricket(),
		"amb_wind": S.make([{"wave": "noise", "dur": 3.5, "vol": 2.4, "lowpass": 0.04, "attack": 1.2, "release": 1.8}]),
	}


func _chord(freqs: Array, dur: float, delay: float) -> AudioStreamWAV:
	return Synth.make(freqs.map(func(f: float) -> Dictionary:
		return {"wave": "sine", "freq": f, "dur": dur, "vol": 0.3, "delay": delay, "release": dur * 0.9}))


func _arpeggio(freqs: Array, step: float, hold: float) -> AudioStreamWAV:
	var layers := []
	for i in freqs.size():
		layers.append({"wave": "triangle", "freq": freqs[i], "dur": hold if i == freqs.size() - 1 else step * 1.5,
			"vol": 0.4, "delay": i * step, "release": 0.3})
	return Synth.make(layers)


func _cricket() -> AudioStreamWAV:
	var layers := []
	for d in [0.0, 0.06, 0.12, 0.3, 0.36, 0.42]:
		layers.append({"wave": "square", "freq": 4200, "dur": 0.03, "vol": 0.15, "delay": d})
	return Synth.make(layers)


func _bird(f0: float, f1: float, chirps: int) -> AudioStreamWAV:
	var layers := []
	for i in chirps:
		layers.append({"wave": "sine", "freq": f0, "freq_end": f1, "dur": 0.07, "vol": 0.3,
			"delay": i * 0.11, "release": 0.05})
	return Synth.make(layers)
