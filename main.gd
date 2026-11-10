extends Node3D

const PORT := 7777
const CHUNK_SIZE := 48.0
const RES := 20
const VIEW := 2
const WALK := 8.0
const RUN := 14.0
const WATER_Y := -3.0
const DAY_LEN := 480.0

var noise: FastNoiseLite
var mnoise: FastNoiseLite
var tnoise: FastNoiseLite
var dnoise: FastNoiseLite
var fnoise: FastNoiseLite
var mat := StandardMaterial3D.new()
var veg_mat := StandardMaterial3D.new()
var flame_mat := StandardMaterial3D.new()
var beam_mat := StandardMaterial3D.new()
var oak_mesh: ArrayMesh
var pine_mesh: ArrayMesh
var cactus_mesh: ArrayMesh
var rock_mesh: ArrayMesh
var bush_mesh: ArrayMesh
var tower_mesh: ArrayMesh
var tent_mesh: ArrayMesh
var flame_mesh: ArrayMesh
var env: Environment
var sun: DirectionalLight3D
var chunks := {}
var taken := {}
var felled := {}
var hits := {}
var res_list := {}
var camps := {}
var fires: Array = []
var pending: Array = []
var last_chunk := Vector2i(99999, 99999)
var biome_name := ""
var time_name := ""

var inv := {}
var ITEMS := {
	"wood": ["Gỗ", Color(0.55, 0.35, 0.18)],
	"stone": ["Đá", Color(0.6, 0.6, 0.62)],
	"fiber": ["Sợi", Color(0.6, 0.75, 0.25)],
	"berry": ["Quả", Color(0.85, 0.1, 0.25)],
	"roast": ["Quả nướng", Color(0.75, 0.4, 0.15)],
	"bandage": ["Băng gạc", Color(0.9, 0.9, 0.9)],
	"axe": ["Rìu đá", Color(0.45, 0.5, 0.75)],
	"pick": ["Cuốc đá", Color(0.4, 0.6, 0.7)],
	"spear": ["Giáo gỗ", Color(0.7, 0.55, 0.3)],
	"fire": ["Lửa trại", Color(1.0, 0.5, 0.1)],
}
var RECIPES := [
	{"id": "axe", "name": "Rìu đá", "need": {"wood": 3, "stone": 2, "fiber": 1}, "fire": false},
	{"id": "pick", "name": "Cuốc đá", "need": {"wood": 3, "stone": 3, "fiber": 1}, "fire": false},
	{"id": "spear", "name": "Giáo gỗ", "need": {"wood": 2, "stone": 1}, "fire": false},
	{"id": "fire", "name": "Lửa trại", "need": {"wood": 5, "stone": 3}, "fire": false},
	{"id": "roast", "name": "Quả nướng", "need": {"berry": 2}, "fire": true},
	{"id": "bandage", "name": "Băng gạc", "need": {"fiber": 3}, "fire": false},
]
var act_cd := 0.0

var player: Node3D
var pivot: Node3D
var cam: Camera3D
var water: MeshInstance3D
var others := {}
var targets := {}
var started := false
var send_timer := 0.0
var net_note := ""

var hp := 100.0
var hunger := 100.0
var thirst := 100.0
var stamina := 100.0
var running := false

var move_vec := Vector2.ZERO
var joy_id := -1
var look_id := -1
var run_id := -1
var joy_origin := Vector2.ZERO
var yaw := 0.0
var pitch := -0.3

var label: Label
var msg: Label
var msg_time := 0.0
var menu: VBoxContainer
var ip_edit: LineEdit
var info: Label
var joy_base: Panel
var joy_knob: Panel
var btn_run: Panel
var btn_pick: Panel
var btn_drink: Panel
var btn_bag: Panel
var panel: PanelContainer
var grid: GridContainer
var rec_box: VBoxContainer
var status: Label
var bars := {}

