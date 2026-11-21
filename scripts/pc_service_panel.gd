extends CanvasLayer
## Monitör / BIOS & Servis Paneli: BIOS ayarları (boot sırası, XMP, BIOS güncelleme),
## yazılım onarımı (format, antivirüs, sürücü, disk temizliği) ve alet tabanlı teşhis raporu.

const T := preload("res://scripts/ui_theme.gd")
const K := preload("res://scripts/ui_kit.gd")
const COMP := preload("res://scripts/compatibility.gd")

const HEX_CODES := {
	"nopower": "00", "cable_fp": "01", "cable_24pin": "02", "mobo": "05", "mobo_cap": "09",
	"cable_cpu": "10", "cpu": "12", "cpu_pins": "14", "ram": "53", "ram_unseated": "55",
	"cable_gpu": "92", "gpu": "96", "gpu_artifact": "98", "cable_sata": "A1", "ssd": "A2",
	"hdd_smart": "A4", "cooler": "C1", "fan": "C2", "cmos": "E0", "overheat": "F1",
}

var _root: Control
var _panel: Control
var _pc = null
var _subtitle: Label
var _tabs: Array[Button] = []
var _pages: Array[Control] = []
var _tab_idx := 0

# Dinamik içerik düğümleri
var _bios_box: VBoxContainer
var _sw_box: VBoxContainer
var _diag_box: VBoxContainer


func _ready() -> void:
	layer = 20
	var m := K.modal(self, 860, 0.75)
	_root = m[0]
	_panel = m[1]
	var vb: VBoxContainer = m[2]

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	vb.add_child(head)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 0)
	head.add_child(tv)
	K.label(tv, "BilgiBIOS & Servis Paneli", 30, T.ACCENT, "TitleLabel")
	_subtitle = K.label(tv, "", 14, T.MUTED, "MutedLabel")

	var tbar := HBoxContainer.new()
	tbar.add_theme_constant_override("separation", 8)
	vb.add_child(tbar)
	var tg := ButtonGroup.new()
	for spec in [[0, "BIOS Ayarları"], [1, "Yazılım & Servis"], [2, "Teşhis Raporu"]]:
		var idx: int = spec[0]
		var tb := K.button(tbar, spec[1], func(): _show_tab(idx), "SegButton", 15, Vector2(180, 38))
		tb.toggle_mode = true
		tb.button_group = tg
		_tabs.append(tb)

	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 410)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(stack)

	for i in 3:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.visible = i == 0
		stack.add_child(box)
		_pages.append(box)
	_bios_box = _pages[0]
	_sw_box = _pages[1]
	_diag_box = _pages[2]

	K.hsep(vb)
	var foot := HBoxContainer.new()
	vb.add_child(foot)
	K.label(foot, "Esc: kapat", 14, Color(1, 1, 1, 0.35), "MutedLabel").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	K.button(foot, "Kapat", close, "", 18, Vector2(140, 42))


func is_open() -> bool:
	return _root != null and _root.visible


func open(pc, tab := 0) -> void:
	if pc == null or pc.has_method("slot_open"):
		return
	_pc = pc
	_tab_idx = clampi(tab, 0, 2)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.ui_modal = true
	refresh()
	_show_tab(_tab_idx)
	K.open(_root, _panel)
	if not _tabs.is_empty():
		_tabs[_tab_idx].grab_focus()


func close() -> void:
	if not is_open():
		return
	K.close(_root, _panel)
	if Game.started and Game.phase == "day" and not Game.bench_active and not Game.paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if is_open():
		Game.ui_modal = true


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("ui_cancel"):
		Game.sfx.ui_back()
		close()
		get_viewport().set_input_as_handled()


func _show_tab(idx: int) -> void:
	_tab_idx = idx
	for i in _pages.size():
		_pages[i].visible = i == idx
		_tabs[i].set_pressed_no_signal(i == idx)
	refresh()


