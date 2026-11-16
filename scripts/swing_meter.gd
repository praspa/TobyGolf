class_name SwingMeter
extends Control
## Classic three-click swing meter.
##   Click 1: start the swing - the cursor runs from the impact line toward 100%.
##   Click 2: lock POWER (cursor turns around).
##   Click 3: hit ACCURACY as the cursor passes back over the impact line.
## Early on click 3 = pull/hook (left), late = push/slice (right).
## Putter: click 2 strikes the putt (distance only).

signal power_set(power: float)
signal finished(power: float, accuracy: float)
signal cancelled

const ACC_ZONE := 0.15       # how far past the impact line the cursor travels (fraction of bar)
const RISE_TIME := 1.05      # seconds from 0 to 100%
const RETURN_TIME := 0.85    # seconds per 100% on the way back

enum Phase { IDLE, RISING, FALLING, RETURN, DONE }

var phase := Phase.IDLE
var value := 0.0
var power := 0.0
var accuracy := 0.0
var putter := false
var perfect_window := 0.3    # fraction of ACC_ZONE counted as perfect
var full_label := ""         # e.g. "150 yd"
var target_mark := -1.0      # suggested power for the distance to the pin (<0 = hidden)
var target_label := ""       # e.g. "132 yd"
var lie_name := ""           # e.g. "Rough" (empty = no lie badge)
var lie_pct := 100           # how much of a full shot the lie allows
var speed_scale := 1.0       # <1 slows the cursor (Dewey's Puppy Eyes)
var cpu_name := ""           # set while a CPU player is swinging
var _flash := 0.0
var _result_text := ""
var _font: Font

func _ready() -> void:
	_font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(760, 120)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func start(is_putter: bool, perfect: float, label: String) -> void:
	putter = is_putter
	perfect_window = perfect
	full_label = label
	phase = Phase.RISING
	value = 0.0
	power = 0.0
	accuracy = 0.0
	_result_text = ""
	visible = true

func reset(label: String, is_putter: bool, perfect: float) -> void:
	phase = Phase.IDLE
	value = 0.0
	putter = is_putter
	perfect_window = perfect
	full_label = label
	_result_text = ""

func is_active() -> bool:
	return phase == Phase.RISING or phase == Phase.FALLING or phase == Phase.RETURN

## Called by the round when the swing button is pressed while the meter runs.
func press() -> void:
	match phase:
		Phase.RISING, Phase.FALLING:
			power = clampf(value, 0.01, 1.0)
			_flash = 0.25
			power_set.emit(power)
			if putter:
				phase = Phase.DONE
				_result_text = "%d%%" % int(round(power * 100.0))
				finished.emit(power, 0.0)
			else:
				phase = Phase.RETURN
		Phase.RETURN:
			_finish_accuracy(value / ACC_ZONE)

func cancel() -> void:
	if phase == Phase.RISING or phase == Phase.FALLING:
		phase = Phase.IDLE
		value = 0.0
		cancelled.emit()

func _finish_accuracy(a: float) -> void:
	accuracy = clampf(a, -1.5, 1.5)
	phase = Phase.DONE
	_flash = 0.25
	if absf(accuracy) <= perfect_window:
		_result_text = "PERFECT!"
	elif accuracy > 0.0:
		_result_text = "Early - pulled left" if accuracy < 0.8 else "Way early - big hook!"
	else:
		_result_text = "Late - pushed right" if accuracy > -0.8 else "Way late - big slice!"
	finished.emit(power, accuracy)

## Suggested power mark: where 100% of the club would cover the distance to the pin.
## No wind/lie adjustment - that's the player's job.
func set_target(mark: float, label: String) -> void:
	target_mark = mark
	target_label = label
	queue_redraw()

func set_lie(lie: String, pct: int) -> void:
	lie_name = lie
	lie_pct = pct
	queue_redraw()