func _mk_noise(seed_: int, freq: float, oct: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.seed = seed_
	n.frequency = freq
	n.fractal_octaves = oct
	return n

func _ready() -> void:
	noise = _mk_noise(1337, 0.012, 4)
	mnoise = _mk_noise(2024, 0.0035, 3)
	tnoise = _mk_noise(77, 0.004, 2)
	dnoise = _mk_noise(5, 0.12, 1)
	fnoise = _mk_noise(99, 0.02, 2)

	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	veg_mat.vertex_color_use_as_albedo = true
	veg_mat.vertex_color_is_srgb = true
	veg_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	flame_mat.vertex_color_use_as_albedo = true
	flame_mat.vertex_color_is_srgb = true
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.albedo_color = Color(0.4, 0.9, 1.0, 0.35)
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	oak_mesh = _mesh_oak()
	pine_mesh = _mesh_pine()
	cactus_mesh = _mesh_cactus()
	rock_mesh = _mesh_rock()
	bush_mesh = _mesh_bush()
	tower_mesh = _mesh_tower()
	tent_mesh = _mesh_tent()
	flame_mesh = _mesh_flame()

	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.75, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_density = 0.004
	env.fog_light_color = Color(0.55, 0.75, 0.95)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	add_child(sun)

	water = MeshInstance3D.new()
	var pl := PlaneMesh.new()
	pl.size = Vector2(800, 800)
	water.mesh = pl
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.15, 0.4, 0.8, 0.75)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.material_override = wm
	water.position.y = WATER_Y
	add_child(water)

	player = Node3D.new()
	add_child(player)
	var body := MeshInstance3D.new()
	body.mesh = CapsuleMesh.new()
	body.position.y = 1.0
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.9, 0.3, 0.2)
	body.material_override = pm
	player.add_child(body)
	pivot = Node3D.new()
	pivot.position.y = 1.5
	player.add_child(pivot)
	cam = Camera3D.new()
	cam.position = Vector3(0, 0.5, 6)
	cam.far = 400.0
	pivot.add_child(cam)

	_load_inv()
	_build_ui()
	_update_sky()

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)

	label = Label.new()
	label.position = Vector2(20, 15)
	label.add_theme_font_size_override("font_size", 24)
	ui.add_child(label)

	var bx := VBoxContainer.new()
	bx.position = Vector2(20, 120)
	bx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bx)
	var defs := [["Máu", Color(0.9, 0.2, 0.2)], ["Đói", Color(0.9, 0.6, 0.2)], ["Khát", Color(0.3, 0.6, 1.0)], ["Thể lực", Color(0.3, 0.9, 0.4)]]
	for d in defs:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var nl := Label.new()
		nl.text = d[0]
		nl.custom_minimum_size = Vector2(110, 0)
		nl.add_theme_font_size_override("font_size", 22)
		row.add_child(nl)
		var pb := ProgressBar.new()
		pb.custom_minimum_size = Vector2(300, 28)
		pb.show_percentage = false
		pb.max_value = 100.0
		pb.value = 100.0
		pb.modulate = d[1]
		pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pb)
		bx.add_child(row)
		bars[d[0]] = pb

	msg = Label.new()
	msg.position = Vector2(20, 270)
	msg.add_theme_font_size_override("font_size", 26)
	ui.add_child(msg)

	joy_base = _circle(220.0, Color(1, 1, 1, 0.25))
	joy_knob = _circle(100.0, Color(1, 1, 1, 0.6))
	joy_base.visible = false
	joy_knob.visible = false
	ui.add_child(joy_base)
	ui.add_child(joy_knob)

	var ab := VBoxContainer.new()
	ab.anchor_left = 1.0
	ab.anchor_right = 1.0
	ab.anchor_top = 1.0
	ab.anchor_bottom = 1.0
	ab.offset_left = -220
	ab.offset_right = -20
	ab.offset_top = -350
	ab.offset_bottom = -20
	ab.add_theme_constant_override("separation", 16)
	ab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(ab)
	btn_bag = _btn("Túi đồ")
	btn_pick = _btn("Thu thập")
	btn_drink = _btn("Uống nước")
	btn_run = _btn("Chạy")
	ab.add_child(btn_bag)
	ab.add_child(btn_pick)
	ab.add_child(btn_drink)
	ab.add_child(btn_run)

	_build_bag(ui)

	menu = VBoxContainer.new()
	menu.anchor_left = 0.5
	menu.anchor_right = 0.5
	menu.anchor_top = 0.5
	menu.anchor_bottom = 0.5
	menu.offset_left = -260
	menu.offset_right = 260
	menu.offset_top = -230
	menu.offset_bottom = 230
	menu.add_theme_constant_override("separation", 20)
	ui.add_child(menu)
	var title := Label.new()
	title.text = "SURVIVAL ONLINE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	menu.add_child(title)
	var host_btn := Button.new()
	host_btn.text = "Tạo phòng (Host)"
	host_btn.custom_minimum_size = Vector2(0, 90)
	host_btn.add_theme_font_size_override("font_size", 30)
	host_btn.pressed.connect(_host)
	menu.add_child(host_btn)
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "IP của người tạo phòng"
	ip_edit.custom_minimum_size = Vector2(0, 80)
	ip_edit.add_theme_font_size_override("font_size", 28)
	menu.add_child(ip_edit)
	var join_btn := Button.new()
	join_btn.text = "Vào phòng"
	join_btn.custom_minimum_size = Vector2(0, 90)
	join_btn.add_theme_font_size_override("font_size", 30)
	join_btn.pressed.connect(_join)
	menu.add_child(join_btn)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 22)
	menu.add_child(info)

func _circle(s: float, c: Color) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(s / 2.0))
	p.add_theme_stylebox_override("panel", sb)
	p.size = Vector2(s, s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

func _btn(t: String) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.set_corner_radius_all(20)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(200, 70)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 26)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p

# ---------- TÚI ĐỒ & CHẾ TẠO ----------
func _flat(c: Color, r: int = 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(r)
	return sb

func _style_btn(b: Button, c: Color) -> void:
	b.add_theme_stylebox_override("normal", _flat(c))
	b.add_theme_stylebox_override("hover", _flat(c.lightened(0.15)))
	b.add_theme_stylebox_override("pressed", _flat(c.lightened(0.3)))
	b.add_theme_stylebox_override("disabled", _flat(Color(0.2, 0.2, 0.22)))
	b.add_theme_font_size_override("font_size", 24)

func _build_bag(ui: CanvasLayer) -> void:
	panel = PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -540
	panel.offset_right = 540
	panel.offset_top = -310
	panel.offset_bottom = 310
	var ps := _flat(Color(0.05, 0.07, 0.1, 0.94), 24)
	ps.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", ps)
	panel.visible = false
	ui.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	var title := Label.new()
	title.text = "TÚI ĐỒ & CHẾ TẠO"
	title.add_theme_font_size_override("font_size", 32)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "Đóng"
	close.custom_minimum_size = Vector2(130, 64)
	close.add_theme_font_size_override("font_size", 26)
	close.pressed.connect(_toggle_bag)
	head.add_child(close)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	root.add_child(body)
	body.add_child(_column("Túi đồ (chạm để dùng)", true))
	body.add_child(_column("Chế tạo", false))

	status = Label.new()
	status.add_theme_font_size_override("font_size", 24)
	root.add_child(status)

func _column(t: String, is_grid: bool) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 26)
	col.add_child(l)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(sc)
	if is_grid:
		grid = GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(grid)
	else:
		rec_box = VBoxContainer.new()
		rec_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rec_box.add_theme_constant_override("separation", 10)
		sc.add_child(rec_box)
	return col

