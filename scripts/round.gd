class_name Round
extends Node3D
## Plays one hole for all players (stroke play, local pass & play).
## Turn order: everyone tees off in order, then whoever is farthest from the hole.

signal hole_complete
signal quit_requested

enum Phase { INTRO, BANNER, AIM, SWING, FLIGHT, RESULT, DONE, CPU_THINK, CPU_SWING }

const AIM_SPEED := 0.733        # rad/s (~42 deg/s)
const AIM_SPEED_PUTT := 0.244   # rad/s (~14 deg/s)
const GREEN_ROLL := 0.55              # must match CourseTerrain green "roll"
const PUTTER_RANGES := [8.0, 16.0, 32.0]  # metres
const FAST_FORWARD := 4.0                 # time scale while the impatient button is on

var hole_index := 0
var hole: Dictionary
var terrain: CourseTerrain
var balls: Array = []
var strokes: Array = []
var holed: Array = []
var current := 0
var phase := Phase.INTRO
var aim_yaw := 0.0
var club := 0
var spin := Vector2.ZERO
var special_armed := false
var wind := Vector3.ZERO
var overview := false
var layup_dist := 0.0         # >0 when auto-aim chose a lay-up short of trouble
var aim_target := Vector3.ZERO # where auto-aim pointed (pin or lay-up spot)
var cpus: Dictionary = {}      # player index -> CpuPlayer
var _cpu_plan: Dictionary = {}
var _cpu_t := 0.0
var _cpu_ff := false           # player asked to fast-forward the CPU's shot

var golfer: Golfer          # the current player's golfer
var golfers: Array = []     # one per player (characters can differ)
var _seek_offset := Vector2.ZERO
var cam: CameraRig
var hud: Hud
var slope_grid: SlopeGrid
var flag_pivot: Node3D
var landing_marker: MeshInstance3D
var arc_dots: MultiMeshInstance3D
var sfx_player: AudioStreamPlayer

var _predict_dirty := true
var _predicted_land := Vector3.ZERO
var _intro_t := 0.0
var _result_timer := 0.0
var _pending: Dictionary = {}
var _shot_from := Vector3.ZERO
var _putter_range := 16.0
var _speed_cache: Dictionary = {}
var _showing_card := false
var _rng := RandomNumberGenerator.new()
var _sfx_pool: Array = []
var _sfx_next := 0
var _ambient: AudioStreamPlayer

# ================================================================ setup ===
func _ready() -> void:
	_rng.randomize()
	hole = Course.holes()[hole_index]
	terrain = CourseTerrain.new(hole, Course.theme())
	_build_environment()
	add_child(terrain.build_node())
	slope_grid = SlopeGrid.new(terrain)
	slope_grid.visible = false
	add_child(slope_grid)
	_build_flag()
	_build_markers()

	var tee3 := Vector3(terrain.tee.x, 0, terrain.tee.y)
	for i in Game.num_players:
		var b := Ball.new(terrain, Game.players[i]["color"])
		add_child(b)
		b.place(tee3)
		b.finished.connect(_on_ball_finished)
		b.bubble_popped.connect(_on_bubble_popped)
		b.landed.connect(_on_ball_landed)
		b.tree_hit.connect(_on_tree_hit)
		balls.append(b)
		strokes.append(0)
		holed.append(false)

	for i in Game.num_players:
		if Game.is_cpu(i):
			cpus[i] = CpuPlayer.new(self, Game.players[i]["character"])
	for i in Game.num_players:
		var gf := Golfer.new(Game.players[i]["character"])
		add_child(gf)
		gf.impact.connect(_on_impact)
		gf.visible = i == 0
		golfers.append(gf)
	golfer = golfers[0]

	sfx_player = AudioStreamPlayer.new()
	sfx_player.stream = Sfx.woof() # synthesise up front so the first woof doesn't hitch
	add_child(sfx_player)
	for i in 5:
		var ap := AudioStreamPlayer.new()
		add_child(ap)
		_sfx_pool.append(ap)
	# synthesise up front (cached) so the first hit doesn't hitch
	Sfx.iron()
	Sfx.wood()
	Sfx.putter()
	Sfx.cup()
	Sfx.splash()
	Sfx.thud()
	Sfx.sand()
	Sfx.wood_clunk()
	Sfx.rustle()
	Sfx.gasp()
	_ambient = AudioStreamPlayer.new()
	_ambient.stream = Sfx.ambient(String(Course.info()["theme"]))
	_ambient.volume_db = -13.0
	add_child(_ambient)
	_ambient.play()

	cam = CameraRig.new(terrain)
	add_child(cam)
	cam.current = true

	hud = Hud.new()
	add_child(hud)
	hud.set_hole(hole_index, hole, terrain)
	hud.meter.finished.connect(_on_meter_finished)
	hud.meter.cancelled.connect(_on_meter_cancelled)
	hud.quit_to_menu.connect(func() -> void: quit_requested.emit())
	hud.continue_pressed.connect(_on_continue)

	var ang := _rng.randf() * TAU
	wind = Vector3(cos(ang), 0, sin(ang)) * _rng.randf_range(0.0, float(hole["wind_max"]))

	# intro flyover
	current = 0
	golfer.stand_at(balls[0].position, _dir_to(balls[0].position, terrain.pin_pos3()), terrain)
	phase = Phase.INTRO
	_intro_t = 0.0
	_update_intro_cam(0.0)
	cam.snap()
	var yd := int(round(Game.to_yards(Course.hole_length_m(hole))))
	var head := String(Course.info()["name"])
	if Game.mode == "match":
		head = "Match vs %s  -  %s" % [Game.players[1]["name"], Game.match_status()["text"]]
	hud.show_message("%s\nHole %d: %s\nPar %d  -  %d yd" % [head, hole_index + 1, hole["name"], int(hole["par"]), yd], 4.5, Color(1, 0.95, 0.5))
	hud.set_help("A / Space: start")
	hud.meter.visible = false
	hud.set_aim_ui_visible(false)
	_refresh_player_hud()
	hud.set_club("", "", "")

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	var th := Course.theme()
	sm.sky_top_color = th["sky_top"]
	sm.sky_horizon_color = th["sky_horizon"]
	sm.ground_horizon_color = Color(0.6, 0.75, 0.6)
	sm.ground_bottom_color = Color(0.2, 0.35, 0.15)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.7, 0.85)
	env.ambient_light_energy = 0.3
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.fog_enabled = true
	env.fog_light_color = th["fog"]
	env.fog_density = 0.0012
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 0.4
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)

