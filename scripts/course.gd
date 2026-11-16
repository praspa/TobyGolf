class_name Course
extends RefCounted
## Course + hole layout data. Units are metres. Each hole plays roughly toward -Z.
## 2D positions are Vector2(x, z).
##
## fairway        polyline of the fairway centre, fairway_hw = half width
## corridor       (built automatically) tee -> fairway -> green, shapes the valley
## green          ellipse with a tilt plane (rise per metre in x / z) for readable break
## bunkers/water  ellipses {c, rx, rz}
## islands        ellipses of dry land inside water (island greens / fairways)
## waste          ellipses of waste bunker (sandy, plays easier than a bunker)
## rocks          {c, r} boulders the ball bounces off
## bounds         Rect2 in (x, z): outside is out of bounds
## elev           terrain rise per metre travelled toward -Z (uphill/downhill holes)

## Visual / terrain themes. Colours are sRGB.
const THEMES := {
	"parkland": {
		"fairway_a": Color(0.42, 0.74, 0.30), "fairway_b": Color(0.36, 0.66, 0.26),
		"rough": Color(0.26, 0.52, 0.19), "oob": Color(0.20, 0.42, 0.15),
		"green_a": Color(0.46, 0.84, 0.39), "green_b": Color(0.445, 0.82, 0.375),
		"fringe": Color(0.38, 0.70, 0.30), "tee": Color(0.44, 0.76, 0.32),
		"bunker": Color(0.95, 0.86, 0.60), "waste": Color(0.88, 0.78, 0.55),
		"water": Color(0.25, 0.55, 0.95, 0.82), "water_bed": Color(0.32, 0.36, 0.22),
		"ground": Color(0.18, 0.38, 0.14), "hill_a": Color(0.30, 0.52, 0.32), "hill_b": Color(0.42, 0.55, 0.62),
		"sky_top": Color(0.28, 0.52, 0.95), "sky_horizon": Color(0.72, 0.86, 1.0), "fog": Color(0.75, 0.86, 1.0),
		"tree": "pine", "tree_density": 1.0, "scenery": "hills", "valley": 9.0, "rolls": 1.2, "bumps": 3.0,
		"rough_name": "Rough",
	},
	"tropical": {
		"fairway_a": Color(0.35, 0.68, 0.27), "fairway_b": Color(0.30, 0.61, 0.24),
		"rough": Color(0.25, 0.52, 0.19), "oob": Color(0.93, 0.87, 0.68),
		"green_a": Color(0.43, 0.79, 0.36), "green_b": Color(0.415, 0.77, 0.35),
		"fringe": Color(0.33, 0.64, 0.26), "tee": Color(0.39, 0.71, 0.30),
		"bunker": Color(0.99, 0.95, 0.82), "waste": Color(0.95, 0.9, 0.72),
		"water": Color(0.1, 0.78, 0.85, 0.8), "water_bed": Color(0.75, 0.85, 0.7),
		"ground": Color(0.08, 0.55, 0.78), "hill_a": Color(0.2, 0.6, 0.35), "hill_b": Color(0.35, 0.7, 0.5),
		"sky_top": Color(0.2, 0.55, 1.0), "sky_horizon": Color(0.75, 0.93, 1.0), "fog": Color(0.8, 0.95, 1.0),
		"tree": "palm", "tree_density": 0.45, "scenery": "ocean", "valley": -4.0, "rolls": 0.9, "bumps": 0.8,
		"rough_name": "Rough",
	},
	"desert": {
		"fairway_a": Color(0.52, 0.72, 0.30), "fairway_b": Color(0.46, 0.66, 0.27),
		"rough": Color(0.75, 0.59, 0.40), "oob": Color(0.70, 0.52, 0.35),
		"green_a": Color(0.47, 0.82, 0.38), "green_b": Color(0.455, 0.80, 0.37),
		"fringe": Color(0.42, 0.66, 0.30), "tee": Color(0.50, 0.74, 0.32),
		"bunker": Color(0.97, 0.88, 0.66), "waste": Color(0.90, 0.78, 0.56),
		"water": Color(0.2, 0.55, 0.85, 0.85), "water_bed": Color(0.5, 0.45, 0.3),
		"ground": Color(0.74, 0.56, 0.36), "hill_a": Color(0.74, 0.38, 0.22), "hill_b": Color(0.85, 0.55, 0.35),
		"sky_top": Color(0.3, 0.52, 0.92), "sky_horizon": Color(0.98, 0.86, 0.66), "fog": Color(0.98, 0.88, 0.72),
		"tree": "cactus", "tree_density": 0.3, "scenery": "mesas", "valley": 13.0, "rolls": 1.1, "bumps": 3.5,
		"rough_name": "Desert scrub",
	},
}

static func courses() -> Array:
	return [
		{
			"name": "Puppy Meadows",
			"blurb": "A traditional parkland course. Tree-lined fairways, a few ponds, friendly greens.",
			"theme": "parkland",
			"holes": _bend_all(_puppy_meadows() + _puppy_meadows_back()),
		},
		{
			"name": "Barking Paradise",
			"blurb": "Tropical Caribbean links. Fairways broken up by lagoons and islands - pick your lay-ups.",
			"theme": "tropical",
			"holes": _bend_all(_barking_paradise() + _barking_paradise_back()),
		},
		{
			"name": "Kitty Litter Dunes",
			"blurb": "Desert southwest. Fairway bunkers in every landing zone, waste areas, cactus and rocks.",
			"theme": "desert",
			"holes": _bend_all(_kitty_litter_dunes() + _kitty_litter_dunes_back()),
		},
	]

## Course chosen for the current round (set from the course select screen).
static var current := 0

# ----------------------------------------------------------------- doglegs ---
## Holes can declare "dogleg": [{"at": metres along the centreline, "deg": angle}].
## Everything past the corner (fairway, green, pin, hazards, rocks) pivots around
## it: +deg bends right, -deg bends left. Holes are laid out straight and bent
## here so the hazards stay where they were designed relative to the fairway.
## Bounds are recomputed for bent holes.
static func _bend_all(holes: Array) -> Array:
	for h in holes:
		for key in ["islands", "waste", "rocks"]:
			if not h.has(key):
				h[key] = []
		if h.has("dogleg"):
			for bend in h["dogleg"]:
				_bend(h, float(bend["at"]), deg_to_rad(float(bend["deg"])))
			h["bounds"] = _auto_bounds(h)
		elif not h.has("bounds"):
			h["bounds"] = _auto_bounds(h)
	return holes

static func _path(h: Dictionary) -> Array:
	var pts: Array = [h["tee"]]
	pts.append_array(h["fairway"])
	pts.append(h["green"]["c"])
	return pts

## Distance along the polyline of the closest point to p.
static func _along(pts: Array, p: Vector2) -> float:
	var best := INF
	var best_s := 0.0
	var acc := 0.0
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best:
			best = d
			best_s = acc + ab.length() * t
		acc += ab.length()
	return best_s

static func _point_at(pts: Array, s: float) -> Vector2:
	var acc := 0.0
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var l := a.distance_to(b)
		if acc + l >= s:
			return a.lerp(b, (s - acc) / maxf(l, 0.0001))
		acc += l
	return pts[pts.size() - 1]

static func _bend(h: Dictionary, at: float, ang: float) -> void:
	var path := _path(h)
	var corner := _point_at(path, at)
	var rot := func(p: Vector2) -> Vector2:
		var v := p - corner
		return corner + Vector2(v.x * cos(ang) - v.y * sin(ang), v.x * sin(ang) + v.y * cos(ang))
	var past := func(p: Vector2) -> bool:
		return _along(path, p) > at
	var swap := absf(ang) >= deg_to_rad(45.0)
	# fairway: insert the corner itself so the centreline kinks exactly there
	var fw: Array = []
	var inserted := false
	for p in h["fairway"]:
		if past.call(p):
			if not inserted:
				fw.append(corner)
				inserted = true
			fw.append(rot.call(p))
		else:
			fw.append(p)
	h["fairway"] = fw
	if past.call(h["pin"]):
		h["pin"] = rot.call(h["pin"])
	var g: Dictionary = h["green"]
	if past.call(g["c"]):
		g["c"] = rot.call(g["c"])
		var tl: Vector2 = g["tilt"]
		g["tilt"] = tl.rotated(ang)
		if swap:
			var t2: float = g["rx"]
			g["rx"] = g["rz"]
			g["rz"] = t2
	for key in ["bunkers", "water", "islands", "waste", "rocks"]:
		for e in h.get(key, []):
			if past.call(e["c"]):
				e["c"] = rot.call(e["c"])
				if swap and e.has("rx"):
					var t3: float = e["rx"]
					e["rx"] = e["rz"]
					e["rz"] = t3

