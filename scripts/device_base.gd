extends Node3D
## Laptop ve telefonun ortak temeli: yuvalar, servis kapağı durumu, güç, kendi küçük ekranı (SubViewport),
## parça doldurma ve teslim kontrolü. job_manager bunu bir bilgisayar kasası gibi kullanır
## (fill, diagnose, power_off, panel_open, part_in); laptop_device.gd ve phone_device.gd türetir.

const MU := preload("res://scripts/mesh_util.gd")
const PM := preload("res://scripts/part_models.gd")
const DP := preload("res://scripts/device_parts.gd")
const DSLOT := preload("res://scripts/device_slot.gd")
const PART := preload("res://scripts/part.gd")

var slots := {}
var monitor = null          # job_manager atar; cihaz kendi ekranını kullanır
var powered := false
var panel_open := false     # servis modu: laptopta alt kapak, telefonda ekran açık
var screen_state := "off"   # ekranda ne görünüyor (test ve teşhis için)
var device_name := "Cihaz"
var dust := 0.0
var liquid_damage := false
var hinge_loose := false
var sw_fault := false

var vp: SubViewport
var scr_root: Control
var scr_quad: MeshInstance3D
var _token := 0
var _anim: Tween


# ---------------------------------------------------------------- yuvalar

## Yuva ekler. rot: derece. Parça yuvanın yerel eksenlerine oturur (+Y parça üstü).
func _add_slot(slot_name: String, type: String, parent: Node3D, pos: Vector3, rot := Vector3.ZERO):
	var s = DSLOT.new()
	s.name = slot_name
	MU.no_merge(s)
	s.position = pos
	s.rotation_degrees = rot
	parent.add_child(s)
	s.setup(type, self)
	slots[slot_name] = s
	return s


## Yuva o an erişilebilir mi? (türetilen sınıflar ezer)
func slot_open(_s) -> bool:
	return panel_open and not powered


func fill(parts: Array) -> void:
	for p in parts:
		if p is Dictionary:
			if p.has("flags"):
				var fl: Dictionary = p.flags
				dust = float(fl.get("dust", dust))
				liquid_damage = bool(fl.get("liquid_damage", liquid_damage))
				hinge_loose = bool(fl.get("hinge_loose", hinge_loose))
				sw_fault = bool(fl.get("sw_fault", sw_fault))
			else:
				var sn := str(p.get("slot", ""))
				if slots.has(sn) and slots[sn].part == null:
					var sku_id := str(p.get("sku", ""))
					var part = PART.new().setup_sku(sku_id, bool(p.get("broken", false))) if sku_id != "" else PART.new().setup(str(p.get("type", "")), int(p.get("tier", 1)), bool(p.get("broken", false)))
					if bool(p.get("broken", false)):
						DP.add_damage(part, part.part_type)
					slots[sn].install(part)
			continue
		var part = PART.new().setup(p[1], p[2], p[3])
		if p[3]:
			DP.add_damage(part, p[1])
		slots[p[0]].install(part)
	_update_visuals()


func part_in(slot_name: String):
	return slots[slot_name].part


func installed_parts() -> Array:
	var out := []
	for s in slots.values():
		if s.part:
			out.append(s.part)
	return out


func _ok(slot_name: String) -> bool:
	var p = part_in(slot_name)
	return p != null and not p.broken


func on_parts_changed() -> void:
	if powered:
		power_off()
		Game.msg("Parça değişince %s kapandı." % device_name.to_lower())
	_update_visuals()


func _update_visuals() -> void:
	pass


# ---------------------------------------------------------------- aletler (kasa aletleri burada işe yaramaz)

func tool_hint(_tool, _slot) -> String:
	return "Bu alet burada işe yaramaz"


func tool_use(_player, _tool, _slot) -> void:
	Game.msg("Bu aleti %s için kullanamazsın." % device_name.to_lower(), Color(1, 0.8, 0.4))


func get_hint(player) -> String:
	if player.held and player.held.is_tool():
		return tool_hint(player.held, null)
	return ""


func interact(player) -> void:
	if player.held and player.held.is_tool():
		tool_use(player, player.held, null)


# ---------------------------------------------------------------- teşhis / teslim

func diagnose_all() -> Array[String]:
	return []


