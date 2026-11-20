class_name Compatibility
extends RefCounted
## Saf, durumsuz PC parça uyumluluk, güç (watt) ve görüntü doğrulama motoru.
## Tezgâh modu, yuva etkileşimi, ParçaNet uyumluluk filtresi, kasa teşhisi ve iş üretici kullanır.

const NEEDS_MOBO := ["cpu", "cooler", "ram", "gpu", "nvme", "cmos"]


static func _ok() -> Dictionary:
	return {"ok": true, "reason": "", "code": "ok", "severity": "ok"}


static func _block(code: String, reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "code": code, "severity": "block"}


static func _warn(code: String, reason: String) -> Dictionary:
	return {"ok": true, "reason": reason, "code": code, "severity": "warn"}


static func _slot_val(slot, key: String, fallback):
	if slot == null:
		return fallback
	if slot is Dictionary:
		return slot.get(key, fallback)
	if slot is Object and key in slot:
		return slot.get(key)
	return fallback


static func _slot_index(slot) -> int:
	var idx = _slot_val(slot, "slot_index", -1)
	if int(idx) >= 0:
		return int(idx)
	var nm := str(_slot_val(slot, "name", ""))
	# "ram1".."ram4" veya "m2_1"/"m2_2" gibi adlardan 0 tabanlı indeks çıkar
	var digits := ""
	for i in range(nm.length() - 1, -1, -1):
		var ch := nm[i]
		if ch >= "0" and ch <= "9":
			digits = ch + digits
		else:
			break
	if not digits.is_empty():
		return maxi(0, int(digits) - 1)
	return 0


static func _case_def_for(case_state: Dictionary) -> Dictionary:
	var cd = case_state.get("case_def", {})
	if cd is Dictionary and not cd.is_empty():
		return cd
	var cid := str(case_state.get("case_id", "atx_mid"))
	var found := DB.parts.case_def(cid)
	return found if not found.is_empty() else DB.parts.case_def("atx_mid")


## PC düğümünden (veya mevcut bir durum sözlüğünden) standart kasa durum sözlüğü üretir.
static func case_state_of(pc) -> Dictionary:
	if pc is Dictionary:
		var cid := str(pc.get("case_id", "atx_mid"))
		return {
			"case_id": cid,
			"case_def": _case_def_for(pc),
			"mobo": pc.get("mobo", null),
			"cpu": pc.get("cpu", null),
			"cooler": pc.get("cooler", null),
			"rams": pc.get("rams", []),
			"gpu": pc.get("gpu", null),
			"psu": pc.get("psu", null),
			"storage": pc.get("storage", []),
			"fans": pc.get("fans", []),
			"cmos": pc.get("cmos", null),
			"slots_occupied": pc.get("slots_occupied", {}),
		}
	var cid := "atx_mid"
	if pc != null and "case_id" in pc:
		cid = str(pc.case_id)
	var cdef := DB.parts.case_def(cid)
	if cdef.is_empty():
		cdef = DB.parts.case_def("atx_mid")
	var st := {
		"case_id": cid,
		"case_def": cdef,
		"mobo": null,
		"cpu": null,
		"cooler": null,
		"rams": [],
		"gpu": null,
		"psu": null,
		"storage": [],
		"fans": [],
		"cmos": null,
		"slots_occupied": {},
	}
	if pc == null or not ("slots" in pc):
		return st
	for sn in pc.slots:
		var s = pc.slots[sn]
		if s == null or s.part == null:
			continue
		var p = s.part
		var pdef: PartDef = p.def() if p.has_method("def") else DB.parts.def_for(p.part_type, p.tier)
		if pdef == null:
			continue
		st.slots_occupied[str(sn)] = pdef
		match pdef.category:
			"mobo": st.mobo = pdef
			"cpu": st.cpu = pdef
			"cooler": st.cooler = pdef
			"ram": st.rams.append(pdef)
			"gpu": st.gpu = pdef
			"psu": st.psu = pdef
			"ssd", "hdd", "nvme": st.storage.append(pdef)
			"fan": st.fans.append(pdef)
			"cmos": st.cmos = pdef
	return st