static func _auto_bounds(h: Dictionary) -> Rect2:
	var r := Rect2(h["tee"], Vector2.ZERO)
	for p in h["fairway"]:
		r = r.expand(p)
	var g: Dictionary = h["green"]
	var gc: Vector2 = g["c"]
	r = r.expand(gc + Vector2(g["rx"], g["rz"]) * 1.3).expand(gc - Vector2(g["rx"], g["rz"]) * 1.3)
	for key in ["bunkers", "water", "islands", "waste"]:
		for e in h.get(key, []):
			var c: Vector2 = e["c"]
			var ext := Vector2(e["rx"], e["rz"])
			r = r.expand(c + ext).expand(c - ext)
	r = r.grow_individual(48.0, 30.0, 48.0, 22.0)  # sides, past the green, behind the tee
	return r

static func course_count() -> int:
	return courses().size()

## Info for one course (defaults to the course picked for this round).
static func info(course_index: int = -1) -> Dictionary:
	var all := courses()
	var i := current if course_index < 0 else course_index
	return all[clampi(i, 0, all.size() - 1)]

static func holes(course_index: int = -1) -> Array:
	return info(course_index)["holes"]

static func theme(course_index: int = -1) -> Dictionary:
	return THEMES[info(course_index)["theme"]]

static func par_total(course_index: int = -1) -> int:
	var t := 0
	for h in holes(course_index):
		t += int(h["par"])
	return t

static func _puppy_meadows() -> Array:
	return [
		{
			"name": "Puppy Meadow",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(8, -298),
			"fairway": [Vector2(0, -28), Vector2(-4, -120), Vector2(2, -220), Vector2(6, -276)],
			"fairway_hw": 16.0,
			"green": {"c": Vector2(6, -300), "rx": 15.0, "rz": 13.0, "tilt": Vector2(0.015, -0.02), "und": 0.05, "raise": 0.8},
			"bunkers": [
				{"c": Vector2(-12, -297), "rx": 5.0, "rz": 4.0},
				{"c": Vector2(21, -308), "rx": 4.0, "rz": 5.5},
				{"c": Vector2(21, -205), "rx": 7.0, "rz": 4.0},
			],
			"water": [
				{"c": Vector2(-40, -160), "rx": 14.0, "rz": 24.0},
			],
			"bounds": Rect2(-70, -345, 140, 365),
			"elev": 0.008,
			"seed": 101,
			"dogleg": [{"at": 205.0, "deg": -30.0}],
			"wind_max": 5.0,
		},
		{
			"name": "Splash Pond",
			"par": 3,
			"tee": Vector2(0, 0),
			"pin": Vector2(-2, -134),
			"fairway": [Vector2(-1, -104), Vector2(-4, -122)],
			"fairway_hw": 13.0,
			"green": {"c": Vector2(-4, -136), "rx": 13.0, "rz": 11.0, "tilt": Vector2(-0.025, -0.012), "und": 0.04, "raise": 0.6},
			"bunkers": [
				{"c": Vector2(11, -142), "rx": 4.0, "rz": 4.5},
				{"c": Vector2(-18, -133), "rx": 3.5, "rz": 5.0},
				{"c": Vector2(-4, -152), "rx": 7.0, "rz": 3.0},
			],
			"water": [
				{"c": Vector2(0, -78), "rx": 26.0, "rz": 21.0},
			],
			"bounds": Rect2(-55, -180, 110, 200),
			"elev": -0.01,
			"seed": 202,
			"wind_max": 6.0,
		},
		{
			"name": "Long Walkies",
			"par": 5,
			"tee": Vector2(0, 0),
			"pin": Vector2(88, -456),
			"fairway": [Vector2(0, -35), Vector2(0, -150), Vector2(12, -235), Vector2(45, -320), Vector2(72, -395), Vector2(82, -432)],
			"fairway_hw": 17.0,
			"green": {"c": Vector2(86, -458), "rx": 16.0, "rz": 13.0, "tilt": Vector2(0.01, 0.022), "und": 0.06, "raise": 1.0},
			"bunkers": [
				{"c": Vector2(-13, -215), "rx": 6.0, "rz": 4.0},
				{"c": Vector2(61, -300), "rx": 6.0, "rz": 4.0},
				{"c": Vector2(104, -455), "rx": 4.0, "rz": 6.0},
				{"c": Vector2(84, -475), "rx": 7.0, "rz": 3.0},
			],
			"water": [
				{"c": Vector2(52, -245), "rx": 16.0, "rz": 13.0},
				{"c": Vector2(57, -468), "rx": 8.0, "rz": 13.0},
			],
			"bounds": Rect2(-55, -505, 195, 525),
			"elev": 0.004,
			"seed": 303,
			"wind_max": 4.5,
		},
		{
			"name": "Fetch Lane",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(-70, -343),
			"fairway": [Vector2(0, -30), Vector2(-2, -150), Vector2(-15, -230), Vector2(-45, -300), Vector2(-60, -325)],
			"fairway_hw": 16.0,
			"green": {"c": Vector2(-72, -345), "rx": 14.0, "rz": 12.0, "tilt": Vector2(-0.012, 0.015), "und": 0.05, "raise": 0.8},
			"bunkers": [
				{"c": Vector2(-40, -232), "rx": 7.0, "rz": 5.0},
				{"c": Vector2(-56, -357), "rx": 4.0, "rz": 5.0},
				{"c": Vector2(-88, -335), "rx": 4.0, "rz": 4.5},
			],
			"water": [
				{"c": Vector2(30, -200), "rx": 12.0, "rz": 30.0},
			],
			"bounds": Rect2(-115, -385, 175, 405),
			"elev": 0.005,
			"seed": 404,
			"dogleg": [{"at": 185.0, "deg": -25.0}],
			"wind_max": 5.0,
		},
		{
			"name": "Squirrel Chase",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(18, -327),
			"fairway": [Vector2(0, -30), Vector2(4, -140), Vector2(10, -250), Vector2(14, -300)],
			"fairway_hw": 15.0,
			"green": {"c": Vector2(16, -325), "rx": 13.0, "rz": 12.0, "tilt": Vector2(0.02, -0.01), "und": 0.04, "raise": 1.0},
			"bunkers": [
				{"c": Vector2(25, -180), "rx": 5.0, "rz": 6.0},
				{"c": Vector2(32, -322), "rx": 4.0, "rz": 5.0},
				{"c": Vector2(4, -340), "rx": 4.0, "rz": 3.0},
			],
			"water": [
				{"c": Vector2(-15, -290), "rx": 12.0, "rz": 18.0},
			],
			"bounds": Rect2(-60, -365, 130, 385),
			"elev": 0.012,
			"seed": 505,
			"dogleg": [{"at": 210.0, "deg": 50.0}],
			"wind_max": 5.5,
		},
		{
			"name": "Catnip Cove",
			"par": 3,
			"tee": Vector2(0, 0),
			"pin": Vector2(-6, -158),
			"fairway": [Vector2(-6, -122), Vector2(-8, -140)],
			"fairway_hw": 10.0,
			"green": {"c": Vector2(-8, -160), "rx": 12.0, "rz": 11.0, "tilt": Vector2(0.01, 0.018), "und": 0.04, "raise": 0.7},
			"bunkers": [
				{"c": Vector2(-24, -160), "rx": 4.0, "rz": 5.0},
				{"c": Vector2(-8, -177), "rx": 6.0, "rz": 3.0},
			],
			"water": [
				{"c": Vector2(-4, -98), "rx": 22.0, "rz": 11.0},
				{"c": Vector2(15, -150), "rx": 9.0, "rz": 16.0},
			],
			"bounds": Rect2(-55, -200, 110, 220),
			"elev": -0.015,
			"seed": 606,
			"wind_max": 6.5,
		},
		{
			"name": "The Big Nap",
			"par": 5,
			"tee": Vector2(0, 0),
			"pin": Vector2(22, -468),
			"fairway": [Vector2(0, -30), Vector2(-5, -130), Vector2(10, -230), Vector2(35, -300), Vector2(40, -380), Vector2(28, -440)],
			"fairway_hw": 17.0,
			"green": {"c": Vector2(24, -470), "rx": 15.0, "rz": 13.0, "tilt": Vector2(-0.015, -0.015), "und": 0.05, "raise": 1.0},
			"bunkers": [
				{"c": Vector2(-24, -140), "rx": 5.0, "rz": 6.0},
				{"c": Vector2(60, -290), "rx": 6.0, "rz": 5.0},
				{"c": Vector2(42, -472), "rx": 4.0, "rz": 5.0},
				{"c": Vector2(12, -487), "rx": 6.0, "rz": 3.0},
			],
			"water": [
				{"c": Vector2(40, -345), "rx": 32.0, "rz": 7.0},
			],
			"bounds": Rect2(-60, -515, 160, 535),
			"elev": 0.003,
			"seed": 707,
			"wind_max": 4.5,
		},
		{
			"name": "Hairball Hollow",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(-10, -367),
			"fairway": [Vector2(0, -30), Vector2(0, -200), Vector2(-6, -310), Vector2(-8, -340)],
			"fairway_hw": 15.0,
			"green": {"c": Vector2(-8, -365), "rx": 14.0, "rz": 12.0, "tilt": Vector2(0.018, 0.01), "und": 0.05, "raise": 0.8},
			"bunkers": [
				{"c": Vector2(-19, -222), "rx": 6.0, "rz": 5.0},
				{"c": Vector2(18, -232), "rx": 6.0, "rz": 5.0},
				{"c": Vector2(-25, -362), "rx": 4.0, "rz": 5.0},
				{"c": Vector2(9, -373), "rx": 4.0, "rz": 5.0},
				{"c": Vector2(-8, -381), "rx": 6.0, "rz": 2.5},
			],
			"water": [
				{"c": Vector2(-40, -120), "rx": 14.0, "rz": 30.0},
			],
			"bounds": Rect2(-75, -400, 140, 420),
			"elev": -0.012,
			"seed": 808,
			"dogleg": [{"at": 225.0, "deg": -55.0}],
			"wind_max": 5.0,
		},
		{
			"name": "Home to the Couch",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(78, -370),
			"fairway": [Vector2(0, -30), Vector2(-4, -170), Vector2(10, -260), Vector2(45, -330), Vector2(62, -350)],
			"fairway_hw": 17.0,
			"green": {"c": Vector2(76, -372), "rx": 16.0, "rz": 13.0, "tilt": Vector2(-0.01, -0.02), "und": 0.05, "raise": 1.0},
			"bunkers": [
				{"c": Vector2(-20, -180), "rx": 5.0, "rz": 6.0},
				{"c": Vector2(96, -370), "rx": 4.0, "rz": 6.0},
				{"c": Vector2(72, -389), "rx": 7.0, "rz": 3.0},
				{"c": Vector2(56, -368), "rx": 3.0, "rz": 4.0},
			],
			"water": [
				{"c": Vector2(52, -232), "rx": 22.0, "rz": 28.0},
			],
			"bounds": Rect2(-60, -415, 190, 435),
			"elev": 0.006,
			"seed": 909,
			"wind_max": 5.0,
		},
	]

