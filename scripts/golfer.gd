class_name Golfer
extends Node3D
## Chunky box-built dog golfers. Each character shares the same rig (legs, torso,
## head, ears, tail, swinging arms + club) with its own colours and props:
##   toby   - black & tan coonhound in a light blue hoodie
##   carlin - derpy golden retriever in a backwards purple cap
##   onezy  - gray Persian cat in black & red buffalo-check pajamas
##   zero   - black Persian cat in red/blue 3D movie glasses
## The model faces local -Z; the ball sits in front (target to the left,
## right-handed stance). Animations are procedural.

signal impact

const BALL_OFFSET := 0.62
const BACKSWING_MAX := 2.5
const FOLLOW_THROUGH := -2.1
const DOWNSWING_TIME := 0.22

enum Anim { IDLE, BACKSWING, DOWNSWING, FOLLOW, CELEBRATE, SAD }

const BLACK := Color(0.09, 0.08, 0.08)
const TAN := Color(0.78, 0.5, 0.25)
const GOLD := Color(0.88, 0.63, 0.28)
const GOLD_DARK := Color(0.76, 0.5, 0.2)
const CREAM := Color(0.97, 0.87, 0.64)
const PURPLE := Color(0.5, 0.25, 0.75)
const PINK := Color(0.96, 0.45, 0.55)
const WHITE := Color(1, 1, 1)
const PUPIL := Color(0.05, 0.03, 0.02)
const CAT_GRAY := Color(0.6, 0.6, 0.65)
const CAT_LIGHT := Color(0.82, 0.82, 0.85)
const PJ_RED := Color(0.78, 0.1, 0.1)
const PJ_BLACK := Color(0.08, 0.08, 0.08)
const COPPER := Color(0.95, 0.6, 0.15)

var character := "toby"
var hoodie_color := Color(0.55, 0.78, 0.95)
var anim := Anim.IDLE
var t := 0.0
var swing_angle := 0.0
var _down_from := 0.0
var _impact_sent := false
var _anim_time := 0.0
var _ear_base := 0.0
var _cat_fur := CAT_GRAY
var _cat_light := CAT_LIGHT

var upper: Node3D
var head: Node3D
var ear_l: Node3D
var ear_r: Node3D
var tail: Node3D
var arms: Node3D
var club: Node3D
var club_head: MeshInstance3D
var club_shaft: MeshInstance3D
var _hoodie_mats: Array = []

func _init(character_id: String = "toby") -> void:
	character = character_id
	hoodie_color = Game.CHARACTERS[character_id]["hoodie"] if Game.CHARACTERS.has(character_id) else hoodie_color
	_build()

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m

func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, hoodie: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := _mat(color)
	mi.material_override = m
	if hoodie:
		_hoodie_mats.append(m)
	mi.position = pos
	parent.add_child(mi)
	return mi

func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n