## Belirli bir yuvaya belirli bir parçanın takılabilirliğini denetler.
## slot: Slot (Area3D) ya da test sözlüğü ({accepts, accepts_extra, part, slot_index, name}).
static func check(slot, part_def: PartDef, case_state: Dictionary) -> Dictionary:
	if part_def == null:
		return _block("invalid_part", "Geçersiz parça")
	# 1. Doluluk ve yuva türü
	if _slot_val(slot, "part", null) != null:
		return _block("occupied", "Bu yuva dolu")
	var accepts := str(_slot_val(slot, "accepts", ""))
	var extra: Array = _slot_val(slot, "accepts_extra", [])
	if part_def.category != accepts and not extra.has(part_def.category):
		return _block("wrong_slot", "Bu parça bu yuvaya uymaz")

	var cdef := _case_def_for(case_state)
	var mobo: PartDef = case_state.get("mobo", null)
	var cpu: PartDef = case_state.get("cpu", null)
	var gpu: PartDef = case_state.get("gpu", null)
	var psu: PartDef = case_state.get("psu", null)
	var storage: Array = case_state.get("storage", [])

	# 2. Anakart şartı
	if NEEDS_MOBO.has(part_def.category) and mobo == null:
		return _block("no_mobo", "Önce anakart takmalısın")

	# 3. Kasa <-> Anakart form faktörü
	if part_def.category == "mobo":
		var ff := str(part_def.compat.get("form_factor", ""))
		var supported: Array = cdef.get("form_factors", ["ATX", "mATX", "ITX"])
		if not ff.is_empty() and not supported.has(ff):
			return _block("form_factor", "Bu kasa %s anakartı desteklemiyor" % ff)
		return _ok()

	# 4. CPU <-> Anakart soket
	if part_def.category == "cpu":
		var c_sock := str(part_def.compat.get("socket", ""))
		var m_sock := str(mobo.compat.get("socket", ""))
		if not c_sock.is_empty() and not m_sock.is_empty() and c_sock != m_sock:
			return _block("socket", "Bu anakart %s, işlemci %s" % [m_sock, c_sock])
		return _ok()

	# 5. RAM <-> Anakart DDR çentiği ve yuva sayısı
	if part_def.category == "ram":
		var r_type := str(part_def.compat.get("ram_type", ""))
		var m_type := str(mobo.compat.get("ram_type", ""))
		if not r_type.is_empty() and not m_type.is_empty() and r_type != m_type:
			return _block("ddr_notch", "Çentik uymuyor: anakart %s, bu RAM %s" % [m_type, r_type])
		var idx := _slot_index(slot)
		var max_slots := int(mobo.compat.get("ram_slots", 2))
		if idx >= max_slots:
			return _block("ram_slot_limit", "Bu anakartta yalnızca %d RAM yuvası var" % max_slots)
		return _ok()

	# 6. Depolama (M.2 NVMe / SATA SSD-HDD)
	if part_def.category == "nvme":
		var iface := str(part_def.compat.get("iface", "NVMe"))
		if iface != "NVMe":
			return _block("wrong_slot", "Bu yuva yalnızca M.2 NVMe destekler")
		var m2_idx := _slot_index(slot)
		var m2_max := int(mobo.compat.get("m2_slots", 1))
		if m2_idx >= m2_max:
			return _block("m2_limit", "Bu anakartta yalnızca %d M.2 yuvası var" % m2_max)
		return _ok()

	if part_def.category == "ssd" or part_def.category == "hdd":
		var iface := str(part_def.compat.get("iface", "SATA"))
		if iface != "SATA":
			return _block("wrong_slot", "Bu yuva yalnızca SATA depolama destekler")
		if mobo != null:
			var sata_count := 0
			for st in storage:
				if st != null and str(st.compat.get("iface", "")) == "SATA":
					sata_count += 1
			var sata_max := int(mobo.compat.get("sata_ports", 4))
			if sata_count >= sata_max:
				return _block("sata_limit", "Anakartta boş SATA portu kalmadı (%d/%d)" % [sata_count, sata_max])
		return _ok()

	# 7. GPU uzunluğu + PSU konnektör ve watt kontrolü
	if part_def.category == "gpu":
		var gpu_mm := int(part_def.specs.get("length_mm", 0))
		var max_gpu := int(cdef.get("max_gpu_mm", 330))
		if gpu_mm > max_gpu:
			return _block("gpu_length", "Ekran kartı kasaya sığmıyor (%dmm > %dmm)" % [gpu_mm, max_gpu])
		if psu != null:
			var pc_res := check_psu_connectors(psu, part_def)
			if not pc_res.ok:
				return pc_res
			var hyp := case_state.duplicate()
			hyp["gpu"] = part_def
			var w := calc_watts(hyp)
			if not w.ok:
				return _warn("psu_watts", "Güç kaynağı yetersiz kalabilir (%dW / önerilen %dW)" % [w.psu, w.recommended])
		return _ok()

	# 8. CPU soğutucu: işlemci şartı, soket, yükseklik, radyatör
	if part_def.category == "cooler":
		if cpu == null:
			return _block("no_cpu", "Önce işlemci takmalısın")
		var m_sock := str(mobo.compat.get("socket", ""))
		var c_socks: Array = part_def.compat.get("sockets", [])
		if not m_sock.is_empty() and not c_socks.is_empty() and not c_socks.has(m_sock):
			return _block("cooler_socket", "Bu soğutucu %s soketini desteklemiyor" % m_sock)
		var h_mm := int(part_def.specs.get("height_mm", 0))
		var max_h := int(cdef.get("max_cooler_mm", 165))
		if h_mm > max_h:
			return _block("cooler_height", "Soğutucu kasaya sığmıyor (%dmm > %dmm)" % [h_mm, max_h])
		var rad_mm := int(part_def.specs.get("radiator_mm", 0))
		var max_rad := int(cdef.get("max_rad_mm", 240))
		if rad_mm > 0 and rad_mm > max_rad:
			return _block("cooler_rad", "Bu kasa %dmm radyatör desteklemiyor" % rad_mm)
		return _ok()

	# 9. PSU: GPU konnektörü (engeller) ve watt (uyarır)
	if part_def.category == "psu":
		if gpu != null:
			var pc_res := check_psu_connectors(part_def, gpu)
			if not pc_res.ok:
				return pc_res
		var hyp := case_state.duplicate()
		hyp["psu"] = part_def
		var w := calc_watts(hyp)
		if not w.ok:
			return _warn("psu_watts", "Güç kaynağı yetersiz kalabilir (%dW / önerilen %dW)" % [w.psu, w.recommended])
		return _ok()

	return _ok()


