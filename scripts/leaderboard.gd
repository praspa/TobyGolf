class_name Leaderboard
extends RefCounted
## All-time top 10 lowest rounds, saved to user://leaderboard.json.
## Only completed rounds (all holes played) are recorded. Rounds are ranked by
## score to par, then total strokes, then oldest first (first to post it keeps it).

const PATH := "user://leaderboard.json"
const SIZE := 10

## Indices (into entries()) of rounds added by the last record_round(), for highlighting.
static var last_added: Array = []

static func entries() -> Array:
	if not FileAccess.file_exists(PATH):
		return []
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return []
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_ARRAY:
		return []
	return data

static func _save(list: Array) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(list, "  "))

static func _less(a: Dictionary, b: Dictionary) -> bool:
	var da := int(a["strokes"]) - int(a["par"])
	var db := int(b["strokes"]) - int(b["par"])
	if da != db:
		return da < db
	if int(a["strokes"]) != int(b["strokes"]):
		return int(a["strokes"]) < int(b["strokes"])
	return int(a.get("time", 0)) < int(b.get("time", 0))

## players: Game.players after the last hole. Returns how many made the board.
static func record_round(players: Array, course_name: String, par: int) -> int:
	var list := entries()
	var now := int(Time.get_unix_time_from_system())
	var new_ones: Array = []
	for i in players.size():
		var p: Dictionary = players[i]
		var total := 0
		for sc in p["scores"]:
			total += int(sc)
		var e := {
			"name": String(p["name"]),
			"character": String(p["character"]),
			"course": course_name,
			"strokes": total,
			"par": par,
			"holes": (p["scores"] as Array).size(),
			"date": Time.get_date_string_from_system(),
			"time": now,
			"id": "%d-%d" % [now, i],
		}
		list.append(e)
		new_ones.append(e["id"])
	list.sort_custom(_less)
	list = list.slice(0, SIZE)
	_save(list)
	last_added = []
	for i in list.size():
		if new_ones.has(String(list[i].get("id", ""))):
			last_added.append(i)
	return last_added.size()
