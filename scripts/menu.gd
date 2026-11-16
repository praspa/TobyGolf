class_name MainMenu
extends Control
## Title screen. Navigable with dpad / left stick / arrow keys; A / Enter selects.

signal start_round(players: int, characters: Array, course: int)
signal start_match(character: String, opponent: String, course: int)

var _players := 1
var _players_btn: Button
var _controls: PanelContainer
var _start_btn: Button
var _main_box: VBoxContainer
var _course_box: VBoxContainer
var _course_preview: Hud.MiniMap
var _course_terrains: Dictionary = {}   # course index -> CourseTerrain of hole 1 (for previews)
var _course := 0
var _char_box: VBoxContainer
var _chars: Array = ["toby", "carlin", "onezy", "zero"]  # pick per player (defaults)
var _bg: _Backdrop
var _info: Label
var _lb_panel: PanelContainer
var _match_btn: Button
var _challenge_box: VBoxContainer
var _challenge_char_btn: Button
var _opponent := ""            # set while picking a course for a match
var _result_panel: PanelContainer
var _grid_box: VBoxContainer
var _grid_title: Label
var _grid: GridContainer
var _grid_player := 0            # which player is choosing
var _grid_from := "main"         # "main" or "challenge": where Back returns to
var _grid_hint: Label
const GRID_HINT := "A / Enter: choose     B / Backspace: back"
var _result_label: Label
var _result_ok: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_chars[0] = "toby"
	var bg := _Backdrop.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_bg = bg

	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 20)
	_info.add_theme_constant_override("outline_size", 6)
	_info.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.set_anchors_preset(Control.PRESET_CENTER)
	_info.offset_left = -560
	_info.offset_right = -60
	_info.offset_top = 200
	_info.offset_bottom = 390
	add_child(_info)

	var title := Label.new()
	title.text = "TOBY GOLF"
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", Color(1, 0.95, 0.4))
	title.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0.3))
	title.add_theme_constant_override("outline_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -500
	title.offset_right = 500
	title.offset_top = 40
	title.offset_bottom = 160
	add_child(title)

	var sub := Label.new()
	sub.text = "%d courses of chunky golf" % Course.course_count()
	sub.add_theme_font_size_override("font_size", 28)
	sub.add_theme_constant_override("outline_size", 8)
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub.offset_left = -500
	sub.offset_right = 500
	sub.offset_top = 160
	sub.offset_bottom = 200
	add_child(sub)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = 60
	box.offset_right = 520
	box.offset_top = -175
	box.offset_bottom = 380
	add_child(box)
	_main_box = box

	_start_btn = _button(box, "Stroke Play")
	_start_btn.pressed.connect(func() -> void:
		_opponent = ""
		_open_course_select())
	_match_btn = _button(box, "Match Play Challenge")
	_match_btn.pressed.connect(_open_challenge)
	_match_btn.focus_entered.connect(_show_challenge_teaser)
	_players_btn = _button(box, "")
	_players_btn.pressed.connect(_cycle_players.bind(1))
	_char_box = VBoxContainer.new()
	_char_box.add_theme_constant_override("separation", 8)
	box.add_child(_char_box)
	_update_players()
	_start_btn.focus_entered.connect(_show_leaderboard)
	_players_btn.focus_entered.connect(_show_leaderboard)
	var ctl_btn := _button(box, "Controls")
	ctl_btn.focus_entered.connect(_show_leaderboard)
	ctl_btn.pressed.connect(func() -> void: _controls.visible = not _controls.visible)
	var quit_btn := _button(box, "Quit")
	quit_btn.pressed.connect(func() -> void: get_tree().quit())
	quit_btn.focus_entered.connect(_show_leaderboard)
	_build_leaderboard()

	_controls = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.1, 0.2, 0.92)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(18)
	_controls.add_theme_stylebox_override("panel", sb)
	_controls.set_anchors_preset(Control.PRESET_CENTER)
	_controls.offset_left = -600
	_controls.offset_right = 20
	_controls.offset_top = -150
	_controls.offset_bottom = 330
	var cl := Label.new()
	cl.add_theme_font_size_override("font_size", 19)
	cl.text = """CONTROLS            Steam Deck / Gamepad      Keyboard
Aim                 Left stick / D-pad        Left/Right or A/D
Club                LB / RB, D-pad up/down    Up/Down or W/S
Swing (3 clicks)    A                         Space / Enter
Cancel swing        B                         Backspace / X
Spin & shape        Right stick               I J K L  (U resets)
Special shot        X                         P
Overview camera     Y                         V / C
Zoom                RT / LT                   Z / Q
Scorecard (hold)    View (Back)               Tab
Pause               Menu (Start)              Esc

Swing: 1) start  2) set POWER  3) stop on the white line.
Early on click 3 pulls left, late pushes right.
Putting is power only - read the green grid (dots drift downhill)."""
	_controls.add_child(cl)
	_controls.visible = false
	add_child(_controls)

	_build_course_select()
	_build_challenge()
	_build_grid()
	_build_result_popup()
	_start_btn.grab_focus()
	_show_leaderboard()
	if Game.last_match_result != "":
		_show_result(Game.last_match_result)
		Game.last_match_result = ""