func _build_flag() -> void:
	var pin := terrain.pin_pos3()
	var root := Node3D.new()
	root.position = pin
	add_child(root)
	var cup := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = Ball.CUP_R
	cm.bottom_radius = Ball.CUP_R
	cm.height = 0.02
	cm.radial_segments = 12
	cup.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.02, 0.02, 0.02)
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cup.material_override = cmat
	cup.position.y = 0.012
	root.add_child(cup)
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.025
	pm.bottom_radius = 0.025
	pm.height = 2.4
	pm.radial_segments = 6
	pole.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.95, 0.95, 0.95)
	pole.material_override = pmat
	pole.position.y = 1.2
	root.add_child(pole)
	flag_pivot = Node3D.new()
	flag_pivot.position.y = 2.2
	root.add_child(flag_pivot)
	var flag := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.7, 0.42, 0.02)
	flag.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(1, 0.2, 0.2)
	flag.material_override = fmat
	flag.position = Vector3(0.35, -0.05, 0)
	flag_pivot.add_child(flag)

func _build_markers() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.95, 0.3)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	landing_marker = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.0
	tm.outer_radius = 1.35
	tm.rings = 16
	tm.ring_segments = 4
	landing_marker.mesh = tm
	landing_marker.material_override = mat
	landing_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(landing_marker)
	var dot := BoxMesh.new()
	dot.size = Vector3(0.12, 0.12, 0.12)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = dot
	mm.instance_count = 60
	arc_dots = MultiMeshInstance3D.new()
	arc_dots.multimesh = mm
	arc_dots.material_override = mat
	arc_dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(arc_dots)
	_set_markers_visible(false)

func _set_markers_visible(v: bool) -> void:
	landing_marker.visible = v
	arc_dots.visible = v

# ============================================================ turn flow ===
func _pick_next_player() -> int:
	var best := -1
	# tee shots in player order
	for i in balls.size():
		if not holed[i] and strokes[i] == 0:
			return i
	var far := -1.0
	var pin := terrain.pin_pos3()
	for i in balls.size():
		if holed[i]:
			continue
		var d := _flat_dist((balls[i] as Ball).position, pin)
		if d > far:
			far = d
			best = i
	return best

func _begin_turn() -> void:
	var next := _pick_next_player()
	if next < 0:
		_hole_finished()
		return
	current = next
	_setup_aim()
	if Game.is_cpu(current):
		_start_cpu_turn()
		return
	if _human_count() > 1:
		phase = Phase.BANNER
		var p: Dictionary = Game.players[current]
		var dist := int(round(Game.to_yards(_flat_dist(balls[current].position, terrain.pin_pos3()))))
		hud.show_banner("%s's turn!\nStroke %d  -  %d yd to the pin\n\nPass the controller and press A" % [p["name"], int(strokes[current]) + 1, dist])
		hud.meter.visible = false

func _human_count() -> int:
	var n := 0
	for i in Game.num_players:
		if not Game.is_cpu(i):
			n += 1
	return n

# ============================================================ CPU turns ===
func _start_cpu_turn() -> void:
	phase = Phase.CPU_THINK
	_cpu_t = 0.0
	_cpu_ff = false
	_set_markers_visible(false)
	hud.meter.visible = true
	hud.hide_banner()
	var p: Dictionary = Game.players[current]
	hud.set_help("%s is lining up the shot...     A / Space: fast forward" % p["name"])

func _process_cpu(delta: float) -> void:
	if Input.is_action_just_pressed("swing"):
		_cpu_ff = true
		hud.set_help("Fast forward")
	var m := hud.meter
	if phase == Phase.CPU_THINK:
		_cpu_t += delta * (4.0 if _cpu_ff else 1.0)
		if _cpu_plan.is_empty() and _cpu_t > 0.15:
			var t0 := Time.get_ticks_usec()
			_cpu_plan = (cpus[current] as CpuPlayer).plan()
			if OS.has_environment("TOBY_DEBUG"):
				print("CPU plan %s club=%s %.1fms %s" % [Game.players[current]["name"], Game.CLUBS[club]["short"], (Time.get_ticks_usec() - t0) / 1000.0, _cpu_plan])
			_on_club_changed()    # golfer, camera, HUD follow the chosen club/aim
			_set_markers_visible(false)
		if _cpu_t > 1.4 and not _cpu_plan.is_empty():
			phase = Phase.CPU_SWING
			m.speed_scale = 0.45 if special_armed and _special_id() == "puppy_eyes" else 1.0
			if _cpu_ff:
				m.speed_scale *= 3.0
			m.start(_is_putter(), _perfect_window(), _full_label())
		return
	# CPU_SWING: "press" the meter at the planned power, then at the planned timing
	var power: float = _cpu_plan["power"]
	var acc: float = _cpu_plan["accuracy"]
	if m.phase == SwingMeter.Phase.RISING or m.phase == SwingMeter.Phase.FALLING:
		golfer.set_backswing(m.value * (0.45 if _is_putter() else 1.0))
		if m.value >= power or m.phase == SwingMeter.Phase.FALLING:
			m.value = power
			phase = Phase.SWING  # meter results flow through the normal path
			m.press()
			phase = Phase.CPU_SWING if m.phase == SwingMeter.Phase.RETURN else phase
	elif m.phase == SwingMeter.Phase.IDLE:
		m.start(_is_putter(), _perfect_window(), _full_label())   # meter timed out: go again
	elif m.phase == SwingMeter.Phase.RETURN:
		var at := maxf(acc * SwingMeter.ACC_ZONE, -SwingMeter.ACC_ZONE * 0.99)
		if m.value <= at:
			m.value = at
			phase = Phase.SWING
			m.press()

func _setup_aim() -> void:
	var b: Ball = balls[current]
	for i in balls.size():
		var bi: Ball = balls[i]
		bi.visible = not holed[i] and (strokes[i] > 0 or i == current)
		bi.set_marker_visible(i != current)
	var lie := b.lie()
	var pin := terrain.pin_pos3()
	var dist := _flat_dist(b.position, pin)
	_choose_putter_range(dist)
	if lie == CourseTerrain.Surface.GREEN or (lie == CourseTerrain.Surface.FRINGE and dist < 22.0):
		club = Game.PUTTER_INDEX
	else:
		club = _auto_club(dist, lie)
	_auto_aim()
	if layup_dist > 0.0:
		club = _layup_club(layup_dist, lie)
		_auto_aim()
	spin = Vector2.ZERO
	special_armed = false
	overview = false
	for bb in balls:
		(bb as Ball).clear_trail()
	for gf in golfers:
		(gf as Golfer).visible = false
	golfer = golfers[current]
	golfer.idle()
	golfer.visible = true
	_on_club_changed()
	# a breath of wind change between shots
	var w2 := Vector2(wind.x, wind.z).rotated(_rng.randf_range(-0.15, 0.15))
	var wl := clampf(w2.length() + _rng.randf_range(-0.4, 0.4), 0.0, float(hole["wind_max"]))
	w2 = w2.normalized() * wl if w2.length() > 0.01 else Vector2.ZERO
	wind = Vector3(w2.x, 0, w2.y)
	phase = Phase.AIM
	hud.hide_banner()
	hud.meter.visible = true
	hud.set_aim_ui_visible(true)
	_cpu_plan = {}
	hud.meter.cpu_name = String(Game.players[current]["name"]) if Game.is_cpu(current) else ""
	hud.set_help("Aim: L-stick/Arrows   Club: LB RB/Up Down   Spin: R-stick/IJKL   Special: X/P   View: Y/V   Swing: A/Space")
	_refresh_player_hud()

