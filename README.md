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
as a brisk walk, which is historically accurate and slightly funny.

**It changes nothing but the duration of a step.** A tile still costs a
tile. Collision, encounters, triggers, ledges, warps and the step itself
are untouched, so the world has no idea how fast you crossed it. Grass does
not become less dangerous because you hurried through it, and no, this is
not an encounter-rate mod.

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

## Help wanted

Small mod, few places to go wrong, but a couple of real questions:

- **are the speeds right?** ×1.5 / ×2 / ×3 / ×4 is a guess. If ×2 feels
  wrong on your device, that is worth an issue;
- **does anything else desync?** The escort-NPC bug — where the player
  arrived before the cutscene did — was found by a player, not by a test.
  There may be more scenes like it;
- **other things B could do.** Running is one idea; it is not obviously the
  only one.

The one hard rule is that anything you send has to be **yours**. No sprites,
palettes, audio or text lifted from a ROM, a fan game, a wiki or another
mod — not out of fussiness, but because this whole project stands on not
redistributing other people's game data, and the other modders on the index
deserve the same courtesy we would want.

You do not need to know Lua for any of the above.

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
