class_name Hud
extends CanvasLayer
## In-round HUD: hole/player info, club + lie panel, wind dial, spin ball,
## minimap, swing meter, messages, turn banner, scorecard and pause menu.
## Sized for 1280x800 (Steam Deck) with large, outlined text.

signal quit_to_menu
signal continue_pressed

var meter: SwingMeter
var wind_dial: WindDial
var spin_ball: SpinBall
var minimap: MiniMap

var _hole_label: Label
var _player_label: Label
var _score_label: Label
var _club_label: Label
var _info_label: Label
var _special_label: Label
var _message: Label
var _banner: Label
var _help: Label
var _ff_label: Label
var _scorecard: PanelContainer
var _scorecard_grid: GridContainer
var _scorecard_title: Label
var _scorecard_hint: Label
var _pause: PanelContainer
var _pause_title: Label
var _pause_main: VBoxContainer
var _pause_confirm: VBoxContainer
var _quit_btn: Button
var _no_btn: Button
var _resume_btn: Button
var _msg_time := 0.0
var _paused_allowed := true

func _init() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- top left: hole + player
	var tl := _panel(root, Vector2(16, 16), Vector2(380, 0))
	var tlv := VBoxContainer.new()
	tl.add_child(tlv)
	_hole_label = _label(tlv, 28)
	_player_label = _label(tlv, 24)
	_score_label = _label(tlv, 20)

	# --- top right: wind
	wind_dial = WindDial.new()
	root.add_child(wind_dial)
	_place(wind_dial, Control.PRESET_TOP_RIGHT, Rect2(-206, 16, 190, 120))

	# --- right: minimap
	minimap = MiniMap.new()
	root.add_child(minimap)
	_place(minimap, Control.PRESET_TOP_RIGHT, Rect2(-206, 146, 190, 330))

	# --- bottom left: club, lie, distances
	var bl := _panel(root, Vector2(16, 0), Vector2(330, 0))
	_place(bl, Control.PRESET_BOTTOM_LEFT, Rect2(16, -262, 330, 10))
	var blv := VBoxContainer.new()
	bl.add_child(blv)
	_club_label = _label(blv, 32)
	_info_label = _label(blv, 21)
	_special_label = _label(blv, 19)
	_special_label.modulate = Color(1, 0.85, 0.4)

	spin_ball = SpinBall.new()
	root.add_child(spin_ball)
	_place(spin_ball, Control.PRESET_BOTTOM_RIGHT, Rect2(-126, -262, 110, 130))

	var hint := Label.new()
	hint.text = "Menu / Esc\nPause / Quit"
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_constant_override("outline_size", 5)
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint)
	_place(hint, Control.PRESET_BOTTOM_RIGHT, Rect2(-136, -122, 130, 44))

	# --- bottom centre: swing meter
	meter = SwingMeter.new()
	root.add_child(meter)
	meter.process_mode = Node.PROCESS_MODE_PAUSABLE
	_place(meter, Control.PRESET_CENTER_BOTTOM, Rect2(-280, -152, 760, 120))

	# --- help line
	_help = _label(root, 17)
	_place(_help, Control.PRESET_BOTTOM_WIDE, Rect2(0, -28, 0, 24))
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help.modulate = Color(1, 1, 1, 0.85)

	# --- centre message + banner
	_message = _label(root, 44)
	_place(_message, Control.PRESET_CENTER_TOP, Rect2(-500, 96, 1000, 80))
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.visible = false

	_banner = _label(root, 40)
	_place(_banner, Control.PRESET_CENTER, Rect2(-520, -110, 1040, 220))
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.05, 0.1, 0.2, 0.85)
	bsb.set_corner_radius_all(14)
	bsb.set_content_margin_all(20)
	_banner.add_theme_stylebox_override("normal", bsb)
	_banner.visible = false

	_ff_label = _label(root, 30)
	_place(_ff_label, Control.PRESET_CENTER_TOP, Rect2(-120, 96, 240, 44))
	_ff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ff_label.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	_ff_label.visible = false

	_build_scorecard(root)
	_build_pause(root)

# ------------------------------------------------------------ helpers ---
## Anchor a control to a preset and set its offsets (rect is relative to the anchor).
func _place(c: Control, preset: int, r: Rect2) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = r.position.x
	c.offset_top = r.position.y
	c.offset_right = r.end.x
	c.offset_bottom = r.end.y