func _is_putter() -> bool:
	return club == Game.PUTTER_INDEX

func _on_club_changed() -> void:
	var b: Ball = balls[current]
	golfer.set_club(_is_putter())
	golfer.stand_at(b.position, _aim_dir(), terrain)
	cam.set_aim(b, _aim_dir(), _is_putter())
	var lie := b.lie()
	slope_grid.visible = _is_putter() or lie == CourseTerrain.Surface.GREEN
	slope_grid.set_aim(b.position, _aim_dir(), _putt_length())
	hud.meter.reset(_full_label(), _is_putter(), _perfect_window())
	_predict_dirty = true
	_refresh_club_hud()

func _choose_putter_range(dist: float) -> void:
	_putter_range = PUTTER_RANGES[PUTTER_RANGES.size() - 1]
	for r in PUTTER_RANGES:
		if float(r) >= dist * 1.3:
			_putter_range = r
			break

# ============================================================ helpers ===
static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

static func _dir_to(from: Vector3, to: Vector3) -> Vector3:
	var d := Vector3(to.x - from.x, 0, to.z - from.z)
	return d.normalized() if d.length() > 0.001 else Vector3.FORWARD

func _aim_dir() -> Vector3:
	return Vector3(-sin(aim_yaw), 0, -cos(aim_yaw))

func _set_aim_dir(d: Vector3) -> void:
	aim_yaw = atan2(-d.x, -d.z)

func _character() -> Dictionary:
	return Game.character_for(current)

func _perfect_window() -> float:
	if special_armed and _special_id() == "reflexes":
		return 1.0 # Cat-like Reflexes: the whole accuracy zone counts as perfect
	return 0.15 + 0.2 * float(_character()["accuracy"])

func _lie_mods(lie: int, club_i: int) -> Dictionary:
	var info := terrain.surf_info(lie)
	if special_armed and _special_id() == "dig_in" and lie != CourseTerrain.Surface.GREEN:
		# Bacon's Dig In: plays like it's sitting up on the fairway
		var fw := terrain.surf_info(CourseTerrain.Surface.FAIRWAY)
		return {"dist": float(fw["dist"]), "err": float(fw["err"]), "spin": float(fw["spin"]), "name": "%s (dug in)" % info["name"]}
	var dist: float = info["dist"]
	var err: float = info["err"]
	var spn: float = info["spin"]
	if lie == CourseTerrain.Surface.BUNKER and club_i == Game.SAND_WEDGE_INDEX:
		dist = 0.9
		err = 1.2
		spn = 0.8
	if club_i == 0 and lie != CourseTerrain.Surface.TEE:
		dist *= 0.9
		err *= 1.3
	return {"dist": dist, "err": err, "spin": spn, "name": info["name"]}

func _club_carry_m(club_i: int, lie: int) -> float:
	var c: Dictionary = Game.CLUBS[club_i]
	return float(c["carry"]) / Game.YARDS_PER_METER * float(_character()["power"]) * float(_lie_mods(lie, club_i)["dist"])

func _auto_club(dist: float, lie: int) -> int:
	var max_club := 0 if lie == CourseTerrain.Surface.TEE else 1
	for i in range(Game.SAND_WEDGE_INDEX, max_club - 1, -1):
		if _club_carry_m(i, lie) * 1.06 >= dist:
			return i
	return max_club

func _auto_aim() -> void:
	layup_dist = 0.0
	var b: Ball = balls[current]
	var pin := terrain.pin_pos3()
	var dist := _flat_dist(b.position, pin)
	aim_target = pin
	if _is_putter() or club == Game.PUTTER_INDEX:
		_set_aim_dir(_dir_to(b.position, pin))
		return
	var want := _club_carry_m(club, b.lie()) * 1.05
	if dist <= want * 1.1:
		_set_aim_dir(_dir_to(b.position, pin))
		return
	# walk the corridor (tee -> fairway -> green) and aim at the point about `want` away
	var pts: Array = terrain.corridor
	var bp := Vector2(b.position.x, b.position.z)
	var best_i := 0
	var best_d := INF
	for i in pts.size():
		var d := bp.distance_to(pts[i])
		if d < best_d:
			best_d = d
			best_i = i
	# sample the corridor ahead of the ball every ~2 m
	var target := Vector2(pin.x, pin.z)
	var samples: Array = []
	for i in range(maxi(0, best_i), pts.size() - 1):
		var a: Vector2 = pts[i]
		var c: Vector2 = pts[i + 1]
		var steps := maxi(1, int(ceil(a.distance_to(c) / 2.0)))
		for s in steps:
			var p := a.lerp(c, float(s) / float(steps))
			if (p - bp).dot(target - bp) > 0.0:
				samples.append(p)
	samples.append(target)
	var k := samples.size() - 1
	for i in samples.size():
		if (samples[i] as Vector2).distance_to(bp) >= want:
			k = i
			break
	# lay up: if the landing (plus a little roll) would find water or OOB,
	# walk back along the corridor to the last dry landing spot
	layup_dist = 0.0
	if not _safe_landing(samples, k):
		for j in range(k - 1, -1, -1):
			var pj: Vector2 = samples[j]
			if pj.distance_to(bp) < 35.0:
				break
			if _safe_landing(samples, j):
				k = j
				layup_dist = pj.distance_to(bp)
				break
	target = samples[k]
	aim_target = Vector3(target.x, terrain.height(target.x, target.y), target.y)
	_set_aim_dir(_dir_to(b.position, aim_target))

## True if the corridor around sample i (8 m short for a mis-hit, ~16 m of roll
## past it) stays out of water/OOB.
func _safe_landing(samples: Array, i: int) -> bool:
	for j in range(maxi(0, i - 4), mini(i + 9, samples.size())):
		var p: Vector2 = samples[j]
		var s := terrain.surface(p.x, p.y)
		if s == CourseTerrain.Surface.WATER or s == CourseTerrain.Surface.OOB:
			return false
	return true

## Longest club that carries no further than the lay-up spot.
func _layup_club(d: float, lie: int) -> int:
	var max_club := 0 if lie == CourseTerrain.Surface.TEE else 1
	for i in range(max_club, Game.PUTTER_INDEX):
		if _club_carry_m(i, lie) <= d:
			return i
	return Game.SAND_WEDGE_INDEX

## Full (100%) carry of the current club from a perfect lie, including Zoomies.
## The meter is scaled to this; the lie penalty is shown separately so the
## player adjusts for it (and for wind) themselves.
func _meter_full_m() -> float:
	if _is_putter():
		return _putter_range
	var c: Dictionary = Game.CLUBS[club]
	var carry := float(c["carry"]) / Game.YARDS_PER_METER * float(_character()["power"])
	if special_armed and _special_id() == "zoomies":
		carry *= 1.12
	return carry

