extends Node

var main = null
var main_id := 0
var dead_id := 0
var t_now := 0.0
var mode := "title"
var back_to := "home"
var cfg := ConfigFile.new()
var vals := {"master": 1.0, "sfx": 1.0, "voice": 1.0}
var fps_cap := 60
var shadow_q := 2
var last_ip := ""

var layer: CanvasLayer
var root: Control
var bg: Control
var dim: ColorRect
var title_box: VBoxContainer
var pages := {}
var status: Label
var ip_edit: LineEdit
var val_labels := {}
var btn_fps: Button
var btn_shadow: Button
var stars: Array = []
var layers: Array = []
var flies: Array = []
var pause_layer: CanvasLayer
var pause_btn: Button
var W := 1280.0
var H := 720.0

func _ready() -> void:
	get_tree().quit_on_go_back = false
	_load()
	var vs := get_viewport().get_visible_rect().size
	if vs.x > 100.0:
		W = vs.x
		H = vs.y
	layer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	_build_bg()
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.visible = false
	root.add_child(dim)
	_build_pages()
	pause_layer = CanvasLayer.new()
	pause_layer.layer = 8
	add_child(pause_layer)
	pause_btn = _mkbtn("Menu", 56, 24)
	pause_btn.anchor_left = 0.5
	pause_btn.anchor_right = 0.5
	pause_btn.offset_left = -60
	pause_btn.offset_right = 60
	pause_btn.offset_top = 12
	pause_btn.offset_bottom = 68
	pause_btn.pressed.connect(_open_pause)
	pause_layer.add_child(pause_btn)
	pause_layer.visible = false
	_go_title()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()

# ---------- LƯU CÀI ĐẶT ----------
func _load() -> void:
	if cfg.load("user://settings.cfg") == OK:
		vals["master"] = float(cfg.get_value("s", "master", 1.0))
		vals["sfx"] = float(cfg.get_value("s", "sfx", 1.0))
		vals["voice"] = float(cfg.get_value("s", "voice", 1.0))
		fps_cap = int(cfg.get_value("s", "fps", 60))
		shadow_q = int(cfg.get_value("s", "shadow", 2))
		last_ip = str(cfg.get_value("s", "ip", ""))

func _save() -> void:
	cfg.set_value("s", "master", vals["master"])
	cfg.set_value("s", "sfx", vals["sfx"])
	cfg.set_value("s", "voice", vals["voice"])
	cfg.set_value("s", "fps", fps_cap)
	cfg.set_value("s", "shadow", shadow_q)
	cfg.set_value("s", "ip", last_ip)
	cfg.save("user://settings.cfg")

func _apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(vals["master"]), 0.0001)))
	var sb := AudioServer.get_bus_index("SFX")
	if sb >= 0:
		AudioServer.set_bus_volume_db(sb, linear_to_db(maxf(float(vals["sfx"]), 0.0001)))
	var vb := AudioServer.get_bus_index("Voice")
	if vb >= 0:
		AudioServer.set_bus_volume_db(vb, linear_to_db(maxf(float(vals["voice"]), 0.0001)))
	Engine.max_fps = fps_cap
	if main != null and is_instance_valid(main):
		var s: DirectionalLight3D = main.sun
		if shadow_q == 0:
			s.directional_shadow_max_distance = 1.0
			s.shadow_opacity = 0.0
		elif shadow_q == 1:
			s.directional_shadow_max_distance = 30.0
			s.shadow_opacity = 1.0
		else:
			s.directional_shadow_max_distance = 70.0
			s.shadow_opacity = 1.0

# ---------- DỰNG GIAO DIỆN ----------
func _mkbtn(t: String, h: float, fs: int) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, h)
	b.add_theme_font_size_override("font_size", fs)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.12, 0.2, 0.82)
	sb.set_corner_radius_all(18)
	sb.border_color = Color(1.0, 0.7, 0.35, 0.9)
	sb.set_border_width_all(2)
	b.add_theme_stylebox_override("normal", sb)
	var sh := sb.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.18, 0.2, 0.32, 0.9)
	b.add_theme_stylebox_override("hover", sh)
	var sp := sb.duplicate() as StyleBoxFlat
	sp.bg_color = Color(0.9, 0.55, 0.2, 0.95)
	b.add_theme_stylebox_override("pressed", sp)
	return b

