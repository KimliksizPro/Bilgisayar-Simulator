extends "res://scripts/customer.gd"
## Dükkân çalışanı: müşteri modelinin önlüklü hâli. Elinde parça taşıyabilir (tezgah satışı için
## job_manager._try_sell'e "oyuncu" gibi verilir: held / release_held).

const SD := preload("res://scripts/staff_data.gd")

var info: Dictionary = {}     # Game.staff kaydı
var held = null               # elindeki parça (satış)
var home := Vector3.ZERO
var home_face := 0.0
# görev durumu (staff.gd yönetir)
var task := "idle"            # idle / serve / sell / cargo / repair / leave
var react_t := 0.0
var work := 0.0               # tamirde geçen oyun saati
var need := 0.0               # tamirin süreceği oyun saati
var pc = null
var plan := {}
var reserved: Array = []      # stoktan ayrılmış parçalar [tür, seviye]
var at_desk := false
var noted = null              # "stokta yok" dediği müşteri (tekrar etmesin)
var _say_t := 0.0


func setup_staff(d: Dictionary, hint_fn: Callable, action: Callable) -> void:
	info = d
	build(hint_fn, action)
	speed = 1.5
	_dress()
	# oyuncuyu fiziksel olarak engellemesin: sadece bakış ışını (katman 2) çarpar
	for c in get_children():
		if c is StaticBody3D:
			c.collision_layer = 2


## İş önlüğü: rol rengi, askılar, cep ve göğüste rol yazısı.
func _dress() -> void:
	var col: Color = SD.ROLES.get(info.get("role", "tezgahtar"), SD.ROLES.tezgahtar).color
	var apron := MU.mat(col, 0, 0.8)
	var dark := MU.mat(col.darkened(0.35), 0, 0.8)
	MU.rbox(self, Vector3(0.36, 0.56, 0.02), Vector3(0, 1.07, 0.125), apron, 0.008)
	for x in [-0.13, 0.13]:
		MU.rbox(self, Vector3(0.045, 0.2, 0.02), Vector3(x, 1.42, 0.12), apron, 0.006)
	MU.rbox(self, Vector3(0.16, 0.09, 0.006), Vector3(0.06, 0.95, 0.138), dark, 0.003)
	if info.get("role", "") == "teknisyen":
		# cepte tornavida
		MU.cyl(self, 0.008, 0.08, Vector3(0.1, 1.0, 0.14), MU.mat(Color(0.9, 0.75, 0.1), 0, 0.4))
	var tag := MU.label(self, SD.role_name(info.get("role", "")).to_upper(), Vector3(0, 1.25, 0.137), 40, Color(1, 1, 1), Vector3.ZERO, 0.0009)
	tag.double_sided = false
	tag.outline_size = 0


func say_for(text: String, sec := 3.5, angry := false) -> void:
	say(text, angry)
	_say_t = sec


## Elinde parçayla yürür (satış için raftan aldığı).
func carry(p) -> void:
	held = p
	p.freeze = true
	p.collision_layer = 0
	p.collision_mask = 0
	add_child(p)
	p.position = Vector3(0, 1.0, 0.3)
	p.rotation_degrees = Vector3(0, 90, 0)


func release_held():
	var p = held
	held = null
	return p


func _process(delta: float) -> void:
	super(delta)
	if _say_t > 0.0:
		_say_t -= delta
		if _say_t <= 0.0:
			say("")
	# tamirde çalışırken kollar kıpırdar
	if task == "repair" and at_desk:
		arms[0].rotation.x = -0.9 + sin(_t * 6.0) * 0.25
		arms[1].rotation.x = -0.9 + cos(_t * 5.0) * 0.25
