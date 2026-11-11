extends Node

const WATER := -3.0
const BASE := Vector3(0.36, -0.42, -0.72)

var TOOLS := ["hand", "axe", "pick", "sword", "bow", "rod"]
var TNAME := {"hand": "Tay", "axe": "Rìu", "pick": "Cuốc", "sword": "Kiếm", "bow": "Cung", "rod": "Cần câu"}
var REST := {
	"hand": [Vector3(-10, 0, 8), Vector3(0, 0, 0), Vector3(1, 1, 1)],
	"axe": [Vector3(-18, 0, 14), Vector3(0, 0, 0), Vector3(1, 1, 1)],
	"pick": [Vector3(-18, 0, 14), Vector3(0, 0, 0), Vector3(1, 1, 1)],
	"sword": [Vector3(-20, 0, 15), Vector3(0, 0, 0), Vector3(1.6, 1, 0.45)],
	"bow": [Vector3(0, 0, 0), Vector3(-0.1, 0.12, 0), Vector3(1, 1, 1)],
	"rod": [Vector3(-35, 0, 8), Vector3(0, 0, 0), Vector3(1, 1, 1)],
}
# mỗi khung: [thời điểm, xoay (độ), dịch chuyển]
var ANIMS := {
	"punch": {"dur": 0.35, "hit": 0.12, "keys": [
		[0.0, Vector3(0, 0, 0), Vector3(0, 0, 0)],
		[0.12, Vector3(-15, 0, 0), Vector3(0, 0.1, -0.28)],
		[0.35, Vector3(0, 0, 0), Vector3(0, 0, 0)]]},
	"slash": {"dur": 0.62, "hit": 0.3, "keys": [
		[0.0, Vector3(0, 0, 0), Vector3(0, 0, 0)],
		[0.2, Vector3(25, 0, -50), Vector3(0.1, 0.05, 0.1)],
		[0.4, Vector3(-55, 0, 60), Vector3(-0.18, -0.05, -0.12)],
		[0.62, Vector3(0, 0, 0), Vector3(0, 0, 0)]]},
	"chop": {"dur": 0.75, "hit": 0.42, "keys": [
		[0.0, Vector3(0, 0, 0), Vector3(0, 0, 0)],
		[0.28, Vector3(60, 0, 0), Vector3(0, 0.14, 0.12)],
		[0.46, Vector3(-65, 0, 6), Vector3(0, -0.1, -0.2)],
		[0.75, Vector3(0, 0, 0), Vector3(0, 0, 0)]]},
	"mine": {"dur": 0.9, "hit": 0.45, "keys": [
		[0.0, Vector3(0, 0, 0), Vector3(0, 0, 0)],
		[0.3, Vector3(65, 0, 0), Vector3(0, 0.15, 0.14)],
		[0.48, Vector3(-60, 0, 0), Vector3(0, -0.1, -0.22)],
		[0.6, Vector3(-48, 0, 0), Vector3(0, -0.07, -0.16)],
		[0.9, Vector3(0, 0, 0), Vector3(0, 0, 0)]]},
	"cast": {"dur": 0.8, "hit": 0.45, "keys": [
		[0.0, Vector3(0, 0, 0), Vector3(0, 0, 0)],
		[0.25, Vector3(45, 0, 0), Vector3(0, 0.1, 0.12)],
		[0.45, Vector3(-45, 0, 0), Vector3(0, 0, -0.2)],
		[0.8, Vector3(-10, 0, 0), Vector3(0, 0, -0.05)]]},
	"reel": {"dur": 0.6, "hit": 0.2, "keys": [
		[0.0, Vector3(0, 0, 0), Vector3(0, 0, 0)],
		[0.2, Vector3(35, 0, 0), Vector3(0, 0.1, 0.1)],
		[0.6, Vector3(0, 0, 0), Vector3(0, 0, 0)]]},
	"bow": {"dur": 0.95, "hit": 0.5, "keys": [
		[0.0, Vector3(0, 0, 0), Vector3(0, 0, 0)],
		[0.5, Vector3(-8, 0, 0), Vector3(0, 0.04, -0.08)],
		[0.58, Vector3(-3, 0, 0), Vector3(0, 0.02, 0.02)],
		[0.95, Vector3(0, 0, 0), Vector3(0, 0, 0)]]},
}

var main = null
var vmat := StandardMaterial3D.new()
var line_mat := StandardMaterial3D.new()
var meshes := {}
var world_root: Node3D