func diagnose() -> String:
	var all := diagnose_all()
	return all[0] if not all.is_empty() else "ok"


## Teslimde müşteri itirazı ("" = sorun yok).
func problem() -> String:
	var code := diagnose()
	if code != "ok":
		return _fault_line(code)
	if panel_open:
		return _open_line()
	return ""


func _fault_line(_code: String) -> String:
	return "Usta bu hâlâ düzgün çalışmıyor ki!"


func _open_line() -> String:
	return "Kapağı kapatmadan mı vereceksin usta?"


func power_off() -> void:
	powered = false
	_token += 1
	_show("off")


# ---------------------------------------------------------------- küçük ekran

## Cihazın kendi ekranı: SubViewport + üzerine çizildiği quad (+Y'ye bakar, görüntü üstü -Z).
func _make_screen(px: Vector2i, parent: Node3D, size: Vector2, pos: Vector3) -> void:
	vp = SubViewport.new()
	vp.size = px
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	scr_root = Control.new()
	scr_root.size = Vector2(px)
	vp.add_child(scr_root)
	var q := QuadMesh.new()
	q.size = size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = vp.get_texture()
	scr_quad = MeshInstance3D.new()
	scr_quad.mesh = q
	scr_quad.material_override = m
	scr_quad.position = pos
	scr_quad.rotation_degrees = Vector3(-90, 0, 0)
	scr_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	MU.no_merge(scr_quad)
	parent.add_child(scr_quad)
	scr_quad.visible = false


## Ekran içeriğini kurar (türetilen sınıf _paint ile çizer).
func _show(state: String) -> void:
	screen_state = state
	if scr_root == null:
		return
	for c in scr_root.get_children():
		c.queue_free()
	scr_quad.visible = state != "off"
	if state != "off":
		_paint(state)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _paint(_state: String) -> void:
	pass


## Açılış animasyonu: logo, sonra asıl durum. Arada kapatılırsa iptal.
func _boot_then(state: String, wait := 0.9) -> void:
	_show("boot")
	var my := _token
	await get_tree().create_timer(wait).timeout
	if my == _token and powered:
		_show(state)


# --- 2D çizim yardımcıları
func _rect(pos: Vector2, size: Vector2, col: Color, parent: Control = null) -> ColorRect:
	var r := ColorRect.new()
	r.position = pos
	r.size = size
	r.color = col
	(parent if parent else scr_root).add_child(r)
	return r


func _txt(text: String, pos: Vector2, size: Vector2, fsize: int, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	scr_root.add_child(l)
	return l


func _wallpaper(a: Color, b: Color) -> void:
	var grad := Gradient.new()
	grad.set_color(0, a)
	grad.set_color(1, b)
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 1)
	var w := TextureRect.new()
	w.texture = gt
	w.size = scr_root.size
	w.stretch_mode = TextureRect.STRETCH_SCALE
	w.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scr_root.add_child(w)


## Kırık panelin bozuk görüntüsü: renkli dikey şeritler ve kara lekeler.
func _glitch() -> void:
	var s := scr_root.size
	_rect(Vector2.ZERO, s, Color(0.05, 0.05, 0.08))
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var x := 0.0
	while x < s.x:
		var w := rng.randf_range(2, s.x * 0.06)
		var cols := [Color(1, 0.1, 0.8), Color(0.1, 1, 0.3), Color(0.2, 0.4, 1), Color(1, 1, 1), Color(0.02, 0.02, 0.02)]
		_rect(Vector2(x, 0), Vector2(w, s.y), cols[rng.randi() % cols.size()] * Color(1, 1, 1, rng.randf_range(0.3, 0.9)))
		x += w + rng.randf_range(0, s.x * 0.08)
	for i in 4:
		_rect(Vector2(rng.randf_range(0, s.x * 0.7), rng.randf_range(0, s.y * 0.7)), Vector2(rng.randf_range(20, s.x * 0.4), rng.randf_range(10, s.y * 0.3)), Color(0, 0, 0, 0.95))


## Servis kapağı animasyonu için tek tween (önceki yarıda kalırsa kesilir).
func _new_anim() -> Tween:
	if _anim and _anim.is_valid():
		_anim.kill()
	_anim = create_tween()
	return _anim