# ---------------------------------------------------------- course select ---
func _build_course_select() -> void:
	_course_box = VBoxContainer.new()
	_course_box.add_theme_constant_override("separation", 14)
	_course_box.set_anchors_preset(Control.PRESET_CENTER)
	_course_box.offset_left = 60
	_course_box.offset_right = 560
	_course_box.offset_top = -175
	_course_box.offset_bottom = 380
	add_child(_course_box)
	var title := Label.new()
	title.text = "Choose a course"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_course_box.add_child(title)
	for i in Course.course_count():
		var c: Dictionary = Course.courses()[i]
		var b := _button(_course_box, "%s   -   %d holes, par %d" % [c["name"], Course.hole_count(i), Course.par_total(i)])
		b.custom_minimum_size = Vector2(0, 62)
		b.add_theme_font_size_override("font_size", 24)
		b.pressed.connect(_start_on_course.bind(i))
		b.focus_entered.connect(_show_course.bind(i))
	var back := _button(_course_box, "Back")
	back.pressed.connect(_close_course_select)
	_course_preview = Hud.MiniMap.new()
	_course_preview.set_anchors_preset(Control.PRESET_CENTER)
	_course_preview.offset_left = -470
	_course_preview.offset_right = -270
	_course_preview.offset_top = -120
	_course_preview.offset_bottom = 190
	add_child(_course_preview)
	_course_box.visible = false
	_course_preview.visible = false

func _open_course_select() -> void:
	_main_box.visible = false
	_controls.visible = false
	_course_box.visible = true
	_course_preview.visible = true
	(_course_box.get_child(1 + _course) as Button).grab_focus()
	_show_course(_course)

func _close_course_select() -> void:
	_course_box.visible = false
	_course_preview.visible = false
	if _opponent != "":
		_open_challenge()
		return
	_main_box.visible = true
	_start_btn.grab_focus()
	_show_leaderboard()

func _show_course(i: int) -> void:
	_course = i
	_lb_panel.visible = false
	_info.visible = true
	var c: Dictionary = Course.courses()[i]
	_bg.character = ""
	_bg.theme_name = c["theme"]
	_bg.queue_redraw()
	var hole1: Dictionary = Course.holes(i)[0]
	_info.text = "%s\n%s\nHole 1: %s, par %d" % [c["name"], c["blurb"], hole1["name"], int(hole1["par"])]
	if not _course_terrains.has(i):
		_course_terrains[i] = CourseTerrain.new(hole1, Course.THEMES[c["theme"]])
	_course_preview.setup(_course_terrains[i])
	_course_preview.update_state([], Vector3.ZERO, Vector3.ZERO, false)

func _start_on_course(i: int) -> void:
	if _opponent != "":
		start_match.emit(_chars[0], _opponent, i)
	else:
		start_round.emit(_players, _chars.slice(0, _players), i)

func _button(parent: Control, t: String) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(0, 54)
	b.add_theme_font_size_override("font_size", 28)
	parent.add_child(b)
	return b

func _cycle_players(d: int) -> void:
	_players = wrapi(_players + d, 1, 5)
	_update_players()

func _update_players() -> void:
	_players_btn.text = "Players: %d  %s" % [_players, "(pass & play)" if _players > 1 else ""]
	# one character picker per player
	for c in _char_box.get_children():
		_char_box.remove_child(c)
		c.queue_free()
	for i in _players:
		var b := _button(_char_box, "")
		b.custom_minimum_size = Vector2(0, 46)
		b.add_theme_font_size_override("font_size", 24)
		b.set_meta("player", i)
		b.pressed.connect(_open_grid.bind(i, "main"))
		b.focus_entered.connect(_show_char.bind(i))
		_update_char_button(i)

func _char_button(i: int) -> Button:
	return _char_box.get_child(i) as Button

func _update_char_button(i: int) -> void:
	var ch: Dictionary = Game.CHARACTERS[_chars[i]]
	_char_button(i).text = "P%d:  %s" % [i + 1, ch["name"]] if _players > 1 else "Character:  %s" % ch["name"]

func _show_char(i: int) -> void:
	_show_char_id(_chars[i])

