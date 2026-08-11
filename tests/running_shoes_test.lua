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

-- ------- BURN GRASS: the cut, against a REAL Map
--
-- The previous version of this section asserted that the mod had written a
-- key into its own save table, which is a test of bookkeeping and not of
-- anything the player can see.  The grass was never cut, and the test was
-- green the whole time.
--
-- So these drive src/world/Map itself.  The map, the tileset and the block
-- table are built here, but every question asked of them -- blockAt,
-- tileAt, cellTile, isGrassCell, setBlock -- is the engine's own code, and
-- isGrassCell is the exact predicate OverworldState:onStepComplete gates
-- the wild-encounter roll on.  If the tile is not grass to Map, there is no
-- encounter to suppress and nothing left to take on trust.

local Map = require("src.world.Map")
local OverworldState = require("src.world.OverworldController")

local GRASS, GROUND = 0x52, 0x00

local function blockOf(tile)
  local out = {}
  for i = 1, 16 do out[i] = tile end
  return out
end

-- block 0 is grass in all four of its cells, which is what makes the
-- one-clod claim testable: cut one cell and three must still be grass.
-- Block 2 is ALSO grass and is deliberately absent from the swap table
-- below -- the real tileset is full of grass blocks CUT was never meant
-- to be used on, and matching swaps by block id is what left holes in the
-- player's path.
local TILESET = {
  id = "OVERWORLD",
  blocks = { blockOf(GRASS), blockOf(GROUND), blockOf(GRASS) },
  walkable = { GRASS, GROUND },
  grassTile = GRASS,
  doorTiles = {}, warpTiles = {},
}

local rebuilds = 0

local function freshMap(blockId)
  local def = { id = "ROUTE_1", width = 4, height = 4, tileset = "OVERWORLD",
                borderBlock = 0, blocks = {}, warps = {}, signs = {} }
  for i = 1, def.width * def.height do def.blocks[i] = blockId or 0 end
  local map = Map.new(def, TILESET)
  map.renderer = { rebuild = function() rebuilds = rebuilds + 1 end }
  return map
end

-- a stand-in overworld that borrows the engine's OWN replaceBlock and
-- startDustAnim rather than reimplementing them, so what is under test is
-- the mod plus the engine, not the mod plus a second opinion
local function overworldOn(map)
  return { isOverworld = true, map = map,
           player = { cellX = 0, cellY = 0, facing = "down" },
           replaceBlock = OverworldState.replaceBlock,
           startDustAnim = OverworldState.startDustAnim }
end

local MAP = freshMap()
local OW = overworldOn(MAP)
STUB.stack.states = { OW }
STUB.overworld = OW
-- the swap table the engine's own tryCut reads: before -> the fully cut
-- block.  The mod takes ONE cell's quadrant out of it rather than the
-- whole block, which is the difference between a cut and a clearing.
STUB.data = { field = { cutTreeSwaps = { { before = 0, after = 1 } } } }

-- `live` reaches the mod through the tick hook, the way it does in play
local function tick(game) Runtime.call("input.step", function() end, game or STUB, 1 / 60) end
local runner = { px = 0, py = 0, facing = "down", moving = false }

local function stepOnto(cx, cy, holdingB)
  runner.px, runner.py = cx * 16, cy * 16
  speed(WALK, ctx{ b = holdingB, player = runner })
  tick()
  Runtime.emit("world.stepped", { mapId = "ROUTE_1", x = cx, y = cy,
                                  tile = MAP:cellTile(cx, cy) })
end

T.check(MAP:isGrassCell(2, 3), "the fixture map starts as tall grass")

-- with the row off nothing is touched, however hard you run
setOpt("burn", false)
stepOnto(2, 3, true)
T.check(MAP:isGrassCell(2, 3), "BURN GRASS off: running over grass leaves it standing")

setOpt("burn", true)

-- walking is not running, and only running cuts
stepOnto(2, 3, false)
T.check(MAP:isGrassCell(2, 3), "walking over grass leaves it standing")

-- the cut itself
local before = rebuilds
stepOnto(2, 3, true)
T.check(not MAP:isGrassCell(2, 3), "running over grass CUTS it: the cell is no longer grass")
T.eq(MAP:cellTile(2, 3), GROUND, "and the tile under it is the tileset's own cut tile")
T.eq(rebuilds, before + 1, "the map renderer was rebuilt exactly once for the cut")

-- one clod, not four.  cell (2,3) lives in block (1,1) together with
-- (3,3), (2,2) and (3,2); those three are the whole point of the quadrant
-- arithmetic and must be untouched.
T.check(MAP:isGrassCell(3, 3), "the cell beside it is still grass")
T.check(MAP:isGrassCell(2, 2), "the cell above it is still grass")
T.check(MAP:isGrassCell(3, 2), "the cell diagonal to it is still grass")