var vm: Node3D
var grip: Node3D
var tool_root: Node3D
var tip: Node3D
var b_string: MeshInstance3D
var b_arrow: MeshInstance3D
var b_hand: MeshInstance3D

var held := "hand"
var anim := ""
var anim_t := 0.0
var anim_fired := false
var t_now := 0.0
var bar_sig := ""
var bar_btns := {}
var arrows: Array = []

var fish_state := "idle"
var fish_t := 0.0
var fish_pos := Vector3.ZERO
var bobber: MeshInstance3D
var line: MeshInstance3D

var ui: CanvasLayer
var bar: HBoxContainer
var use_btn: Button
var bar_t := 0.0

func _ready() -> void:
	vmat.vertex_color_use_as_albedo = true
	vmat.vertex_color_is_srgb = true
	vmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	vmat.roughness = 1.0
	vmat.metallic_specular = 0.1
	line_mat.albedo_color = Color(1, 1, 1, 0.8)
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	world_root = Node3D.new()
	add_child(world_root)
	_build_meshes()
	_build_ui()

func _process(delta: float) -> void:
	if main == null:
		var cs := get_tree().current_scene
		if cs != null and cs.get("started") != null and cs.get("cam") != null and cs.get("ITEMS") != null:
			main = cs
			_setup()
		return
	if not is_instance_valid(main):
		_reset()
		return
	var on: bool = main.started
	bar.visible = on
	use_btn.visible = on
	vm.visible = on and not main.panel.visible
	if not on:
		return
	t_now += delta
	bar_t += delta
	if bar_t >= 0.5:
		bar_t = 0.0
		_refresh_bar()

	var rot := Vector3.ZERO
	var pos := Vector3.ZERO
	var prog := 0.0
	if anim != "":
		anim_t += delta
		var d: Dictionary = ANIMS[anim]
		prog = anim_t
		if not anim_fired and anim_t >= float(d["hit"]):
			anim_fired = true
			_event(anim)
		var s := _sample(anim, anim_t)
		rot = s[0]
		pos = s[1]
		if anim_t >= float(d["dur"]):
			anim = ""
	var hold := Vector3.ZERO
	if held == "rod" and fish_state != "idle":
		hold = Vector3(-12, 0, 0)
		if fish_state == "bite":
			hold.z = sin(t_now * 40.0) * 6.0
	var mv: float = main.move_vec.length()
	var bob := Vector3(sin(t_now * 9.0) * 0.012 * mv, absf(sin(t_now * 9.0)) * 0.012 * mv + sin(t_now * 1.6) * 0.004, 0.0)
	var rest: Array = REST[held]
	grip.rotation_degrees = (rest[0] as Vector3) + rot + hold
	grip.position = (rest[1] as Vector3) + pos + bob

	if held == "bow" and b_string != null:
		var draw := 0.0
		if anim == "bow" and prog < 0.5:
			draw = clampf(prog / 0.5, 0.0, 1.0)
		b_string.position.z = draw * 0.35
		b_arrow.position.z = draw * 0.35
		b_hand.position.z = draw * 0.35
		b_arrow.visible = main._has("arrow")

	_update_fishing(delta)
	_update_arrows(delta)

func _setup() -> void:
	var it: Dictionary = main.ITEMS
	it["sword"] = ["Kiếm đá", Color(0.7, 0.72, 0.78)]
	it["bow"] = ["Cung gỗ", Color(0.6, 0.42, 0.22)]
	it["arrow"] = ["Mũi tên", Color(0.85, 0.8, 0.6)]
	it["rod"] = ["Cần câu", Color(0.5, 0.35, 0.2)]
	it["fish"] = ["Cá", Color(0.5, 0.7, 0.85)]
	it["grilled"] = ["Cá nướng", Color(0.8, 0.5, 0.25)]
	var rec: Array = main.RECIPES
	rec.append({"id": "sword", "name": "Kiếm đá", "need": {"wood": 2, "stone": 3, "fiber": 1}, "fire": false})
	rec.append({"id": "bow", "name": "Cung gỗ", "need": {"wood": 3, "fiber": 3}, "fire": false})
	rec.append({"id": "arrow", "name": "Mũi tên", "need": {"wood": 1, "stone": 1}, "fire": false})
	rec.append({"id": "rod", "name": "Cần câu", "need": {"wood": 3, "fiber": 2}, "fire": false})
	rec.append({"id": "grilled", "name": "Cá nướng", "need": {"fish": 1}, "fire": true})
	main._load_inv()
	_build_vm()
	_set_held("hand")