func _full_label() -> String:
	if _is_putter():
		return "%d yd putt" % int(round(Game.to_yards(_putter_range)))
	if special_armed and _special_id() == "pin_seeker":
		var b: Ball = balls[current]
		return "Pin Seeker (max %d yd)" % int(round(Game.to_yards(_club_carry_m(club, b.lie()) * 1.15)))
	return "%d yd" % int(round(Game.to_yards(_meter_full_m())))

func _update_meter_marks() -> void:
	var b: Ball = balls[current]
	var m := hud.meter
	var dist := _flat_dist(b.position, terrain.pin_pos3())
	if special_armed and _special_id() == "pin_seeker":
		m.set_target(-1.0, "")
	elif _is_putter():
		m.set_target(dist / _putter_range, "Pin %d ft" % int(round(dist * 3.28084)))
	else:
		m.set_target(dist / _meter_full_m(), "Pin %d yd" % int(round(Game.to_yards(dist))))
	var mods := _lie_mods(b.lie(), club)
	m.set_lie(String(mods["name"]), int(round(float(mods["dist"]) * 100.0)))

func _special_id() -> String:
	return String(_character().get("special_id", ""))

func _vs_par_text(i: int) -> String:
	var tot := 0
	var par := 0
	var holes := Course.holes()
	var scores: Array = Game.players[i]["scores"]
	for h in scores.size():
		tot += int(scores[h])
		par += int(holes[h]["par"])
	var d := tot - par
	if scores.is_empty():
		return "E"
	return "E" if d == 0 else ("+%d" % d if d > 0 else str(d))

func _refresh_player_hud() -> void:
	var p: Dictionary = Game.players[current]
	hud.set_player(p["name"], p["color"], strokes[current], _vs_par_text(current))
	if Game.mode == "match":
		hud.set_status_text("Match: %s" % Game.match_status()["text"])

func _refresh_club_hud() -> void:
	var b: Ball = balls[current]
	var c: Dictionary = Game.CLUBS[club]
	var lie := b.lie()
	var mods := _lie_mods(lie, club)
	var pin := terrain.pin_pos3()
	var dist_yd := Game.to_yards(_flat_dist(b.position, pin))
	var elev_ft := (pin.y - b.position.y) * 3.28084
	var elev_txt := "level"
	if elev_ft > 1.0:
		elev_txt = "%d ft uphill" % int(round(elev_ft))
	elif elev_ft < -1.0:
		elev_txt = "%d ft downhill" % int(round(-elev_ft))
	var info := "Full: %s\nLie: %s (%d%%)\nPin: %d yd, %s" % [_full_label(), mods["name"], int(round(float(mods["dist"]) * 100.0)), int(round(dist_yd)), elev_txt]
	var sp := ""
	var left := int(Game.players[current]["special_left"])
	var ch := _character()
	if _is_putter():
		sp = _putt_read_text()
	elif ch.get("passive", false):
		sp = "%s (passive) x%d left" % [ch["special"], left] if left > 0 else "%s used up" % ch["special"]
	elif special_armed:
		sp = "%s ARMED!" % String(ch["special"]).to_upper()
	elif left > 0:
		sp = "Special: %s x%d  [X / P]" % [ch["special"], left]
	hud.set_club("%s" % c["name"], info, sp)
	_update_meter_marks()
	hud.spin_ball.set_spin(spin, special_armed)

# ========================================================== shot maths ===
## Returns {putt: bool, v: Vector3, spin: Vector3, roll: float}
func _compute_shot(power: float, accuracy: float) -> Dictionary:
	var b: Ball = balls[current]
	var dir := _aim_dir()
	if _is_putter():
		var d := _putter_range * power
		return {"putt": true, "v": dir * sqrt(2.0 * GREEN_ROLL * d), "spin": Vector3.ZERO, "roll": 1.0}
	if special_armed and _special_id() == "pin_seeker":
		return _compute_pin_seeker(b)
	var c: Dictionary = Game.CLUBS[club]
	var ch := _character()
	var mods := _lie_mods(b.lie(), club)
	var carry := _club_carry_m(club, b.lie()) * power
	var zoomies := special_armed and _special_id() == "zoomies"
	if zoomies:
		carry *= 1.12
	var err := 0.0
	var pw := _perfect_window()
	if absf(accuracy) > pw:
		err = accuracy - signf(accuracy) * pw
	err *= float(mods["err"]) * (1.25 - 0.5 * float(ch["accuracy"]))
	if special_armed and _special_id() == "reflexes":
		err = 0.0 # insured perfect strike
	carry *= 1.0 - minf(0.25, 0.08 * absf(err))
	var bubble := special_armed and _special_id() == "bubble"
	if bubble:
		err = 0.0 # Dorothy's bubble flies dead straight
	var back_rpm: float = float(c["spin"]) * float(mods["spin"]) * (1.0 - 0.45 * spin.y)
	var side_rpm: float = -spin.x * 1300.0 + float(ch["natural_shape"]) * 1000.0 + err * 1500.0
	if bubble:
		side_rpm = 0.0
	var launch: float = float(c["launch"]) - spin.y * 1.5
	var key := "%d|%.3f|%.0f|%.2f" % [club, launch, back_rpm, carry]
	var speed := 0.0
	if _speed_cache.has(key):
		speed = _speed_cache[key]
	else:
		speed = Ball.solve_speed(carry, launch, back_rpm)
		_speed_cache[key] = speed
	dir = dir.rotated(Vector3.UP, deg_to_rad(err * 3.5))
	var la := deg_to_rad(launch)
	var v := (dir * cos(la) + Vector3.UP * sin(la)) * speed
	var right := dir.cross(Vector3.UP).normalized()
	var s := right * back_rpm * Ball.RPM + Vector3.UP * side_rpm * Ball.RPM
	var roll := 1.0
	if zoomies:
		roll *= 0.75
	if spin.y > 0.0:
		roll *= 1.0 - 0.3 * spin.y
	return {"putt": false, "v": v, "spin": s, "roll": roll, "bubble": bubble}

func _seek_target(b: Ball) -> Vector3:
	var pin := terrain.pin_pos3()
	var t := Vector2(pin.x, pin.z) + _seek_offset
	var from := Vector2(b.position.x, b.position.z)
	var reach := _club_carry_m(club, b.lie()) * 1.15
	if from.distance_to(t) > reach:
		t = from + (t - from).normalized() * reach
	return Vector3(t.x, terrain.height(t.x, t.y), t.y)

