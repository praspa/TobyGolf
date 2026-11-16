class_name CourseTerrain
extends RefCounted
## Analytic heightfield + surface map for one hole, plus builders for the
## chunky flat-shaded mesh, water, trees and green slope arrows.
## Physics samples height()/normal_at() directly so ball motion is smooth while
## the visual mesh stays low-poly.

enum Surface { TEE, FAIRWAY, ROUGH, BUNKER, GREEN, FRINGE, WATER, OOB, WASTE }

# e: bounce restitution, keep: tangential speed kept on bounce,
# roll: rolling deceleration m/s^2, grab: how much backspin bites,
# dist/spin/err: lie effects on the next shot (distance, spin, error multipliers)
const SURF := {
	Surface.TEE:     {"name": "Tee",      "e": 0.35, "keep": 0.55, "roll": 2.2,  "grab": 0.6,  "dist": 1.0,  "spin": 1.0, "err": 1.0},
	Surface.FAIRWAY: {"name": "Fairway",  "e": 0.35, "keep": 0.55, "roll": 2.2,  "grab": 0.6,  "dist": 1.0,  "spin": 1.0, "err": 1.0},
	Surface.ROUGH:   {"name": "Rough",    "e": 0.20, "keep": 0.40, "roll": 4.5,  "grab": 0.15, "dist": 0.82, "spin": 0.5, "err": 1.5},
	Surface.BUNKER:  {"name": "Bunker",   "e": 0.04, "keep": 0.20, "roll": 9.0,  "grab": 0.0,  "dist": 0.65, "spin": 0.4, "err": 1.7},
	Surface.GREEN:   {"name": "Green",    "e": 0.28, "keep": 0.58, "roll": 0.55, "grab": 1.0,  "dist": 0.97, "spin": 0.9, "err": 1.1},
	Surface.FRINGE:  {"name": "Fringe",   "e": 0.30, "keep": 0.55, "roll": 1.3,  "grab": 0.8,  "dist": 0.97, "spin": 0.9, "err": 1.1},
	Surface.WATER:   {"name": "Water",    "e": 0.0,  "keep": 0.0,  "roll": 99.0, "grab": 0.0,  "dist": 0.5,  "spin": 0.5, "err": 2.0},
	Surface.OOB:     {"name": "Out of Bounds", "e": 0.20, "keep": 0.45, "roll": 4.5, "grab": 0.15, "dist": 0.82, "spin": 0.5, "err": 1.5},
	Surface.WASTE:   {"name": "Waste area", "e": 0.12, "keep": 0.35, "roll": 5.0, "grab": 0.1, "dist": 0.88, "spin": 0.6, "err": 1.25},
}

const MESH_CELL := 2.0
const MESH_MARGIN := 45.0

var hole: Dictionary
var bounds: Rect2
var fairway: Array = []      # Array[Vector2]
var corridor: Array = []     # Array[Vector2]
var fw_hw := 16.0
var green: Dictionary
var green_c := Vector2.ZERO
var green_base := 0.0
var tee := Vector2.ZERO
var tee_h := 0.0
var pin := Vector2.ZERO
var bunkers: Array = []
var waters: Array = []       # each gets "base" and "level"
var trees: Array = []        # [{kind, p: Vector3, r: float, trunk: float, top: float}]
var islands: Array = []      # dry land inside water, each gets "base"
var wastes: Array = []       # waste bunkers
var rocks: Array = []        # [{p: Vector3, r: float, h: float}]
var theme: Dictionary = {}
var valley_amp := 9.0
var bumps := 3.0
var noise := FastNoiseLite.new()
var noise2 := FastNoiseLite.new()
var noise3 := FastNoiseLite.new()   # rolling swales through the fairways
var noise4 := FastNoiseLite.new()   # small undulations on top
var rolls := 1.4
var elev := 0.0
var min_h := 0.0
var border_min := 0.0