-- a SECOND cut in the same block has to read the block back as it now
-- stands, or it would start again from the uncut original and undo the
-- first cut
stepOnto(3, 3, true)
T.check(not MAP:isGrassCell(3, 3), "a second cut in the same block also cuts")
T.check(not MAP:isGrassCell(2, 3), "and the first cut is still cut")
T.check(MAP:isGrassCell(2, 2), "while the two cells nobody ran over stay grass")

-- the engine reads isGrassCell to decide whether to roll at all, so a cut
-- cell is not "suppressed" -- there is nothing there to suppress
T.check(not MAP:isGrassCell(2, 3),
  "a cut cell answers no to the predicate the encounter check gates on")

-- what was cut is recorded, and entering the map again re-applies it: a
-- fresh boot rebuilds the map from its record, with every block uncut
local saved = loader.modSave.running_shoes and loader.modSave.running_shoes.burnt
T.check(saved and saved.ROUTE_1 and saved.ROUTE_1["2,3"] == true,
  "the cut cell is recorded in mod.save so it survives a reload")

MAP = freshMap()
OW = overworldOn(MAP)
STUB.stack.states = { OW }
STUB.overworld = OW
T.check(MAP:isGrassCell(2, 3), "a freshly loaded map starts uncut again")
tick()
Runtime.emit("map.entered", { mapId = "ROUTE_1" })
T.check(not MAP:isGrassCell(2, 3), "entering the map re-applies the cut")
T.check(not MAP:isGrassCell(3, 3), "both cut cells come back")
T.check(MAP:isGrassCell(2, 2), "and the cells that were never cut are still grass")

-- ------- the cut has to FOLLOW the player, with no holes in it
--
-- Two ways the trail used to break, both fixed by taking one tile id out
-- of the swap table instead of matching whole blocks against it.

-- 1. a grass block the swap table has never heard of still cuts
MAP = freshMap(2)                        -- block 2: grass, and not in the swaps
OW = overworldOn(MAP)
STUB.stack.states = { OW }
STUB.overworld = OW
setOpt("burn", true)
T.check(MAP:isGrassCell(1, 1), "the unlisted grass block starts as grass")
stepOnto(1, 1, true)
T.check(not MAP:isGrassCell(1, 1),
  "a grass block absent from the swap table is cut all the same")
T.eq(MAP:cellTile(1, 1), GROUND, "and it is cut to the same ground tile")

-- 2. every cell of a run is cut, so the path is unbroken
MAP = freshMap(2)
OW = overworldOn(MAP)
STUB.stack.states = { OW }
STUB.overworld = OW
runner.facing = "right"
for cx = 0, 5 do stepOnto(cx, 2, true) end
local holes = 0
for cx = 0, 5 do
  if MAP:isGrassCell(cx, 2) then holes = holes + 1 end
end
T.eq(holes, 0, "running six cells cuts all six: the path has no holes in it")
-- and only that row: the run was one cell wide
T.check(MAP:isGrassCell(0, 3) and MAP:isGrassCell(5, 3),
  "the row beside the path is untouched")
T.check(MAP:isGrassCell(0, 1) and MAP:isGrassCell(5, 1),
  "and so is the row above it")
runner.facing = "down"

-- the puff behind a running player is the engine's own dust animation,
-- placed on the cell just vacated rather than the one being landed on.
-- BURN GRASS goes off first: a cut leaves its own puff on the cell it
-- cut, and that is the animation this would otherwise be reading back.
setOpt("burn", false)
setOpt("fx", "dust")
OW.dustAnim = nil
runner.facing = "down"
stepOnto(2, 4, true)
T.check(OW.dustAnim ~= nil, "a running step leaves the engine's dust puff")
T.eq(OW.dustAnim.y, 3, "on the cell just vacated, not the one landed on")

-- and never over one already in flight: that animation owns a callback,
-- and dropping it would strand whatever queued it
OW.dustAnim = { x = 0, y = 0, frames = 30, onDone = function() end }
local held = OW.dustAnim
stepOnto(2, 5, true)
T.eq(OW.dustAnim, held, "an animation already running is never stamped on")
OW.dustAnim = nil

setOpt("burn", false)
setOpt("fx", "off")
STUB.stack.states = { WORLD }
STUB.overworld = nil
STUB.data = Data

-- ------- 1.2.0: the trail
--
-- Screen-space, drawn through render.hud over the finished frame.  The
-- stub's love.graphics.rectangle is swapped for a counter, which is the
-- only observable a headless run has: these assert WHETHER it draws and
-- on what condition, never what it looks like.

local VIEWPORT = { width = 640, height = 576, gameX = 0, gameY = 0,
                   gameWidth = 640, gameHeight = 576, scale = 4,
                   dpiX = 1, dpiY = 1 }