## Carlin's Pin Seeker: ignores wind and mis-hits, flies straight at a random
## spot close to the pin (within the club's reach) and sticks on landing.
## The launch speed is solved against the real terrain so elevation is handled.
func _compute_pin_seeker(b: Ball) -> Dictionary:
	var c: Dictionary = Game.CLUBS[club]
	var target := _seek_target(b)
	var dir := _dir_to(b.position, target)
	var want := _flat_dist(b.position, target)
	var launch: float = maxf(float(c["launch"]), 20.0)
	var back_rpm: float = float(c["spin"])
	var la := deg_to_rad(launch)
	var right := dir.cross(Vector3.UP).normalized()
	var s := right * back_rpm * Ball.RPM
	var carry_for := func(speed: float) -> float:
		var v := (dir * cos(la) + Vector3.UP * sin(la)) * speed
		var land := Ball.predict_carry(terrain, b.position, v, s, Vector3.ZERO, [], Ball.DT)
		return _flat_dist(b.position, land)
	# secant iterations starting from the flat-ground solution
	var s0 := Ball.solve_speed(want, launch, back_rpm)
	var s1 := s0 * 1.03
	var d0: float = carry_for.call(s0) - want
	var d1: float = carry_for.call(s1) - want
	for i in 6:
		if absf(d1) < 0.15 or absf(d1 - d0) < 0.0001:
			break
		var s2 := s1 - d1 * (s1 - s0) / (d1 - d0)
		s0 = s1
		d0 = d1
		s1 = clampf(s2, 2.0, 130.0)
		d1 = carry_for.call(s1) - want
	var v := (dir * cos(la) + Vector3.UP * sin(la)) * s1
	return {"putt": false, "v": v, "spin": s, "roll": 1.0, "seek": true}

func _update_prediction() -> void:
	_predict_dirty = false
	var b: Ball = balls[current]
	var mm := arc_dots.multimesh
	var n := mm.instance_count
	var hidden := Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3(0, -1000, 0))
	if _is_putter():
		landing_marker.visible = false
		var pin := terrain.pin_pos3()
		var length := minf(_putter_range, _flat_dist(b.position, pin) + 1.5)
		var dir := _aim_dir()
		for i in n:
			var t := float(i + 1) / float(n) * length
			if t > length * 0.6:
				mm.set_instance_transform(i, hidden)
				continue
			var p := b.position + dir * t
			p.y = terrain.height(p.x, p.z) + 0.05
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(0.5, 0.3, 0.5)), p))
		_predicted_land = b.position + dir * length
		return
	if special_armed and _special_id() == "pin_seeker":
		var tgt := _seek_target(b)
		_predicted_land = tgt
		landing_marker.visible = true
		landing_marker.position = tgt + Vector3(0, 0.08, 0)
		landing_marker.basis = _basis_from_up(terrain.normal_at(tgt.x, tgt.z))
		for i in n:
			mm.set_instance_transform(i, hidden)
		return
	var shot := _compute_shot(1.0, 0.0)
	var pts: Array = []
	var land := Ball.predict_carry(terrain, b.position, shot["v"], shot["spin"], Vector3.ZERO, pts)
	_predicted_land = land
	landing_marker.visible = true
	landing_marker.position = land + Vector3(0, 0.08, 0)
	var nrm := terrain.normal_at(land.x, land.z)
	landing_marker.basis = _basis_from_up(nrm)
	for i in n:
		if i < pts.size():
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pts[i]))
		else:
			mm.set_instance_transform(i, hidden)

static func _basis_from_up(up: Vector3) -> Basis:
	var x := up.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(up).normalized()
	return Basis(x, up, z)

# ============================================================== update ===
func _process(delta: float) -> void:
	_animate_flag(delta)
	match phase:
		Phase.INTRO:
			_intro_t += delta
			_update_intro_cam(_intro_t)
			if Input.is_action_just_pressed("swing"):
				_begin_turn()
		Phase.BANNER:
			if Input.is_action_just_pressed("swing"):
				hud.hide_banner()
				hud.meter.visible = true
				phase = Phase.AIM
		Phase.AIM:
			_process_aim(delta)
		Phase.SWING:
			_process_swing()
		Phase.CPU_THINK, Phase.CPU_SWING:
			_process_cpu(delta)
		Phase.FLIGHT:
			if Input.is_action_just_pressed("swing") and _pending.is_empty():
				_set_fast_forward(Engine.time_scale < FAST_FORWARD)
		Phase.RESULT:
			_result_timer -= delta
			if _result_timer <= 0.0 or (_result_timer < 1.2 and Input.is_action_just_pressed("swing")):
				_begin_turn()
		Phase.DONE:
			pass
	_update_minimap()
	hud.wind_dial.set_wind(wind, cam.global_rotation.y)

func _process_aim(delta: float) -> void:
	var b: Ball = balls[current]
	var axis := Input.get_axis("aim_left", "aim_right")
	if absf(axis) > 0.05:
		var spd := AIM_SPEED_PUTT if _is_putter() else AIM_SPEED
		aim_yaw -= axis * spd * delta
		golfer.stand_at(b.position, _aim_dir(), terrain)
		if not overview:
			cam.set_aim(b, _aim_dir(), _is_putter())
		_predict_dirty = true
		if slope_grid.visible:
			slope_grid.set_aim(b.position, _aim_dir(), _putt_length())
		if _is_putter():
			_refresh_club_hud()
	if Input.is_action_just_pressed("club_prev"):
		club = wrapi(club - 1, 0, Game.CLUBS.size())
		_on_club_changed()
	elif Input.is_action_just_pressed("club_next"):
		club = wrapi(club + 1, 0, Game.CLUBS.size())
		_on_club_changed()
	# spin / shot shape (not for putts)
	if not _is_putter():
		var sv := Vector2(Input.get_axis("spin_left", "spin_right"), Input.get_axis("spin_down", "spin_up"))
		if sv.length() > 0.1:
			spin = (spin + sv * delta * 1.6).limit_length(1.0)
			_predict_dirty = true
			_refresh_club_hud()
		if Input.is_action_just_pressed("spin_reset"):
			spin = Vector2.ZERO
			_predict_dirty = true
			_refresh_club_hud()
		if Input.is_action_just_pressed("special") and _character().get("passive", false):
			hud.show_message("%s is passive - it kicks in on its own" % _character()["special"], 1.6, Color(1, 0.85, 0.5))
		elif Input.is_action_just_pressed("special"):
			var left := int(Game.players[current]["special_left"])
			if special_armed:
				special_armed = false
			elif left > 0:
				special_armed = true
				var pin_dist := _flat_dist(b.position, terrain.pin_pos3())
				var radius := clampf(pin_dist * 0.02, 0.8, 3.5)
				_seek_offset = Vector2.from_angle(_rng.randf() * TAU) * radius * sqrt(_rng.randf_range(0.15, 1.0))
			hud.meter.reset(_full_label(), false, _perfect_window())
			_predict_dirty = true
			_refresh_club_hud()
	if Input.is_action_just_pressed("view"):
		overview = not overview
		if overview:
			cam.set_overview(_predicted_land if not _is_putter() else terrain.pin_pos3())
		else:
			cam.set_aim(b, _aim_dir(), _is_putter())
	var z := Input.get_action_strength("zoom_out") - Input.get_action_strength("zoom_in")
	if absf(z) > 0.05:
		cam.adjust_zoom(z * delta * 0.9)
	# hold for scorecard
	if Input.is_action_pressed("scorecard"):
		if not _showing_card:
			_showing_card = true
			hud.show_scorecard("Scorecard", "", hole_index, strokes)
	elif _showing_card:
		_showing_card = false
		hud.hide_scorecard()
	if _predict_dirty:
		_update_prediction()
		if overview:
			cam.set_overview(_predicted_land)
	_set_markers_visible(true)
	if _is_putter():
		landing_marker.visible = false
	if Input.is_action_just_pressed("swing") and not _showing_card:
		phase = Phase.SWING
		overview = false
		cam.set_aim(b, _aim_dir(), _is_putter())
		hud.meter.speed_scale = 0.45 if special_armed and _special_id() == "puppy_eyes" else 1.0
		hud.meter.start(_is_putter(), _perfect_window(), _full_label())
		hud.set_help("A/Space: set power, then hit the line     B/Backspace: cancel")