func refresh() -> void:
	if _pc == null or not is_instance_valid(_pc):
		return
	var mobo = _pc.part_in("mobo")
	var cpu = _pc.part_in("cpu")
	var psu = _pc.part_in("psu")
	var w: Dictionary = _pc.watt_summary()
	var pw_txt := "AÇIK" if _pc.powered else "KAPALI"
	_subtitle.text = "%s · Anakart: %s · CPU: %s · RAM: %d GB · Güç: %d/%dW [%s]" % [
		str(_pc.case_def.get("name", "PC Kasası")),
		mobo.display_name if mobo else "Yok",
		cpu.display_name if cpu else "Yok",
		_pc.total_ram(),
		int(w.get("draw", 0)),
		int(w.get("psu", 0)),
		pw_txt,
	]
	_build_bios()
	_build_sw()
	_build_diag()


func _clear(box: Control) -> void:
	for c in box.get_children():
		c.queue_free()


func _row_card(parent: Control, title: String, status: String, status_col: Color, btn_text: String, cb: Callable, req_ok := true, lock_reason := "") -> void:
	var ip := K.panel(parent, "InsetPanel")
	ip.add_theme_stylebox_override("panel", T.flat(Color(0, 0, 0, 0.28), 6, Color(1, 1, 1, 0.06), 1, Vector2(14, 10)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	ip.add_child(h)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	K.label(v, title, 17, T.TEXT, "BoldLabel")
	K.label(v, status, 14, status_col)
	if cb.is_valid():
		var b := K.button(h, btn_text if req_ok else lock_reason, cb, "PrimaryButton" if req_ok else "", 14, Vector2(210, 40))
		b.disabled = not req_ok
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _apply_sw_fix(code: String, ok_msg: String) -> void:
	if _pc == null or not is_instance_valid(_pc):
		return
	var was_powered: bool = _pc.powered
	if _pc.fix_sw_fault(code):
		Game.sfx.beep_scan()
		Game.msg(ok_msg, Color(0.5, 1.0, 0.5))
		if was_powered:
			_pc.power_button()
	else:
		Game.msg("Bu işlem için düzeltilecek bir sorun yok.", Color(0.7, 0.9, 1.0))
	refresh()


func _build_bios() -> void:
	_clear(_bios_box)
	var cmos = _pc.part_in("cmos")
	var cmos_ok: bool = cmos != null and not cmos.broken
	_row_card(_bios_box,
		"CMOS & Sistem Saati",
		"Pil Sağlam (+3.0V) — BIOS ayarları kalıcı." if cmos_ok else "CMOS pili eksik veya bitik! Saat 01.01.2001 — donanım pilini değiştirin.",
		T.GOOD if cmos_ok else T.BAD,
		"", Callable())

	var boot_bad: bool = _pc.has_sw_fault("sw_boot_order")
	_row_card(_bios_box,
		"Açılış Sırası (Boot Order)",
		"1. Ağ (PXE)  →  2. Sabit Disk (HATALI! Sistem açılmıyor)" if boot_bad else "1. SSD / NVMe İşletim Sistemi  →  2. USB (Sorunsuz)",
		T.ACCENT if boot_bad else T.GOOD,
		"Diski 1. Sıraya Al" if boot_bad else "Sorunsuz ✓",
		func(): _apply_sw_fix("sw_boot_order", "BIOS Boot sırası düzeltildi (SSD/NVMe 1. sıra)."),
		boot_bad, "Sorunsuz ✓")

	var xmp_off: bool = _pc.has_sw_fault("sw_xmp_off")
	_row_card(_bios_box,
		"RAM XMP / EXPO Profili",
		"KAPALI — Bellek temel hızda (2133 MHz) çalışıyor!" if xmp_off else "AÇIK — RAM tam hız profilinde çalışıyor.",
		T.ACCENT if xmp_off else T.GOOD,
		"XMP Profilini Aç" if xmp_off else "XMP Aktif ✓",
		func(): _apply_sw_fix("sw_xmp_off", "RAM XMP profili etkinleştirildi!"),
		xmp_off, "XMP Aktif ✓")

	var bios_old: bool = _pc.has_sw_fault("sw_bios_update")
	var has_usb := Game.has_upgrade("install_usb")
	var bios_can := bios_old and has_usb
	var bios_btn := "BIOS Güncelle (v3.2)" if bios_old else "Güncel (v3.2) ✓"
	var bios_lock := "Güncel ✓" if not bios_old else "Kurulum & BIOS USB Gerekli"
	_row_card(_bios_box,
		"Anakart BIOS Sürümü",
		"BilgiBIOS v1.0 (ESKİ) — Yeni nesil CPU desteği için güncelleme gerekli!" if bios_old else "BilgiBIOS v3.2 (Güncel)",
		T.BAD if bios_old else T.GOOD,
		bios_btn,
		func(): _apply_sw_fix("sw_bios_update", "Anakart BIOS'u v3.2 sürümüne güncellendi!"),
		bios_can, bios_lock)


func _build_sw() -> void:
	_clear(_sw_box)
	var os_bad: bool = _pc.has_sw_fault("sw_os_corrupt")
	var has_install := Game.has_upgrade("install_usb")
	_row_card(_sw_box,
		"İşletim Sistemi (BilgiOS 11)",
		"BOZUK — Mavi ekran (CRITICAL_PROCESS_DIED). Format gerekiyor." if os_bad else "Sağlıklı — Sistem dosyaları bütün.",
		T.BAD if os_bad else T.GOOD,
		"Format & BilgiOS Kur",
		func(): _apply_sw_fix("sw_os_corrupt", "Disk formatlandı ve BilgiOS 11 yeniden kuruldu!"),
		os_bad and has_install,
		"Sorunsuz ✓" if not os_bad else "Kurulum & BIOS USB Gerekli")

	var vir: bool = _pc.has_sw_fault("sw_virus")
	var has_av := Game.has_upgrade("antivirus_usb")
	_row_card(_sw_box,
		"Virüs & Zararlı Yazılım Koruması",
		"TEHDİT BULUNDU — Reklam yazılımı ve trojan sistemi yavaşlatıyor!" if vir else "Temiz — Zararlı yazılım saptanmadı.",
		T.BAD if vir else T.GOOD,
		"Virüsleri Temizle",
		func(): _apply_sw_fix("sw_virus", "Antivirüs taraması tamamlandı: zararlı yazılımlar temizlendi!"),
		vir and has_av,
		"Temiz ✓" if not vir else "Antivirüs USB Gerekli")

	var drv: bool = _pc.has_sw_fault("sw_driver")
	_row_card(_sw_box,
		"Aygıt Sürücüleri (GPU / Chipset)",
		"ÇAKIŞMA VAR (Kod 43) — Görüntü ve donanım sürücüleri hatalı." if drv else "Tüm sürücüler güncel ve düzgün çalışıyor.",
		T.ACCENT if drv else T.GOOD,
		"Sürücüleri Onar",
		func(): _apply_sw_fix("sw_driver", "Ekran ve yonga seti sürücüleri başarıyla onarıldı!"),
		drv, "Güncel ✓")

	var full: bool = _pc.has_sw_fault("sw_disk_full")
	_row_card(_sw_box,
		"C: Sürücüsü Depolama Alanı",
		"DİSK DOLU (%99) — Temp ve önbellek dosyaları sistemi kilitliyor!" if full else "Boş alan yeterli (Sistem %42 dolu).",
		T.ACCENT if full else T.GOOD,
		"Disk Temizliği Yap",
		func(): _apply_sw_fix("sw_disk_full", "Gereksiz dosyalar silindi, C: sürücüsünde yer açıldı!"),
		full, "Alan Yeterli ✓")


func _diag_line(title: String, detail: String, col := T.TEXT) -> void:
	var ip := K.panel(_diag_box, "InsetPanel")
	ip.add_theme_stylebox_override("panel", T.flat(Color(0, 0, 0, 0.25), 6, Color(1, 1, 1, 0.05), 1, Vector2(12, 8)))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	ip.add_child(v)
	K.label(v, title, 15, T.INFO, "BoldLabel")
	var dl := K.label(v, detail, 14, col)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _build_diag() -> void:
	_clear(_diag_box)
	# 1. Temel fiziksel kontrol (her zaman açık)
	var loose_cables: Array[String] = []
	for cid in _pc.cables:
		if str(_pc.cables[cid]) != "ok":
			loose_cables.append(str(_pc.CABLE_NAMES.get(cid, cid)))
	var miss_screws: String = _pc.missing_screws_text()
	var compat: Dictionary = COMP.check_system(_pc.case_state())
	var basic_parts: Array[String] = []
	basic_parts.append("Gevşek Kablo: %s" % (", ".join(loose_cables) if not loose_cables.is_empty() else "Yok"))
	basic_parts.append("Eksik Vida: %s" % (miss_screws if miss_screws != "" else "Yok"))
	basic_parts.append("Uyumluluk: %s" % ("Sorunsuz" if compat.ok else "%d çakışma!" % compat.issues.size()))
	_diag_line("Temel Kontrol (Gözle & Uyumluluk)", " · ".join(basic_parts),
		T.ACCENT if (not loose_cables.is_empty() or miss_screws != "" or not compat.ok) else T.GOOD)

	# 2. PSU Test Cihazı
	if Game.has_upgrade("psu_tester"):
		var psu = _pc.part_in("psu")
		var w: Dictionary = _pc.watt_summary()
		var p_txt := "PSU takılı değil!"
		var p_col := T.BAD
		if psu != null and psu.broken:
			p_txt = "%s: ARIZALI (+12V / +5V yok)" % psu.display_name
		elif psu != null:
			var need_ok: bool = int(w.psu) >= int(w.recommended)
			p_txt = "%s: +12V/+5V OK · Yük %dW / %dW (Önerilen %dW+)" % [psu.display_name, w.draw, w.psu, w.recommended]
			p_col = T.GOOD if (bool(w.ok) and need_ok) else T.ACCENT
		_diag_line("PSU Test Cihazı", p_txt, p_col)
	else:
		_diag_line("PSU Test Cihazı [Kilitli]", "Açmak için Dükkân > Geliştirmeler'den PSU Test Cihazı satın alın.", T.MUTED)

	# 3. Dijital Multimetre
	if Game.has_upgrade("multimeter"):
		var bad_hw: Array[String] = []
		for p in _pc.installed_parts():
			if p.broken:
				bad_hw.append("%s (ARIZALI)" % p.display_name)
			elif p.bad_caps:
				bad_hw.append("%s (Şişmiş Kondansatör)" % p.display_name)
			elif p.bent_pins:
				bad_hw.append("%s (Eğik Pin)" % p.display_name)
			elif p.vram_bad:
				bad_hw.append("%s (VRAM Hatası)" % p.display_name)
		_diag_line("Dijital Multimetre",
			"Arızalı hatlar: %s" % ", ".join(bad_hw) if not bad_hw.is_empty() else "Tüm donanım voltaj ve kondansatör hatları normal.",
			T.BAD if not bad_hw.is_empty() else T.GOOD)
	else:
		_diag_line("Dijital Multimetre [Kilitli]", "Açmak için Dükkân > Geliştirmeler'den Dijital Multimetre satın alın.", T.MUTED)

	# 4. POST Teşhis Kartı
	if Game.has_upgrade("post_card"):
		var issues: Array = _pc.diagnose_all()
		if issues.is_empty():
			_diag_line("POST Teşhis Kartı [AA]", "Tüm POST adımları temiz — arıza kodu yok.", T.GOOD)
		else:
			var codes: Array[String] = []
			for ic in issues:
				codes.append("[%s] %s" % [HEX_CODES.get(str(ic), "FF"), str(ic)])
			_diag_line("POST Teşhis Kartı (%d kod)" % issues.size(), ", ".join(codes), T.ACCENT)
	else:
		_diag_line("POST Teşhis Kartı [Kilitli]", "Debug LED olmayan anakartlarda kod okumak için POST Teşhis Kartı alın.", T.MUTED)

	# 5. Termal Kamera
	if Game.has_upgrade("thermal_cam"):
		var cpu = _pc.part_in("cpu")
		var cooler = _pc.part_in("cooler")
		var paste_txt := "Kuru!" if (cpu != null and not cpu.paste_ok) else "Taze"
		var fan_txt := "OK"
		if cooler == null or cooler.broken:
			fan_txt = "Soğutucu arızalı/yok"
		elif (_pc.part_in("fan1") != null and _pc.part_in("fan1").broken) or (_pc.part_in("fan2") != null and _pc.part_in("fan2").broken):
			fan_txt = "Kasa fanı bozuk"
		var t_warn: bool = _pc.dust > 0.5 or paste_txt == "Kuru!" or fan_txt != "OK"
		_diag_line("Termal Kamera",
			"CPU %.0f°C · Toz: %%%d · Termal Macun: %s · Fanlar: %s" % [_pc.cpu_temp, roundi(_pc.dust * 100.0), paste_txt, fan_txt],
			T.ACCENT if t_warn else T.GOOD)
	else:
		_diag_line("Termal Kamera [Kilitli]", "Sıcaklık ve soğutma taraması için Termal Kamera satın alın.", T.MUTED)

	# 6. RAM Test USB & SMART USB
	if Game.has_upgrade("ram_usb"):
		var r_list: Array[String] = []
		for rn in ["ram1", "ram2", "ram3", "ram4"]:
			var rp = _pc.part_in(rn)
			if rp == null:
				continue
			r_list.append("%s: %s" % [rn.to_upper(), "BOZUK" if rp.broken else ("OTURMAMIŞ" if not rp.seated else "OK")])
		var xmp_s := " · XMP KAPALI" if _pc.has_sw_fault("sw_xmp_off") else " · XMP Açık"
		var r_bad: bool = r_list.is_empty() or _pc.has_sw_fault("sw_xmp_off") or r_list.any(func(s): return not s.ends_with("OK"))
		_diag_line("RAM Test USB", (", ".join(r_list) if not r_list.is_empty() else "RAM yok") + xmp_s, T.ACCENT if r_bad else T.GOOD)
	else:
		_diag_line("RAM Test USB [Kilitli]", "Yuva testi ve XMP raporu için RAM Test USB satın alın.", T.MUTED)

	if Game.has_upgrade("smart_usb"):
		var d_list: Array[String] = []
		var d_bad: bool = _pc.has_sw_fault("sw_disk_full")
		for sn in ["m2", "ssd"]:
			var sp = _pc.part_in(sn)
			if sp == null:
				continue
			if sp.broken:
				d_list.append("%s: YANIT YOK" % sn.to_upper())
				d_bad = true
			else:
				d_list.append("%s: %%%d sağlık" % [sn.to_upper(), int(sp.health)])
				if sp.health < 35:
					d_bad = true
		var full_s := " · DİSK DOLU (%99)" if _pc.has_sw_fault("sw_disk_full") else ""
		_diag_line("Disk SMART USB", (", ".join(d_list) if not d_list.is_empty() else "Depolama yok") + full_s, T.BAD if d_bad else T.GOOD)
	else:
		_diag_line("Disk SMART USB [Kilitli]", "Disk sağlık yüzdesi ve bad sector ölçümü için Disk SMART USB alın.", T.MUTED)
