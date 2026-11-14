extends Node
## Kodla üretilen sakin fon müziği (Am - F - C - G pedi + hafif arpej). "Music" kanalından çalar.

const RATE := 11025
const CHORD_SEC := 3.2
const CHORDS := [
	[220.0, 261.63, 329.63],   # Am
	[174.61, 220.0, 261.63],   # F
	[196.0, 261.63, 329.63],   # C
	[196.0, 246.94, 293.66],   # G
]
var player: AudioStreamPlayer
var _stream: AudioStreamWAV
var _task := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = AudioStreamPlayer.new()
	player.bus = "Music"
	player.volume_db = -6.0
	add_child(player)
	_task = WorkerThreadPool.add_task(_generate)
	set_process(true)


func _process(_d: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		player.stream = _stream
		player.play()
		set_process(false)


func _generate() -> void:
	var total := CHORD_SEC * CHORDS.size()
	var n := int(RATE * total)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for k in CHORDS.size():
			var lt := fposmod(t - k * CHORD_SEC, total)
			if lt < CHORD_SEC * 1.5:
				var w := sin(PI * lt / (CHORD_SEC * 1.5))
				w *= w
				for f in CHORDS[k]:
					s += w * (sin(TAU * f * 0.5 * t) * 0.5 + sin(TAU * f * t + sin(TAU * 0.2 * t)) * 0.18)
			# arpej: her 0.8 sn'de bir yumuşak nota
			var at := fposmod(t - k * CHORD_SEC, 0.8)
			var idx := int((fposmod(t - k * CHORD_SEC, total)) / 0.8) % 3
			if lt < CHORD_SEC:
				var f2: float = CHORDS[k][idx] * 2.0
				s += exp(-at * 5.0) * sin(TAU * f2 * t) * 0.16 * minf(1.0, at * 80.0)
		data.encode_s16(i * 2, int(clampf(s * 0.16, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	_stream = w
