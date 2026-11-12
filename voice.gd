extends Node

const VRATE := 12000
const CHUNK := 960
const RANGE := 55.0
const VAD := 0.02
const GAIN := 2.0
const MU := 255.0

var main = null
var mic_on := false
var capture: AudioEffectCapture
var mic_player: AudioStreamPlayer
var raw := PackedFloat32Array()
var buf := PackedFloat32Array()
var speak_until := 0.0
var speakers := {}
var t_now := 0.0

var ui: CanvasLayer
var btn: Button
var lbl: Label

func _ready() -> void:
	AudioServer.add_bus()
	var mic_bus := AudioServer.bus_count - 1
	AudioServer.set_bus_name(mic_bus, "Mic")
	capture = AudioEffectCapture.new()
	AudioServer.add_bus_effect(mic_bus, capture)
	AudioServer.set_bus_mute(mic_bus, true)
	AudioServer.add_bus()
	var voice_bus := AudioServer.bus_count - 1
	AudioServer.set_bus_name(voice_bus, "Voice")
	mic_player = AudioStreamPlayer.new()
	mic_player.stream = AudioStreamMicrophone.new()
	mic_player.bus = "Mic"
	add_child(mic_player)
	get_tree().on_request_permissions_result.connect(_on_perm)
	_build_ui()

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	btn = Button.new()
	btn.text = "Mic: TẮT"
	btn.focus_mode = Control.FOCUS_NONE
	btn.anchor_left = 1.0
	btn.anchor_right = 1.0
	btn.offset_left = -220
	btn.offset_right = -20
	btn.offset_top = 20
	btn.offset_bottom = 80
	btn.add_theme_font_size_override("font_size", 24)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.5)
	sb.set_corner_radius_all(16)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.pressed.connect(_toggle_mic)
	btn.visible = false
	ui.add_child(btn)
	lbl = Label.new()
	lbl.anchor_left = 1.0
	lbl.anchor_right = 1.0
	lbl.offset_left = -420
	lbl.offset_right = -20
	lbl.offset_top = 160
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.add_theme_font_size_override("font_size", 22)
	ui.add_child(lbl)

func _on_perm(_perm: String, granted: bool) -> void:
	if granted and mic_on:
		mic_player.stop()
		mic_player.play()

func _toggle_mic() -> void:
	mic_on = not mic_on
	btn.text = "Mic: BẬT" if mic_on else "Mic: TẮT"
	if mic_on:
		if OS.get_name() == "Android":
			var gp := OS.get_granted_permissions()
			if not gp.has("android.permission.RECORD_AUDIO"):
				OS.request_permissions()
		mic_player.play()
		capture.clear_buffer()
		raw.clear()
		buf.clear()
	else:
		mic_player.stop()
		btn.modulate = Color(1, 1, 1)

func _process(delta: float) -> void:
	t_now += delta
	if main == null:
		var cs := get_tree().current_scene
		if cs != null and cs.get("started") != null and cs.get("targets") != null:
			main = cs
		return
	if not is_instance_valid(main):
		_reset()
		return
	var on: bool = main.started
	btn.visible = on
	if not on:
		return
	_update_speakers()
	if mic_on:
		_pump_mic()
		btn.modulate = Color(0.5, 1.0, 0.5) if t_now < speak_until else Color(1, 1, 1)

func _reset() -> void:
	main = null
	if mic_on:
		_toggle_mic()
	for id in speakers.keys():
		var sp: Dictionary = speakers[id]
		var p: AudioStreamPlayer3D = sp["player"]
		p.queue_free()
	speakers.clear()
	btn.visible = false
	lbl.text = ""

# ---------- THU VÀ GỬI ----------
func _pump_mic() -> void:
	var avail := capture.get_frames_available()
	if avail <= 0:
		return
	var frames := capture.get_buffer(avail)
	for v in frames:
		raw.append((v.x + v.y) * 0.5)
	var ratio := AudioServer.get_mix_rate() / float(VRATE)
	var pos := 0.0
	while pos + ratio <= float(raw.size()):
		var a := int(pos)
		var b := mini(int(pos + ratio), raw.size() - 1)
		var s := 0.0
		for k in range(a, b + 1):
			s += raw[k]
		buf.append(s / float(b - a + 1))
		pos += ratio
	raw = raw.slice(int(pos))
	while buf.size() >= CHUNK:
		var chunk := buf.slice(0, CHUNK)
		buf = buf.slice(CHUNK)
		_send_chunk(chunk)

