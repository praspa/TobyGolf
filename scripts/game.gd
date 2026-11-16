extends Node
## Global game state (autoload "Game").
## Holds players, scores, character + club data and registers the input map
## (keyboard for early Ubuntu testing, gamepad for Steam Deck).

const YARDS_PER_METER := 1.09361
const MPH_PER_MPS := 2.23694

# --- Characters ------------------------------------------------------------
# power: distance multiplier. accuracy: 0..1, widens the "perfect" impact window
# and shrinks mis-hit penalties. natural_shape: built-in side spin
# (+ draws / right-to-left, - fades). special: name of the special shot.
const CHARACTERS := {
	"toby": {
		"name": "Toby",
		"blurb": "Black & tan coonhound. Loves zoomies and the smell of fresh-cut fairway.",
		"power": 1.0,
		"accuracy": 0.75,
		"natural_shape": 0.15,
		"special": "Zoomies",
		"special_id": "zoomies",
		"special_desc": "+12% distance, extra roll",
		"special_uses": 2,
		"hoodie": Color(0.55, 0.78, 0.95),
		"unlocked": true,
	},
	"carlin": {
		"name": "Carlin",
		"blurb": "Derpy golden retriever in a backwards purple cap. Somehow always finds the flag.",
		"power": 0.93,
		"accuracy": 0.85,
		"natural_shape": -0.2,
		"special": "Pin Seeker",
		"special_id": "pin_seeker",
		"special_desc": "homes in, lands near the pin",
		"special_uses": 2,
		"hoodie": Color(0.55, 0.3, 0.75),
		"unlocked": true,
	},
	"onezy": {
		"name": "Onezy",
		"blurb": "Fluffy gray Persian in black & red buffalo-check pajamas. Unbothered. Precise.",
		"power": 0.88,
		"accuracy": 0.95,
		"natural_shape": 0.0,
		"special": "Cat-like Reflexes",
		"special_id": "reflexes",
		"special_desc": "huge accuracy window: perfect strike",
		"special_uses": 2,
		"hoodie": Color(0.8, 0.12, 0.12),
		"unlocked": true,
	},
	"zero": {
		"name": "Zero",
		"blurb": "Black Persian in red & blue 3D movie glasses. Always lands on his feet.",
		"power": 0.97,
		"accuracy": 0.7,
		"natural_shape": -0.1,
		"special": "Nine Lives",
		"special_id": "nine_lives",
		"special_desc": "passive: may pop out of sand, water or trees",
		"special_uses": 3,
		"special_chance": 0.5,
		"passive": true,
		"hoodie": Color(0.1, 0.1, 0.12),
		"unlocked": true,
	},
	"bacon": {
		"name": "Bacon",
		"blurb": "Stocky white bulldog in a pink bow tie. Doesn't care where the ball is - he just digs in.",
		"power": 1.04,
		"accuracy": 0.65,
		"natural_shape": 0.2,
		"special": "Dig In",
		"special_id": "dig_in",
		"special_desc": "ignores the lie penalty",
		"special_uses": 3,
		"hoodie": Color(0.98, 0.5, 0.72),
		"unlocked": false,   # won in Match Play Challenge
	},
	"dorothy": {
		"name": "Dorothy",
		"blurb": "A clanky golf robot with a fishbowl for a head. Her goldfish does the thinking.",
		"power": 0.94,
		"accuracy": 0.8,
		"natural_shape": 0.0,
		"special": "Bubble Shot",
		"special_id": "bubble",
		"special_desc": "dead straight, ignores wind, splash-bounces forward",
		"special_uses": 2,
		"hoodie": Color(0.72, 0.76, 0.8),
		"unlocked": false,   # won in Match Play Challenge
	},
	"dewey": {
		"name": "Dewey",
		"blurb": "Tiny white fluffball in high-top sneakers. Nobody can say no to those eyes.",
		"power": 0.84,
		"accuracy": 0.88,
		"natural_shape": 0.05,
		"special": "Puppy Eyes",
		"special_id": "puppy_eyes",
		"special_desc": "the swing meter slows way down",
		"special_uses": 3,
		"hoodie": Color(0.9, 0.2, 0.2),
		"unlocked": false,   # won in Match Play Challenge
	},
}

