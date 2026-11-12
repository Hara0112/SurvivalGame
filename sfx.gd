extends Node

const RATE := 22050
const R2 := 11025
const MUSIC := true

var main = null
var snd := {}
var rng := RandomNumberGenerator.new()
var bus_idx := -1
var ui: CanvasLayer
var btn: Button
var on := true
var inited := false
var t_now := 0.0

var wind: AudioStreamPlayer
var cricket: AudioStreamPlayer
var prev_pos := Vector3.ZERO
var steps_d := 0.0
var splash_t := 0.0
var prev_swim := false
var prev_hp := 100.0
var hp_t := 0.0
var prev_hunger := 100.0
var prev_thirst := 100.0
var prev_inv := {}
var inv_t := 0.0
var prev_hits := 0
var prev_anim := ""
var prev_fired := false
var prev_fish := "idle"
var animal_t := 4.0
var birds_t := 3.0
var music_t := 3.0

func _ready() -> void:
	rng.randomize()
	AudioServer.add_bus()
	bus_idx = AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_idx, "SFX")
	_build_sounds()
	ui = CanvasLayer.new()
	add_child(ui)
	btn = Button.new()
	btn.text = "Âm: BẬT"
	btn.focus_mode = Control.FOCUS_NONE
	btn.anchor_left = 1.0
	btn.anchor_right = 1.0
	btn.offset_left = -220
	btn.offset_right = -20
	btn.offset_top = 90
	btn.offset_bottom = 150
	btn.add_theme_font_size_override("font_size", 24)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.5)
	sb.set_corner_radius_all(16)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.pressed.connect(_toggle)
	btn.visible = false
	ui.add_child(btn)

func _toggle() -> void:
	on = not on
	btn.text = "Âm: BẬT" if on else "Âm: TẮT"
	AudioServer.set_bus_mute(bus_idx, not on)

func _reset() -> void:
	main = null
	inited = false
	btn.visible = false
	if wind != null:
		wind.stop()
	if cricket != null:
		cricket.stop()

func _setup() -> void:
	if wind == null:
		wind = AudioStreamPlayer.new()
		wind.stream = snd["wind"]
		wind.bus = "SFX"
		wind.volume_db = -34.0
		add_child(wind)
		cricket = AudioStreamPlayer.new()
		cricket.stream = snd["cricket"]
		cricket.bus = "SFX"
		cricket.volume_db = -70.0
		add_child(cricket)

func _process(delta: float) -> void:
	if main == null:
		var cs := get_tree().current_scene
		if cs != null and cs.get("started") != null and cs.get("hits") != null and cs.get("inv") != null:
			main = cs
			_setup()
		return
	if not is_instance_valid(main):
		_reset()
		return
	var live: bool = main.started
	btn.visible = live
	if not live:
		return
	t_now += delta
	var pp: Vector3 = main.player.position
	if not inited:
		inited = true
		prev_inv = main.inv.duplicate()
		prev_pos = pp
		prev_hp = main.hp
		prev_hunger = main.hunger
		prev_thirst = main.thirst
		prev_swim = main.swim
		wind.play()
		cricket.play()

	_footsteps(delta, pp)
	_vitals(delta)
	_inventory(delta)
	_tools()
	_ambient(delta, pp)

# ---------- HÀNH ĐỘNG ----------
func _footsteps(delta: float, pp: Vector3) -> void:
	var d := Vector2(pp.x - prev_pos.x, pp.z - prev_pos.z).length()
	prev_pos = pp
	var sw: bool = main.swim
	if sw and not prev_swim:
		_play("splash", -4.0, 0.8)
	prev_swim = sw
	if d > 3.0 or d < 0.002:
		return
	if sw:
		splash_t -= delta
		if splash_t <= 0.0:
			_play("splash", -14.0, rng.randf_range(0.9, 1.2))
			splash_t = 0.8
		return
	steps_d += d
	var stride := 2.1 if main.running and main.stamina > 0.0 else 1.6
	if steps_d >= stride:
		steps_d = 0.0
		var h: float = main._height(pp.x, pp.z)
		var t: float = main.tnoise.get_noise_2d(pp.x, pp.z)
		var kind := "step_grass"
		if h < -1.5 or t > 0.3:
			kind = "step_sand"
		elif h > 22.0 or t < -0.28:
			kind = "step_snow"
		elif h > 12.0:
			kind = "step_rock"
		_play(kind, -12.0, rng.randf_range(0.9, 1.1))