func _panel(parent: Control, pos: Vector2, min_size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.5)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	p.position = pos
	p.custom_minimum_size = min_size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p

func _label(parent: Control, font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_constant_override("outline_size", maxi(4, font_size / 5))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

# ------------------------------------------------------------- setters ---
func set_hole(index: int, hole: Dictionary, terrain: CourseTerrain) -> void:
	var yd := int(round(Game.to_yards(Course.hole_length_m(hole))))
	_hole_label.text = "Hole %d  -  Par %d  -  %d yd" % [index + 1, int(hole["par"]), yd]
	minimap.setup(terrain)

func set_player(pname: String, color: Color, strokes: int, total_text: String) -> void:
	_player_label.text = "%s   Stroke %d" % [pname, strokes + 1]
	_player_label.add_theme_color_override("font_color", color.lightened(0.3))
	_score_label.text = "Round: %s" % total_text

func set_status_text(t: String) -> void:
	_score_label.text = t

func set_club(club_text: String, info_text: String, special_text: String) -> void:
	_club_label.text = club_text
	_info_label.text = info_text
	_special_label.text = special_text

func set_help(t: String) -> void:
	_help.text = t

func show_message(t: String, duration: float = 2.0, color: Color = Color(1, 1, 1)) -> void:
	_message.text = t
	_message.add_theme_color_override("font_color", color)
	_message.visible = true
	_msg_time = duration

func show_banner(t: String) -> void:
	_banner.text = t
	_banner.visible = true

func hide_banner() -> void:
	_banner.visible = false

func set_fast_forward(on: bool, speed: float) -> void:
	_ff_label.text = ">> x%d" % int(speed)
	_ff_label.visible = on
	if on:
		_help.text = "A / Space: normal speed"
	elif _help.text == "A / Space: normal speed":
		_help.text = "A / Space: fast forward"

func set_aim_ui_visible(v: bool) -> void:
	spin_ball.visible = v

func _process(delta: float) -> void:
	if _msg_time > 0.0:
		_msg_time -= delta
		if _msg_time <= 0.0:
			_message.visible = false

# ----------------------------------------------------------- scorecard ---
func _build_scorecard(root: Control) -> void:
	_scorecard = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.96, 0.95, 0.88)
	sb.border_color = Color(0.2, 0.45, 0.2)
	sb.set_border_width_all(6)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(24)
	_scorecard.add_theme_stylebox_override("panel", sb)
	_scorecard.custom_minimum_size = Vector2(980, 0)
	root.add_child(_scorecard)
	_place(_scorecard, Control.PRESET_CENTER, Rect2(-490, -330, 980, 10))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	_scorecard.add_child(v)
	_scorecard_title = Label.new()
	_scorecard_title.add_theme_font_size_override("font_size", 30)
	_scorecard_title.add_theme_color_override("font_color", Color(0.15, 0.35, 0.15))
	_scorecard_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_scorecard_title)
	_scorecard_grid = GridContainer.new()
	_scorecard_grid.add_theme_constant_override("h_separation", 12)
	_scorecard_grid.add_theme_constant_override("v_separation", 3)
	v.add_child(_scorecard_grid)
	_scorecard_hint = Label.new()
	_scorecard_hint.add_theme_font_size_override("font_size", 22)
	_scorecard_hint.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3))
	_scorecard_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_scorecard_hint)
	_scorecard.visible = false

func _cell(t: String, bold: bool = false, color: Color = Color(0.1, 0.1, 0.1)) -> void:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 21 if bold else 20)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(44, 0)
	_scorecard_grid.add_child(l)