# --- Clubs -----------------------------------------------------------------
# carry in yards for a power-1.0 character at 100% on a perfect lie.
# launch in degrees, spin in rpm. Ball speed is solved at runtime so that the
# power meter is linear in carry distance.
const CLUBS := [
	{"name": "Driver", "short": "1W", "carry": 230.0, "launch": 12.0, "spin": 2800.0},
	{"name": "3 Wood", "short": "3W", "carry": 210.0, "launch": 13.0, "spin": 3500.0},
	{"name": "5 Iron", "short": "5I", "carry": 175.0, "launch": 15.5, "spin": 5000.0},
	{"name": "7 Iron", "short": "7I", "carry": 150.0, "launch": 18.5, "spin": 6500.0},
	{"name": "9 Iron", "short": "9I", "carry": 125.0, "launch": 23.0, "spin": 8000.0},
	{"name": "Pitching Wedge", "short": "PW", "carry": 105.0, "launch": 27.0, "spin": 9000.0},
	{"name": "Sand Wedge", "short": "SW", "carry": 75.0, "launch": 33.0, "spin": 10000.0},
	{"name": "Putter", "short": "PT", "carry": 30.0, "launch": 0.0, "spin": 0.0},
]
const PUTTER_INDEX := 7
const SAND_WEDGE_INDEX := 6

const PLAYER_COLORS := [
	Color(0.55, 0.78, 0.95), # light blue (Toby classic)
	Color(0.95, 0.55, 0.6),
	Color(0.7, 0.9, 0.45),
	Color(0.98, 0.82, 0.35),
]

const MAX_STROKES_PER_HOLE := 10

# --- Match Play Challenge -----------------------------------------------------
# Non-stock characters are unlocked one at a time, in this order, by beating
# them in an 18-hole match against the CPU. Each is tougher than the last.
const UNLOCK_ORDER := ["dorothy", "bacon", "dewey"]
## CPU skill: power_sd = spread of power (fraction of the shot), aim_sd = degrees,
## acc_sd = timing spread on the accuracy click (1.0 = edge of the zone),
## wind = how much of the wind it allows for, putt_sd / putt_aim = putting spread,
## blunder = chance of a properly bad swing.
const CPU_SKILL := {
	"dorothy": {"label": "Rookie", "power_sd": 0.08, "aim_sd": 2.8, "acc_sd": 0.55, "wind": 0.45, "putt_sd": 0.19, "putt_aim": 2.6, "blunder": 0.15},
	"bacon": {"label": "Pro", "power_sd": 0.05, "aim_sd": 1.8, "acc_sd": 0.36, "wind": 0.75, "putt_sd": 0.11, "putt_aim": 1.6, "blunder": 0.07},
	"dewey": {"label": "Champion", "power_sd": 0.035, "aim_sd": 1.3, "acc_sd": 0.28, "wind": 0.88, "putt_sd": 0.09, "putt_aim": 1.2, "blunder": 0.04},
}
const PROGRESS_PATH := "user://progress.json"

var num_players := 1
var players: Array = [] # [{name, character, color, scores: Array[int]}]
var current_hole := 0
var course_index := 0   # which course this round is on (see Course.courses())
var mode := "stroke"    # "stroke" or "match"
var match_opponent := ""          # character id of the CPU in a match
var last_match_result := ""       # shown on the menu after a match ends
var unlocked_ids: Array = []      # characters won in Match Play (saved)

func _ready() -> void:
	_setup_input()
	_load_progress()