func _build() -> void:
	match character:
		"bacon":
			_build_bacon()
			return
		"dorothy":
			_build_dorothy()
			return
		"dewey":
			_build_dewey()
			return
	var carlin := character == "carlin"
	var cat := character == "onezy" or character == "zero"
	var pj := character == "onezy"   # Onezy wears buffalo-check pajamas
	if character == "zero":
		_cat_fur = Color(0.1, 0.1, 0.12)
		_cat_light = Color(0.26, 0.26, 0.3)
	var fur := GOLD if carlin else BLACK
	var accent := CREAM if carlin else TAN     # paws, muzzle
	var torso := GOLD if carlin else hoodie_color
	if cat:
		fur = _cat_fur
		accent = _cat_light
		torso = PJ_RED if pj else _cat_fur
	# legs + paws (Onezy wears pajama pants)
	for sx in [-1.0, 1.0]:
		_box(self, Vector3(0.13, 0.32, 0.14), Vector3(0.11 * sx, 0.16, 0.0), PJ_RED if pj else fur)
		if pj:
			_box(self, Vector3(0.14, 0.06, 0.15), Vector3(0.11 * sx, 0.22, 0.0), PJ_BLACK)
		_box(self, Vector3(0.15, 0.06, 0.2), Vector3(0.11 * sx, 0.03, -0.03), accent)
	tail = _pivot(self, Vector3(0, 0.42, 0.14))
	if cat:
		_box(tail, Vector3(0.11, 0.11, 0.5), Vector3(0, 0, 0.22), _cat_fur)   # long fluffy tail
		_box(tail, Vector3(0.12, 0.12, 0.12), Vector3(0, 0, 0.47), _cat_light)
	elif carlin:
		_box(tail, Vector3(0.12, 0.11, 0.36), Vector3(0, 0, 0.16), GOLD)      # fluffy plume
		_box(tail, Vector3(0.09, 0.08, 0.1), Vector3(0, -0.02, 0.36), CREAM)
	else:
		_box(tail, Vector3(0.07, 0.07, 0.34), Vector3(0, 0, 0.16), BLACK)
	tail.rotation.x = 0.7

	upper = _pivot(self, Vector3.ZERO)
	_box(upper, Vector3(0.46, 0.5, 0.3), Vector3(0, 0.57, 0), torso, not (carlin or cat))
	if pj:
		# buffalo check: black bands crossing the red top, plus white buttons
		for y in [0.45, 0.63]:
			_box(upper, Vector3(0.47, 0.08, 0.31), Vector3(0, y, 0), PJ_BLACK)
		for x in [-0.11, 0.11]:
			_box(upper, Vector3(0.08, 0.51, 0.31), Vector3(x, 0.57, 0), PJ_BLACK)
		for y in [0.5, 0.6, 0.7]:
			_box(upper, Vector3(0.035, 0.035, 0.02), Vector3(0, y, -0.16), Color(0.95, 0.95, 0.95))
		_box(upper, Vector3(0.44, 0.07, 0.32), Vector3(0, 0.82, 0), CAT_LIGHT)    # fluffy neck ruff
	elif cat:
		_box(upper, Vector3(0.3, 0.32, 0.02), Vector3(0, 0.6, -0.16), _cat_light)    # chest floof
		_box(upper, Vector3(0.44, 0.07, 0.32), Vector3(0, 0.82, 0), _cat_light)      # neck ruff
	elif carlin:
		_box(upper, Vector3(0.3, 0.3, 0.02), Vector3(0, 0.6, -0.16), CREAM)          # chest floof
		_box(upper, Vector3(0.4, 0.06, 0.33), Vector3(0, 0.83, 0), PURPLE)           # collar
		_box(upper, Vector3(0.06, 0.07, 0.02), Vector3(0, 0.78, -0.175), Color(1, 0.85, 0.2)) # tag
	else:
		_box(upper, Vector3(0.3, 0.12, 0.02), Vector3(0, 0.44, -0.16), hoodie_color.darkened(0.2), true)
		_box(upper, Vector3(0.42, 0.24, 0.13), Vector3(0, 0.86, 0.15), hoodie_color, true) # hood
		_box(upper, Vector3(0.02, 0.12, 0.02), Vector3(-0.06, 0.72, -0.16), Color(0.95, 0.95, 0.95))
		_box(upper, Vector3(0.02, 0.12, 0.02), Vector3(0.06, 0.72, -0.16), Color(0.95, 0.95, 0.95))

	head = _pivot(upper, Vector3(0, 0.84, -0.02))
	if cat:
		_build_onezy_head()
	else:
		_box(head, Vector3(0.36, 0.32, 0.34), Vector3(0, 0.17, 0), fur)
		_box(head, Vector3(0.2, 0.14, 0.18), Vector3(0, 0.09, -0.24), accent)               # muzzle
		_box(head, Vector3(0.09, 0.06, 0.05), Vector3(0, 0.15, -0.34), Color(0.02, 0.02, 0.02)) # nose
	if cat:
		pass
	elif carlin:
		_build_carlin_face()
	else:
		_box(head, Vector3(0.24, 0.04, 0.02), Vector3(0, 0.04, -0.33), Color(0.55, 0.3, 0.2))  # mouth line
		for sx in [-1.0, 1.0]:
			_box(head, Vector3(0.075, 0.075, 0.02), Vector3(0.09 * sx, 0.22, -0.175), WHITE)
			_box(head, Vector3(0.04, 0.045, 0.02), Vector3(0.09 * sx, 0.215, -0.188), PUPIL)
			_box(head, Vector3(0.065, 0.03, 0.02), Vector3(0.09 * sx, 0.285, -0.175), TAN)  # coonhound eyebrow pips
			_box(head, Vector3(0.08, 0.06, 0.1), Vector3(0.12 * sx, 0.06, -0.12), TAN)     # cheeks
	var ear_len := 0.28 if carlin else 0.42
	var ear_col := GOLD_DARK if carlin else BLACK
	if cat:
		# small pointed ears: rotated cubes half-buried in the head read as triangles
		ear_l = _pivot(head, Vector3(-0.14, 0.31, 0.0))
		ear_r = _pivot(head, Vector3(0.14, 0.31, 0.0))
		for e in [ear_l, ear_r]:
			var outer := _box(e, Vector3(0.12, 0.12, 0.06), Vector3(0, 0.0, 0), _cat_fur)
			outer.rotation.z = PI * 0.25
			var inner := _box(e, Vector3(0.07, 0.07, 0.02), Vector3(0, 0.0, -0.03), Color(0.95, 0.65, 0.7))
			inner.rotation.z = PI * 0.25
	else:
		ear_l = _pivot(head, Vector3(-0.2, 0.27, 0.02))
		_box(ear_l, Vector3(0.07, ear_len, 0.2), Vector3(0, -ear_len * 0.48, 0), ear_col)
		ear_r = _pivot(head, Vector3(0.2, 0.27, 0.02))
		_box(ear_r, Vector3(0.07, ear_len, 0.2), Vector3(0, -ear_len * 0.48, 0), ear_col)
	if carlin:
		_ear_base = 0.25 # a little floppier / outward

	# arms swing in the plane containing the target line (rotation about local Z)
	arms = _pivot(upper, Vector3(0, 0.74, -0.08))
	var arm_col := GOLD if carlin else hoodie_color
	if cat:
		arm_col = PJ_RED if pj else _cat_fur
	var la := _box(arms, Vector3(0.1, 0.4, 0.1), Vector3(-0.12, -0.18, -0.05), arm_col, not (carlin or cat))
	la.rotation.z = -0.4
	var ra := _box(arms, Vector3(0.1, 0.4, 0.1), Vector3(0.12, -0.18, -0.05), arm_col, not (carlin or cat))
	ra.rotation.z = 0.4
	if pj:
		for arm in [la, ra]:
			_box(arm, Vector3(0.11, 0.06, 0.11), Vector3(0, -0.12, 0), PJ_BLACK) # sleeve check band
	_box(arms, Vector3(0.14, 0.09, 0.11), Vector3(0, -0.38, -0.08), accent) # paws on the grip
	_build_club()