## live_strokes: strokes for the hole in progress (or -1 entries when unknown)
## Laid out like a real card: front nine + OUT, then back nine + IN + TOT.
func show_scorecard(title: String, hint: String, live_hole: int = -1, live_strokes: Array = []) -> void:
	for c in _scorecard_grid.get_children():
		_scorecard_grid.remove_child(c)
		c.queue_free()
	var holes := Course.holes()
	var nine := 9
	var blocks := int(ceil(holes.size() / float(nine)))
	var multi := blocks > 1
	# columns: name | 9 holes | OUT/IN | TOT | +/-
	_scorecard_grid.columns = 1 + nine + (1 if multi else 0) + 2
	var match_mode := Game.mode == "match" and Game.players.size() == 2
	# per-player per-hole scores (finished holes + the live one)
	var sc: Array = []
	for pi in Game.players.size():
		var row: Array = []
		var scores: Array = Game.players[pi]["scores"]
		for i in holes.size():
			var v := -1
			if i < scores.size():
				v = int(scores[i])
			elif i == live_hole and pi < live_strokes.size() and int(live_strokes[pi]) > 0:
				v = int(live_strokes[pi])
			row.append(v)
		sc.append(row)
	var green := Color(0.15, 0.35, 0.15)
	for bk in blocks:
		var h0 := bk * nine
		var h1 := mini(h0 + nine, holes.size())
		var last := bk == blocks - 1
		var sub_name := ("OUT" if bk == 0 else "IN") if multi else ""
		# header
		_cell("", true)
		for i in range(h0, h0 + nine):
			_cell(str(i + 1) if i < h1 else "", true, green)
		if multi:
			_cell(sub_name, true, green)
		_cell("Tot" if last else "", true, green)
		_cell("+/-" if last else "", true, green)
		# par
		_cell("Par", true)
		var par_sub := 0
		for i in range(h0, h0 + nine):
			if i < h1:
				_cell(str(holes[i]["par"]))
				par_sub += int(holes[i]["par"])
			else:
				_cell("")
		if multi:
			_cell(str(par_sub), true)
		_cell(str(Course.par_total()) if last else "", true)
		_cell("")
		# players
		for pi in Game.players.size():
			var p: Dictionary = Game.players[pi]
			_cell(p["name"], true, (p["color"] as Color).darkened(0.35))
			var sub := 0
			for i in range(h0, h0 + nine):
				var s: int = sc[pi][i] if i < h1 else -1
				if s > 0:
					sub += s
					var diff := s - int(holes[i]["par"])
					var col := Color(0.1, 0.1, 0.1)
					if diff < 0:
						col = Color(0.8, 0.1, 0.1)
					elif diff > 0:
						col = Color(0.1, 0.2, 0.7)
					_cell(str(s), false, col)
				else:
					_cell("-" if i < h1 else "")
			if multi:
				_cell(str(sub) if sub > 0 else "-", true)
			if last:
				var tot := 0
				var par_played := 0
				for i in holes.size():
					if sc[pi][i] > 0:
						tot += sc[pi][i]
						par_played += int(holes[i]["par"])
				_cell(str(tot), true)
				_cell(_vs_par(tot - par_played), true)
			else:
				_cell("")
				_cell("")
		if match_mode:
			# running match score from player 1's side: +n = n up, AS = all square
			_cell("Match", true, Color(0.35, 0.2, 0.5))
			var a: Array = Game.players[0]["scores"]
			var b: Array = Game.players[1]["scores"]
			for i in range(h0, h0 + nine):
				if i < h1 and i < a.size() and i < b.size():
					var up := 0
					for k in i + 1:
						up += signi(int(b[k]) - int(a[k]))
					_cell("AS" if up == 0 else ("+%d" % up if up > 0 else str(up)), true, Color(0.1, 0.45, 0.15) if up > 0 else (Color(0.7, 0.1, 0.1) if up < 0 else Color(0.2, 0.2, 0.2)))
				else:
					_cell("")
			if multi:
				_cell("")
			_cell("")
			_cell("")
	_scorecard_title.text = "%s  -  %s" % [Course.info()["name"], title]
	_scorecard_hint.text = hint
	_scorecard.visible = true

func hide_scorecard() -> void:
	_scorecard.visible = false

func scorecard_visible() -> bool:
	return _scorecard.visible

static func _vs_par(d: int) -> String:
	if d == 0:
		return "E"
	return "+%d" % d if d > 0 else str(d)

