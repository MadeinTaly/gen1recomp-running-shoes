# Changelog

## 1.7.1 — the trail goes behind you, and looks like something

Reported from play: running rightwards drew the trail on top of the
character. `render.hud` composites over the **finished** frame, so anything
this mod draws inside the player's own 16×16 sprite box is drawn on him
rather than behind him — and the trail was shed at his centre and drifted out
from there, which put its freshest and brightest marks squarely on the
sprite. It reads worst on whichever side the character art happens to reach
the trailing edge, which is why one direction looked fine and the other did
not.

Two changes, and the second is the one that makes it a guarantee:

- **The trail is shed a cell and a quarter behind the heels**, along the
  direction of travel, instead of at the player's own centre. One cell only
  just cleared the sprite and still read as crowding him on the way right.
- **Nothing is drawn inside the sprite's box, ever.** The box is grown by how
  far the particle reaches from its own centre before the test is made —
  asymmetrically, because a bolt is a jagged line climbing eleven pixels
  *upward* from its base where a puff of smoke reaches four in every
  direction, and a guard written around the centre alone lets exactly that
  case through. The suite now pins this across all four directions and all
  three kinds: twelve runs, zero marks on the character.

**And the particles are no longer boxes.** They used to be four rectangles —
two crossed bars whose overlap knocked the corners off a square, the body
inset in that, a lit square for the core. Round at a glance, obviously a box
the moment you looked at one.

They are drawn as **rows** now: one filled rectangle per scanline, its width
read out of a shape table, so the outline is whatever curve the table
describes.

| | |
| --- | --- |
| `DUST` | a real disc, shaded in three bands, highlight up top where a puff catches the light |
| `FLAMES` | a teardrop — pinched to a point at the tip, widest about two thirds down, rounded off at the base, with the lit core low where a flame is hottest |
| `BOLTS` | thick where it leaves the ground and a hair at its tip, instead of the same width the whole climb |

The shape tables are computed once at load, so the per-frame cost is one
draw call per row rather than per pixel: a six-pixel puff is twelve
rectangles where the old blob was four, and the old one was not round.

No new options, no change to the colour ramps, and nothing outside the
`RUN FX` row moves.

## 1.7.0 — the shoes work in first and third person

Everything below is inert unless the Dramatic Shape voxel mod is installed
*and* one of its free cameras is up. It went out as `1.7.0-beta.1` first and
is promoted here on a confirmed run of the two mods together, which is the
only test that counts for a cross-mod fix.