func _process(real_delta: float) -> void:
	_flash = maxf(0.0, _flash - real_delta)
	var delta := real_delta * speed_scale
	match phase:
		Phase.RISING:
			value += delta / RISE_TIME
			if value >= 1.0:
				value = 1.0
				phase = Phase.FALLING
		Phase.FALLING:
			value -= delta / RISE_TIME
			if value <= 0.0:
				phase = Phase.IDLE
				value = 0.0
				cancelled.emit()
		Phase.RETURN:
			value -= delta / RETURN_TIME
			if value < -ACC_ZONE:
				value = -ACC_ZONE
				_finish_accuracy(-1.5)
	queue_redraw()

# ----------------------------------------------------------------- drawing ---
func _bar_rect() -> Rect2:
	return Rect2(30, 44, size.x - 60, 50)

func _x_for(m: float) -> float:
	var r := _bar_rect()
	var m_min := -ACC_ZONE - 0.03
	return r.position.x + (m - m_min) / (1.0 - m_min) * r.size.x

func _draw() -> void:
	var r := _bar_rect()
	# panel
	draw_rect(Rect2(r.position - Vector2(14, 40), r.size + Vector2(28, 64)), Color(0, 0, 0, 0.55))
	draw_rect(r, Color(0.12, 0.12, 0.16))
	var x0 := _x_for(0.0)
	var x1 := _x_for(1.0)
	# power gradient background (dim)
	var slices := 24
	for i in slices:
		var a := float(i) / slices
		var col := _power_color(a)
		col.a = 0.28
		draw_rect(Rect2(lerpf(x0, x1, a), r.position.y, (x1 - x0) / slices + 1.0, r.size.y), col)
	# live fill up to the cursor / locked power
	var fill_to := value if phase == Phase.RISING or phase == Phase.FALLING else power
	if phase != Phase.IDLE and fill_to > 0.0:
		var n := int(ceil(fill_to * slices))
		for i in n:
			var a := float(i) / slices
			var b := minf(float(i + 1) / slices, fill_to)
			draw_rect(Rect2(lerpf(x0, x1, a), r.position.y + 4, lerpf(x0, x1, b) - lerpf(x0, x1, a) + 0.5, r.size.y - 8), _power_color(a))
	# accuracy zone
	if not putter:
		var za := _x_for(-ACC_ZONE)
		var zb := _x_for(ACC_ZONE)
		draw_rect(Rect2(za, r.position.y, zb - za, r.size.y), Color(1, 1, 1, 0.12))
		var pa := _x_for(-ACC_ZONE * perfect_window)
		var pb := _x_for(ACC_ZONE * perfect_window)
		draw_rect(Rect2(pa, r.position.y, pb - pa, r.size.y), Color(0.3, 1.0, 0.45, 0.45))
	# impact line
	draw_rect(Rect2(x0 - 2, r.position.y - 6, 4, r.size.y + 12), Color(1, 1, 1))
	# ticks
	for pct in [0.25, 0.5, 0.75, 1.0]:
		var tx := _x_for(pct)
		draw_line(Vector2(tx, r.end.y), Vector2(tx, r.end.y + 8), Color(1, 1, 1, 0.8), 2.0)
		var lbl := "%d%%" % int(pct * 100)
		var near_mark := target_mark > 0.0 and absf(tx - _x_for(minf(target_mark, 1.0))) < 58.0
		if not near_mark:
			draw_string(_font, Vector2(tx - 18, r.end.y + 24), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.85))
	# suggested power mark for the distance to the pin
	if target_mark > 0.0:
		_draw_target(r)
	# locked power marker
	if phase == Phase.RETURN or phase == Phase.DONE:
		var px := _x_for(power)
		draw_rect(Rect2(px - 3, r.position.y - 8, 6, r.size.y + 16), Color(1, 0.95, 0.3))
	# cursor
	if phase != Phase.IDLE:
		var cx := _x_for(value)
		draw_rect(Rect2(cx - 4, r.position.y - 12, 8, r.size.y + 24), Color(0, 0, 0))
		draw_rect(Rect2(cx - 2, r.position.y - 10, 4, r.size.y + 20), Color(1, 1, 1))
	if lie_name != "" and not putter:
		_draw_lie_badge(r)
	# labels
	var title := ""
	match phase:
		Phase.IDLE:
			title = "Press A / Space to swing" if cpu_name == "" else "%s is up..." % cpu_name
		Phase.RISING, Phase.FALLING:
			title = "Press to set POWER" if not putter else "Press to set PUTT STRENGTH"
			if cpu_name != "":
				title = "%s is swinging..." % cpu_name
		Phase.RETURN:
			title = "Hit the WHITE LINE for accuracy!" if cpu_name == "" else "%s is swinging..." % cpu_name
			if speed_scale < 1.0:
				title = "Puppy eyes... hit the WHITE LINE"
		Phase.DONE:
			title = _result_text
	var fs := 26
	var tcol := Color(1, 1, 1)
	if _flash > 0.0:
		tcol = Color(1, 1, 0.4)
	draw_string_outline(_font, Vector2(r.position.x, r.position.y - 12), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0))
	draw_string(_font, Vector2(r.position.x, r.position.y - 12), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tcol)
	var shown := power if phase == Phase.RETURN or phase == Phase.DONE else maxf(value, 0.0)
	var right := "100%% = %s" % full_label
	if phase != Phase.IDLE:
		right = "%d%%  (100%% = %s)" % [int(round(shown * 100.0)), full_label]
	var w := _font.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	draw_string_outline(_font, Vector2(r.end.x - w, r.position.y - 12), right, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 5, Color(0, 0, 0))
	draw_string(_font, Vector2(r.end.x - w, r.position.y - 12), right, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.9, 0.95, 1))