func _vitals(delta: float) -> void:
	hp_t += delta
	if hp_t >= 0.4:
		hp_t = 0.0
		if float(main.hp) < prev_hp - 3.0:
			_play("hurt", -4.0, rng.randf_range(0.9, 1.1))
		prev_hp = main.hp
	if float(main.hunger) > prev_hunger + 4.0:
		_play("eat", -6.0, rng.randf_range(0.95, 1.1))
	if float(main.thirst) > prev_thirst + 8.0:
		_play("drink", -6.0, 1.0)
	prev_hunger = main.hunger
	prev_thirst = main.thirst

func _inventory(delta: float) -> void:
	var hs := 0
	for v in main.hits.values():
		hs += int(v)
	if hs > prev_hits:
		_play("thud", -6.0, rng.randf_range(0.9, 1.1))
	prev_hits = hs
	inv_t += delta
	if inv_t < 0.2:
		return
	inv_t = 0.0
	var inv: Dictionary = main.inv
	var played := false
	for k in inv.keys():
		var c := int(inv[k])
		var o := int(prev_inv.get(k, 0))
		if c > o and not played:
			played = true
			if k == "wood":
				_play("chop", -4.0, 1.0)
			elif k == "stone":
				_play("clink", -6.0, 1.0)
			else:
				_play("pick", -6.0, rng.randf_range(0.95, 1.15))
	prev_inv = inv.duplicate()

func _tools() -> void:
	var g = get_node_or_null("/root/Gear")
	if g == null or g.vm == null:
		return
	var a: String = g.anim
	if a != prev_anim:
		if a == "slash":
			_play("whoosh", -3.0, 1.0)
		elif a == "chop" or a == "mine" or a == "punch":
			_play("whoosh", -9.0, 1.3)
		elif a == "cast":
			_play("whoosh", -8.0, 0.8)
		elif a == "reel":
			_play("splash", -6.0, 1.1)
	prev_anim = a
	var fired: bool = g.anim_fired
	if a == "bow" and fired and not prev_fired:
		_play("twang", -3.0, rng.randf_range(0.95, 1.05))
	prev_fired = fired
	var fs: String = g.fish_state
	if fs == "bite" and prev_fish != "bite":
		_play("bubble", -3.0, 1.0)
	prev_fish = fs

# ---------- MÔI TRƯỜNG ----------
func _ambient(delta: float, pp: Vector3) -> void:
	var h: float = main._height(pp.x, pp.z)
	var alt := clampf((h - 5.0) / 20.0, 0.0, 1.0)
	var k := clampf(delta * 1.5, 0.0, 1.0)
	wind.volume_db = lerpf(wind.volume_db, lerpf(-34.0, -14.0, alt), k)
	var night: bool = main.time_name == "Đêm"
	var cdb := -70.0
	if night and h > -1.0 and h < 12.0:
		cdb = -28.0
	cricket.volume_db = lerpf(cricket.volume_db, cdb, k)

	birds_t -= delta
	if birds_t <= 0.0:
		birds_t = rng.randf_range(3.0, 8.0)
		if not night and main._biome_id(h, main.tnoise.get_noise_2d(pp.x, pp.z)) == 0:
			var ang := rng.randf() * TAU
			var rad := rng.randf_range(10.0, 25.0)
			var bp := pp + Vector3(cos(ang) * rad, rng.randf_range(5.0, 10.0), sin(ang) * rad)
			_play3d("bird%d" % rng.randi_range(0, 2), bp, -8.0, rng.randf_range(0.9, 1.15))

	animal_t -= delta
	if animal_t <= 0.0:
		animal_t = rng.randf_range(4.0, 9.0)
		_animal_call(pp)

	if MUSIC:
		music_t -= delta
		if music_t <= 0.0:
			music_t = rng.randf_range(3.5, 8.0)
			var lo := 0 if night else 1
			var idx := lo + rng.randi_range(0, 5)
			_play("n%d" % idx, -20.0, 1.0)
			if rng.randf() < 0.4:
				_play("n%d" % (lo + rng.randi_range(0, 5)), -23.0, 1.0)

func _animal_call(pp: Vector3) -> void:
	var f = get_node_or_null("/root/Fauna")
	if f == null:
		return
	var cand: Array = []
	for id in f.puppets.keys():
		var n: Node3D = f.puppets[id]
		if Vector2(n.position.x - pp.x, n.position.z - pp.z).length() < 35.0 and int(f.ptype[id]) < 4:
			cand.append(id)
	if cand.is_empty():
		return
	var pick = cand[rng.randi() % cand.size()]
	var ty: int = f.ptype[pick]
	var names := ["moo", "oink", "baa", "cluck"]
	var pn: Node3D = f.puppets[pick]
	_play3d(names[ty], pn.global_position + Vector3(0, 1.0, 0), -4.0, rng.randf_range(0.85, 1.15))