## PSU konnektörlerinin ekran kartının istediği güç pinlerini karşılayıp karşılamadığını denetler.
static func check_psu_connectors(psu_def: PartDef, gpu_def: PartDef) -> Dictionary:
	if psu_def == null or gpu_def == null:
		return _ok()
	var req: Array = gpu_def.compat.get("pcie_pins", [])
	if req.is_empty():
		return _ok()
	var avail: Dictionary = psu_def.compat.get("connectors", {})
	var need := {}
	for p in req:
		var k := str(p)
		need[k] = int(need.get(k, 0)) + 1
	for k in need:
		if int(avail.get(k, 0)) < int(need[k]):
			return _block("psu_connectors", "PSU'da gereken %s güç kablosu yok" % k.to_upper())
	return _ok()


## Sistem güç tüketimi ve önerilen PSU watt değeri.
static func calc_watts(case_state: Dictionary) -> Dictionary:
	var cpu: PartDef = case_state.get("cpu", null)
	var gpu: PartDef = case_state.get("gpu", null)
	var psu: PartDef = case_state.get("psu", null)
	var rams: Array = case_state.get("rams", [])
	var storage: Array = case_state.get("storage", [])
	var fans: Array = case_state.get("fans", [])
	var draw := 50
	if cpu != null:
		draw += int(cpu.specs.get("tdp", 65))
	if gpu != null:
		draw += int(gpu.specs.get("tdp", 0))
	draw += rams.size() * 5
	draw += storage.size() * 5
	draw += fans.size() * 3
	var recommended := int(ceil(float(draw) * 1.25 / 50.0)) * 50
	var psu_w := 0
	if psu != null:
		psu_w = int(psu.compat.get("watts", psu.specs.get("watts", 0)))
	return {"draw": draw, "psu": psu_w, "recommended": recommended, "ok": psu_w >= draw and psu_w > 0}