static func _barking_paradise() -> Array:
	return [
		{
			"name": "Sandy Paws",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(12, -298),
			"fairway": [Vector2(0, -30), Vector2(0, -150), Vector2(8, -240), Vector2(10, -275)],
			"fairway_hw": 16.0,
			"green": {"c": Vector2(12, -300), "rx": 14.0, "rz": 12.0, "tilt": Vector2(0.012, -0.015), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(-4, -298), "rx": 4.0, "rz": 5.0}, {"c": Vector2(26, -306), "rx": 4.0, "rz": 4.0}],
			"water": [{"c": Vector2(6, -228), "rx": 75.0, "rz": 13.0}],
			"islands": [],
			"waste": [],
			"rocks": [],
			"bounds": Rect2(-60, -340, 130, 360),
			"elev": 0.004,
			"seed": 1101,
			"dogleg": [{"at": 250.0, "deg": 40.0}],
			"wind_max": 6.0,
		},
		{
			"name": "Island Hop",
			"par": 3,
			"tee": Vector2(0, 0),
			"pin": Vector2(1, -145),
			"fairway": [Vector2(0, -128), Vector2(0, -131)],
			"fairway_hw": 6.0,
			"green": {"c": Vector2(0, -146), "rx": 12.0, "rz": 11.0, "tilt": Vector2(-0.01, 0.015), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(13, -152), "rx": 3.0, "rz": 4.0}],
			"water": [{"c": Vector2(0, -120), "rx": 34.0, "rz": 45.0}],
			"islands": [{"c": Vector2(0, -145), "rx": 17.0, "rz": 16.0}],
			"waste": [],
			"rocks": [],
			"bounds": Rect2(-55, -200, 110, 220),
			"elev": 0.0,
			"seed": 1102,
			"wind_max": 7.0,
		},
		{
			"name": "Coconut Carry",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(-12, -343),
			"fairway": [Vector2(0, -125), Vector2(-5, -230), Vector2(-10, -320)],
			"fairway_hw": 17.0,
			"green": {"c": Vector2(-12, -345), "rx": 14.0, "rz": 12.0, "tilt": Vector2(0.015, 0.01), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(6, -340), "rx": 4.0, "rz": 5.0}, {"c": Vector2(-28, -350), "rx": 4.0, "rz": 4.0}],
			"water": [{"c": Vector2(0, -90), "rx": 30.0, "rz": 22.0}, {"c": Vector2(-5, -248), "rx": 62.0, "rz": 48.0}],
			"islands": [{"c": Vector2(-5, -248), "rx": 19.0, "rz": 15.0}],
			"waste": [],
			"rocks": [],
			"bounds": Rect2(-70, -385, 130, 405),
			"elev": 0.003,
			"seed": 1103,
			"wind_max": 6.0,
		},
		{
			"name": "Treasure Cove",
			"par": 5,
			"tee": Vector2(0, 0),
			"pin": Vector2(-8, -463),
			"fairway": [Vector2(0, -30), Vector2(5, -200), Vector2(2, -265), Vector2(0, -320), Vector2(-6, -420), Vector2(-8, -440)],
			"fairway_hw": 17.0,
			"green": {"c": Vector2(-10, -465), "rx": 15.0, "rz": 13.0, "tilt": Vector2(-0.012, -0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(18, -160), "rx": 5.0, "rz": 6.0}, {"c": Vector2(-27, -460), "rx": 4.0, "rz": 5.0}, {"c": Vector2(6, -480), "rx": 5.0, "rz": 3.0}],
			"water": [{"c": Vector2(3, -222), "rx": 70.0, "rz": 26.0}, {"c": Vector2(-3, -368), "rx": 70.0, "rz": 36.0}],
			"islands": [{"c": Vector2(-3, -368), "rx": 18.0, "rz": 13.0}],
			"waste": [],
			"rocks": [],
			"bounds": Rect2(-70, -505, 140, 525),
			"elev": 0.002,
			"seed": 1104,
			"wind_max": 5.5,
		},
		{
			"name": "Parrot Point",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(47, -318),
			"fairway": [Vector2(0, -30), Vector2(-4, -150), Vector2(10, -240), Vector2(35, -300)],
			"fairway_hw": 16.0,
			"green": {"c": Vector2(48, -320), "rx": 13.0, "rz": 12.0, "tilt": Vector2(0.018, 0.008), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(63, -322), "rx": 4.0, "rz": 5.0}, {"c": Vector2(42, -336), "rx": 5.0, "rz": 3.0}],
			"water": [{"c": Vector2(46, -150), "rx": 17.0, "rz": 50.0}, {"c": Vector2(10, -246), "rx": 60.0, "rz": 11.0}],
			"islands": [],
			"waste": [],
			"rocks": [],
			"bounds": Rect2(-50, -360, 140, 380),
			"elev": 0.004,
			"seed": 1105,
			"wind_max": 6.5,
		},
		{
			"name": "Lagoon Lob",
			"par": 3,
			"tee": Vector2(0, 0),
			"pin": Vector2(-5, -122),
			"fairway": [Vector2(-5, -104), Vector2(-6, -108)],
			"fairway_hw": 8.0,
			"green": {"c": Vector2(-6, -123), "rx": 12.0, "rz": 10.0, "tilt": Vector2(0.012, -0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(-21, -125), "rx": 3.0, "rz": 4.0}],
			"water": [{"c": Vector2(5, -70), "rx": 30.0, "rz": 27.0}, {"c": Vector2(-6, -150), "rx": 25.0, "rz": 11.0}],
			"islands": [],
			"waste": [],
			"rocks": [],
			"bounds": Rect2(-55, -175, 110, 195),
			"elev": -0.004,
			"seed": 1106,
			"wind_max": 7.0,
		},
		{
			"name": "Shipwreck",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(-11, -340),
			"fairway": [Vector2(0, -40), Vector2(0, -200), Vector2(-8, -290), Vector2(-10, -318)],
			"fairway_hw": 15.0,
			"green": {"c": Vector2(-10, -342), "rx": 14.0, "rz": 12.0, "tilt": Vector2(0.01, -0.018), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(5, -348), "rx": 4.0, "rz": 5.0}, {"c": Vector2(-26, -336), "rx": 4.0, "rz": 4.0}],
			"water": [{"c": Vector2(-2, -172), "rx": 70.0, "rz": 46.0}, {"c": Vector2(30, -275), "rx": 12.0, "rz": 35.0}],
			"islands": [{"c": Vector2(0, -170), "rx": 17.0, "rz": 19.0}],
			"waste": [],
			"rocks": [],
			"bounds": Rect2(-70, -385, 140, 405),
			"elev": 0.003,
			"seed": 1107,
			"dogleg": [{"at": 222.0, "deg": -40.0}],
			"wind_max": 6.0,
		},
		{
			"name": "Big Kahuna",
			"par": 5,
			"tee": Vector2(0, 0),
			"pin": Vector2(3, -470),
			"fairway": [Vector2(0, -30), Vector2(0, -140), Vector2(-20, -260), Vector2(-15, -380), Vector2(0, -450)],
			"fairway_hw": 17.0,
			"green": {"c": Vector2(2, -472), "rx": 15.0, "rz": 13.0, "tilt": Vector2(-0.015, 0.01), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(20, -466), "rx": 4.0, "rz": 5.0}, {"c": Vector2(-30, -250), "rx": 5.0, "rz": 6.0}],
			"water": [{"c": Vector2(0, -175), "rx": 70.0, "rz": 12.0}, {"c": Vector2(-15, -335), "rx": 70.0, "rz": 34.0}, {"c": Vector2(-22, -472), "rx": 8.0, "rz": 14.0}],
			"islands": [{"c": Vector2(-15, -335), "rx": 16.0, "rz": 12.0}],
			"waste": [],
			"rocks": [],
			"bounds": Rect2(-75, -515, 145, 535),
			"elev": 0.002,
			"seed": 1108,
			"wind_max": 5.5,
		},
		{
			"name": "Sunset Finish",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(2, -338),
			"fairway": [Vector2(0, -30), Vector2(4, -150), Vector2(0, -250), Vector2(0, -290)],
			"fairway_hw": 16.0,
			"green": {"c": Vector2(0, -340), "rx": 14.0, "rz": 12.0, "tilt": Vector2(0.012, 0.015), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(12, -345), "rx": 3.0, "rz": 4.0}],
			"water": [{"c": Vector2(0, -335), "rx": 32.0, "rz": 30.0}, {"c": Vector2(-36, -150), "rx": 12.0, "rz": 40.0}],
			"islands": [{"c": Vector2(0, -340), "rx": 17.0, "rz": 15.0}],
			"waste": [],
			"rocks": [],
			"bounds": Rect2(-60, -385, 120, 405),
			"elev": 0.002,
			"seed": 1109,
			"dogleg": [{"at": 200.0, "deg": -35.0}],
			"wind_max": 6.5,
		},
	]

