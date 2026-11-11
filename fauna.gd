extends Node

const WATER := -3.0
const CELL := 24.0
const VCELL := 160.0
const GROW := 90.0
const REGROW := 150.0
const T_COW := 0
const T_PIG := 1
const T_SHEEP := 2
const T_CHICK := 3
const T_NATIVE := 4

var TYPE_MESH := ["cow", "pig", "sheep", "chick", "native"]
var TYPE_NAME := ["Bò", "Heo", "Cừu", "Gà", "Thổ dân"]
var HP := [30.0, 20.0, 18.0, 8.0, 40.0]
var SPD := [1.8, 2.2, 1.8, 2.6, 1.6]
var TRADES := [
	{"give": {"meat": 2}, "get": {"seed": 3}},
	{"give": {"wool": 3}, "get": {"pick": 1}},
	{"give": {"feather": 6}, "get": {"axe": 1}},
	{"give": {"egg": 4}, "get": {"bandage": 2}},
	{"give": {"pumpkin": 2}, "get": {"spear": 1}},
	{"give": {"apple": 4}, "get": {"fire": 1}},
]

var main = null
var world_root: Node3D
var vmat := StandardMaterial3D.new()
var flame_mat := StandardMaterial3D.new()
var smoke_mat := StandardMaterial3D.new()
var meshes := {}

var ents := {}
var puppets := {}
var pmesh := {}
var ptype := {}
var ptarget := {}
var pyaw := {}
var next_id := 1
var snap_t := 0.0
var pop_t := 0.0
var world_t := 0.0
var plot_t := 0.0

var vill := {}
var vcache := {}
var patches := {}
var pcache := {}
var picked := {}
var plots := {}
var cool := {}
var atk_cd := 0.0

var ui: CanvasLayer
var box: VBoxContainer
var trade: PanelContainer
var trade_box: VBoxContainer

func _ready() -> void:
	vmat.vertex_color_use_as_albedo = true
	vmat.vertex_color_is_srgb = true
	vmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	vmat.roughness = 1.0
	vmat.metallic_specular = 0.1
	flame_mat.vertex_color_use_as_albedo = true
	flame_mat.vertex_color_is_srgb = true
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.albedo_color = Color(1.0, 0.7, 0.35, 0.2)
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	world_root = Node3D.new()
	add_child(world_root)
	_build_meshes()
	_build_ui()

func _process(delta: float) -> void:
	if main == null:
		var cs := get_tree().current_scene
		if cs != null and cs.get("started") != null and cs.get("ITEMS") != null:
			main = cs
			_setup()
		return
	if not is_instance_valid(main):
		_reset()
		return
	var on: bool = main.started
	box.visible = on
	if not on:
		return
	atk_cd = maxf(0.0, atk_cd - delta)
	_puppets_step(delta)
	world_t += delta
	if world_t >= 1.0:
		world_t = 0.0
		_update_world()
	plot_t += delta
	if plot_t >= 1.0:
		plot_t = 0.0
		_update_plots()
	if multiplayer.is_server():
		_server_step(delta)

func _setup() -> void:
	var it: Dictionary = main.ITEMS
	it["meat"] = ["Thịt sống", Color(0.8, 0.3, 0.3)]
	it["cooked"] = ["Thịt nướng", Color(0.65, 0.35, 0.15)]
	it["egg"] = ["Trứng", Color(0.95, 0.9, 0.8)]
	it["boiled"] = ["Trứng luộc", Color(0.98, 0.95, 0.85)]
	it["milk"] = ["Sữa", Color(0.95, 0.95, 1.0)]
	it["wool"] = ["Len", Color(0.9, 0.9, 0.85)]
	it["feather"] = ["Lông vũ", Color(0.85, 0.3, 0.3)]
	it["seed"] = ["Hạt giống", Color(0.7, 0.6, 0.3)]
	it["carrot"] = ["Cà rốt", Color(0.95, 0.5, 0.1)]
	it["cabbage"] = ["Bắp cải", Color(0.5, 0.75, 0.3)]
	it["pumpkin"] = ["Bí ngô", Color(0.95, 0.55, 0.1)]
	it["apple"] = ["Táo", Color(0.85, 0.15, 0.15)]
	it["soup"] = ["Súp rau củ", Color(0.8, 0.5, 0.25)]
	var rec: Array = main.RECIPES
	rec.append({"id": "cooked", "name": "Thịt nướng", "need": {"meat": 1}, "fire": true})
	rec.append({"id": "boiled", "name": "Trứng luộc", "need": {"egg": 2}, "fire": true})
	rec.append({"id": "soup", "name": "Súp rau củ", "need": {"carrot": 1, "cabbage": 1, "pumpkin": 1}, "fire": true})
	main._load_inv()
	if not multiplayer.peer_connected.is_connected(_on_peer):
		multiplayer.peer_connected.connect(_on_peer)

func _reset() -> void:
	main = null
	for ch in world_root.get_children():
		ch.queue_free()
	ents.clear()
	puppets.clear()
	pmesh.clear()
	ptype.clear()
	ptarget.clear()
	pyaw.clear()
	vill.clear()
	patches.clear()
	plots.clear()
	picked.clear()
	cool.clear()
	trade.visible = false
	box.visible = false

func _net() -> bool:
	return multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty()

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _on_peer(id: int) -> void:
	if multiplayer.is_server():
		var list: Array = []
		for pid in plots.keys():
			var pl: Dictionary = plots[pid]
			list.append([pid, pl["pos"], pl["kind"], pl["t0"]])
		_sync_plots.rpc_id(id, list)

# ---------- UI ----------
func _mkbtn(t: String) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(200, 70)
	b.add_theme_font_size_override("font_size", 26)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.set_corner_radius_all(20)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	var sp := StyleBoxFlat.new()
	sp.bg_color = Color(0.25, 0.25, 0.25, 0.7)
	sp.set_corner_radius_all(20)
	b.add_theme_stylebox_override("pressed", sp)
	return b

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	box = VBoxContainer.new()
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = -440
	box.offset_right = -240
	box.offset_top = -350
	box.offset_bottom = -20
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 16)
	box.visible = false
	ui.add_child(box)
	var b1 := _mkbtn("Đánh")
	b1.pressed.connect(_attack)
	box.add_child(b1)
	var b2 := _mkbtn("Tương tác")
	b2.pressed.connect(_interact)
	box.add_child(b2)

	trade = PanelContainer.new()
	trade.anchor_left = 0.5
	trade.anchor_right = 0.5
	trade.anchor_top = 0.5
	trade.anchor_bottom = 0.5
	trade.offset_left = -300
	trade.offset_right = 300
	trade.offset_top = -280
	trade.offset_bottom = 280
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.06, 0.08, 0.1, 0.95)
	ps.set_corner_radius_all(24)
	ps.set_content_margin_all(16)
	trade.add_theme_stylebox_override("panel", ps)
	trade.visible = false
	ui.add_child(trade)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	trade.add_child(root)
	var title := Label.new()
	title.text = "Thổ dân - Trao đổi"
	title.add_theme_font_size_override("font_size", 30)
	root.add_child(title)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 360)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(sc)
	trade_box = VBoxContainer.new()
	trade_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trade_box.add_theme_constant_override("separation", 10)
	sc.add_child(trade_box)
	var close := Button.new()
	close.text = "Đóng"
	close.custom_minimum_size = Vector2(0, 64)
	close.add_theme_font_size_override("font_size", 26)
	close.pressed.connect(_close_trade)
	root.add_child(close)

