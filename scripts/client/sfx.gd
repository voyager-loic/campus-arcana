extends Node
## Tiny procedural sound bank (no audio assets needed).

const RATE := 22050

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0

var intro_sound_player: AudioStreamPlayer = AudioStreamPlayer.new()
var gameplay_sound_player: AudioStreamPlayer = AudioStreamPlayer.new()


func _ready() -> void:
	_streams["rifle"] = _noise(0.28, 18.0, 0.55, 0.9)
	_streams["smg"] = _noise(0.09, 40.0, 0.6, 0.6)
	_streams["shotgun"] = _noise(0.40, 12.0, 0.3, 1.0)
	_streams["hit"] = _tone(170.0, 120.0, 0.09, 0.6)
	_streams["kill"] = _tone(420.0, 90.0, 0.45, 0.7)
	_streams["ability"] = _tone(500.0, 1150.0, 0.18, 0.45)
	_streams["deny"] = _tone(220.0, 180.0, 0.16, 0.5)
	_streams["voice"] = _tone(900.0, 1200.0, 0.06, 0.35)
	_streams["start"] = _tone(660.0, 990.0, 0.35, 0.5)
	_streams["cast"] = _tone(420.0, 1320.0, 0.16, 0.48)
	_streams["cast_fast"] = _tone(680.0, 1580.0, 0.10, 0.38)
	_streams["cast_burst"] = _tone(280.0, 1040.0, 0.22, 0.58)
	# Combat feedback uses intentionally distinct timbres: a dull body impact,
	# a short airy miss, brittle glass, heavy wood, and a bright ready chime.
	_streams["impact_hit"] = _noise(0.14, 22.0, 0.30, 0.95)
	_streams["impact_miss"] = _tone(1050.0, 360.0, 0.075, 0.24)
	_streams["glass_break"] = _noise(0.34, 11.0, 0.82, 0.92)
	_streams["wood_break"] = _noise(0.30, 9.0, 0.24, 1.0)
	_streams["explosion"] = _noise(0.46, 7.0, 0.16, 1.0)
	_streams["cooldown_ready"] = _tone(580.0, 1280.0, 0.18, 0.38)
	for i in 18:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)

	intro_sound_player.stream = preload("res://assets/intro_sound.mp3")
	add_child(intro_sound_player)
	gameplay_sound_player.stream = preload("res://assets/gameplay_music.mp3")
	add_child(gameplay_sound_player)

func play(sound: String, volume_db := 0.0) -> void:
	match sound:
		"intro_sound":
			intro_sound_player.play()
			return
		"gameplay_music":
			gameplay_sound_player.play()
			return

	if not _streams.has(sound):
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _streams[sound]
	p.volume_db = volume_db
	p.play()


func _make(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


func _noise(length: float, decay: float, lowpass: float, gain: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		y += lowpass * (randf_range(-1.0, 1.0) - y)
		out[i] = y * exp(-t * decay) * gain * 1.6
	return _make(out)


func _tone(f0: float, f1: float, length: float, gain: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var k := float(i) / n
		phase += TAU * lerpf(f0, f1, k) / RATE
		var env := minf(1.0, k * 30.0) * (1.0 - k)
		out[i] = sin(phase) * env * gain
	return _make(out)
