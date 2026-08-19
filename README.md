# gen1recomp-running-shoes

Hold **B** to walk faster.

Gen 3 handed you running shoes in the first five minutes. Gen 1 made you
walk to Cerulean, beat a gym, and buy a bicycle voucher off a man in a
skyscraper. This evens things up slightly.

## New in 1.4.0 — a run that leaves something behind

Three extras, and **every one of them has an off switch**, on the mod's own
options page. Nothing here is permanent and nothing is forced on you.

**A trail off your heels while you run.** Pick **smoke**, **flames** or
**lightning** — it reaches about three and a half cells back and fades the
whole way out. Set `RUN FX` to `OFF` and the picture is exactly what it was
before; the trail draws over the finished frame and changes nothing
underneath it, not a tile, not a flag, and not one roll of the dice that
decide encounters.

**Grass you can cut by running through it.** `BURN GRASS` cuts the tall
grass you *run* across, one clod at a time — the size of your character,
following every cell of your path — using the same block swap the CUT move
uses. Cut grass has no Pokémon in it, because it genuinely is not tall
grass any more. **Off by default**, and walking never cuts anything.

**Grass you can run straight through.** `SAFE GRASS` means a run through
tall grass never starts a wild battle. Walking is left exactly as it was,
so the grass is still dangerous — you just have a way past it. **Off by
default.**

Leave all three alone and the mod is what it always was: a step gets
shorter when you hold B, and nothing else in the game moves.

## On Gold

Runs on Pokémon Gold as well as Red, Blue and Yellow (`"games": ["gen1",
"gen2"]`), and as of 1.6.0 **every row works there**.

**RUN SPEED**, **BOOST BIKE**, **BOOST SURF** and **SAFE GRASS** work exactly
as they do here — Gold's own `movement.speed` site carries the same keys, and
it rebuilds the step duration every step, so a scripted cutscene can never
inherit a running step the way it can on Gen 1.

**BURN GRASS** and **RUN FX** used to switch themselves off on Gold. Both now
run there too, off the engine's own Gen 2 material:

- Gold's own CUT does not touch a tile — it swaps the whole 32×32 block the
  facing tile sits in, out of `FieldMoves.CUT_BLOCKS`, a per-tileset table
  with no single "this tile is grass" constant to key off the way Red's
  OVERWORLD tileset allows. So the one-clod cut is built the same way there,
  off a diff of that table's before/after blocks instead of a tile id, and it
  also has to splice a new COLLISION entry alongside the new tile block,
  because Gold's walkability is a per-cell byte indexed by block id rather
  than a tile-id set.
- The trail's projection was never actually Gen 1 specific — both games call
  the same `Camera:follow` the same way — what needed a Gen 2 arm was knowing
  whether the overworld was really on screen at all, since Gold's overworld
  is not a stack state the way Gen 1's is.

One honest gap remains: the ENGINE's own dust puff behind a running step has
no Gen 2 backing at all, so on Gold the coloured particles carry the whole
trail by themselves rather than riding on top of the puff.

## With the Dramatic Shape voxel mod