# --------------------------------------------------------------- pause ---
func _build_pause(root: Control) -> void:
	_pause = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.1, 0.2, 0.92)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(30)
	_pause.add_theme_stylebox_override("panel", sb)
	_pause.custom_minimum_size = Vector2(400, 0)
	root.add_child(_pause)
	_place(_pause, Control.PRESET_CENTER, Rect2(-200, -150, 400, 10))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	_pause.add_child(v)
	_pause_title = _label(v, 40)
	_pause_title.text = "Paused"
	_pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_main = VBoxContainer.new()
	_pause_main.add_theme_constant_override("separation", 16)
	v.add_child(_pause_main)
	_resume_btn = _button(_pause_main, "Resume")
	_resume_btn.pressed.connect(toggle_pause)
	_quit_btn = _button(_pause_main, "Quit to Main Menu")
	_quit_btn.pressed.connect(_ask_quit)
	# confirmation step so a stray press doesn't throw the round away
	_pause_confirm = VBoxContainer.new()
	_pause_confirm.add_theme_constant_override("separation", 16)
	v.add_child(_pause_confirm)
	var warn := _label(_pause_confirm, 22)
	warn.text = "Leave this round?\nScores won't be saved\nto the leaderboard."
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var yes := _button(_pause_confirm, "Yes, quit")
	yes.pressed.connect(_on_quit_pressed)
	_no_btn = _button(_pause_confirm, "No, keep playing")
	_no_btn.pressed.connect(_cancel_quit)
	_pause_confirm.visible = false
	_pause.visible = false

func _ask_quit() -> void:
	_pause_main.visible = false
	_pause_confirm.visible = true
	_pause_title.text = "Quit?"
	_no_btn.grab_focus()

func _cancel_quit() -> void:
	_pause_confirm.visible = false
	_pause_main.visible = true
	_pause_title.text = "Paused"
	_quit_btn.grab_focus()

func _on_quit_pressed() -> void:
	get_tree().paused = false
	_pause.visible = false
	quit_to_menu.emit()

func _button(parent: Control, t: String) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(0, 56)
	b.add_theme_font_size_override("font_size", 28)
	parent.add_child(b)
	return b

func toggle_pause() -> void:
	var p := not get_tree().paused
	get_tree().paused = p
	_pause.visible = p
	_pause_confirm.visible = false
	_pause_main.visible = true
	_pause_title.text = "Paused"
	if p:
		_resume_btn.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if _pause.visible and _pause_confirm.visible and event.is_action_pressed("cancel"):
		_cancel_quit()
		get_viewport().set_input_as_handled()
	elif _pause.visible and event.is_action_pressed("cancel"):
		toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause") and not _scorecard.visible:
		toggle_pause()
		get_viewport().set_input_as_handled()
	elif _scorecard.visible and event.is_action_pressed("swing"):
		get_viewport().set_input_as_handled()
		continue_pressed.emit()