func _show_char_id(id: String) -> void:
	_lb_panel.visible = false
	_info.visible = true
	var ch: Dictionary = Game.CHARACTERS[id]
	_bg.character = id
	_bg.queue_redraw()
	_info.text = "%s\n%s\nPower %d%%   Accuracy %d%%   Shape: %s\nSpecial: %s (%s) x%d per round" % [
		ch["name"], ch["blurb"],
		int(round(float(ch["power"]) * 100.0)), int(round(float(ch["accuracy"]) * 100.0)),
		"draw" if float(ch["natural_shape"]) > 0.05 else ("fade" if float(ch["natural_shape"]) < -0.05 else "straight"),
		ch["special"], ch["special_desc"], int(ch["special_uses"])]

# ------------------------------------------------------ character grid ---
const GRID_COLS := 4

## Order on the grid: the stock four, then the unlockables in unlock order.
static func _grid_ids() -> Array:
	var ids: Array = []
	for id in Game.CHARACTERS:
		if not Game.UNLOCK_ORDER.has(id):
			ids.append(id)
	ids.append_array(Game.UNLOCK_ORDER)
	return ids

func _build_grid() -> void:
	_grid_box = VBoxContainer.new()
	_grid_box.add_theme_constant_override("separation", 14)
	_grid_box.set_anchors_preset(Control.PRESET_CENTER)
	_grid_box.offset_left = 62
	_grid_box.offset_right = 632
	_grid_box.offset_top = -175
	_grid_box.offset_bottom = 380
	add_child(_grid_box)
	_grid_title = Label.new()
	_grid_title.add_theme_font_size_override("font_size", 32)
	_grid_title.add_theme_constant_override("outline_size", 8)
	_grid_title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_grid_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grid_box.add_child(_grid_title)
	_grid = GridContainer.new()
	_grid.columns = GRID_COLS
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_grid_box.add_child(_grid)
	for id in _grid_ids():
		var t := _CharTile.new()
		t.id = id
		t.menu = self
		t.pressed.connect(_pick_tile.bind(id))
		t.focus_entered.connect(_show_tile.bind(id))
		_grid.add_child(t)
	var hint := Label.new()
	_grid_hint = hint
	hint.text = GRID_HINT
	hint.add_theme_font_size_override("font_size", 19)
	hint.add_theme_constant_override("outline_size", 6)
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grid_box.add_child(hint)
	_grid_box.visible = false

func _open_grid(player: int, from: String) -> void:
	_grid_player = player
	_grid_from = from
	_main_box.visible = false
	_challenge_box.visible = false
	_controls.visible = false
	_lb_panel.visible = false
	_grid_title.text = ("Player %d: choose your golfer" % (player + 1)) if _players > 1 else "Choose your golfer"
	_grid_box.visible = true
	for t in _grid.get_children():
		(t as _CharTile).locked = not Game.is_unlocked((t as _CharTile).id)
		t.queue_redraw()
		if (t as _CharTile).id == _chars[player]:
			(t as Control).grab_focus()
	_show_tile(_chars[player])

func _close_grid() -> void:
	_grid_box.visible = false
	if _grid_from == "challenge":
		_challenge_box.visible = true
		_update_challenge_char()
		_challenge_char_btn.grab_focus()
	else:
		_main_box.visible = true
		_update_char_button(_grid_player)
		_char_button(_grid_player).grab_focus()

func _pick_tile(id: String) -> void:
	if not Game.is_unlocked(id):
		_grid_hint.text = "Locked - win them in Match Play Challenge!"
		_grid_hint.add_theme_color_override("font_color", Color(1, 0.55, 0.45))
		get_tree().create_timer(2.0).timeout.connect(func() -> void:
			if is_instance_valid(_grid_hint):
				_grid_hint.text = GRID_HINT
				_grid_hint.remove_theme_color_override("font_color"))
		return
	_chars[_grid_player] = id
	_close_grid()

func _show_tile(id: String) -> void:
	if Game.is_unlocked(id):
		_show_char_id(id)
		return
	_lb_panel.visible = false
	_info.visible = true
	_bg.character = ""
	_bg.queue_redraw()
	var hint := "Beat them in Match Play Challenge to unlock."
	if id != Game.next_challenger():
		var idx := Game.UNLOCK_ORDER.find(id)
		hint = "Unlock %s first, then beat this one in Match Play Challenge." % Game.CHARACTERS[Game.UNLOCK_ORDER[idx - 1]]["name"] if idx > 0 else hint
	_info.text = "???\nA mystery golfer.\n%s" % hint