func _lbl(t: String, fs: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _mountain(c: Color, base: float, amp: float, sd: int, freq: float) -> Polygon2D:
	var n := FastNoiseLite.new()
	n.seed = sd
	n.frequency = freq
	var pts := PackedVector2Array()
	var x := -120.0
	while x <= W + 120.0:
		pts.append(Vector2(x, base - (n.get_noise_1d(x) * 0.5 + 0.5) * amp))
		x += 24.0
	pts.append(Vector2(W + 120.0, H + 20.0))
	pts.append(Vector2(-120.0, H + 20.0))
	var p := Polygon2D.new()
	p.polygon = pts
	p.color = c
	return p

func _build_bg() -> void:
	bg = Control.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 0.8, 1.0])
	g.colors = PackedColorArray([Color(0.03, 0.04, 0.14), Color(0.16, 0.12, 0.32), Color(0.75, 0.38, 0.35), Color(0.95, 0.6, 0.35)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 8
	gt.height = 256
	var tr := TextureRect.new()
	tr.texture = gt
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(tr)

	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 70:
		var s := ColorRect.new()
		var sz := rng.randf_range(2.0, 4.0)
		s.size = Vector2(sz, sz)
		s.position = Vector2(rng.randf() * W, rng.randf() * H * 0.5)
		s.color = Color(1, 1, 0.9)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_child(s)
		stars.append(s)

	var halo := Panel.new()
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(1.0, 0.95, 0.8, 0.12)
	hs.set_corner_radius_all(100)
	halo.add_theme_stylebox_override("panel", hs)
	halo.size = Vector2(200, 200)
	halo.position = Vector2(W * 0.8 - 100.0, H * 0.2 - 100.0)
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(halo)
	var moon := Panel.new()
	var ms := StyleBoxFlat.new()
	ms.bg_color = Color(0.96, 0.94, 0.82)
	ms.set_corner_radius_all(46)
	moon.add_theme_stylebox_override("panel", ms)
	moon.size = Vector2(92, 92)
	moon.position = Vector2(W * 0.8 - 46.0, H * 0.2 - 46.0)
	moon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(moon)

	var far := _mountain(Color(0.3, 0.22, 0.42), H * 0.66, 120.0, 3, 0.004)
	var mid := _mountain(Color(0.17, 0.13, 0.3), H * 0.76, 110.0, 7, 0.006)
	var near := _mountain(Color(0.07, 0.08, 0.15), H * 0.88, 80.0, 13, 0.01)
	bg.add_child(far)
	bg.add_child(mid)
	bg.add_child(near)
	layers = [far, mid, near]

	var pts := PackedVector2Array()
	var polys: Array = []
	var x := -100.0
	var base := H * 0.93
	while x < W + 100.0:
		var h := rng.randf_range(60.0, 130.0)
		var i0 := pts.size()
		pts.append(Vector2(x - 24.0, base + 10.0))
		pts.append(Vector2(x, base + 10.0 - h))
		pts.append(Vector2(x + 24.0, base + 10.0))
		polys.append(PackedInt32Array([i0, i0 + 1, i0 + 2]))
		x += rng.randf_range(34.0, 58.0)
	var trees := Polygon2D.new()
	trees.polygon = pts
	trees.polygons = polys
	trees.color = Color(0.03, 0.04, 0.09)
	bg.add_child(trees)
	layers.append(trees)

	for i in 26:
		var f := ColorRect.new()
		f.size = Vector2(5, 5)
		f.color = Color(1.0, 0.95, 0.5)
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_child(f)
		flies.append({"n": f, "b": Vector2(rng.randf() * W, H * rng.randf_range(0.5, 0.95)), "ph": rng.randf() * 6.0, "sp": rng.randf_range(0.5, 1.2)})

func _build_pages() -> void:
	var col := VBoxContainer.new()
	col.anchor_left = 0.5
	col.anchor_right = 0.5
	col.anchor_top = 0.5
	col.anchor_bottom = 0.5
	col.offset_left = -300
	col.offset_right = 300
	col.offset_top = -340
	col.offset_bottom = 340
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	root.add_child(col)

	title_box = VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 0)
	title_box.add_child(_lbl("SURVIVAL", 88, Color(1.0, 0.75, 0.35)))
	title_box.add_child(_lbl("ONLINE", 46, Color(0.9, 0.95, 1.0)))
	title_box.add_child(_lbl("Sinh tồn thế giới mở nhiều người chơi", 24, Color(0.85, 0.85, 0.95)))
	col.add_child(title_box)

	# Trang chính
	var home := VBoxContainer.new()
	home.add_theme_constant_override("separation", 12)
	var b1 := _mkbtn("Tạo phòng / Chơi ngay", 74, 32)
	b1.pressed.connect(_on_host)
	home.add_child(b1)
	var b2 := _mkbtn("Vào phòng bạn bè", 74, 32)
	b2.pressed.connect(_show_page.bind("join"))
	home.add_child(b2)
	var b3 := _mkbtn("Cài đặt", 74, 32)
	b3.pressed.connect(_open_settings.bind("home"))
	home.add_child(b3)
	var b4 := _mkbtn("Hướng dẫn", 74, 32)
	b4.pressed.connect(_show_page.bind("guide"))
	home.add_child(b4)
	var b5 := _mkbtn("Thoát game", 74, 32)
	b5.pressed.connect(_quit)
	home.add_child(b5)
	pages["home"] = home
	col.add_child(home)

	# Vào phòng
	var join := VBoxContainer.new()
	join.add_theme_constant_override("separation", 12)
	join.add_child(_lbl("Địa chỉ IP của người tạo phòng", 28, Color.WHITE))
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "Ví dụ: 192.168.1.5"
	ip_edit.text = last_ip
	ip_edit.custom_minimum_size = Vector2(0, 80)
	ip_edit.add_theme_font_size_override("font_size", 30)
	join.add_child(ip_edit)
	var j1 := _mkbtn("Kết nối", 74, 32)
	j1.pressed.connect(_on_join)
	join.add_child(j1)
	var j2 := _mkbtn("Quay lại", 74, 32)
	j2.pressed.connect(_show_page.bind("home"))
	join.add_child(j2)
	pages["join"] = join
	col.add_child(join)

	# Cài đặt
	var st := VBoxContainer.new()
	st.add_theme_constant_override("separation", 8)
	st.add_child(_lbl("CÀI ĐẶT", 44, Color(1.0, 0.75, 0.35)))
	st.add_child(_vol_row("Âm lượng tổng", "master"))
	st.add_child(_vol_row("Hiệu ứng và nhạc", "sfx"))
	st.add_child(_vol_row("Giọng nói", "voice"))
	btn_fps = _mkbtn("", 64, 28)
	btn_fps.pressed.connect(_toggle_fps)
	st.add_child(btn_fps)
	btn_shadow = _mkbtn("", 64, 28)
	btn_shadow.pressed.connect(_cycle_shadow)
	st.add_child(btn_shadow)
	var s1 := _mkbtn("Quay lại", 66, 30)
	s1.pressed.connect(_settings_back)
	st.add_child(s1)
	pages["settings"] = st
	col.add_child(st)

	# Hướng dẫn
	var gd := VBoxContainer.new()
	gd.add_theme_constant_override("separation", 10)
	gd.add_child(_lbl("HƯỚNG DẪN", 44, Color(1.0, 0.75, 0.35)))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 400)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var gl := Label.new()
	gl.text = "ĐIỀU KHIỂN\n- Kéo ở nửa trái màn hình: di chuyển.\n- Kéo ở nửa phải: xoay camera.\n- Giữ nút Chạy: chạy nhanh, tốn thể lực.\n- Thu thập: hái quả, chặt cây, đập đá ở gần.\n- Túi đồ: xem đồ và chế tạo.\n- Dùng: dùng dụng cụ đang cầm (rìu, cuốc, kiếm, cung, cần câu).\n- Đánh / Tương tác: chiến đấu, vắt sữa, trao đổi với thổ dân.\n- Mic: bật để nói chuyện với người ở gần.\n\nSINH TỒN\n- Giữ Máu, Đói, Khát, Thể lực. Hết thể lực khi bơi sẽ chết đuối.\n- Ban đêm tối, hãy đốt lửa trại để nướng đồ ăn.\n- Trồng hạt giống để có thức ăn lâu dài.\n\nMẸO\n- Cột khói cam là làng thổ dân, tia sáng xanh là tháp cổ.\n- Chơi nhiều người: người tạo phòng đọc IP trên màn hình cho bạn bè."
	gl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gl.custom_minimum_size = Vector2(580, 0)
	gl.add_theme_font_size_override("font_size", 24)
	sc.add_child(gl)
	gd.add_child(sc)
	var g1 := _mkbtn("Quay lại", 66, 30)
	g1.pressed.connect(_show_page.bind("home"))
	gd.add_child(g1)
	pages["guide"] = gd
	col.add_child(gd)

	# Tạm dừng
	var pz := VBoxContainer.new()
	pz.add_theme_constant_override("separation", 14)
	pz.add_child(_lbl("TẠM DỪNG", 56, Color(1.0, 0.75, 0.35)))
	var p1 := _mkbtn("Tiếp tục", 76, 32)
	p1.pressed.connect(_resume)
	pz.add_child(p1)
	var p2 := _mkbtn("Cài đặt", 76, 32)
	p2.pressed.connect(_open_settings.bind("pause"))
	pz.add_child(p2)
	var p3 := _mkbtn("Về menu chính", 76, 32)
	p3.pressed.connect(_to_title)
	pz.add_child(p3)
	pages["pause"] = pz
	col.add_child(pz)

	status = _lbl("", 24, Color(1.0, 0.85, 0.5))
	col.add_child(status)

