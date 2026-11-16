# Toby Golf 0.1

A light-hearted, chunky retro 3D golf game starring **Toby**, a black & tan
coonhound in a light blue hoodie, **Carlin**, a derpy golden retriever in a backwards
purple cap, **Onezy**, a gray Persian cat in black & red pajamas, **Zero**,
a black Persian cat in red & blue 3D movie glasses, **Bacon**, a white bulldog in a
pink bow tie, **Dorothy**, a robot with a goldfish bowl for a head, and **Dewey**, a
little white fluffball in high-top sneakers. Built with **Godot 4.5 + GDScript**, all
geometry is generated in code (no imported art), targeting the **Steam Deck**
(1280x800, 60 FPS, gamepad) with keyboard support for desktop testing.

## Run it

```bash
# Ubuntu: install Godot 4.5+ (e.g. from godotengine.org, or flatpak org.godotengine.Godot)
godot --headless --import --path ~/projects/toby-golf  # first time: build the class/import cache
godot --path ~/projects/toby-golf                      # play
godot --editor --path ~/projects/toby-golf             # open the editor
```

## Controls

| Action | Steam Deck / Gamepad | Keyboard |
|---|---|---|
| Aim | Left stick / D-pad L-R | Left/Right, A/D |
| Club | LB / RB, D-pad up/down | Up/Down, W/S |
| Swing (3-click) | A | Space / Enter |
| Cancel swing | B | Backspace / X |
| Fast-forward ball (x4, toggle) | A while ball is moving | Space / Enter |
| Spin & shape (draw/fade/top/back) | Right stick (R3 resets) | I J K L (U resets) |
| Special shot (Zoomies) | X | P |
| Overview camera | Y | V / C |
| Zoom | RT / LT | Z / Q |
| Scorecard (hold) | View | Tab |
| Pause / quit to main menu | Menu | Esc |

**Swing meter:** press once to start, again to lock **power**, then a third time
as the cursor crosses the **white line**. Early = pull/hook left, late =
push/slice right. Putts are two clicks: distance only - read the green grid (dots drift downhill).

The cyan **Pin** mark on the bar is the power that would carry the club exactly to
the pin from a perfect lie with no wind (putts: the roll distance). It doesn't adjust
for lie, wind or elevation - you do. The **LIE** badge above the meter shows how much
of a full shot the current lie allows, e.g. `LIE: ROUGH 80% (-20% distance)`, so from
the rough you'd swing past the mark. "100% = N yd" is the club's full carry from a
perfect lie.

## What's in 0.1

- Three 18-hole courses (par 72 each, front and back nine of par 36), chosen on a course select screen. The scorecard reads like a real card: front nine + OUT, back nine + IN, total and +/-:
  - **Puppy Meadows** - traditional parkland: pines, ponds, friendly greens
  - **Barking Paradise** - tropical Caribbean: palms, ocean edges, island greens, and fairways broken up by creeks and lagoons with fairway islands to lay up onto
  - **Kitty Litter Dunes** - desert southwest: pot bunkers scattered through every driving and lay-up zone, waste areas, saguaro cactus, rocks in the fairway, canyon walls and mesas
- Course themes drive surface colours, sky/fog, tree type, terrain shape and distant scenery
- Waste areas play easier than bunkers (88% distance); rocks and cactus deflect the ball
- Terrain with fairway, rough, bunkers, ponds, fringe, sloped greens, trees, OOB. Fairways aren't flat: long gentle swales (~60 m apart) plus small undulations, strength per theme via `"rolls"` in `Course.THEMES` - balls kick and roll with the slopes
- Full bag (Driver -> Putter); auto club/aim suggestions (auto aim lays up short of water and picks a club to match); landing marker + arc preview
- Ball physics: drag, Magnus lift from backspin, side-spin curve, wind, bounce/roll
  per surface, backspin "check" on greens, slope break, cup capture & lip-outs,
  tree collisions, water drops and stroke-and-distance OOB
