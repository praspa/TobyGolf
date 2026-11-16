class_name Ball
extends Node3D
## Golf ball: flight with drag, Magnus lift/curve from spin and wind, bounces
## and rolling that depend on the surface, green slope, cup capture and lip-outs,
## tree collisions, water and out-of-bounds detection.

signal finished(outcome: String)
signal bubble_popped(pos: Vector3)   # Dorothy's bubble hit the ground / water
signal landed(surface: int, speed: float) # first touchdown of a shot (for sounds)
signal tree_hit(kind: String, solid: bool)  # solid = trunk/cactus, else branches/fronds

const G := 9.81
const KD := 0.0040        # drag   a = -KD * |v| * v
const KM := 0.00042       # Magnus a =  KM * (spin x v)
const SPIN_TAU := 7.0     # seconds for spin to decay by 1/e
const DT := 1.0 / 120.0
const RPM := TAU / 60.0
const CUP_R := 0.11       # generous, video-game sized cup
const CUP_CAPTURE_SPEED := 1.9
const CUP_LIP_SPEED := 3.2
const VISUAL_R := 0.075

enum State { REST, FLIGHT, ROLL, DONE }

var terrain: CourseTerrain
var state := State.REST
var vel := Vector3.ZERO
var spin := Vector3.ZERO     # rad/s
var wind := Vector3.ZERO
var roll_mult := 1.0         # <1 = extra roll (special shot / topspin)
var time_in_motion := 0.0
var bounces := 0
var max_height := 0.0
var start_pos := Vector3.ZERO
var last_dry_pos := Vector3.ZERO
var result := ""
var lipped := false
var tree_cooldown := 0.0
var on_tee := false
var hit_tree := false       # touched a tree this shot (for Zero's Nine Lives)
var stick := false          # pin seeker: kill most speed on first landing
var bubble := false         # Dorothy's Bubble Shot: splash-bounce forward on landing

var _bubble_mesh: MeshInstance3D

var _mesh: MeshInstance3D
var _shadow: MeshInstance3D
var _ring: MeshInstance3D
var _trail: MeshInstance3D
var _trail_pts: Array = []
var _trail_mesh := ImmediateMesh.new()

func _init(t: CourseTerrain, marker_color: Color) -> void:
	terrain = t
	_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = VISUAL_R
	sm.height = VISUAL_R * 2.0
	sm.radial_segments = 8
	sm.rings = 4
	_mesh.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.35, 0.35)
	_mesh.material_override = mat
	add_child(_mesh)
	_shadow = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = VISUAL_R * 1.1
	cm.bottom_radius = VISUAL_R * 1.1
	cm.height = 0.005
	cm.radial_segments = 8
	_shadow.mesh = cm
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0, 0, 0, 0.45)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow.material_override = smat
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)
	# Coloured ring so each player's ball is easy to find.
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.22
	tm.outer_radius = 0.3
	tm.rings = 10
	tm.ring_segments = 4
	_ring.mesh = tm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = marker_color
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.material_override = rmat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_bubble_mesh = MeshInstance3D.new()
	var bsm := SphereMesh.new()
	bsm.radius = 0.32
	bsm.height = 0.64
	bsm.radial_segments = 12
	bsm.rings = 6
	_bubble_mesh.mesh = bsm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.55, 0.85, 1.0, 0.35)
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.emission_enabled = true
	bmat.emission = Color(0.2, 0.45, 0.6)
	bmat.metallic_specular = 1.0
	bmat.roughness = 0.05
	_bubble_mesh.material_override = bmat
	_bubble_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bubble_mesh.visible = false
	_mesh.add_child(_bubble_mesh)
	_trail = MeshInstance3D.new()
	_trail.mesh = _trail_mesh
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(1, 1, 1, 0.8)
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail.material_override = tmat
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail.top_level = true

func _ready() -> void:
	add_child(_trail)
	_trail.global_transform = Transform3D.IDENTITY

func place(p: Vector3) -> void:
	var h := terrain.height(p.x, p.z)
	on_tee = terrain.surface(p.x, p.z) == CourseTerrain.Surface.TEE
	position = Vector3(p.x, h, p.z)
	state = State.REST
	vel = Vector3.ZERO
	spin = Vector3.ZERO
	_update_visual()