static func _kitty_litter_dunes() -> Array:
	return [
		{
			"name": "Litter Box",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(11, -308),
			"fairway": [Vector2(0, -90), Vector2(5, -200), Vector2(8, -285)],
			"fairway_hw": 16.0,
			"green": {"c": Vector2(10, -310), "rx": 14.0, "rz": 12.0, "tilt": Vector2(0.015, -0.015), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(-5, -305), "rx": 4.0, "rz": 5.0}, {"c": Vector2(24, -316), "rx": 4.0, "rz": 4.0}, {"c": Vector2(-7, -208), "rx": 4.0, "rz": 5.0}, {"c": Vector2(15, -215), "rx": 4.0, "rz": 4.0}, {"c": Vector2(3, -252), "rx": 5.0, "rz": 3.0}],
			"water": [],
			"islands": [],
			"waste": [{"c": Vector2(0, -50), "rx": 20.0, "rz": 30.0}, {"c": Vector2(36, -200), "rx": 14.0, "rz": 50.0}],
			"rocks": [{"c": Vector2(-6, -170), "r": 0.9}, {"c": Vector2(11, -232), "r": 1.1}],
			"bounds": Rect2(-60, -350, 130, 370),
			"elev": 0.006,
			"seed": 2101,
			"dogleg": [{"at": 232.0, "deg": -40.0}],
			"wind_max": 5.0,
		},
		{
			"name": "Scratch Post",
			"par": 3,
			"tee": Vector2(0, 0),
			"pin": Vector2(-3, -149),
			"fairway": [Vector2(-3, -125), Vector2(-4, -130)],
			"fairway_hw": 9.0,
			"green": {"c": Vector2(-4, -150), "rx": 13.0, "rz": 11.0, "tilt": Vector2(-0.015, -0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(10, -156), "rx": 4.0, "rz": 5.0}, {"c": Vector2(-18, -148), "rx": 3.0, "rz": 5.0}, {"c": Vector2(-3, -129), "rx": 5.0, "rz": 2.5}],
			"water": [],
			"islands": [],
			"waste": [{"c": Vector2(0, -75), "rx": 25.0, "rz": 45.0}],
			"rocks": [{"c": Vector2(6, -40), "r": 1.2}],
			"bounds": Rect2(-55, -190, 110, 210),
			"elev": -0.006,
			"seed": 2102,
			"wind_max": 6.0,
		},
		{
			"name": "Tumbleweed",
			"par": 5,
			"tee": Vector2(0, 0),
			"pin": Vector2(-62, -463),
			"fairway": [Vector2(0, -30), Vector2(0, -180), Vector2(-20, -300), Vector2(-50, -400), Vector2(-60, -440)],
			"fairway_hw": 17.0,
			"green": {"c": Vector2(-64, -465), "rx": 15.0, "rz": 13.0, "tilt": Vector2(0.012, 0.015), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(-47, -463), "rx": 4.0, "rz": 5.0}, {"c": Vector2(-81, -470), "rx": 4.0, "rz": 5.0}, {"c": Vector2(6, -200), "rx": 4.0, "rz": 5.0}, {"c": Vector2(-10, -218), "rx": 5.0, "rz": 4.0}, {"c": Vector2(-34, -348), "rx": 4.0, "rz": 5.0}, {"c": Vector2(-50, -370), "rx": 4.0, "rz": 4.0}],
			"water": [],
			"islands": [],
			"waste": [{"c": Vector2(-46, -260), "rx": 17.0, "rz": 40.0}, {"c": Vector2(32, -120), "rx": 12.0, "rz": 60.0}],
			"rocks": [{"c": Vector2(2, -150), "r": 1.0}, {"c": Vector2(-18, -292), "r": 1.2}, {"c": Vector2(-46, -388), "r": 0.9}],
			"bounds": Rect2(-115, -505, 165, 525),
			"elev": 0.004,
			"seed": 2103,
			"wind_max": 5.0,
		},
		{
			"name": "Hairball Canyon",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(-4, -363),
			"fairway": [Vector2(0, -30), Vector2(4, -180), Vector2(0, -300), Vector2(-4, -340)],
			"fairway_hw": 14.0,
			"green": {"c": Vector2(-5, -365), "rx": 13.0, "rz": 12.0, "tilt": Vector2(-0.012, -0.015), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(10, -372), "rx": 4.0, "rz": 4.0}, {"c": Vector2(-6, -195), "rx": 4.0, "rz": 5.0}, {"c": Vector2(10, -210), "rx": 4.0, "rz": 4.0}, {"c": Vector2(0, -245), "rx": 4.0, "rz": 3.0}],
			"water": [],
			"islands": [],
			"waste": [{"c": Vector2(-22, -200), "rx": 8.0, "rz": 40.0}, {"c": Vector2(22, -260), "rx": 8.0, "rz": 35.0}],
			"rocks": [{"c": Vector2(-4, -120), "r": 1.0}, {"c": Vector2(8, -230), "r": 1.1}, {"c": Vector2(-2, -290), "r": 0.8}],
			"bounds": Rect2(-65, -400, 130, 420),
			"elev": 0.008,
			"seed": 2104,
			"dogleg": [{"at": 232.0, "deg": 45.0}],
			"wind_max": 4.0,
		},
		{
			"name": "Sun Nap Oasis",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(7, -318),
			"fairway": [Vector2(0, -30), Vector2(-6, -170), Vector2(0, -270), Vector2(4, -295)],
			"fairway_hw": 16.0,
			"green": {"c": Vector2(6, -320), "rx": 14.0, "rz": 12.0, "tilt": Vector2(0.015, 0.01), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(21, -325), "rx": 4.0, "rz": 5.0}, {"c": Vector2(3, -190), "rx": 4.0, "rz": 5.0}, {"c": Vector2(-14, -230), "rx": 4.0, "rz": 4.0}, {"c": Vector2(7, -246), "rx": 4.0, "rz": 4.0}],
			"water": [{"c": Vector2(-19, -312), "rx": 8.0, "rz": 12.0}],
			"islands": [],
			"waste": [{"c": Vector2(30, -150), "rx": 15.0, "rz": 40.0}],
			"rocks": [{"c": Vector2(-8, -210), "r": 1.0}],
			"bounds": Rect2(-60, -360, 130, 380),
			"elev": 0.005,
			"seed": 2105,
			"dogleg": [{"at": 205.0, "deg": 35.0}],
			"wind_max": 5.0,
		},
		{
			"name": "Prickly Pear",
			"par": 3,
			"tee": Vector2(0, 0),
			"pin": Vector2(6, -127),
			"fairway": [Vector2(4, -105), Vector2(5, -110)],
			"fairway_hw": 8.0,
			"green": {"c": Vector2(5, -128), "rx": 12.0, "rz": 10.0, "tilt": Vector2(0.012, -0.015), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(-9, -126), "rx": 3.0, "rz": 5.0}, {"c": Vector2(18, -132), "rx": 3.0, "rz": 4.0}, {"c": Vector2(5, -142), "rx": 6.0, "rz": 2.5}, {"c": Vector2(2, -110), "rx": 4.0, "rz": 2.5}],
			"water": [],
			"islands": [],
			"waste": [{"c": Vector2(4, -70), "rx": 24.0, "rz": 30.0}],
			"rocks": [],
			"bounds": Rect2(-50, -170, 110, 190),
			"elev": -0.008,
			"seed": 2106,
			"wind_max": 6.5,
		},
		{
			"name": "Rattlesnake Run",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(7, -373),
			"fairway": [Vector2(0, -30), Vector2(10, -150), Vector2(-5, -260), Vector2(5, -350)],
			"fairway_hw": 15.0,
			"green": {"c": Vector2(6, -375), "rx": 14.0, "rz": 12.0, "tilt": Vector2(-0.012, 0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(-9, -372), "rx": 4.0, "rz": 5.0}, {"c": Vector2(21, -380), "rx": 4.0, "rz": 4.0}, {"c": Vector2(1, -200), "rx": 4.0, "rz": 5.0}, {"c": Vector2(-12, -222), "rx": 4.0, "rz": 4.0}, {"c": Vector2(7, -235), "rx": 3.0, "rz": 4.0}],
			"water": [],
			"islands": [],
			"waste": [{"c": Vector2(-26, -150), "rx": 13.0, "rz": 40.0}, {"c": Vector2(29, -262), "rx": 13.0, "rz": 40.0}],
			"rocks": [{"c": Vector2(12, -128), "r": 1.0}, {"c": Vector2(-4, -240), "r": 1.1}, {"c": Vector2(2, -318), "r": 0.9}],
			"bounds": Rect2(-70, -415, 140, 435),
			"elev": 0.004,
			"seed": 2107,
			"dogleg": [{"at": 228.0, "deg": -50.0}],
			"wind_max": 5.0,
		},
		{
			"name": "Coyote Ugly",
			"par": 5,
			"tee": Vector2(0, 0),
			"pin": Vector2(7, -453),
			"fairway": [Vector2(0, -30), Vector2(0, -280), Vector2(5, -320), Vector2(5, -430)],
			"fairway_hw": 17.0,
			"green": {"c": Vector2(6, -455), "rx": 15.0, "rz": 13.0, "tilt": Vector2(0.01, -0.015), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(-10, -452), "rx": 4.0, "rz": 5.0}, {"c": Vector2(22, -460), "rx": 4.0, "rz": 5.0}, {"c": Vector2(6, -190), "rx": 4.0, "rz": 5.0}, {"c": Vector2(-9, -222), "rx": 4.0, "rz": 4.0}, {"c": Vector2(4, -248), "rx": 5.0, "rz": 3.0}, {"c": Vector2(-5, -355), "rx": 4.0, "rz": 4.0}, {"c": Vector2(13, -362), "rx": 3.0, "rz": 4.0}],
			"water": [],
			"islands": [],
			"waste": [{"c": Vector2(0, -300), "rx": 42.0, "rz": 13.0}, {"c": Vector2(33, -150), "rx": 12.0, "rz": 50.0}],
			"rocks": [{"c": Vector2(-6, -200), "r": 1.0}, {"c": Vector2(10, -380), "r": 1.2}],
			"bounds": Rect2(-65, -495, 140, 515),
			"elev": 0.003,
			"seed": 2108,
			"wind_max": 5.5,
		},
		{
			"name": "Last Lick Mesa",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(56, -343),
			"fairway": [Vector2(0, -30), Vector2(-4, -170), Vector2(10, -260), Vector2(35, -310), Vector2(45, -325)],
			"fairway_hw": 16.0,
			"green": {"c": Vector2(55, -345), "rx": 14.0, "rz": 12.0, "tilt": Vector2(-0.015, -0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(40, -352), "rx": 4.0, "rz": 5.0}, {"c": Vector2(70, -340), "rx": 4.0, "rz": 5.0}, {"c": Vector2(-10, -195), "rx": 4.0, "rz": 5.0}, {"c": Vector2(8, -208), "rx": 4.0, "rz": 4.0}, {"c": Vector2(18, -276), "rx": 4.0, "rz": 3.0}],
			"water": [],
			"islands": [],
			"waste": [{"c": Vector2(33, -215), "rx": 13.0, "rz": 30.0}],
			"rocks": [{"c": Vector2(2, -200), "r": 1.0}, {"c": Vector2(25, -290), "r": 0.9}],
			"bounds": Rect2(-55, -385, 155, 405),
			"elev": 0.012,
			"seed": 2109,
			"wind_max": 5.0,
		},
	]