func _open_trade() -> void:
	trade.visible = true
	_refresh_trade()

func _close_trade() -> void:
	trade.visible = false

func _fmt(d: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in d.keys():
		parts.append("%d %s" % [int(d[k]), main.ITEMS[k][0]])
	return ", ".join(parts)

func _refresh_trade() -> void:
	for ch in trade_box.get_children():
		trade_box.remove_child(ch)
		ch.queue_free()
	for i in TRADES.size():
		var t: Dictionary = TRADES[i]
		var ok := true
		for k in t["give"].keys():
			if int(main.inv.get(k, 0)) < int(t["give"][k]):
				ok = false
		var b := Button.new()
		b.text = "%s\n→ %s" % [_fmt(t["give"]), _fmt(t["get"])]
		b.custom_minimum_size = Vector2(0, 90)
		b.disabled = not ok
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(_do_trade.bind(i))
		trade_box.add_child(b)

func _do_trade(i: int) -> void:
	var t: Dictionary = TRADES[i]
	for k in t["give"].keys():
		if int(main.inv.get(k, 0)) < int(t["give"][k]):
			main._say("Thiếu nguyên liệu")
			return
	for k in t["give"].keys():
		main._spend(k, int(t["give"][k]))
	for k in t["get"].keys():
		main._add(k, int(t["get"][k]))
	main._say("Đã trao đổi với thổ dân")
	_refresh_trade()

# ---------- ĂN & GIEO HẠT ----------
func _eat(id: String, hun: float, thi: float, hpd: float, txt: String) -> void:
	main.hunger = clampf(main.hunger + hun, 0.0, 100.0)
	main.thirst = clampf(main.thirst + thi, 0.0, 100.0)
	main.hp = clampf(main.hp + hpd, 1.0, 100.0)
	main._spend(id, 1)
	main._say(txt)

func use_item(id: String) -> bool:
	if main == null:
		return false
	if id == "meat":
		_eat(id, 15.0, 0.0, -8.0, "Ăn thịt sống (+15 no, -8 máu). Nên nướng!")
	elif id == "cooked":
		_eat(id, 45.0, 0.0, 5.0, "Ăn thịt nướng (+45 no)")
	elif id == "egg":
		_eat(id, 8.0, 0.0, 0.0, "Ăn trứng sống (+8 no)")
	elif id == "boiled":
		_eat(id, 25.0, 0.0, 0.0, "Ăn trứng luộc (+25 no)")
	elif id == "milk":
		_eat(id, 10.0, 30.0, 0.0, "Uống sữa (+30 khát)")
	elif id == "apple":
		_eat(id, 12.0, 8.0, 0.0, "Ăn táo (+12 no)")
	elif id == "carrot":
		_eat(id, 14.0, 0.0, 0.0, "Ăn cà rốt (+14 no)")
	elif id == "cabbage":
		_eat(id, 12.0, 5.0, 0.0, "Ăn bắp cải (+12 no)")
	elif id == "pumpkin":
		_eat(id, 20.0, 0.0, 0.0, "Ăn bí ngô (+20 no)")
	elif id == "soup":
		_eat(id, 60.0, 0.0, 10.0, "Húp súp rau củ (+60 no, +10 máu)")
	elif id == "seed":
		_plant_seed()
		else:
		var tl = get_node_or_null("/root/Gear")
		return tl != null and tl.use_item(id)
	return true

func _plant_seed() -> void:
	var p: Vector3 = main.player.position
	var pos := p + Vector3(0, 0, -2.0).rotated(Vector3.UP, main.yaw)
	var h: float = main._height(pos.x, pos.z)
	pos.y = h
	if main._biome_id(h, main.tnoise.get_noise_2d(pos.x, pos.z)) != 0:
		main._say("Chỉ gieo được trên đất cỏ")
		return
	var id := randi()
	var kind := randi() % 3
	var t0 := Time.get_unix_time_from_system()
	_do_plant(id, pos, kind, t0)
	if _net():
		_rpc_plant.rpc(id, pos, kind, t0)
	main._spend("seed", 1)
	main._say("Đã gieo hạt. Khoảng 90 giây nữa sẽ chín!")

func _do_plant(id: int, pos: Vector3, kind: int, t0: float) -> void:
	if plots.has(id):
		return
	var n := Node3D.new()
	n.position = pos
	var m := MeshInstance3D.new()
	m.mesh = meshes["sprout"]
	m.material_override = vmat
	n.add_child(m)
	world_root.add_child(n)
	plots[id] = {"node": n, "mi": m, "pos": pos, "kind": kind, "t0": t0, "stage": 0}

func _do_unplant(id: int) -> void:
	if plots.has(id):
		var pl: Dictionary = plots[id]
		var n: Node3D = pl["node"]
		n.queue_free()
		plots.erase(id)

func _update_plots() -> void:
	var now := Time.get_unix_time_from_system()
	for id in plots.keys():
		var pl: Dictionary = plots[id]
		var age: float = now - float(pl["t0"])
		var st := 0
		if age >= GROW:
			st = 2
		elif age >= 25.0:
			st = 1
		if st != int(pl["stage"]):
			pl["stage"] = st
			var m: MeshInstance3D = pl["mi"]
			if st == 1:
				m.mesh = meshes["leaf"]
			elif st == 2:
				m.mesh = meshes["p%d" % int(pl["kind"])]
				m.scale = Vector3(0.75, 0.75, 0.75)

@rpc("any_peer", "reliable")
func _rpc_plant(id: int, pos: Vector3, kind: int, t0: float) -> void:
	_do_plant(id, pos, kind, t0)

@rpc("any_peer", "reliable")
func _rpc_unplant(id: int) -> void:
	_do_unplant(id)

@rpc("authority", "reliable")
func _sync_plots(list: Array) -> void:
	for e in list:
		_do_plant(int(e[0]), e[1], int(e[2]), float(e[3]))

@rpc("any_peer", "reliable")
func _rpc_picked(key: String, t: float) -> void:
	picked[key] = t

# ---------- TƯƠNG TÁC / ĐÁNH ----------
func _fwd() -> Vector3:
	return Vector3(0, 0, -1).rotated(Vector3.UP, main.yaw)

func _cone_ok(p: Vector3, q: Vector3, rng: float, mincos: float) -> float:
	var d := Vector3(q.x - p.x, 0.0, q.z - p.z)
	var l := d.length()
	if l > rng:
		return -1.0
	if l > 0.8 and d.normalized().dot(_fwd()) < mincos:
		return -1.0
	return l

func _find(rng: float, mincos: float, want_ents: bool, want_world: bool) -> Dictionary:
	var p: Vector3 = main.player.position
	var best := {}
	var bs := 1000000.0
	if want_ents:
		for id in puppets.keys():
			var n: Node3D = puppets[id]
			var l := _cone_ok(p, n.position, rng, mincos)
			if l >= 0.0 and l < bs:
				bs = l
				best = {"kind": "ent", "id": id}
	if want_world:
		for key in patches.keys():
			var v: Dictionary = patches[key]
			var pn: Node3D = v["node"]
			if not pn.visible:
				continue
			var l2 := _cone_ok(p, pn.position, rng, mincos)
			if l2 >= 0.0 and l2 < bs:
				bs = l2
				best = {"kind": "patch", "key": key}
		for id in plots.keys():
			var pl: Dictionary = plots[id]
			var l3 := _cone_ok(p, pl["pos"], rng, mincos)
			if l3 >= 0.0 and l3 < bs:
				bs = l3
				best = {"kind": "plot", "id": id}
	return best

func _attack() -> void:
	if main == null or atk_cd > 0.0:
		return
	atk_cd = 0.45
	var t := _find(3.8, 0.3, true, false)
	if t.is_empty():
		main._say("Vung tay vào không khí")
		return
	var dmg := 18.0 if main._has("spear") else 6.0
	var ty: int = ptype[t["id"]]
	main._say("Đánh %s! (-%d)" % [TYPE_NAME[ty], int(dmg)])
	_send_hit(int(t["id"]), dmg)

func _interact() -> void:
	if main == null:
		return
	var t := _find(4.5, 0.2, true, true)
	if t.is_empty():
		main._say("Không có gì để tương tác phía trước")
		return
	var kind: String = t["kind"]
	if kind == "ent":
		_interact_ent(int(t["id"]))
	elif kind == "patch":
		_harvest_patch(str(t["key"]))
	else:
		_harvest_plot(int(t["id"]))

func _interact_ent(id: int) -> void:
	var ty: int = ptype[id]
	if ty == T_NATIVE:
		_open_trade()
		return
	var now := Time.get_unix_time_from_system()
	var last := float(cool.get(id, 0.0))
	var wait := 60.0
	var item := "milk"
	var cnt := 1
	var txt := "Vắt sữa bò: +1 Sữa"
	if ty == T_PIG:
		main._say("Con heo ủn ỉn. Dùng giáo để săn nó!")
		return
	elif ty == T_CHICK:
		wait = 45.0
		item = "egg"
		txt = "Nhặt trứng gà: +1 Trứng"
	elif ty == T_SHEEP:
		wait = 90.0
		item = "wool"
		cnt = 2
		txt = "Cắt lông cừu: +2 Len"
	if now - last < wait:
		main._say("Chờ khoảng %d giây nữa" % int(wait - (now - last)))
		return
	cool[id] = now
	main._add(item, cnt)
	main._say(txt)

func _harvest_patch(key: String) -> void:
	var v: Dictionary = patches[key]
	var ty: int = v["type"]
	if ty == 0:
		main._add("carrot", 3)
		main._say("Nhổ cà rốt: +3")
	elif ty == 1:
		main._add("cabbage", 2)
		main._say("Hái bắp cải: +2")
	elif ty == 2:
		main._add("pumpkin", 2)
		main._say("Hái bí ngô: +2")
	else:
		main._add("apple", 3)
		main._say("Hái táo: +3")
	if ty < 3 and randf() < 0.5:
		main._add("seed", 1)
	var now := Time.get_unix_time_from_system()
	picked[key] = now
	if _net():
		_rpc_picked.rpc(key, now)

func _harvest_plot(id: int) -> void:
	var pl: Dictionary = plots[id]
	var age: float = Time.get_unix_time_from_system() - float(pl["t0"])
	if age < GROW:
		main._say("Chưa chín, còn khoảng %d giây" % int(GROW - age))
		return
	var kind: int = pl["kind"]
	var names := ["carrot", "cabbage", "pumpkin"]
	main._add(names[kind], 2)
	main._add("seed", 1)
	main._say("Thu hoạch: +2 %s, +1 Hạt giống" % main.ITEMS[names[kind]][0])
	_do_unplant(id)
	if _net():
		_rpc_unplant.rpc(id)

# ---------- THẾ GIỚI (làng + cây dại) ----------
func _vil(cx: int, cz: int):
	var key := "%d_%d" % [cx, cz]
	if vcache.has(key):
		return vcache[key]
	var res = null
	var r := RandomNumberGenerator.new()
	r.seed = hash(Vector2i(cx, cz)) + 424242
	if r.randf() < 0.5:
		var x := (float(cx) + 0.15 + r.randf() * 0.7) * VCELL
		var z := (float(cz) + 0.15 + r.randf() * 0.7) * VCELL
		var h: float = main._height(x, z)
		var ok: bool = h > WATER + 2.0 and h < 8.0
		if ok:
			var lo := h
			var hi := h
			for d in [Vector2(10, 0), Vector2(-10, 0), Vector2(0, 10), Vector2(0, -10)]:
				var v: Vector2 = d
				var hh: float = main._height(x + v.x, z + v.y)
				lo = minf(lo, hh)
				hi = maxf(hi, hh)
			ok = hi - lo < 3.5 and main._biome_id(h, main.tnoise.get_noise_2d(x, z)) == 0
		if ok:
			res = Vector3(x, h, z)
	vcache[key] = res
	return res

func _patch_for(cx: int, cz: int, key: String):
	if pcache.has(key):
		return pcache[key]
	var res = null
	var r := RandomNumberGenerator.new()
	r.seed = hash(Vector2i(cx, cz)) + 909
	if r.randf() < 0.3:
		var x := (float(cx) + 0.1 + r.randf() * 0.8) * CELL
		var z := (float(cz) + 0.1 + r.randf() * 0.8) * CELL
		var h: float = main._height(x, z)
		if main._biome_id(h, main.tnoise.get_noise_2d(x, z)) == 0:
			var tp := r.randf()
			var ty := 3
			if tp < 0.35:
				ty = 0
			elif tp < 0.6:
				ty = 1
			elif tp < 0.8:
				ty = 2
			res = {"pos": Vector3(x, h, z), "type": ty}
	pcache[key] = res
	return res

func _update_world() -> void:
	var p: Vector3 = main.player.position
	var vx := floori(p.x / VCELL)
	var vz := floori(p.z / VCELL)
	for cx in range(vx - 1, vx + 2):
		for cz in range(vz - 1, vz + 2):
			var key := "%d_%d" % [cx, cz]
			if vill.has(key):
				continue
			var vp = _vil(cx, cz)
			if vp == null:
				continue
			var v: Vector3 = vp
			if _flat(v, p) < 100.0:
				_spawn_village(key, v)
	for key in vill.keys():
		var vd: Dictionary = vill[key]
		var vpos: Vector3 = vd["pos"]
		if _flat(vpos, p) > 135.0:
			var nd: Node3D = vd["node"]
			nd.queue_free()
			main.camps.erase("v_" + str(key))
			vill.erase(key)

	var gx := floori(p.x / CELL)
	var gz := floori(p.z / CELL)
	for cx in range(gx - 4, gx + 5):
		for cz in range(gz - 4, gz + 5):
			var key2 := "%d_%d" % [cx, cz]
			if patches.has(key2):
				continue
			var pd = _patch_for(cx, cz, key2)
			if pd == null:
				continue
			var pp: Vector3 = pd["pos"]
			if _flat(pp, p) > 85.0:
				continue
			var n := Node3D.new()
			n.position = pp
			n.rotation.y = float(hash(key2) % 628) / 100.0
			var m := MeshInstance3D.new()
			m.mesh = meshes["p%d" % int(pd["type"])]
			m.material_override = vmat
			n.add_child(m)
			world_root.add_child(n)
			patches[key2] = {"node": n, "type": int(pd["type"])}
	var now := Time.get_unix_time_from_system()
	for key3 in patches.keys():
		var pv: Dictionary = patches[key3]
		var pn2: Node3D = pv["node"]
		if _flat(pn2.position, p) > 115.0:
			pn2.queue_free()
			patches.erase(key3)
			continue
		pn2.visible = now - float(picked.get(key3, 0.0)) > REGROW

func _vprop(root: Node3D, m: Mesh, off: Vector3, rot: float, mt: Material) -> void:
	var p := MeshInstance3D.new()
	p.mesh = m
	p.material_override = mt
	var h: float = main._height(root.position.x + off.x, root.position.z + off.z)
	p.position = Vector3(off.x, h - root.position.y + off.y, off.z)
	p.rotation.y = rot
	root.add_child(p)

func _spawn_village(key: String, vp: Vector3) -> void:
	var root := Node3D.new()
	root.position = vp
	world_root.add_child(root)
	var r := RandomNumberGenerator.new()
	r.seed = hash(key) + 55
	for k in 4:
		var a := float(k) * TAU / 4.0 + 0.4 + r.randf() * 0.3
		var rot := atan2(-cos(a), -sin(a))
		_vprop(root, meshes["hut"], Vector3(cos(a) * 10.0, 0.0, sin(a) * 10.0), rot, vmat)
	_vprop(root, meshes["totem"], Vector3(4.5, 0.0, -3.5), 0.0, vmat)
	_vprop(root, meshes["flame"], Vector3.ZERO, 0.0, flame_mat)
	for k in 7:
		var a2 := float(k) * TAU / 7.0
		var sp := MeshInstance3D.new()
		sp.mesh = meshes["stone"]
		sp.material_override = vmat
		var h: float = main._height(vp.x + cos(a2) * 1.4, vp.z + sin(a2) * 1.4)
		sp.position = Vector3(cos(a2) * 1.4, h - vp.y - 0.1, sin(a2) * 1.4)
		sp.scale = Vector3(0.3, 0.3, 0.3)
		root.add_child(sp)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.6, 0.25)
	lamp.light_energy = 2.5
	lamp.omni_range = 20.0
	lamp.position = Vector3(0, 1.8, 0)
	root.add_child(lamp)
	var smoke := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 0.4
	cm.height = 45.0
	cm.radial_segments = 8
	smoke.mesh = cm
	smoke.material_override = smoke_mat
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.position.y = 23.0
	root.add_child(smoke)
	main.camps["v_" + key] = vp
	vill[key] = {"pos": vp, "node": root}