## Görüntü çıkışı doğrulaması: GPU yoksa işlemcide dahili grafik (iGPU) olmalı.
static func check_display(cpu_def: PartDef, gpu_def: PartDef) -> Dictionary:
	if gpu_def != null:
		return _ok()
	if cpu_def == null:
		return _block("no_display", "Görüntü kaynağı yok")
	if not bool(cpu_def.specs.get("igpu", false)):
		return _block("no_display", "Bu işlemcide dahili grafik yok, ekran kartı gerekli")
	return _ok()


## Tüm sistemin uyumluluk ve eksiksizlik doğrulaması.
## Dönüş: {"ok": bool, "issues": [{"code", "reason", "severity"}], "watts": Dictionary}
static func check_system(case_state: Dictionary) -> Dictionary:
	var issues: Array = []
	var cdef := _case_def_for(case_state)
	var mobo: PartDef = case_state.get("mobo", null)
	var cpu: PartDef = case_state.get("cpu", null)
	var cooler: PartDef = case_state.get("cooler", null)
	var rams: Array = case_state.get("rams", [])
	var gpu: PartDef = case_state.get("gpu", null)
	var psu: PartDef = case_state.get("psu", null)
	var storage: Array = case_state.get("storage", [])

	if mobo == null:
		issues.append({"code": "no_mobo", "reason": "Anakart takılı değil", "severity": "block"})
	else:
		var ff := str(mobo.compat.get("form_factor", ""))
		var supported: Array = cdef.get("form_factors", ["ATX", "mATX", "ITX"])
		if not ff.is_empty() and not supported.has(ff):
			issues.append({"code": "form_factor", "reason": "Bu kasa %s anakartı desteklemiyor" % ff, "severity": "block"})

	if cpu == null:
		issues.append({"code": "no_cpu", "reason": "İşlemci takılı değil", "severity": "block"})
	elif mobo != null:
		var c_sock := str(cpu.compat.get("socket", ""))
		var m_sock := str(mobo.compat.get("socket", ""))
		if not c_sock.is_empty() and not m_sock.is_empty() and c_sock != m_sock:
			issues.append({"code": "socket", "reason": "Bu anakart %s, işlemci %s" % [m_sock, c_sock], "severity": "block"})

	if cooler == null:
		issues.append({"code": "no_cooler", "reason": "CPU soğutucu takılı değil", "severity": "block"})
	else:
		if mobo != null:
			var m_sock := str(mobo.compat.get("socket", ""))
			var c_socks: Array = cooler.compat.get("sockets", [])
			if not m_sock.is_empty() and not c_socks.is_empty() and not c_socks.has(m_sock):
				issues.append({"code": "cooler_socket", "reason": "Soğutucu %s soketini desteklemiyor" % m_sock, "severity": "block"})
		var h_mm := int(cooler.specs.get("height_mm", 0))
		var max_h := int(cdef.get("max_cooler_mm", 165))
		if h_mm > max_h:
			issues.append({"code": "cooler_height", "reason": "Soğutucu kasaya sığmıyor (%dmm > %dmm)" % [h_mm, max_h], "severity": "block"})
		var rad_mm := int(cooler.specs.get("radiator_mm", 0))
		var max_rad := int(cdef.get("max_rad_mm", 240))
		if rad_mm > 0 and rad_mm > max_rad:
			issues.append({"code": "cooler_rad", "reason": "Bu kasa %dmm radyatör desteklemiyor" % rad_mm, "severity": "block"})

	if rams.is_empty():
		issues.append({"code": "no_ram", "reason": "RAM takılı değil", "severity": "block"})
	elif mobo != null:
		var m_type := str(mobo.compat.get("ram_type", ""))
		var max_slots := int(mobo.compat.get("ram_slots", 2))
		if rams.size() > max_slots:
			issues.append({"code": "ram_slot_limit", "reason": "Anakart yuva sayısından fazla RAM (%d/%d)" % [rams.size(), max_slots], "severity": "block"})
		for r in rams:
			if r == null:
				continue
			var r_type := str(r.compat.get("ram_type", ""))
			if not r_type.is_empty() and not m_type.is_empty() and r_type != m_type:
				issues.append({"code": "ddr_notch", "reason": "Çentik uymuyor: anakart %s, bu RAM %s" % [m_type, r_type], "severity": "block"})
				break

	if storage.is_empty():
		issues.append({"code": "no_storage", "reason": "Depolama birimi takılı değil", "severity": "block"})
	elif mobo != null:
		var nvme_n := 0
		var sata_n := 0
		for st in storage:
			if st == null:
				continue
			var iface := str(st.compat.get("iface", ""))
			if iface == "NVMe":
				nvme_n += 1
			elif iface == "SATA":
				sata_n += 1
		if nvme_n > int(mobo.compat.get("m2_slots", 1)):
			issues.append({"code": "m2_limit", "reason": "Anakart M.2 yuvası yetersiz", "severity": "block"})
		if sata_n > int(mobo.compat.get("sata_ports", 4)):
			issues.append({"code": "sata_limit", "reason": "Anakart SATA portu yetersiz", "severity": "block"})

	if gpu != null:
		var gpu_mm := int(gpu.specs.get("length_mm", 0))
		var max_gpu := int(cdef.get("max_gpu_mm", 330))
		if gpu_mm > max_gpu:
			issues.append({"code": "gpu_length", "reason": "Ekran kartı kasaya sığmıyor (%dmm > %dmm)" % [gpu_mm, max_gpu], "severity": "block"})

	if cpu != null:
		var disp := check_display(cpu, gpu)
		if not disp.ok:
			issues.append({"code": disp.code, "reason": disp.reason, "severity": disp.severity})

	var watts := calc_watts(case_state)
	if psu == null:
		issues.append({"code": "no_psu", "reason": "Güç kaynağı takılı değil", "severity": "block"})
	else:
		if gpu != null:
			var pc_res := check_psu_connectors(psu, gpu)
			if not pc_res.ok:
				issues.append({"code": pc_res.code, "reason": pc_res.reason, "severity": pc_res.severity})
		if not watts.ok:
			issues.append({"code": "psu_watts", "reason": "Güç kaynağı yetersiz (%dW < %dW)" % [watts.psu, watts.draw], "severity": "block"})

	return {"ok": issues.is_empty(), "issues": issues, "watts": watts}