# ------------------------------------------------------------ back nines ---
## Laid out straight down -Z; "dogleg" bends them (see _bend_all).
static func _puppy_meadows_back() -> Array:
	return [
		{
			"name": "Tail Wagger",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(1, -338),
			"fairway": [Vector2(0, -30), Vector2(0, -130), Vector2(0, -230), Vector2(0, -316)],
			"fairway_hw": 16.0,
			"green": {"c": Vector2(0, -340), "rx": 14.0, "rz": 12.0, "tilt": Vector2(0.012, -0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(-15, -225), "rx": 6.0, "rz": 4.0}, {"c": Vector2(-15, -338), "rx": 4.0, "rz": 5.0}, {"c": Vector2(14, -350), "rx": 4.0, "rz": 4.0}],
			"water": [],
			"islands": [],
			"waste": [],
			"rocks": [],
			"elev": 0.006,
			"seed": 1010,
			"wind_max": 5.5,
			"dogleg": [{"at": 215.0, "deg": 35.0}],
		},
		{
			"name": "Biscuit Bend",
			"par": 3,
			"tee": Vector2(0, 0),
			"pin": Vector2(4, -148),
			"fairway": [Vector2(3, -129), Vector2(3, -133)],
			"fairway_hw": 10.0,
			"green": {"c": Vector2(3, -150), "rx": 13.0, "rz": 11.0, "tilt": Vector2(-0.015, 0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(19, -150), "rx": 4.0, "rz": 5.0}, {"c": Vector2(-12, -163), "rx": 5.0, "rz": 3.0}],
			"water": [{"c": Vector2(0, -105), "rx": 20.0, "rz": 14.0}],
			"islands": [],
			"waste": [],
			"rocks": [],
			"elev": -0.008,
			"seed": 1011,
			"wind_max": 6.5,
		},
		{
			"name": "The Long Leash",
			"par": 5,
			"tee": Vector2(0, 0),
			"pin": Vector2(1, -468),
			"fairway": [Vector2(0, -30), Vector2(0, -130), Vector2(0, -230), Vector2(0, -330), Vector2(0, -446)],
			"fairway_hw": 17.0,
			"green": {"c": Vector2(0, -470), "rx": 15.0, "rz": 13.0, "tilt": Vector2(0.012, -0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(-15, -195), "rx": 6.0, "rz": 4.0}, {"c": Vector2(14, -320), "rx": 5.0, "rz": 5.0}, {"c": Vector2(16, -470), "rx": 4.0, "rz": 5.0}, {"c": Vector2(-14, -481), "rx": 6.0, "rz": 3.0}],
			"water": [{"c": Vector2(-40, -280), "rx": 12.0, "rz": 22.0}],
			"islands": [],
			"waste": [],
			"rocks": [],
			"elev": 0.004,
			"seed": 1012,
			"wind_max": 5.5,
			"dogleg": [{"at": 200.0, "deg": -30.0}, {"at": 335.0, "deg": 35.0}],
		},
		{
			"name": "Puddle Jump",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(1, -318),
			"fairway": [Vector2(0, -30), Vector2(0, -130), Vector2(0, -230), Vector2(0, -296)],
			"fairway_hw": 16.0,
			"green": {"c": Vector2(0, -320), "rx": 14.0, "rz": 12.0, "tilt": Vector2(0.012, -0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(13, -325), "rx": 4.0, "rz": 5.0}, {"c": Vector2(-14, -312), "rx": 4.0, "rz": 4.0}],
			"water": [{"c": Vector2(0, -228), "rx": 65.0, "rz": 8.0}],
			"islands": [],
			"waste": [],
			"rocks": [],
			"elev": 0.005,
			"seed": 1013,
			"wind_max": 5.5,
			"dogleg": [{"at": 255.0, "deg": -25.0}],
		},
		{
			"name": "Mailman's Route",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(1, -363),
			"fairway": [Vector2(0, -30), Vector2(0, -130), Vector2(0, -230), Vector2(0, -341)],
			"fairway_hw": 15.0,
			"green": {"c": Vector2(0, -365), "rx": 14.0, "rz": 12.0, "tilt": Vector2(0.012, -0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(18, -212), "rx": 6.0, "rz": 8.0}, {"c": Vector2(-17, -250), "rx": 6.0, "rz": 4.0}, {"c": Vector2(-14, -360), "rx": 4.0, "rz": 5.0}, {"c": Vector2(14, -373), "rx": 4.0, "rz": 4.0}],
			"water": [{"c": Vector2(-32, -352), "rx": 9.0, "rz": 14.0}],
			"islands": [],
			"waste": [],
			"rocks": [],
			"elev": 0.006,
			"seed": 1014,
			"wind_max": 5.5,
			"dogleg": [{"at": 225.0, "deg": 45.0}],
		},
		{
			"name": "Chew Toy",
			"par": 3,
			"tee": Vector2(0, 0),
			"pin": Vector2(-3, -133),
			"fairway": [Vector2(-4, -115), Vector2(-4, -119)],
			"fairway_hw": 9.0,
			"green": {"c": Vector2(-4, -135), "rx": 12.0, "rz": 10.0, "tilt": Vector2(0.018, 0.01), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(-19, -133), "rx": 4.0, "rz": 5.0}, {"c": Vector2(10, -145), "rx": 4.0, "rz": 4.0}, {"c": Vector2(-4, -150), "rx": 7.0, "rz": 3.0}, {"c": Vector2(9, -123), "rx": 3.0, "rz": 3.0}],
			"water": [],
			"islands": [],
			"waste": [],
			"rocks": [],
			"elev": -0.01,
			"seed": 1015,
			"wind_max": 6.5,
		},
		{
			"name": "Belly Rub Ridge",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(1, -378),
			"fairway": [Vector2(0, -30), Vector2(0, -130), Vector2(0, -230), Vector2(0, -356)],
			"fairway_hw": 16.0,
			"green": {"c": Vector2(0, -380), "rx": 14.0, "rz": 12.0, "tilt": Vector2(0.012, -0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(-16, -200), "rx": 5.0, "rz": 6.0}, {"c": Vector2(15, -262), "rx": 6.0, "rz": 4.0}, {"c": Vector2(-15, -376), "rx": 4.0, "rz": 5.0}, {"c": Vector2(13, -390), "rx": 5.0, "rz": 3.0}],
			"water": [],
			"islands": [],
			"waste": [],
			"rocks": [],
			"elev": 0.014,
			"seed": 1016,
			"wind_max": 5.5,
			"dogleg": [{"at": 230.0, "deg": -30.0}],
		},
		{
			"name": "Fire Hydrant",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(1, -328),
			"fairway": [Vector2(0, -30), Vector2(0, -130), Vector2(0, -230), Vector2(0, -306)],
			"fairway_hw": 15.0,
			"green": {"c": Vector2(0, -330), "rx": 14.0, "rz": 12.0, "tilt": Vector2(0.012, -0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(-15, -330), "rx": 4.0, "rz": 5.0}, {"c": Vector2(-14, -205), "rx": 6.0, "rz": 4.0}],
			"water": [{"c": Vector2(26, -318), "rx": 11.0, "rz": 20.0}],
			"islands": [],
			"waste": [],
			"rocks": [],
			"elev": 0.003,
			"seed": 1017,
			"wind_max": 5.5,
			"dogleg": [{"at": 210.0, "deg": 25.0}],
		},
		{
			"name": "Walkies Home",
			"par": 5,
			"tee": Vector2(0, 0),
			"pin": Vector2(1, -478),
			"fairway": [Vector2(0, -30), Vector2(0, -130), Vector2(0, -230), Vector2(0, -330), Vector2(0, -456)],
			"fairway_hw": 17.0,
			"green": {"c": Vector2(0, -480), "rx": 16.0, "rz": 13.0, "tilt": Vector2(0.012, -0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(-16, -220), "rx": 6.0, "rz": 4.0}, {"c": Vector2(15, -250), "rx": 5.0, "rz": 5.0}, {"c": Vector2(-16, -478), "rx": 4.0, "rz": 5.0}, {"c": Vector2(16, -470), "rx": 4.0, "rz": 5.0}],
			"water": [{"c": Vector2(0, -428), "rx": 32.0, "rz": 9.0}],
			"islands": [],
			"waste": [],
			"rocks": [],
			"elev": 0.004,
			"seed": 1018,
			"wind_max": 5.5,
			"dogleg": [{"at": 260.0, "deg": 30.0}],
		},
	]