local drawn, minX, maxX = 0, nil, nil
local headW, tailW = nil, nil       -- rect width at each end of the trail
local realRect = love.graphics.rectangle
love.graphics.rectangle = function(_, x, _y, w)
  drawn = drawn + 1
  if type(x) == "number" then
    if not minX or x < minX then minX, tailW = x, w end
    if not maxX or x > maxX then maxX, headW = x, w end
  end
end

local function hud()
  drawn, minX, maxX, headW, tailW = 0, nil, nil, nil, nil
  Runtime.call("render.hud", function() end, STUB, VIEWPORT)
  return drawn
end

-- How far the trail reaches, in CELLS of ground.  VIEWPORT is scale 4 at
-- dpi 1, so one world pixel is 4 screen pixels and a cell is 64 of them.
local function trailCells()
  if not (minX and maxX) then return 0 end
  return (maxX - minX) / (16 * VIEWPORT.scale)
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

-- ------- how far back the trail actually reaches
--
-- The asked-for shape: at least three cells of ground behind the player,
-- fading out rather than stopping.  A trail is made of particles left in
-- world space that the player runs away from, so its length is speed times
-- lifetime -- which means the lifetime has to be derived from the step
-- duration, or the same mod draws a trail twice as long at half the speed.
--
-- These run the player across the map a world pixel at a time, the way
-- Player:update does, and then measure the spread of what reaches
-- love.graphics.  It is the one assertion here that is about how the thing
-- LOOKS, and it is measured rather than eyeballed.

local function runAcross(ticks)
  Runtime.emit("map.exited", {})            -- start from an empty trail
  runner.facing, runner.moving = "right", true
  runner.px, runner.py = 0, 0
  -- One manual step, which is what tells the mod how long a step is; the
  -- trail's lifetime is read off the answer.  That answer is also how fast
  -- the player then travels -- a 16-pixel cell in `sped` ticks -- so the
  -- walk it was derived from is not what moves him.
  local sped = speed(WALK, ctx{ b = true, player = runner })
  for _ = 1, ticks do
    runner.px = runner.px + 16 / sped
    Runtime.call("input.step", function() end, STUB, 1 / 60)
  end
  return sped
end

setOpt("fx", "fire")

-- x2: a 16-frame walk becomes an 8-frame step
setOpt("speed", "2")
T.eq(runAcross(40), BIKE, "the x2 run under test really is an 8-frame step")
hud()
local slow = trailCells()
T.check(slow >= 3,
  ("the trail reaches at least three cells back (got %.1f)"):format(slow))

-- x4 halves the step again, and the trail must still be about as long ON
-- THE GROUND.  This is the assertion a fixed frame count fails: the same
-- lifetime at twice the speed draws twice the trail.
setOpt("speed", "4")
T.eq(runAcross(40), 4, "the x4 run under test really is a 4-frame step")
hud()
local fast = trailCells()
T.check(fast >= 3,
  ("at x4 it still reaches three cells back (got %.1f)"):format(fast))
-- Tight on purpose.  A loose bound here passed happily while the lifetime
-- floor was set ABOVE the fastest rung's honest lifetime, which stretched
-- the trail to nearly six cells at x4 -- at exactly the speed the
-- cells-not-frames measure exists to hold steady.
T.check(math.abs(fast - slow) <= 1,
  ("and the two speeds leave the SAME trail, within a cell (%.1f vs %.1f)")
    :format(slow, fast))
setOpt("speed", "2")

-- ------- big at the heel, small at the tail
--
-- The shape a trail has to have: you should be able to tell which end the
-- player is at from a still frame.  The run above goes RIGHTWARDS, so the
-- freshest particles are at the largest x and the oldest at the smallest,
-- and the rectangles at those two ends are what say whether it tapers.
--
-- An earlier pass had smoke EXPAND as it thinned, which is what real smoke
-- does and which read as a smear rather than as a trail; this is the
-- assertion that keeps all three kinds pointing the same way.

for _, kind in ipairs({ "dust", "fire", "bolt" }) do
  setOpt("fx", kind)
  runAcross(40)
  hud()
  T.check(headW and tailW and headW > tailW,
    ("RUN FX %s tapers: %s wide at the heel, %s at the tail")
      :format(kind, tostring(headW), tostring(tailW)))
end
setOpt("fx", "fire")

-- ------- the puff is not a grass thing, and not a smoke thing
--
-- The engine's dust animation is the most solidly visible part of the
-- trail, and for a while it was given to smoke alone -- which is how
-- flames and bolts came to look like they only existed over tall grass,
-- where the dark tile behind them happened to give the particles an edge.
-- Every kind gets it, on any ground.

