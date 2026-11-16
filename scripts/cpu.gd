class_name CpuPlayer
extends RefCounted
## Computer opponent for Match Play. It plans a shot the way a player would
## (club, aim, power) by solving against the real ball physics, then adds
## skill-based mistakes from Game.CPU_SKILL: power and aim spread, a timing
## spread on the accuracy click, only partly allowing for the wind, putting
## spread and the occasional proper blunder.

var r: Round
var skill: Dictionary
var rng := RandomNumberGenerator.new()
var _sim: Ball

func _init(round_node: Round, character_id: String) -> void:
	r = round_node
	skill = Game.CPU_SKILL.get(character_id, Game.CPU_SKILL["bacon"])
	rng.randomize()

## Called on the CPU's turn after the round has auto-picked club and aim.
## Adjusts r.aim_yaw / r.club / r.special_armed and returns
## {"power": 0..1, "accuracy": click timing (0 = perfect)}.
func plan() -> Dictionary:
	var b: Ball = r.balls[r.current]
	if r._is_putter():
		return _plan_putt(b)
	return _plan_full(b)

# ------------------------------------------------------------ full shots ---
func _plan_full(b: Ball) -> Dictionary:
	var pin := r.terrain.pin_pos3()
	var to_pin := Round._flat_dist(b.position, pin)
	var going_for_pin := r.layup_dist <= 0.0 and Round._flat_dist(r.aim_target, pin) < 1.0
	_maybe_special(b, going_for_pin, to_pin)
	var bubble := r.special_armed and r._special_id() == "bubble"
	var land := r.aim_target
	if going_for_pin:
		# land short of the flag and let it release
		var roll := clampf(to_pin * (0.08 if r.club >= 4 else 0.13), 1.5, 18.0)
		if bubble:
			roll += 16.0  # the bubble's splash-hop carries it on
		var d := Round._dir_to(pin, b.position)
		land = pin + d * minf(roll, to_pin * 0.5)
	var wind_used: Vector3 = Vector3.ZERO if bubble else r.wind * float(skill["wind"])
	var power := _solve(b, land, wind_used)
	# out of reach at full power? go up a club (twice at most)
	var tries := 0
	while power >= 0.995 and tries < 2 and r.club > (0 if b.lie() == CourseTerrain.Surface.TEE else 1):
		var shot := r._compute_shot(1.0, 0.0)
		var p := Ball.predict_carry(r.terrain, b.position, shot["v"], shot["spin"], wind_used)
		if Round._flat_dist(b.position, p) >= Round._flat_dist(b.position, land) * 0.97:
			break
		r.club -= 1
		power = _solve(b, land, wind_used)
		tries += 1
	# human error
	var acc_sd := float(skill["acc_sd"])
	if r.special_armed and r._special_id() == "puppy_eyes":
		acc_sd *= 0.4   # the slow meter makes the click easy
	power = clampf(power * (1.0 + rng.randfn(0.0, float(skill["power_sd"]))), 0.03, 1.0)
	r.aim_yaw += deg_to_rad(rng.randfn(0.0, float(skill["aim_sd"])))
	var acc := rng.randfn(0.0, acc_sd)
	if rng.randf() < float(skill["blunder"]):
		acc = rng.randf_range(0.7, 1.3) * (1.0 if rng.randf() < 0.5 else -1.0)
		power = clampf(power * rng.randf_range(0.82, 1.0), 0.03, 1.0)
	return {"power": power, "accuracy": clampf(acc, -1.4, 1.4)}

## Iterate power and aim until the predicted (un-mishit) landing hits `land`.
func _solve(b: Ball, land: Vector3, wind_used: Vector3) -> float:
	var want_vec := Vector3(land.x - b.position.x, 0, land.z - b.position.z)
	var want := want_vec.length()
	r.aim_yaw = atan2(-want_vec.x, -want_vec.z)
	var power := clampf(want / maxf(1.0, r._club_carry_m(r.club, b.lie())), 0.03, 1.0)
	for it in 6:
		var shot := r._compute_shot(power, 0.0)
		var p := Ball.predict_carry(r.terrain, b.position, shot["v"], shot["spin"], wind_used)
		var fwd := want_vec.normalized()
		var right := fwd.cross(Vector3.UP)
		var got_vec := Vector3(p.x - b.position.x, 0, p.z - b.position.z)
		var got := got_vec.dot(fwd)
		var lateral := got_vec.dot(right)
		if got > 1.0:
			power = clampf(power * want / got, 0.03, 1.0)
			r.aim_yaw += atan2(lateral, got)
	return power