static func _barking_paradise_back() -> Array:
	return [
		{
			"name": "Conch Shell",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(1, -338),
			"fairway": [Vector2(0, -30), Vector2(0, -130), Vector2(0, -230), Vector2(0, -316)],
			"fairway_hw": 16.0,
			"green": {"c": Vector2(0, -340), "rx": 14.0, "rz": 12.0, "tilt": Vector2(0.012, -0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(-15, -338), "rx": 4.0, "rz": 5.0}, {"c": Vector2(14, -350), "rx": 4.0, "rz": 3.0}],
			"water": [{"c": Vector2(0, -170), "rx": 70.0, "rz": 10.0}],
			"islands": [],
			"waste": [],
			"rocks": [],
			"elev": 0.003,
			"seed": 1110,
			"wind_max": 6.0,
			"dogleg": [{"at": 235.0, "deg": 30.0}],
		},
		{
			"name": "Turtle Island",
			"par": 3,
			"tee": Vector2(0, 0),
			"pin": Vector2(1, -148),
			"fairway": [Vector2(0, -133), Vector2(0, -136)],
			"fairway_hw": 6.0,
			"green": {"c": Vector2(0, -150), "rx": 12.0, "rz": 11.0, "tilt": Vector2(0.01, -0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(-13, -156), "rx": 3.0, "rz": 4.0}],
			"water": [{"c": Vector2(0, -128), "rx": 34.0, "rz": 42.0}],
			"islands": [{"c": Vector2(0, -150), "rx": 17.0, "rz": 15.0}],
			"waste": [],
			"rocks": [],
			"elev": 0,
			"seed": 1111,
			"wind_max": 7.0,
		},
		{
			"name": "Pirate's Plank",
			"par": 5,
			"tee": Vector2(0, 0),
			"pin": Vector2(1, -478),
			"fairway": [Vector2(0, -30), Vector2(0, -130), Vector2(0, -230), Vector2(0, -330), Vector2(0, -456)],
			"fairway_hw": 17.0,
			"green": {"c": Vector2(0, -480), "rx": 15.0, "rz": 13.0, "tilt": Vector2(0.012, -0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(16, -150), "rx": 5.0, "rz": 6.0}, {"c": Vector2(-16, -478), "rx": 4.0, "rz": 5.0}, {"c": Vector2(15, -488), "rx": 4.0, "rz": 3.0}],
			"water": [{"c": Vector2(0, -180), "rx": 70.0, "rz": 13.0}, {"c": Vector2(0, -330), "rx": 70.0, "rz": 32.0}],
			"islands": [{"c": Vector2(0, -330), "rx": 18.0, "rz": 12.0}],
			"waste": [],
			"rocks": [],
			"elev": 0.002,
			"seed": 1112,
			"wind_max": 5.5,
			"dogleg": [{"at": 400.0, "deg": -30.0}],
		},
		{
			"name": "Coral Reef",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(1, -348),
			"fairway": [Vector2(0, -30), Vector2(0, -130), Vector2(0, -230), Vector2(0, -326)],
			"fairway_hw": 16.0,
			"green": {"c": Vector2(0, -350), "rx": 14.0, "rz": 12.0, "tilt": Vector2(0.012, -0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(-15, -352), "rx": 4.0, "rz": 5.0}, {"c": Vector2(14, -360), "rx": 4.0, "rz": 4.0}],
			"water": [{"c": Vector2(32, -190), "rx": 12.0, "rz": 55.0}, {"c": Vector2(0, -318), "rx": 20.0, "rz": 6.0}],
			"islands": [],
			"waste": [],
			"rocks": [],
			"elev": 0.003,
			"seed": 1113,
			"wind_max": 6.0,
			"dogleg": [{"at": 220.0, "deg": -40.0}],
		},
		{
			"name": "Hammock Hollow",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(1, -318),
			"fairway": [Vector2(0, -30), Vector2(0, -130), Vector2(0, -230), Vector2(0, -296)],
			"fairway_hw": 16.0,
			"green": {"c": Vector2(0, -320), "rx": 14.0, "rz": 12.0, "tilt": Vector2(0.012, -0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(-15, -318), "rx": 4.0, "rz": 5.0}, {"c": Vector2(14, -330), "rx": 4.0, "rz": 3.0}],
			"water": [{"c": Vector2(0, -262), "rx": 60.0, "rz": 8.0}],
			"islands": [],
			"waste": [],
			"rocks": [],
			"elev": 0.004,
			"seed": 1114,
			"wind_max": 6.0,
			"dogleg": [{"at": 200.0, "deg": 35.0}],
		},
		{
			"name": "Mango Tango",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(1, -328),
			"fairway": [Vector2(0, -30), Vector2(0, -130), Vector2(0, -230), Vector2(0, -306)],
			"fairway_hw": 15.0,
			"green": {"c": Vector2(0, -330), "rx": 14.0, "rz": 12.0, "tilt": Vector2(0.012, -0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(16, -310), "rx": 4.0, "rz": 5.0}, {"c": Vector2(-14, -340), "rx": 4.0, "rz": 4.0}],
			"water": [{"c": Vector2(-34, -200), "rx": 12.0, "rz": 50.0}],
			"islands": [],
			"waste": [],
			"rocks": [],
			"elev": 0.003,
			"seed": 1115,
			"wind_max": 6.0,
			"dogleg": [{"at": 210.0, "deg": 30.0}],
		},
		{
			"name": "Sea Turtle Crossing",
			"par": 5,
			"tee": Vector2(0, 0),
			"pin": Vector2(1, -458),
			"fairway": [Vector2(0, -30), Vector2(0, -130), Vector2(0, -230), Vector2(0, -330), Vector2(0, -436)],
			"fairway_hw": 17.0,
			"green": {"c": Vector2(0, -460), "rx": 15.0, "rz": 13.0, "tilt": Vector2(0.012, -0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(-16, -458), "rx": 4.0, "rz": 5.0}, {"c": Vector2(16, -466), "rx": 4.0, "rz": 4.0}],
			"water": [{"c": Vector2(0, -260), "rx": 70.0, "rz": 55.0}],
			"islands": [{"c": Vector2(0, -255), "rx": 18.0, "rz": 16.0}],
			"waste": [],
			"rocks": [],
			"elev": 0.002,
			"seed": 1116,
			"wind_max": 5.5,
			"dogleg": [{"at": 340.0, "deg": 30.0}],
		},
		{
			"name": "Message in a Bottle",
			"par": 3,
			"tee": Vector2(0, 0),
			"pin": Vector2(-5, -130),
			"fairway": [Vector2(-6, -112), Vector2(-6, -116)],
			"fairway_hw": 8.0,
			"green": {"c": Vector2(-6, -132), "rx": 11.0, "rz": 10.0, "tilt": Vector2(0.015, -0.01), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(-20, -132), "rx": 3.0, "rz": 5.0}],
			"water": [{"c": Vector2(6, -100), "rx": 26.0, "rz": 16.0}, {"c": Vector2(20, -134), "rx": 7.0, "rz": 13.0}],
			"islands": [],
			"waste": [],
			"rocks": [],
			"elev": -0.004,
			"seed": 1117,
			"wind_max": 7.0,
		},
		{
			"name": "Paradise Found",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(1, -378),
			"fairway": [Vector2(0, -30), Vector2(0, -130), Vector2(0, -230), Vector2(0, -356)],
			"fairway_hw": 16.0,
			"green": {"c": Vector2(0, -380), "rx": 14.0, "rz": 12.0, "tilt": Vector2(0.012, -0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(-16, -376), "rx": 4.0, "rz": 5.0}, {"c": Vector2(-12, -392), "rx": 6.0, "rz": 3.0}],
			"water": [{"c": Vector2(0, -150), "rx": 70.0, "rz": 9.0}, {"c": Vector2(27, -375), "rx": 12.0, "rz": 20.0}],
			"islands": [],
			"waste": [],
			"rocks": [],
			"elev": 0.003,
			"seed": 1118,
			"wind_max": 6.0,
			"dogleg": [{"at": 230.0, "deg": -40.0}],
		},
	]