# ---------- MẠNG: SINH VẬT ----------
func _players() -> Array:
	var arr: Array = []
	arr.append([1, main.player.position])
	for id in main.targets.keys():
		arr.append([int(id), main.targets[id]])
	return arr

func _peer_pos(who: int) -> Vector3:
	if who == 1:
		return main.player.position
	return main.targets.get(who, main.player.position)

func _server_step(delta: float) -> void:
	for id in ents.keys():
		var e: Dictionary = ents[id]
		if int(e["type"]) == T_NATIVE:
			_sim_native(e, delta)
		else:
			_sim_animal(e, delta)
	snap_t += delta
	if snap_t >= 0.1:
		snap_t = 0.0
		_send_snap()
	pop_t += delta
	if pop_t >= 2.0:
		pop_t = 0.0
		_populate()

func _step_to(e: Dictionary, tp: Vector3, spd: float, delta: float) -> void:
	var pos: Vector3 = e["pos"]
	var d := Vector3(tp.x - pos.x, 0.0, tp.z - pos.z)
	var l := d.length()
	if l < 0.4:
		e["moving"] = false
		e["wait"] = randf_range(2.0, 7.0)
		return
	var np := pos + d / l * minf(spd * delta, l)
	var h: float = main._height(np.x, np.z)
	if h < WATER + 0.6:
		e["moving"] = false
		e["wait"] = 1.5
		e["flee"] = 0.0
		return
	np.y = h
	e["pos"] = np
	e["yaw"] = atan2(-d.x, -d.z)