func _reset() -> void:
	main = null
	vm = null
	grip = null
	tool_root = null
	tip = null
	b_string = null
	b_arrow = null
	b_hand = null
	bobber = null
	line = null
	held = "hand"
	anim = ""
	fish_state = "idle"
	arrows.clear()
	bar_sig = ""
	for ch in world_root.get_children():
		ch.queue_free()
	bar.visible = false
	use_btn.visible = false

# ---------- GIAO DIỆN ----------
func _mkbtn(t: String, w: float, h: float) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_size_override("font_size", 24)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.5)
	sb.set_corner_radius_all(18)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	var sp := StyleBoxFlat.new()
	sp.bg_color = Color(0.3, 0.3, 0.3, 0.8)
	sp.set_corner_radius_all(18)
	b.add_theme_stylebox_override("pressed", sp)
	return b

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	bar = HBoxContainer.new()
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -420
	bar.offset_right = 420
	bar.offset_top = -92
	bar.offset_bottom = -16
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 10)
	bar.visible = false
	ui.add_child(bar)
	use_btn = _mkbtn("Dùng", 200, 90)
	use_btn.anchor_left = 1.0
	use_btn.anchor_right = 1.0
	use_btn.anchor_top = 1.0
	use_btn.anchor_bottom = 1.0
	use_btn.offset_left = -220
	use_btn.offset_right = -20
	use_btn.offset_top = -460
	use_btn.offset_bottom = -370
	use_btn.add_theme_font_size_override("font_size", 32)
	use_btn.visible = false
	use_btn.pressed.connect(_use_tool)
	ui.add_child(use_btn)

func _refresh_bar() -> void:
	var sig := ""
	for id in TOOLS:
		if id == "hand" or main._has(id):
			sig += id + ","
	if sig != bar_sig:
		bar_sig = sig
		for ch in bar.get_children():
			bar.remove_child(ch)
			ch.queue_free()
		bar_btns.clear()
		for id in TOOLS:
			if id == "hand" or main._has(id):
				var b := _mkbtn(TNAME[id], 120, 70)
				b.pressed.connect(_set_held.bind(id))
				bar.add_child(b)
				bar_btns[id] = b
		if held != "hand" and not main._has(held):
			_set_held("hand")
	for id in bar_btns.keys():
		var bb: Button = bar_btns[id]
		bb.modulate = Color(1, 1, 1) if id == held else Color(0.55, 0.55, 0.55)

# ---------- ĂN & CẦM ĐỒ TỪ TÚI ----------
func use_item(id: String) -> bool:
	if main == null:
		return false
	if id != "hand" and TOOLS.has(id):
		_set_held(id)
		main._say("Đã cầm " + main.ITEMS[id][0])
		return true
	if id == "arrow":
		main._say("Mũi tên dùng cùng Cung gỗ")
		return true
	if id == "fish":
		_eat(id, 14.0, -3.0, "Ăn cá sống (+14 no). Nên nướng!")
		return true
	if id == "grilled":
		_eat(id, 40.0, 5.0, "Ăn cá nướng (+40 no)")
		return true
	return false

func _eat(id: String, hun: float, hpd: float, txt: String) -> void:
	main.hunger = clampf(main.hunger + hun, 0.0, 100.0)
	main.hp = clampf(main.hp + hpd, 1.0, 100.0)
	main._spend(id, 1)
	main._say(txt)

# ---------- DỤNG CỤ TRÊN TAY ----------
func _build_vm() -> void:
	vm = Node3D.new()
	vm.position = BASE
	main.cam.add_child(vm)
	grip = Node3D.new()
	vm.add_child(grip)
	var arm := MeshInstance3D.new()
	arm.mesh = meshes["arm"]
	arm.material_override = vmat
	arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grip.add_child(arm)
	tool_root = Node3D.new()
	grip.add_child(tool_root)
	tip = Node3D.new()
	tip.position = Vector3(0, 1.55, 0)
	grip.add_child(tip)