func _maybe_special(b: Ball, going_for_pin: bool, to_pin: float) -> void:
	var left := int(Game.players[r.current]["special_left"])
	if left <= 0 or r.special_armed:
		return
	var lie := b.lie()
	match r._special_id():
		"dig_in":
			if lie == CourseTerrain.Surface.ROUGH or lie == CourseTerrain.Surface.BUNKER or lie == CourseTerrain.Surface.WASTE:
				r.special_armed = true
				# better lie -> maybe less club
				r.club = r._auto_club(to_pin, lie)
				r._auto_aim()
		"bubble":
			if r.wind.length() > 3.5 and to_pin > 110.0 and r.layup_dist <= 0.0:
				r.special_armed = true
		"puppy_eyes":
			if going_for_pin and to_pin < 170.0 and rng.randf() < 0.5:
				r.special_armed = true
		"zoomies":
			if lie == CourseTerrain.Surface.TEE and int(r.hole["par"]) == 5:
				r.special_armed = true
				r._auto_aim()
		"reflexes":
			if going_for_pin and rng.randf() < 0.4:
				r.special_armed = true

# ---------------------------------------------------------------- putts ---
func _plan_putt(b: Ball) -> Dictionary:
	var pin := r.terrain.pin_pos3()
	var dist := Round._flat_dist(b.position, pin)
	if _sim == null:
		_sim = Ball.new(r.terrain, Color.WHITE)
	var to_pin := Round._dir_to(b.position, pin)
	var yaw := atan2(-to_pin.x, -to_pin.z)
	var d := dist * 1.1 + 0.3
	for it in 6:
		var res := _sim_putt(b.position, yaw, d, pin, to_pin)
		if res["holed"]:
			break
		yaw += atan2(float(res["lateral"]), maxf(dist, 0.5))
		var past: float = res["past"]
		d = clampf(d * clampf((dist + 0.4) / maxf(0.3, dist + past), 0.7, 1.4), 0.2, 40.0)
	# human error: longer putts are harder to judge
	yaw += deg_to_rad(rng.randfn(0.0, float(skill["putt_aim"])))
	d *= 1.0 + rng.randfn(0.0, float(skill["putt_sd"]) * clampf(0.5 + dist / 12.0, 0.5, 1.6))
	d = maxf(d, 0.2)
	r.aim_yaw = yaw
	for rr in Round.PUTTER_RANGES:
		r._putter_range = rr
		if float(rr) >= d:
			break
	return {"power": clampf(d / r._putter_range, 0.01, 1.0), "accuracy": 0.0}

## Roll a ghost ball and report: holed, signed miss to the right at the
## closest approach, and how far past the hole (along the line) it stopped.
func _sim_putt(start: Vector3, yaw: float, d: float, pin: Vector3, line: Vector3) -> Dictionary:
	var dir := Vector3(-sin(yaw), 0, -cos(yaw))
	_sim.result = ""
	_sim.position = start
	_sim.putt(dir * sqrt(2.0 * Round.GREEN_ROLL * d))
	var best := INF
	var best_pos := start
	var steps := 0
	while _sim.is_moving() and steps < 900:
		_sim._step(1.0 / 60.0)
		var dd := Round._flat_dist(_sim.position, pin)
		if dd < best:
			best = dd
			best_pos = _sim.position
		steps += 1
	var right := line.cross(Vector3.UP)
	var off := Vector3(best_pos.x - pin.x, 0, best_pos.z - pin.z)
	var end_off := Vector3(_sim.position.x - pin.x, 0, _sim.position.z - pin.z)
	return {"holed": _sim.result == "holed", "lateral": off.dot(right), "past": end_off.dot(line)}