## One square on the character grid: pixel portrait + name, black "??" silhouette when locked,
## and P1-P4 tags for whoever has picked it.
class _CharTile extends Button:
	var id := ""
	var locked := false
	var menu: Control
	const PX := 6.0

	func _init() -> void:
		custom_minimum_size = Vector2(126, 142)
		focus_mode = Control.FOCUS_ALL
		flat = true

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var focused := has_focus()
		draw_rect(r, Color(0.06, 0.1, 0.22, 0.9) if not locked else Color(0.05, 0.05, 0.07, 0.9))
		if focused:
			draw_rect(r, Color(1, 0.85, 0.25), false, 5.0)
		else:
			draw_rect(r, Color(1, 1, 1, 0.25), false, 2.0)
		var face: Array = _Backdrop.face_for(id)
		var pal: Dictionary = _Backdrop.palette_for(id)
		var origin := Vector2((size.x - 16.0 * PX) * 0.5, 8)
		for y in face.size():
			var row: String = face[y]
			for x in row.length():
				var col: Color = pal.get(row[x], Color(0, 0, 0, 0))
				if col.a <= 0.0:
					continue
				if locked:
					col = Color(0.0, 0.0, 0.0)
				draw_rect(Rect2(origin + Vector2(x, y) * PX, Vector2(PX, PX)), col)
		var font := ThemeDB.fallback_font
		if locked:
			var q := "??"
			var qw := font.get_string_size(q, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
			draw_string_outline(font, Vector2((size.x - qw) * 0.5, origin.y + 8.0 * PX + 14), q, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, 6, Color(0.6, 0.6, 0.7))
			draw_string(font, Vector2((size.x - qw) * 0.5, origin.y + 8.0 * PX + 14), q, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(0.1, 0.1, 0.12))
		var nm: String = "???" if locked else String(Game.CHARACTERS[id]["name"])
		var fs := 19
		var nw := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2((size.x - nw) * 0.5, size.y - 10), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.95, 0.5) if focused else Color(1, 1, 1))
		# who has picked this golfer
		if menu and not locked:
			var tags: Array = []
			var chars: Array = menu.get("_chars")
			for p in int(menu.get("_players")):
				if chars[p] == id:
					tags.append("P%d" % (p + 1))
			for k in tags.size():
				var tr := Rect2(Vector2(4 + k * 34, 4), Vector2(32, 22))
				draw_rect(tr, Game.PLAYER_COLORS[int(String(tags[k]).substr(1)) - 1])
				draw_string(font, tr.position + Vector2(4, 17), tags[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.05, 0.05, 0.1))

	func _notification(what: int) -> void:
		if what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT:
			queue_redraw()

# ------------------------------------------------------- match challenge ---
func _build_challenge() -> void:
	_challenge_box = VBoxContainer.new()
	_challenge_box.add_theme_constant_override("separation", 12)
	_challenge_box.set_anchors_preset(Control.PRESET_CENTER)
	_challenge_box.offset_left = 60
	_challenge_box.offset_right = 600
	_challenge_box.offset_top = -175
	_challenge_box.offset_bottom = 380
	add_child(_challenge_box)
	var title := Label.new()
	title.text = "Match Play Challenge"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_challenge_box.add_child(title)
	var sub_l := Label.new()
	sub_l.text = "Beat a challenger over 18 holes of match play\nto unlock them for good. One at a time!"
	sub_l.add_theme_font_size_override("font_size", 19)
	sub_l.add_theme_constant_override("outline_size", 6)
	sub_l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	sub_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_challenge_box.add_child(sub_l)
	_challenge_char_btn = _button(_challenge_box, "")
	_challenge_char_btn.custom_minimum_size = Vector2(0, 46)
	_challenge_char_btn.add_theme_font_size_override("font_size", 24)
	_challenge_char_btn.pressed.connect(_open_grid.bind(0, "challenge"))
	_challenge_char_btn.focus_entered.connect(func() -> void: _show_char(0))
	for id in Game.UNLOCK_ORDER:
		var b := _button(_challenge_box, "")
		b.custom_minimum_size = Vector2(0, 58)
		b.add_theme_font_size_override("font_size", 23)
		b.set_meta("opponent", id)
		b.pressed.connect(_pick_opponent.bind(id))
		b.focus_entered.connect(_show_opponent.bind(id))
	var back := _button(_challenge_box, "Back")
	back.pressed.connect(_close_challenge)
	back.focus_entered.connect(func() -> void: _show_opponent(Game.next_challenger()))
	_challenge_box.visible = false

func _update_challenge_char() -> void:
	_challenge_char_btn.text = "You play as:  %s" % Game.CHARACTERS[_chars[0]]["name"]
	if _char_box.get_child_count() > 0:
		_update_char_button(0)