const MARK_COLOR := Color(0.35, 0.9, 1.0)

func _draw_target(r: Rect2) -> void:
	var over := target_mark > 1.0
	var mx := _x_for(minf(target_mark, 1.0))
	# dashed line through the bar
	var y := r.position.y
	while y < r.end.y:
		draw_line(Vector2(mx, y), Vector2(mx, minf(y + 6.0, r.end.y)), MARK_COLOR, 3.0)
		y += 10.0
	# flag-shaped pointer under the bar
	var tip := Vector2(mx, r.end.y + 1)
	var tri := PackedVector2Array([tip, tip + Vector2(-8, 12), tip + Vector2(8, 12)])
	draw_colored_polygon(tri, MARK_COLOR)
	var txt := target_label + (" >" if over else "")
	var fs := 17
	var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tx := clampf(mx - w * 0.5, r.position.x - 10, r.end.x + 10 - w)
	draw_string_outline(_font, Vector2(tx, r.end.y + 28), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0))
	draw_string(_font, Vector2(tx, r.end.y + 28), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, MARK_COLOR)

## Lie badge above the meter: how much of a full shot this lie lets you hit.
func _draw_lie_badge(r: Rect2) -> void:
	var col := Color(0.35, 0.85, 0.4)
	var txt := "LIE: %s  %d%%" % [lie_name.to_upper(), lie_pct]
	if lie_pct < 100:
		txt += "   (-%d%% distance)" % (100 - lie_pct)
		col = Color(1.0, 0.85, 0.25) if lie_pct >= 85 else Color(1.0, 0.45, 0.25)
	var fs := 20
	var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var box := Rect2(r.position.x - 14, r.position.y - 76, w + 24, 30)
	draw_rect(box, Color(0, 0, 0, 0.6))
	draw_rect(Rect2(box.position, Vector2(6, box.size.y)), col)
	draw_string(_font, Vector2(box.position.x + 14, box.position.y + 22), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _power_color(a: float) -> Color:
	if a < 0.6:
		return Color(0.3, 0.85, 0.35).lerp(Color(1.0, 0.9, 0.2), a / 0.6)
	return Color(1.0, 0.9, 0.2).lerp(Color(1.0, 0.3, 0.2), (a - 0.6) / 0.4)