func _init(h: Dictionary, th: Dictionary = {}) -> void:
	hole = h
	theme = th if not th.is_empty() else Course.THEMES["parkland"]
	valley_amp = float(theme.get("valley", 9.0))
	bumps = float(theme.get("bumps", 3.0))
	rolls = float(theme.get("rolls", 1.4))
	wastes = h.get("waste", [])
	bounds = h["bounds"]
	fairway = h["fairway"]
	fw_hw = h["fairway_hw"]
	green = h["green"]
	green_c = green["c"]
	tee = h["tee"]
	pin = h["pin"]
	bunkers = h["bunkers"]
	elev = h["elev"]
	noise.seed = h["seed"]
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.011
	noise2.seed = int(h["seed"]) + 7
	noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise2.frequency = 0.05
	noise3.seed = int(h["seed"]) + 13
	noise3.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise3.frequency = 0.016
	noise4.seed = int(h["seed"]) + 29
	noise4.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise4.frequency = 0.06
	corridor = [tee]
	corridor.append_array(fairway)
	corridor.append(green_c)
	tee_h = _raw(tee.x, tee.y) + 0.35
	green_base = _raw(green_c.x, green_c.y) + float(green.get("raise", 0.5))
	waters = []
	for w in h["water"]:
		var wd: Dictionary = w.duplicate()
		var c: Vector2 = wd["c"]
		wd["base"] = _raw(c.x, c.y)
		wd["level"] = float(wd["base"]) - 0.08
		waters.append(wd)
	islands = []
	for isl in h.get("islands", []):
		var idd: Dictionary = isl.duplicate()
		var ic: Vector2 = idd["c"]
		var lvl := _raw(ic.x, ic.y)
		for w in waters:
			if _ell(ic.x, ic.y, w) < 1.0:
				lvl = float(w["level"])
		idd["base"] = lvl + 0.55
		islands.append(idd)
	# the green on an island sits on the island, not on the raw terrain
	for isl in islands:
		if _ell(green_c.x, green_c.y, isl) < 1.0:
			green_base = float(isl["base"]) + 0.25
		if _ell(tee.x, tee.y, isl) < 1.0:
			tee_h = float(isl["base"]) + 0.35
	for rk in h.get("rocks", []):
		var rc: Vector2 = rk["c"]
		var rr: float = rk["r"]
		rocks.append({"p": Vector3(rc.x, height(rc.x, rc.y) - 0.15, rc.y), "r": rr, "h": rr * 0.85})
	_generate_trees()

# ---------------------------------------------------------------- geometry ---
static func _seg_dist(p: Vector2, pts: Array) -> float:
	var best := INF
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	if pts.size() == 1:
		best = p.distance_to(pts[0])
	return best

static func _ell(x: float, z: float, e: Dictionary) -> float:
	var c: Vector2 = e["c"]
	var dx := (x - c.x) / float(e["rx"])
	var dz := (z - c.y) / float(e["rz"])
	return sqrt(dx * dx + dz * dz)

func _valley(x: float, z: float) -> float:
	var d := _seg_dist(Vector2(x, z), corridor)
	var t := clampf((d - fw_hw - 12.0) / 70.0, 0.0, 1.0)
	return pow(t, 1.5) * valley_amp

func _raw(x: float, z: float) -> float:
	return -z * elev + noise.get_noise_2d(x, z) * bumps + _rolls(x, z) + _valley(x, z)

## Fairways aren't dead flat: long gentle swales plus a little undulation.
func _rolls(x: float, z: float) -> float:
	return noise3.get_noise_2d(x, z) * rolls + noise4.get_noise_2d(x, z) * rolls * 0.06

func fairway_dist(x: float, z: float) -> float:
	return _seg_dist(Vector2(x, z), fairway)

