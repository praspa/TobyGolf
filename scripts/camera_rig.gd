class_name CameraRig
extends Camera3D
## Mostly-fixed golf camera with a few modes and a small zoom adjustment.

enum Mode { AIM, OVERVIEW, FOLLOW, MANUAL }

var terrain: CourseTerrain
var mode := Mode.AIM
var ball: Ball
var aim_dir := Vector3.FORWARD
var putting := false
var overview_target := Vector3.ZERO
var zoom := 1.0
var manual_pos := Vector3.ZERO
var manual_look := Vector3.ZERO
var smooth := 5.0
var _look := Vector3.ZERO
var _follow_dir := Vector3.FORWARD

func _init(t: CourseTerrain) -> void:
	terrain = t
	fov = 62.0
	near = 0.05
	far = 3000.0

func snap() -> void:
	var d := _desired()
	global_position = d[0]
	_look = d[1]
	_safe_look_at(_look)

func set_aim(b: Ball, dir: Vector3, is_putting: bool) -> void:
	ball = b
	aim_dir = Vector3(dir.x, 0, dir.z).normalized()
	putting = is_putting
	mode = Mode.AIM
	smooth = 6.0

func set_overview(target: Vector3) -> void:
	overview_target = target
	mode = Mode.OVERVIEW
	smooth = 3.0

func set_follow(b: Ball, dir: Vector3) -> void:
	ball = b
	_follow_dir = Vector3(dir.x, 0, dir.z).normalized()
	mode = Mode.FOLLOW
	smooth = 3.5

func set_manual(p: Vector3, look: Vector3, s: float = 4.0) -> void:
	manual_pos = p
	manual_look = look
	mode = Mode.MANUAL
	smooth = s

func adjust_zoom(amount: float) -> void:
	zoom = clampf(zoom + amount, 0.6, 1.8)

func _desired() -> Array:
	var p := global_position
	var look := _look
	match mode:
		Mode.AIM:
			if ball:
				var b := ball.position
				if putting:
					p = b - aim_dir * 3.4 * zoom + Vector3.UP * 1.7 * zoom
					look = b + aim_dir * 4.0
				else:
					p = b - aim_dir * 5.2 * zoom + Vector3.UP * 2.9 * zoom
					look = b + aim_dir * 20.0 + Vector3.UP * 0.3
		Mode.OVERVIEW:
			var from := ball.position if ball else overview_target
			var dist := from.distance_to(overview_target)
			var dir := (overview_target - from)
			dir.y = 0
			dir = dir.normalized() if dir.length() > 0.01 else aim_dir
			p = overview_target - dir * (12.0 + dist * 0.15) + Vector3.UP * (18.0 + dist * 0.18) * zoom
			look = overview_target
		Mode.FOLLOW:
			if ball:
				var b := ball.position
				var hv := Vector3(ball.vel.x, 0, ball.vel.z)
				if hv.length() > 2.0:
					_follow_dir = _follow_dir.lerp(hv.normalized(), 0.05).normalized()
				p = b - _follow_dir * 9.0 * zoom + Vector3.UP * 3.5 * zoom
				look = b
		Mode.MANUAL:
			p = manual_pos
			look = manual_look
	var gh := terrain.height(p.x, p.z) + 1.0
	if p.y < gh:
		p.y = gh
	return [p, look]

func _process(delta: float) -> void:
	var d := _desired()
	var k := 1.0 - exp(-smooth * delta)
	global_position = global_position.lerp(d[0], k)
	_look = _look.lerp(d[1], minf(1.0, k * 1.6))
	_safe_look_at(_look)

func _safe_look_at(target: Vector3) -> void:
	var to := target - global_position
	if to.length() < 0.01:
		return
	var up := Vector3.UP
	if absf(to.normalized().dot(up)) > 0.99:
		up = Vector3.FORWARD
	look_at(target, up)