func _part(m: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = vmat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _set_held(id: String) -> void:
	if main == null or grip == null:
		return
	if id != "rod" and fish_state != "idle":
		_fish_end()
	held = id
	anim = ""
	for ch in tool_root.get_children():
		tool_root.remove_child(ch)
		ch.queue_free()
	b_string = null
	b_arrow = null
	b_hand = null
	var r: Array = REST[id]
	tool_root.scale = r[2]
	if id == "bow":
		tool_root.add_child(_part(meshes["bowlimb"]))
		b_string = _part(meshes["string"])
		tool_root.add_child(b_string)
		b_arrow = _part(meshes["arrow"])
		b_arrow.rotation_degrees = Vector3(-90, 0, 0)
		b_arrow.scale = Vector3(0.8, 0.8, 0.8)
		tool_root.add_child(b_arrow)
		b_hand = _part(meshes["fist"])
		tool_root.add_child(b_hand)
	elif meshes.has(id):
		tool_root.add_child(_part(meshes[id]))
	for bid in bar_btns.keys():
		var bb: Button = bar_btns[bid]
		bb.modulate = Color(1, 1, 1) if bid == held else Color(0.55, 0.55, 0.55)

func _sample(name: String, t: float) -> Array:
	var keys: Array = ANIMS[name]["keys"]
	for i in range(keys.size() - 1):
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		var t0: float = a[0]
		var t1: float = b[0]
		if t >= t0 and t <= t1:
			var u := smoothstep(0.0, 1.0, (t - t0) / maxf(t1 - t0, 0.001))
			var ra: Vector3 = a[1]
			var rb: Vector3 = b[1]
			var pa: Vector3 = a[2]
			var pb: Vector3 = b[2]
			return [ra.lerp(rb, u), pa.lerp(pb, u)]
	var last: Array = keys[keys.size() - 1]
	return [last[1], last[2]]

func _play(a: String) -> void:
	anim = a
	anim_t = 0.0
	anim_fired = false

func _use_tool() -> void:
	if main == null:
		return
	if held == "rod":
		_rod_press()
		return
	if anim != "":
		return
	if held == "hand":
		_play("punch")
	elif held == "axe":
		_play("chop")
	elif held == "pick":
		_play("mine")
	elif held == "sword":
		_play("slash")
	elif held == "bow":
		if not main._has("arrow"):
			main._say("Hết mũi tên! Chế thêm trong túi đồ")
			return
		_play("bow")

func _event(a: String) -> void:
	if a == "punch" or a == "chop" or a == "mine":
		main._gather()
	elif a == "slash":
		_sword_hit()
	elif a == "bow":
		_fire_arrow()
	elif a == "cast":
		_do_cast()

func _sword_hit() -> void:
	var f = get_node_or_null("/root/Fauna")
	if f == null:
		return
	var t: Dictionary = f._find(3.9, 0.3, true, false)
	if t.is_empty():
		main._say("Chém vào khoảng không")
		return
	f._send_hit(int(t["id"]), 16.0)
	main._say("Chém trúng! (-16)")

# ---------- CUNG TÊN ----------
func _fire_arrow() -> void:
	if not main._has("arrow"):
		return
	main._spend("arrow", 1)
	var c: Camera3D = main.cam
	var b := c.global_transform.basis
	var dir := -b.z
	var n := Node3D.new()
	var m := _part(meshes["arrow"])
	m.rotation_degrees = Vector3(-90, 0, 0)
	n.add_child(m)
	world_root.add_child(n)
	n.global_position = c.global_position + dir * 0.9 + b.x * 0.18 - b.y * 0.15
	arrows.append({"node": n, "vel": dir * 40.0, "life": 5.0, "stuck": false})
	main._say("Bắn! Còn %d mũi tên" % int(main.inv.get("arrow", 0)))

func _update_arrows(delta: float) -> void:
	var f = get_node_or_null("/root/Fauna")
	for a in arrows.duplicate():
		var n: Node3D = a["node"]
		a["life"] = float(a["life"]) - delta
		if float(a["life"]) <= 0.0:
			n.queue_free()
			arrows.erase(a)
			continue
		if a["stuck"]:
			continue
		var v: Vector3 = a["vel"]
		v.y -= 14.0 * delta
		a["vel"] = v
		var p := n.global_position + v * delta
		n.global_position = p
		n.look_at(p + v, Vector3.UP)
		var h: float = main._height(p.x, p.z)
		if p.y <= h + 0.05:
			a["stuck"] = true
			a["life"] = 6.0
			continue
		if f != null:
			for id in f.puppets.keys():
				var pn: Node3D = f.puppets[id]
				if Vector2(p.x - pn.position.x, p.z - pn.position.z).length() < 1.1 and p.y > pn.position.y - 0.2 and p.y < pn.position.y + 2.4:
					f._send_hit(int(id), 16.0)
					main._say("Bắn trúng!")
					n.queue_free()
					arrows.erase(a)
					break

# ---------- CÂU CÁ ----------
func _find_water() -> Variant:
	var p: Vector3 = main.player.position
	var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, main.yaw)
	for i in range(4, 17):
		var q := p + fwd * float(i)
		if main._height(q.x, q.z) < WATER - 0.4:
			return Vector3(q.x, WATER, q.z)
	return null