- Lie affects the next shot (distance %, spin, mis-hit severity); driver off the deck is harder
- Character stats: power, accuracy (perfect-window size), natural shot shape, special shot
- Putting read: faint grid squared to your putt line that re-lays as you aim. Each line is coloured by the slope along it: green = flat, yellow = mild, red = dramatic. Slope markers slide downhill *along the grid lines* (faster = steeper). The HUD reads e.g. "Uphill 1.2% - breaks left 0.8%" Only the area around the putt is drawn (behind the ball to just past the putt length, a few metres either side).
- Fast-forward: press A / Space while the ball is flying or rolling for x4 speed
- Windsock HUD: streams downwind (up = away from you), longer/straighter with speed, strength bars
- Characters: pick from a grid of pixel portraits (one pick per player; locked challengers show as black "??" silhouettes until won in Match Play Challenge):
  - **Toby** - power 100%, accuracy 75%, slight draw. Powerup **Zoomies** (x2/round): +12% distance, extra roll, hound woof
  - **Carlin** - power 93%, accuracy 85%, slight fade. Powerup **Pin Seeker** (x2/round): ignores wind and mis-hits, homes in and sticks at a random spot within ~1-3 m of the pin (limited to the club's reach)
  - **Onezy** - power 88%, accuracy 95%, straight. Powerup **Cat-like Reflexes** (x2/round): the whole accuracy zone counts as perfect - an insured perfect strike
  - **Zero** - power 97%, accuracy 70%, slight fade. Passive **Nine Lives** (x3/round): when his ball finishes in sand or water or clips a tree, 50% chance it pops out onto the fairway/fringe with a clear line to the pin - no penalty
  - **Bacon** - power 104%, accuracy 65%, draw. Powerup **Dig In** (x3/round): ignores the lie penalty - rough, sand and waste play like fairway
  - **Dorothy** - power 94%, accuracy 80%, straight. Powerup **Bubble Shot** (x2/round): the ball flies in a water bubble - dead straight (no mis-hit curve or shape), ignores wind, and bursts on landing with a splash that springs it forward (it even skips off water)
  - **Dewey** - power 84%, accuracy 88%, slight draw. Powerup **Puppy Eyes** (x3/round): the swing meter runs at 45% speed
- **Match Play Challenge**: an 18-hole match against a CPU challenger. Bacon, Dorothy and Dewey start locked and are unlocked one at a time, in order, by beating them: **Dorothy** (Rookie) -> **Bacon** (Pro) -> **Dewey** (Champion). Holes are won by the lower score (once one side holes out and the other can't tie, the other picks up). The match ends as soon as one side is more holes up than there are holes left to play - e.g. 3 up with 2 to play wins "3&2". At "dormie" (as many holes up as are left) play continues, since the trailing side can still halve. A halved match doesn't unlock. The scorecard shows the running match score per hole. Press A / Space during the CPU's turn to fast-forward its shot. Beaten challengers can be rematched. Progress is saved in `user://progress.json` (delete it to re-lock everyone).
- CPU golfers plan with the real ball physics (club, aim, power, lay-ups, putt reads on a simulated green roll), then make skill-based mistakes: power and aim spread, accuracy-click timing, only partly allowing for wind, putting spread and the occasional blunder. They use their powerups too. Tune in `Game.CPU_SKILL`.
- Stroke play, 1-4 players local pass & play, scorecard
- Pause menu (Menu / Esc) with *Quit to Main Menu* (asks to confirm; the round isn't recorded)
- Leaderboard on the main screen: all-time top 10 completed rounds (score, to par, character, course, date), saved in `user://leaderboard.json` (on Linux: `~/.local/share/godot/app_userdata/Toby Golf/`)
- Sounds, all synthesised in code: compressed iron whack, metallic driver/wood "ping", putter click, tin-cup rattle when holed, a gallery gasp when a shot finds water, OB, a bunker, deep rough or runs through the green, a subtle thud when the ball lands on grass (a soft "pff" in sand), a wooden clunk off tree trunks (leafy rustle through branches), water splash, Toby's woof, and looping course ambience: Puppy Meadows - forest breeze, birds and crickets; Barking Paradise - waves lapping on sand and seagulls; Kitty Litter Dunes - wind and the odd vulture squawk
- Doglegs: holes can declare `"dogleg": [{"at": metres, "deg": angle}]` in `course.gd`; everything past the corner pivots with the fairway and bounds are recomputed

## Project layout

```
project.godot           1280x800, GL Compatibility renderer, autoload Game
scenes/main.tscn        root scene -> scripts/main.gd
scripts/game.gd         autoload: players, scores, characters, clubs, input map
scripts/course.gd       courses, themes and hole layouts (pure data - edit to design holes)
scripts/terrain.gd      heightfield, surfaces, mesh/trees/water/slope-arrow builders
scripts/ball.gd         ball flight/bounce/roll physics + carry solver
scripts/golfer.gd       Toby model + procedural swing/celebrate/sad animations
scripts/round.gd        one hole: turn order, aiming, shots, results, scoring
scripts/swing_meter.gd  three-click meter
scripts/hud.gd          HUD, wind dial, spin ball, minimap, scorecard, pause
scripts/camera_rig.gd   aim / overview / follow cameras
scripts/slope_grid.gd   green contour grid + downhill dots
scripts/sfx.gd          procedurally synthesised sounds and ambience
scripts/leaderboard.gd  all-time top 10, saved to user://leaderboard.json
scripts/cpu.gd          CPU opponent for Match Play (shot planning + mistakes)
scripts/menu.gd         title menu, leaderboard, course select
```

### Tuning knobs
- Club distances / launch / spin: `Game.CLUBS` (ball speed is solved so the meter is linear in carry)
- Characters: `Game.CHARACTERS` (add more; `unlocked` is reserved for future unlocks)
- Surface behaviour & lie penalties: `CourseTerrain.SURF`
- Flight model: `Ball.KD`, `Ball.KM`, `Ball.SPIN_TAU`
- Meter speed/difficulty: `SwingMeter.RISE_TIME`, `RETURN_TIME`, `ACC_ZONE`

## Steam Deck

One-time setup on the Deck (Desktop Mode -> Konsole): `passwd` (set a password for
`deck`) and `sudo systemctl enable --now sshd`.

Then from this machine:

```bash
./deploy-to-steamdeck.sh            # host 'steamdeck' (falls back to steamdeck.local)
./deploy-to-steamdeck.sh 192.168.1.50
```

It builds the game, asks for the Deck password once (or uses your SSH key), and
installs to `/home/deck/Games/TobyGolf/`. In Desktop Mode Steam: *Games -> Add a
Non-Steam Game -> Browse*, file filter "All Files", pick `TobyGolf.sh`. Re-run the
script to update; the Steam shortcut keeps working.

Steam artwork (icon, library capsule, wide capsule, hero banner, logo) lives in
`steam_art/` and is copied to `/home/deck/Games/TobyGolf/artwork/`; the script prints
where each image goes in Steam. Regenerate it from the game's pixel art with
`godot --path . res://tools/make_steam_art.tscn`.

If Godot export templates are installed (*Editor -> Manage Export Templates*) it does a
proper release export; otherwise it ships the game data (`TobyGolf.pck`) with the
Godot runtime binary next to it - same engine, same result, ~130 MB bigger.

## Roadmap ideas
CPU opponents (match play, simulated tournaments), unlockable characters and courses,
character-specific special shots, sound/music, more animation, replays.