func _refresh_challengers() -> void:
	var avail := Game.available_challengers()
	for c in _challenge_box.get_children():
		if not (c is Button) or not c.has_meta("opponent"):
			continue
		var id: String = c.get_meta("opponent")
		var ch: Dictionary = Game.CHARACTERS[id]
		var lvl: String = Game.CPU_SKILL[id]["label"]
		var b := c as Button
		if Game.is_unlocked(id):
			b.text = "%s  -  %s  -  Unlocked (rematch)" % [ch["name"], lvl]
			b.disabled = false
		elif avail.has(id):
			b.text = "%s  -  %s  -  CHALLENGE!" % [ch["name"], lvl]
			b.disabled = false
		else:
			var idx := Game.UNLOCK_ORDER.find(id)
			b.text = "???  -  %s  -  Beat %s first" % [lvl, Game.CHARACTERS[Game.UNLOCK_ORDER[idx - 1]]["name"]]
			b.disabled = true

func _open_challenge() -> void:
	_main_box.visible = false
	_controls.visible = false
	_course_box.visible = false
	_course_preview.visible = false
	_lb_panel.visible = false
	_challenge_box.visible = true
	_players = 1
	_update_players()
	_update_challenge_char()
	_refresh_challengers()
	var focus_id := _opponent if _opponent != "" else Game.next_challenger()
	if focus_id == "":
		focus_id = Game.UNLOCK_ORDER[Game.UNLOCK_ORDER.size() - 1]
	for c in _challenge_box.get_children():
		if c is Button and c.has_meta("opponent") and c.get_meta("opponent") == focus_id:
			(c as Button).grab_focus()
	_show_opponent(focus_id)

func _close_challenge() -> void:
	_opponent = ""
	_challenge_box.visible = false
	_main_box.visible = true
	_match_btn.grab_focus()
	_show_leaderboard()

func _pick_opponent(id: String) -> void:
	_opponent = id
	_challenge_box.visible = false
	_open_course_select()

func _show_opponent(id: String) -> void:
	if id == "":
		return
	_lb_panel.visible = false
	_info.visible = true
	var ch: Dictionary = Game.CHARACTERS[id]
	var sk: Dictionary = Game.CPU_SKILL[id]
	if Game.is_unlocked(id) or Game.available_challengers().has(id):
		_bg.character = id
		_info.text = "%s  -  %s\n%s\nPower %d%%   Accuracy %d%%\nSpecial: %s (%s)" % [
			ch["name"], sk["label"], ch["blurb"],
			int(round(float(ch["power"]) * 100.0)), int(round(float(ch["accuracy"]) * 100.0)),
			ch["special"], ch["special_desc"]]
	else:
		_bg.character = ""
		_info.text = "A mystery challenger awaits...\nDifficulty: %s" % sk["label"]
	_bg.queue_redraw()

## Main-menu teaser on the Match Play button: who's next.
func _show_challenge_teaser() -> void:
	var nxt := Game.next_challenger()
	if nxt == "":
		_show_leaderboard()
		return
	_show_opponent(nxt)
	_info.text = "Next challenger: %s (%s)\nBeat them in match play to unlock them!\n%d of %d challengers unlocked" % [
		Game.CHARACTERS[nxt]["name"], Game.CPU_SKILL[nxt]["label"],
		Game.UNLOCK_ORDER.size() - Game.UNLOCK_ORDER.filter(func(x): return not Game.is_unlocked(x)).size(), Game.UNLOCK_ORDER.size()]

# ------------------------------------------------------------ result popup ---
func _build_result_popup() -> void:
	_result_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.2, 0.96)
	sb.border_color = Color(1, 0.85, 0.3)
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(28)
	_result_panel.add_theme_stylebox_override("panel", sb)
	_result_panel.set_anchors_preset(Control.PRESET_CENTER)
	_result_panel.offset_left = -330
	_result_panel.offset_right = 330
	_result_panel.offset_top = -150
	_result_panel.offset_bottom = -140
	add_child(_result_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 20)
	_result_panel.add_child(v)
	var l := Label.new()
	_result_label = l
	l.add_theme_font_size_override("font_size", 28)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(l)
	var ok := _button(v, "OK")
	_result_ok = ok
	ok.pressed.connect(func() -> void:
		_result_panel.visible = false
		_match_btn.grab_focus())
	_result_panel.visible = false

func _show_result(t: String) -> void:
	_result_label.text = t
	_result_panel.visible = true
	_result_ok.grab_focus()

