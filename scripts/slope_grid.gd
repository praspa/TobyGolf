class_name SlopeGrid
extends Node3D
## Putting-green read, squared to the putting direction:
## - Grid lines are laid out in the aim frame (one set runs along the putt
##   line, one across it) and drape over the green's contours. The grid is
##   rebuilt as the aim changes.
## - Each line is coloured by the slope *along that line*:
##   green = flat, yellow = mild, red = dramatic.
## - Slope markers travel along the grid lines (never free-form): each one
##   slides downhill along its own line, faster on steeper sections, so lines
##   along the putt show uphill/downhill and lines across it show the break.
## - Only the area around the putt is drawn: from just behind the ball to a
##   little past the putt length, and a few metres either side.
## Everything is low-opacity so the green stays visible.

const SPACING := 1.0       # metres between grid lines
const SEG := 0.5           # strip segment length (follows the terrain)
const LIFT := 0.025        # sit just above the turf
const LINE_W := 0.035      # strip width in metres
const LINE_ALPHA := 0.28
const LUT_STEP := 0.25     # resolution of the pre-sampled height/gradient lookup

const FLAT_C := Color(0.3, 1.0, 0.35)
const MILD_C := Color(1.0, 0.92, 0.2)
const STEEP_C := Color(1.0, 0.22, 0.18)
const FLAT := 0.005        # below this (0.5%) a line reads as flat
const MILD := 0.015        # ~1.5% = clearly yellow
const DRAMATIC := 0.03     # 3%+ = full red

var terrain: CourseTerrain
var _lines: MeshInstance3D
var _dots: MultiMeshInstance3D
var _dot_data: Array = []
var _t := 0.0

# pre-sampled lookup over the green's bounding box
var _lut_origin := Vector2.ZERO
var _lut_w := 0
var _lut_h := 0
var _lut_height := PackedFloat32Array()
var _lut_gx := PackedFloat32Array()
var _lut_gz := PackedFloat32Array()

var _aim_origin := Vector3(INF, 0, 0)
var _aim_dir := Vector3.FORWARD
var _length := 10.0
var _dirty := false

func _init(t: CourseTerrain) -> void:
	terrain = t
	_build_lut()
	_lines = MeshInstance3D.new()
	_lines.material_override = _overlay_material()
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lines)
	var quad := PlaneMesh.new()
	quad.size = Vector2(0.07, 0.18)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	_dots = MultiMeshInstance3D.new()
	_dots.multimesh = mm
	_dots.material_override = _overlay_material()
	_dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dots)

# ------------------------------------------------------------- lookup ---
func _build_lut() -> void:
	var g: Dictionary = terrain.green
	var c: Vector2 = g["c"]
	var rx: float = float(g["rx"]) * 1.25
	var rz: float = float(g["rz"]) * 1.25
	_lut_origin = Vector2(c.x - rx, c.y - rz)
	_lut_w = int(ceil(rx * 2.0 / LUT_STEP)) + 1
	_lut_h = int(ceil(rz * 2.0 / LUT_STEP)) + 1
	var count := _lut_w * _lut_h
	_lut_height.resize(count)
	_lut_gx.resize(count)
	_lut_gz.resize(count)
	for j in _lut_h:
		for i in _lut_w:
			var x := _lut_origin.x + i * LUT_STEP
			var z := _lut_origin.y + j * LUT_STEP
			_lut_height[j * _lut_w + i] = terrain.height(x, z)
	# gradient by central differences on the lookup itself
	for j in _lut_h:
		for i in _lut_w:
			var i0 := maxi(i - 1, 0)
			var i1 := mini(i + 1, _lut_w - 1)
			var j0 := maxi(j - 1, 0)
			var j1 := mini(j + 1, _lut_h - 1)
			_lut_gx[j * _lut_w + i] = (_lut_height[j * _lut_w + i1] - _lut_height[j * _lut_w + i0]) / ((i1 - i0) * LUT_STEP)
			_lut_gz[j * _lut_w + i] = (_lut_height[j1 * _lut_w + i] - _lut_height[j0 * _lut_w + i]) / ((j1 - j0) * LUT_STEP)

