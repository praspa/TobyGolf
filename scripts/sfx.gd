class_name Sfx
extends RefCounted
## Procedurally synthesised sound effects (no audio files needed yet).
## Swap any of these for recorded .wav/.ogg files later.

const RATE := 22050

static var _cache: Dictionary = {}

## Deep "woof-woof" from a hound: a buzzy voice with a falling pitch, shaped by
## two vocal-tract resonances ("wuh" vowel) plus a breathy onset.
static func woof() -> AudioStreamWAV:
	if _cache.has("woof"):
		return _cache["woof"]
	var barks := [
		{"start": 0.0, "amp": 1.0, "f_hi": 230.0, "f_lo": 125.0, "len": 0.28},
		{"start": 0.34, "amp": 0.85, "f_hi": 215.0, "f_lo": 115.0, "len": 0.32},
	]
	var total := 0.75
	var n := int(total * RATE)
	var raw := PackedFloat32Array()
	raw.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for b in barks:
		var start := int(float(b["start"]) * RATE)
		var length: float = b["len"]
		var phase := 0.0
		var count := int(length * RATE)
		for i in count:
			var idx := start + i
			if idx >= n:
				break
			var t := float(i) / RATE
			var u := t / length
			# pitch: quick scoop up for the "w", then a long fall
			var f0: float
			if u < 0.08:
				f0 = lerpf(float(b["f_lo"]) * 1.1, float(b["f_hi"]), u / 0.08)
			else:
				f0 = lerpf(float(b["f_hi"]), float(b["f_lo"]), pow((u - 0.08) / 0.92, 0.7))
			phase = fposmod(phase + f0 / RATE, 1.0)
			# glottal-ish pulse: sawtooth softened with a bit of sine
			var voice := (2.0 * phase - 1.0) * 0.7 + sin(TAU * phase) * 0.3
			var env := clampf(t / 0.012, 0.0, 1.0) * exp(-t * 7.5) * (1.0 - smoothstep(0.85, 1.0, u))
			var breath := rng.randf_range(-1.0, 1.0) * exp(-t * 30.0) * 0.35
			raw[idx] += (voice * env + breath) * float(b["amp"])
	# formant filter bank: F1 ~ 420 Hz, F2 ~ 950 Hz, plus a chesty low band
	var f1 := _bandpass(raw, 420.0, 3.5)
	var f2 := _bandpass(raw, 950.0, 5.0)
	var f0b := _bandpass(raw, 170.0, 1.2)
	var out := PackedFloat32Array()
	out.resize(n)
	var peak := 0.0001
	for i in n:
		out[i] = f1[i] * 1.0 + f2[i] * 0.55 + f0b[i] * 0.6
		peak = maxf(peak, absf(out[i]))
	var stream := _to_wav(out, 0.9 / peak)
	_cache["woof"] = stream
	return stream

# ------------------------------------------------------------ ball strikes ---
## Sum of decaying sine partials: [freq, amp, decay_rate].
static func _partials(out: PackedFloat32Array, start: int, parts: Array, amp: float) -> void:
	for pt in parts:
		var f: float = pt[0]
		var a: float = pt[1] * amp
		var k: float = pt[2]
		var n := mini(out.size() - start, int(RATE * 5.0 / k))
		for i in n:
			var t := float(i) / RATE
			out[start + i] += sin(TAU * f * t) * a * exp(-t * k)