static func _kitty_litter_dunes_back() -> Array:
	return [
		{
			"name": "Scaredy Cat",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(1, -343),
			"fairway": [Vector2(0, -30), Vector2(0, -130), Vector2(0, -230), Vector2(0, -321)],
			"fairway_hw": 16.0,
			"green": {"c": Vector2(0, -345), "rx": 14.0, "rz": 12.0, "tilt": Vector2(0.012, -0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(-7, -200), "rx": 4.0, "rz": 5.0}, {"c": Vector2(10, -212), "rx": 4.0, "rz": 4.0}, {"c": Vector2(2, -250), "rx": 5.0, "rz": 3.0}, {"c": Vector2(-15, -342), "rx": 4.0, "rz": 5.0}, {"c": Vector2(14, -354), "rx": 4.0, "rz": 4.0}],
			"water": [],
			"islands": [],
			"waste": [{"c": Vector2(34, -150), "rx": 12.0, "rz": 40.0}],
			"rocks": [{"c": Vector2(-4, -165), "r": 1.0}, {"c": Vector2(6, -290), "r": 0.9}],
			"elev": 0.006,
			"seed": 2110,
			"wind_max": 5.0,
			"dogleg": [{"at": 228.0, "deg": -35.0}],
		},
		{
			"name": "Sandbox",
			"par": 3,
			"tee": Vector2(0, 0),
			"pin": Vector2(1, -148),
			"fairway": [Vector2(0, -129), Vector2(0, -133)],
			"fairway_hw": 9.0,
			"green": {"c": Vector2(0, -150), "rx": 13.0, "rz": 11.0, "tilt": Vector2(-0.012, -0.015), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(-17, -150), "rx": 4.0, "rz": 5.0}, {"c": Vector2(15, -158), "rx": 4.0, "rz": 4.0}, {"c": Vector2(0, -167), "rx": 7.0, "rz": 2.5}],
			"water": [],
			"islands": [],
			"waste": [{"c": Vector2(0, -78), "rx": 25.0, "rz": 40.0}],
			"rocks": [{"c": Vector2(9, -40), "r": 1.1}],
			"elev": -0.006,
			"seed": 2111,
			"wind_max": 6.0,
		},
		{
			"name": "Mirage",
			"par": 5,
			"tee": Vector2(0, 0),
			"pin": Vector2(1, -483),
			"fairway": [Vector2(0, -30), Vector2(0, -130), Vector2(0, -230), Vector2(0, -330), Vector2(0, -461)],
			"fairway_hw": 17.0,
			"green": {"c": Vector2(0, -485), "rx": 15.0, "rz": 13.0, "tilt": Vector2(0.012, -0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(-8, -196), "rx": 4.0, "rz": 5.0}, {"c": Vector2(10, -210), "rx": 4.0, "rz": 4.0}, {"c": Vector2(-6, -400), "rx": 4.0, "rz": 5.0}, {"c": Vector2(9, -412), "rx": 4.0, "rz": 4.0}, {"c": Vector2(-16, -483), "rx": 4.0, "rz": 5.0}, {"c": Vector2(15, -490), "rx": 4.0, "rz": 4.0}],
			"water": [],
			"islands": [],
			"waste": [{"c": Vector2(0, -300), "rx": 40.0, "rz": 12.0}],
			"rocks": [{"c": Vector2(3, -150), "r": 1.0}, {"c": Vector2(-5, -335), "r": 1.1}],
			"elev": 0.004,
			"seed": 2112,
			"wind_max": 5.0,
			"dogleg": [{"at": 220.0, "deg": 30.0}, {"at": 360.0, "deg": -35.0}],
		},
		{
			"name": "Gila Gulch",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(1, -328),
			"fairway": [Vector2(0, -30), Vector2(0, -130), Vector2(0, -230), Vector2(0, -306)],
			"fairway_hw": 15.0,
			"green": {"c": Vector2(0, -330), "rx": 14.0, "rz": 12.0, "tilt": Vector2(0.012, -0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(5, -205), "rx": 4.0, "rz": 5.0}, {"c": Vector2(-8, -228), "rx": 4.0, "rz": 4.0}, {"c": Vector2(-14, -330), "rx": 4.0, "rz": 5.0}, {"c": Vector2(14, -338), "rx": 4.0, "rz": 4.0}],
			"water": [],
			"islands": [],
			"waste": [{"c": Vector2(-26, -170), "rx": 9.0, "rz": 40.0}, {"c": Vector2(27, -250), "rx": 9.0, "rz": 35.0}],
			"rocks": [{"c": Vector2(-3, -140), "r": 0.9}, {"c": Vector2(4, -275), "r": 1.0}],
			"elev": 0.005,
			"seed": 2113,
			"wind_max": 5.0,
			"dogleg": [{"at": 240.0, "deg": 25.0}],
		},
		{
			"name": "Roadrunner",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(1, -393),
			"fairway": [Vector2(0, -30), Vector2(0, -130), Vector2(0, -230), Vector2(0, -330), Vector2(0, -371)],
			"fairway_hw": 16.0,
			"green": {"c": Vector2(0, -395), "rx": 14.0, "rz": 12.0, "tilt": Vector2(0.012, -0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(6, -205), "rx": 4.0, "rz": 5.0}, {"c": Vector2(-9, -222), "rx": 4.0, "rz": 4.0}, {"c": Vector2(2, -262), "rx": 4.0, "rz": 3.0}, {"c": Vector2(-15, -392), "rx": 4.0, "rz": 5.0}, {"c": Vector2(14, -402), "rx": 4.0, "rz": 4.0}],
			"water": [],
			"islands": [],
			"waste": [{"c": Vector2(30, -235), "rx": 12.0, "rz": 30.0}],
			"rocks": [{"c": Vector2(-5, -160), "r": 1.0}, {"c": Vector2(3, -330), "r": 1.1}],
			"elev": 0.006,
			"seed": 2114,
			"wind_max": 5.0,
			"dogleg": [{"at": 240.0, "deg": -45.0}],
		},
		{
			"name": "Tumble Dry",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(1, -328),
			"fairway": [Vector2(0, -30), Vector2(0, -130), Vector2(0, -230), Vector2(0, -306)],
			"fairway_hw": 16.0,
			"green": {"c": Vector2(0, -330), "rx": 14.0, "rz": 12.0, "tilt": Vector2(0.012, -0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(-6, -205), "rx": 4.0, "rz": 5.0}, {"c": Vector2(9, -222), "rx": 4.0, "rz": 4.0}, {"c": Vector2(-14, -328), "rx": 4.0, "rz": 5.0}],
			"water": [],
			"islands": [],
			"waste": [{"c": Vector2(0, -95), "rx": 22.0, "rz": 30.0}],
			"rocks": [{"c": Vector2(8, -60), "r": 1.0}, {"c": Vector2(-4, -255), "r": 0.9}],
			"elev": -0.012,
			"seed": 2115,
			"wind_max": 5.5,
			"dogleg": [{"at": 215.0, "deg": 30.0}],
		},
		{
			"name": "Coyote Crossing",
			"par": 5,
			"tee": Vector2(0, 0),
			"pin": Vector2(1, -468),
			"fairway": [Vector2(0, -30), Vector2(0, -130), Vector2(0, -230), Vector2(0, -330), Vector2(0, -446)],
			"fairway_hw": 17.0,
			"green": {"c": Vector2(0, -470), "rx": 15.0, "rz": 13.0, "tilt": Vector2(0.012, -0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(6, -195), "rx": 4.0, "rz": 5.0}, {"c": Vector2(-9, -215), "rx": 4.0, "rz": 4.0}, {"c": Vector2(-5, -330), "rx": 4.0, "rz": 4.0}, {"c": Vector2(8, -345), "rx": 4.0, "rz": 4.0}, {"c": Vector2(-16, -468), "rx": 4.0, "rz": 5.0}, {"c": Vector2(15, -476), "rx": 4.0, "rz": 4.0}],
			"water": [],
			"islands": [],
			"waste": [{"c": Vector2(0, -280), "rx": 45.0, "rz": 14.0}, {"c": Vector2(-33, -150), "rx": 11.0, "rz": 40.0}],
			"rocks": [{"c": Vector2(4, -240), "r": 1.0}, {"c": Vector2(-3, -400), "r": 1.1}],
			"elev": 0.003,
			"seed": 2116,
			"wind_max": 5.5,
			"dogleg": [{"at": 360.0, "deg": 30.0}],
		},
		{
			"name": "Dust Bowl",
			"par": 3,
			"tee": Vector2(0, 0),
			"pin": Vector2(1, -133),
			"fairway": [Vector2(0, -115), Vector2(0, -119)],
			"fairway_hw": 8.0,
			"green": {"c": Vector2(0, -135), "rx": 11.0, "rz": 10.0, "tilt": Vector2(0.015, 0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(-15, -133), "rx": 3.0, "rz": 5.0}, {"c": Vector2(13, -140), "rx": 3.0, "rz": 4.0}, {"c": Vector2(0, -149), "rx": 6.0, "rz": 2.5}, {"c": Vector2(11, -122), "rx": 3.0, "rz": 3.0}],
			"water": [],
			"islands": [],
			"waste": [{"c": Vector2(0, -78), "rx": 20.0, "rz": 30.0}],
			"rocks": [],
			"elev": -0.006,
			"seed": 2117,
			"wind_max": 6.5,
		},
		{
			"name": "Cat Nap Canyon",
			"par": 4,
			"tee": Vector2(0, 0),
			"pin": Vector2(1, -398),
			"fairway": [Vector2(0, -30), Vector2(0, -130), Vector2(0, -230), Vector2(0, -330), Vector2(0, -376)],
			"fairway_hw": 16.0,
			"green": {"c": Vector2(0, -400), "rx": 14.0, "rz": 12.0, "tilt": Vector2(0.012, -0.012), "und": 0.05, "raise": 0.8},
			"bunkers": [{"c": Vector2(6, -205), "rx": 4.0, "rz": 5.0}, {"c": Vector2(-8, -222), "rx": 4.0, "rz": 4.0}, {"c": Vector2(4, -258), "rx": 5.0, "rz": 3.0}, {"c": Vector2(-15, -398), "rx": 4.0, "rz": 5.0}, {"c": Vector2(14, -408), "rx": 4.0, "rz": 4.0}],
			"water": [],
			"islands": [],
			"waste": [{"c": Vector2(-30, -170), "rx": 10.0, "rz": 40.0}],
			"rocks": [{"c": Vector2(-3, -150), "r": 1.0}, {"c": Vector2(5, -320), "r": 1.0}],
			"elev": 0.01,
			"seed": 2118,
			"wind_max": 5.0,
			"dogleg": [{"at": 240.0, "deg": -30.0}],
		},
	]

static func hole_count(course_index: int = -1) -> int:
	return holes(course_index).size()

static func hole_length_m(hole: Dictionary) -> float:
	# Distance along tee -> fairway -> pin.
	var pts: Array = [hole["tee"]]
	pts.append_array(hole["fairway"])
	pts.append(hole["pin"])
	var total := 0.0
	for i in range(1, pts.size()):
		total += (pts[i] as Vector2).distance_to(pts[i - 1])
	return total