# --- unlock progress ---------------------------------------------------------
func _load_progress() -> void:
	unlocked_ids = []
	if not FileAccess.file_exists(PROGRESS_PATH):
		return
	var f := FileAccess.open(PROGRESS_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) == TYPE_DICTIONARY and typeof(data.get("unlocked")) == TYPE_ARRAY:
		for id in data["unlocked"]:
			if CHARACTERS.has(String(id)):
				unlocked_ids.append(String(id))

func _save_progress() -> void:
	var f := FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"unlocked": unlocked_ids}, "  "))

func is_unlocked(id: String) -> bool:
	return bool(CHARACTERS[id]["unlocked"]) or unlocked_ids.has(id)

func unlock(id: String) -> void:
	if not unlocked_ids.has(id):
		unlocked_ids.append(id)
		_save_progress()

## The next character waiting to be challenged ("" when everyone is unlocked).
func next_challenger() -> String:
	for id in UNLOCK_ORDER:
		if not is_unlocked(id):
			return id
	return ""

## Challengers that can be played now: everyone already beaten (rematches) + the next one.
func available_challengers() -> Array:
	var out: Array = []
	for id in UNLOCK_ORDER:
		out.append(id)
		if not is_unlocked(id):
			break
	return out

# --- match play --------------------------------------------------------------
## Holes won by each side so far: {"up": +n (player 0 ahead) / -n, "played": holes,
## "decided": bool, "winner": -1/0/1, "text": "Toby 2 UP"}.
func match_status() -> Dictionary:
	var up := 0
	var played := 0
	var holes := Course.hole_count()
	var decided_at := -1
	var a: Array = players[0]["scores"]
	var b: Array = players[1]["scores"] if players.size() > 1 else []
	for i in mini(a.size(), b.size()):
		played += 1
		if int(a[i]) < int(b[i]):
			up += 1
		elif int(b[i]) < int(a[i]):
			up -= 1
		if decided_at < 0 and absi(up) > holes - played:
			decided_at = played
	var decided := decided_at >= 0 or played >= holes
	var winner := -1
	if decided and up != 0:
		winner = 0 if up > 0 else 1
	var text := "All square"
	if up != 0:
		text = "%s %d UP" % [players[0 if up > 0 else 1]["name"], absi(up)]
	var left := holes - played
	if decided and up != 0:
		text = "%s wins %s" % [players[winner]["name"], ("%d&%d" % [absi(up), left]) if left > 0 else ("%d UP" % absi(up))]
	elif decided:
		text = "Match halved"
	elif up != 0 and absi(up) == left:
		text += " (dormie)"
	return {"up": up, "played": played, "decided": decided, "winner": winner, "text": text}

## characters: one character id per player (missing entries default to Toby).
## cpu: per-player flags; CPU players are driven by CpuPlayer.
func new_round(count: int, characters: Array = [], cpu: Array = []) -> void:
	num_players = clampi(count, 1, 4)
	players.clear()
	var seen := {}
	for i in num_players:
		var id: String = characters[i] if i < characters.size() else "toby"
		var nm: String = CHARACTERS[id]["name"]
		seen[id] = int(seen.get(id, 0)) + 1
		if seen[id] > 1:
			nm = "%s %d" % [nm, seen[id]]
		players.append({
			"name": nm,
			"character": id,
			"color": PLAYER_COLORS[i],
			"scores": [],
			"special_left": int(CHARACTERS[id]["special_uses"]),
			"cpu": i < cpu.size() and bool(cpu[i]),
		})
	current_hole = 0

## Character ids that can be picked in the menu.
func playable_characters() -> Array:
	var out: Array = []
	for id in CHARACTERS:
		if is_unlocked(id):
			out.append(id)
	return out

func is_cpu(player_index: int) -> bool:
	return bool(players[player_index].get("cpu", false))

func character_for(player_index: int) -> Dictionary:
	var id: String = players[player_index]["character"]
	return CHARACTERS[id]