func _sim_animal(e: Dictionary, delta: float) -> void:
	var pos: Vector3 = e["pos"]
	var spd: float = e["speed"]
	var tp: Vector3 = e["target"]
	var go := false
	if float(e["flee"]) > 0.0:
		e["flee"] = float(e["flee"]) - delta
		var away: Vector3 = pos - e["from"]
		away.y = 0.0
		if away.length() < 0.1:
			away = Vector3(1, 0, 0)
		tp = pos + away.normalized() * 8.0
		spd *= 2.4
		go = true
	else:
		e["wait"] = float(e["wait"]) - delta
		if e["moving"]:
			go = true
		elif float(e["wait"]) <= 0.0:
			var home: Vector3 = e["home"]
			var ang := randf() * TAU
			var dist := randf_range(4.0, 12.0)
			tp = pos + Vector3(cos(ang), 0, sin(ang)) * dist
			if _flat(tp, home) > float(e["leash"]):
				tp = home + Vector3(cos(ang), 0, sin(ang)) * 5.0
			e["target"] = tp
			e["moving"] = true
			go = true
	if go:
		_step_to(e, tp, spd, delta)

func _sim_native(e: Dictionary, delta: float) -> void:
	if e["hostile"]:
		e["alert"] = float(e["alert"]) - delta
		if float(e["alert"]) <= 0.0:
			e["hostile"] = false
		else:
			var pos: Vector3 = e["pos"]
			var tpos := _peer_pos(int(e["tpeer"]))
			var dist := _flat(pos, tpos)
			if dist > 45.0:
				e["hostile"] = false
			elif dist > 2.2:
				_step_to(e, tpos, 3.4, delta)
			else:
				e["yaw"] = atan2(-(tpos.x - pos.x), -(tpos.z - pos.z))
				e["atk"] = float(e["atk"]) - delta
				if float(e["atk"]) <= 0.0:
					e["atk"] = 1.3
					_hurt_peer(int(e["tpeer"]), 8.0)
			return
	_sim_animal(e, delta)