func _toggle_bag() -> void:
	panel.visible = not panel.visible
	if panel.visible:
		joy_id = -1
		look_id = -1
		run_id = -1
		running = false
		move_vec = Vector2.ZERO
		joy_base.visible = false
		joy_knob.visible = false
		status.text = ""
		_refresh_bag()

func _refresh_bag() -> void:
	for ch in grid.get_children():
		grid.remove_child(ch)
		ch.queue_free()
	for ch in rec_box.get_children():
		rec_box.remove_child(ch)
		ch.queue_free()

	var any := false
	for id in ITEMS.keys():
		var cnt := int(inv.get(id, 0))
		if cnt <= 0:
			continue
		any = true
		var b := Button.new()
		b.text = "%s\nx%d" % [ITEMS[id][0], cnt]
		b.custom_minimum_size = Vector2(150, 100)
		var ic: Color = ITEMS[id][1]
		_style_btn(b, ic.darkened(0.35))
		b.pressed.connect(_use.bind(id))
		grid.add_child(b)
	if not any:
		var l := Label.new()
		l.text = "Túi trống. Hãy thu thập tài nguyên!"
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(300, 0)
		l.add_theme_font_size_override("font_size", 24)
		grid.add_child(l)

	var near := _near_fire()
	for r in RECIPES:
		var ok := true
		var parts := PackedStringArray()
		for k in r["need"].keys():
			var have := int(inv.get(k, 0))
			var need := int(r["need"][k])
			if have < need:
				ok = false
			parts.append("%s %d/%d" % [ITEMS[k][0], have, need])
		var txt := "%s\n%s" % [r["name"], ", ".join(parts)]
		if r["fire"]:
			txt += "\n(cần đứng gần lửa trại)"
			if not near:
				ok = false
		var rb := Button.new()
		rb.text = txt
		rb.custom_minimum_size = Vector2(0, 110)
		rb.disabled = not ok
		_style_btn(rb, Color(0.15, 0.4, 0.2))
		rb.pressed.connect(_craft.bind(r["id"]))
		rec_box.add_child(rb)

func _craft(id: String) -> void:
	for r in RECIPES:
		if r["id"] != id:
			continue
		for k in r["need"].keys():
			if int(inv.get(k, 0)) < int(r["need"][k]):
				_say("Thiếu nguyên liệu")
				return
		if r["fire"] and not _near_fire():
			_say("Cần đứng gần lửa trại")
			return
		for k in r["need"].keys():
			_spend(k, int(r["need"][k]))
		_add(id, 1)
		_say("Đã chế tạo: " + r["name"])
		break
	_refresh_bag()

func _use(id: String) -> void:
	if int(inv.get(id, 0)) <= 0:
		return
	match id:
		"berry":
			hunger = minf(100.0, hunger + 15.0)
			_spend(id, 1)
			_say("Ăn quả (+15 no)")
		"roast":
			hunger = minf(100.0, hunger + 40.0)
			hp = minf(100.0, hp + 5.0)
			_spend(id, 1)
			_say("Ăn quả nướng (+40 no)")
		"bandage":
			if hp >= 100.0:
				_say("Máu đã đầy")
				return
			hp = minf(100.0, hp + 30.0)
			_spend(id, 1)
			_say("Đã băng bó (+30 máu)")
		"fire":
			_place_fire_here()
			_spend(id, 1)
			_say("Đã đặt lửa trại")
		_:
			_say("Cứ để trong túi, tự dùng khi thu thập")
	_refresh_bag()

func _add(id: String, n: int) -> void:
	inv[id] = mini(99, int(inv.get(id, 0)) + n)
	_save_inv()

func _spend(id: String, n: int) -> void:
	var left := int(inv.get(id, 0)) - n
	if left <= 0:
		inv.erase(id)
	else:
		inv[id] = left
	_save_inv()

func _has(id: String) -> bool:
	return int(inv.get(id, 0)) > 0

func _save_inv() -> void:
	var f := FileAccess.open("user://inv.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(inv))

func _load_inv() -> void:
	if not FileAccess.file_exists("user://inv.json"):
		return
	var f := FileAccess.open("user://inv.json", FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		for k in data.keys():
			if ITEMS.has(k):
				inv[k] = int(data[k])

# ---------- LỬA TRẠI ----------
func _near_fire() -> bool:
	if player == null:
		return false
	var p := player.position
	for f in fires:
		if Vector2(f.x - p.x, f.z - p.z).length() < 7.0:
			return true
	for f in camps.values():
		if Vector2(f.x - p.x, f.z - p.z).length() < 7.0:
			return true
	return false

func _place_fire_here() -> void:
	var fwd := Vector3(0, 0, -2.5).rotated(Vector3.UP, yaw)
	var pos := player.position + fwd
	pos.y = _height(pos.x, pos.z)
	_spawn_fire(pos)
	if multiplayer.has_multiplayer_peer():
		_rpc_fire.rpc(pos)

func _spawn_fire(pos: Vector3) -> void:
	fires.append(pos)
	var n := Node3D.new()
	n.position = pos
	var f := MeshInstance3D.new()
	f.mesh = flame_mesh
	f.material_override = flame_mat
	n.add_child(f)
	for i in 6:
		var a := float(i) * TAU / 6.0
		var st := MeshInstance3D.new()
		st.mesh = rock_mesh
		st.material_override = veg_mat
		st.position = Vector3(cos(a) * 1.1, 0.0, sin(a) * 1.1)
		st.scale = Vector3(0.3, 0.3, 0.3)
		n.add_child(st)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.6, 0.25)
	lamp.light_energy = 2.5
	lamp.omni_range = 18.0
	lamp.position = Vector3(0, 1.8, 0)
	n.add_child(lamp)
	add_child(n)

# ---------- MẠNG ----------
func _wire() -> void:
	if multiplayer.peer_connected.is_connected(_on_peer):
		return
	multiplayer.peer_connected.connect(_on_peer)
	multiplayer.peer_disconnected.connect(_on_peer_gone)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)