func ground_pos() -> Vector3:
	return Vector3(position.x, terrain.height(position.x, position.z), position.z)

func lie() -> int:
	return terrain.surface(position.x, position.z)

func set_marker_visible(v: bool) -> void:
	_ring.visible = v

func clear_trail() -> void:
	_trail_pts.clear()
	_trail_mesh.clear_surfaces()

# ------------------------------------------------------------- launching ---
func set_bubble(on: bool) -> void:
	bubble = on
	_bubble_mesh.visible = on

func launch(v: Vector3, s: Vector3, w: Vector3, extra_roll: float = 1.0, sticky: bool = false) -> void:
	set_bubble(false)
	stick = sticky
	hit_tree = false
	start_pos = position
	last_dry_pos = position
	vel = v
	spin = s
	wind = w
	roll_mult = extra_roll
	time_in_motion = 0.0
	bounces = 0
	max_height = position.y
	result = ""
	lipped = false
	tree_cooldown = 0.0
	clear_trail()
	position.y += 0.02
	state = State.FLIGHT

func putt(v: Vector3) -> void:
	hit_tree = false
	stick = false
	start_pos = position
	last_dry_pos = position
	var n := terrain.normal_at(position.x, position.z)
	vel = v - n * v.dot(n)
	spin = Vector3.ZERO
	wind = Vector3.ZERO
	roll_mult = 1.0
	time_in_motion = 0.0
	bounces = 0
	result = ""
	lipped = false
	clear_trail()
	state = State.ROLL

func is_moving() -> bool:
	return state == State.FLIGHT or state == State.ROLL

# --------------------------------------------------------------- physics ---
func _physics_process(delta: float) -> void:
	if not is_moving():
		return
	var steps := maxi(1, int(round(delta / DT)))
	for i in steps:
		if not is_moving():
			break
		_step(DT)
	_update_visual()
	if state == State.FLIGHT:
		_trail_pts.append(position)
		if _trail_pts.size() > 400:
			_trail_pts.pop_front()
		_draw_trail()

static func flight_accel(v: Vector3, s: Vector3, w: Vector3) -> Vector3:
	var vr := v - w
	return Vector3(0, -G, 0) - vr * (KD * vr.length()) + s.cross(vr) * KM

func _step(dt: float) -> void:
	time_in_motion += dt
	tree_cooldown = maxf(0.0, tree_cooldown - dt)
	if state == State.FLIGHT:
		_step_flight(dt)
	elif state == State.ROLL:
		_step_roll(dt)
	if time_in_motion > 40.0 and is_moving():
		_finish("rest")
	# far outside the map: stop early
	if is_moving() and not terrain.bounds.grow(120.0).has_point(Vector2(position.x, position.z)):
		_finish("oob")

func _step_flight(dt: float) -> void:
	vel += flight_accel(vel, spin, wind) * dt
	position += vel * dt
	spin *= exp(-dt / SPIN_TAU)
	max_height = maxf(max_height, position.y)
	_check_trees()
	_check_rocks()
	var h := terrain.height(position.x, position.z)
	if position.y > h:
		if terrain.surface(position.x, position.z) != CourseTerrain.Surface.WATER:
			last_dry_pos = Vector3(position.x, h, position.z)
		return
	# --- ground contact ---
	position.y = h
	if bubble:
		_bubble_splash(h)
		return
	var s := terrain.surface(position.x, position.z)
	if bounces == 0:
		landed.emit(s, vel.length())
	if s == CourseTerrain.Surface.WATER:
		_finish("water")
		return
	var pin := terrain.pin_pos3()
	var hd := Vector2(position.x - pin.x, position.z - pin.z).length()
	if hd < CUP_R * 1.15 and Vector2(vel.x, vel.z).length() < 9.0:
		_finish("holed")
		return
	var info := terrain.surf_info(s)
	var n := terrain.normal_at(position.x, position.z)
	if stick:
		stick = false
		vel *= 0.12
		spin = Vector3.ZERO
	var vn := vel.dot(n)
	var vt := vel - n * vn
	var vn_out := -vn * float(info["e"])
	vt *= float(info["keep"])
	# backspin bites on landing (wedges check up / spin back)
	var hv := Vector3(vt.x, 0, vt.z)
	if hv.length() > 0.01:
		var d := hv.normalized()
		var back := spin.dot(d.cross(Vector3.UP).normalized())
		var bite := maxf(0.0, back) * 0.006 * float(info["grab"])
		bite = minf(bite, vt.length() * 1.25)
		vt -= d * bite
	spin *= 0.4
	bounces += 1
	if vn_out < 1.2 or bounces > 8:
		vel = vt
		state = State.ROLL
	else:
		vel = vt + n * vn_out
		position += n * 0.01
	last_dry_pos = position