func _hurt_peer(peer: int, dmg: float) -> void:
	if peer == 1 or not _net():
		_apply_hurt(dmg)
	else:
		_rpc_hurt.rpc_id(peer, dmg)

func _apply_hurt(dmg: float) -> void:
	main.hp = maxf(0.0, main.hp - dmg)
	main._say("Thổ dân đánh bạn! -%d máu" % int(dmg))

@rpc("authority", "reliable")
func _rpc_hurt(dmg: float) -> void:
	_apply_hurt(dmg)

func _pick_type() -> int:
	var r := randf()
	if r < 0.28:
		return T_COW
	if r < 0.55:
		return T_PIG
	if r < 0.8:
		return T_SHEEP
	return T_CHICK

func _spawn_ent(ty: int, pos: Vector3, home: Vector3, leash: float) -> void:
	var h: float = main._height(pos.x, pos.z)
	if h < WATER + 0.8:
		return
	pos.y = h
	var id := next_id
	next_id += 1
	ents[id] = {"id": id, "type": ty, "pos": pos, "yaw": randf() * TAU, "hp": HP[ty], "speed": SPD[ty],
		"target": pos, "wait": randf_range(1.0, 4.0), "moving": false, "flee": 0.0, "from": pos,
		"home": home, "leash": leash, "hostile": false, "tpeer": 1, "alert": 0.0, "atk": 0.0}

func _populate() -> void:
	var pl := _players()
	for id in ents.keys():
		var e: Dictionary = ents[id]
		var near := false
		for pp in pl:
			if _flat(pp[1], e["pos"]) < 150.0:
				near = true
		if not near:
			ents.erase(id)
	var animals := 0
	var natives := 0
	for e in ents.values():
		if int(e["type"]) == T_NATIVE:
			natives += 1
		else:
			animals += 1
	var cap := mini(18, 8 + 5 * pl.size())
	if animals < cap:
		var pp2 = pl[randi() % pl.size()]
		var ppos: Vector3 = pp2[1]
		var ang := randf() * TAU
		var dist := randf_range(35.0, 75.0)
		var x := ppos.x + cos(ang) * dist
		var z := ppos.z + sin(ang) * dist
		var h: float = main._height(x, z)
		if main._biome_id(h, main.tnoise.get_noise_2d(x, z)) == 0:
			var ty := _pick_type()
			var cnt := randi_range(1, 3)
			for k in cnt:
				var sp := Vector3(x + randf_range(-3.0, 3.0), 0.0, z + randf_range(-3.0, 3.0))
				_spawn_ent(ty, sp, sp, 28.0)
	for pp3 in pl:
		var p3: Vector3 = pp3[1]
		var vx := floori(p3.x / VCELL)
		var vz := floori(p3.z / VCELL)
		for cx in range(vx - 1, vx + 2):
			for cz in range(vz - 1, vz + 2):
				var vp = _vil(cx, cz)
				if vp == null:
					continue
				var v: Vector3 = vp
				if _flat(v, p3) > 110.0 or natives >= 10:
					continue
				var have := 0
				for e2 in ents.values():
					if int(e2["type"]) == T_NATIVE and _flat(e2["home"], v) < 1.0:
						have += 1
				if have < 3:
					var a := randf() * TAU
					var d := randf_range(3.0, 8.0)
					_spawn_ent(T_NATIVE, v + Vector3(cos(a) * d, 0.0, sin(a) * d), v, 12.0)
					natives += 1

func _send_snap() -> void:
	var ids := PackedInt32Array()
	var tys := PackedInt32Array()
	var pos := PackedVector3Array()
	var yaws := PackedFloat32Array()
	for id in ents.keys():
		var e: Dictionary = ents[id]
		ids.append(int(id))
		tys.append(int(e["type"]))
		pos.append(e["pos"])
		yaws.append(float(e["yaw"]))
	_apply_snapshot(ids, tys, pos, yaws)
	if _net():
		_snap.rpc(ids, tys, pos, yaws)

@rpc("authority", "unreliable")
func _snap(ids: PackedInt32Array, tys: PackedInt32Array, pos: PackedVector3Array, yaws: PackedFloat32Array) -> void:
	_apply_snapshot(ids, tys, pos, yaws)

func _apply_snapshot(ids: PackedInt32Array, tys: PackedInt32Array, pos: PackedVector3Array, yaws: PackedFloat32Array) -> void:
	var seen := {}
	for i in ids.size():
		var id := ids[i]
		seen[id] = true
		if not puppets.has(id):
			_spawn_puppet(id, tys[i], pos[i])
		ptarget[id] = pos[i]
		pyaw[id] = yaws[i]
	for id in puppets.keys():
		if not seen.has(id):
			_free_puppet(id)

func _spawn_puppet(id: int, ty: int, pos: Vector3) -> void:
	var n := Node3D.new()
	n.position = pos
	var m := MeshInstance3D.new()
	m.mesh = meshes[TYPE_MESH[ty]]
	m.material_override = vmat
	n.add_child(m)
	world_root.add_child(n)
	puppets[id] = n
	pmesh[id] = m
	ptype[id] = ty

func _free_puppet(id: int) -> void:
	var n: Node3D = puppets[id]
	n.queue_free()
	puppets.erase(id)
	pmesh.erase(id)
	ptype.erase(id)
	ptarget.erase(id)
	pyaw.erase(id)