func _host() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 8)
	if err != OK:
		info.text = "Không tạo được phòng (lỗi %d)" % err
		return
	multiplayer.multiplayer_peer = peer
	_wire()
	_start("Phòng của bạn - IP: " + _local_ip())

func _join() -> void:
	var ip := ip_edit.text.strip_edges()
	if ip == "":
		info.text = "Hãy nhập IP của người tạo phòng"
		return
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		info.text = "Không kết nối được (lỗi %d)" % err
		return
	multiplayer.multiplayer_peer = peer
	_wire()
	info.text = "Đang kết nối..."

func _local_ip() -> String:
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			return a
	return "không rõ"

func _on_connected() -> void:
	_start("Đã vào phòng")

func _on_failed() -> void:
	multiplayer.multiplayer_peer = null
	info.text = "Không kết nối được. Kiểm tra IP và đảm bảo cùng WiFi."

func _on_server_gone() -> void:
	multiplayer.multiplayer_peer = null
	get_tree().reload_current_scene()

func _on_peer(id: int) -> void:
	_add_avatar(id)
	if multiplayer.is_server():
		_sync_taken.rpc_id(id, taken.keys())
		_sync_felled.rpc_id(id, felled.keys())
		_sync_fires.rpc_id(id, fires)

func _on_peer_gone(id: int) -> void:
	if others.has(id):
		others[id].queue_free()
		others.erase(id)
		targets.erase(id)

func _add_avatar(id: int) -> void:
	if others.has(id):
		return
	var n := Node3D.new()
	var m := MeshInstance3D.new()
	m.mesh = CapsuleMesh.new()
	m.position.y = 1.0
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.2, 0.5, 0.95)
	m.material_override = pm
	n.add_child(m)
	var l := Label3D.new()
	l.text = "Người chơi %d" % id
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position.y = 2.6
	l.pixel_size = 0.01
	l.font_size = 40
	l.no_depth_test = true
	n.add_child(l)
	n.visible = false
	add_child(n)
	others[id] = n