func height(x: float, z: float) -> float:
	var dfw := fairway_dist(x, z)
	var fwm := 1.0 - smoothstep(fw_hw, fw_hw + 14.0, dfw)
	var h := -z * elev + _valley(x, z)
	h += noise.get_noise_2d(x, z) * bumps * (1.0 - 0.6 * fwm)
	h += noise2.get_noise_2d(x, z) * 0.35 * (1.0 - fwm)
	h += _rolls(x, z)
	# tee box
	var tdx := absf(x - tee.x) - 3.5
	var tdz := absf(z - (tee.y - 2.0)) - 6.0
	var tm := 1.0 - smoothstep(0.0, 3.0, maxf(tdx, tdz))
	h = lerpf(h, tee_h, tm)
	# ponds: flatten around, then dig
	for w in waters:
		var d := _ell(x, z, w)
		if d < 1.7:
			h = lerpf(h, float(w["base"]), 1.0 - smoothstep(1.0, 1.6, d))
			h -= 1.6 * (1.0 - smoothstep(0.45, 1.0, d))
	# islands: raise dry land back out of the water
	for isl in islands:
		var di := _ell(x, z, isl)
		if di < 1.15:
			h = lerpf(h, float(isl["base"]), 1.0 - smoothstep(0.85, 1.1, di))
	# waste areas: gently scooped sandy hollows
	for wa in wastes:
		var dw := _ell(x, z, wa)
		if dw < 1.0:
			h -= 0.25 * (1.0 - smoothstep(0.6, 1.0, dw))
	# green: tilted plane with a gentle undulation
	var gd := _ell(x, z, green)
	if gd < 1.8:
		var dx := x - green_c.x
		var dz := z - green_c.y
		var tilt: Vector2 = green["tilt"]
		var gh := green_base + tilt.x * dx + tilt.y * dz + float(green["und"]) * sin(dx * 0.35) * cos(dz * 0.3)
		h = lerpf(h, gh, 1.0 - smoothstep(1.05, 1.7, gd))
	for b in bunkers:
		var bd := _ell(x, z, b)
		if bd < 1.0:
			h -= 0.7 * (1.0 - smoothstep(0.55, 1.0, bd))
	return h

