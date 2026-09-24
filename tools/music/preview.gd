extends SceneTree
## Renders one loop of each music mood to a WAV file (offline mixdown of the
## same instruments and patterns the game plays), for listening outside the
## game:  godot --headless --path . -s res://tools/music/preview.gd -- --out=/tmp/music
func _init() -> void:
	var out := "/tmp/music"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out)
	var m = load("res://scripts/autoload/music.gd").new()
	m._build_instruments()
	var raw := {}
	for inst in m._instruments:
		var w: AudioStreamWAV = m._instruments[inst]
		var f := PackedFloat32Array()
		f.resize(w.data.size() / 2)
		for i in f.size():
			f[i] = w.data.decode_s16(i * 2) / 32768.0
		raw[inst] = f
	for mood in m.MOODS:
		var def: Dictionary = m.MOODS[mood]
		var pat: Array = m._compose(mood, 1) + m._compose(mood, 2)
		var step: float = 60.0 / float(def.bpm) / 2.0
		var n := int((pat.size() * step + 3.0) * Synth.RATE)
		var mix := PackedFloat32Array()
		mix.resize(n)
		for si in pat.size():
			for note in pat[si]:
				var src: PackedFloat32Array = raw[note[0]]
				var ratio: float = pow(2.0, (note[1] - m.BASE_MIDI) / 12.0)
				var gain: float = db_to_linear(note[2] + def.db)
				var start := int(si * step * Synth.RATE)
				var pos := 0.0
				var k := start
				while pos < src.size() - 1 and k < n:
					var i0 := int(pos)
					mix[k] += lerpf(src[i0], src[i0 + 1], pos - i0) * gain
					pos += ratio
					k += 1
		var peak := 0.0
		for v in mix:
			peak = maxf(peak, absf(v))
		var g := 0.9 / peak if peak > 0.0 else 1.0
		var data := PackedByteArray()
		data.resize(n * 2)
		for i in n:
			data.encode_s16(i * 2, int(clampf(mix[i] * g, -1.0, 1.0) * 32767.0))
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = Synth.RATE
		wav.data = data
		wav.save_to_wav("%s/music_%s.wav" % [out, mood])
		print("rendered %s (%.1fs)" % [mood, n / float(Synth.RATE)])
	m.free()
	quit()
