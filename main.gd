extends Node3D

const PORT := 7777
const CHUNK_SIZE := 32.0
const RES := 16
const VIEW := 2
const WALK := 8.0
const RUN := 14.0
const WATER_Y := -3.0

var noise := FastNoiseLite.new()
var mat := StandardMaterial3D.new()
var bush_mat := StandardMaterial3D.new()
var chunks := {}
var taken := {}
var last_chunk := Vector2i(99999, 99999)

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
var bars := {}

func _ready() -> void:
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = 1337
	noise.frequency = 0.01
	noise.fractal_octaves = 4
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bush_mat.albedo_color = Color(0.6, 0.1, 0.5)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.75, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)

	water = MeshInstance3D.new()
	var pl := PlaneMesh.new()
	pl.size = Vector2(600, 600)
	water.mesh = pl
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.2, 0.45, 0.85, 0.7)
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
	cam.far = 300.0
	pivot.add_child(cam)

	_build_ui()

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)

	label = Label.new()
	label.position = Vector2(20, 15)
	label.add_theme_font_size_override("font_size", 24)
	ui.add_child(label)

	var bx := VBoxContainer.new()
	bx.position = Vector2(20, 90)
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
	msg.position = Vector2(20, 240)
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
	ab.offset_top = -330
	ab.offset_bottom = -20
	ab.add_theme_constant_override("separation", 20)
	ab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(ab)
	btn_pick = _btn("Hái quả")
	btn_drink = _btn("Uống nước")
	btn_run = _btn("Chạy")
	ab.add_child(btn_pick)
	ab.add_child(btn_drink)
	ab.add_child(btn_run)

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
	p.custom_minimum_size = Vector2(200, 90)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 30)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p

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

# ---------- GAME ----------
func _start(note: String) -> void:
	net_note = note
	menu.visible = false
	started = true
	player.position = Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))

func _say(t: String) -> void:
	msg.text = t
	msg_time = 3.0

func _height(x: float, z: float) -> float:
	return noise.get_noise_2d(x, z) * 14.0

func _input(e: InputEvent) -> void:
	if not started:
		return
	var half := get_viewport().get_visible_rect().size.x / 2.0
	if e is InputEventScreenTouch:
		var t: InputEventScreenTouch = e
		if t.pressed:
			if btn_run.get_global_rect().has_point(t.position):
				run_id = t.index
				running = true
			elif btn_pick.get_global_rect().has_point(t.position):
				_pick()
			elif btn_drink.get_global_rect().has_point(t.position):
				_drink()
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

func _pick() -> void:
	var p := player.position
	for c in chunks.values():
		for b in c.get_children():
			if b.has_meta("key") and Vector2(b.position.x - p.x, b.position.z - p.z).length() < 3.0:
				var key: String = b.get_meta("key")
				_remove_bush(key)
				hunger = minf(100.0, hunger + 25.0)
				_say("Đã hái quả (+25 no)")
				if multiplayer.has_multiplayer_peer():
					_take.rpc(key)
				return
	_say("Không có bụi quả (màu tím) gần đây")

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
		player.position = Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
		_say("Bạn đã chết và hồi sinh!")

func _process(delta: float) -> void:
	if not started:
		return
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
	label.text = "FPS %d | Người chơi: %d\n%s" % [Engine.get_frames_per_second(), others.size() + 1, net_note]

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
	for k in need.keys():
		if not chunks.has(k):
			var m := _make_chunk(k)
			chunks[k] = m
			add_child(m)

func _make_chunk(c: Vector2i) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := CHUNK_SIZE / RES
	var ox := c.x * CHUNK_SIZE
	var oz := c.y * CHUNK_SIZE
	for i in RES:
		for j in RES:
			var x0 := ox + i * step
			var x1 := x0 + step
			var z0 := oz + j * step
			var z1 := z0 + step
			var a := Vector3(x0, _height(x0, z0), z0)
			var b := Vector3(x1, _height(x1, z0), z0)
			var d := Vector3(x0, _height(x0, z1), z1)
			var e := Vector3(x1, _height(x1, z1), z1)
			_tri(st, a, b, d)
			_tri(st, b, e, d)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c)
	for i in 4:
		var bx := ox + rng.randf() * CHUNK_SIZE
		var bz := oz + rng.randf() * CHUNK_SIZE
		var by := _height(bx, bz)
		var key := "%d_%d_%d" % [c.x, c.y, i]
		if by < WATER_Y + 1.0 or by > 6.0 or taken.has(key):
			continue
		var b := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.6
		sm.height = 1.2
		b.mesh = sm
		b.material_override = bush_mat
		b.position = Vector3(bx, by + 0.5, bz)
		b.set_meta("key", key)
		mi.add_child(b)
	return mi

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.y < 0.0:
		n = -n
	var col := _col((a.y + b.y + c.y) / 3.0)
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(v)

func _col(h: float) -> Color:
	if h < WATER_Y:
		return Color(0.85, 0.78, 0.5)
	if h < 6.0:
		return Color(0.3, 0.6, 0.25)
	if h < 9.0:
		return Color(0.5, 0.5, 0.5)
	return Color(0.95, 0.95, 1.0)