@rpc("any_peer", "unreliable")
func _state(pos: Vector3, yw: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	_add_avatar(id)
	var n: Node3D = others[id]
	if not targets.has(id):
		n.position = pos
		n.visible = true
	targets[id] = pos
	n.rotation.y = yw

@rpc("any_peer", "reliable")
func _take(key: String) -> void:
	_remove_bush(key)

@rpc("authority", "reliable")
func _sync_taken(keys: Array) -> void:
	for k in keys:
		_remove_bush(str(k))

@rpc("any_peer", "reliable")
func _rpc_felled(key: String) -> void:
	_felled_apply(key)

@rpc("authority", "reliable")
func _sync_felled(keys: Array) -> void:
	var cs := {}
	for k in keys:
		var ks := str(k)
		felled[ks] = true
		var parts := ks.split("_")
		cs[Vector2i(int(parts[1]), int(parts[2]))] = true
	for c in cs.keys():
		_rebuild(c)

@rpc("any_peer", "reliable")
func _rpc_fire(pos: Vector3) -> void:
	_spawn_fire(pos)

@rpc("authority", "reliable")
func _sync_fires(list: Array) -> void:
	for p in list:
		_spawn_fire(p)

# ---------- GAME ----------
func _start(note: String) -> void:
	net_note = note
	menu.visible = false
	started = true
	player.position = _spawn_pos()

func _spawn_pos() -> Vector3:
	for i in 300:
		var a := float(i) * 0.9
		var r := float(i) * 2.5
		var x := cos(a) * r
		var z := sin(a) * r
		var h := _height(x, z)
		if _biome_id(h, tnoise.get_noise_2d(x, z)) == 0 and h < 7.0:
			return Vector3(x + randf_range(-4.0, 4.0), 0.0, z + randf_range(-4.0, 4.0))
	return Vector3(0.0, 0.0, 0.0)

func _say(t: String) -> void:
	msg.text = t
	msg_time = 3.0
	if status != null:
		status.text = t

func _height(x: float, z: float) -> float:
	var h := noise.get_noise_2d(x, z) * 10.0
	var m := mnoise.get_noise_2d(x, z)
	if m > 0.28:
		h += (m - 0.28) * 90.0
	return h

func _biome_id(h: float, t: float) -> int:
	if h < WATER_Y + 1.5 or h > 22.0:
		return -1
	if h > 12.0:
		return 3
	if t > 0.3:
		return 1
	if t < -0.28:
		return 2
	return 0

func _biome_label(x: float, z: float, h: float) -> String:
	var t := tnoise.get_noise_2d(x, z)
	if h < WATER_Y + 0.5:
		return "Hồ nước"
	if h < WATER_Y + 1.5:
		return "Bãi cát ven hồ"
	if h > 22.0:
		return "Đỉnh núi tuyết"
	if h > 12.0:
		return "Núi đá"
	if t > 0.3:
		return "Sa mạc"
	if t < -0.28:
		return "Vùng tuyết"
	if fnoise.get_noise_2d(x, z) > 0.0:
		return "Rừng rậm"
	return "Đồng cỏ"

func _input(e: InputEvent) -> void:
	if not started or panel.visible:
		return
	var half := get_viewport().get_visible_rect().size.x / 2.0
	if e is InputEventScreenTouch:
		var t: InputEventScreenTouch = e
		if t.pressed:
			if btn_run.get_global_rect().has_point(t.position):
				run_id = t.index
				running = true
			elif btn_pick.get_global_rect().has_point(t.position):
				_gather()
			elif btn_drink.get_global_rect().has_point(t.position):
				_drink()
			elif btn_bag.get_global_rect().has_point(t.position):
				_toggle_bag()
			elif t.position.x < half and joy_id == -1:
				joy_id = t.index
				joy_origin = t.position
				joy_base.position = t.position - joy_base.size / 2.0
				joy_knob.position = t.position - joy_knob.size / 2.0
				joy_base.visible = true
				joy_knob.visible = true
			elif t.position.x >= half and look_id == -1:
				look_id = t.index
		else:
			if t.index == run_id:
				run_id = -1
				running = false
			elif t.index == joy_id:
				joy_id = -1
				move_vec = Vector2.ZERO
				joy_base.visible = false
				joy_knob.visible = false
			elif t.index == look_id:
				look_id = -1
	elif e is InputEventScreenDrag:
		var d: InputEventScreenDrag = e
		if d.index == joy_id:
			move_vec = ((d.position - joy_origin) / 100.0).limit_length(1.0)
			joy_knob.position = joy_origin + move_vec * 100.0 - joy_knob.size / 2.0
		elif d.index == look_id:
			yaw -= d.relative.x * 0.005
			pitch = clampf(pitch + d.relative.y * 0.005, -1.2, 0.3)

func _gather() -> void:
	if act_cd > 0.0:
		return
	act_cd = 0.5
	var p := player.position
	for c in chunks.values():
		for b in c.get_children():
			if b.has_meta("key") and Vector2(b.position.x - p.x, b.position.z - p.z).length() < 3.0:
				var key: String = b.get_meta("key")
				_remove_bush(key)
				_add("berry", randi_range(1, 2))
				_add("fiber", 1)
				_say("Hái bụi quả (+Quả, +Sợi)")
				if multiplayer.has_multiplayer_peer():
					_take.rpc(key)
				return

	var best: Dictionary = {}
	var bd := 3.8
	for lst in res_list.values():
		for r in lst:
			var rp: Vector3 = r["pos"]
			var dd := Vector2(rp.x - p.x, rp.z - p.z).length()
			if dd < bd and not felled.has(r["key"]):
				bd = dd
				best = r
	if best.is_empty():
		_say("Không có gì để thu thập ở gần")
		return

	var rkey: String = best["key"]
	var kind: int = best["kind"]
	var cnt := int(hits.get(rkey, 0)) + 1
	var need := 1
	if kind == 0:
		need = 2 if _has("axe") else 4
	elif kind == 1:
		need = 1 if _has("pick") else 3
	if cnt < need:
		hits[rkey] = cnt
		_say("%s (%d/%d)" % [_res_name(kind), cnt, need])
		return
	hits.erase(rkey)
	if kind == 0:
		var w := 4 if _has("axe") else 2
		_add("wood", w)
		_say("Chặt cây: +%d Gỗ" % w)
	elif kind == 1:
		var s := 3 if _has("pick") else 1
		_add("stone", s)
		_say("Đập đá: +%d Đá" % s)
	else:
		_add("fiber", 2)
		hp = maxf(1.0, hp - 5.0)
		_say("Gai xương rồng đâm! +2 Sợi, -5 máu")
	_felled_apply(rkey)
	if multiplayer.has_multiplayer_peer():
		_rpc_felled.rpc(rkey)

func _res_name(kind: int) -> String:
	if kind == 0:
		return "Chặt cây"
	if kind == 1:
		return "Đập đá"
	return "Cắt xương rồng"

func _felled_apply(key: String) -> void:
	felled[key] = true
	var parts := key.split("_")
	_rebuild(Vector2i(int(parts[1]), int(parts[2])))

func _rebuild(c: Vector2i) -> void:
	if chunks.has(c):
		chunks[c].queue_free()
		var m := _make_chunk(c)
		chunks[c] = m
		add_child(m)

func _drink() -> void:
	if _height(player.position.x, player.position.z) < WATER_Y + 1.0:
		thirst = minf(100.0, thirst + 40.0)
		_say("Đã uống nước")
	else:
		_say("Hãy đến gần vùng nước xanh")

func _remove_bush(key: String) -> void:
	taken[key] = true
	for c in chunks.values():
		for b in c.get_children():
			if b.has_meta("key") and b.get_meta("key") == key:
				b.queue_free()

func _tick(delta: float, sprint: bool) -> void:
	hunger = maxf(0.0, hunger - 0.35 * delta)
	thirst = maxf(0.0, thirst - 0.5 * delta)
	if sprint:
		stamina = maxf(0.0, stamina - 18.0 * delta)
	else:
		stamina = minf(100.0, stamina + 10.0 * delta)
	if hunger <= 0.0 or thirst <= 0.0:
		hp -= 2.0 * delta
	elif hp < 100.0 and hunger > 50.0 and thirst > 50.0:
		hp = minf(100.0, hp + 1.0 * delta)
	if hp <= 0.0:
		hp = 100.0
		hunger = 100.0
		thirst = 100.0
		stamina = 100.0
		player.position = _spawn_pos()
		_say("Bạn đã chết và hồi sinh!")

func _update_sky() -> void:
	var t := fmod(Time.get_unix_time_from_system() / DAY_LEN + 0.08, 1.0)
	var th := t * TAU
	var s := sin(th)
	var f := clampf(s * 2.0 + 0.3, 0.0, 1.0)
	var warm := clampf(1.0 - absf(s - 0.05) * 4.0, 0.0, 1.0)
	var col := Color(0.02, 0.03, 0.09).lerp(Color(0.55, 0.75, 0.95), f).lerp(Color(1.0, 0.55, 0.3), warm * 0.4)
	env.background_color = col
	env.fog_light_color = col
	env.ambient_light_energy = lerpf(0.2, 0.6, f)
	sun.rotation = Vector3(-th, -0.5, 0.0)
	sun.light_energy = maxf(s, 0.0) * 1.1
	sun.light_color = Color(1, 1, 1).lerp(Color(1.0, 0.6, 0.4), warm)
	time_name = "Đêm" if s < -0.05 else "Ngày"

func _process(delta: float) -> void:
	if not started:
		return
	act_cd = maxf(0.0, act_cd - delta)
	var moving := move_vec.length() > 0.1
	var sprint := running and moving and stamina > 0.0
	var spd := RUN if sprint else WALK
	var dir := Vector3(move_vec.x, 0.0, move_vec.y).rotated(Vector3.UP, yaw)
	player.position += dir * spd * delta
	player.position.y = _height(player.position.x, player.position.z)
	player.rotation.y = yaw
	pivot.rotation.x = pitch
	water.position = Vector3(player.position.x, WATER_Y, player.position.z)
	_tick(delta, sprint)
	_update_chunks()
	_gen_pending()
	_update_sky()

	for id in others.keys():
		if targets.has(id):
			others[id].position = others[id].position.lerp(targets[id], clampf(12.0 * delta, 0.0, 1.0))

	send_timer += delta
	if send_timer >= 0.05 and multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		send_timer = 0.0
		_state.rpc(player.position, yaw)

	bars["Máu"].value = hp
	bars["Đói"].value = hunger
	bars["Khát"].value = thirst
	bars["Thể lực"].value = stamina
	if msg_time > 0.0:
		msg_time -= delta
		if msg_time <= 0.0:
			msg.text = ""
	biome_name = _biome_label(player.position.x, player.position.z, player.position.y)
	label.text = "FPS %d | Người chơi: %d | %s\n%s\n%s" % [Engine.get_frames_per_second(), others.size() + 1, time_name, biome_name, net_note]

# ---------- THẾ GIỚI ----------
func _update_chunks() -> void:
	var pc := Vector2i(floori(player.position.x / CHUNK_SIZE), floori(player.position.z / CHUNK_SIZE))
	if pc == last_chunk:
		return
	last_chunk = pc
	var need := {}
	for dx in range(-VIEW, VIEW + 1):
		for dz in range(-VIEW, VIEW + 1):
			need[Vector2i(pc.x + dx, pc.y + dz)] = true
	for k in chunks.keys():
		if not need.has(k):
			chunks[k].queue_free()
			chunks.erase(k)
			res_list.erase(k)
			camps.erase(k)
	pending.clear()
	for k in need.keys():
		if not chunks.has(k):
			pending.append(k)
	pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a - pc).length() < Vector2(b - pc).length())

