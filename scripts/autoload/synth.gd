class_name Synth
extends RefCounted
## Tiny sound synthesizer: builds short 16-bit mono AudioStreamWAVs from
## oscillators, noise and envelopes, in the spirit of sfxr. Every game sound
## is made here at startup, so the game ships no audio files.

const RATE := 22050


## A sound as layers mixed together. Each layer:
##   wave: "sine" | "square" | "saw" | "noise" | "triangle"
##   freq, freq_end (Hz, slides linearly), dur (s), delay (s), vol (0..1),
##   attack, release (s), vibrato (Hz), vib_depth (fraction of freq),
##   lowpass (0..1, 1 = off; for noise), duty (square wave)
static func make(layers: Array) -> AudioStreamWAV:
	var total := 0.0
	for l: Dictionary in layers:
		total = maxf(total, l.get("delay", 0.0) + l.dur)
	var n := int(total * RATE) + 1
	var buf := PackedFloat32Array()
	buf.resize(n)
	for l: Dictionary in layers:
		_render(buf, l)
	# Normalise gently and convert to 16-bit.
	var peak := 0.0
	for v in buf:
		peak = maxf(peak, absf(v))
	var gain := 0.9 / peak if peak > 0.9 else 1.0
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i] * gain, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


static func _render(buf: PackedFloat32Array, l: Dictionary) -> void:
	var start := int(l.get("delay", 0.0) * RATE)
	var count := int(float(l.dur) * RATE)
	var f0: float = l.get("freq", 440.0)
	var f1: float = l.get("freq_end", f0)
	var vol: float = l.get("vol", 0.5)
	var attack: float = l.get("attack", 0.005)
	var release: float = l.get("release", l.dur * 0.7)
	var vib: float = l.get("vibrato", 0.0)
	var vib_depth: float = l.get("vib_depth", 0.0)
	var lp: float = l.get("lowpass", 1.0)
	var duty: float = l.get("duty", 0.5)
	var wave: String = l.get("wave", "sine")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(l)
	var phase := 0.0
	var smooth := 0.0
	for i in count:
		var idx := start + i
		if idx >= buf.size():
			break
		var t := float(i) / RATE
		var k := float(i) / maxf(count, 1)
		var f := lerpf(f0, f1, k) * (1.0 + sin(TAU * vib * t) * vib_depth)
		phase = fmod(phase + f / RATE, 1.0)
		var s := 0.0
		match wave:
			"sine":
				s = sin(TAU * phase)
			"square":
				s = 1.0 if phase < duty else -1.0
			"saw":
				s = 2.0 * phase - 1.0
			"triangle":
				s = 4.0 * absf(phase - 0.5) - 1.0
			"noise":
				s = rng.randf_range(-1.0, 1.0)
		if lp < 1.0:
			smooth += (s - smooth) * lp
			s = smooth
		var env := 1.0
		if t < attack:
			env = t / attack
		var tail: float = l.dur - t
		if tail < release:
			env *= maxf(tail / release, 0.0)
		buf[idx] += s * env * vol
