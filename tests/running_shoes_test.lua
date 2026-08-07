-- Standalone: luajit mods/running_shoes/tests/running_shoes_test.lua
--
-- Drives the movement.speed hook the way Player:step does and asserts the
-- stated effect: B shortens a step by the chosen multiplier, nothing else
-- does, the bicycle and surfing are opt-in, and an earlier handler's
-- opinion survives.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local Data = require("src.core.Data")
Data:load()

local DIR = os.getenv("RUNNING_SHOES_DIR") or "mods/running_shoes"
local run = T.sdk.loadMod(DIR, { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

T.check(Runtime.wantsHook("movement.speed"), "the movement.speed hook is claimed")

-- The engine's own numbers (src/world/Player.lua): a walking step is 16
-- frames and the bicycle is 8. Lower is faster.
local WALK, BIKE = 16, 8

local function ctx(opts)
  opts = opts or {}
  return {
    onBike = opts.onBike or false,
    surfing = opts.surfing or false,
    input = { isDown = function(_, btn) return opts.b and btn == "b" end },
    save = {},
    player = opts.player,
  }
end

local function identity(f) return f end
local function speed(frames, c)
  return Runtime.call("movement.speed", identity, frames, c)
end

-- ------- the default: x2, walking only

T.eq(speed(WALK, ctx{}), WALK, "not holding B leaves a step exactly as it was")
T.eq(speed(WALK, ctx{ b = true }), BIKE,
  "holding B at the default x2 lands on the bicycle's own 8 frames")

-- the bicycle and surfing are opt-in, so B alone must not touch them
T.eq(speed(BIKE, ctx{ b = true, onBike = true }), BIKE,
  "the bicycle is untouched while BOOST BIKE is off")
T.eq(speed(WALK, ctx{ b = true, surfing = true }), WALK,
  "surfing is untouched while BOOST SURF is off")

-- ------- every rung of the ladder

local loader = run.loader
-- One options table for the whole suite, written key by key: the rows are
-- independent of each other and a wholesale replace would silently reset
-- whichever one the previous section had turned on.
local OPTS = {}
loader.modOptions.running_shoes = OPTS
local function setOpt(key, value) OPTS[key] = value end
local function setSpeed(value) setOpt("speed", value) end

for _, case in ipairs({
  { "1.5", 11 },   -- 16 / 1.5 = 10.67, rounded
  { "2", 8 },
  { "3", 5 },      -- 16 / 3 = 5.33
  { "4", 4 },
}) do
  setSpeed(case[1])
  T.eq(speed(WALK, ctx{ b = true }), case[2],
    ("x%s turns a 16-frame step into %d"):format(case[1], case[2]))
end

-- ------- the floor
--
-- Steps are whole frames. A step already near the floor must not be driven
-- below it however hard the multiplier pushes.

setSpeed("4")
local floored = speed(6, ctx{ b = true })
T.check(floored >= 4, "a short step is not driven under the 4-frame floor")
T.check(floored <= 6, "and is still no slower than it started")

-- ------- another mod keeps its say
--
-- The wrap calls next() first and multiplies what comes back, so a handler
-- that slowed the player down is respected rather than overwritten.

setSpeed("2")   -- the floor test above left it at x4
local slowed = Runtime.call("movement.speed", function(f) return f * 2 end,
  WALK, ctx{ b = true })
T.eq(slowed, 16, "a doubling handler runs first: 16 -> 32 -> halved back to 16")

-- and one that already made it faster than our own answer is left alone
local quick = Runtime.call("movement.speed", function() return 3 end,
  WALK, ctx{ b = true })
T.eq(quick, 3, "a handler that is already faster than the floor is not slowed")


-- ------- auto-update wiring (engine >= the ModUpdate/ModIndex release)
--
-- The manifest's `github` field is what the launcher's updater and the
-- "Find mods" tab read. And ModUpdate.pickZipAsset prefers an asset named
-- exactly "<id>-<version>.zip" -- so the release file name is part of the
-- contract, not decoration. This asserts the pair actually match.

local Manifest = require("src.mods.Manifest")
local ModUpdate = require("src.mods.ModUpdate")

local fh = assert(io.open(DIR .. "/manifest.json", "rb"))
local body = fh:read("*a"); fh:close()
local declared = body:match('"github"%s*:%s*"([^"]+)"')
T.check(declared ~= nil, "the manifest declares a github repo for updates")
T.check(Manifest.parseGithub(declared) ~= nil,
  "and it parses as owner/repo (" .. tostring(declared) .. ")")

local id = body:match('"id"%s*:%s*"([^"]+)"')
local version = body:match('"version"%s*:%s*"([^"]+)"')
local wanted = id .. "-" .. version .. ".zip"
local picked = ModUpdate.pickZipAsset({
  { name = "Source code (zip)", browser_download_url = "x" },
  { name = wanted, browser_download_url = "y" },
}, id, version)
T.eq(picked and picked.name, wanted,
  "the release asset must be named " .. wanted)

-- ------- a scripted walk must NOT inherit the running step
--
-- The bug this covers: the guide who escorts you somewhere walks at the
-- NPC's fixed 16 frames, but the player's scripted steps reuse whatever
-- `stepFramesCur` the last MANUAL step left on the player -- and
-- OverworldState:updateScriptMoves sets `moving` directly, so the hook is
-- never asked. Run into a cutscene and the player crosses two tiles for
-- the guide's one.
--
-- These drive a real Player rather than a stand-in, so the assertion is
-- against the engine's own arithmetic and would notice if it changed.

-- The restore itself needs nothing but a table carrying `moving` and
-- `stepFramesCur`, which is all the mod touches -- so these run everywhere,
-- including CI's 3-species fixture.

local function walker() return { moving = false, stepFramesCur = nil } end
local function tick() Runtime.call("input.step", function() end, {}, 1 / 60) end

do
  local p = walker()
  T.eq(speed(WALK, ctx{ b = true, player = p }), BIKE,
    "the running step itself is still sped up")
  p.stepFramesCur = BIKE          -- what Player:tryMove stores
  tick()
  T.eq(p.stepFramesCur, WALK, "standing still puts the engine's own duration back")
end

-- the cutscene's own signal: script.started closes the one-frame race where
-- a script queues a move on the tick the running step ended
do
  local p = walker()
  speed(WALK, ctx{ b = true, player = p })
  p.stepFramesCur = BIKE
  Runtime.emit("script.started", { ctx = {} })
  T.eq(p.stepFramesCur, WALK, "a starting script restores it immediately")
end

-- a step still IN PROGRESS must keep its speed: restoring mid-stride would
-- change the duration under a move already part-way across a tile
do
  local p = walker()
  speed(WALK, ctx{ b = true, player = p })
  p.stepFramesCur, p.moving = BIKE, true
  tick()
  T.eq(p.stepFramesCur, BIKE, "a step already under way keeps the speed it started with")
end

-- and we only ever undo OUR number: if anything else has set the duration
-- since, that decision belongs to whoever made it
do
  local p = walker()
  speed(WALK, ctx{ b = true, player = p })
  p.stepFramesCur = 3       -- somebody else's idea, not ours
  tick()
  T.eq(p.stepFramesCur, 3, "another mod's duration is left alone")
end

-- the bicycle restores to the BICYCLE's number, not to walking: vanilla
-- would have left 8 there, and that is what the scripted step should use
do
  local p = walker()
  local sped = speed(BIKE, ctx{ b = true, onBike = true, player = p })
  if sped < BIKE then       -- only meaningful while BOOST BIKE is on
    p.stepFramesCur = sped
    tick()
    T.eq(p.stepFramesCur, BIKE, "on the bicycle it goes back to 8, not 16")
  else
    T.check(true, "BOOST BIKE is off by default, so there is nothing to restore")
  end
end

-- ------- and the same thing against the engine's real arithmetic
--
-- The assertions above take it on trust that `stepFramesCur` is what a
-- scripted step is timed by. These prove it, by counting a real Player
-- across a real tile -- so if the engine ever changes how a step is timed,
-- this notices instead of quietly passing.
--
-- Gated: building a Player needs the player sprites, which the 3-species
-- fixture CI runs on does not carry. The gate reports which way it went
-- rather than skipping silently.

if not _G.love then _G.love = require("tests.love_stub") end
local Player = require("src.world.Player")
local Collision = require("src.world.Collision")

local probe = select(2, pcall(function() return Player.new(Data, 5, 5, "down") end))
local REAL = type(probe) == "table" and probe.update ~= nil
T.check(true, REAL and "full dataset: the real-Player checks ARE running"
                    or "fixture dataset: no player sprites, real-Player checks skipped")

if REAL then
  -- exactly what updateScriptMoves does: no tryMove, so no hook
  local function scriptStep(p, dir)
    p.facing = dir
    p.targetX, p.targetY = Collision.target(p.cellX, p.cellY, dir)
    p.moving, p.progress = true, 0
  end
  local function ticksToCross(p)
    local n = 0
    while p.moving and n < 200 do p:update(); n = n + 1 end
    return n
  end

  local p = Player.new(Data, 5, 5, "down")
  scriptStep(p, "down")
  T.eq(ticksToCross(p), WALK, "a scripted step is 16 frames with nothing in the way")

  -- the bug, end to end: run, stand still, then let a script move you
  speed(WALK, ctx{ b = true, player = p })
  p.stepFramesCur = BIKE
  p.moving = false
  tick()
  scriptStep(p, "down")
  T.eq(ticksToCross(p), WALK,
    "so the escort's scripted step runs at the NPC's speed, not the player's")
end

-- ------- 1.2.0: the grass
--
-- `encounter.roll` is asked on every step onto tall grass and nil
-- suppresses the battle.  These drive it the way OverworldState does and
-- assert the three answers the mod can give, plus the two things it must
-- never do: touch a non-grass roll, and skip the vanilla draw.

T.check(Runtime.wantsHook("encounter.roll"), "the encounter.roll hook is claimed")
T.check(Runtime.wantsHook("render.hud"), "the render.hud hook is claimed")

-- mod.world resolves the live overworld by scanning the state stack for
-- the isOverworld marker, so a stub with one such state is the whole of
-- what the mod reads: a map id, a cell, and the options table the overlay
-- checks before it draws.
local STUB = {
  data = Data,
  save = { flags = {}, options = { zoom = 0, tilt = 0 } },
  input = { isDown = function(_, btn) return btn == "b" end },
}
local WORLD = { isOverworld = true, map = { id = "ROUTE_1" },
                player = { cellX = 3, cellY = 4, facing = "down" } }
STUB.stack = { states = { WORLD } }
loader.game = STUB

local rolls = 0
local function vanillaRoll()
  rolls = rolls + 1
  return { species = "PIKACHU", level = 3 }
end
local function grass()
  return { mapId = "ROUTE_1", terrain = "grass", rng = function() return 0 end }
end
local function roll(c)
  return Runtime.call("encounter.roll", vanillaRoll, {}, c or grass())
end

local function walkOnto(cx, cy)
  WORLD.player.cellX, WORLD.player.cellY = cx, cy
  speed(WALK, ctx{ b = false })       -- a plain step: not running
end
local function runOnto(cx, cy)
  WORLD.player.cellX, WORLD.player.cellY = cx, cy
  speed(WALK, ctx{ b = true })        -- holding B: the shoes are in play
end

-- with both rows off the hook is a pass-through, whatever the player did
setOpt("burn", false); setOpt("safe", false)
runOnto(3, 4)
T.check(roll() ~= nil, "with BURN and SAFE off a running step still meets Pokemon")
T.eq(Runtime.call("encounter.roll", vanillaRoll, {},
                  { mapId = "ROUTE_1", terrain = "water" }) ~= nil, true,
  "water is never touched")

-- SAFE GRASS: running through is quiet, walking through is not
setOpt("safe", true)
runOnto(3, 5)
T.eq(roll(), nil, "SAFE GRASS: a running step meets nothing")
walkOnto(3, 6)
T.check(roll() ~= nil, "SAFE GRASS: walking is left exactly as it was")

-- and the vanilla dice are still thrown on the suppressed step, so the
-- stream every other roll draws from stays where vanilla left it
local before = rolls
runOnto(3, 7)
roll()
T.eq(rolls, before + 1, "a suppressed step still draws the vanilla roll")

setOpt("safe", false)

-- BURN GRASS: the cell you ran across is recorded, and stays recorded
setOpt("burn", true)
runOnto(8, 9)
T.eq(roll(), nil, "BURN GRASS: the grass you just set alight holds nothing")
local burnt = loader.modSave.running_shoes
              and loader.modSave.running_shoes.burnt
T.check(burnt and burnt.ROUTE_1 and burnt.ROUTE_1["8,9"] == true,
  "the burnt cell is written into mod.save, so it survives a reload")

-- walking back over it later is just as empty: the grass is gone, and it
-- was not the running that emptied it
walkOnto(8, 9)
T.eq(roll(), nil, "a burnt cell stays empty when you walk back over it")

-- a cell nobody ran across is untouched
walkOnto(9, 9)
T.check(roll() ~= nil, "walking onto unburnt grass is unchanged")
T.check(not (burnt.ROUTE_1["9,9"]), "and walking does not burn anything")

-- a row switched off is a row that does nothing: the burn is remembered,
-- but the grass is grass again until BURN GRASS comes back on
setOpt("burn", false)
walkOnto(8, 9)
T.check(roll() ~= nil, "with BURN GRASS off the burnt cell meets Pokemon again")
T.check(burnt.ROUTE_1["8,9"] == true, "and the burn itself is remembered, not erased")
setOpt("burn", true)
T.eq(roll(), nil, "switching it back on returns the map you left")
setOpt("burn", false)

-- ------- 1.2.0: the trail
--
-- Screen-space, drawn through render.hud over the finished frame.  The
-- stub's love.graphics.rectangle is swapped for a counter, which is the
-- only observable a headless run has: these assert WHETHER it draws and
-- on what condition, never what it looks like.

local VIEWPORT = { width = 640, height = 576, gameX = 0, gameY = 0,
                   gameWidth = 640, gameHeight = 576, scale = 4,
                   dpiX = 1, dpiY = 1 }

local drawn = 0
local realRect = love.graphics.rectangle
love.graphics.rectangle = function() drawn = drawn + 1 end

local function hud()
  drawn = 0
  Runtime.call("render.hud", function() end, STUB, VIEWPORT)
  return drawn
end

-- the anchor the overlay measures from is the player object the
-- movement.speed hook is handed, so it needs the pixel fields a real
-- Player carries
local runner = { px = 48, py = 64, facing = "down", moving = true,
                 stepFramesCur = nil }
local function runTicks(n)
  for _ = 1, n do Runtime.call("input.step", function() end, STUB, 1 / 60) end
end

setOpt("fx", "off")
speed(WALK, ctx{ b = true, player = runner })
runTicks(8)
T.eq(hud(), 0, "RUN FX off draws nothing at all")

setOpt("fx", "dust")
speed(WALK, ctx{ b = true, player = runner })
runTicks(8)
T.check(hud() > 0, "RUN FX dust puts a trail on screen while running")

-- standing still sheds no dust: the particles already out live their few
-- frames and the trail empties itself
runner.moving = false
runTicks(40)
T.eq(hud(), 0, "standing still, the trail expires and stops drawing")

-- a scripted walk is not a run.  B is re-read every tick precisely so the
-- flag left by the last manual step cannot trail the player through a
-- cutscene, so with B released there is nothing to draw.
local released = { data = Data, save = STUB.save, stack = STUB.stack,
                   input = { isDown = function() return false end } }
runner.moving = true
speed(WALK, ctx{ b = true, player = runner })
for _ = 1, 8 do Runtime.call("input.step", function() end, released, 1 / 60) end
T.eq(hud(), 0, "with B released the trail stops, whatever the last step was")

-- every kind draws, and none of them throws
for _, kind in ipairs({ "dust", "fire", "bolt" }) do
  setOpt("fx", kind)
  runner.moving = true
  speed(WALK, ctx{ b = true, player = runner })
  runTicks(12)
  T.check(hud() > 0, "RUN FX " .. kind .. " draws")
end

-- tilt projects the world through a perspective mesh, which a screen-space
-- overlay cannot follow; it stands down rather than drawing the trail
-- somewhere the player is not
STUB.save.options.tilt = 35
T.eq(hud(), 0, "the overlay stands down while tilt owns the world pass")
STUB.save.options.tilt = 0

-- the trail belongs to the map it was shed on
runner.moving = true
speed(WALK, ctx{ b = true, player = runner })
runTicks(12)
Runtime.emit("map.exited", { mapId = "ROUTE_1" })
T.eq(hud(), 0, "leaving the map clears the trail")

-- ------- the scorch marks
--
-- Drawn by the same overlay, from the cells mod.save recorded, and only
-- while BURN GRASS is on: switching the row off puts the map back the way
-- the engine draws it without touching what was burnt.

setOpt("fx", "off")
WORLD.player.cellX, WORLD.player.cellY = 9, 9   -- next to the burnt 8,9
T.eq(hud(), 0, "with BURN GRASS off a burnt cell draws nothing")
setOpt("burn", true)
T.check(hud() > 0, "a burnt cell within view is scorched over the frame")

-- the cell underfoot is skipped: this draws OVER the finished frame, so a
-- patch on the player's own tile would char the player too
WORLD.player.cellX, WORLD.player.cellY = 8, 9
T.eq(hud(), 0, "standing on the burnt cell, nothing is drawn over you")

-- and a burn half a region away is never walked over by the draw loop
WORLD.player.cellX, WORLD.player.cellY = 90, 90
T.eq(hud(), 0, "a burnt cell far off screen costs no draws")
setOpt("burn", false)

love.graphics.rectangle = realRect
loader.game = nil

run.release()
T.finish("running_shoes")
