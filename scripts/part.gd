extends RigidBody3D
## Alınıp takılabilen bilgisayar parçası.

const PM := preload("res://scripts/part_models.gd")
const MU := preload("res://scripts/mesh_util.gd")

# Elde tutuş pozları data/parts.json'da (tür: "hold", SKU ezmesi: "hold"); bkz. DB.parts.hold_pose_id

var sku := ""         # kanonik SKU kimliği (örn. "ram_ddr4_16g_rgb")
var part_type := ""
var tier := 1
var broken := false
var health := 100     # parça sağlığı (0..100, özellikle HDD/SMART ve Faz 3 için)
var paste_ok := true  # CPU için: termal macun sağlam mı
var cheap := false    # muadil (ucuz) parça: garantide bozulma riski taşır
var display_name := ""
var slot = null
var rotors: Array = []
var rgb_mats: Array = []


## Kanonik kurulum: SKU kimliği ile parçayı oluşturur.
func setup_sku(id: String, is_broken := false):
	var resolved: String = DB.parts.resolve_id(id)
	var d: PartDef = DB.parts.get_def(resolved)
	sku = d.id if d else resolved
	part_type = d.category if d else ""
	tier = d.tier if d else 1
	broken = is_broken
	display_name = PM.display_name_sku(sku)
	var built := PM.build_sku(sku)
	add_child(built.node)
	rotors = built.rotors
	rgb_mats = built.rgb
	var info: Dictionary = PM.info(part_type)
	if not info.is_empty():
		MU.add_box_shape(self, info.size, info.center)
	if broken and (part_type == "psu" or part_type == "gpu") and randf() < 0.35:
		_burn_mark()
	mass = 0.5
	continuous_cd = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	collision_layer = 2
	collision_mask = 1
	return self


## Geriye dönük kurulum sarmalayıcısı: (tür, seviye) -> setup_sku.
func setup(type: String, t := 1, is_broken := false):
	var id: String = DB.parts.id_for(type, t)
	if not id.is_empty():
		return setup_sku(id, is_broken)
	part_type = type
	tier = t
	sku = "%s:%d" % [type, t]
	broken = is_broken
	display_name = PM.display_name(type, t)
	var built := PM.build(type, t)
	add_child(built.node)
	rotors = built.rotors
	rgb_mats = built.rgb
	var info: Dictionary = PM.info(type)
	if not info.is_empty():
		MU.add_box_shape(self, info.size, info.center)
	if broken and (type == "psu" or type == "gpu") and randf() < 0.35:
		_burn_mark()
	mass = 0.5
	continuous_cd = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	collision_layer = 2
	collision_mask = 1
	return self


## Parçanın PartDef tanımı; yoksa null.
func def() -> PartDef:
	if not sku.is_empty():
		return DB.parts.get_def(sku)
	return DB.parts.def_for(part_type, tier)


func is_tool() -> bool:
	return false


## Elde tutulurken merkez ve dönüş (player.pick_up kullanır).
func hold_center() -> Vector3:
	return PM.info(part_type).center


func hold_euler() -> Vector3:
	return DB.parts.hold_pose_id(sku)[0] if not sku.is_empty() else DB.parts.hold_pose(part_type, tier)[0]


## Elde tutuş kaydırması: büyük parçalar uzağa/aşağıya, küçükler yakına.
func hold_offset() -> Vector3:
	return DB.parts.hold_pose_id(sku)[1] if not sku.is_empty() else DB.parts.hold_pose(part_type, tier)[1]


## Bazı bozuk parçalarda küçük yanık izi: ipucu ama her bozukta yok.
func _burn_mark() -> void:
	var dark := MU.mat(Color(0.03, 0.02, 0.02), 0, 0.9)
	var rim := MU.mat(Color(0.25, 0.14, 0.06), 0, 0.9)
	var p := Vector3(0.0766, -0.022, 0.035) if part_type == "psu" else Vector3(0.1085, -0.012, 0.072)
	var s := MU.sphere(self, 0.011, p, rim, Vector3(0.12, 1, 1.2))
	var d := MU.sphere(self, 0.007, p + Vector3(0.0004, 0, 0.001), dark, Vector3(0.12, 1, 1.2))
	s.name = "Burn"
	d.name = "BurnCore"


func get_hint(player) -> String:
	if slot:
		return slot.get_hint(player)
	if player.held == null:
		return "Elin dolu (cihaz taşıyorsun)" if Game.is_carrying() else "Al: %s  [E]" % display_name
	return ""


func interact(player) -> void:
	if slot:
		slot.interact(player)
	elif player.held == null and not Game.is_carrying():
		player.pick_up(self)


func install_into(s) -> void:
	slot = s
	# takılı parça cihazla birlikte hareket etmeli: kinematik dondurmada fizik motoru eski
	# dünya konumunu geri yazıp parçayı geride bırakıyordu (taşırken havada kalma hatası)
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	collision_layer = 2
	collision_mask = 0
	if get_parent():
		reparent(s, false)
	else:
		s.add_child(self)
	transform = Transform3D.IDENTITY


func value() -> int:
	var base := PM.price_sku(sku) if not sku.is_empty() else PM.price(part_type, tier)
	return roundi(base * (Game.CHEAP_FACTOR if cheap else 1.0))


## Muadil parça yap: ismine etiket eklenir, üstüne turuncu bir sticker yapışır.
func make_cheap() -> void:
	cheap = true
	var base_name := PM.display_name_sku(sku) if not sku.is_empty() else PM.display_name(part_type, tier)
	display_name = base_name + " (muadil)"
	var info: Dictionary = PM.info(part_type)
	var sz: Vector3 = info.size
	MU.box(self, Vector3(sz.x * 0.25, 0.002, sz.z * 0.25), info.center + Vector3(0, sz.y * 0.5 + 0.001, 0), MU.mat(Color(1.0, 0.55, 0.1), 0, 0.6))
