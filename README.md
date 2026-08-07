# gen1recomp-running-shoes

Hold **B** to walk faster.

Gen 3 handed you running shoes in the first five minutes. Gen 1 made you
walk to Cerulean, beat a gym, and buy a bicycle voucher off a man in a
skyscraper. This evens things up slightly.

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
| `BURN GRASS` | off | running across tall grass scorches it |
| `SAFE GRASS` | off | running through tall grass meets nothing |

## The three extras

**`RUN FX`** draws a trail off your heels while you hold B. Dust is the
default, because dust is the one a pair of shoes could actually account
for; flames and lightning are there because you asked, and they are honest
about being decoration. It is drawn over the finished frame and changes
nothing underneath it — no tile, no flag, and not one draw of the random
number generator that decides encounters and battles. It has its own tiny
generator for exactly that reason: a spark that moved the game's dice would
be a spark you could see in a battle log.

Two places it stands down rather than draw in the wrong spot: **tilt mode**,
and a mod's **render pipeline** that replaces the world pass. Both move the
camera in ways a screen-space overlay cannot follow, so it waits them out.

**`BURN GRASS`** scorches the tall grass you *run* across — walking never
burns anything — and scorched grass holds no Pokémon. Walk back over it a
week later and it is still empty, because the burnt cells are written into
`mod.save` and travel with your save file. The scorch itself is drawn over
the tile as charred stubble, so the cell underfoot is skipped: a solid
patch on your own tile would char you along with the grass.

Switching the row back **off** puts the map back exactly as the engine
draws it and gives the grass its Pokémon back — a row you turned off is a
row that does nothing, and nobody should be stuck with a scarred save and
no way out of it. What burnt is remembered rather than erased, so turning
it on again returns the map you actually left.

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