func _puppets_step(delta: float) -> void:
	var tt := Time.get_ticks_msec() / 1000.0
	for id in puppets.keys():
		var n: Node3D = puppets[id]
		var tp: Vector3 = ptarget.get(id, n.position)
		var before := n.position
		n.position = n.position.lerp(tp, clampf(10.0 * delta, 0.0, 1.0))
		n.rotation.y = lerp_angle(n.rotation.y, float(pyaw.get(id, 0.0)), clampf(10.0 * delta, 0.0, 1.0))
		var mv := (n.position - before).length() / maxf(delta, 0.001)
		var m: Node3D = pmesh[id]
		if mv > 0.4:
			m.position.y = absf(sin(tt * 9.0 + float(id))) * 0.07
		else:
			m.position.y = 0.0

func _send_hit(id: int, dmg: float) -> void:
	if multiplayer.is_server():
		_server_hit(id, dmg, 1)
	else:
		_rpc_hit.rpc_id(1, id, dmg)

@rpc("any_peer", "reliable")
func _rpc_hit(id: int, dmg: float) -> void:
	_server_hit(id, minf(dmg, 30.0), multiplayer.get_remote_sender_id())

func _server_hit(id: int, dmg: float, who: int) -> void:
	if not ents.has(id):
		return
	var e: Dictionary = ents[id]
	e["hp"] = float(e["hp"]) - dmg
	e["from"] = _peer_pos(who)
	if int(e["type"]) == T_NATIVE:
		for o in ents.values():
			if int(o["type"]) == T_NATIVE and _flat(o["home"], e["home"]) < 1.0:
				o["hostile"] = true
				o["tpeer"] = who
				o["alert"] = 40.0
	else:
		e["flee"] = 6.0
	if float(e["hp"]) <= 0.0:
		_kill(id, who)

func _loot_for(ty: int) -> Dictionary:
	if ty == T_COW:
		return {"meat": 3}
	if ty == T_PIG:
		return {"meat": 2}
	if ty == T_SHEEP:
		return {"meat": 1, "wool": 2}
	if ty == T_CHICK:
		return {"meat": 1, "feather": 2}
	var d := {"wood": 2, "stone": 1, "feather": 2, "meat": 1}
	if randf() < 0.3:
		d["spear"] = 1
	return d

func _kill(id: int, who: int) -> void:
	var e: Dictionary = ents[id]
	var loot := _loot_for(int(e["type"]))
	ents.erase(id)
	if who == 1 or not _net():
		_apply_loot(loot)
	else:
		_rpc_loot.rpc_id(who, loot)

func _apply_loot(loot: Dictionary) -> void:
	var parts := PackedStringArray()
	for k in loot.keys():
		main._add(k, int(loot[k]))
		parts.append("%s x%d" % [main.ITEMS[k][0], int(loot[k])])
	main._say("Nhận: " + ", ".join(parts))

@rpc("authority", "reliable")
func _rpc_loot(loot: Dictionary) -> void:
	_apply_loot(loot)

# ---------- MESH ----------
func _newst() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

func _vtri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, outv: Vector3) -> void:
	var nrm := (b - a).cross(c - a).normalized()
	if nrm.dot(outv) < 0.0:
		nrm = -nrm
	var vs := [a, b, c]
	var cs := [ca, cb, cc]
	for k in 3:
		var col: Color = cs[k]
		st.set_normal(nrm)
		st.set_color(col)
		st.add_vertex(vs[k])

func _frustum(st: SurfaceTool, ox: float, oz: float, y0: float, y1: float, r0: float, r1: float, cb: Color, ct: Color, sides: int) -> void:
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var am := (a0 + a1) * 0.5
		var outv := Vector3(cos(am), 0.15, sin(am))
		var b0 := Vector3(ox + cos(a0) * r0, y0, oz + sin(a0) * r0)
		var b1 := Vector3(ox + cos(a1) * r0, y0, oz + sin(a1) * r0)
		var t0 := Vector3(ox + cos(a0) * r1, y1, oz + sin(a0) * r1)
		var t1 := Vector3(ox + cos(a1) * r1, y1, oz + sin(a1) * r1)
		_vtri(st, b0, t0, b1, cb, ct, cb, outv)
		if r1 > 0.001:
			_vtri(st, b1, t0, t1, cb, ct, ct, outv)
			_vtri(st, Vector3(ox, y1, oz), t0, t1, ct, ct, ct, Vector3.UP)

func _fr(st: SurfaceTool, ox: float, oz: float, y0: float, y1: float, r0: float, r1: float, col: Color, sides: int) -> void:
	_frustum(st, ox, oz, y0, y1, r0, r1, col, col, sides)

func _bt(st: SurfaceTool, c: Vector3, rad: Vector3, col: Color, sd: float, p0: Vector3, p1: Vector3, p2: Vector3) -> void:
	for p in [p0, p1, p2]:
		var dir: Vector3 = p
		var j := 1.0 + 0.14 * sin(dir.x * 6.0 + sd) * cos(dir.y * 5.0 + sd * 1.7) + 0.08 * sin(dir.z * 9.0 + sd * 0.6)
		var pos := c + Vector3(dir.x * rad.x, dir.y * rad.y, dir.z * rad.z) * j
		var shade := 0.82 + 0.28 * (dir.y * 0.5 + 0.5)
		st.set_normal(dir)
		st.set_color(Color(col.r * shade, col.g * shade, col.b * shade))
		st.add_vertex(pos)