# ------------------------------------------------------------- leaderboard ---
func _build_leaderboard() -> void:
	_lb_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.1, 0.2, 0.86)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(16)
	_lb_panel.add_theme_stylebox_override("panel", sb)
	_lb_panel.set_anchors_preset(Control.PRESET_CENTER)
	_lb_panel.offset_left = -610
	_lb_panel.offset_right = 10
	_lb_panel.offset_top = -175
	_lb_panel.offset_bottom = -165   # grows to fit its rows
	add_child(_lb_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_lb_panel.add_child(v)
	var t := Label.new()
	t.text = "LEADERBOARD  -  Top 10 All Time"
	t.add_theme_font_size_override("font_size", 28)
	t.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var list := Leaderboard.entries()
	if list.is_empty():
		var e := Label.new()
		e.text = "\nNo rounds yet.\nFinish all 18 holes of any course\nto get your name on the board!"
		e.add_theme_font_size_override("font_size", 22)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(e)
		return
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	for hdr in ["#", "Player", "Score", "Course", "Date"]:
		_lb_cell(grid, hdr, Color(0.65, 0.8, 1.0), 18)
	for i in list.size():
		var e: Dictionary = list[i]
		var fresh := Leaderboard.last_added.has(i)
		var col := Color(1, 0.95, 0.4) if fresh else Color(1, 1, 1)
		var cid := String(e.get("character", ""))
		var cname: String = Game.CHARACTERS[cid]["name"] if Game.CHARACTERS.has(cid) else cid
		var who := String(e.get("name", cname))
		if not who.begins_with(cname):
			who = "%s (%s)" % [who, cname]
		var d := int(e["strokes"]) - int(e["par"])
		var vs := "E" if d == 0 else ("+%d" % d if d > 0 else str(d))
		_lb_cell(grid, ("%d" % (i + 1)) + ("*" if fresh else ""), col, 21)
		_lb_cell(grid, who, col, 21)
		_lb_cell(grid, "%d (%s)" % [int(e["strokes"]), vs], col, 21)
		_lb_cell(grid, String(e.get("course", "")), col, 19)
		_lb_cell(grid, String(e.get("date", "")), Color(col, 0.75), 17)
	if not Leaderboard.last_added.is_empty():
		var nb := Label.new()
		nb.text = "* New entry from your last round!"
		nb.add_theme_font_size_override("font_size", 18)
		nb.add_theme_color_override("font_color", Color(1, 0.95, 0.4))
		v.add_child(nb)

func _lb_cell(grid: GridContainer, text: String, col: Color, fs: int) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	grid.add_child(l)

func _show_leaderboard() -> void:
	if _lb_panel == null:
		return
	_lb_panel.visible = true
	_info.visible = false
	_bg.character = ""
	_bg.queue_redraw()

func _flash_info(t: String) -> void:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	l.offset_left = -300
	l.offset_right = 300
	l.offset_top = -70
	l.offset_bottom = -30
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)
	get_tree().create_timer(2.0).timeout.connect(l.queue_free)