func _process_swing() -> void:
	var m := hud.meter
	if m.phase == SwingMeter.Phase.RISING or m.phase == SwingMeter.Phase.FALLING:
		golfer.set_backswing(m.value * (0.45 if _is_putter() else 1.0))
		if Input.is_action_just_pressed("cancel"):
			m.cancel()
			return
	if Input.is_action_just_pressed("swing"):
		m.press()

func _on_meter_cancelled() -> void:
	if phase != Phase.SWING:
		return
	golfer.idle()
	phase = Phase.AIM
	hud.meter.reset(_full_label(), _is_putter(), _perfect_window())
	hud.set_help("Swing cancelled - A / Space to try again")

func _on_meter_finished(power: float, accuracy: float) -> void:
	if phase != Phase.SWING and phase != Phase.CPU_SWING:
		return
	_pending = _compute_shot(power, accuracy)
	_pending["special"] = special_armed
	if special_armed:
		Game.players[current]["special_left"] = int(Game.players[current]["special_left"]) - 1
		hud.show_message("%s!" % String(_character()["special"]).to_upper(), 1.2, Color(1, 0.6, 0.9))
		_pending["special_id"] = _special_id()
	strokes[current] += 1
	_shot_from = (balls[current] as Ball).position
	_set_markers_visible(false)
	phase = Phase.FLIGHT
	golfer.start_downswing()
	hud.set_help("")

func _on_impact() -> void:
	if _pending.is_empty():
		return
	var b: Ball = balls[current]
	if _pending.get("special_id", "") == "zoomies":
		sfx_player.stream = Sfx.woof()
		sfx_player.play()
	if _pending["putt"]:
		var pv: Vector3 = _pending["v"]
		play_sfx(Sfx.putter(), linear_to_db(clampf(0.35 + pv.length() / 6.0, 0.35, 1.0)))
	elif club <= 1:
		play_sfx(Sfx.wood())
	else:
		play_sfx(Sfx.iron(), 0.0, 1.0 + 0.03 * (club - 2))
	if _pending["putt"]:
		b.putt(_pending["v"])
	elif _pending.get("seek", false):
		b.launch(_pending["v"], _pending["spin"], Vector3.ZERO, 1.0, true)
	elif _pending.get("bubble", false):
		b.launch(_pending["v"], _pending["spin"], Vector3.ZERO, _pending["roll"])
		b.set_bubble(true)
	else:
		b.launch(_pending["v"], _pending["spin"], wind, _pending["roll"])
	_pending = {}
	hud.meter.speed_scale = 1.0
	cam.set_follow(b, _aim_dir())
	if Game.is_cpu(current) and _cpu_ff:
		_set_fast_forward(true)
	hud.set_help("A / Space: fast forward")
	slope_grid.visible = slope_grid.visible and _is_putter()