## The bubble bursts on touchdown (on land or on the water's surface) and
## springs the ball forward in a fresh hop.
func _bubble_splash(h: float) -> void:
	set_bubble(false)
	var w := terrain.water_at(position.x, position.z)
	var y := h
	if not w.is_empty():
		y = maxf(h, float(w["level"]))
	position.y = y + 0.06
	var hv := Vector3(vel.x, 0, vel.z)
	var spd := hv.length()
	var fwd := hv / spd if spd > 0.01 else Vector3.FORWARD
	vel = fwd * clampf(spd * 0.55, 5.0, 16.0) + Vector3.UP * clampf(spd * 0.22, 3.0, 6.0)
	spin = Vector3.ZERO
	bubble_popped.emit(Vector3(position.x, y, position.z))

func _step_roll(dt: float) -> void:
	var s := terrain.surface(position.x, position.z)
	if s == CourseTerrain.Surface.WATER:
		_finish("water")
		return
	last_dry_pos = position
	var info := terrain.surf_info(s)
	var decel: float = float(info["roll"]) * roll_mult
	var n := terrain.normal_at(position.x, position.z)
	var g := Vector3(0, -G, 0)
	var gt := g - n * g.dot(n)
	var speed := vel.length()
	# cup
	var pin := terrain.pin_pos3()
	var to_pin := Vector2(position.x - pin.x, position.z - pin.z)
	if to_pin.length() < CUP_R:
		if speed < CUP_CAPTURE_SPEED:
			_finish("holed")
			return
		elif speed < CUP_LIP_SPEED and not lipped:
			lipped = true
			var ang := randf_range(-0.7, 0.7)
			vel = vel.rotated(Vector3.UP, ang) * 0.6
			speed = vel.length()
	elif to_pin.length() > CUP_R * 2.0:
		lipped = false
	if speed < 0.06:
		if gt.length() < decel * 1.05:
			_finish("rest")
			return
		vel += gt * dt
	else:
		var dir := vel / speed
		var new_speed_vec := vel + gt * dt - dir * decel * dt
		# don't let friction reverse the ball by itself
		if new_speed_vec.dot(dir) < 0.0 and gt.length() < decel:
			vel = Vector3.ZERO
		else:
			vel = new_speed_vec
	vel -= n * vel.dot(n)
	position += vel * dt
	position.y = terrain.height(position.x, position.z)
	_check_rocks()

func _check_trees() -> void:
	if tree_cooldown > 0.0:
		return
	for t in terrain.trees:
		var p: Vector3 = t["p"]
		var dx := position.x - p.x
		var dz := position.z - p.z
		var r: float = t["r"]
		var dist2 := dx * dx + dz * dz
		if dist2 > r * r:
			continue
		var y := position.y - p.y
		var top: float = t["top"]
		var trunk: float = t["trunk"]
		if y > top or y < 0.0:
			continue
		var dist := sqrt(dist2)
		var kind: String = t.get("kind", "pine")
		if kind == "cactus":
			# solid column: ping off it
			_bounce_off(Vector3(dx, 0, dz), 0.45)
			tree_cooldown = 0.15
			hit_tree = true
			tree_hit.emit(kind, true)
			return
		if y < trunk or (kind == "palm" and y < trunk - 0.5):
			if dist < (0.3 if kind == "palm" else 0.35):
				_bounce_off(Vector3(dx, 0, dz), 0.5)
				tree_cooldown = 0.15
				hit_tree = true
				tree_hit.emit(kind, true)
			continue
		var rr := r
		if kind == "pine":
			rr = r * (1.0 - (y - trunk) / (top - trunk))
		if dist < rr:
			# rattled through the branches / fronds
			var sp := vel.length() * randf_range(0.15, 0.35)
			vel = Vector3(randf_range(-1, 1), randf_range(-0.6, 0.2), randf_range(-1, 1)).normalized() * sp
			spin *= 0.2
			tree_cooldown = 0.25
			hit_tree = true
			tree_hit.emit(kind, false)
			return