for _, kind in ipairs({ "dust", "fire", "bolt" }) do
  setOpt("fx", kind)
  OW.dustAnim = nil
  STUB.overworld = OW
  runner.facing, runner.moving = "down", true
  speed(WALK, ctx{ b = true, player = runner })
  Runtime.call("input.step", function() end, STUB, 1 / 60)
  Runtime.emit("world.stepped", { mapId = "ROUTE_1", x = 2, y = 6 })
  T.check(OW.dustAnim ~= nil, "RUN FX " .. kind .. " leaves the engine's puff too")
end
OW.dustAnim = nil
STUB.overworld = nil
setOpt("fx", "fire")

-- ------- and through the engine's OWN draw path
--
-- Everything above calls the render.hud chain directly, which proves the
-- wrapper works and proves nothing about whether the engine ever reaches
-- it.  This drives src/core/Game.draw itself -- the real function, with
-- only the renderer's frame ends stubbed, exactly the way the engine's own
-- tests/engine/tool_mod_hooks.lua exercises this hook -- and asserts that
-- a trail put on screen from inside it actually reaches love.graphics.
--
-- This is the check that would have caught an overlay wired to a hook the
-- engine never calls.
do
  local Renderer = require("src.render.Renderer")
  local TouchControls = require("src.core.TouchControls")
  local savedUI, savedBegin, savedEnd, savedTouch =
    Renderer.setUISize, Renderer.beginFrame, Renderer.endFrame, TouchControls.draw
  Renderer.setUISize = function() end
  Renderer.beginFrame = function() end
  Renderer.endFrame = function()
    -- the engine's own fixture shape: no dpi fields, which is itself worth
    -- surviving, since the overlay divides by them
    return { width = 640, height = 576, gameX = 0, gameY = 0,
             gameWidth = 640, gameHeight = 576, scale = 4 }
  end
  TouchControls.draw = function() end

  local world = { isOverworld = true, draw = function() end }
  local fake = { overworld = {}, save = STUB.save, input = STUB.input,
                 stack = { states = { world } } }
  function fake.stack:visibleBase() return 1 end
  function fake.stack:top() return self.states[#self.states] end

  setOpt("fx", "fire")
  runner.moving = true
  speed(WALK, ctx{ b = true, player = runner })
  for _ = 1, 10 do Runtime.call("input.step", function() end, fake, 1 / 60) end

  drawn = 0
  require("src.core.Game").draw(fake)
  T.check(drawn > 0,
    "the trail reaches love.graphics through the engine's own Game:draw")

  Renderer.setUISize, Renderer.beginFrame, Renderer.endFrame, TouchControls.draw =
    savedUI, savedBegin, savedEnd, savedTouch
end

-- tilt projects the world through a perspective mesh, which a screen-space
-- overlay cannot follow; it stands down rather than drawing the trail
-- somewhere the player is not
STUB.save.options.tilt = 35
T.eq(hud(), 0, "the overlay stands down while tilt owns the world pass")
STUB.save.options.tilt = 0

-- an engine build with no render.hud call site draws nothing and says so
-- rather than leaving a working option that quietly does nothing
do
  local seen = {}
  local realInfo = require("src.core.Logger").info
  require("src.core.Logger").info = function(fmt, ...)
    seen[#seen + 1] = tostring(fmt)
    return realInfo(fmt, ...)
  end
  for _ = 1, 620 do
    Runtime.call("input.step", function() end, released, 1 / 60)
  end
  require("src.core.Logger").info = realInfo
  local said = false
  for _, line in ipairs(seen) do
    if line:find("render.hud", 1, true) then said = true end
  end
  -- render.hud HAS been called in this suite, so the warning must NOT fire
  T.check(not said, "with render.hud reached, no stale-engine warning is logged")
end

-- the trail belongs to the map it was shed on
runner.moving = true
speed(WALK, ctx{ b = true, player = runner })
runTicks(12)
Runtime.emit("map.exited", { mapId = "ROUTE_1" })
T.eq(hud(), 0, "leaving the map clears the trail")

-- The overlay no longer draws the cut at all, and that is worth asserting
-- rather than merely deleting: with the trail off and BURN GRASS on, over
-- a map with cut cells on it, nothing reaches the screen from this mod.
-- The cut is a block swap the engine draws, so it cannot depend on the one
-- surface that might not exist on an older build.
setOpt("fx", "off")
setOpt("burn", true)
runner.px, runner.py, runner.moving = 2 * 16, 3 * 16, false
speed(WALK, ctx{ b = false, player = runner })
T.eq(hud(), 0, "with the trail off, a map full of cuts draws nothing over the frame")
setOpt("burn", false)

love.graphics.rectangle = realRect
loader.game = nil

run.release()
T.finish("running_shoes")