func _unhandled_input(event: InputEvent) -> void:
	if _result_panel.visible:
		return
	if _grid_box.visible:
		if event.is_action_pressed("cancel") or event.is_action_pressed("ui_cancel"):
			_close_grid()
			get_viewport().set_input_as_handled()
		return
	if _challenge_box.visible:
		if event.is_action_pressed("cancel") or event.is_action_pressed("ui_cancel"):
			_close_challenge()
			get_viewport().set_input_as_handled()
		return
	if _course_box.visible:
		if event.is_action_pressed("cancel") or event.is_action_pressed("ui_cancel"):
			_close_course_select()
			get_viewport().set_input_as_handled()
		return
	if _players_btn.has_focus():
		if event.is_action_pressed("ui_left"):
			_cycle_players(-1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_right"):
			_cycle_players(1)
			get_viewport().set_input_as_handled()
	if event.is_action_pressed("cancel") and _controls.visible:
		_controls.visible = false


## Sky gradient, rolling hills and a big pixel-art portrait of the selected character.
class _Backdrop extends Control:
	var character := "toby"
	var theme_name := "parkland"
	const CARLIN_FACE := [
		"................",
		"...PPPPPPPPPP...",
		"..PPPPPPPPPPPPPP",
		"..GGGGGGGGGGGG..",
		".GGGWWGGGGWKGGG.",
		".GGGKWGGGGWWGGG.",
		"GGGGGGGGGGGGGGGG",
		"GGGGCCCKKCCCGGGG",
		"GGGGCCCCCCCCGGGG",
		"GGG.CCKKKKCC.GGG",
		"GGG..CCRRCC..GGG",
		".GG....RR....GG.",
		"..GGGGGGGGGGGG..",
		"...GGGGCCGGGG...",
		"..GGGGCCCCGGGG..",
		"..GGGGGGGGGGGG..",
	]
	const ONEZY_FACE := [
		"..G..........G..",
		".GNG........GNG.",
		".GGGGGGGGGGGGGG.",
		"GGGGGGGGGGGGGGGG",
		"GGKKGGGGGGGGKKGG",
		"GGOOKOGGGGOKOOGG",
		"LGOOKOGGGGOKOOGL",
		"LLGGGGGNNGGGGGLL",
		"LLLGGGLLLLGGGLLL",
		".LLLLLLKKLLLLLL.",
		"..LLLLLLLLLLLL..",
		"..RRBBRRBBRRBB..",
		".RRRBBRRBBRRBBR.",
		".BBBBBBBBBBBBBB.",
		".RRRBBRRBBRRBBR.",
		".RRRBBRRBBRRBBR.",
	]
	const ZERO_FACE := [
		"..K..........K..",
		".KNK........KNK.",
		".KKKKKKKKKKKKKK.",
		"KKKKKKKKKKKKKKKK",
		"KWWWWWWWWWWWWWWK",
		"WWRRRRWWWWBBBBWW",
		"DWRRRRWKKWBBBBWD",
		"DDWWWWWNNWWWWWDD",
		"DDDKKKDDDDKKKDDD",
		".DDDDDDKKDDDDDD.",
		"..DDDDDDDDDDDD..",
		"..KKKKKKKKKKKK..",
		".KKKKKDDDDKKKKK.",
		".KKKKDDDDDDKKKK.",
		".KKKKDDDDDDKKKK.",
		".KKKKKKKKKKKKKK.",
	]
	const BACON_FACE := [
		"................",
		"..PP........PP..",
		".PPPWWWWWWWWPPP.",
		"..WWWWSSSSWWWW..",
		".WWWWWWSSWWWWWW.",
		".WFFFWWWWWWWWWW.",
		".WFKFWWWWWWKWWW.",
		"WWFFFWWWWWWWWWWW",
		"WWWWWWKKKKWWWWWW",
		"WSWWWWKKKKWWWWSW",
		"WSSWPPPPPPPPWSSW",
		".WSWPTPPPPTPWSW.",
		"..WWPPPPPPPPWW..",
		"...WWWWWWWWWW...",
		"....BBBDDBBB....",
		"...BBBBDDBBBB...",
	]
	const DOROTHY_FACE := [
		"....RRRRRRRR....",
		"...G........G...",
		"..G..........G..",
		".G............G.",
		".GBBBBBBBBBBBBG.",
		".GBBBOOOOBBBBBG.",
		".GBBOKOOOOBOOBG.",
		".GBBBOOOOOOOBBG.",
		".GBBBBOOOBBBOBG.",
		"..GBBNBBBBBBBG..",
		"...GSSNSSSSSG...",
		"..DDDDDDDDDDDD..",
		".MMMMMMMMMMMMMM.",
		".MMMDDDDDDDDMMM.",
		".MMMDrDyDgDDMMM.",
		".MMMDDDDDDDDMMM.",
	]
	const DEWEY_FACE := [
		"....WWWWWWWW....",
		"...WFWWWWWWFW...",
		".FFWWWWWWWWWWFF.",
		"FFFWWWWWWWWWWFFF",
		"FFWWKKKWWKKKWWFF",
		"FFWWKWKWWKWKWWFF",
		"FFWWKKKWWKKKWWFF",
		"FFFWWWWWWWWWWFFF",
		".FFWWWWNNWWWWFF.",
		".FFWWWWNNWWWWFF.",
		"..FWWWWPPWWWWF..",
		"...WWWWPPWWWW...",
		"....WWWWWWWW....",
		"..FFWWWWWWWWFF..",
		".FFFFWWWWWWFFFF.",
		".FFFFFWWWWFFFFF.",
	]
	const FACE := [
		"................",
		"................",
		"...##########...",
		".############...",
		".###TT####TT####",
		".###WW####WW####",
		".###WP####PW####",
		".####TTTTTT#####",
		".####TTNNTT#####",
		".####TTTTTT#####",
		".###.TTTTTT.###.",
		".###.......####.",
		"..##BBBBBBBB##..",
		"...BBBBBBBBBB...",
		"..BBBBBBBBBBBB..",
		"..BBBBBBBBBBBB..",
	]

	static func face_for(id: String) -> Array:
		var face: Array = FACE
		if id == "carlin":
			face = CARLIN_FACE
		elif id == "onezy":
			face = ONEZY_FACE
		elif id == "zero":
			face = ZERO_FACE
		elif id == "bacon":
			face = BACON_FACE
		elif id == "dorothy":
			face = DOROTHY_FACE
		elif id == "dewey":
			face = DEWEY_FACE
		return face

	static func palette_for(id: String) -> Dictionary:
		var palette: Dictionary = {
			"#": Color(0.09, 0.08, 0.08), "T": Color(0.78, 0.5, 0.25), "W": Color(1, 1, 1),
			"P": Color(0.05, 0.03, 0.02), "N": Color(0, 0, 0), "B": Color(0.55, 0.78, 0.95),
		}
		if id == "carlin":
			palette = {
				"G": Color(0.88, 0.63, 0.28), "C": Color(0.97, 0.87, 0.64), "P": Color(0.5, 0.25, 0.75),
				"W": Color(1, 1, 1), "K": Color(0.05, 0.03, 0.02), "R": Color(0.96, 0.45, 0.55),
			}
		if id == "onezy":
			palette = {
				"G": Color(0.6, 0.6, 0.65), "L": Color(0.82, 0.82, 0.85), "O": Color(0.95, 0.6, 0.15),
				"K": Color(0.05, 0.05, 0.06), "N": Color(0.95, 0.6, 0.65), "R": Color(0.78, 0.1, 0.1),
				"B": Color(0.08, 0.08, 0.08),
			}
		if id == "zero":
			palette = {
				"K": Color(0.1, 0.1, 0.12), "D": Color(0.26, 0.26, 0.3), "W": Color(0.97, 0.97, 0.95),
				"R": Color(0.9, 0.1, 0.12), "B": Color(0.15, 0.45, 1.0), "N": Color(0.95, 0.6, 0.65),
			}
		if id == "bacon":
			palette = {
				"W": Color(0.96, 0.95, 0.92), "S": Color(0.84, 0.82, 0.78), "P": Color(0.96, 0.75, 0.76),
				"F": Color(0.82, 0.6, 0.4), "K": Color(0.05, 0.05, 0.05), "T": Color(1, 1, 1),
				"B": Color(0.98, 0.5, 0.72), "D": Color(0.85, 0.35, 0.58),
			}
		if id == "dorothy":
			palette = {
				"R": Color(0.85, 0.95, 1.0), "G": Color(0.8, 0.92, 1.0), "B": Color(0.35, 0.62, 0.95),
				"O": Color(1.0, 0.5, 0.1), "K": Color(0.05, 0.03, 0.02), "N": Color(0.2, 0.7, 0.3),
				"S": Color(0.55, 0.5, 0.45), "D": Color(0.25, 0.27, 0.3), "M": Color(0.72, 0.76, 0.8),
				"r": Color(1, 0.25, 0.2), "y": Color(1, 0.85, 0.2), "g": Color(0.3, 1, 0.4),
			}
		if id == "dewey":
			palette = {
				"W": Color(0.98, 0.97, 0.95), "F": Color(0.88, 0.87, 0.84), "K": Color(0.05, 0.03, 0.02),
				"N": Color(0.05, 0.05, 0.05), "P": Color(0.96, 0.45, 0.55),
			}
		return palette

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var bands := 16
		var th: Dictionary = Course.THEMES.get(theme_name, Course.THEMES["parkland"])
		var sky_top: Color = th["sky_top"]
		var sky_hz: Color = th["sky_horizon"]
		for i in bands:
			var c := sky_top.lerp(sky_hz, float(i) / bands)
			draw_rect(Rect2(0, h * 0.6 * i / bands, w, h * 0.6 / bands + 1), c)
		var ground: Color = th["fairway_b"] if theme_name == "parkland" else th["rough"]
		draw_rect(Rect2(0, h * 0.6, w, h * 0.4), ground)
		for i in 7:
			var cx := w * (i / 6.0)
			var flat_top := theme_name == "desert"
			var peak := h * 0.45 + (i % 3) * 18
			var pts := PackedVector2Array([Vector2(cx - 220, h * 0.62), Vector2(cx - (90 if flat_top else 0), peak), Vector2(cx + (90 if flat_top else 0), peak), Vector2(cx + 220, h * 0.62)])
			draw_colored_polygon(pts, (th["hill_a"] as Color).lerp(th["hill_b"], (i % 2) * 0.5))
		for i in 10:
			draw_rect(Rect2(0, h * 0.62 + i * h * 0.04, w, h * 0.02), th["fairway_a"])
		# pixel Toby
		var px := 18.0
		var origin := Vector2(w * 0.5 - 16 * px - 120, h * 0.5 - 8 * px + 40)
		if character == "":
			return
		var face: Array = face_for(character)
		var palette: Dictionary = palette_for(character)
		for y in face.size():
			var row: String = face[y]
			for x in row.length():
				var col: Color = palette.get(row[x], Color(0, 0, 0, 0))
				if col.a > 0.0:
					draw_rect(Rect2(origin + Vector2(x, y) * px, Vector2(px, px)), col)
		# flag
		var fx := w * 0.47
		draw_rect(Rect2(fx, h * 0.38, 6, h * 0.25), Color(1, 1, 1))
		draw_colored_polygon(PackedVector2Array([Vector2(fx + 6, h * 0.38), Vector2(fx + 80, h * 0.41), Vector2(fx + 6, h * 0.44)]), Color(1, 0.25, 0.25))
