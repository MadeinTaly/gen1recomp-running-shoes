# Changelog

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
