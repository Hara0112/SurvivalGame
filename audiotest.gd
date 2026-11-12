extends Node

var lbl: Label
var p: AudioStreamPlayer
var acc := 0.0

func _ready() -> void:
	p = AudioStreamPlayer.new()
	p.stream = _make_beep()
	add_child(p)
	var cl := CanvasLayer.new()
	cl.layer = 20
	add_child(cl)
	lbl = Label.new()
	lbl.position = Vector2(20, 330)
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(1, 1, 0.4))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 6)
	cl.add_child(lbl)
	var b1 := _btn("Phát thử Master", Vector2(20, 560))
	b1.pressed.connect(_t1)
	cl.add_child(b1)
	var b2 := _btn("Phát thử SFX", Vector2(300, 560))
	b2.pressed.connect(_t2)
	cl.add_child(b2)

func _btn(t: String, pos: Vector2) -> Button:
	var b := Button.new()
	b.text = t
	b.position = pos
	b.size = Vector2(260, 70)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 24)
	return b

func _make_beep() -> AudioStreamWAV:
	var rate := 22050
	var n := int(0.5 * float(rate))
	var d := PackedByteArray()
	d.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var e := sin(PI * float(i) / float(n))
		d.encode_s16(i * 2, int(sin(TAU * 440.0 * t) * e * 20000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = d
	return w

func _t1() -> void:
	p.play()

func _t2() -> void:
	var sf = get_node_or_null("/root/Sfx")
	if sf != null and sf.snd.has("chop"):
		sf._play("chop", 0.0, 1.0)

func _process(delta: float) -> void:
	acc += delta
	if acc < 0.5:
		return
	acc = 0.0
	var s := "Am thanh: %d bus, %d Hz\n" % [AudioServer.bus_count, int(AudioServer.get_mix_rate())]
	s += "Thiet bi: %s | %s\n" % [AudioServer.output_device, OS.get_name()]
	s += "Master: %.0f dB, tat tieng=%s\n" % [AudioServer.get_bus_volume_db(0), str(AudioServer.is_bus_mute(0))]
	for nm in ["Sfx", "Voice", "Gear", "Fauna", "Menu"]:
		s += "%s=%s  " % [nm, "co" if get_node_or_null("/root/" + nm) != null else "KHONG"]
	var sf = get_node_or_null("/root/Sfx")
	if sf != null:
		var bi := AudioServer.get_bus_index("SFX")
		s += "\nSfx: %d am, bat=%s, chay=%s, bus=%d" % [sf.snd.size(), str(sf.on), str(sf.inited), bi]
		if bi >= 0:
			s += ", %.0f dB, tat tieng=%s" % [AudioServer.get_bus_volume_db(bi), str(AudioServer.is_bus_mute(bi))]
	lbl.text = s