# ---------- PHÁT ----------
var real := {}
var REAL_MAP := {
	"step_grass": ["footstep_grass"],
	"step_sand": ["footstep_carpet", "footstep_grass"],
	"step_snow": ["footstep_snow"],
	"step_rock": ["footstep_concrete"],
	"chop": ["impactWood_heavy", "impactWood_medium"],
	"thud": ["impactWood_medium", "impactWood_light"],
	"mine": ["impactMining", "impactMetal_medium", "impactMetal_light"],
	"clink": ["impactMining", "impactPlate_light", "impactMetal_light"],
	"hurt": ["impactPunch_heavy", "impactPunch_medium"],
}

func _audio_files(dir: String) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir):
		var n := f.trim_suffix(".remap").trim_suffix(".import")
		var ext := n.get_extension().to_lower()
		if ext == "ogg" or ext == "wav" or ext == "mp3":
			if not out.has(n):
				out.append(n)
	return out

func _load_list(dir: String, names: Array) -> Array:
	var arr: Array = []
	for n in names:
		var s = load(dir + "/" + str(n))
		if s is AudioStream:
			arr.append(s)
	return arr

func _load_real() -> void:
	if DirAccess.open("res://audio") == null:
		return
	var all := _audio_files("res://audio")
	for cat in REAL_MAP.keys():
		for pre in REAL_MAP[cat]:
			var found: Array = []
			for n in all:
				if str(n).to_lower().begins_with(str(pre).to_lower()):
					found.append(n)
			if found.size() > 0:
				var l := _load_list("res://audio", found)
				if l.size() > 0:
					real[cat] = l
					break
	for d in DirAccess.get_directories_at("res://audio"):
		var files := _audio_files("res://audio/" + d)
		if files.size() > 0:
			var l2 := _load_list("res://audio/" + d, files)
			if l2.size() > 0:
				real[d] = l2

func _stream_for(name: String) -> AudioStream:
	var key := name
	if name == "thud":
		var g = get_node_or_null("/root/Gear")
		if g != null and g.held == "pick" and real.has("mine"):
			key = "mine"
	if real.has(key):
		var arr: Array = real[key]
		return arr[rng.randi() % arr.size()]
	if snd.has(name):
		return snd[name]
	return null

func _play(name: String, db: float, pitch: float) -> void:
	var s := _stream_for(name)
	if s == null or get_child_count() > 50:
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = "SFX"
	p.volume_db = db
	p.pitch_scale = pitch
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

func _play3d(name: String, pos: Vector3, db: float, pitch: float) -> void:
	var s := _stream_for(name)
	if s == null or get_child_count() > 50:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = "SFX"
	p.volume_db = db
	p.pitch_scale = pitch
	p.unit_size = 6.0
	p.max_distance = 60.0
	add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()