func _gen_pending() -> void:
	var n := 0
	while not pending.is_empty() and n < 2:
		var k: Vector2i = pending.pop_front()
		if chunks.has(k):
			continue
		var m := _make_chunk(k)
		chunks[k] = m
		add_child(m)
		n += 1

func _vcolor(x: float, z: float, h: float, t: float) -> Color:
	var c := Color(0.28, 0.58, 0.22)
	c = c.lerp(Color(0.88, 0.72, 0.38), smoothstep(0.22, 0.34, t))
	c = c.lerp(Color(0.93, 0.96, 1.0), smoothstep(-0.2, -0.32, t))
	if h < WATER_Y + 0.4:
		c = Color(0.5, 0.45, 0.32)
	elif h < WATER_Y + 1.5:
		c = Color(0.85, 0.78, 0.5)
	if h > 12.0:
		c = c.lerp(Color(0.5, 0.5, 0.52), clampf((h - 12.0) / 6.0, 0.0, 1.0))
	if h > 24.0:
		c = c.lerp(Color(0.97, 0.98, 1.0), clampf((h - 24.0) / 6.0, 0.0, 1.0))
	var v := 0.92 + dnoise.get_noise_2d(x, z) * 0.12
	return Color(c.r * v, c.g * v, c.b * v)

