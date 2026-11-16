extends Node
## Top-level screen flow: main menu -> holes 1..N -> back to menu.

var _screen: Node

func _ready() -> void:
	show_menu()

func _swap(n: Node) -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	if _screen:
		remove_child(_screen)
		_screen.queue_free()
	_screen = n
	add_child(n)

func show_menu() -> void:
	var m := MainMenu.new()
	m.start_round.connect(_on_start_round, CONNECT_DEFERRED)
	m.start_match.connect(_on_start_match, CONNECT_DEFERRED)
	_swap(m)

func _on_start_round(players: int, characters: Array, course: int) -> void:
	Game.mode = "stroke"
	Game.match_opponent = ""
	Game.course_index = course
	Course.current = course
	Game.new_round(players, characters)
	_load_hole(0)

func _load_hole(i: int) -> void:
	Game.current_hole = i
	var r := Round.new()
	r.hole_index = i
	r.hole_complete.connect(_on_hole_complete, CONNECT_DEFERRED)
	r.quit_requested.connect(_on_quit_round, CONNECT_DEFERRED)
	_swap(r)

## Match Play Challenge: you vs a CPU challenger over the full course.
func _on_start_match(character: String, opponent: String, course: int) -> void:
	Game.mode = "match"
	Game.match_opponent = opponent
	Game.course_index = course
	Course.current = course
	Game.new_round(2, [character, opponent], [false, true])
	_load_hole(0)

func _finish_match() -> void:
	var st := Game.match_status()
	var opp := Game.match_opponent
	var oname: String = Game.CHARACTERS[opp]["name"]
	if st["winner"] == 0:
		var fresh := not Game.is_unlocked(opp)
		Game.unlock(opp)
		Game.last_match_result = "You beat %s!  (%s)" % [oname, st["text"].trim_prefix(Game.players[0]["name"] + " wins ")]
		if fresh:
			Game.last_match_result += "\n\n%s is now unlocked!" % oname
			var nxt := Game.next_challenger()
			if nxt != "":
				Game.last_match_result += "\nNext challenger: %s" % Game.CHARACTERS[nxt]["name"]
			else:
				Game.last_match_result += "\nEvery character is unlocked - nice!"
	elif st["winner"] == 1:
		Game.last_match_result = "%s won the match (%s).\nTry again!" % [oname, st["text"].trim_prefix(Game.players[1]["name"] + " wins ")]
	else:
		Game.last_match_result = "Match halved.\nYou need to win outright to unlock %s - try again!" % oname
	Game.mode = "stroke"
	show_menu()

## Quit mid-round from the pause menu: nothing is recorded.
func _on_quit_round() -> void:
	Leaderboard.last_added = []
	show_menu()

func _on_hole_complete() -> void:
	if Game.mode == "match" and Game.match_status()["decided"]:
		_finish_match()
		return
	var next := Game.current_hole + 1
	if next < Course.hole_count():
		_load_hole(next)
	else:
		if Game.mode == "stroke":
			Leaderboard.record_round(Game.players, String(Course.info()["name"]), Course.par_total())
		show_menu()
