# Changelog

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