func normal_at(x: float, z: float) -> Vector3:
	var e := 0.3
	var hx := height(x + e, z) - height(x - e, z)
	var hz := height(x, z + e) - height(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()

func surface(x: float, z: float) -> int:
	if not bounds.has_point(Vector2(x, z)):
		return Surface.OOB
	var island := _on_island(x, z)
	if not island:
		for w in waters:
			if _ell(x, z, w) < 0.93:
				return Surface.WATER
	for b in bunkers:
		if _ell(x, z, b) < 0.92:
			return Surface.BUNKER
	var gd := _ell(x, z, green)
	if gd < 1.0:
		return Surface.GREEN
	if gd < 1.2:
		return Surface.FRINGE
	if absf(x - tee.x) <= 3.5 and z <= tee.y + 4.0 and z >= tee.y - 8.0:
		return Surface.TEE
	for wa in wastes:
		if _ell(x, z, wa) < 0.95:
			return Surface.WASTE
	if fairway_dist(x, z) < fw_hw:
		return Surface.FAIRWAY
	return Surface.ROUGH

func _on_island(x: float, z: float) -> bool:
	for isl in islands:
		if _ell(x, z, isl) < 0.92:
			return true
	return false

func surf_info(s: int) -> Dictionary:
	var d: Dictionary = SURF[s]
	if s == Surface.ROUGH and theme.get("rough_name", "Rough") != "Rough":
		d = d.duplicate()
		d["name"] = theme["rough_name"]
	return d

func pin_pos3() -> Vector3:
	return Vector3(pin.x, height(pin.x, pin.y), pin.y)

func water_at(x: float, z: float) -> Dictionary:
	if _on_island(x, z):
		return {}
	for w in waters:
		if _ell(x, z, w) < 0.93:
			return w
	return {}

# ------------------------------------------------------------------- trees ---
## Trees depend on the theme: "pine" (parkland), "palm" (tropical), "cactus" (desert).
## Each keeps the same collision fields: p (base), r (canopy/column radius),
## trunk (height where the canopy starts), top.
func _generate_trees() -> void:
	var kind: String = theme.get("tree", "pine")
	var density: float = float(theme.get("tree_density", 1.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(hole["seed"]) * 31
	var area := bounds.grow(30.0)
	var attempts := int(area.size.x * area.size.y / 140.0 * density)
	var keep_out := fw_hw + (9.0 if kind == "pine" else (5.0 if kind == "palm" else 3.0))
	for i in attempts:
		var x := rng.randf_range(area.position.x, area.end.x)
		var z := rng.randf_range(area.position.y, area.end.y)
		if fairway_dist(x, z) < fw_hw + 3.0:
			continue
		if _ell(x, z, green) < 2.2:
			continue
		if Vector2(x, z).distance_to(tee) < 14.0:
			continue
		var ok := true
		for w in waters:
			if _ell(x, z, w) < 1.25 and not _on_island(x, z):
				ok = false
		for isl in islands:
			if _ell(x, z, isl) < 1.1:
				ok = false # keep islands clear
		for bk in bunkers:
			if _ell(x, z, bk) < 1.6:
				ok = false
		for rk in rocks:
			if Vector2(x, z).distance_to(Vector2(rk["p"].x, rk["p"].z)) < 4.0:
				ok = false
		# keep the line from the tee to the fairway reasonably open
		if _seg_dist(Vector2(x, z), corridor) < keep_out:
			ok = false
		if not ok:
			continue
		var t := {"kind": kind, "p": Vector3(x, height(x, z), z), "shade": rng.randf()}
		match kind:
			"palm":
				var top := rng.randf_range(7.0, 10.5)
				t["r"] = rng.randf_range(2.4, 3.4)
				t["trunk"] = top - 1.4
				t["top"] = top + 0.4
				t["lean"] = rng.randf_range(-0.25, 0.25)
				t["yaw"] = rng.randf() * TAU
			"cactus":
				t["r"] = 0.42
				t["trunk"] = 0.0
				t["top"] = rng.randf_range(2.6, 4.6)
				t["yaw"] = rng.randf() * TAU
			_:
				t["r"] = rng.randf_range(2.0, 3.6)
				t["trunk"] = rng.randf_range(1.8, 2.6)
				t["top"] = rng.randf_range(8.0, 13.0)
		trees.append(t)

# -------------------------------------------------------------------- mesh ---
func _tc(key: String) -> Color:
	return theme.get(key, Color.MAGENTA)

func _color_for(s: int, x: float, z: float) -> Color:
	var jitter := fposmod(sin(x * 12.9898 + z * 78.233) * 43758.5453, 1.0) * 0.04
	var j3 := Color(jitter, jitter, jitter * 0.5, 0.0)
	match s:
		Surface.FAIRWAY:
			return _tc("fairway_a") if int(floor(z / 9.0)) % 2 == 0 else _tc("fairway_b")
		Surface.TEE:
			return _tc("tee")
		Surface.GREEN:
			var chk := (int(floor(x / 2.5)) + int(floor(z / 2.5))) % 2 == 0
			return _tc("green_a") if chk else _tc("green_b")
		Surface.FRINGE:
			return _tc("fringe")
		Surface.BUNKER:
			return _tc("bunker")
		Surface.WASTE:
			return _tc("waste") + j3 * 1.5 - Color(0.03, 0.03, 0.03, 0.0)
		Surface.WATER:
			return _tc("water_bed")
		Surface.OOB:
			return _tc("oob") + j3
	return _tc("rough") + j3

func build_mesh() -> ArrayMesh:
	var r := bounds.grow(MESH_MARGIN)
	var nx := int(ceil(r.size.x / MESH_CELL))
	var nz := int(ceil(r.size.y / MESH_CELL))
	var hs := PackedFloat32Array()
	hs.resize((nx + 1) * (nz + 1))
	for j in nz + 1:
		var z := r.position.y + j * MESH_CELL
		for i in nx + 1:
			hs[j * (nx + 1) + i] = height(r.position.x + i * MESH_CELL, z)
	min_h = INF
	for hv in hs:
		min_h = minf(min_h, hv)
	border_min = INF
	for j in nz + 1:
		border_min = minf(border_min, minf(hs[j * (nx + 1)], hs[j * (nx + 1) + nx]))
	for i in nx + 1:
		border_min = minf(border_min, minf(hs[i], hs[nz * (nx + 1) + i]))
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var tri_count := nx * nz * 2
	verts.resize(tri_count * 3)
	norms.resize(tri_count * 3)
	cols.resize(tri_count * 3)
	var k := 0
	for j in nz:
		var z0 := r.position.y + j * MESH_CELL
		var z1 := z0 + MESH_CELL
		for i in nx:
			var x0 := r.position.x + i * MESH_CELL
			var x1 := x0 + MESH_CELL
			var a := Vector3(x0, hs[j * (nx + 1) + i], z0)
			var b := Vector3(x1, hs[j * (nx + 1) + i + 1], z0)
			var c := Vector3(x0, hs[(j + 1) * (nx + 1) + i], z1)
			var d := Vector3(x1, hs[(j + 1) * (nx + 1) + i + 1], z1)
			# two triangles per quad, flat shaded, coloured by the surface at the centroid
			for tri in [[a, b, d], [a, d, c]]:
				var p0: Vector3 = tri[0]
				var p1: Vector3 = tri[1]
				var p2: Vector3 = tri[2]
				# Godot treats clockwise (seen from the front) as front-facing, so wind
				# triangles so the geometric normal points down, then use the up normal.
				var n := (p1 - p0).cross(p2 - p0).normalized()
				if n.y > 0.0:
					var tmp := p1
					p1 = p2
					p2 = tmp
				else:
					n = -n
				var cen := (p0 + p1 + p2) / 3.0
				var col := _color_for(surface(cen.x, cen.z), cen.x, cen.z)
				verts[k] = p0
				verts[k + 1] = p1
				verts[k + 2] = p2
				for m in 3:
					norms[k + m] = n
					cols[k + m] = col
				k += 3
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

static func vertex_color_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func build_node() -> Node3D:
	var root := Node3D.new()
	root.name = "Course"
	var mi := MeshInstance3D.new()
	mi.mesh = build_mesh()
	mi.material_override = vertex_color_material()
	root.add_child(mi)
	root.add_child(_build_water())
	root.add_child(_build_trees())
	root.add_child(_build_rocks())
	root.add_child(_build_scenery())
	return root

func _build_water() -> Node3D:
	var n := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _tc("water")
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.15
	mat.metallic_specular = 0.8
	for w in waters:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.0
		cyl.bottom_radius = 1.0
		cyl.height = 0.04
		cyl.radial_segments = 20
		cyl.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.material_override = mat
		var c: Vector2 = w["c"]
		mi.position = Vector3(c.x, float(w["level"]), c.y)
		mi.scale = Vector3(float(w["rx"]), 1.0, float(w["rz"]))
		n.add_child(mi)
	return n

func _mm(mesh: Mesh, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	return mm

func _mmi(mm: MultiMesh, mat: Material) -> MultiMeshInstance3D:
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	return mi

func _cyl(top_r: float, bottom_r: float, segs: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bottom_r
	c.height = 1.0
	c.radial_segments = segs
	c.rings = 1
	return c

func _instance_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	return mat

func _build_trees() -> Node3D:
	var n := Node3D.new()
	var kind: String = theme.get("tree", "pine")
	match kind:
		"palm":
			_build_palms(n)
		"cactus":
			_build_cacti(n)
		_:
			_build_pines(n)
	return n

func _build_pines(n: Node3D) -> void:
	var mat := _instance_mat()
	var mm_c := _mm(_cyl(0.0, 1.0, 6), trees.size() * 2)
	var mm_t := _mm(_cyl(0.22, 0.3, 5), trees.size())
	for i in trees.size():
		var t: Dictionary = trees[i]
		var p: Vector3 = t["p"]
		var r: float = t["r"]
		var trunk_h: float = t["trunk"]
		var top: float = t["top"]
		var shade: float = t["shade"]
		var green_col := Color(0.12, 0.38 + shade * 0.12, 0.14).lerp(Color(0.2, 0.45, 0.12), shade)
		var ch := top - trunk_h
		# two stacked cones for a chunky pine silhouette
		mm_c.set_instance_transform(i * 2, Transform3D(Basis.from_scale(Vector3(r, ch * 0.62, r)), p + Vector3(0, trunk_h + ch * 0.31, 0)))
		mm_c.set_instance_color(i * 2, green_col)
		mm_c.set_instance_transform(i * 2 + 1, Transform3D(Basis.from_scale(Vector3(r * 0.7, ch * 0.55, r * 0.7)), p + Vector3(0, trunk_h + ch * 0.68, 0)))
		mm_c.set_instance_color(i * 2 + 1, green_col.lightened(0.12))
		mm_t.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(1, trunk_h + 0.4, 1)), p + Vector3(0, (trunk_h + 0.4) * 0.5 - 0.2, 0)))
		mm_t.set_instance_color(i, Color(0.42, 0.28, 0.16))
	n.add_child(_mmi(mm_c, mat))
	n.add_child(_mmi(mm_t, mat))

func _build_palms(n: Node3D) -> void:
	# leaning segmented trunk + a crown of drooping fronds + a few coconuts
	var mat := _instance_mat()
	var fronds := 6
	var segs := 4
	var mm_t := _mm(_cyl(0.16, 0.22, 6), trees.size() * segs)
	var frond_mesh := BoxMesh.new()
	frond_mesh.size = Vector3(1, 1, 1)
	var mm_f := _mm(frond_mesh, trees.size() * fronds)
	var nut := SphereMesh.new()
	nut.radius = 0.5
	nut.height = 1.0
	nut.radial_segments = 6
	nut.rings = 3
	var mm_n := _mm(nut, trees.size() * 3)
	for i in trees.size():
		var t: Dictionary = trees[i]
		var p: Vector3 = t["p"]
		var trunk_h: float = t["trunk"]
		var lean: float = t["lean"]
		var yaw: float = t["yaw"]
		var r: float = t["r"]
		var shade: float = t["shade"]
		var lean_dir := Vector3(cos(yaw), 0, sin(yaw))
		var seg_h := trunk_h / segs
		for k in segs:
			# curve: each segment leans a bit more
			var a0 := lean * float(k) / segs
			var base := p + lean_dir * (sin(lean) * trunk_h * pow(float(k) / segs, 1.6)) + Vector3(0, seg_h * k, 0)
			var basis := Basis(lean_dir.cross(Vector3.UP).normalized(), -a0 * 1.2).scaled(Vector3(1, seg_h * 1.05, 1))
			mm_t.set_instance_transform(i * segs + k, Transform3D(basis, base + Vector3(0, seg_h * 0.5, 0)))
			mm_t.set_instance_color(i * segs + k, Color(0.55, 0.42, 0.26) if k % 2 == 0 else Color(0.48, 0.36, 0.22))
		var crown := p + lean_dir * (sin(lean) * trunk_h) + Vector3(0, trunk_h, 0)
		var leaf := Color(0.18, 0.55 + shade * 0.12, 0.2)
		for f in fronds:
			var fy := yaw + TAU * f / fronds
			# frond: long flat box pointing outward and drooping
			var b := Basis(Vector3.UP, fy) * Basis(Vector3(0, 0, 1), -0.45)
			var scaled := b.scaled_local(Vector3(r, 0.08, 0.55))
			var offset := b * Vector3(r * 0.5, 0, 0)
			mm_f.set_instance_transform(i * fronds + f, Transform3D(scaled, crown + offset))
			mm_f.set_instance_color(i * fronds + f, leaf.lightened(0.08 * (f % 2)))
		for c in 3:
			var ca := yaw + TAU * c / 3.0
			mm_n.set_instance_transform(i * 3 + c, Transform3D(Basis.from_scale(Vector3.ONE * 0.28), crown + Vector3(cos(ca) * 0.22, -0.3, sin(ca) * 0.22)))
			mm_n.set_instance_color(i * 3 + c, Color(0.42, 0.3, 0.15))
	n.add_child(_mmi(mm_t, mat))
	n.add_child(_mmi(mm_f, mat))
	n.add_child(_mmi(mm_n, mat))

func _build_cacti(n: Node3D) -> void:
	# saguaro: a tall column plus 0-2 arms (horizontal stub + upright)
	var mat := _instance_mat()
	var col_mesh := _cyl(0.32, 0.36, 7)
	var parts: Array = [] # [Transform3D, Color]
	for t in trees:
		var p: Vector3 = t["p"]
		var top: float = t["top"]
		var yaw: float = t["yaw"]
		var shade: float = t["shade"]
		var col := Color(0.28, 0.5 + shade * 0.1, 0.3)
		parts.append([Transform3D(Basis.from_scale(Vector3(1, top, 1)), p + Vector3(0, top * 0.5 - 0.1, 0)), col])
		var arms := int(shade * 3.0)
		for a in arms:
			var side := 1.0 if a == 0 else -1.0
			var dir := Vector3(cos(yaw), 0, sin(yaw)) * side
			var ah := top * (0.45 + 0.15 * a)
			var stub_len := 0.7
			var stub_basis := Basis(dir.cross(Vector3.UP).normalized(), PI * 0.5).scaled(Vector3(0.7, stub_len, 0.7))
			parts.append([Transform3D(stub_basis, p + Vector3(0, ah, 0) + dir * (stub_len * 0.5 + 0.2)), col.darkened(0.05)])
			var up_len := top * 0.35
			parts.append([Transform3D(Basis.from_scale(Vector3(0.7, up_len, 0.7)), p + dir * (stub_len + 0.2) + Vector3(0, ah + up_len * 0.5 - 0.1, 0)), col])
	var mm := _mm(col_mesh, parts.size())
	for i in parts.size():
		mm.set_instance_transform(i, parts[i][0])
		mm.set_instance_color(i, parts[i][1])
	n.add_child(_mmi(mm, mat))

func _build_rocks() -> Node3D:
	var n := Node3D.new()
	if rocks.is_empty():
		return n
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 6
	sm.rings = 3
	var mm := _mm(sm, rocks.size())
	for i in rocks.size():
		var rk: Dictionary = rocks[i]
		var r: float = rk["r"]
		var h: float = rk["h"]
		var b := Basis(Vector3.UP, float(i) * 1.7).scaled(Vector3(r, h, r * 0.85))
		mm.set_instance_transform(i, Transform3D(b, rk["p"]))
		mm.set_instance_color(i, Color(0.6, 0.5, 0.42).darkened(0.1 * (i % 3)))
	n.add_child(_mmi(mm, _instance_mat()))
	return n

func _build_scenery() -> Node3D:
	# Big ground plane (or ocean) + distant hills / mesas + a few blocky clouds.
	var n := Node3D.new()
	var scenery: String = theme.get("scenery", "hills")
	var center := bounds.get_center()
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4000, 4000)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = _tc("ground")
	gmat.roughness = 1.0
	if scenery == "ocean":
		gmat.roughness = 0.2
		gmat.metallic_specular = 0.7
	ground.material_override = gmat
	var ground_y := min_h - 1.5
	if scenery == "ocean":
		ground_y = border_min + 0.6 # the low edges of the island sink into the sea
	ground.position = Vector3(center.x, ground_y, center.y)
	n.add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(hole["seed"]) + 999
	var mesas := scenery == "mesas"
	var hill := _cyl(0.8 if mesas else 0.15, 1.0, 8 if mesas else 7)
	var count := 28
	var mm := _mm(hill, count)
	var radius := maxf(bounds.size.x, bounds.size.y) * 0.5 + 380.0
	for i in count:
		var ang := TAU * float(i) / count + rng.randf_range(-0.08, 0.08)
		var dist := radius + rng.randf_range(0, 220)
		var w := rng.randf_range(90, 180)
		var hh := rng.randf_range(40, 110)
		if mesas:
			hh = rng.randf_range(30, 75)
			w = rng.randf_range(110, 220)
		elif scenery == "ocean":
			hh = rng.randf_range(15, 45)
			w = rng.randf_range(60, 130)
			dist += 250.0
		var p := Vector3(center.x + cos(ang) * dist, ground_y + hh * 0.5 - 2.0, center.y + sin(ang) * dist)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(w, hh, w)), p))
		mm.set_instance_color(i, _tc("hill_a").lerp(_tc("hill_b"), rng.randf()))
	n.add_child(_mmi(mm, _instance_mat()))
	var cloud_mat := StandardMaterial3D.new()
	cloud_mat.albedo_color = Color(1, 1, 1)
	cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var clouds := 6 if mesas else 14
	for i in clouds:
		var cloud := Node3D.new()
		var ang := rng.randf() * TAU
		var dist := radius * rng.randf_range(0.5, 1.1)
		cloud.position = Vector3(center.x + cos(ang) * dist, rng.randf_range(70, 120), center.y + sin(ang) * dist)
		for j in 3:
			var box := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(rng.randf_range(18, 34), rng.randf_range(6, 10), rng.randf_range(12, 22))
			box.mesh = bm
			box.material_override = cloud_mat
			box.position = Vector3(j * 14.0 - 14.0, rng.randf_range(-2, 3), rng.randf_range(-4, 4))
			box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cloud.add_child(box)
		n.add_child(cloud)
	return n