# ---------- TỔNG HỢP ÂM THANH ----------
func _arr(sec: float, rate: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(int(sec * float(rate)))
	return a

func _noise() -> float:
	return rng.randf_range(-1.0, 1.0)

func _mk(s: PackedFloat32Array, rate: int, loop: bool, loop_begin: int = 0) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	var d := PackedByteArray()
	d.resize(s.size() * 2)
	for i in s.size():
		d.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	w.data = d
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = loop_begin
		w.loop_end = s.size()
	return w

func _s_step(k: float, thump: float, decay: float) -> AudioStreamWAV:
	var a := _arr(0.14, RATE)
	var lp := 0.0
	for i in a.size():
		var t := float(i) / float(RATE)
		var e := exp(-t * decay)
		lp += (_noise() - lp) * k
		a[i] = lp * 1.6 * e + sin(TAU * 90.0 * t) * e * thump
	return _mk(a, RATE, false)

func _s_whoosh(sec: float, amp: float, k0: float, k1: float) -> AudioStreamWAV:
	var a := _arr(sec, RATE)
	var n := a.size()
	var lp := 0.0
	for i in n:
		var u := float(i) / float(n)
		lp += (_noise() - lp) * lerpf(k0, k1, u)
		a[i] = lp * sin(PI * u) * amp
	return _mk(a, RATE, false)

func _s_thud(f0: float, sec: float, nz: float, decay: float) -> AudioStreamWAV:
	var a := _arr(sec, RATE)
	var ph := 0.0
	for i in a.size():
		var t := float(i) / float(RATE)
		ph += TAU * lerpf(f0, f0 * 0.5, t / sec) / float(RATE)
		a[i] = (sin(ph) * 0.9 + _noise() * nz * exp(-t * 90.0)) * exp(-t * decay)
	return _mk(a, RATE, false)

func _s_clink() -> AudioStreamWAV:
	var a := _arr(0.3, RATE)
	for i in a.size():
		var t := float(i) / float(RATE)
		var v := sin(TAU * 1850.0 * t) + 0.6 * sin(TAU * 2770.0 * t) + 0.4 * sin(TAU * 4100.0 * t)
		a[i] = v * exp(-t * 22.0) * 0.4
	return _mk(a, RATE, false)

func _s_twang() -> AudioStreamWAV:
	var a := _arr(0.6, RATE)
	var ph := 0.0
	for i in a.size():
		var t := float(i) / float(RATE)
		var f := 220.0 * (1.0 + 0.04 * sin(TAU * 18.0 * t) * exp(-t * 3.0))
		ph += TAU * f / float(RATE)
		a[i] = (sin(ph) * 0.7 + _noise() * 0.5 * exp(-t * 80.0)) * exp(-t * 5.0)
	return _mk(a, RATE, false)

func _s_splash() -> AudioStreamWAV:
	var a := _arr(0.5, RATE)
	var lp := 0.0
	for i in a.size():
		var t := float(i) / float(RATE)
		lp += (_noise() - lp) * 0.3
		a[i] = lp * 1.4 * exp(-t * 5.0) * (1.0 - exp(-t * 60.0))
	return _mk(a, RATE, false)

func _s_pick() -> AudioStreamWAV:
	var a := _arr(0.2, RATE)
	var n := a.size()
	for i in n:
		var t := float(i) / float(RATE)
		var f := 640.0 if i < n / 2 else 960.0
		var u := fmod(float(i) / float(n) * 2.0, 1.0)
		a[i] = sin(TAU * f * t) * sin(PI * u) * 0.5
	return _mk(a, RATE, false)

func _s_eat() -> AudioStreamWAV:
	var a := _arr(0.3, RATE)
	for i in a.size():
		var t := float(i) / float(RATE)
		var tt := fmod(t, 0.09)
		a[i] = _noise() * exp(-tt * 70.0) * (1.0 if t < 0.27 else 0.0) * 0.7
	return _mk(a, RATE, false)

func _s_hurt() -> AudioStreamWAV:
	var a := _arr(0.3, RATE)
	var ph := 0.0
	for i in a.size():
		var t := float(i) / float(RATE)
		ph += lerpf(150.0, 90.0, t / 0.3) / float(RATE)
		a[i] = ((fmod(ph, 1.0) * 2.0 - 1.0) * 0.6 + _noise() * 0.3) * exp(-t * 7.0)
	return _mk(a, RATE, false)

func _s_drink() -> AudioStreamWAV:
	var a := _arr(0.45, RATE)
	for i in a.size():
		var t := float(i) / float(RATE)
		var tt := fmod(t, 0.15)
		var f := lerpf(280.0, 180.0, tt / 0.15)
		a[i] = sin(TAU * f * tt) * exp(-tt * 18.0) * 0.6 + _noise() * 0.1 * exp(-tt * 30.0)
	return _mk(a, RATE, false)

func _s_bubble() -> AudioStreamWAV:
	var a := _arr(0.4, RATE)
	for i in a.size():
		var t := float(i) / float(RATE)
		var tt := fmod(t, 0.13)
		var f := lerpf(500.0, 1100.0, tt / 0.13)
		a[i] = sin(TAU * f * tt) * exp(-tt * 25.0) * 0.6
	return _mk(a, RATE, false)

func _s_moo() -> AudioStreamWAV:
	var a := _arr(0.9, RATE)
	var n := a.size()
	var ph := 0.0
	for i in n:
		var u := float(i) / float(n)
		var t := u * 0.9
		var f := 110.0 + 35.0 * sin(PI * u) - 25.0 * u
		ph += TAU * f / float(RATE)
		var v := sin(ph) + 0.6 * sin(2.0 * ph) + 0.35 * sin(3.0 * ph) + 0.2 * sin(4.0 * ph)
		a[i] = v * pow(sin(PI * u), 0.6) * 0.3 * (0.85 + 0.15 * sin(TAU * 7.0 * t))
	return _mk(a, RATE, false)

func _s_oink() -> AudioStreamWAV:
	var a := _arr(0.35, RATE)
	var n := a.size()
	var ph := 0.0
	for i in n:
		var u := float(i) / float(n)
		ph += TAU * lerpf(300.0, 150.0, u) / float(RATE)
		var v := 0.0
		for h in range(1, 6):
			v += sin(float(h) * ph) / float(h)
		a[i] = (v * 0.5 + _noise() * 0.08) * pow(sin(PI * u), 0.5) * 0.5
	return _mk(a, RATE, false)

func _s_baa() -> AudioStreamWAV:
	var a := _arr(0.8, RATE)
	var n := a.size()
	var ph := 0.0
	for i in n:
		var u := float(i) / float(n)
		var t := u * 0.8
		ph += TAU * (330.0 + 18.0 * sin(TAU * 6.0 * t)) / float(RATE)
		var v := 0.0
		for h in range(1, 7):
			v += sin(float(h) * ph) / float(h)
		a[i] = (v * 0.45 + _noise() * 0.05) * pow(sin(PI * u), 0.7) * 0.5
	return _mk(a, RATE, false)

func _s_cluck() -> AudioStreamWAV:
	var a := _arr(0.4, RATE)
	for i in a.size():
		var t := float(i) / float(RATE)
		var idx := int(t / 0.1)
		var tt := fmod(t, 0.1)
		if idx < 3:
			var f := lerpf(750.0, 520.0, tt / 0.1) * (1.0 + 0.05 * float(idx))
			a[i] = sin(TAU * f * tt) * exp(-tt * 28.0) * 0.6
	return _mk(a, RATE, false)

func _s_bird(base: float) -> AudioStreamWAV:
	var a := _arr(0.28, RATE)
	var n := a.size()
	var ph := 0.0
	for i in n:
		var u := float(i) / float(n)
		var f := base + 900.0 * sin(PI * u) + 120.0 * sin(TAU * 30.0 * u)
		ph += TAU * f / float(RATE)
		a[i] = sin(ph) * sin(PI * u) * 0.35
	return _mk(a, RATE, false)

func _s_wind() -> AudioStreamWAV:
	var a := _arr(4.0, R2)
	var n := a.size()
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / float(R2)
		lp += (_noise() - lp) * 0.05
		lp2 += (lp - lp2) * 0.2
		a[i] = lp2 * 2.4 * (0.7 + 0.3 * sin(TAU * 0.25 * t))
	var m := 2000
	for i in m:
		var w := float(i) / float(m)
		a[n - m + i] = a[n - m + i] * (1.0 - w) + a[i] * w
	return _mk(a, R2, true, m)

func _s_cricket() -> AudioStreamWAV:
	var a := _arr(0.5, RATE)
	for i in a.size():
		var t := float(i) / float(RATE)
		var tt := fmod(t, 0.125)
		var e := sin(PI * tt / 0.06) if tt < 0.06 else 0.0
		a[i] = sin(TAU * 4300.0 * t) * e * 0.3
	return _mk(a, RATE, true)

func _s_note(f: float) -> AudioStreamWAV:
	var a := _arr(2.6, R2)
	for i in a.size():
		var t := float(i) / float(R2)
		var e := (1.0 - exp(-t * 8.0)) * exp(-t * 1.3)
		var v := sin(TAU * f * t) + 0.3 * sin(TAU * 2.0 * f * t) + 0.12 * sin(TAU * 3.0 * f * t)
		a[i] = v * e * 0.3
	return _mk(a, R2, false)

func _build_sounds() -> void:
	snd["step_grass"] = _s_step(0.25, 0.35, 38.0)
	snd["step_sand"] = _s_step(0.6, 0.1, 30.0)
	snd["step_snow"] = _s_step(0.8, 0.15, 55.0)
	snd["step_rock"] = _s_step(0.9, 0.5, 60.0)
	snd["whoosh"] = _s_whoosh(0.35, 1.6, 0.08, 0.5)
	snd["thud"] = _s_thud(120.0, 0.25, 0.6, 14.0)
	snd["chop"] = _s_thud(95.0, 0.35, 0.8, 10.0)
	snd["clink"] = _s_clink()
	snd["twang"] = _s_twang()
	snd["splash"] = _s_splash()
	snd["pick"] = _s_pick()
	snd["eat"] = _s_eat()
	snd["hurt"] = _s_hurt()
	snd["drink"] = _s_drink()
	snd["bubble"] = _s_bubble()
	snd["moo"] = _s_moo()
	snd["oink"] = _s_oink()
	snd["baa"] = _s_baa()
	snd["cluck"] = _s_cluck()
	snd["bird0"] = _s_bird(2500.0)
	snd["bird1"] = _s_bird(3000.0)
	snd["bird2"] = _s_bird(3500.0)
	snd["wind"] = _s_wind()
	snd["cricket"] = _s_cricket()
	var notes := [220.0, 261.63, 293.66, 329.63, 392.0, 440.0, 523.25]
	for i in notes.size():
		snd["n%d" % i] = _s_note(notes[i])