Fixes [#1](../../issues/1): with the voxel mod installed, the shoes worked
until you switched to the first- or third-person camera, where every row of
this mod went quiet — no speed, no cut grass, no safe grass — and came back
the moment you returned to the overhead view.

**Why.** Those two cameras do not walk the grid. The voxel mod's
`lib/FreeMove.lua` wraps `OverworldState:handleInput` and, while a free
camera drives, replaces the grid step outright with a continuous
camera-relative walk — a point in world pixels advanced by `FreeMove.WALK`
(1.0) or `FreeMove.BIKE` (2.0) pixels a frame. The player's logical cell is
kept honest and `onStepComplete` still fires once per cell crossed, so warps
and encounters carry on — but there is no step duration any more, so
`movement.speed` is never asked. That hook is not just where this mod's
speed comes from; it is the only thing that sets the flag `BURN GRASS`,
`SAFE GRASS` and the trail all read. One missing call, every row silent, and
nothing in the log to say so.

**The fix converts exactly.** Sixteen frames for a sixteen-pixel cell *is*
one pixel a frame — which is why `FreeMove.WALK` is 1.0 in the first place.
Dividing a step duration by your multiplier and multiplying a walk speed by
it are the same sentence, so the ladder, the floor (x4, four frames a cell,
four pixels a frame) and the `BOOST BIKE` / `BOOST SURF` gates are all the
numbers the grid arm already keeps.

- **RUN SPEED works in 1ST and 3RD**, at the multiplier you picked, with the
  same floor and the same opt-in for the bicycle and for surfing.
- **BURN GRASS and SAFE GRASS work there too**, because the running flag is
  set again.
- **The mod never hard-depends on the voxel mod.** It is declared as an
  optional dependency and found through `mod.find`, on a logic tick rather
  than at load, so enabling either mod mid-session works and neither one
  missing costs the other anything.
- **The wrap is honest about what it is.** The voxel mod publishes its module
  namespace as `mod.exports.lib` for companion mods, which is how this
  reaches `FreeMove`; wrapping `FreeMove.tick` on top of that is a
  monkeypatch and is commented as one. It is confined to a single call — set
  the two constants, run the original, put them back whether it returned or
  threw — and a throw out of the voxel mod's own walk is passed straight on
  rather than swallowed. If that module is ever restructured, the failure
  mode is that running stops working inside those cameras, which is exactly
  where it stood before this release.

**RUN FX still does not draw under the voxel pipeline**, at any of its rungs
including the overhead ones, and this release does not pretend otherwise.
The trail is a screen-space overlay measured off the engine's 2D camera; it
cannot follow a depth-buffered one, and drawing it anyway would put it
somewhere you are not. The mod already stands it down whenever a
world-replacing render pipeline is active and says so in the log once.

Release plumbing, kept from the beta: a semver prerelease now ships as a
GitHub prerelease, so `ModUpdate.pickRelease` keeps auto-update on the last
stable build rather than moving everybody onto an untried one.

## 1.6.0 — CUT GRASS and RUN FX, actually on Gold

1.5.0 switched both of these off on Gold. That turned out to be about the
wrong place to look, not a missing capability.

- **BURN GRASS now cuts on Gold too.** Gold's own CUT does not read
  `data.field.cutTreeSwaps` at all -- Gold's `field` registry never did, and
  it never needed to. Gold's CUT reads `FieldMoves.CUT_BLOCKS`
  (`src/world/gen2/FieldMoves.lua:262`), a per-tileset { facing block ->
  replacement block, animation } table with no single tile id in it, and
  swaps the whole 32×32 block once the text box closes.

  The one-clod trick still applies, off different raw material: every GRASS
  row (the swirl animation, not the falling tree) in a tileset's table has
  its before/after 16-tile blocks diffed, and every tile that changed becomes
  one entry in a source-tile -> destination-tile table -- Gen 1's single
  `GRASS_TILE` constant, generalised to however many distinct grass tiles
  Gold's edge and corner art actually uses. Unlike Gen 1, walkability on Gold
  is a per-CELL collision byte keyed by BLOCK id, not a tile-id set, so a
  synthesized block also needs a synthesized collision entry at the same new
  id -- taken from the matching CUT_BLOCKS row's own "after" block, at the
  same quadrant, which is the actual cart answer for what a real cut there
  collides as.

  Same guarantees as the Gen 1 arm: one clod per footstep, every cell of a
  run cut with no holes, a grass block CUT_BLOCKS never named still cuts, and
  the cut is written to `mod.save` and re-applied on re-entry.

- **RUN FX now draws on Gold too.** The projection was never actually Gen 1
  specific -- Gen 1's `OverworldController.lua:485` and Gold's
  `World.lua:9928` both call the exact same `Camera:follow(p.px, p.py, viewW,
  viewH)`, sized the same way (forced even, grown for tilt) on both sides.
  What needed a Gen 2 arm was `topIsOverworld`: Gold's overworld is not a
  stack state, so the Gen 1 test for "is it safe to draw" -- is the TOP of
  the stack marked `isOverworld` -- always answered no on a plain walk with
  nothing pushed over it, which is what actually stood the trail down.
  `Game2:drawScene`'s own `frameWorldActive` flag (`src/core/Game2.lua:1454,
  :1578`) answers the real question instead: did `World:draw()` paint the
  background this frame.

  One honest gap: the ENGINE's own dust puff behind a running step
  (`OverworldState.startDustAnim`) has no Gen 2 backing at all -- Gold's
  World has no such method. The coloured particles never depended on it and
  carry the whole trail there on their own.

- Suite coverage added against real Gen 2 engine modules: `src/world/gen2
  /Map`, the real `World.changeBlock` / `World.replaceBlock`, and
  `FieldMoves.CUT_BLOCKS` for the cut; `frameWorldActive` for the trail's
  gate.

## 1.5.0 — it runs on Gold

`"games": ["gen1", "gen2"]`. The speed itself crosses over unchanged: Gold
raises `movement.speed` at `src/world/gen2/World.lua:8817` with the same ctx
keys the Gen 1 site offers, and adds `downhill` and `playerState` because the
Cycling Road already needed them. Gold also rewrites the base duration from
scratch every step (`World.lua:8787` walking, `:8807` biking, both before the
hook), so the "put the number back" work the Gen 1 arm does has nothing to undo
there — scripted steps cannot inherit a running one.

Crossing over: **RUN SPEED**, **BOOST BIKE**, **BOOST SURF**, **SAFE GRASS**.

Gen 1 only, switched off on Gold rather than left to fail in the picture, each
saying so once in the log:

- **CUT GRASS** — the cut swaps a block and finds the "after" id in
  `data.field.cutTreeSwaps`. `field` is one of the six registries with no Gen 2
  home, and its only two readers in the engine live in
  `src/world/OverworldController.lua`, which a Gold boot never loads. No table,
  no reader.
- **RUN FX** — the trail is measured from the Gen 1 world canvas and Gold
  composites its own through `Chrome.fitScale`. It stands down rather than draw
  a plausible smear in the wrong place; it comes back when it has been checked
  in a real Gold boot.

## 1.4.2

**The effects are drawn properly now.**

- **Each particle is a shaded sprite, not a coloured square.** It has a
  dark rim, a body and a lit core — three shades, laid out as a square with
  its corners knocked off, which is what the eye reads as round. That is
  how a Game Boy sprite is shaded, and it is the difference between an
  object and a rectangle.

  All three shades come off **one five-step ramp per kind**, and a particle
  draws from a three-shade *window* onto it. The window slides down the
  ramp as the particle ages, so a flame starts white-yellow at the core and
  ends as an ember with nothing bright left in it — without any colour ever
  being interpolated. A smooth blend would look like somebody else's engine.

- **Fire is a tongue, not a ball**: taller than it is wide, narrowing as it
  dies, with its lit core low, where a flame is actually hottest.

- **Smoke sways as it rises.** The lean comes off each puff's own seed and
  its age, so no two lean the same way at the same moment, and its
  highlight sits high where a puff catches the light.

- **Bolts are a jagged line again.** Five joints, each kicking sideways,
  re-picked every other frame from the particle's seed — so it crackles
  into a new shape instead of being one shape that blinks. The near end is
  the bright core shade and it cools along its length.

- **Particles come off alternating feet** rather than a random spray, which
  is what is actually shedding them.

- **Fixed: at `x4` the trail ran to nearly six cells, not three and a half.**
  The lifetime floor was set *above* the fastest rung's honest lifetime (a
  4-frame step wants 14 ticks; the floor was 24), so the floor stopped
  being a floor and became the answer — at exactly the speed the
  cells-not-frames measure exists to hold steady. Measured across every
  kind at x1.5, x2 and x4 it is now 3.2–3.7 cells everywhere, and the
  suite's tolerance is tightened from three cells to one so this cannot
  come back quietly.

- Cost, since this draws on a phone: 70–224 rectangles a frame depending on
  speed and kind. The particle is four rectangles rather than a per-pixel
  mask deliberately — a 7x7 mask at seventy live particles would be three
  thousand draw calls a frame for a decoration.

## 1.4.1

**The trail now shows everywhere, and it tapers.**

- **`RUN FX` is visible on every surface, not just over tall grass.** It
  always *ran* everywhere — the particles never cared what you were
  standing on — but only smoke got the engine's dust puff, and that puff is
  the most solidly visible part of the whole effect. Without it, flames and
  bolts were carried by the coloured particles alone, and those only really
  read against a dark tile. Tall grass is dark; a path is not. So the
  effect looked like a grass feature.

  Every kind now leaves the puff, on every running step, on any ground. And
  every particle now gets a darker skirt under it — smoke included, in grey
  rather than black — so it has an edge on a pale tile instead of
  dissolving into it. Particles are bigger and hold more of their opacity
  down the length of the trail.

- **All three kinds now go big at the heel and taper to a point at the
  tail.** You should be able to tell which end the player is at from a
  still frame. 1.4.0 had smoke do the opposite — *expanding* as it thinned,
  which is what real smoke does and which read as a smear rather than as a
  trail. Flames and bolts taper the same way now, so the three differ in
  colour and behaviour rather than in shape.

- The suite pins both: it measures the width of the rectangles at each end
  of a rightward run and asserts the heel end is wider than the tail end,
  for every kind — and asserts every kind leaves the engine's puff, rather
  than only smoke.

**Things this mod does that were only ever written down in the source, put
here where they can be found:**

- The trail's length is measured in **cells of ground, not frames**, so it
  is the same length at `x1.5` and at `x4`. A step is 8 frames at x2 and 4
  at x4; a fixed lifetime would draw twice the trail at half the speed.
- Particles are left in **world space** and you run away from them. They
  barely drift on their own, because a trail is something left behind.
- The trail uses **its own random number generator**, never the game's. A
  spark drawn from `love.math.random` would move the dice that decide
  encounters and battles — a spark you could see in a battle log.
- `BURN GRASS` cuts by **swapping a map block**, the way `CUT` does, so the
  tile stops being tall grass and the engine stops rolling encounters on it
  without being asked. It suppresses nothing.
- `SAFE GRASS` **does** suppress, and throws the vanilla dice first and
  discards them, so a suppressed step draws from the RNG exactly what a
  vanilla step would have drawn.
- The coloured particles stand down under **tilt mode** or a world-replacing
  **render pipeline** — a screen-space overlay cannot follow either camera.
  The puff and the cut are engine drawing and keep working.
- Every reason the overlay declines to draw is **logged once**, including
  the one it cannot fix: an engine build from before the `render.hud` hook
  existed.

## 1.4.0

**A run now leaves something behind — and every bit of it has an off
switch.** Pick a trail of **smoke**, **flames** or **lightning** off your
heels; **cut** the tall grass you run across, one clod at a time, the way
the CUT move cuts it, so that grass has no Pokémon left in it; or run
straight through tall grass without ever starting a wild battle.

`RUN FX` set to `OFF` restores the vanilla picture exactly. `BURN GRASS`
and `SAFE GRASS` ship **off**. Leave all three alone and this is still what
it always was: a step gets shorter when you hold B, and nothing else in the
game moves.

- **The cut now follows the player, with no holes in it.** 1.3.0 matched a
  grass block against `field.cutTreeSwaps` by **block id**, and that table
  only names the specific blocks CUT was ever meant to be used on. Run
  across any other grass block and there was no pair to take tiles from, so
  nothing happened — which is why the cut skipped cells and broke up along
  the path.

  The swap table is now read for one thing instead: **which tile the grass
  becomes**. Compare any before/after pair tile by tile, and wherever the
  before is grass and the after is not, the after is the ground the grass
  was standing on. With that single tile id, *any* grass block can be cut,
  one cell at a time — so every cell you run over is cut and the trail is
  unbroken. (If a dataset has no swaps at all, it falls back to the most
  common walkable tile in the tileset, which outdoors is that same ground.)

- **The trail now reaches about three and a half cells back**, and fades
  the whole way out instead of stopping.

  Its length is measured in **cells of ground, not frames** — because
  frames are not a length. A step is 8 frames at x2 and 4 at x4, so a fixed
  lifetime draws a trail twice as long at half the speed. Particles are
  left in world space and the player runs away from them, so the lifetime
  is now derived from the step duration and the length on the ground stays
  put. Measured in the suite at both speeds.

  Particles also barely drift now. A trail is something *left behind*;
  pushing it backwards as well made the far end chase the player, which is
  what kept the old one hugging his heels.

- **Colours, and what each one does.**
  - `FLAMES` — orange at the heel, **red** through the middle, ember at the
    end, and it shrinks as it dies down.
  - `BOLTS` — a white-hot core cooling through **yellow** into amber, still
    lit on alternate ticks so it crackles rather than glows.
  - `DUST` is **smoke**: greys, no hard black edge, and it *expands* as it
    thins, which is the difference between smoke and a row of shrinking
    dots. The engine's own dust puff still anchors the first cell for this
    one only — a grey puff under a red flame made the fire look like it was
    smoking.

- Two particles a tick now, spread across the width of the cell, so the
  trail is a band with texture in it rather than a dotted line.

## 1.3.0

- **`BURN GRASS` now really cuts the grass.** 1.2.x drew a dark patch over
  the tile and called it burnt. It was not burnt — it was a shadow lying on
  grass that was still standing, and the grass still had Pokémon in it.

  The engine already knew how to do this. `OverworldState:tryCut` cuts tall
  grass by **swapping a block**: `field.cutTreeSwaps` is a before/after
  table of block ids out of the ROM, and cutting writes the "after" id into
  the map and rebuilds the renderer. So the mod does the same thing, and
  the grass is genuinely gone — gone from the picture, and gone from
  `Map:isGrassCell`, which is the exact predicate the wild-encounter check
  gates on.

  One improvement on the engine's own Cut: a block is 2×2 cells, so
  swapping it whole would take four tiles for one footstep. This assembles
  a block that is the current block everywhere **except** the one cell's
  2×2 tile quadrant, which comes from the cut one — a cut exactly one clod
  wide, the size of the character, built only from tile ids the tileset
  already contains.

- **`BURN GRASS` no longer touches `encounter.roll` at all.** It does not
  need to: the cut lands on `world.stepped`, which the engine emits near
  the top of `onStepComplete`, a long way above the encounter check at the
  bottom of the same function. By the time that check looks, the tile is
  not tall grass, and the engine declines the battle by itself. A feature
  that needs no hook is the better version of the feature.

- **The trail no longer depends on the overlay to be visible.** Every
  running step now drops the **engine's own dust puff** — the same
  animation Cut leaves on grass — on the cell just vacated. That is drawn
  in the world pass at the right anchor under every camera the engine has.
  The coloured particles ride on top of it for the dust/flames/bolts
  difference; if that surface is unavailable, the puff is still there.

- **The tests now drive the engine instead of stubs.** The cut is asserted
  against a real `src/world/Map` — `blockAt`, `tileAt`, `cellTile`,
  `isGrassCell`, `setBlock` are the engine's own code — proving the tile
  stops being grass, that the three neighbouring cells in the same block do
  not, that a second cut in the same block works, and that entering a map
  re-applies what was cut. The trail is asserted through the real
  `Game.draw`, which is the check that would have caught an overlay wired
  to a hook the engine never reached.

## 1.2.1

- **`BURN GRASS` now cuts a tile, not a shadow.** The mark is a solid
  16×16 patch of bare earth with a band of cut stubble along its top edge —
  exactly the size of the clod you ran over — instead of the faint checker
  1.2.0 drew. It reads as grass that has been taken off rather than as a
  shadow lying on grass that is still there.

  The cells skipped while drawing are now measured off the **sprite**
  rather than off the logical cell, so a step in flight skips both cells it
  straddles and the cut appears the instant your heel clears the tile.

- **`RUN FX` made visible.** 1.2.0's dust was a pale grey at half opacity,
  which over Route 1's green is a rumour rather than an effect. Particles
  are now roughly twice the size, close to opaque, warm brown for dust, and
  every one gets a one-pixel black skirt underneath — the way a Game Boy
  sprite gets its darkest shade — so they have an edge on a bright tile.
  They also spawn on every tick rather than every other one.

- The overlay now clears the shader, scissor and blend mode before it
  draws. The engine leaves that state clean today, but "leaves it clean" is
  a promise about the current compositor, and a palette shader still bound
  would remap these colours to whatever it pleased — one of the ways an
  effect ends up invisible rather than wrong.

- **It now says why when it cannot draw.** Every reason the overlay stands
  down is logged once, and ten seconds of play with the `render.hud` hook
  never reached logs the one cause the mod cannot fix: an engine build from
  before that hook existed, on which the trail is silently impossible. The
  speed rows are unaffected on such a build.

## 1.2.0

- **New: `RUN FX` — a trail behind you while you run.** `OFF` / **`DUST`** /
  `FLAMES` / `BOLTS`, on the mod's own options page. It is drawn over the
  finished frame and changes nothing else: no tile, no flag, and — because
  it runs its own little generator rather than borrowing the game's — not
  one draw of the RNG that decides encounters and battles.

  `DUST` is the default, because dust is the one a pair of shoes could
  actually account for. `OFF` is the top of the same row for anyone who
  wants 1.1.0's picture back.

- **New: `BURN GRASS` (off).** Tall grass you *run* across is scorched, and
  scorched grass holds no Pokémon — walking over it later is just as empty.
  Burnt cells are written to `mod.save`, so a burnt route is still burnt
  after a save and a reload. Walking through grass never burns it.

  Switching the row off puts the map back the way the engine draws it and
  gives the grass its Pokémon back; the burns are remembered rather than
  erased, so switching it on again returns the map you left.

- **New: `SAFE GRASS` (off).** Running through tall grass never starts a
  wild battle. Walking through it is untouched, so the grass is still
  dangerous — you just have a way past it.

  Both of these suppress the battle by throwing the vanilla dice first and
  discarding the answer, so a suppressed step draws from the RNG exactly
  what a vanilla step would have drawn.

- The trail is screen-space, and it stands down rather than drawing in the
  wrong place when something else owns the camera: tilt mode, or a mod's
  render pipeline that replaces the world pass.

## 1.1.0

- **Fixed: cutscenes ran at running speed.** When an NPC escorts you
  somewhere, the player was crossing two tiles for the guide's one and
  arriving ahead of the dialogue.

  A step's duration is stored on the player, and a *scripted* step is not
  started through the hook — `updateScriptMoves` sets the move directly and
  never asks — so it reused whatever the last manual step left behind. The
  escort NPC has no such knob (`NPC.lua` keeps its own fixed 16 frames), so
  the two walked at different speeds. Measured: 16 frames normally, 8 after
  a running step.

  It happened almost every time, because the button that advances the
  dialogue you are being escorted out of is B — the same button that makes
  you run.

  The duration is now handed back to the engine's own number the moment you
  stand still, and again when a script starts. A step already under way
  keeps the speed it began with, the bicycle goes back to 8 rather than 16,
  and a duration set by another mod is left alone.

## 1.0.0

- First release, with in-game updates wired from the start: the manifest
  declares its `github` repo and releases are named
  `running_shoes-<version>.zip`, the name the launcher's updater prefers. Hold B to run, with RUN SPEED (x1.5 / x2 / x3 / x4) and
  optional BOOST BIKE and BOOST SURF toggles.