func _rod_press() -> void:
	if fish_state == "idle":
		if anim != "":
			return
		var w = _find_water()
		if w == null:
			main._say("Hãy hướng cần câu về phía nước (hồ)")
			return
		fish_pos = w
		_play("cast")
	elif fish_state == "wait":
		main._say("Chưa có cá, đã kéo cần lên")
		_fish_end()
	else:
		var n := 1
		if randf() < 0.12:
			n = 3
		main._add("fish", n)
		if n == 3:
			main._say("Câu được cá lớn! +3 Cá")
		else:
			main._say("Câu được cá! +1 Cá")
		_fish_end()
		_play("reel")

func _do_cast() -> void:
	if bobber == null:
		bobber = _part(meshes["bobber"])
		world_root.add_child(bobber)
	if line == null:
		line = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.01, 0.01, 1.0)
		line.mesh = bm
		line.material_override = line_mat
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world_root.add_child(line)
	bobber.visible = true
	line.visible = true
	bobber.global_position = fish_pos + Vector3(0, 0.05, 0)
	fish_state = "wait"
	fish_t = randf_range(3.0, 8.0)
	main._say("Đã quăng câu, chờ cá cắn...")

func _fish_end() -> void:
	fish_state = "idle"
	if bobber != null:
		bobber.visible = false
	if line != null:
		line.visible = false

func _update_fishing(delta: float) -> void:
	if fish_state == "idle":
		return
	var p: Vector3 = main.player.position
	if Vector2(p.x - fish_pos.x, p.z - fish_pos.z).length() > 20.0:
		main._say("Bạn đi xa quá, dây câu đứt")
		_fish_end()
		return
	if fish_state == "wait":
		fish_t -= delta
		bobber.global_position = fish_pos + Vector3(0, 0.05 + sin(t_now * 2.0) * 0.02, 0)
		if fish_t <= 0.0:
			fish_state = "bite"
			fish_t = 1.6
			main._say("Cá cắn câu! Bấm DÙNG ngay!")
	else:
		fish_t -= delta
		bobber.global_position = fish_pos + Vector3(0, -0.1 + sin(t_now * 30.0) * 0.05, 0)
		if fish_t <= 0.0:
			main._say("Cá đã chạy mất")
			_fish_end()
	if line != null and line.visible and held == "rod":
		var a: Vector3 = tip.global_position
		var b: Vector3 = bobber.global_position
		var d := (a - b).length()
		if d > 0.05:
			line.look_at_from_position((a + b) * 0.5, b, Vector3.UP)
			line.scale = Vector3(1, 1, d)

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
		var j := 1.0 + 0.1 * sin(dir.x * 6.0 + sd) * cos(dir.y * 5.0 + sd * 1.7)
		var pos := c + Vector3(dir.x * rad.x, dir.y * rad.y, dir.z * rad.z) * j
		var shade := 0.85 + 0.25 * (dir.y * 0.5 + 0.5)
		st.set_normal(dir)
		st.set_color(Color(col.r * shade, col.g * shade, col.b * shade))
		st.add_vertex(pos)

func _blob(st: SurfaceTool, c: Vector3, rad: Vector3, col: Color, sd: float) -> void:
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
		_bt(st, c, rad, col, sd, a, b, d)