Its **1ST** and **3RD** cameras do not walk the grid — they replace the step
with a continuous, camera-relative walk — so until 1.7.0 every row of this
mod went quiet the moment you switched to one, and came back when you went
back overhead ([#1](../../issues/1)).

As of **1.7.0**, `RUN SPEED`, `BURN GRASS` and `SAFE GRASS` all work inside
those cameras, at the multiplier you picked and with the same floor and the
same opt-in for the bicycle and for surfing. Sixteen frames for a
sixteen-pixel cell is one pixel a frame, so shortening a step and quickening
a walk are the same arithmetic.

The voxel mod is an **optional** dependency: neither mod needs the other, and
enabling either one mid-session works.

`RUN FX` is the exception, and it is not new: the trail is drawn over the
finished 2D frame, and a screen-space overlay cannot follow a 3D camera. It
stands down whenever a world-replacing render pipeline is active — which the
voxel pipeline is at every rung, overhead included — and says so in the log
once.

## Install

Download `running_shoes-<version>.zip` from [Releases](../../releases),
then **Launcher → MODS → Import mod .zip** (or in game,
**START → MODS → Import mod .zip**).

The launcher can also keep it up to date on its own: the manifest declares
this repo, so **MODS → the mod's row** offers a newer release when one is
published, and it can be installed from the launcher's **Find mods** tab
without touching a file at all.

## Use

Hold **B** while walking. That is the whole interface.

**START → MODS → Running Shoes → OPTIONS..**

| Row | Values | |
| --- | --- | --- |
| `RUN SPEED` | x1.5 / **x2** / x3 / x4 | how much shorter a step gets |
| `BOOST BIKE` | off | whether the bicycle gets it too |
| `BOOST SURF` | off | whether surfing does |
| `RUN FX` | off / **dust** / flames / bolts | what a run leaves behind you |
| `BURN GRASS` | **off** | running across tall grass cuts it |
| `SAFE GRASS` | **off** | running through tall grass meets nothing |

Every row above turns off. `RUN FX` on `OFF` restores the vanilla picture,
and the other two ship off already.

## The three extras

**`RUN FX`** leaves a trail off your heels while you hold B, reaching about
**three and a half cells back** and fading the whole way out.

All three go **big at the heel and taper to a point at the tail**, so you
can tell which end the player is at from a still frame, and all three show
on any ground — not just over tall grass.

| | |
| --- | --- |
| `DUST` | smoke — a disc, greys, swaying as it rises, its highlight up top where a puff catches the light. |
| `FLAMES` | a teardrop: pinched to a point at the tip, widest about two thirds down, rounded at the base, its lit core low where a flame is hottest. |
| `BOLTS` | a jagged line of five joints, thick where it leaves the ground and a hair at its tip, re-picked every other frame so it crackles into a new shape instead of blinking. |

Each particle is a shaded sprite rather than a coloured square: a dark rim,
a body and a lit core, drawn as one filled row per scanline off a shape
table, so the outline is a real curve rather than a box with its corners
knocked off.

All three shades come off **one five-step ramp per kind**, and a particle
draws from a three-shade *window* onto it — the window sliding down the
ramp as the particle ages, so a flame starts white-yellow and ends an ember
without any colour ever being interpolated.

The trail is shed **a cell and a quarter behind your heels**, and nothing it
draws is ever allowed inside your own sprite's box — `RUN FX` composites over
the finished frame, so a mark in that box would be a mark *on* the character
rather than behind him.

Every kind also leaves the engine's own dust puff on the cell you have just
left — the same animation `CUT` leaves on grass. That is drawn in the world
pass, at the right place under every camera the engine has, so there is
always something solid in the trail no matter what tile you are crossing.

The length is measured in **cells of ground, not frames**, because frames
are not a length: a step is 8 frames at x2 and 4 at x4, so a fixed lifetime
would draw a trail twice as long at half the speed. Particles are left in
world space and you run away from them, so the lifetime comes off the step
duration and the trail stays the same length on the ground at every setting.

Nothing underneath changes — no tile, no flag, and not one draw of the
random number generator that decides encounters and battles. The trail has
its own tiny generator for exactly that reason: a spark that moved the
game's dice would be a spark you could see in a battle log.

Two places the coloured layer stands down rather than draw in the wrong
spot: **tilt mode**, and a mod's **render pipeline** that replaces the
world pass. Both move the camera in ways a screen-space overlay cannot
follow. The puff underneath is unaffected.

**If you see nothing, the log will say why.** Every reason the overlay
stands down is written to the log once, and ten seconds of play without the
`render.hud` hook ever being reached logs the one cause the mod cannot work
around: an engine build from before that hook existed. On such a build the
puff and the cut still work — they are the engine's own drawing.

**`BURN GRASS`** *cuts* the tall grass you run across, exactly the way the
CUT move cuts it — walking never cuts anything.

This is not a mark drawn on top of the grass. The engine cuts tall grass by
**swapping a block**: `field.cutTreeSwaps` is a before/after table of block
ids out of the ROM, and `OverworldState:tryCut` writes the "after" id into
the map and rebuilds the renderer. The mod does the same thing, so the
grass is genuinely gone — gone from the picture, and gone from
`Map:isGrassCell`, which is the exact predicate the wild-encounter check
gates on. There is no suppression and no overlay: the tile simply is not
tall grass any more.

Two improvements on the engine's own Cut.

A block is 2×2 cells, so swapping it whole would take four tiles for one
footstep. Instead this rebuilds the block with the grass taken out of **one
cell's 2×2 tile quadrant** — a cut exactly one clod wide, the size of your
character, built only from tile ids the tileset already contains. No art is
invented and nothing ROM-derived is shipped.

And the swap table is read for *which tile the grass becomes*, not for
which blocks are allowed to be cut. That table only names the blocks CUT
was ever meant to be used on, so matching whole blocks against it left
holes wherever you ran across a grass block it had never heard of. Comparing
one before/after pair tile by tile gives the ground the grass was standing
on, and with that single tile id **every** cell you run over is cut, so the
path is unbroken.

What you cut is written into `mod.save` and travels with your save file, so
entering the map again re-applies it.

**`SAFE GRASS`** is the smaller version of the same idea with nothing
permanent about it: while you are running, tall grass never starts a wild
battle. Walk and it is as dangerous as it ever was.

Both suppress the battle by throwing the vanilla dice first and *discarding*
the answer, so a suppressed step draws from the RNG exactly what a vanilla
step would have drawn. Only the battle is missing; the stream underneath it
is where the engine left it.

## The numbers, since you asked

A step in this engine is a frame count, and lower is faster. The engine
walks you at **16 frames** a tile and rides the bicycle at **8** — which is
where "the bicycle doubles walking speed" comes from, and it is exact.

So the ladder is arithmetic on that 16:

| Setting | Frames per tile | Tiles per second |
| --- | ---: | ---: |
| walking | 16 | 3.75 |
| x1.5 | 11 | 5.45 |
| **x2** | **8** | **7.5** |
| x3 | 5 | 12 |
| x4 | 4 | 15 |

Two things fall out of that table.

**At x2 your shoes are the bicycle.** Not "about as fast as" — the same
integer. You have spent nothing, gone nowhere, and matched a vehicle that
costs a gym badge and an errand for a man on the eleventh floor. The
bicycle's remaining advantage is that it does not require you to hold a
button. This is a fact about Gen 1's bicycle rather than a bug in these
shoes, and it is the most Gen 1 fact in this README.

**The ladder stops at x4 because integers run out.** One rung further is 3
frames, then 2, then 1 — and at 1 frame a tile passes in a sixtieth of a
second, which is 60 tiles a second, which is the length of Route 1 in about
half a second, which is not running. The walk cycle would be a strobe and
the camera would be a rumour. x4 is where it still reads as a person in a
hurry.

## What it does not do

**There is no running animation.** Gen 1 does not have one — there were no
sprint frames to draw, because nobody in 1996 had thought of it. Your legs
keep the walking cadence and simply spend less time on each tile. It reads
as a brisk walk, which is historically accurate and slightly funny. `RUN FX`
is a trail, not a sprint cycle: the sprite is still the sprite.

**Out of the box it changes nothing but the duration of a step.** A tile
still costs a tile. Collision, encounters, triggers, ledges, warps and the
step itself are untouched, so the world has no idea how fast you crossed
it. Grass does not become less dangerous because you hurried through it —
unless you go and switch `BURN GRASS` or `SAFE GRASS` on, which is a
deliberate two-button trip through the options page and says so on the row.

**It is still not an encounter-rate mod.** `SAFE GRASS` does not lower a
rate; it declines the battle outright while you are running, and leaves
walking exactly as it was.

**It plays well with others.** The hook calls the next handler first and
multiplies whatever comes back, so a mod that slows you down in a swamp
keeps its say and you are simply a fast person in a swamp.

## How it works

The engine has a `movement.speed` hook, and its own comment in
`src/world/Player.lua` reads:

> the bicycle doubles walking speed (8 frames per step); `movement.speed`
> lets a mod multiply or replace that (**running shoes**, dash, etc.)

So this mod is the shape the engine was expecting, rather than something
prised in around the side. It reads one button and returns one number.

### The part where one number turned out not to be enough

The hook is asked on a **manual** step, and the answer is stored on the
player as `stepFramesCur`. A **scripted** step — the guide walking you to
the Poké Mart, Oak marching you to his lab — never asks:
`OverworldState:updateScriptMoves` sets the move directly. So it reused the
last manual step's duration.

Measured on a real `Player`:

| | frames per tile |
| --- | --- |
| scripted step, no run before it | 16 |
| scripted step after a running step | **8** |

The escort NPC has no such knob — `src/world/NPC.lua` keeps its own fixed
16 — so the player crossed two tiles for the guide's one and arrived ahead
of the dialogue. And it happened nearly every time, because the button that
advances the dialogue you are being escorted out of is B: the same button
that makes you run.

Since 1.1.0 the duration is handed back to the engine's own number as soon
as you stand still, and again when a script starts. A step already under
way keeps the speed it began with, the bicycle goes back to 8 rather than
16, and a duration set by another mod is never overwritten.

## Ideas, and help building them

**Got an idea for something this should do?** Open an issue — there is a
template for it. You do not need to know any Lua, and you do not need to
have worked out how it would be built. Describe what you want and why.

**Want to build it yourself?** Open a pull request. Collaboration is welcome
on any part of this.

Anything you send that includes art has to be your own work — nothing
traced, edited or recoloured from a ROM, a fan game, a wiki or another mod.

## Requirements and legal

Lua source only: no ROM, no ROM-derived data, no game assets. You need
Gen1Recomp and your own legally obtained Pokémon Red or Blue ROM; neither
is provided here.

Not affiliated with, endorsed by, or connected to Nintendo, Game Freak, or
The Pokémon Company. Pokémon and all related names are trademarks of their
respective owners, used here only to describe what this software does.

## Support

If this saved you some walking, you can support the author here:
<https://linktr.ee/made_in_taly>

## Licence

[MIT](LICENSE) — see the file for terms.
