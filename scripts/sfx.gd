extends Node
## Kodla üretilen basit sesler (bip, tık, para sesi). Dışarıdan ses dosyası gerekmez.

const RATE := 22050

var _players: Array[AudioStreamPlayer] = []
var _cache := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # menü sesleri duraklatmada da çalsın
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
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


## Basınçlı hava tıslaması (filtrelenmiş beyaz gürültü).
func hiss() -> void:
	if not _cache.has("hiss"):
		var n := int(RATE * 0.7)
		var data := PackedByteArray()
		data.resize(n * 2)
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var lp := 0.0
		for i in n:
			var env: float = min(1.0, i / (RATE * 0.03)) * pow(1.0 - float(i) / n, 1.5)
			var w := rng.randf_range(-1.0, 1.0)
			lp = lp * 0.35 + w * 0.65
			data.encode_s16(i * 2, int(clamp((w - lp * 0.3) * 0.3 * env, -1.0, 1.0) * 32767.0))
		var ws := AudioStreamWAV.new()
		ws.format = AudioStreamWAV.FORMAT_16_BITS
		ws.mix_rate = RATE
		ws.data = data
		_cache["hiss"] = ws
	play(_cache["hiss"])


## Macun sıkma sesi.
func squish() -> void:
	play(tone(260.0, 0.07, 0.18))
	await get_tree().create_timer(0.06).timeout
	play(tone(180.0, 0.1, 0.15))


## Kısa metalik cırcır/vida sesi.
func screw() -> void:
	play(tone(1450.0, 0.025, 0.16, true))
	await get_tree().create_timer(0.045).timeout
	play(tone(1950.0, 0.028, 0.14, true))


## Teşhis aleti tarama bipi.
func beep_scan() -> void:
	play(tone(1200.0, 0.05, 0.15))
	await get_tree().create_timer(0.06).timeout
	play(tone(1680.0, 0.08, 0.16))


## IPA temizlik spreyi fıs sesi.
func spray() -> void:
	play(tone(2800.0, 0.06, 0.08, false))
	hiss()


func play(stream: AudioStream, pitch := 1.0) -> void:
	for p in _players:
		if not p.playing:
			p.stream = stream
			p.pitch_scale = pitch
			p.play()
			return


func click() -> void:
	play(tone(1800.0, 0.03, 0.2, true))


## Menü sesleri: hafif üstüne gelme tıkı, tıklama, geri.
func ui_hover() -> void:
	play(tone(1500.0, 0.025, 0.05))


func ui_click() -> void:
	play(tone(660.0, 0.04, 0.16))
	await get_tree().create_timer(0.04, true).timeout
	play(tone(990.0, 0.07, 0.14))


func ui_back() -> void:
	play(tone(520.0, 0.07, 0.14))


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