func _blob(st: SurfaceTool, c: Vector3, rad: Vector3, col: Color, sd: float, sub: bool) -> void:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var vs: Array = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var fs: Array = [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for f in fs:
		var a: Vector3 = (vs[f[0]] as Vector3).normalized()
		var b: Vector3 = (vs[f[1]] as Vector3).normalized()
		var d: Vector3 = (vs[f[2]] as Vector3).normalized()
		if sub:
			var ab := ((a + b) * 0.5).normalized()
			var bd := ((b + d) * 0.5).normalized()
			var da := ((d + a) * 0.5).normalized()
			_bt(st, c, rad, col, sd, a, ab, da)
			_bt(st, c, rad, col, sd, ab, b, bd)
			_bt(st, c, rad, col, sd, da, bd, d)
			_bt(st, c, rad, col, sd, ab, bd, da)
		else:
			_bt(st, c, rad, col, sd, a, b, d)

func _legs(st: SurfaceTool, xs: float, zs: float, h: float, r: float, col: Color) -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_fr(st, xs * sx, zs * sz, 0.0, h, r, r * 0.9, col, 5)

func _build_meshes() -> void:
	meshes["cow"] = _mesh_cow()
	meshes["pig"] = _mesh_pig()
	meshes["sheep"] = _mesh_sheep()
	meshes["chick"] = _mesh_chick()
	meshes["native"] = _mesh_native()
	meshes["hut"] = _mesh_hut()
	meshes["totem"] = _mesh_totem()
	meshes["flame"] = _mesh_flame()
	meshes["stone"] = _mesh_stone()
	meshes["sprout"] = _mesh_sprout()
	meshes["leaf"] = _mesh_leaf()
	meshes["p0"] = _mesh_carrot()
	meshes["p1"] = _mesh_cabbage()
	meshes["p2"] = _mesh_pumpkin()
	meshes["p3"] = _mesh_apple_tree()

func _mesh_cow() -> ArrayMesh:
	var st := _newst()
	var white := Color(0.93, 0.93, 0.9)
	var blk := Color(0.14, 0.12, 0.12)
	_blob(st, Vector3(0, 1.05, 0), Vector3(0.55, 0.5, 0.95), white, 1.0, true)
	_blob(st, Vector3(0.28, 1.2, 0.25), Vector3(0.3, 0.3, 0.4), blk, 2.0, false)
	_blob(st, Vector3(-0.25, 1.15, -0.35), Vector3(0.3, 0.28, 0.35), blk, 3.0, false)
	_blob(st, Vector3(0, 1.4, -1.05), Vector3(0.32, 0.3, 0.36), white, 4.0, false)
	_blob(st, Vector3(0, 1.25, -1.4), Vector3(0.22, 0.17, 0.17), Color(0.9, 0.6, 0.6), 5.0, false)
	_fr(st, 0.2, -1.0, 1.6, 1.95, 0.05, 0.0, Color(0.9, 0.85, 0.7), 4)
	_fr(st, -0.2, -1.0, 1.6, 1.95, 0.05, 0.0, Color(0.9, 0.85, 0.7), 4)
	_legs(st, 0.3, 0.6, 0.75, 0.1, Color(0.25, 0.2, 0.18))
	return st.commit()

func _mesh_pig() -> ArrayMesh:
	var st := _newst()
	var pink := Color(0.95, 0.65, 0.68)
	_blob(st, Vector3(0, 0.7, 0), Vector3(0.45, 0.4, 0.7), pink, 1.0, true)
	_blob(st, Vector3(0, 0.75, -0.8), Vector3(0.3, 0.28, 0.3), pink, 2.0, false)
	_blob(st, Vector3(0, 0.68, -1.08), Vector3(0.16, 0.12, 0.1), Color(0.85, 0.5, 0.55), 3.0, false)
	_blob(st, Vector3(0.2, 1.0, -0.8), Vector3(0.1, 0.12, 0.06), pink, 4.0, false)
	_blob(st, Vector3(-0.2, 1.0, -0.8), Vector3(0.1, 0.12, 0.06), pink, 5.0, false)
	_blob(st, Vector3(0, 0.85, 0.75), Vector3(0.06, 0.06, 0.06), pink, 6.0, false)
	_legs(st, 0.22, 0.4, 0.45, 0.08, Color(0.85, 0.55, 0.58))
	return st.commit()

func _mesh_sheep() -> ArrayMesh:
	var st := _newst()
	var wool := Color(0.95, 0.95, 0.92)
	var dark := Color(0.25, 0.22, 0.2)
	_blob(st, Vector3(0, 0.95, 0), Vector3(0.55, 0.45, 0.65), wool, 1.0, true)
	_blob(st, Vector3(0, 1.15, 0.15), Vector3(0.45, 0.35, 0.45), wool, 2.0, false)
	_blob(st, Vector3(0.3, 0.9, -0.3), Vector3(0.3, 0.3, 0.3), wool, 3.0, false)
	_blob(st, Vector3(-0.3, 0.9, -0.3), Vector3(0.3, 0.3, 0.3), wool, 4.0, false)
	_blob(st, Vector3(0, 1.05, -0.8), Vector3(0.22, 0.24, 0.26), dark, 5.0, false)
	_legs(st, 0.22, 0.4, 0.65, 0.07, dark)
	return st.commit()

func _mesh_chick() -> ArrayMesh:
	var st := _newst()
	var white := Color(0.97, 0.97, 0.95)
	_blob(st, Vector3(0, 0.42, 0), Vector3(0.2, 0.2, 0.27), white, 1.0, false)
	_blob(st, Vector3(0, 0.72, -0.2), Vector3(0.1, 0.1, 0.1), white, 2.0, false)
	_blob(st, Vector3(0, 0.84, -0.2), Vector3(0.04, 0.06, 0.07), Color(0.9, 0.1, 0.1), 3.0, false)
	_blob(st, Vector3(0, 0.7, -0.32), Vector3(0.04, 0.03, 0.06), Color(0.95, 0.6, 0.1), 4.0, false)
	_blob(st, Vector3(0, 0.55, 0.3), Vector3(0.08, 0.14, 0.1), Color(0.8, 0.8, 0.78), 5.0, false)
	_fr(st, 0.07, 0.0, 0.0, 0.25, 0.02, 0.02, Color(0.95, 0.75, 0.2), 3)
	_fr(st, -0.07, 0.0, 0.0, 0.25, 0.02, 0.02, Color(0.95, 0.75, 0.2), 3)
	return st.commit()

func _mesh_native() -> ArrayMesh:
	var st := _newst()
	var skin := Color(0.62, 0.42, 0.28)
	_fr(st, -0.12, 0.0, 0.0, 0.8, 0.1, 0.09, skin, 5)
	_fr(st, 0.12, 0.0, 0.0, 0.8, 0.1, 0.09, skin, 5)
	_frustum(st, 0, 0, 0.7, 1.45, 0.34, 0.26, Color(0.7, 0.25, 0.15), Color(0.85, 0.55, 0.2), 7)
	_fr(st, -0.38, 0.0, 0.85, 1.4, 0.07, 0.06, skin, 5)
	_fr(st, 0.38, 0.0, 0.85, 1.4, 0.07, 0.06, skin, 5)
	_blob(st, Vector3(0, 1.65, 0), Vector3(0.2, 0.22, 0.2), skin, 1.0, false)
	_blob(st, Vector3(0, 1.78, 0.03), Vector3(0.21, 0.14, 0.21), Color(0.1, 0.07, 0.05), 2.0, false)
	_fr(st, 0.0, 0.0, 1.62, 1.7, 0.215, 0.215, Color(0.8, 0.15, 0.1), 8)
	_fr(st, 0.12, 0.0, 1.75, 2.15, 0.04, 0.0, Color(0.9, 0.2, 0.2), 4)
	_fr(st, -0.12, 0.0, 1.75, 2.15, 0.04, 0.0, Color(0.2, 0.6, 0.9), 4)
	_fr(st, 0.5, -0.1, 0.0, 2.2, 0.025, 0.025, Color(0.5, 0.35, 0.2), 4)
	_fr(st, 0.5, -0.1, 2.2, 2.5, 0.05, 0.0, Color(0.6, 0.6, 0.62), 4)
	return st.commit()

func _mesh_hut() -> ArrayMesh:
	var st := _newst()
	_frustum(st, 0, 0, 0.0, 2.0, 2.1, 1.9, Color(0.5, 0.36, 0.22), Color(0.62, 0.47, 0.3), 8)
	_frustum(st, 0, 0, 1.8, 4.2, 2.8, 0.0, Color(0.55, 0.4, 0.12), Color(0.82, 0.68, 0.28), 8)
	_blob(st, Vector3(0, 0.7, 2.0), Vector3(0.5, 0.7, 0.15), Color(0.12, 0.08, 0.06), 1.0, false)
	return st.commit()

func _mesh_totem() -> ArrayMesh:
	var st := _newst()
	_fr(st, 0, 0, 0.0, 1.5, 0.5, 0.48, Color(0.4, 0.27, 0.15), 6)
	_fr(st, 0, 0, 1.5, 3.0, 0.45, 0.45, Color(0.75, 0.2, 0.15), 6)
	_fr(st, 0, 0, 3.0, 4.5, 0.45, 0.45, Color(0.9, 0.75, 0.2), 6)
	_fr(st, 0, 0, 4.5, 6.0, 0.45, 0.45, Color(0.92, 0.92, 0.88), 6)
	_fr(st, 0, 0, 6.0, 7.2, 0.5, 0.0, Color(0.2, 0.45, 0.8), 6)
	return st.commit()

func _mesh_flame() -> ArrayMesh:
	var st := _newst()
	_fr(st, 0, 0, 0.0, 0.9, 0.4, 0.0, Color(1.0, 0.55, 0.1), 5)
	_fr(st, 0, 0, 0.0, 0.5, 0.25, 0.0, Color(1.0, 0.9, 0.3), 5)
	return st.commit()

func _mesh_stone() -> ArrayMesh:
	var st := _newst()
	_blob(st, Vector3(0, 0.55, 0), Vector3(1.1, 0.75, 1.0), Color(0.5, 0.49, 0.47), 0.7, true)
	return st.commit()

func _leaves(st: SurfaceTool, ox: float, oz: float, n: int, hh: float, cb: Color, ct: Color) -> void:
	for k in n:
		var a := float(k) * TAU / float(n) + 0.3
		var h2 := hh * (0.75 + 0.25 * float(k % 2))
		_frustum(st, ox + cos(a) * 0.12, oz + sin(a) * 0.12, 0.0, h2, 0.07, 0.0, cb, ct, 3)

func _mound(st: SurfaceTool, ox: float, oz: float) -> void:
	_blob(st, Vector3(ox, 0.0, oz), Vector3(0.45, 0.15, 0.45), Color(0.3, 0.2, 0.12), 1.0, false)

func _mesh_sprout() -> ArrayMesh:
	var st := _newst()
	_mound(st, 0.0, 0.0)
	_leaves(st, 0.0, 0.0, 2, 0.3, Color(0.15, 0.5, 0.15), Color(0.5, 0.8, 0.3))
	return st.commit()

func _mesh_leaf() -> ArrayMesh:
	var st := _newst()
	_mound(st, 0.0, 0.0)
	_leaves(st, 0.0, 0.0, 6, 0.6, Color(0.1, 0.4, 0.1), Color(0.45, 0.75, 0.25))
	return st.commit()

func _mesh_carrot() -> ArrayMesh:
	var st := _newst()
	var offs := [Vector2(0, 0), Vector2(0.75, 0.3), Vector2(-0.5, 0.65)]
	for o in offs:
		var v: Vector2 = o
		_mound(st, v.x, v.y)
		_leaves(st, v.x, v.y, 6, 0.75, Color(0.1, 0.4, 0.1), Color(0.45, 0.75, 0.25))
		_blob(st, Vector3(v.x + 0.1, 0.06, v.y + 0.05), Vector3(0.07, 0.06, 0.07), Color(0.95, 0.5, 0.1), 2.0, false)
		_blob(st, Vector3(v.x - 0.1, 0.06, v.y - 0.05), Vector3(0.07, 0.06, 0.07), Color(0.95, 0.5, 0.1), 3.0, false)
	return st.commit()

func _mesh_cabbage() -> ArrayMesh:
	var st := _newst()
	var offs := [Vector2(0, 0), Vector2(0.9, 0.3), Vector2(-0.5, 0.8)]
	for o in offs:
		var v: Vector2 = o
		_blob(st, Vector3(v.x, 0.22, v.y), Vector3(0.55, 0.2, 0.55), Color(0.2, 0.5, 0.2), 1.0, false)
		_blob(st, Vector3(v.x, 0.3, v.y), Vector3(0.45, 0.38, 0.45), Color(0.5, 0.75, 0.3), 2.0, false)
	return st.commit()

func _mesh_pumpkin() -> ArrayMesh:
	var st := _newst()
	var offs := [Vector2(0, 0), Vector2(0.95, 0.5)]
	for o in offs:
		var v: Vector2 = o
		_blob(st, Vector3(v.x, 0.4, v.y), Vector3(0.62, 0.45, 0.62), Color(0.95, 0.5, 0.1), 1.0, true)
		_fr(st, v.x, v.y, 0.8, 1.0, 0.07, 0.05, Color(0.25, 0.4, 0.15), 4)
		_leaves(st, v.x + 0.5, v.y - 0.3, 3, 0.5, Color(0.1, 0.4, 0.1), Color(0.4, 0.7, 0.2))
	return st.commit()

func _mesh_apple_tree() -> ArrayMesh:
	var st := _newst()
	var g1 := Color(0.2, 0.52, 0.14)
	var g2 := Color(0.3, 0.62, 0.18)
	_frustum(st, 0, 0, 0.0, 2.6, 0.45, 0.3, Color(0.3, 0.2, 0.12), Color(0.42, 0.29, 0.17), 6)
	_blob(st, Vector3(0, 3.6, 0), Vector3(2.0, 1.6, 2.0), g1, 1.0, false)
	_blob(st, Vector3(0.9, 4.5, 0.3), Vector3(1.5, 1.3, 1.5), g2, 2.3, false)
	_blob(st, Vector3(-0.8, 4.7, -0.4), Vector3(1.4, 1.3, 1.4), g2, 3.7, false)
	var red := Color(0.9, 0.12, 0.12)
	var ap := [Vector3(1.6, 3.4, 0.4), Vector3(-1.5, 3.5, 0.6), Vector3(0.5, 3.1, 1.7), Vector3(-0.6, 3.2, -1.7),
		Vector3(1.1, 4.3, 1.1), Vector3(-1.2, 4.4, -0.8), Vector3(0.2, 5.0, 1.0)]
	for a in ap:
		var pa: Vector3 = a
		_blob(st, pa, Vector3(0.2, 0.2, 0.2), red, pa.x * 3.0, false)
	return st.commit()