# ===================================================== inner widgets ===
class WindDial extends Control:
	## Top-down windsock: the sock streams downwind (screen up = away from the
	## camera). It grows longer and straighter with wind speed and droops/flutters
	## when calm.
	var wind := Vector3.ZERO
	var cam_yaw := 0.0
	const ORANGE := Color(1.0, 0.45, 0.1)
	const WHITE := Color(0.97, 0.97, 0.97)

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.5))
		var c := Vector2(52, size.y * 0.5 + 4)
		draw_circle(c, 44, Color(0.2, 0.42, 0.2))
		draw_arc(c, 44, 0, TAU, 32, Color(1, 1, 1, 0.5), 2.0)
		# small "you are here" chevron at the bottom of the dial (camera side)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, 36), c + Vector2(-6, 44), c + Vector2(6, 44)]), Color(1, 1, 1, 0.6))
		var spd := Vector2(wind.x, wind.z).length()
		var k := clampf(spd / 8.0, 0.0, 1.0)
		var dir := Vector2(0, 1)
		if spd > 0.05:
			# project world wind onto the camera's right/forward so "up" = blowing away from you
			var right := Vector2(cos(cam_yaw), -sin(cam_yaw))
			var fwd := Vector2(-sin(cam_yaw), -cos(cam_yaw))
			var w2 := Vector2(wind.x, wind.z)
			dir = Vector2(w2.dot(right), -w2.dot(fwd)).normalized()
		var side := Vector2(-dir.y, dir.x)
		var t := Time.get_ticks_msec() / 1000.0
		var length := 16.0 + 22.0 * k
		var mouth := 9.0
		var tip := 9.0 * (0.35 + 0.35 * k)
		var segs := 5
		var flutter := 1.5 + 3.0 * (1.0 - k)
		var prev_a := c + side * mouth
		var prev_b := c - side * mouth
		for i in segs:
			var f := float(i + 1) / segs
			var wob := sin(t * (6.0 + 6.0 * k) - f * 4.0) * flutter * f
			var center := c + dir * length * f + side * wob
			var half := lerpf(mouth, tip, f)
			var a := center + side * half
			var b := center - side * half
			draw_colored_polygon(PackedVector2Array([prev_a, a, b, prev_b]), ORANGE if i % 2 == 0 else WHITE)
			prev_a = a
			prev_b = b
		# pole (seen from above) with its ring
		draw_circle(c, 5, Color(0.25, 0.25, 0.28))
		draw_arc(c, 5, 0, TAU, 12, Color(0.9, 0.9, 0.9), 1.5)
		# text
		var mph := int(round(spd * Game.MPH_PER_MPS))
		draw_string(font, Vector2(104, 30), "WIND", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.9, 1))
		draw_string_outline(font, Vector2(104, 64), "%d mph" % mph, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 5, Color(0, 0, 0))
		draw_string(font, Vector2(104, 64), "%d mph" % mph, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1))
		draw_string(font, Vector2(104, 90), _describe(dir, mph), HORIZONTAL_ALIGNMENT_LEFT, 84, 15, Color(1, 0.85, 0.5))
		# strength bars
		for i in 5:
			var on := k * 5.0 > float(i) + 0.2
			draw_rect(Rect2(104 + i * 14, 100, 10, 8), ORANGE if on else Color(1, 1, 1, 0.2))

	func _describe(dir: Vector2, mph: int) -> String:
		if mph <= 1:
			return "Calm"
		if dir.y < -0.7:
			return "Helping"
		if dir.y > 0.7:
			return "Into you"
		return "From left" if dir.x > 0.0 else "From right"

	func set_wind(w: Vector3, yaw: float) -> void:
		wind = w
		cam_yaw = yaw
		queue_redraw()


class SpinBall extends Control:
	var spin := Vector2.ZERO  # x: + fade (right) / - draw (left); y: + top / - back
	var special := false

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.5))
		var c := Vector2(size.x * 0.5, 58)
		draw_circle(c, 40, Color(1, 1, 1))
		draw_arc(c, 40, 0, TAU, 24, Color(0.2, 0.2, 0.2), 2.0)
		draw_line(c - Vector2(40, 0), c + Vector2(40, 0), Color(0.75, 0.75, 0.75), 1.0)
		draw_line(c - Vector2(0, 40), c + Vector2(0, 40), Color(0.75, 0.75, 0.75), 1.0)
		var dot := c + Vector2(spin.x, -spin.y) * 30.0
		draw_circle(dot, 9, Color(1, 0.3, 0.6) if special else Color(0.9, 0.15, 0.15))
		var txt := _shape_text()
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string(font, Vector2((size.x - w) * 0.5, 120), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1))

	func _shape_text() -> String:
		var parts: Array = []
		if spin.x < -0.15:
			parts.append("Draw")
		elif spin.x > 0.15:
			parts.append("Fade")
		if spin.y > 0.15:
			parts.append("Top")
		elif spin.y < -0.15:
			parts.append("Back")
		if parts.is_empty():
			return "Straight"
		return " + ".join(PackedStringArray(parts))

	func set_spin(s: Vector2, sp: bool) -> void:
		spin = s
		special = sp
		queue_redraw()