func _make_chunk(c: Vector2i) -> MeshInstance3D:
	camps.erase(c)
	var n := RES + 1
	var step := CHUNK_SIZE / RES
	var ox := c.x * CHUNK_SIZE
	var oz := c.y * CHUNK_SIZE
	var hs := PackedFloat32Array()
	var cols := PackedColorArray()
	hs.resize(n * n)
	cols.resize(n * n)
	for i in n:
		for j in n:
			var x := ox + i * step
			var z := oz + j * step
			var h := _height(x, z)
			hs[i * n + j] = h
			cols[i * n + j] = _vcolor(x, z, h, tnoise.get_noise_2d(x, z))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in RES:
		for j in RES:
			var x0 := ox + i * step
			var x1 := x0 + step
			var z0 := oz + j * step
			var z1 := z0 + step
			var a := Vector3(x0, hs[i * n + j], z0)
			var b := Vector3(x1, hs[(i + 1) * n + j], z0)
			var d := Vector3(x0, hs[i * n + j + 1], z1)
			var e := Vector3(x1, hs[(i + 1) * n + j + 1], z1)
			_tri(st, a, b, d, cols[i * n + j], cols[(i + 1) * n + j], cols[i * n + j + 1])
			_tri(st, b, e, d, cols[(i + 1) * n + j], cols[(i + 1) * n + j + 1], cols[i * n + j + 1])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c)
	var oaks: Array = []
	var pines: Array = []
	var cacti: Array = []
	var rocks: Array = []
	var lst: Array = []
	for i in 70:
		var x := ox + rng.randf() * CHUNK_SIZE
		var z := oz + rng.randf() * CHUNK_SIZE
		var roll := rng.randf()
		var s := 0.8 + rng.randf() * 0.7
		var ang := rng.randf() * TAU
		var h := _height(x, z)
		var bid := _biome_id(h, tnoise.get_noise_2d(x, z))
		if bid < 0:
			continue
		var rkey := "r_%d_%d_%d" % [c.x, c.y, i]
		if felled.has(rkey):
			continue
		var pos := Vector3(x, h - 0.1, z)
		var dens := clampf(0.4 + fnoise.get_noise_2d(x, z) * 1.2, 0.05, 0.85)
		var which := ""
		match bid:
			0:
				if roll < dens:
					which = "oak"
				elif roll > 0.97:
					which = "rock"
			1:
				if roll < 0.2:
					which = "cactus"
				elif roll > 0.9:
					which = "rock"
			2:
				if roll < dens * 0.8:
					which = "pine"
				elif roll > 0.95:
					which = "rock"
			3:
				if roll < 0.25:
					which = "rock"
		if which == "":
			continue
		var kind := 0
		if which == "oak":
			oaks.append(_xf(pos, ang, s, s))
		elif which == "pine":
			pines.append(_xf(pos, ang, s, s))
		elif which == "cactus":
			cacti.append(_xf(pos, ang, s, s))
			kind = 2
		else:
			var sr := s * (1.6 if bid == 3 else 0.9)
			rocks.append(_xf(pos, ang, sr, sr * 0.85))
			kind = 1
		lst.append({"key": rkey, "kind": kind, "pos": pos})
	res_list[c] = lst
	if oaks.size() > 0:
		mi.add_child(_multi(oak_mesh, oaks))
	if pines.size() > 0:
		mi.add_child(_multi(pine_mesh, pines))
	if cacti.size() > 0:
		mi.add_child(_multi(cactus_mesh, cacti))
	if rocks.size() > 0:
		mi.add_child(_multi(rock_mesh, rocks))

	var lr := RandomNumberGenerator.new()
	lr.seed = hash(c) + 7777
	if lr.randf() < 0.10:
		var lx := ox + 8.0 + lr.randf() * (CHUNK_SIZE - 16.0)
		var lz := oz + 8.0 + lr.randf() * (CHUNK_SIZE - 16.0)
		var lh := _height(lx, lz)
		var lt := lr.randi() % 3
		if lh > WATER_Y + 1.5 and lh < 16.0:
			mi.add_child(_landmark(lt, Vector3(lx, lh, lz), lr))
			if lt == 1:
				camps[c] = Vector3(lx, lh, lz)

	for i in 5:
		var bx := ox + rng.randf() * CHUNK_SIZE
		var bz := oz + rng.randf() * CHUNK_SIZE
		var roll2 := rng.randf()
		var rot := rng.randf() * TAU
		var by := _height(bx, bz)
		var key := "%d_%d_%d" % [c.x, c.y, i]
		if roll2 > 0.5 or taken.has(key):
			continue
		if _biome_id(by, tnoise.get_noise_2d(bx, bz)) != 0:
			continue
		var bs := MeshInstance3D.new()
		bs.mesh = bush_mesh
		bs.material_override = veg_mat
		bs.position = Vector3(bx, by - 0.05, bz)
		bs.rotation.y = rot
		bs.set_meta("key", key)
		mi.add_child(bs)
	return mi

func _xf(pos: Vector3, ang: float, sxz: float, sy: float) -> Transform3D:
	var b := Basis(Vector3.UP, ang).scaled(Vector3(sxz, sy, sxz))
	return Transform3D(b, pos)

func _multi(m: Mesh, xf: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = veg_mat
	return mmi

func _prop(root: Node3D, m: Mesh, mt: Material, off: Vector3, rot: float, sc: Vector3) -> void:
	var p := MeshInstance3D.new()
	p.mesh = m
	p.material_override = mt
	var wx := root.position.x + off.x
	var wz := root.position.z + off.z
	p.position = Vector3(off.x, _height(wx, wz) - root.position.y + off.y, off.z)
	p.rotation.y = rot
	p.scale = sc
	root.add_child(p)

func _landmark(kind: int, pos: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	if kind == 0:
		_prop(root, tower_mesh, veg_mat, Vector3(0, -1.5, 0), 0.0, Vector3.ONE)
		for i in 7:
			var a := rng.randf() * TAU
			var d := 3.5 + rng.randf() * 3.5
			var sc := 0.6 + rng.randf() * 0.8
			_prop(root, rock_mesh, veg_mat, Vector3(cos(a) * d, -0.2, sin(a) * d), a, Vector3(sc, sc, sc))
		var bm := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.35
		cm.bottom_radius = 0.35
		cm.height = 90.0
		cm.radial_segments = 6
		bm.mesh = cm
		bm.material_override = beam_mat
		bm.position.y = 45.0
		root.add_child(bm)
	elif kind == 1:
		for i in 3:
			var a := float(i) * 2.1 + rng.randf() * 0.5
			_prop(root, tent_mesh, veg_mat, Vector3(cos(a) * 5.5, -0.1, sin(a) * 5.5), a + 1.57, Vector3.ONE)
		for i in 7:
			var a2 := float(i) * TAU / 7.0
			_prop(root, rock_mesh, veg_mat, Vector3(cos(a2) * 1.4, -0.1, sin(a2) * 1.4), a2, Vector3(0.3, 0.3, 0.3))
		_prop(root, flame_mesh, flame_mat, Vector3(0, 0.0, 0), 0.0, Vector3.ONE)
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.6, 0.25)
		lamp.light_energy = 2.5
		lamp.omni_range = 18.0
		lamp.position = Vector3(0, 1.8, 0)
		root.add_child(lamp)
	else:
		_prop(root, oak_mesh, veg_mat, Vector3(0, -0.3, 0), rng.randf() * TAU, Vector3(4.0, 4.0, 4.0))
		for i in 6:
			var a3 := rng.randf() * TAU
			var d3 := 6.0 + rng.randf() * 3.0
			var sc3 := 0.8 + rng.randf() * 1.0
			_prop(root, rock_mesh, veg_mat, Vector3(cos(a3) * d3, -0.2, sin(a3) * d3), a3, Vector3(sc3, sc3, sc3))
	return root

# ---------- MESH ----------
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var nrm := (b - a).cross(c - a).normalized()
	if nrm.y < 0.0:
		nrm = -nrm
	var rock := clampf((0.8 - nrm.y) * 6.0, 0.0, 1.0)
	var rc := Color(0.45, 0.43, 0.42)
	var cs := [ca, cb, cc]
	var vs := [a, b, c]
	for k in 3:
		var col: Color = cs[k]
		st.set_normal(nrm)
		st.set_color(col.lerp(rc, rock))
		st.add_vertex(vs[k])

func _vtri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, outv: Vector3) -> void:
	var nrm := (b - a).cross(c - a).normalized()
	if nrm.dot(outv) < 0.0:
		nrm = -nrm
	for v in [a, b, c]:
		st.set_normal(nrm)
		st.set_color(col)
		st.add_vertex(v)

