extends Node
## Renders Steam library artwork for the "Non-Steam Game" shortcut into steam_art/.
##   godot --path . res://tools/make_steam_art.tscn   (needs a display, not --headless)
## Sizes follow Steam's custom artwork slots:
##   icon.png            256x256    shortcut icon (Properties -> icon)
##   capsule.png         600x900    portrait library grid
##   wide_capsule.png    920x430    wide grid / recently played
##   hero.png            1920x620   banner behind the game page
##   logo.png            1280x720   transparent title drawn over the hero

const OUT := "res://steam_art/"
const JOBS := [
	["icon", Vector2i(256, 256), true],
	["capsule", Vector2i(600, 900), false],
	["wide_capsule", Vector2i(920, 430), false],
	["hero", Vector2i(1920, 620), false],
	["logo", Vector2i(1280, 720), true],
]

var _views: Array = []
var _frames := 0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for job in JOBS:
		var vp := SubViewport.new()
		vp.size = job[1]
		vp.transparent_bg = job[2]
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var art := Art.new()
		art.kind = job[0]
		art.size = Vector2(job[1])
		vp.add_child(art)
		add_child(vp)
		_views.append([job[0], vp])

func _process(_d: float) -> void:
	_frames += 1
	if _frames < 5:
		return
	for v in _views:
		var img: Image = (v[1] as SubViewport).get_texture().get_image()
		var path := ProjectSettings.globalize_path(OUT + String(v[0]) + ".png")
		img.save_png(path)
		print("wrote ", path, "  ", img.get_size())
	get_tree().quit()


class Art extends Control:
	var kind := ""

	func _draw() -> void:
		match kind:
			"icon":
				_icon()
			"capsule":
				_scene(Rect2(Vector2.ZERO, size), 0.62)
				_face("toby", Vector2(size.x * 0.5, size.y * 0.66), 22.0)
				_title(Vector2(size.x * 0.5, size.y * 0.17), 92.0, true)
			"wide_capsule":
				_scene(Rect2(Vector2.ZERO, size), 0.66)
				_face("toby", Vector2(size.x * 0.82, size.y * 0.6), 14.0)
				_title(Vector2(size.x * 0.36, size.y * 0.42), 86.0, false)
			"hero":
				_scene(Rect2(Vector2.ZERO, size), 0.64)
				# the gang lined up along the fairway; centre kept clear for the logo
				# stock golfers only - the unlockables stay a surprise
				var xs := [0.1, 0.24, 0.84]
				var ids := ["carlin", "onezy", "zero"]
				for i in ids.size():
					_face(ids[i], Vector2(size.x * xs[i], size.y * 0.7), 11.0)
				_face("toby", Vector2(size.x * 0.5, size.y * 0.72), 13.0)
			"logo":
				_title(Vector2(size.x * 0.5, size.y * 0.5), 210.0, true)

	## Sky gradient, hills, striped fairway (same look as the title screen).
	func _scene(r: Rect2, horizon: float) -> void:
		var th: Dictionary = Course.THEMES["parkland"]
		var w := r.size.x
		var h := r.size.y
		var hz := h * horizon
		var bands := 24
		for i in bands:
			var c := (th["sky_top"] as Color).lerp(th["sky_horizon"], float(i) / bands)
			draw_rect(Rect2(0, hz * i / bands, w, hz / bands + 1), c)
		for i in 9:
			var cx := w * (i / 8.0)
			var peak := hz - h * 0.14 - (i % 3) * h * 0.035
			var pts := PackedVector2Array([Vector2(cx - w * 0.2, hz + 4), Vector2(cx, peak), Vector2(cx + w * 0.2, hz + 4)])
			draw_colored_polygon(pts, (th["hill_a"] as Color).lerp(th["hill_b"], (i % 2) * 0.5))
		draw_rect(Rect2(0, hz, w, h - hz), th["fairway_b"])
		var stripe := (h - hz) / 10.0
		for i in 5:
			draw_rect(Rect2(0, hz + stripe * (i * 2 + 0.5), w, stripe), th["fairway_a"])
		# flag
		var fx := w * 0.62
		var fy := hz - h * 0.08
		draw_rect(Rect2(fx, fy, maxf(3.0, w * 0.006), h * 0.14), Color(1, 1, 1))
		draw_colored_polygon(PackedVector2Array([Vector2(fx + 3, fy), Vector2(fx + w * 0.07, fy + h * 0.025), Vector2(fx + 3, fy + h * 0.05)]), Color(1, 0.25, 0.25))

	## 16x16 pixel portrait centred on c.
	func _face(id: String, c: Vector2, px: float) -> void:
		var face: Array = MainMenu._Backdrop.face_for(id)
		var pal: Dictionary = MainMenu._Backdrop.palette_for(id)
		var o := c - Vector2(8, 8) * px
		# soft shadow
		draw_rect(Rect2(o + Vector2(px * 1.5, px * 15.6), Vector2(px * 13, px * 0.9)), Color(0, 0, 0, 0.18))
		for y in face.size():
			var row: String = face[y]
			for x in row.length():
				var col: Color = pal.get(row[x], Color(0, 0, 0, 0))
				if col.a > 0.0:
					draw_rect(Rect2(o + Vector2(x, y) * px, Vector2(px + 0.5, px + 0.5)), col)

	## "TOBY GOLF" in the title-screen style: yellow with a thick purple outline.
	func _title(c: Vector2, fs: float, stacked: bool) -> void:
		var font := ThemeDB.fallback_font
		var lines := ["TOBY", "GOLF"] if stacked else ["TOBY GOLF"]
		var lh := fs * 0.95
		var y0 := c.y - lh * (lines.size() - 1) * 0.5 + fs * 0.35
		for i in lines.size():
			var t: String = lines[i]
			var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x
			var p := Vector2(c.x - tw * 0.5, y0 + i * lh)
			draw_string_outline(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), int(fs * 0.22), Color(0.15, 0.1, 0.3))
			draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), Color(1, 0.95, 0.4))

	## App icon: Toby's face on a rounded light-blue tile with a little flag.
	func _icon() -> void:
		var s := size.x
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.55, 0.78, 0.95)
		sb.border_color = Color(0.15, 0.1, 0.3)
		sb.set_border_width_all(int(s * 0.035))
		sb.set_corner_radius_all(int(s * 0.18))
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		# fairway strip, rounded to sit inside the tile's bottom corners
		var grass := StyleBoxFlat.new()
		grass.bg_color = Color(0.42, 0.74, 0.30)
		grass.corner_radius_bottom_left = int(s * 0.145)
		grass.corner_radius_bottom_right = int(s * 0.145)
		var b := s * 0.035
		draw_style_box(grass, Rect2(b, s * 0.72, s - b * 2.0, s * 0.28 - b))
		_face("toby", Vector2(s * 0.5, s * 0.5), s / 20.0)