func _build_meshes() -> void:
	var skin := Color(0.78, 0.55, 0.4)
	var wood := Color(0.4, 0.27, 0.15)
	var stone := Color(0.58, 0.58, 0.6)

	var st := _newst()
	_frustum(st, 0, 0, -1.0, -0.05, 0.1, 0.075, Color(0.42, 0.28, 0.18), Color(0.5, 0.35, 0.22), 7)
	_blob(st, Vector3(0, 0.0, 0), Vector3(0.085, 0.09, 0.085), skin, 1.0)
	meshes["arm"] = st.commit()

	st = _newst()
	_blob(st, Vector3(0, 0, 0), Vector3(0.07, 0.07, 0.07), skin, 2.0)
	meshes["fist"] = st.commit()

	st = _newst()
	_fr(st, 0, 0, -0.14, 0.12, 0.035, 0.03, wood, 6)
	_blob(st, Vector3(0, -0.16, 0), Vector3(0.05, 0.04, 0.05), Color(0.7, 0.6, 0.2), 1.0)
	_blob(st, Vector3(0, 0.13, 0), Vector3(0.14, 0.025, 0.045), Color(0.5, 0.4, 0.25), 2.0)
	_frustum(st, 0, 0, 0.12, 0.92, 0.04, 0.03, Color(0.6, 0.62, 0.66), Color(0.88, 0.9, 0.94), 4)
	_fr(st, 0, 0, 0.92, 1.05, 0.03, 0.0, Color(0.9, 0.92, 0.96), 4)
	meshes["sword"] = st.commit()

	st = _newst()
	_fr(st, 0, 0, -0.12, 0.95, 0.035, 0.03, wood, 6)
	_blob(st, Vector3(0.12, 0.85, 0), Vector3(0.2, 0.16, 0.045), stone, 1.0)
	_blob(st, Vector3(0.28, 0.85, 0), Vector3(0.05, 0.2, 0.03), Color(0.75, 0.75, 0.78), 2.0)
	_blob(st, Vector3(0, 0.82, 0), Vector3(0.06, 0.06, 0.06), Color(0.55, 0.65, 0.3), 3.0)
	meshes["axe"] = st.commit()

	st = _newst()
	_fr(st, 0, 0, -0.12, 0.95, 0.035, 0.03, wood, 6)
	_blob(st, Vector3(0, 0.95, 0), Vector3(0.34, 0.06, 0.05), stone, 1.0)
	_blob(st, Vector3(0.32, 0.9, 0), Vector3(0.06, 0.09, 0.04), Color(0.72, 0.72, 0.75), 2.0)
	_blob(st, Vector3(-0.32, 0.9, 0), Vector3(0.06, 0.09, 0.04), Color(0.72, 0.72, 0.75), 3.0)
	meshes["pick"] = st.commit()

	st = _newst()
	_fr(st, 0, 0, -0.1, 1.6, 0.022, 0.008, Color(0.5, 0.35, 0.2), 5)
	_blob(st, Vector3(0.05, 0.22, 0), Vector3(0.05, 0.05, 0.04), Color(0.2, 0.2, 0.22), 1.0)
	_blob(st, Vector3(0, 0.0, 0), Vector3(0.045, 0.1, 0.045), Color(0.25, 0.18, 0.12), 2.0)
	meshes["rod"] = st.commit()

	st = _newst()
	for i in 9:
		var t := -1.0 + float(i) * 0.25
		var z := -0.15 * (1.0 - t * t)
		_blob(st, Vector3(0, t * 0.58, z), Vector3(0.03, 0.09, 0.03), Color(0.55, 0.38, 0.2), float(i))
	meshes["bowlimb"] = st.commit()

	st = _newst()
	_fr(st, 0, 0, -0.58, 0.58, 0.006, 0.006, Color(0.95, 0.95, 0.9), 3)
	meshes["string"] = st.commit()

	st = _newst()
	_fr(st, 0, 0, 0.0, 0.9, 0.012, 0.012, Color(0.6, 0.45, 0.25), 4)
	_fr(st, 0, 0, 0.9, 1.02, 0.03, 0.0, Color(0.7, 0.7, 0.72), 4)
	_blob(st, Vector3(0, 0.05, 0), Vector3(0.025, 0.05, 0.01), Color(0.85, 0.2, 0.2), 1.0)
	_blob(st, Vector3(0, 0.12, 0), Vector3(0.01, 0.05, 0.025), Color(0.85, 0.2, 0.2), 2.0)
	meshes["arrow"] = st.commit()

	st = _newst()
	_blob(st, Vector3(0, 0.04, 0), Vector3(0.1, 0.08, 0.1), Color(0.9, 0.15, 0.1), 1.0)
	_blob(st, Vector3(0, -0.04, 0), Vector3(0.1, 0.07, 0.1), Color(0.95, 0.95, 0.95), 2.0)
	meshes["bobber"] = st.commit()