## ParçaNet "Uyumluluk" filtresi ve rozeti için: yuvaya bakmadan tezgâhtaki PC ile uyum kontrolü.
static func check_catalog_part(part_def: PartDef, case_state: Dictionary) -> Dictionary:
	if part_def == null or part_def.device != "pc" or case_state.is_empty():
		return _ok()
	var cdef := _case_def_for(case_state)
	var mobo: PartDef = case_state.get("mobo", null)
	var cpu: PartDef = case_state.get("cpu", null)
	var rams: Array = case_state.get("rams", [])
	var gpu: PartDef = case_state.get("gpu", null)
	var psu: PartDef = case_state.get("psu", null)

	match part_def.category:
		"mobo":
			var ff := str(part_def.compat.get("form_factor", ""))
			var supported: Array = cdef.get("form_factors", ["ATX", "mATX", "ITX"])
			if not ff.is_empty() and not supported.has(ff):
				return _block("form_factor", "Kasa %s desteklemiyor" % ff)
			if cpu != null:
				var c_sock := str(cpu.compat.get("socket", ""))
				var m_sock := str(part_def.compat.get("socket", ""))
				if not c_sock.is_empty() and not m_sock.is_empty() and c_sock != m_sock:
					return _block("socket", "Mevcut işlemci %s, anakart %s" % [c_sock, m_sock])
			if not rams.is_empty():
				var r_type := str(rams[0].compat.get("ram_type", ""))
				var m_type := str(part_def.compat.get("ram_type", ""))
				if not r_type.is_empty() and not m_type.is_empty() and r_type != m_type:
					return _block("ddr_notch", "Mevcut RAM %s, anakart %s" % [r_type, m_type])
			return _ok()
		"cpu":
			if mobo != null:
				var c_sock := str(part_def.compat.get("socket", ""))
				var m_sock := str(mobo.compat.get("socket", ""))
				if not c_sock.is_empty() and not m_sock.is_empty() and c_sock != m_sock:
					return _block("socket", "Anakart %s, işlemci %s" % [m_sock, c_sock])
			return _ok()
		"ram":
			if mobo != null:
				var r_type := str(part_def.compat.get("ram_type", ""))
				var m_type := str(mobo.compat.get("ram_type", ""))
				if not r_type.is_empty() and not m_type.is_empty() and r_type != m_type:
					return _block("ddr_notch", "Anakart %s, RAM %s" % [m_type, r_type])
			return _ok()
		"gpu":
			var gpu_mm := int(part_def.specs.get("length_mm", 0))
			var max_gpu := int(cdef.get("max_gpu_mm", 330))
			if gpu_mm > max_gpu:
				return _block("gpu_length", "Kasaya sığmıyor (%dmm > %dmm)" % [gpu_mm, max_gpu])
			if psu != null:
				var pc_res := check_psu_connectors(psu, part_def)
				if not pc_res.ok:
					return pc_res
				var hyp := case_state.duplicate()
				hyp["gpu"] = part_def
				var w := calc_watts(hyp)
				if not w.ok:
					return _warn("psu_watts", "PSU yetersiz (%dW / %dW)" % [w.psu, w.recommended])
			return _ok()
		"cooler":
			if mobo != null:
				var m_sock := str(mobo.compat.get("socket", ""))
				var c_socks: Array = part_def.compat.get("sockets", [])
				if not m_sock.is_empty() and not c_socks.is_empty() and not c_socks.has(m_sock):
					return _block("cooler_socket", "%s soketini desteklemiyor" % m_sock)
			var h_mm := int(part_def.specs.get("height_mm", 0))
			var max_h := int(cdef.get("max_cooler_mm", 165))
			if h_mm > max_h:
				return _block("cooler_height", "Kasaya sığmıyor (%dmm > %dmm)" % [h_mm, max_h])
			var rad_mm := int(part_def.specs.get("radiator_mm", 0))
			var max_rad := int(cdef.get("max_rad_mm", 240))
			if rad_mm > 0 and rad_mm > max_rad:
				return _block("cooler_rad", "Kasa %dmm radyatör desteklemiyor" % rad_mm)
			return _ok()
		"psu":
			if gpu != null:
				var pc_res := check_psu_connectors(part_def, gpu)
				if not pc_res.ok:
					return pc_res
			var hyp := case_state.duplicate()
			hyp["psu"] = part_def
			var w := calc_watts(hyp)
			if not w.ok:
				return _warn("psu_watts", "Sistem için yetersiz (%dW / %dW)" % [w.psu, w.recommended])
			return _ok()
		"nvme":
			if mobo != null and int(mobo.compat.get("m2_slots", 0)) <= 0:
				return _block("m2_limit", "Anakartta M.2 yuvası yok")
			return _ok()
		"ssd", "hdd":
			if mobo != null and int(mobo.compat.get("sata_ports", 0)) <= 0:
				return _block("sata_limit", "Anakartta SATA portu yok")
			return _ok()
	return _ok()
