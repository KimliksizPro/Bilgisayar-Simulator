extends Node
## Oyun ayarları (autoload): user://settings.cfg dosyasına kaydedilir, açılışta uygulanır.

signal changed(key: String)

const PATH := "user://settings.cfg"
const QUALITY_NAMES := ["Düşük", "Orta", "Yüksek"]
const WINDOW_NAMES := ["Pencere", "Tam ekran", "Kenarsız"]
const FPS_CAPS := [0, 30, 60, 120, 144]

# anahtar -> [bölüm, varsayılan]
const DEFS := {
	"quality": ["grafik", 2],
	"window_mode": ["grafik", 0],
	"vsync": ["grafik", true],
	"fps_cap": ["grafik", 0],
	"res_scale": ["grafik", 1.0],
	"fsr": ["grafik", false],
	"fov": ["grafik", 72.0],
	"master": ["ses", 0.8],
	"sfx": ["ses", 1.0],
	"music": ["ses", 0.5],
	"sensitivity": ["kontrol", 1.0],
	"invert_y": ["kontrol", false],
	"show_fps": ["oyun", false],
	"show_hints": ["oyun", true],
	"tips_seen": ["oyun", []],
}

var quality := 2
var window_mode := 0
var vsync := true
var fps_cap := 0
var res_scale := 1.0
var fsr := false
var fov := 72.0
var master := 0.8
var sfx := 1.0
var music := 0.5
var sensitivity := 1.0
var invert_y := false
var show_fps := false
var show_hints := true
var tips_seen: Array = []

var _save_timer: SceneTreeTimer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	load_settings()
	apply_all()


func _setup_buses() -> void:
	for n in ["SFX", "Music"]:
		if AudioServer.get_bus_index(n) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, n)
			AudioServer.set_bus_send(i, "Master")


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for k in DEFS:
		var d: Array = DEFS[k]
		var v = cf.get_value(d[0], k, d[1])
		if typeof(v) == typeof(d[1]) or (typeof(d[1]) == TYPE_FLOAT and typeof(v) == TYPE_INT):
			set(k, v)
	quality = clampi(quality, 0, 2)
	window_mode = clampi(window_mode, 0, 2)
	res_scale = clampf(res_scale, 0.5, 1.0)
	fov = clampf(fov, 60.0, 100.0)


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in DEFS:
		cf.set_value(DEFS[k][0], k, get(k))
	cf.save(PATH)


## Bir ayarı değiştirir, uygular ve (gecikmeli) kaydeder.
func set_opt(key: String, value) -> void:
	set(key, value)
	_apply(key)
	changed.emit(key)
	if _save_timer == null:
		_save_timer = get_tree().create_timer(0.6, true)
		_save_timer.timeout.connect(func():
			_save_timer = null
			save_settings())


func reset_defaults() -> void:
	for k in DEFS:
		if k == "tips_seen":
			continue
		set_opt(k, DEFS[k][1])


func apply_all() -> void:
	for k in DEFS:
		_apply(k)


func _apply(key: String) -> void:
	var headless := DisplayServer.get_name() == "headless"
	match key:
		"window_mode":
			if headless:
				return
			var cur := DisplayServer.window_get_mode()
			match window_mode:
				0:
					if cur != DisplayServer.WINDOW_MODE_WINDOWED:
						DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				1:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
				2:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
		"fps_cap":
			Engine.max_fps = fps_cap
		"res_scale", "fsr":
			var vp := get_tree().root
			vp.scaling_3d_scale = res_scale
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if (fsr and res_scale < 0.999) else Viewport.SCALING_3D_MODE_BILINEAR
		"quality":
			get_tree().root.msaa_3d = Viewport.MSAA_DISABLED if quality == 0 else Viewport.MSAA_2X
		"master":
			_set_bus("Master", master)
		"sfx":
			_set_bus("SFX", sfx)
		"music":
			_set_bus("Music", music)


func _set_bus(name: String, lin: float) -> void:
	var i := AudioServer.get_bus_index(name)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, lin <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(lin, 0.001)))


func mark_tip_seen(id: String) -> void:
	if not tips_seen.has(id):
		tips_seen.append(id)
		save_settings()


func reset_tips() -> void:
	tips_seen = []
	save_settings()