func total_strokes(player_index: int) -> int:
	var t := 0
	for s in players[player_index]["scores"]:
		t += int(s)
	return t

static func to_yards(m: float) -> float:
	return m * YARDS_PER_METER

static func score_name(strokes: int, par: int) -> String:
	if strokes == 1:
		return "HOLE IN ONE!"
	match strokes - par:
		-3: return "Albatross!"
		-2: return "Eagle!"
		-1: return "Birdie!"
		0: return "Par"
		1: return "Bogey"
		2: return "Double Bogey"
		3: return "Triple Bogey"
	return "+%d" % (strokes - par)

# --- Input -------------------------------------------------------------------
func _setup_input() -> void:
	_action("aim_left", [KEY_LEFT, KEY_A], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_action("aim_right", [KEY_RIGHT, KEY_D], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_action("club_prev", [KEY_UP, KEY_W], [JOY_BUTTON_DPAD_UP, JOY_BUTTON_LEFT_SHOULDER], [])
	_action("club_next", [KEY_DOWN, KEY_S], [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_RIGHT_SHOULDER], [])
	_action("swing", [KEY_SPACE, KEY_ENTER], [JOY_BUTTON_A], [])
	_action("cancel", [KEY_BACKSPACE, KEY_X], [JOY_BUTTON_B], [])
	_action("spin_left", [KEY_J], [], [[JOY_AXIS_RIGHT_X, -1.0]])
	_action("spin_right", [KEY_L], [], [[JOY_AXIS_RIGHT_X, 1.0]])
	_action("spin_up", [KEY_I], [], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_action("spin_down", [KEY_K], [], [[JOY_AXIS_RIGHT_Y, 1.0]])
	_action("spin_reset", [KEY_U], [JOY_BUTTON_RIGHT_STICK], [])
	_action("special", [KEY_P], [JOY_BUTTON_X], [])
	_action("view", [KEY_V, KEY_C], [JOY_BUTTON_Y], [])
	_action("zoom_in", [KEY_Z], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_action("zoom_out", [KEY_Q], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_action("scorecard", [KEY_TAB], [JOY_BUTTON_BACK], [])
	_action("pause", [KEY_ESCAPE], [JOY_BUTTON_START], [])
	# Godot's built-in ui_accept/ui_cancel are keyboard-only: add the pad's
	# A (accept) and B (back) so menu buttons work on the Steam Deck.
	_add_button("ui_accept", JOY_BUTTON_A)
	_add_button("ui_cancel", JOY_BUTTON_B)
	# Make menus navigable with the left stick as well as dpad/keys.
	_add_axis("ui_left", JOY_AXIS_LEFT_X, -1.0)
	_add_axis("ui_right", JOY_AXIS_LEFT_X, 1.0)
	_add_axis("ui_up", JOY_AXIS_LEFT_Y, -1.0)
	_add_axis("ui_down", JOY_AXIS_LEFT_Y, 1.0)

func _add_button(act: String, button: JoyButton) -> void:
	for e in InputMap.action_get_events(act):
		if e is InputEventJoypadButton and e.button_index == button:
			return
	var jb := InputEventJoypadButton.new()
	jb.button_index = button
	InputMap.action_add_event(act, jb)

func _action(act: String, keys: Array, buttons: Array, axes: Array) -> void:
	if not InputMap.has_action(act):
		InputMap.add_action(act, 0.3)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(act, ev)
	for b in buttons:
		var jb := InputEventJoypadButton.new()
		jb.button_index = b
		InputMap.action_add_event(act, jb)
	for a in axes:
		_add_axis(act, a[0], a[1])

func _add_axis(act: String, axis: int, value: float) -> void:
	if not InputMap.has_action(act):
		InputMap.add_action(act, 0.3)
	var jm := InputEventJoypadMotion.new()
	jm.axis = axis
	jm.axis_value = value
	InputMap.action_add_event(act, jm)
