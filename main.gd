extends Node3D

const CHUNK_SIZE := 32.0
const RES := 16
const VIEW := 2
const SPEED := 8.0

var noise := FastNoiseLite.new()
var chunks := {}
var last_chunk := Vector2i(99999, 99999)
var player: Node3D
var pivot: Node3D
var cam: Camera3D
var label: Label
var joy_base: Panel
var joy_knob: Panel
var move_vec := Vector2.ZERO
var joy_id := -1
var look_id := -1
var joy_origin := Vector2.ZERO
var yaw := 0.0
var pitch := -0.3
var mat := StandardMaterial3D.new()

func _ready() -> void:
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = 1337
	noise.frequency = 0.01
	noise.fractal_octaves = 4
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

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

	var ui := CanvasLayer.new()
	add_child(ui)
	label = Label.new()
	label.position = Vector2(20, 20)
	label.add_theme_font_size_override("font_size", 28)
	ui.add_child(label)
	joy_base = _circle(220.0, Color(1, 1, 1, 0.25))
	joy_knob = _circle(100.0, Color(1, 1, 1, 0.6))
	joy_base.visible = false
	joy_knob.visible = false
	ui.add_child(joy_base)
	ui.add_child(joy_knob)

	player.position.y = _height(0.0, 0.0)

func _circle(s: float, c: Color) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(s / 2.0))
	p.add_theme_stylebox_override("panel", sb)
	p.size = Vector2(s, s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

func _height(x: float, z: float) -> float:
	return noise.get_noise_2d(x, z) * 14.0

func _input(e: InputEvent) -> void:
	var half := get_viewport().get_visible_rect().size.x / 2.0
	if e is InputEventScreenTouch:
		var t: InputEventScreenTouch = e
		if t.pressed:
			if t.position.x < half and joy_id == -1:
				joy_id = t.index
				joy_origin = t.position
				joy_base.position = t.position - joy_base.size / 2.0
				joy_knob.position = t.position - joy_knob.size / 2.0
				joy_base.visible = true
				joy_knob.visible = true
			elif t.position.x >= half and look_id == -1:
				look_id = t.index
		else:
			if t.index == joy_id:
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

func _process(delta: float) -> void:
	var dir := Vector3(move_vec.x, 0.0, move_vec.y).rotated(Vector3.UP, yaw)
	player.position += dir * SPEED * delta
	player.position.y = _height(player.position.x, player.position.z)
	player.rotation.y = yaw
	pivot.rotation.x = pitch
	_update_chunks()
	label.text = "FPS %d | x %d z %d | chunks %d" % [Engine.get_frames_per_second(), player.position.x, player.position.z, chunks.size()]

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
	if h < -3.0:
		return Color(0.85, 0.78, 0.5)
	if h < 6.0:
		return Color(0.3, 0.6, 0.25)
	if h < 9.0:
		return Color(0.5, 0.5, 0.5)
	return Color(0.95, 0.95, 1.0)