## Boulders: the ball can't pass through them in the air or on the ground.
func _check_rocks() -> void:
	for rk in terrain.rocks:
		var p: Vector3 = rk["p"]
		var r: float = rk["r"]
		var off := Vector3(position.x - p.x, 0, position.z - p.z)
		if off.length() >= r or position.y > p.y + float(rk["h"]):
			continue
		var n := off.normalized() if off.length() > 0.001 else Vector3.BACK
		position.x = p.x + n.x * r * 1.02
		position.z = p.z + n.z * r * 1.02
		if state == State.ROLL:
			position.y = terrain.height(position.x, position.z)
		_bounce_off(n, 0.55)
		hit_tree = true # counts as "trouble" for Nine Lives too

func _bounce_off(normal_h: Vector3, restitution: float) -> void:
	var n := Vector3(normal_h.x, 0, normal_h.z).normalized()
	if vel.dot(n) < 0.0:
		vel = vel.bounce(n) * restitution

func _finish(r: String) -> void:
	result = r
	if r == "rest" and terrain.surface(position.x, position.z) == CourseTerrain.Surface.OOB:
		result = "oob"
	vel = Vector3.ZERO
	state = State.DONE
	_update_visual()
	finished.emit(result)

# --------------------------------------------------------------- visuals ---
func _update_visual() -> void:
	var gh := terrain.height(position.x, position.z)
	var lift := VISUAL_R
	if state == State.REST and on_tee:
		lift += 0.04
	if result == "holed":
		lift = -0.12
	_mesh.position = Vector3(0, maxf(position.y, gh) - position.y + lift, 0)
	_shadow.position = Vector3(0, gh - position.y + 0.01, 0)
	_shadow.visible = result != "holed"
	_ring.position = _shadow.position
	_mesh.visible = result != "water"

func _draw_trail() -> void:
	_trail_mesh.clear_surfaces()
	if _trail_pts.size() < 2:
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in _trail_pts:
		_trail_mesh.surface_add_vertex(p + Vector3(0, VISUAL_R, 0))
	_trail_mesh.surface_end()

# ------------------------------------------------------- shot prediction ---
## Simulate a flight over the terrain (no trees) and return the first landing point.
static func predict_carry(t: CourseTerrain, p: Vector3, v: Vector3, s: Vector3, w: Vector3, out_points: Array = [], dt: float = 1.0 / 60.0) -> Vector3:
	var pos := p + Vector3(0, 0.02, 0)
	var vv := v
	var ss := s
	var max_steps := int(15.0 / dt)
	for i in max_steps:
		vv += flight_accel(vv, ss, w) * dt
		pos += vv * dt
		ss *= exp(-dt / SPIN_TAU)
		if i % maxi(1, int(0.1 / dt)) == 0:
			out_points.append(pos)
		var h := t.height(pos.x, pos.z)
		if pos.y <= h and i > 2:
			return Vector3(pos.x, h, pos.z)
	return pos

## Carry on flat ground (no wind) for a ball speed, launch angle (deg) and backspin (rpm).
static func flat_carry(speed: float, launch_deg: float, spin_rpm: float) -> float:
	var a := deg_to_rad(launch_deg)
	var v := Vector3(0, sin(a), -cos(a)) * speed
	var s := Vector3(1, 0, 0) * spin_rpm * RPM # backspin axis for travel along -Z
	var p := Vector3.ZERO
	var dt := 1.0 / 60.0
	for i in 1200:
		v += flight_accel(v, s, Vector3.ZERO) * dt
		p += v * dt
		s *= exp(-dt / SPIN_TAU)
		if p.y < 0.0 and i > 2:
			return -p.z
	return -p.z

## Ball speed needed to carry `carry_m` on flat ground.
static func solve_speed(carry_m: float, launch_deg: float, spin_rpm: float) -> float:
	var lo := 2.0
	var hi := 130.0
	for i in 22:
		var mid := (lo + hi) * 0.5
		if flat_carry(mid, launch_deg, spin_rpm) < carry_m:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5