func _frustum(st: SurfaceTool, ox: float, oz: float, y0: float, y1: float, r0: float, r1: float, col: Color, sides: int) -> void:
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var am := (a0 + a1) * 0.5
		var outv := Vector3(cos(am), 0.15, sin(am))
		var b0 := Vector3(ox + cos(a0) * r0, y0, oz + sin(a0) * r0)
		var b1 := Vector3(ox + cos(a1) * r0, y0, oz + sin(a1) * r0)
		var t0 := Vector3(ox + cos(a0) * r1, y1, oz + sin(a0) * r1)
		var t1 := Vector3(ox + cos(a1) * r1, y1, oz + sin(a1) * r1)
		_vtri(st, b0, t0, b1, col, outv)
		if r1 > 0.001:
			_vtri(st, b1, t0, t1, col, outv)
			_vtri(st, Vector3(ox, y1, oz), t0, t1, col, Vector3.UP)

func _new_st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

func _mesh_oak() -> ArrayMesh:
	var st := _new_st()
	_frustum(st, 0, 0, 0.0, 2.4, 0.4, 0.28, Color(0.4, 0.27, 0.15), 6)
	_frustum(st, 0, 0, 1.9, 3.9, 1.9, 1.35, Color(0.2, 0.5, 0.15), 7)
	_frustum(st, 0, 0, 3.7, 5.6, 1.45, 0.0, Color(0.27, 0.6, 0.18), 7)
	return st.commit()

func _mesh_pine() -> ArrayMesh:
	var st := _new_st()
	_frustum(st, 0, 0, 0.0, 1.6, 0.35, 0.25, Color(0.35, 0.24, 0.14), 6)
	_frustum(st, 0, 0, 1.2, 3.4, 1.9, 0.5, Color(0.1, 0.38, 0.22), 7)
	_frustum(st, 0, 0, 2.8, 5.0, 1.5, 0.3, Color(0.12, 0.42, 0.25), 7)
	_frustum(st, 0, 0, 4.4, 6.6, 1.1, 0.0, Color(0.9, 0.95, 1.0), 7)
	return st.commit()

func _mesh_cactus() -> ArrayMesh:
	var st := _new_st()
	_frustum(st, 0, 0, 0.0, 3.2, 0.45, 0.38, Color(0.2, 0.55, 0.25), 6)
	_frustum(st, 0.75, 0, 1.3, 2.5, 0.25, 0.22, Color(0.22, 0.58, 0.27), 6)
	return st.commit()

func _mesh_rock() -> ArrayMesh:
	var st := _new_st()
	_frustum(st, 0, 0, 0.0, 0.9, 1.1, 0.8, Color(0.5, 0.49, 0.47), 6)
	_frustum(st, 0.1, 0, 0.8, 1.5, 0.8, 0.3, Color(0.42, 0.41, 0.4), 6)
	return st.commit()

func _mesh_bush() -> ArrayMesh:
	var st := _new_st()
	_frustum(st, 0, 0, 0.0, 0.8, 0.9, 0.55, Color(0.18, 0.45, 0.15), 7)
	_frustum(st, 0.35, 0.1, 0.6, 1.0, 0.2, 0.1, Color(0.85, 0.1, 0.2), 5)
	_frustum(st, -0.3, 0.25, 0.6, 1.0, 0.2, 0.1, Color(0.85, 0.1, 0.2), 5)
	_frustum(st, 0.0, -0.4, 0.6, 1.0, 0.2, 0.1, Color(0.85, 0.1, 0.2), 5)
	return st.commit()

func _mesh_tower() -> ArrayMesh:
	var st := _new_st()
	_frustum(st, 0, 0, 0.0, 9.0, 2.6, 2.2, Color(0.55, 0.54, 0.52), 8)
	_frustum(st, 0, 0, 9.0, 11.0, 2.2, 1.0, Color(0.42, 0.41, 0.4), 8)
	_frustum(st, 1.4, 0, 9.0, 12.5, 0.8, 0.8, Color(0.5, 0.49, 0.47), 6)
	_frustum(st, 0, 0, 10.5, 11.0, 1.2, 0.9, Color(0.35, 0.5, 0.3), 8)
	return st.commit()

func _mesh_tent() -> ArrayMesh:
	var st := _new_st()
	_frustum(st, 0, 0, 0.0, 2.4, 2.2, 0.0, Color(0.8, 0.65, 0.4), 4)
	return st.commit()

func _mesh_flame() -> ArrayMesh:
	var st := _new_st()
	_frustum(st, 0, 0, 0.0, 0.9, 0.4, 0.0, Color(1.0, 0.55, 0.1), 5)
	_frustum(st, 0, 0, 0.0, 0.5, 0.25, 0.0, Color(1.0, 0.9, 0.3), 5)
	return st.commit()