static func _noise_burst(out: PackedFloat32Array, start: int, length: float, amp: float, decay: float, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n := mini(out.size() - start, int(length * RATE))
	for i in n:
		var t := float(i) / RATE
		out[start + i] += rng.randf_range(-1.0, 1.0) * amp * exp(-t * decay)

## Iron: a compressed "whack" - a hard, dense strike with a short, muted
## metallic body (the ball squashing against a forged face), then the turf.
static func iron() -> AudioStreamWAV:
	if _cache.has("iron"):
		return _cache["iron"]
	var out := PackedFloat32Array()
	out.resize(int(0.32 * RATE))
	# impact crack: a very short broadband burst, darkened a little
	var crack := PackedFloat32Array()
	crack.resize(out.size())
	_noise_burst(crack, 0, 0.02, 1.0, 260.0, 3)
	var crack_lo := _bandpass(crack, 1700.0, 0.6)
	# compressed body: low-mid partials that die almost instantly (no ring)
	_partials(out, 0, [[620.0, 0.75, 55.0], [1040.0, 0.55, 65.0], [1550.0, 0.4, 80.0], [2650.0, 0.22, 110.0]], 1.0)
	_partials(out, 0, [[170.0, 0.9, 38.0], [95.0, 0.5, 30.0]], 1.0)   # the "whump"
	# divot: a short burst of dull turf noise just after impact
	var turf := PackedFloat32Array()
	turf.resize(out.size())
	_noise_burst(turf, int(0.006 * RATE), 0.12, 0.55, 28.0, 5)
	turf = _bandpass(turf, 700.0, 0.7)
	for i in out.size():
		out[i] += crack_lo[i] * 1.6 + crack[i] * 0.25 + turf[i]
	var st := _to_wav(out, 0.95 / _peak(out))
	_cache["iron"] = st
	return st

## Driver: a bright, metallic titanium "PING" - sharp strike and a high,
## ringing shell that sings for a moment after impact.
static func wood() -> AudioStreamWAV:
	if _cache.has("wood"):
		return _cache["wood"]
	var out := PackedFloat32Array()
	out.resize(int(0.7 * RATE))
	_noise_burst(out, 0, 0.008, 0.8, 500.0, 9)
	# hollow titanium head: a few clear, slightly inharmonic high modes
	_partials(out, 0, [[3120.0, 0.85, 7.5], [4470.0, 0.5, 9.0], [5960.0, 0.32, 12.0], [2210.0, 0.35, 10.0], [7900.0, 0.15, 18.0]], 1.0)
	# subtle beating between two close modes gives the "ping" its shimmer
	_partials(out, 0, [[3165.0, 0.35, 8.0]], 1.0)
	_partials(out, 0, [[140.0, 0.45, 35.0]], 1.0)
	var st := _to_wav(out, 0.95 / _peak(out))
	_cache["wood"] = st
	return st

## Putter: a clean, short putting "click" - a tight transient and a brief
## high tick from the milled face, no lingering ring.
static func putter() -> AudioStreamWAV:
	if _cache.has("putter"):
		return _cache["putter"]
	var out := PackedFloat32Array()
	out.resize(int(0.12 * RATE))
	_noise_burst(out, 0, 0.004, 0.9, 1200.0, 13)
	_partials(out, 0, [[2650.0, 0.8, 90.0], [5300.0, 0.4, 130.0], [1250.0, 0.35, 110.0]], 1.0)
	var st := _to_wav(out, 0.85 / _peak(out))
	_cache["putter"] = st
	return st

## Gallery gasp: a crowd's sharp intake of breath turning into a falling
## "ooohhh" - a dozen detuned voices through "oh" vowel formants, plus breath.
static func gasp() -> AudioStreamWAV:
	if _cache.has("gasp"):
		return _cache["gasp"]
	var dur := 1.7
	var n := int(dur * RATE)
	var voices := PackedFloat32Array()
	voices.resize(n)
	var breath := PackedFloat32Array()
	breath.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for v in 12:
		var f_base := rng.randf_range(115.0, 250.0)   # mix of low and high voices
		var onset := rng.randf_range(0.0, 0.12)
		var length := rng.randf_range(1.0, 1.5)
		var amp := rng.randf_range(0.6, 1.0)
		var vib := rng.randf_range(4.0, 6.5)
		var ph := 0.0
		var st0 := int(onset * RATE)
		var cnt := mini(int(length * RATE), n - st0)
		for i in cnt:
			var t := float(i) / RATE
			var u := t / length
			# pitch: jumps up with the surprise, then sags
			var contour := 1.18 - 0.3 * u + 0.12 * exp(-t * 14.0)
			var f := f_base * contour * (1.0 + 0.012 * sin(TAU * vib * t))
			ph = fposmod(ph + f / RATE, 1.0)
			var env := clampf(t / 0.12, 0.0, 1.0) * pow(1.0 - u, 1.4)
			voices[st0 + i] += ((2.0 * ph - 1.0) * 0.6 + sin(TAU * ph) * 0.4) * env * amp
	for i in n:
		var t := float(i) / RATE
		# the sharp "hhh" intake at the start, then breathiness under the vowel
		var e := 0.9 * exp(-pow((t - 0.06) / 0.05, 2.0)) + 0.15 * exp(-t * 2.0)
		breath[i] = rng.randf_range(-1.0, 1.0) * e
	var f1 := _bandpass(voices, 480.0, 3.0)
	var f2 := _bandpass(voices, 840.0, 4.0)
	var f3 := _bandpass(voices, 2600.0, 6.0)
	var air := _bandpass(breath, 1600.0, 0.7)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = f1[i] + f2[i] * 0.6 + f3[i] * 0.12 + air[i] * 0.5
	var st := _to_wav(out, 0.8 / _peak(out))
	_cache["gasp"] = st
	return st

## Ball dropping into the tin cup: a hollow first clank and a few rattles,
## each exciting the cup's inharmonic tin partials.
static func cup() -> AudioStreamWAV:
	if _cache.has("cup"):
		return _cache["cup"]
	var out := PackedFloat32Array()
	out.resize(int(0.9 * RATE))
	var tin := [[1180.0, 0.5, 9.0], [2870.0, 0.4, 12.0], [4410.0, 0.3, 16.0], [6290.0, 0.18, 22.0], [610.0, 0.35, 14.0]]
	var hits := [[0.0, 1.0], [0.085, 0.55], [0.14, 0.38], [0.18, 0.25], [0.205, 0.15], [0.222, 0.09]]
	for h in hits:
		var st0 := int(float(h[0]) * RATE)
		_noise_burst(out, st0, 0.005, 0.6 * float(h[1]), 700.0, 17 + st0)
		_partials(out, st0, tin, float(h[1]))
	_partials(out, int(0.24 * RATE), [[180.0, 0.4, 25.0]], 1.0) # ball settles: hollow clunk
	var st := _to_wav(out, 0.9 / _peak(out))
	_cache["cup"] = st
	return st

## Water splash: a hiss of noise, bright at first then darker.
static func splash() -> AudioStreamWAV:
	if _cache.has("splash"):
		return _cache["splash"]
	var raw := PackedFloat32Array()
	raw.resize(int(0.8 * RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for i in raw.size():
		var t := float(i) / RATE
		raw[i] = rng.randf_range(-1.0, 1.0) * (clampf(t / 0.01, 0.0, 1.0) * exp(-t * 5.5))
	var hi := _bandpass(raw, 2600.0, 0.7)
	var lo := _bandpass(raw, 500.0, 0.9)
	var out := PackedFloat32Array()
	out.resize(raw.size())
	for i in raw.size():
		var t := float(i) / RATE
		var k := exp(-t * 7.0)
		out[i] = hi[i] * k + lo[i] * (1.2 - k)
	_partials(out, int(0.02 * RATE), [[260.0, 0.25, 12.0]], 1.0) # "bloop"
	var st := _to_wav(out, 0.8 / _peak(out))
	_cache["splash"] = st
	return st

## Ball landing on grass: a subtle, soft low thud (no ring).
static func thud() -> AudioStreamWAV:
	if _cache.has("thud"):
		return _cache["thud"]
	var raw := PackedFloat32Array()
	raw.resize(int(0.18 * RATE))
	_noise_burst(raw, 0, 0.18, 1.0, 45.0, 31)
	var out := _bandpass(raw, 160.0, 1.1)
	var body := _bandpass(raw, 420.0, 1.5)
	for i in out.size():
		out[i] = out[i] + body[i] * 0.35
	_partials(out, 0, [[85.0, 0.25, 30.0]], 1.0)
	var st := _to_wav(out, 0.8 / _peak(out))
	_cache["thud"] = st
	return st

## Ball landing in sand: a soft, gritty "pff".
static func sand() -> AudioStreamWAV:
	if _cache.has("sand"):
		return _cache["sand"]
	var raw := PackedFloat32Array()
	raw.resize(int(0.3 * RATE))
	_noise_burst(raw, 0, 0.3, 1.0, 14.0, 37)
	var out := _bandpass(raw, 2400.0, 0.9)
	var lo := _bandpass(raw, 300.0, 1.0)
	for i in out.size():
		out[i] += lo[i] * 0.5
	var st := _to_wav(out, 0.6 / _peak(out))
	_cache["sand"] = st
	return st

## Ball hitting a tree trunk: a hollow wooden "clunk" - knock transient plus
## the low, quickly damped resonances of a log.
static func wood_clunk() -> AudioStreamWAV:
	if _cache.has("clunk"):
		return _cache["clunk"]
	var out := PackedFloat32Array()
	out.resize(int(0.35 * RATE))
	_noise_burst(out, 0, 0.008, 0.7, 500.0, 41)
	_partials(out, 0, [[310.0, 0.9, 22.0], [745.0, 0.55, 30.0], [1180.0, 0.35, 40.0], [1890.0, 0.18, 55.0], [160.0, 0.5, 26.0]], 1.0)
	var st := _to_wav(out, 0.95 / _peak(out))
	_cache["clunk"] = st
	return st

## Ball rattling through branches or palm fronds: a leafy rustle with a few
## twig ticks.
static func rustle() -> AudioStreamWAV:
	if _cache.has("rustle"):
		return _cache["rustle"]
	var raw := PackedFloat32Array()
	raw.resize(int(0.5 * RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 43
	for i in raw.size():
		var t := float(i) / RATE
		var crackle := 1.0 if rng.randf() < 0.02 else 0.25
		raw[i] = rng.randf_range(-1.0, 1.0) * crackle * clampf(t / 0.01, 0.0, 1.0) * exp(-t * 7.0)
	var out := _bandpass(raw, 3200.0, 0.8)
	for k in 4:
		_partials(out, int((0.01 + 0.06 * k) * RATE), [[900.0 + 230.0 * k, 0.25, 70.0]], 1.0 - 0.2 * k)
	var st := _to_wav(out, 0.7 / _peak(out))
	_cache["rustle"] = st
	return st

# ----------------------------------------------------------------- ambient ---
const AMB_RATE := 16000
const AMB_LEN := 12.0

## Looping ambience per course theme:
##   parkland (Puppy Meadows)        - forest: leaves in the breeze, a few birds, crickets
##   tropical (Barking Paradise)     - small waves lapping on sand, seagulls
##   desert   (Kitty Litter Dunes)   - mostly wind, the odd vulture squawk
static func ambient(theme_name: String) -> AudioStreamWAV:
	var key := "amb_" + theme_name
	if _cache.has(key):
		return _cache[key]
	var xf := int(1.0 * AMB_RATE)            # crossfade so the loop is seamless
	var n := int(AMB_LEN * AMB_RATE)
	var total := n + xf
	var out := PackedFloat32Array()
	out.resize(total)
	var rng := RandomNumberGenerator.new()
	rng.seed = theme_name.hash()
	match theme_name:
		"tropical":
			_amb_waves(out, rng)
			for at in [1.6, 6.9, 9.4]:
				_seagull(out, int(at * AMB_RATE), rng)
		"desert":
			_amb_wind(out, rng)
			_vulture(out, int(3.2 * AMB_RATE), rng)
			_vulture(out, int(8.6 * AMB_RATE), rng)
		_:
			_amb_forest(out, rng)
	# fold the tail over the head for a seamless loop
	for i in xf:
		var k := float(i) / xf
		out[i] = out[i] * k + out[n + i] * (1.0 - k)
	out.resize(n)
	var data := PackedByteArray()
	data.resize(n * 2)
	var g := 0.5 / _peak(out)
	for i in n:
		data.encode_s16(i * 2, int(clampf(out[i] * g, -1.0, 1.0) * 32767.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = AMB_RATE
	st.stereo = false
	st.data = data
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = n
	_cache[key] = st
	return st

## Forest: soft leaf rustle riding slow breezes, a handful of distant birds,
## and two crickets chirping in pulse trains.
static func _amb_forest(out: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	var total := out.size()
	var raw := PackedFloat32Array()
	raw.resize(total)
	var lp := 0.0
	for i in total:
		var t := float(i) / AMB_RATE
		var breeze := 0.35 + 0.65 * pow(0.5 - 0.5 * cos(TAU * t / 6.0 + 0.6 * sin(TAU * t / 4.0)), 2.0)
		var nz := rng.randf_range(-1.0, 1.0)
		lp += (nz - lp) * 0.05
		raw[i] = nz * breeze
		out[i] = lp * 0.5 * breeze      # low rumble of the canopy
	var leaves := _bandpass_rate(raw, 2600.0, 0.7, AMB_RATE)
	for i in total:
		out[i] += leaves[i] * 0.35
	# crickets: a 4.6 kHz / 5.1 kHz carrier gated into 3-4 pulse chirps
	for cr in [[4600.0, 0.55, 0.0, 4], [5150.0, 0.8, 0.27, 3]]:
		var f: float = cr[0]
		var period: float = cr[1]
		var t0: float = cr[2]
		var pulses: int = cr[3]
		var tt := t0
		while tt < float(total) / AMB_RATE:
			for k in pulses:
				var st0 := int((tt + k * 0.034) * AMB_RATE)
				var cnt := int(0.022 * AMB_RATE)
				for i in cnt:
					if st0 + i >= total:
						break
					var u := float(i) / cnt
					out[st0 + i] += sin(TAU * f * float(i) / AMB_RATE) * sin(PI * u) * 0.05
			tt += period
	var at := 0.9
	while at < AMB_LEN - 1.0:
		_chirp(out, int(at * AMB_RATE), rng)
		at += rng.randf_range(1.8, 3.6)

## Small waves lapping on sand: each wave is a soft rising swash, a little
## fizz as it spreads, then a gentle drawback; plus a quiet low wash.
static func _amb_waves(out: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	var total := out.size()
	var raw := PackedFloat32Array()
	raw.resize(total)
	var env := PackedFloat32Array()
	env.resize(total)
	var lp := 0.0
	var lp2 := 0.0
	var wave_t := 4.0   # 3 waves per 12 s loop
	for i in total:
		var t := float(i) / AMB_RATE
		var ph := fposmod(t, wave_t) / wave_t
		var swash := smoothstep(0.0, 0.18, ph) * exp(-maxf(0.0, ph - 0.18) * 5.0)
		var back := 0.35 * smoothstep(0.35, 0.5, ph) * (1.0 - smoothstep(0.5, 0.9, ph))
		env[i] = swash + back
		var nz := rng.randf_range(-1.0, 1.0)
		raw[i] = nz * env[i]
		lp += (nz - lp) * 0.04
		lp2 += (lp - lp2) * 0.04
		out[i] = lp2 * (0.5 + 0.8 * swash)
	var fizz := _bandpass_rate(raw, 1800.0, 0.6, AMB_RATE)
	var hiss := _bandpass_rate(raw, 4200.0, 0.8, AMB_RATE)
	for i in total:
		out[i] += fizz[i] * 0.55 + hiss[i] * 0.25 * env[i]

## Desert wind: low-passed noise in long gusts plus a narrow whistling band.
static func _amb_wind(out: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	var total := out.size()
	var lp1 := 0.0
	var lp2 := 0.0
	for i in total:
		var t := float(i) / AMB_RATE
		var nz := rng.randf_range(-1.0, 1.0)
		lp1 += (nz - lp1) * 0.06
		lp2 += (lp1 - lp2) * 0.06
		var gust := 0.3 + 0.7 * pow(0.5 - 0.5 * cos(TAU * t / 6.0 + sin(TAU * t / 12.0) * 2.0), 2.0)
		out[i] = lp2 * 1.4 * gust
	var whistle := _bandpass_rate(out, 520.0, 9.0, AMB_RATE)
	var whistle2 := _bandpass_rate(out, 870.0, 12.0, AMB_RATE)
	for i in total:
		out[i] += whistle[i] * 2.2 + whistle2[i] * 1.2

## A little songbird phrase: 2-5 quick upward/downward sine sweeps.
static func _chirp(out: PackedFloat32Array, start: int, rng: RandomNumberGenerator) -> void:
	var notes := rng.randi_range(2, 5)
	var base := rng.randf_range(2600.0, 4200.0)
	var at := start
	for k in notes:
		var dur := rng.randf_range(0.05, 0.11)
		var cnt := int(dur * AMB_RATE)
		var f0 := base * rng.randf_range(0.85, 1.1)
		var f1 := f0 * rng.randf_range(1.15, 1.5) if k % 2 == 0 else f0 * rng.randf_range(0.7, 0.9)
		var ph := 0.0
		for i in cnt:
			if at + i >= out.size():
				return
			var u := float(i) / cnt
			ph += lerpf(f0, f1, u) / AMB_RATE
			out[at + i] += sin(TAU * ph) * sin(PI * u) * 0.08
		at += cnt + int(rng.randf_range(0.02, 0.06) * AMB_RATE)

## Seagull: a run of 2-4 nasal "kyow" calls - a quick rise then a long fall,
## rich in harmonics with a little rasp.
static func _seagull(out: PackedFloat32Array, start: int, rng: RandomNumberGenerator) -> void:
	var calls := rng.randi_range(2, 4)
	var at := start
	var gain := rng.randf_range(0.6, 1.0)
	for c in calls:
		var dur := rng.randf_range(0.22, 0.34) if c > 0 else rng.randf_range(0.38, 0.5)
		var cnt := int(dur * AMB_RATE)
		var peak := rng.randf_range(1450.0, 1750.0)
		var ph := 0.0
		for i in cnt:
			if at + i >= out.size():
				return
			var u := float(i) / cnt
			var f := lerpf(peak * 0.75, peak, u / 0.15) if u < 0.15 else lerpf(peak, peak * 0.62, (u - 0.15) / 0.85)
			f *= 1.0 + 0.015 * rng.randf_range(-1.0, 1.0)
			ph += f / AMB_RATE
			var env := clampf(u / 0.05, 0.0, 1.0) * pow(1.0 - u, 0.8)
			var v := sin(TAU * ph) + 0.55 * sin(TAU * ph * 2.0) + 0.3 * sin(TAU * ph * 3.0) + 0.12 * sin(TAU * ph * 4.0)
			out[at + i] += v * env * 0.05 * gain
		at += cnt + int(rng.randf_range(0.08, 0.16) * AMB_RATE)

## Vulture: a harsh, low, raspy squawk/croak - a buzzy pulse train with a
## noisy edge and a short falling pitch, often doubled.
static func _vulture(out: PackedFloat32Array, start: int, rng: RandomNumberGenerator) -> void:
	var calls := rng.randi_range(1, 2)
	var at := start
	for c in calls:
		var dur := rng.randf_range(0.28, 0.42)
		var cnt := int(dur * AMB_RATE)
		var f0 := rng.randf_range(260.0, 330.0)
		var ph := 0.0
		var seg := PackedFloat32Array()
		seg.resize(cnt)
		for i in cnt:
			var u := float(i) / cnt
			var f := f0 * (1.1 - 0.35 * u) * (1.0 + 0.06 * rng.randf_range(-1.0, 1.0))
			ph = fposmod(ph + f / AMB_RATE, 1.0)
			var buzz := (2.0 * ph - 1.0) + rng.randf_range(-0.6, 0.6)   # raspy sawtooth
			var env := clampf(u / 0.04, 0.0, 1.0) * (1.0 - smoothstep(0.7, 1.0, u)) * (0.75 + 0.25 * sin(TAU * 23.0 * u))
			seg[i] = buzz * env
		var formant := _bandpass_rate(seg, 900.0, 2.0, AMB_RATE)
		var formant2 := _bandpass_rate(seg, 1700.0, 3.0, AMB_RATE)
		for i in cnt:
			if at + i >= out.size():
				return
			out[at + i] += (formant[i] + formant2[i] * 0.6) * 0.16
		at += cnt + int(rng.randf_range(0.12, 0.22) * AMB_RATE)

static func _peak(x: PackedFloat32Array) -> float:
	var p := 0.0001
	for v in x:
		p = maxf(p, absf(v))
	return p

static func _bandpass(x: PackedFloat32Array, freq: float, q: float) -> PackedFloat32Array:
	return _bandpass_rate(x, freq, q, RATE)

static func _bandpass_rate(x: PackedFloat32Array, freq: float, q: float, rate: int) -> PackedFloat32Array:
	# RBJ cookbook band-pass (0 dB peak gain)
	var w0 := TAU * freq / rate
	var alpha := sin(w0) / (2.0 * q)
	var a0 := 1.0 + alpha
	var b0 := alpha / a0
	var b2 := -alpha / a0
	var a1 := -2.0 * cos(w0) / a0
	var a2 := (1.0 - alpha) / a0
	var y := PackedFloat32Array()
	y.resize(x.size())
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in x.size():
		var xi := x[i]
		var yi := b0 * xi + b2 * x2 - a1 * y1 - a2 * y2
		y[i] = yi
		x2 = x1
		x1 = xi
		y2 = y1
		y1 = yi
	return y

static func _to_wav(samples: PackedFloat32Array, gain: float) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	var fade := mini(int(0.012 * RATE), samples.size())   # short fade-out: no click at the cut
	for i in samples.size():
		var k := minf(1.0, float(samples.size() - 1 - i) / fade)
		var v := int(clampf(samples[i] * gain * k, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s