func _vol_row(t: String, key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = t
	l.custom_minimum_size = Vector2(300, 0)
	l.add_theme_font_size_override("font_size", 28)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	var minus := _mkbtn("-", 64, 34)
	minus.custom_minimum_size = Vector2(80, 64)
	minus.pressed.connect(_vol_step.bind(key, -0.1))
	row.add_child(minus)
	var v := Label.new()
	v.custom_minimum_size = Vector2(100, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.add_theme_font_size_override("font_size", 28)
	row.add_child(v)
	val_labels[key] = v
	var plus := _mkbtn("+", 64, 34)
	plus.custom_minimum_size = Vector2(80, 64)
	plus.pressed.connect(_vol_step.bind(key, 0.1))
	row.add_child(plus)
	return row

# ---------- ĐIỀU HƯỚNG TRANG ----------
func _show_page(name: String) -> void:
	for k in pages.keys():
		var p: Control = pages[k]
		p.visible = (k == name)
	title_box.visible = (name == "home" or name == "join")
	if name != "join":
		pass
	status.text = ""

func _go_title() -> void:
	mode = "title"
	layer.visible = true
	bg.visible = true
	dim.visible = false
	pause_layer.visible = false
	_show_page("home")

func _open_settings(from: String) -> void:
	back_to = from
	_refresh_values()
	_show_page("settings")

func _settings_back() -> void:
	_save()
	_show_page(back_to)

func _refresh_values() -> void:
	for k in val_labels.keys():
		var l: Label = val_labels[k]
		l.text = "%d%%" % int(round(float(vals[k]) * 100.0))
	btn_fps.text = "Giới hạn FPS: %d" % fps_cap
	var names := ["Thấp (tắt bóng)", "Trung bình", "Cao"]
	btn_shadow.text = "Bóng đổ: " + names[shadow_q]

func _vol_step(key: String, d: float) -> void:
	vals[key] = clampf(snappedf(float(vals[key]) + d, 0.1), 0.0, 1.0)
	_refresh_values()
	_apply()

func _toggle_fps() -> void:
	fps_cap = 30 if fps_cap == 60 else 60
	_refresh_values()
	_apply()

func _cycle_shadow() -> void:
	shadow_q = (shadow_q + 2) % 3
	_refresh_values()
	_apply()

func _back() -> void:
	if mode == "play":
		_open_pause()
	elif mode == "pause":
		if pages["settings"].visible:
			_settings_back()
		else:
			_resume()
	else:
		if pages["home"].visible:
			_quit()
		elif pages["settings"].visible:
			_settings_back()
		else:
			_show_page("home")

func _quit() -> void:
	_save()
	get_tree().quit()

# ---------- VÀO GAME ----------
func _on_host() -> void:
	if main == null:
		return
	status.text = ""
	main.info.text = ""
	main._host()

func _on_join() -> void:
	if main == null:
		return
	var ip := ip_edit.text.strip_edges()
	if ip == "":
		status.text = "Hãy nhập địa chỉ IP"
		return
	last_ip = ip
	_save()
	main.ip_edit.text = ip
	main.info.text = ""
	status.text = "Đang kết nối..."
	main._join()

func _open_pause() -> void:
	if mode != "play":
		return
	mode = "pause"
	layer.visible = true
	bg.visible = false
	dim.visible = true
	pause_layer.visible = false
	_show_page("pause")

func _resume() -> void:
	mode = "play"
	layer.visible = false
	dim.visible = false

func _to_title() -> void:
	if main != null and is_instance_valid(main):
		dead_id = main_id
		main = null
	multiplayer.multiplayer_peer = null
	get_tree().reload_current_scene()
	_go_title()

# ---------- VÒNG LẶP ----------
func _process(delta: float) -> void:
	t_now += delta
	if main == null:
		var cs := get_tree().current_scene
		if cs != null and cs.get_instance_id() != dead_id and cs.get("started") != null and cs.get("menu") != null and cs.get("info") != null and cs.get("sun") != null:
			main = cs
			main_id = cs.get_instance_id()
			_apply()
		if mode == "title":
			_animate()
		return
	if not is_instance_valid(main):
		dead_id = main_id
		main = null
		_go_title()
		status.text = "Đã rời khỏi phòng"
		return
	var started: bool = main.started
	if not started:
		main.menu.visible = false
		var msg: String = main.info.text
		if msg != "" and mode == "title":
			status.text = msg
		if mode == "title":
			_animate()
	elif mode == "title":
		mode = "play"
		layer.visible = false
		dim.visible = false
	pause_layer.visible = (mode == "play") and started
	if mode == "pause":
		main.move_vec = Vector2.ZERO
		main.joy_id = -1
		main.look_id = -1
		main.run_id = -1
		main.running = false
		main.joy_base.visible = false
		main.joy_knob.visible = false

func _animate() -> void:
	for i in stars.size():
		var s: ColorRect = stars[i]
		s.modulate.a = 0.35 + 0.65 * absf(sin(t_now * (0.6 + float(i % 5) * 0.3) + float(i)))
	for k in layers.size():
		var p: Node2D = layers[k]
		p.position.x = sin(t_now * 0.12 * float(k + 1)) * 14.0 * float(k + 1)
	for f in flies:
		var n: ColorRect = f["n"]
		var b: Vector2 = f["b"]
		var ph: float = f["ph"]
		var sp: float = f["sp"]
		n.position = b + Vector2(sin(t_now * sp + ph) * 34.0, cos(t_now * sp * 0.8 + ph) * 22.0)
		n.modulate.a = 0.25 + 0.75 * maxf(0.0, sin(t_now * 2.0 + ph))