func _bilinear(arr: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf((x - _lut_origin.x) / LUT_STEP, 0.0, _lut_w - 1.001)
	var fz := clampf((z - _lut_origin.y) / LUT_STEP, 0.0, _lut_h - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := lerpf(arr[j * _lut_w + i], arr[j * _lut_w + i + 1], tx)
	var b := lerpf(arr[(j + 1) * _lut_w + i], arr[(j + 1) * _lut_w + i + 1], tx)
	return lerpf(a, b, tz)

func height_at(x: float, z: float) -> float:
	return _bilinear(_lut_height, x, z)

## Uphill gradient (rise per metre) in world x/z.
func gradient_at(x: float, z: float) -> Vector2:
	return Vector2(_bilinear(_lut_gx, x, z), _bilinear(_lut_gz, x, z))

func _inside(x: float, z: float) -> bool:
	return CourseTerrain._ell(x, z, terrain.green) < 1.0

# --------------------------------------------------------- aim + grid ---
## Square the grid to the putt. Cheap to call every frame; only rebuilds on change.
## `length` = how far the putt goes (metres); the grid only covers that window.
func set_aim(origin: Vector3, dir: Vector3, length: float = 10.0) -> void:
	var d := Vector3(dir.x, 0, dir.z).normalized()
	if origin.distance_to(_aim_origin) > 0.01 or d.angle_to(_aim_dir) > 0.002 or absf(length - _length) > 0.25:
		_aim_origin = origin
		_aim_dir = d
		_length = length
		_dirty = true

## Average slope along the putt from the ball toward `length` metres ahead.
## Returns Vector2(along, across): along > 0 uphill; across > 0 = right side higher (breaks left).
func read_putt(origin: Vector3, dir: Vector3, length: float) -> Vector2:
	var f := Vector2(dir.x, dir.z).normalized()
	var r := Vector2(-f.y, f.x)
	var along := 0.0
	var across := 0.0
	var n := 0
	var steps := maxi(2, int(length / 0.5))
	for k in steps + 1:
		var p := Vector2(origin.x, origin.z) + f * (length * float(k) / steps)
		if not _inside(p.x, p.y):
			continue
		var g := gradient_at(p.x, p.y)
		along += g.dot(f)
		across += g.dot(r)
		n += 1
	if n == 0:
		return Vector2.ZERO
	return Vector2(along, across) / n

func _rebuild_lines() -> void:
	_dirty = false
	var o := Vector2(_aim_origin.x, _aim_origin.z)
	var f := Vector2(_aim_dir.x, _aim_dir.z).normalized()
	var r := Vector2(-f.y, f.x) # right of the aim (facing -Z, right is +X)
	# window in the aim frame: along the putt [behind, ahead], across [-half_w, half_w]
	var behind := 1.5
	var ahead := _length + 2.5
	var half_w := clampf(_length * 0.35 + 1.5, 2.5, 6.0)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	_dot_data.clear()
	# set 0: lines parallel to the aim (offset sideways); set 1: lines across the aim
	for set_i in 2:
		var line_dir := f if set_i == 0 else r
		var offset_dir := r if set_i == 0 else f
		# set 0 lines are offset across the putt and run along it; set 1 the other way round
		var k_from := -int(floor(half_w / SPACING)) if set_i == 0 else -int(floor(behind / SPACING))
		var k_to := int(floor(half_w / SPACING)) if set_i == 0 else int(ceil(ahead / SPACING))
		var run_from := -behind if set_i == 0 else -half_w
		var run_to := ahead if set_i == 0 else half_w
		for k in range(k_from, k_to + 1):
			var base := o + offset_dir * (k * SPACING)
			# slope markers: one per grid cell, sliding downhill along this line
			var cell := int(floor(run_from / SPACING))
			while cell < int(ceil(run_to / SPACING)):
				var q := base + line_dir * (cell * SPACING)
				var q2 := q + line_dir * SPACING
				cell += 1
				if not (_inside(q.x, q.y) and _inside(q2.x, q2.y)):
					continue
				var mid := (q + q2) * 0.5
				var comp := gradient_at(mid.x, mid.y).dot(line_dir)
				if absf(comp) < FLAT:
					continue
				var down := -line_dir if comp > 0.0 else line_dir
				_dot_data.append({
					"start": q if comp < 0.0 else q2,
					"d": down,
					"speed": clampf(absf(comp) * 25.0, 0.15, 0.9),
					"phase": fposmod(float(cell) * 0.37 + float(k) * 0.61, 1.0),
					"yaw": atan2(-down.x, -down.y),
					"col": _slope_color(absf(comp), 0.6),
				})
			var u := run_from
			while u < run_to:
				var p0 := base + line_dir * u
				var p1 := base + line_dir * (u + SEG)
				u += SEG
				if not (_inside(p0.x, p0.y) and _inside(p1.x, p1.y)):
					continue
				var a := Vector3(p0.x, height_at(p0.x, p0.y) + LIFT, p0.y)
				var b := Vector3(p1.x, height_at(p1.x, p1.y) + LIFT, p1.y)
				var w := Vector3(-line_dir.y, 0, line_dir.x) * (LINE_W * 0.5)
				var ca := _slope_color(absf(gradient_at(p0.x, p0.y).dot(line_dir)), LINE_ALPHA)
				var cb := _slope_color(absf(gradient_at(p1.x, p1.y).dot(line_dir)), LINE_ALPHA)
				verts.append_array(PackedVector3Array([a + w, b + w, b - w, a + w, b - w, a - w]))
				cols.append_array(PackedColorArray([ca, cb, cb, ca, cb, ca]))
	var mm := _dots.multimesh
	mm.instance_count = _dot_data.size()
	for i in _dot_data.size():
		mm.set_instance_color(i, _dot_data[i]["col"])
	_update_dots()
	if verts.is_empty():
		_lines.mesh = null
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_lines.mesh = mesh

## green (flat) -> yellow (mild) -> red (dramatic), by slope magnitude (rise/run)
func _slope_color(slope: float, alpha: float) -> Color:
	var c: Color
	if slope <= FLAT:
		c = FLAT_C
	elif slope <= MILD:
		c = FLAT_C.lerp(MILD_C, (slope - FLAT) / (MILD - FLAT))
	else:
		c = MILD_C.lerp(STEEP_C, clampf((slope - MILD) / (DRAMATIC - MILD), 0.0, 1.0))
	c.a = alpha + 0.12 * clampf(slope / DRAMATIC, 0.0, 1.0)
	return c

func _overlay_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _process(delta: float) -> void:
	if not visible:
		return
	if _dirty:
		_rebuild_lines()
	_t += delta
	_update_dots()

func _update_dots() -> void:
	if _dots == null:
		return
	var mm := _dots.multimesh
	for i in _dot_data.size():
		var d: Dictionary = _dot_data[i]
		# slide one grid cell downhill along the line, then loop
		var off := fposmod(float(d["phase"]) + _t * float(d["speed"]), 1.0) * SPACING
		var p: Vector2 = (d["start"] as Vector2) + (d["d"] as Vector2) * off
		var pos := Vector3(p.x, height_at(p.x, p.y) + LIFT + 0.006, p.y)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(d["yaw"])), pos))
