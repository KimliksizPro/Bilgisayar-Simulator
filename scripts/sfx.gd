extends Node
## Kodla üretilen basit sesler (bip, tık, para sesi). Dışarıdan ses dosyası gerekmez.

const RATE := 22050

var _players: Array[AudioStreamPlayer] = []
var _cache := {}


func _ready() -> void:
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func tone(freq: float, dur: float, vol := 0.25, square := false) -> AudioStreamWAV:
	var key := "%s|%s|%s|%s" % [freq, dur, vol, square]
	if _cache.has(key):
		return _cache[key]
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var env: float = min(1.0, i / (RATE * 0.004)) * min(1.0, (n - i) / (RATE * 0.012))
		var s := sin(TAU * freq * t)
		if square:
			s = 0.6 if s > 0.0 else -0.6
		data.encode_s16(i * 2, int(clamp(s * vol * env, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	_cache[key] = w
	return w


## Döngüsel fan uğultusu (filtrelenmiş gürültü).
func hum() -> AudioStreamWAV:
	if _cache.has("hum"):
		return _cache["hum"]
	var n := RATE
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var v := 0.0
	for i in n:
		v = v * 0.97 + rng.randf_range(-1.0, 1.0) * 0.03
		var s := v * 2.5 + sin(TAU * 110.0 * i / RATE) * 0.02
		data.encode_s16(i * 2, int(clamp(s, -1.0, 1.0) * 32767.0 * 0.5))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	_cache["hum"] = w
	return w


func play(stream: AudioStream, pitch := 1.0) -> void:
	for p in _players:
		if not p.playing:
			p.stream = stream
			p.pitch_scale = pitch
			p.play()
			return


func click() -> void:
	play(tone(1800.0, 0.03, 0.2, true))


func pickup() -> void:
	play(tone(600.0, 0.05, 0.15))


func error() -> void:
	play(tone(180.0, 0.25, 0.25, true))


func coin() -> void:
	play(tone(1320.0, 0.08, 0.2))
	await get_tree().create_timer(0.09).timeout
	play(tone(1760.0, 0.18, 0.2))


## pattern: saniye cinsinden bip süreleri.
func beeps(pattern: Array) -> void:
	for d in pattern:
		play(tone(950.0, d, 0.22, true))
		await get_tree().create_timer(d + 0.16).timeout