func _enc(x: float) -> int:
	var v := clampf(x, -1.0, 1.0)
	var m := signf(v) * log(1.0 + MU * absf(v)) / log(1.0 + MU)
	return clampi(int(roundf(m * 127.0)) + 128, 0, 255)

func _dec(b: int) -> float:
	var m := float(b - 128) / 127.0
	return signf(m) * (pow(1.0 + MU, absf(m)) - 1.0) / MU

func _send_chunk(chunk: PackedFloat32Array) -> void:
	var peak := 0.0
	for s in chunk:
		peak = maxf(peak, absf(s))
	if peak * GAIN > VAD:
		speak_until = t_now + 0.45
	if t_now > speak_until:
		return
	var data := PackedByteArray()
	data.resize(chunk.size())
	for i in chunk.size():
		data[i] = _enc(chunk[i] * GAIN)
	var pos: Vector3 = main.player.position + Vector3(0, 1.6, 0)
	if multiplayer.is_server():
		_forward(1, data, pos)
	elif multiplayer.has_multiplayer_peer():
		_voice_up.rpc_id(1, data, pos)

func _forward(from: int, data: PackedByteArray, pos: Vector3) -> void:
	for id in main.targets.keys():
		var pid := int(id)
		if pid == from:
			continue
		var lp: Vector3 = main.targets[id]
		if Vector2(lp.x - pos.x, lp.z - pos.z).length() < RANGE:
			_voice_down.rpc_id(pid, from, data, pos)
	if from != 1:
		var hp: Vector3 = main.player.position
		if Vector2(hp.x - pos.x, hp.z - pos.z).length() < RANGE:
			_play_voice(from, data, pos)

@rpc("any_peer", "unreliable")
func _voice_up(data: PackedByteArray, pos: Vector3) -> void:
	if main != null and multiplayer.is_server():
		_forward(multiplayer.get_remote_sender_id(), data, pos)

@rpc("authority", "unreliable")
func _voice_down(from: int, data: PackedByteArray, pos: Vector3) -> void:
	_play_voice(from, data, pos)

# ---------- NGHE ----------
func _play_voice(from: int, data: PackedByteArray, pos: Vector3) -> void:
	if main == null:
		return
	var sp: Dictionary
	if speakers.has(from):
		sp = speakers[from]
	else:
		var p := AudioStreamPlayer3D.new()
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = VRATE
		gen.buffer_length = 0.6
		p.stream = gen
		p.bus = "Voice"
		p.unit_size = 7.0
		p.max_distance = RANGE
		p.volume_db = 4.0
		add_child(p)
		p.play()
		sp = {"player": p, "pb": p.get_stream_playback(), "last": 0.0}
		speakers[from] = sp
	var p2: AudioStreamPlayer3D = sp["player"]
	p2.global_position = pos
	sp["last"] = t_now
	var pb: AudioStreamGeneratorPlayback = sp["pb"]
	var frames := PackedVector2Array()
	frames.resize(data.size())
	for i in data.size():
		var s := _dec(data[i])
		frames[i] = Vector2(s, s)
	if pb.get_frames_available() >= frames.size():
		pb.push_buffer(frames)

func _update_speakers() -> void:
	var names := PackedStringArray()
	for id in speakers.keys():
		var sp: Dictionary = speakers[id]
		if t_now - float(sp["last"]) < 0.5:
			names.append("Người chơi %d" % int(id))
		if main.others.has(id):
			var n: Node3D = main.others[id]
			var p: AudioStreamPlayer3D = sp["player"]
			p.global_position = n.global_position + Vector3(0, 1.6, 0)
	if names.size() > 0:
		lbl.text = "Đang nói: " + ", ".join(names)
	else:
		lbl.text = ""
