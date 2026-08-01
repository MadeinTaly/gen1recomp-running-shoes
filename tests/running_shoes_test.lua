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
local function setSpeed(value) loader.modOptions.running_shoes = { speed = value } end

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

run.release()
T.finish("running_shoes")