class MiniMap extends Control:
	var terrain: CourseTerrain
	var balls: Array = []        # [{p: Vector3, c: Color, active: bool}]
	var aim_from := Vector3.ZERO
	var aim_to := Vector3.ZERO
	var show_aim := false
	var _scale := 1.0
	var _origin := Vector2.ZERO
	var _rect := Rect2()

	func setup(t: CourseTerrain) -> void:
		terrain = t
		var r := t.bounds.grow(-6.0)
		_rect = r
		var sx := (size.x - 16) / r.size.x
		var sy := (size.y - 16) / r.size.y
		_scale = minf(sx, sy)
		var used := r.size * _scale
		_origin = (size - used) * 0.5
		queue_redraw()

	func _to_map(x: float, z: float) -> Vector2:
		return _origin + Vector2(x - _rect.position.x, z - _rect.position.y) * _scale

	func _ellipse(e: Dictionary, grow: float, col: Color) -> void:
		var c: Vector2 = e["c"]
		var pts := PackedVector2Array()
		for i in 20:
			var a := TAU * i / 20.0
			pts.append(_to_map(c.x + cos(a) * float(e["rx"]) * grow, c.y + sin(a) * float(e["rz"]) * grow))
		draw_colored_polygon(pts, col)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.5))
		if terrain == null:
			return
		var tl := _to_map(_rect.position.x, _rect.position.y)
		var br := _to_map(_rect.end.x, _rect.end.y)
		var th: Dictionary = terrain.theme
		draw_rect(Rect2(tl, br - tl), (th["rough"] as Color).darkened(0.15))
		for wa in terrain.wastes:
			_ellipse(wa, 0.95, th["waste"])
		var fw := PackedVector2Array()
		for p in terrain.fairway:
			fw.append(_to_map(p.x, p.y))
		var fw_col: Color = th["fairway_a"]
		for w in terrain.waters:
			var wc: Color = th["water"]
			wc.a = 1.0
			_ellipse(w, 0.93, wc)
		for isl in terrain.islands:
			_ellipse(isl, 0.92, (th["rough"] as Color).darkened(0.15))
		if fw.size() >= 2:
			draw_polyline(fw, fw_col, terrain.fw_hw * 2.0 * _scale)
			for p in fw:
				draw_circle(p, terrain.fw_hw * _scale, fw_col)
		# water over the fairway (creeks / channels) stays visible
		for w in terrain.waters:
			var wc2: Color = th["water"]
			wc2.a = 0.85
			_ellipse(w, 0.93, wc2)
		for isl in terrain.islands:
			_ellipse(isl, 0.92, (th["rough"] as Color).darkened(0.15))
		_ellipse(terrain.green, 1.2, th["fringe"])
		_ellipse(terrain.green, 1.0, th["green_a"])
		for b in terrain.bunkers:
			_ellipse(b, 0.92, th["bunker"])
		for rk in terrain.rocks:
			var rp: Vector3 = rk["p"]
			draw_circle(_to_map(rp.x, rp.z), maxf(2.0, float(rk["r"]) * _scale), Color(0.45, 0.4, 0.36))
		for t in terrain.trees:
			var tp: Vector3 = t["p"]
			if _rect.has_point(Vector2(tp.x, tp.z)):
				draw_circle(_to_map(tp.x, tp.z), maxf(1.5, float(t["r"]) * _scale), Color(0.1, 0.3, 0.12) if t.get("kind", "pine") != "cactus" else Color(0.2, 0.42, 0.22))
		var tee := _to_map(terrain.tee.x, terrain.tee.y)
		draw_rect(Rect2(tee - Vector2(4, 6), Vector2(8, 12)), Color(0.5, 0.8, 0.35))
		var pin := _to_map(terrain.pin.x, terrain.pin.y)
		draw_line(pin, pin - Vector2(0, 14), Color(1, 1, 1), 2.0)
		draw_colored_polygon(PackedVector2Array([pin - Vector2(0, 14), pin - Vector2(-9, 10), pin - Vector2(0, 6)]), Color(1, 0.2, 0.2))
		if show_aim:
			var a := _to_map(aim_from.x, aim_from.z)
			var b := _to_map(aim_to.x, aim_to.z)
			draw_dashed_line(a, b, Color(1, 1, 0.4), 2.0, 5.0)
			draw_arc(b, 5, 0, TAU, 12, Color(1, 1, 0.4), 2.0)
		for bd in balls:
			var bp: Vector3 = bd["p"]
			var m := _to_map(bp.x, bp.z)
			var col: Color = bd["c"]
			draw_circle(m, 6.0 if bd["active"] else 4.5, Color(0, 0, 0))
			draw_circle(m, 4.5 if bd["active"] else 3.2, col)

	func update_state(b: Array, from: Vector3, to: Vector3, aim: bool) -> void:
		balls = b
		aim_from = from
		aim_to = to
		show_aim = aim
		queue_redraw()