func play_sfx(st: AudioStream, db: float = 0.0, pitch: float = 1.0) -> void:
	var ap: AudioStreamPlayer = _sfx_pool[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_pool.size()
	ap.stream = st
	ap.volume_db = db
	ap.pitch_scale = pitch
	ap.play()

## The gallery gasps when a shot finds trouble: water, out of bounds, a bunker,
## deep rough, or an approach that runs through the back of the green.
func _maybe_gasp(b: Ball, result: String) -> void:
	if _is_putter() or result == "holed":
		return
	var why := ""
	var lie := b.lie()
	if result == "water" or result == "oob":
		why = result
	elif lie == CourseTerrain.Surface.BUNKER:
		why = "bunker"
	elif lie == CourseTerrain.Surface.ROUGH and terrain.fairway_dist(b.position.x, b.position.z) > terrain.fw_hw + 10.0 \
			and Vector2(b.position.x, b.position.z).distance_to(terrain.green_c) > 30.0:
		why = "deep rough"
	elif lie != CourseTerrain.Surface.GREEN:
		var gc := Vector3(terrain.green_c.x, 0, terrain.green_c.y)
		var from := Vector3(_shot_from.x, 0, _shot_from.z)
		var to_g := gc.distance_to(from)
		var g_r := maxf(float(terrain.green["rx"]), float(terrain.green["rz"]))
		var along := (Vector3(b.position.x, 0, b.position.z) - from).dot((gc - from).normalized())
		if to_g > 25.0 and gc.distance_to(Vector3(b.position.x, 0, b.position.z)) < 40.0 and along > to_g + g_r * 0.5:
			why = "through the green"
	if why != "":
		play_sfx(Sfx.gasp(), -3.0, _rng.randf_range(0.94, 1.06))

## First touchdown: a subtle thud on grass, a soft "pff" in sand (water splashes elsewhere).
func _on_ball_landed(surface: int, speed: float) -> void:
	var loud := clampf(speed / 30.0, 0.25, 1.0)
	match surface:
		CourseTerrain.Surface.BUNKER, CourseTerrain.Surface.WASTE:
			play_sfx(Sfx.sand(), linear_to_db(loud * 0.7))
		CourseTerrain.Surface.WATER:
			pass
		_:
			play_sfx(Sfx.thud(), linear_to_db(loud * 0.55), _rng.randf_range(0.92, 1.08))

func _on_tree_hit(kind: String, solid: bool) -> void:
	if solid:
		# cactus is softer and pulpier than a trunk
		play_sfx(Sfx.wood_clunk(), 0.0 if kind != "cactus" else -4.0, 1.0 if kind == "pine" else (1.25 if kind == "palm" else 0.7))
	else:
		play_sfx(Sfx.rustle(), -2.0, _rng.randf_range(0.9, 1.1))
		if _rng.randf() < 0.6:
			play_sfx(Sfx.wood_clunk(), -9.0, 1.5)

## Dorothy's bubble bursts: splash sound + a ring of water droplets.
func _on_bubble_popped(pos: Vector3) -> void:
	play_sfx(Sfx.splash(), -3.0, 1.25)
	_spawn_splash(pos, Color(0.6, 0.88, 1.0))

func _spawn_splash(pos: Vector3, col: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col * 0.4
	var bm := BoxMesh.new()
	bm.size = Vector3(0.16, 0.16, 0.16)
	for i in 14:
		var d := MeshInstance3D.new()
		d.mesh = bm
		d.material_override = mat
		add_child(d)
		d.global_position = pos + Vector3(0, 0.1, 0)
		var ang := TAU * i / 14.0 + _rng.randf_range(-0.2, 0.2)
		var out := Vector3(cos(ang), 0, sin(ang)) * _rng.randf_range(0.8, 1.8)
		var up := _rng.randf_range(0.8, 1.8)
		var tw := d.create_tween()
		tw.set_parallel(true)
		tw.tween_property(d, "global_position", pos + out + Vector3(0, up, 0), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(d, "global_position:y", pos.y - 0.2, 0.3).set_delay(0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(d, "scale", Vector3.ONE * 0.2, 0.55)
		tw.chain().tween_callback(d.queue_free)

# ============================================================== results ===
func _on_ball_finished(result: String) -> void:
	var b: Ball = balls[current]
	_set_fast_forward(false)
	hud.set_help("A / Space: continue")
	phase = Phase.RESULT
	_result_timer = 2.6
	if _try_nine_lives(b, result):
		return
	_maybe_gasp(b, result)
	var par := int(hole["par"])
	var carried := Game.to_yards(_flat_dist(_shot_from, b.position))
	match result:
		"holed":
			play_sfx(Sfx.cup())
			holed[current] = true
			var nm := Game.score_name(strokes[current], par)
			hud.show_message(nm, 3.0, Color(1, 0.85, 0.2))
			golfer.celebrate()
			_result_timer = 3.2
		"water":
			strokes[current] += 1
			var splash := b.position
			play_sfx(Sfx.splash())
			_spawn_splash(Vector3(splash.x, maxf(splash.y, float(terrain.water_at(splash.x, splash.z).get("level", splash.y))), splash.z), Color(0.75, 0.9, 1.0))
			b.result = ""
			b.place(_water_drop(b))
			hud.show_message("Splash! +1 penalty stroke", 2.4, Color(0.5, 0.75, 1.0))
			golfer.sad()
			cam.set_manual(splash + Vector3(0, 9, 10), splash, 3.0)
		"oob":
			strokes[current] += 1
			b.place(_shot_from)
			hud.show_message("Out of bounds! +1 stroke", 2.4, Color(1, 0.5, 0.5))
			golfer.sad()
		_:
			var lie := b.lie()
			var pin := terrain.pin_pos3()
			var left_m := _flat_dist(b.position, pin)
			var text := ""
			var col := Color(1, 1, 1)
			match lie:
				CourseTerrain.Surface.GREEN:
					if _shot_from.distance_to(pin) < 40.0 and terrain.surface(_shot_from.x, _shot_from.z) == CourseTerrain.Surface.GREEN:
						text = "%d ft left" % int(round(left_m * 3.28084))
					else:
						text = "On the green!  %d yd" % int(round(carried))
						col = Color(0.6, 1, 0.6)
						golfer.celebrate()
				CourseTerrain.Surface.BUNKER:
					text = "In the bunker!"
					col = Color(1, 0.9, 0.6)
					golfer.sad()
				CourseTerrain.Surface.WASTE:
					text = "%d yd - Waste area" % int(round(carried))
					col = Color(1, 0.9, 0.7)
				CourseTerrain.Surface.ROUGH:
					text = "%d yd - %s" % [int(round(carried)), terrain.surf_info(lie)["name"]]
				CourseTerrain.Surface.FAIRWAY:
					text = "%d yd - Fairway" % int(round(carried))
					col = Color(0.7, 1, 0.7)
				CourseTerrain.Surface.FRINGE:
					text = "%d yd - Fringe" % int(round(carried))
				_:
					text = "%d yd" % int(round(carried))
			hud.show_message(text, 2.2, col)
	if not holed[current] and strokes[current] >= Game.MAX_STROKES_PER_HOLE:
		holed[current] = true
		b.visible = false
		hud.show_message("Picked up (max %d)" % Game.MAX_STROKES_PER_HOLE, 2.4, Color(1, 0.7, 0.4))
	if Game.mode == "match":
		_check_match_hole()
	_refresh_player_hud()

## Match play: once one side has holed out and the other can no longer tie,
## the hole is over - the other ball is picked up (scored as one more stroke).
func _check_match_hole() -> void:
	if balls.size() != 2:
		return
	for i in 2:
		var o := 1 - i
		if holed[i] and not holed[o] and strokes[o] >= strokes[i]:
			holed[o] = true
			strokes[o] = strokes[i] + 1
			(balls[o] as Ball).visible = false
			hud.show_message("%s wins the hole!" % Game.players[i]["name"], 2.6, Color(1, 0.85, 0.3))
			_result_timer = 2.8
			return

# ------------------------------------------------- Zero: Nine Lives ---
## Passive: if the ball finishes in sand or water, or clipped a tree, there's a
## chance it pops out onto a good lie (fairway/fringe) with a clear line to the pin.
## No penalty stroke. Limited saves per round.
func _try_nine_lives(b: Ball, result: String) -> bool:
	var ch := _character()
	if _special_id() != "nine_lives":
		return false
	var left := int(Game.players[current]["special_left"])
	if left <= 0 or result == "holed" or result == "oob":
		return false
	var trouble := result == "water" or b.hit_tree or b.lie() == CourseTerrain.Surface.BUNKER or b.lie() == CourseTerrain.Surface.WASTE
	if not trouble:
		return false
	if _rng.randf() > float(ch.get("special_chance", 0.5)):
		return false
	var from := b.position
	if result == "water":
		from = b.last_dry_pos.lerp(b.position, 0.5)
	var spot := _nine_lives_spot(from)
	if spot == Vector3.INF:
		return false
	Game.players[current]["special_left"] = left - 1
	b.result = ""
	b.visible = true
	_pop_ball(b, b.position if result != "water" else from, spot)
	hud.show_message("NINE LIVES! Zero lands on his feet", 2.6, Color(0.75, 0.6, 1.0))
	golfer.celebrate()
	_result_timer = 3.0
	_refresh_player_hud()
	return true

## Best nearby good lie: close to the pin, near where the ball ended up, with no
## water or trees on the line to the pin. Returns Vector3.INF if nothing suitable.
func _nine_lives_spot(from: Vector3) -> Vector3:
	var pin := terrain.pin_pos3()
	var start_d := _flat_dist(from, pin)
	var cands: Array = [] # [score, Vector3]
	for ring in range(1, 11):
		var r := ring * 3.5
		for k in 20:
			var a := TAU * k / 20.0
			var x := from.x + cos(a) * r
			var z := from.z + sin(a) * r
			var s := terrain.surface(x, z)
			if s != CourseTerrain.Surface.FAIRWAY and s != CourseTerrain.Surface.FRINGE:
				continue
			var p := Vector3(x, terrain.height(x, z), z)
			var d := _flat_dist(p, pin)
			if d > start_d + 12.0:
				continue # don't send him backwards much
			cands.append([d + r * 0.6, p])
	if cands.is_empty():
		return Vector3.INF
	cands.sort_custom(func(u: Array, v: Array) -> bool: return u[0] < v[0])
	# only trees anywhere near the area matter for the line checks
	var area := Rect2(Vector2(from.x, from.z), Vector2.ZERO).expand(Vector2(pin.x, pin.z)).grow(45.0)
	var near_trees: Array = []
	for t in terrain.trees:
		var tp: Vector3 = t["p"]
		if area.has_point(Vector2(tp.x, tp.z)):
			near_trees.append(t)
	# best-ranked spot with a clear line wins; blocked spots cost a 40 m penalty
	var best: Vector3 = cands[0][1]
	var best_score: float = float(cands[0][0]) + 40.0
	for c in cands:
		if float(c[0]) >= best_score:
			break
		if not _line_blocked(c[1], pin, near_trees):
			best = c[1]
			best_score = c[0]
			break
	return best

func _line_blocked(a: Vector3, b: Vector3, trees: Array) -> bool:
	var dist := _flat_dist(a, b)
	var steps := int(dist / 4.0)
	for i in range(1, steps):
		var p := a.lerp(b, float(i) / steps)
		if terrain.surface(p.x, p.z) == CourseTerrain.Surface.WATER:
			return true
		for t in trees:
			var tp: Vector3 = t["p"]
			if Vector2(p.x - tp.x, p.z - tp.z).length() < float(t["r"]) * 0.9:
				return true
	return false

## Hop the ball in an arc from `a` to `to`.
func _pop_ball(b: Ball, a: Vector3, to: Vector3) -> void:
	var apex := maxf(a.y, to.y) + 4.0 + a.distance_to(to) * 0.15
	var tw := create_tween()
	tw.tween_method(_pop_step.bind(b, a, to, apex), 0.0, 1.0, 0.9)
	tw.tween_callback(b.place.bind(to))
	var back := _dir_to(to, a) if _flat_dist(a, to) > 0.5 else Vector3.BACK
	cam.set_manual(to + back * 7.0 + Vector3(0, 4.5, 0), to, 2.5)

func _pop_step(t: float, b: Ball, a: Vector3, to: Vector3, apex: float) -> void:
	var p := a.lerp(to, t)
	p.y = lerpf(lerpf(a.y, apex, t), lerpf(apex, to.y, t), t) # quadratic arc
	b.position = p
	b._update_visual()

func _water_drop(b: Ball) -> Vector3:
	var from := b.last_dry_pos
	var back := _shot_from - from
	back.y = 0
	var dir := back.normalized() if back.length() > 0.1 else Vector3.BACK
	var p := from
	for i in 120:
		var s := terrain.surface(p.x, p.z)
		if s != CourseTerrain.Surface.WATER and s != CourseTerrain.Surface.OOB:
			var q := p + dir * 2.0
			if terrain.surface(q.x, q.z) != CourseTerrain.Surface.WATER:
				return q
		p += dir * 1.5
	return _shot_from

func _hole_finished() -> void:
	phase = Phase.DONE
	for i in balls.size():
		(Game.players[i]["scores"] as Array).append(strokes[i])
	var last := hole_index + 1 >= Course.hole_count()
	_set_markers_visible(false)
	hud.meter.visible = false
	hud.set_aim_ui_visible(false)
	if Game.mode == "match":
		var st := Game.match_status()
		var a := int(strokes[0])
		var bb := int(strokes[1])
		var hole_txt := "Hole %d halved" % (hole_index + 1)
		if a != bb:
			hole_txt = "%s wins hole %d" % [Game.players[0 if a < bb else 1]["name"], hole_index + 1]
		if st["decided"]:
			hud.show_scorecard("%s  -  %s" % [hole_txt, st["text"]], "Press A / Space to finish the match")
		else:
			hud.show_scorecard("%s  -  %s" % [hole_txt, st["text"]], "Press A / Space for hole %d" % (hole_index + 2))
	elif last:
		var best := 0
		for i in Game.players.size():
			if Game.total_strokes(i) < Game.total_strokes(best):
				best = i
		var title := "Final Scorecard"
		if Game.num_players > 1:
			title = "%s wins!" % Game.players[best]["name"]
		hud.show_scorecard(title, "Press A / Space to return to the menu")
	else:
		hud.show_scorecard("Hole %d complete" % (hole_index + 1), "Press A / Space for hole %d" % (hole_index + 2))
	var pin := terrain.pin_pos3()
	cam.set_manual(pin + Vector3(6, 4, 8), pin, 1.5)

func _on_continue() -> void:
	if phase == Phase.DONE:
		hud.hide_scorecard()
		hole_complete.emit()

func _set_fast_forward(on: bool) -> void:
	Engine.time_scale = FAST_FORWARD if on else 1.0
	hud.set_fast_forward(on, FAST_FORWARD)

func _exit_tree() -> void:
	Engine.time_scale = 1.0

## How far the current putt is meant to go (metres): to the hole, capped by the putter range.
func _putt_length() -> float:
	var b: Ball = balls[current]
	return clampf(minf(_flat_dist(b.position, terrain.pin_pos3()), _putter_range), 1.0, 40.0)

## e.g. "Uphill 1.2%  -  breaks left 0.8%"
func _putt_read_text() -> String:
	var b: Ball = balls[current]
	var length := minf(_flat_dist(b.position, terrain.pin_pos3()), _putter_range)
	var rd := slope_grid.read_putt(b.position, _aim_dir(), maxf(length, 0.5))
	var along := rd.x * 100.0
	var across := rd.y * 100.0
	var a_txt := "Flat"
	if along > 0.2:
		a_txt = "Uphill %.1f%%" % along
	elif along < -0.2:
		a_txt = "Downhill %.1f%%" % -along
	var c_txt := "straight"
	if across > 0.2:
		c_txt = "breaks left %.1f%%" % across
	elif across < -0.2:
		c_txt = "breaks right %.1f%%" % -across
	return "%s - %s" % [a_txt, c_txt]

# ============================================================ cosmetics ===
func _update_intro_cam(t: float) -> void:
	var tee := Vector3(terrain.tee.x, terrain.height(terrain.tee.x, terrain.tee.y), terrain.tee.y)
	var pin := terrain.pin_pos3()
	var k := clampf(t / 5.0, 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	var along := _dir_to(tee, pin)
	var start := pin + along * 18.0 + Vector3.UP * 22.0
	var finish := tee - along * 7.0 + Vector3.UP * 4.0
	var look_a := pin
	var look_b := tee + along * 40.0
	cam.set_manual(start.lerp(finish, k), look_a.lerp(look_b, k), 6.0)

func _animate_flag(delta: float) -> void:
	if flag_pivot == null:
		return
	var yaw := atan2(-wind.z, wind.x)
	var flutter := sin(Time.get_ticks_msec() * 0.008) * (0.1 + wind.length() * 0.03)
	flag_pivot.rotation.y = lerp_angle(flag_pivot.rotation.y, yaw + flutter, minf(1.0, delta * 4.0))

func _update_minimap() -> void:
	var list: Array = []
	for i in balls.size():
		var bi: Ball = balls[i]
		if not bi.visible:
			continue
		list.append({"p": bi.position, "c": Game.players[i]["color"], "active": i == current})
	var b: Ball = balls[current]
	hud.minimap.update_state(list, b.position, _predicted_land, phase == Phase.AIM or phase == Phase.SWING)