func _build_club() -> void:
	club = _pivot(arms, Vector3(0, -0.38, -0.08))
	club_shaft = _box(club, Vector3(0.025, 1.0, 0.025), Vector3.ZERO, Color(0.75, 0.75, 0.78))
	club_head = _box(club, Vector3(0.14, 0.06, 0.05), Vector3.ZERO, Color(0.3, 0.3, 0.32))
	set_club(false)

## Two arms angled in to the grip, plus hands/paws on the club.
func _build_arms(arm_col: Color, hand_col: Color, thick: float = 0.1) -> Array:
	arms = _pivot(upper, Vector3(0, 0.74, -0.08))
	var la := _box(arms, Vector3(thick, 0.4, thick), Vector3(-0.12, -0.18, -0.05), arm_col)
	la.rotation.z = -0.4
	var ra := _box(arms, Vector3(thick, 0.4, thick), Vector3(0.12, -0.18, -0.05), arm_col)
	ra.rotation.z = 0.4
	_box(arms, Vector3(0.14, 0.09, 0.11), Vector3(0, -0.38, -0.08), hand_col)
	_build_club()
	return [la, ra]

func _glass(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic_specular = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _sphere(parent: Node3D, r: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 14
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

# ------------------------------------------------------------------ Bacon ---
## Stocky white bulldog: wide body, flat wrinkly face, underbite with two
## little teeth, rose ears, a fawn eye patch and a pink bow tie.
func _build_bacon() -> void:
	var fur := Color(0.96, 0.95, 0.92)
	var shade := Color(0.86, 0.84, 0.8)
	var skin := Color(0.96, 0.78, 0.78)
	var fawn := Color(0.82, 0.6, 0.4)
	var bow := hoodie_color
	for sx in [-1.0, 1.0]:
		_box(self, Vector3(0.17, 0.3, 0.17), Vector3(0.15 * sx, 0.15, 0.0), fur)
		_box(self, Vector3(0.19, 0.06, 0.21), Vector3(0.15 * sx, 0.03, -0.03), shade)
	tail = _pivot(self, Vector3(0, 0.4, 0.18))
	_box(tail, Vector3(0.08, 0.08, 0.1), Vector3(0, 0, 0.04), fur)            # stubby screw tail
	upper = _pivot(self, Vector3.ZERO)
	_box(upper, Vector3(0.6, 0.48, 0.38), Vector3(0, 0.56, 0), fur)           # barrel chest
	_box(upper, Vector3(0.4, 0.3, 0.02), Vector3(0, 0.55, -0.2), shade)       # chest
	_box(upper, Vector3(0.22, 0.18, 0.02), Vector3(0.12, 0.66, 0.2), fawn)    # patch on the back
	# pink bow tie: knot + two wings
	_box(upper, Vector3(0.08, 0.08, 0.05), Vector3(0, 0.74, -0.215), bow.darkened(0.15))
	for sx in [-1.0, 1.0]:
		var wing := _box(upper, Vector3(0.15, 0.13, 0.04), Vector3(0.1 * sx, 0.74, -0.21), bow)
		wing.rotation.z = 0.25 * sx
	head = _pivot(upper, Vector3(0, 0.82, -0.04))
	_box(head, Vector3(0.48, 0.3, 0.34), Vector3(0, 0.16, 0), fur)
	_box(head, Vector3(0.22, 0.025, 0.02), Vector3(0, 0.27, -0.17), shade)    # forehead wrinkles
	_box(head, Vector3(0.16, 0.025, 0.02), Vector3(0, 0.235, -0.17), shade)
	_box(head, Vector3(0.32, 0.13, 0.1), Vector3(0, 0.1, -0.2), fur)          # short wide muzzle
	_box(head, Vector3(0.13, 0.07, 0.04), Vector3(0, 0.15, -0.26), Color(0.05, 0.05, 0.05))  # big nose
	_box(head, Vector3(0.34, 0.08, 0.12), Vector3(0, 0.02, -0.21), skin)      # underbite jaw
	for sx in [-1.0, 1.0]:
		_box(head, Vector3(0.035, 0.045, 0.02), Vector3(0.09 * sx, 0.075, -0.27), WHITE)  # snaggle teeth
		_box(head, Vector3(0.1, 0.12, 0.09), Vector3(0.17 * sx, 0.05, -0.18), fur)        # jowls
	_box(head, Vector3(0.14, 0.13, 0.02), Vector3(-0.13, 0.205, -0.168), fawn)  # eye patch
	for sx in [-1.0, 1.0]:
		_box(head, Vector3(0.07, 0.06, 0.02), Vector3(0.13 * sx, 0.2, -0.175), WHITE)
		_box(head, Vector3(0.04, 0.04, 0.02), Vector3(0.13 * sx, 0.195, -0.187), PUPIL)
	ear_l = _pivot(head, Vector3(-0.22, 0.3, 0.02))
	ear_r = _pivot(head, Vector3(0.22, 0.3, 0.02))
	for e in [ear_l, ear_r]:
		var ear := _box(e, Vector3(0.12, 0.07, 0.13), Vector3(0, 0, 0), skin.darkened(0.05))   # folded rose ears
		ear.rotation.z = 0.5 if e == ear_r else -0.5
	_build_arms(fur, shade, 0.13)

# ---------------------------------------------------------------- Dorothy ---
var _fish: Node3D

## Clanky robot with a fishbowl head and an orange goldfish swimming inside.
func _build_dorothy() -> void:
	var metal := hoodie_color
	var dark := Color(0.25, 0.27, 0.3)
	for sx in [-1.0, 1.0]:
		_box(self, Vector3(0.12, 0.3, 0.12), Vector3(0.12 * sx, 0.17, 0.0), metal)
		_box(self, Vector3(0.14, 0.05, 0.14), Vector3(0.12 * sx, 0.2, 0.0), dark)      # knee joint
		_box(self, Vector3(0.17, 0.07, 0.24), Vector3(0.12 * sx, 0.035, -0.04), dark)  # boots
	tail = _pivot(self, Vector3(0, 0.4, 0.16))
	_box(tail, Vector3(0.035, 0.035, 0.28), Vector3(0, 0, 0.13), Color(0.15, 0.15, 0.15))  # power cord
	_box(tail, Vector3(0.07, 0.05, 0.05), Vector3(0, 0, 0.28), Color(0.9, 0.75, 0.2))      # plug
	upper = _pivot(self, Vector3.ZERO)
	_box(upper, Vector3(0.48, 0.5, 0.32), Vector3(0, 0.57, 0), metal)
	_box(upper, Vector3(0.3, 0.22, 0.02), Vector3(0, 0.6, -0.165), dark)       # chest panel
	var lights := [Color(1, 0.25, 0.2), Color(1, 0.85, 0.2), Color(0.3, 1, 0.4)]
	for i in 3:
		var l := _box(upper, Vector3(0.05, 0.05, 0.02), Vector3(-0.08 + 0.08 * i, 0.65, -0.177), lights[i])
		var lm := l.material_override as StandardMaterial3D
		lm.emission_enabled = true
		lm.emission = lights[i] * 0.8
	_box(upper, Vector3(0.18, 0.03, 0.02), Vector3(0, 0.55, -0.177), Color(0.5, 0.8, 1.0))  # display bar
	for sx in [-1.0, 1.0]:
		_box(upper, Vector3(0.06, 0.06, 0.06), Vector3(0.25 * sx, 0.78, 0), dark)          # shoulder bolts
	_box(upper, Vector3(0.3, 0.06, 0.3), Vector3(0, 0.84, 0), dark)                         # neck collar
	head = _pivot(upper, Vector3(0, 0.86, 0))
	_sphere(head, 0.21, Vector3(0, 0.18, 0), _glass(Color(0.35, 0.65, 1.0, 0.45)))          # water
	_sphere(head, 0.25, Vector3(0, 0.22, 0), _glass(Color(0.85, 0.95, 1.0, 0.22)))          # glass bowl
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.1
	tm.outer_radius = 0.13
	tm.rings = 12
	tm.ring_segments = 4
	rim.mesh = tm
	rim.material_override = _glass(Color(0.9, 0.97, 1.0, 0.6))
	rim.position = Vector3(0, 0.45, 0)
	head.add_child(rim)
	_box(head, Vector3(0.2, 0.04, 0.2), Vector3(0, 0.03, 0), Color(0.55, 0.5, 0.45))       # gravel
	_box(head, Vector3(0.025, 0.12, 0.025), Vector3(0.06, 0.1, 0.05), Color(0.2, 0.7, 0.3)) # weed
	# goldfish on a pivot so it can swim laps
	_fish = _pivot(head, Vector3(0, 0.2, 0))
	var fish := _pivot(_fish, Vector3(0.0, 0, -0.08))
	var orange := Color(1.0, 0.5, 0.1)
	var body := _box(fish, Vector3(0.13, 0.08, 0.05), Vector3.ZERO, orange)
	var fm := body.material_override as StandardMaterial3D
	fm.emission_enabled = true   # glow a little so it reads orange through the blue water
	fm.emission = Color(0.9, 0.35, 0.0)
	var fin := _box(fish, Vector3(0.06, 0.07, 0.015), Vector3(0.085, 0, 0), orange.lightened(0.2))
	fin.rotation.z = PI * 0.25
	_box(fish, Vector3(0.04, 0.03, 0.02), Vector3(0, 0.05, 0), orange.lightened(0.15))      # dorsal fin
	for sz in [-1.0, 1.0]:
		_box(fish, Vector3(0.018, 0.018, 0.01), Vector3(-0.04, 0.012, 0.026 * sz), PUPIL)
	# antennae on the collar double as "ears" for the wobble animation
	ear_l = _pivot(head, Vector3(-0.17, 0.0, 0))
	ear_r = _pivot(head, Vector3(0.17, 0.0, 0))
	for e in [ear_l, ear_r]:
		_box(e, Vector3(0.02, 0.18, 0.02), Vector3(0, 0.09, 0), dark)
		var bulb := _box(e, Vector3(0.05, 0.05, 0.05), Vector3(0, 0.19, 0), Color(1, 0.3, 0.3))
		var bm := bulb.material_override as StandardMaterial3D
		bm.emission_enabled = true
		bm.emission = Color(0.8, 0.1, 0.1)
	_ear_base = -0.25
	_build_arms(metal, dark, 0.09)

# ------------------------------------------------------------------ Dewey ---
## Tiny white fluffball: poofy head, big shiny puppy eyes, fluffy ears and
## tail, and red high-top sneakers with white soles and laces.
func _build_dewey() -> void:
	var fur := Color(0.98, 0.97, 0.95)
	var fluff := Color(0.92, 0.91, 0.88)
	var shoe := hoodie_color
	for sx in [-1.0, 1.0]:
		_box(self, Vector3(0.12, 0.3, 0.13), Vector3(0.11 * sx, 0.17, 0.0), fur)
		# high-tops: sole, toe cap, upper running up the ankle, laces
		_box(self, Vector3(0.18, 0.04, 0.27), Vector3(0.11 * sx, 0.02, -0.04), WHITE)
		_box(self, Vector3(0.17, 0.08, 0.25), Vector3(0.11 * sx, 0.07, -0.04), shoe)
		_box(self, Vector3(0.15, 0.05, 0.07), Vector3(0.11 * sx, 0.06, -0.15), WHITE)
		_box(self, Vector3(0.16, 0.13, 0.16), Vector3(0.11 * sx, 0.16, 0.0), shoe)
		_box(self, Vector3(0.165, 0.025, 0.165), Vector3(0.11 * sx, 0.225, 0.0), WHITE)   # collar stripe
		for ly in [0.1, 0.14, 0.18]:
			_box(self, Vector3(0.08, 0.015, 0.02), Vector3(0.11 * sx, ly, -0.085), WHITE)
		_box(self, Vector3(0.04, 0.04, 0.01), Vector3(0.11 * sx + 0.08 * sx, 0.16, 0.0), WHITE)  # ankle star
	tail = _pivot(self, Vector3(0, 0.45, 0.14))
	_box(tail, Vector3(0.14, 0.14, 0.26), Vector3(0, 0.04, 0.1), fur)          # fluffy plume
	_box(tail, Vector3(0.1, 0.1, 0.1), Vector3(0, 0.1, 0.22), fluff)
	upper = _pivot(self, Vector3.ZERO)
	_box(upper, Vector3(0.42, 0.48, 0.3), Vector3(0, 0.57, 0), fur)
	_box(upper, Vector3(0.48, 0.12, 0.34), Vector3(0, 0.47, 0), fluff)        # fluffy tiers
	_box(upper, Vector3(0.46, 0.1, 0.33), Vector3(0, 0.68, 0), fluff)
	_box(upper, Vector3(0.3, 0.3, 0.04), Vector3(0, 0.62, -0.16), fur)         # chest floof
	head = _pivot(upper, Vector3(0, 0.84, -0.02))
	_box(head, Vector3(0.4, 0.34, 0.36), Vector3(0, 0.18, 0), fur)
	_box(head, Vector3(0.32, 0.12, 0.3), Vector3(0, 0.38, 0.01), fluff)       # top poof
	_box(head, Vector3(0.2, 0.08, 0.2), Vector3(0, 0.46, 0.0), fur)
	for sx in [-1.0, 1.0]:
		_box(head, Vector3(0.1, 0.14, 0.2), Vector3(0.2 * sx, 0.1, -0.06), fluff)       # cheek tufts
	_box(head, Vector3(0.18, 0.12, 0.12), Vector3(0, 0.09, -0.22), fur)          # little muzzle
	_box(head, Vector3(0.07, 0.05, 0.04), Vector3(0, 0.14, -0.29), Color(0.05, 0.05, 0.05))
	_box(head, Vector3(0.05, 0.05, 0.02), Vector3(0.02, 0.03, -0.28), PINK)      # tongue blep
	for sx in [-1.0, 1.0]:
		# huge glossy puppy eyes
		_box(head, Vector3(0.11, 0.11, 0.02), Vector3(0.09 * sx, 0.21, -0.185), PUPIL)
		_box(head, Vector3(0.035, 0.035, 0.01), Vector3(0.09 * sx - 0.025, 0.235, -0.197), WHITE)
		_box(head, Vector3(0.02, 0.02, 0.01), Vector3(0.09 * sx + 0.03, 0.185, -0.197), WHITE)
		var brow := _box(head, Vector3(0.08, 0.025, 0.02), Vector3(0.09 * sx, 0.285, -0.185), fluff)
		brow.rotation.z = 0.35 * sx   # pleading brows
	ear_l = _pivot(head, Vector3(-0.21, 0.3, 0.02))
	_box(ear_l, Vector3(0.1, 0.26, 0.18), Vector3(0, -0.12, 0), fluff)
	ear_r = _pivot(head, Vector3(0.21, 0.3, 0.02))
	_box(ear_r, Vector3(0.1, 0.26, 0.18), Vector3(0, -0.12, 0), fluff)
	_ear_base = 0.15
	_build_arms(fur, fluff, 0.12)

## Onezy: wide, flat Persian face with copper eyes, slit pupils, a grumpy brow and whiskers.
func _build_onezy_head() -> void:
	_box(head, Vector3(0.44, 0.32, 0.34), Vector3(0, 0.17, 0), _cat_fur)
	for sx in [-1.0, 1.0]:
		_box(head, Vector3(0.1, 0.16, 0.22), Vector3(0.23 * sx, 0.1, -0.04), _cat_light)  # cheek floof
		_box(head, Vector3(0.1, 0.1, 0.02), Vector3(0.1 * sx, 0.2, -0.175), COPPER)       # big copper eyes
		_box(head, Vector3(0.025, 0.08, 0.02), Vector3(0.1 * sx, 0.2, -0.187), PUPIL)     # slit pupils
		var brow := _box(head, Vector3(0.11, 0.025, 0.02), Vector3(0.1 * sx, 0.265, -0.18), Color(0.4, 0.4, 0.45))
		brow.rotation.z = -0.3 * sx # unimpressed
		for wy in [0.08, 0.11]:
			var wh := _box(head, Vector3(0.2, 0.008, 0.008), Vector3(0.2 * sx, wy, -0.2), Color(1, 1, 1))
			wh.rotation.z = (0.15 if wy > 0.1 else -0.1) * sx
	_box(head, Vector3(0.16, 0.08, 0.05), Vector3(0, 0.09, -0.18), _cat_light)  # flat little muzzle
	_box(head, Vector3(0.05, 0.035, 0.02), Vector3(0, 0.125, -0.21), Color(0.9, 0.5, 0.55)) # pink nose
	_box(head, Vector3(0.07, 0.015, 0.01), Vector3(0, 0.07, -0.207), Color(0.35, 0.3, 0.32)) # tiny frown
	if character == "zero":
		# red / blue 3D movie glasses: white card frame, one lens each colour, arms to the ears
		_box(head, Vector3(0.42, 0.13, 0.02), Vector3(0, 0.205, -0.2), Color(0.97, 0.97, 0.95))
		_box(head, Vector3(0.13, 0.08, 0.01), Vector3(-0.1, 0.205, -0.212), Color(0.9, 0.1, 0.12))
		_box(head, Vector3(0.13, 0.08, 0.01), Vector3(0.1, 0.205, -0.212), Color(0.15, 0.45, 1.0))
		for sx in [-1.0, 1.0]:
			_box(head, Vector3(0.015, 0.03, 0.3), Vector3(0.215 * sx, 0.22, -0.05), Color(0.97, 0.97, 0.95))

## Carlin's derpy face + backwards purple cap.
func _build_carlin_face() -> void:
	# goofy open mouth with the tongue flopped out to one side
	_box(head, Vector3(0.16, 0.04, 0.02), Vector3(0, 0.03, -0.33), Color(0.45, 0.15, 0.15))
	var tongue := _box(head, Vector3(0.07, 0.13, 0.03), Vector3(0.05, -0.03, -0.32), PINK)
	tongue.rotation.z = 0.35
	# mismatched eyes: one big pupil looking up-left, one small looking down-right
	_box(head, Vector3(0.085, 0.085, 0.02), Vector3(-0.09, 0.22, -0.175), WHITE)
	_box(head, Vector3(0.045, 0.045, 0.02), Vector3(-0.11, 0.24, -0.188), PUPIL)
	_box(head, Vector3(0.075, 0.075, 0.02), Vector3(0.09, 0.215, -0.175), WHITE)
	_box(head, Vector3(0.03, 0.03, 0.02), Vector3(0.105, 0.2, -0.188), PUPIL)
	# backwards cap: crown on top, brim sticking out the back, button on top
	_box(head, Vector3(0.38, 0.11, 0.36), Vector3(0, 0.37, 0.01), PURPLE)
	_box(head, Vector3(0.3, 0.03, 0.17), Vector3(0, 0.33, 0.25), PURPLE.darkened(0.15))
	_box(head, Vector3(0.05, 0.03, 0.05), Vector3(0, 0.44, 0.01), PURPLE.lightened(0.3))
	_box(head, Vector3(0.14, 0.05, 0.01), Vector3(0, 0.36, -0.175), Color(1, 1, 1)) # little logo patch

func set_hoodie(c: Color) -> void:
	hoodie_color = c
	for m in _hoodie_mats:
		(m as StandardMaterial3D).albedo_color = c

## Aim the club from the hands to the ball. Putter = shorter, more upright.
func set_club(is_putter: bool) -> void:
	# hands (in golfer space) at roughly (0, 0.36, -0.16); ball at (0, 0.04, -BALL_OFFSET)
	var hands := Vector3(0, 0.36, -0.16)
	var ball := Vector3(0, 0.04, -BALL_OFFSET)
	var d := ball - hands
	var length := d.length()
	club.rotation = Vector3(atan2(-d.z, -d.y), 0, 0)
	(club_shaft.mesh as BoxMesh).size = Vector3(0.025, length, 0.025)
	club_shaft.position = Vector3(0, -length * 0.5, 0)
	club_head.position = Vector3(0, -length, 0)
	club_head.rotation.x = -club.rotation.x
	if is_putter:
		(club_head.mesh as BoxMesh).size = Vector3(0.16, 0.05, 0.06)
	else:
		(club_head.mesh as BoxMesh).size = Vector3(0.12, 0.07, 0.04)

## Stand next to the ball, facing the target line.
func stand_at(ball_pos: Vector3, aim_dir: Vector3, terrain: CourseTerrain) -> void:
	var f := Vector3(aim_dir.x, 0, aim_dir.z).normalized()
	var facing := f.rotated(Vector3.UP, -PI * 0.5) # target ends up on his left
	var p := ball_pos - facing * BALL_OFFSET
	p.y = terrain.height(p.x, p.z)
	global_position = p
	look_at(p + facing, Vector3.UP)

func idle() -> void:
	anim = Anim.IDLE
	swing_angle = 0.0
	_anim_time = 0.0

func set_backswing(amount: float) -> void:
	anim = Anim.BACKSWING
	swing_angle = clampf(amount, 0.0, 1.0) * BACKSWING_MAX

func start_downswing() -> void:
	anim = Anim.DOWNSWING
	_down_from = swing_angle
	_anim_time = 0.0
	_impact_sent = false

func celebrate() -> void:
	anim = Anim.CELEBRATE
	_anim_time = 0.0

func sad() -> void:
	anim = Anim.SAD
	_anim_time = 0.0

func _process(delta: float) -> void:
	t += delta
	_anim_time += delta
	var wag_speed := 6.0
	var ear_sway := sin(t * 2.0) * 0.05
	var bob := sin(t * 2.5) * 0.01
	head.rotation = Vector3.ZERO
	upper.rotation = Vector3.ZERO
	upper.position.y = 0.0
	match anim:
		Anim.IDLE:
			upper.position.y = bob
		Anim.BACKSWING:
			upper.rotation.y = swing_angle / BACKSWING_MAX * 0.45
			head.rotation.y = -upper.rotation.y * 0.8
		Anim.DOWNSWING:
			var k := clampf(_anim_time / DOWNSWING_TIME, 0.0, 1.0)
			k = k * k
			swing_angle = lerpf(_down_from, FOLLOW_THROUGH, k)
			upper.rotation.y = swing_angle / BACKSWING_MAX * 0.45
			if not _impact_sent and swing_angle <= 0.0:
				_impact_sent = true
				impact.emit()
			if k >= 1.0:
				anim = Anim.FOLLOW
		Anim.FOLLOW:
			swing_angle = FOLLOW_THROUGH
			upper.rotation.y = -0.5
			head.rotation.y = 0.9 # watch the ball fly
			head.rotation.x = 0.25
		Anim.CELEBRATE:
			wag_speed = 22.0
			var hop := absf(sin(_anim_time * 8.0)) * 0.25
			upper.position.y = hop
			head.rotation.x = 0.3
			ear_sway = sin(_anim_time * 16.0) * 0.5
			swing_angle = lerpf(swing_angle, -2.8, delta * 6.0)
		Anim.SAD:
			wag_speed = 0.0
			head.rotation.x = -0.45
			ear_sway = 0.15
			swing_angle = lerpf(swing_angle, 0.2, delta * 4.0)
	arms.rotation.z = swing_angle
	if _fish:
		_fish.rotation.y = t * (4.0 if anim == Anim.CELEBRATE else 1.3)
		_fish.position.y = 0.2 + sin(t * 1.7) * 0.03
	tail.rotation.y = sin(t * wag_speed) * 0.5
	tail.rotation.x = 0.2 if anim == Anim.SAD else 0.7
	ear_l.rotation.z = -_ear_base - ear_sway
	ear_r.rotation.z = _ear_base + ear_sway
