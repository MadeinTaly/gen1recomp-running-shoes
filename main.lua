-- Running Shoes
--
-- Hold B and walk faster. Gen 3 gave them to you in the first five minutes;
-- Gen 1 made you wait for a bicycle.
--
-- ------- how it works
--
-- The engine hands a step's duration through the `movement.speed` hook,
-- whose own comment in src/world/Player.lua names running shoes as the
-- reason it exists -- so this mod is the intended shape, not a workaround.
-- A step is a frame count, and lower is faster:
--
--   16  walking, the vanilla number
--    8  bicycle (which is exactly twice walking, hence "doubles")
--
-- The hook is asked for a number and hands one back. Nothing else is
-- touched -- not collision, not the animation, not the step itself -- so a
-- tile still costs a tile and the world does not care how fast you crossed
-- it. This is a duration knob, and duration is the only thing in it.
--
-- ------- the floor
--
-- Steps are counted in whole frames, so the fast end runs out of road: at
-- x4 a step is four frames, and the next multiplier down would be three,
-- then two, then one -- at which point a tile passes in 1/60th of a second
-- and the walk cycle is a strobe. The ladder stops where the animation
-- still reads as walking rather than teleporting.

-- ------- the one place a duration knob is not just a duration
--
-- `movement.speed` is asked on a MANUAL step, and the answer is stored on
-- the player as `stepFramesCur` (src/world/Player.lua). A SCRIPTED step --
-- the guide who walks you to the Poke Mart, Oak marching you to his lab --
-- is not started through `tryMove`: OverworldState:updateScriptMoves sets
-- `moving` and `progress` directly and never touches `stepFramesCur`.
--
-- So a scripted step reuses whatever the last manual step left there.
-- Measured, on a real Player:
--
--     scripted step, no run before it     16 frames
--     scripted step after a running step    8 frames
--
-- The escort NPC has no such knob -- src/world/NPC.lua keeps its own
-- STEP_FRAMES = 16 and never consults this hook -- so the player crosses
-- two tiles for the guide's one, walks out of the scene, and the dialogue
-- fires late against a player who is no longer where the script put him.
--
-- And it happens nearly every time, because the button that advances the
-- dialogue you are being escorted out of is B, which is also the button
-- that makes you run. You mash B, the last step before the cutscene is a
-- running step, and the cutscene inherits it.
--
-- Vanilla leaves 16 there (8 on the bicycle), which is exactly what the
-- NPCs use. So this is ours to clean up: put back what the engine would
-- have left, the moment the player is standing still.

-- ------- 1.2.0: what a run leaves behind
--
-- Three opt-in extras, and they are deliberately three separate rows
-- because they are three separate promises:
--
--   RUN FX      cosmetic. Draws a trail behind the player and touches
--               nothing else -- not a tile, not a flag, not the RNG.
--   BURN GRASS  the tile you ran across is scorched, and scorched grass
--               holds no Pokemon.
--   SAFE GRASS  running through tall grass never starts a battle.
--
-- The trail is screen-space, drawn over the finished frame through
-- `render.hud`, and it can get away with that because of one fact about
-- this engine's camera: `Camera:follow` (src/render/Camera.lua) centres on
-- the player with no lerp and no edge clamp, so the player is not
-- somewhere on screen -- he is ALWAYS at the same place. The world canvas
-- is blitted centred in the window, and his cell's top-left corner sits 16
-- world pixels left of that centre and 8 above it. That is the entire
-- projection, and every particle is then placed relative to `player.px`:
--
--     screenX = width/2  - 16*sx + (worldX - player.px) * sx
--     screenY = height/2 -  8*sy + (worldY - player.py) * sy
--
-- No camera, no map, no engine internals beyond the player object the
-- `movement.speed` hook is already handed.
--
-- ------- the encounters, and why the dice are still thrown
--
-- `encounter.roll` is asked on every step onto tall grass, even on a map
-- with no encounter table (OverworldState:rollEncounter), and returning
-- nil suppresses the battle. That makes it the one place to both notice
-- "the player just ran into grass" and act on it.
--
-- Suppressing by returning nil WITHOUT calling next() would leave the
-- vanilla roll undrawn and shift every later draw off the stream this
-- engine works hard to keep in parity. So a suppressed step calls next()
-- and throws the answer away: it consumes exactly what a vanilla step
-- consumed, and only the battle is missing.

local WALK_FRAMES = 16   -- what the engine uses; only ever read as a fallback
local MIN_FRAMES = 4     -- see "the floor" above

-- ------- the trail

local TRAIL_MAX = 64     -- hard ceiling on live particles; a strobe of them
                         -- is a frame cost, not an effect

local DIRV = { up = { 0, -1 }, down = { 0, 1 },
               left = { -1, 0 }, right = { 1, 0 } }

-- Three shades each, oldest last, because three shades is what a Game Boy
-- sprite had and a smooth gradient would read as somebody else's engine.
local SHADES = {
  dust = { { 0.87, 0.85, 0.77 }, { 0.68, 0.66, 0.58 }, { 0.47, 0.45, 0.40 } },
  fire = { { 1.00, 0.93, 0.52 }, { 0.97, 0.53, 0.12 }, { 0.70, 0.15, 0.08 } },
  bolt = { { 1.00, 1.00, 1.00 }, { 0.60, 0.90, 1.00 }, { 0.28, 0.52, 0.95 } },
}

local LIFE = { dust = 24, fire = 20, bolt = 8 }

-- one particle every N logic ticks while running; bolts are rarer because
-- lightning that arrives continuously is a light bulb
local CADENCE = { dust = 2, fire = 2, bolt = 4 }

-- a bolt is not a blob: four pixels stacked in a zigzag, drawn upward from
-- the spawn point
local BOLT = { { 0, 0 }, { 1, -2 }, { -1, -4 }, { 0, -6 } }

-- Cosmetic randomness gets its own generator on purpose. The engine draws
-- wild encounters and every battle roll from love.math.random, and a trail
-- that shared that stream would move the game's own dice each time a spark
-- spawned. Nothing in here may be observable in a battle log. Small
-- multiplier and modulus so every product stays exact in a double.
local rngState = 12345
local function rnd()
  rngState = (rngState * 75 + 74) % 65537
  return rngState / 65537
end

return function(mod)
  mod.options:define({
    -- Values are divisors of the step duration, which is why x2 lands
    -- exactly on the bicycle's own 8 frames.
    { key = "speed", label = "RUN SPEED", type = "choice", default = "2",
      choices = {
        { "x1.5", "1.5" },
        { "x2", "2" },
        { "x3", "3" },
        { "x4", "4" },
      } },
    -- The bicycle is already 8 frames. Boosting it too is off by default
    -- because a bike at x4 crosses two tiles in the time the walk cycle
    -- draws one pose, and it looks like a bug rather than a bicycle.
    { key = "bike", label = "BOOST BIKE", type = "toggle", default = false },
    -- Surfing is a Pokemon doing the work, and it has no shoes.
    { key = "surf", label = "BOOST SURF", type = "toggle", default = false },
    -- Purely cosmetic; DUST is the one a pair of shoes could actually
    -- account for, so it is the one that is on.
    { key = "fx", label = "RUN FX", type = "choice", default = "dust",
      choices = {
        { "OFF", "off" },
        { "DUST", "dust" },
        { "FLAMES", "fire" },
        { "BOLTS", "bolt" },
      } },
    -- These two change the game rather than the picture, so they are off.
    { key = "burn", label = "BURN GRASS", type = "toggle", default = false },
    { key = "safe", label = "SAFE GRASS", type = "toggle", default = false },
  })

  local function factor()
    local ok, value = pcall(function() return mod.options:get("speed") end)
    if not ok then return 1 end
    return tonumber(value) or 1
  end

  local function enabled(key)
    local ok, value = pcall(function() return mod.options:get(key) end)
    return ok and value and true or false
  end

  local function fxKind()
    local ok, value = pcall(function() return mod.options:get("fx") end)
    if not ok or type(value) ~= "string" then return "off" end
    return SHADES[value] and value or "off"
  end

  -- ------- putting the duration back
  --
  -- What we sped up, and what the engine would have used instead. Restored
  -- as soon as the player is standing still, so nothing that starts a move
  -- WITHOUT asking the hook can inherit a running step's duration.

  local tracked, ourFrames, vanillaFrames

  -- The player object the hook is handed, kept past the step it arrived
  -- on: it is the anchor every screen-space draw below is measured from,
  -- and it is the same table the engine is animating. Nothing is written
  -- to it here.
  local anchor

  -- Whether the shoes were in play for the step that most recently
  -- STARTED. `encounter.roll` fires after that step lands and is handed no
  -- input, so this is how it knows the player arrived running.
  local running = false

  local function restore()
    local player = tracked
    tracked = nil
    if not player then return end
    -- Only ever undo our own number. If something else has set the duration
    -- since -- another mod, a dismount, a fresh manual step -- that
    -- decision is theirs and this must not stamp on it.
    if player.stepFramesCur == ourFrames then
      player.stepFramesCur = vanillaFrames
    end
  end

  -- ------- burnt cells
  --
  -- Kept in mod.save, so a burnt route is still burnt after a SAVE and a
  -- reload, keyed by map and then by cell. Read through mod.save every
  -- time rather than cached: Game:adoptSave repoints the whole backing
  -- table when a slot is loaded, and a cached reference would go on
  -- writing into the save the player just left.

  local function burntCells(mapId, create)
    if type(mapId) ~= "string" then return nil end
    local all = mod.save:get("burnt")
    if type(all) ~= "table" then
      if not create then return nil end
      all = {}
      mod.save:set("burnt", all)
    end
    local cells = all[mapId]
    if type(cells) ~= "table" then
      if not create then return nil end
      cells = {}
      all[mapId] = cells
    end
    return cells
  end

  local function isBurnt(mapId, x, y)
    local cells = burntCells(mapId, false)
    return cells ~= nil and cells[x .. "," .. y] == true
  end

  local function burn(mapId, x, y)
    local cells = burntCells(mapId, true)
    if cells then cells[x .. "," .. y] = true end
  end

  -- ------- the particles

  local particles = {}
  local spawnClock = 0

  local function clearTrail()
    for i = #particles, 1, -1 do particles[i] = nil end
  end

  local function emit(kind, player)
    if #particles >= TRAIL_MAX then return end
    if not (player.px and player.py) then return end
    local d = DIRV[player.facing] or DIRV.down
    -- `px`,`py` is the top-left of the 16x16 cell the player stands in, so
    -- +8/+12 is roughly where the feet are; the trail leaves from behind
    -- them, which is the direction of travel negated
    local life = LIFE[kind] or 20
    particles[#particles + 1] = {
      kind = kind,
      x = player.px + 8 - d[1] * 8 + (rnd() * 6 - 3),
      y = player.py + 12 - d[2] * 8 + (rnd() * 4 - 2),
      -- drift backwards along the travel axis and upward: the trail falls
      -- behind and rises, the way anything shed at speed does
      vx = -d[1] * 0.35 + (rnd() * 0.30 - 0.15),
      vy = -d[2] * 0.35 - (kind == "fire" and 0.30 or 0.16),
      life = life, max = life,
    }
  end

  local function advance()
    local kept = 0
    for i = 1, #particles do
      local p = particles[i]
      p.life = p.life - 1
      if p.life > 0 then
        p.x, p.y = p.x + p.vx, p.y + p.vy
        kept = kept + 1
        particles[kept] = p
      end
    end
    for i = #particles, kept + 1, -1 do particles[i] = nil end
  end

  -- ------- drawing
  --
  -- Everything below is guarded so a headless run (no love, no graphics)
  -- and a frame with nothing to show both cost a single comparison.

  local function shadeOf(kind, p)
    local set = SHADES[kind] or SHADES.dust
    local t = p.life / p.max            -- 1 fresh, 0 gone
    if t > 0.66 then return set[1] end
    if t > 0.33 then return set[2] end
    return set[3]
  end

  local function sizeOf(kind, p)
    if kind == "bolt" then return 1 end
    local t = p.life / p.max
    if t > 0.6 then return kind == "fire" and 3 or 2 end
    if t > 0.3 then return 2 end
    return 1
  end

  -- The world pass is not always a flat blit of the world canvas: tilt
  -- projects it through a perspective mesh, and a mod's render pipeline
  -- may replace it with geometry of its own. A screen-space overlay cannot
  -- follow either camera, so it stands down rather than drawing the trail
  -- somewhere the player is not.
  local function flatWorld(game)
    local opts = game and game.save and game.save.options
    if type(opts) ~= "table" then return true end
    if (tonumber(opts.tilt) or 0) > 0 then return false end
    if type(opts.pipelines) == "table" then
      for id, level in pairs(opts.pipelines) do
        if (tonumber(level) or 0) > 0 then
          local def = mod.content.render_pipelines:get(id)
          if def and def.drawWorld then return false end
        end
      end
    end
    return true
  end

  -- World pixels per screen pixel. The viewport reports the fit scale; the
  -- world pass draws at the survey zoom on top of it (src/render/Zoom.lua),
  -- whose vanilla range is [1, 2 x fit].
  local function worldScale(game, vp)
    local fit = tonumber(vp.scale) or 1
    local opts = game and game.save and game.save.options
    local s = fit + (tonumber(opts and opts.zoom) or 0)
    if s < 1 then s = 1 end
    if s > fit * 2 then s = fit * 2 end
    return s
  end

  local function topIsOverworld(game)
    local states = game and game.stack and game.stack.states
    local top = states and states[#states]
    return top ~= nil and top.isOverworld == true
  end

  local function overlay(game, vp)
    if not (love and love.graphics and love.graphics.rectangle) then return end
    if type(vp) ~= "table" or not (vp.width and vp.height) then return end
    local player = anchor
    if not (player and player.px and player.py) then return end

    local burnOn = enabled("burn")
    if #particles == 0 and not burnOn then return end
    if not topIsOverworld(game) then return end
    if not flatWorld(game) then return end

    local sp = worldScale(game, vp)
    local sx = sp / (tonumber(vp.dpiX) or 1)
    local sy = sp / (tonumber(vp.dpiY) or 1)
    local ox = vp.width / 2 - 16 * sx
    local oy = vp.height / 2 - 8 * sy

    -- one world-pixel rectangle, snapped to whole screen pixels so the
    -- result reads as pixel art rather than as smeared vector fills
    local function put(wx, wy, w, h)
      love.graphics.rectangle("fill",
        math.floor(ox + (wx - player.px) * sx + 0.5),
        math.floor(oy + (wy - player.py) * sy + 0.5),
        math.max(1, math.floor(w * sx + 0.5)),
        math.max(1, math.floor(h * sy + 0.5)))
    end

    love.graphics.push("all")

    -- ------- scorched cells
    --
    -- A checker of 4x4 world-pixel squares rather than a solid block: the
    -- grass underneath still shows through the gaps, so the cell reads as
    -- charred stubble instead of a hole cut in the map. The cell the
    -- player is standing on is skipped, because this draws OVER the
    -- finished frame and a solid patch on his own tile would char him too.
    if burnOn then
      local here = mod.world and mod.world:current()
      local cells = here and burntCells(here.mapId, false)
      if cells and here.x then
        -- how far a cell can be from the player and still be on screen, at
        -- whatever zoom this frame is drawn at, so the loop never walks a
        -- whole burnt region to reject it
        local rx = math.ceil(vp.width / sx / 32) + 1
        local ry = math.ceil(vp.height / sy / 32) + 1
        love.graphics.setColor(0.10, 0.08, 0.07, 0.62)
        for key in pairs(cells) do
          local cx, cy
          if type(key) == "string" then
            cx, cy = key:match("^(-?%d+),(-?%d+)$")
            cx, cy = tonumber(cx), tonumber(cy)
          end
          if cx and cy and math.abs(cx - here.x) <= rx
             and math.abs(cy - here.y) <= ry
             and not (cx == here.x and cy == here.y) then
            for i = 0, 3 do
              for j = 0, 3 do
                if (i + j) % 2 == 0 then
                  put(cx * 16 + i * 4, cy * 16 + j * 4, 4, 4)
                end
              end
            end
          end
        end
      end
    end

    -- ------- the trail
    for i = 1, #particles do
      local p = particles[i]
      local c = shadeOf(p.kind, p)
      if p.kind == "bolt" then
        -- a bolt is lit on alternate ticks: a spark that burns steadily
        -- for eight frames is a lamp, not lightning
        if p.life % 2 == 1 then
          love.graphics.setColor(c[1], c[2], c[3], 1)
          for _, off in ipairs(BOLT) do
            put(p.x + off[1], p.y + off[2], 1, 1)
          end
        end
      else
        local size = sizeOf(p.kind, p)
        love.graphics.setColor(c[1], c[2], c[3], 0.35 + 0.6 * (p.life / p.max))
        put(p.x, p.y, size, size)
      end
    end

    love.graphics.pop()
  end

  -- ------- wiring

  -- A cutscene queues its moves right after this fires, which closes the
  -- one-frame gap where a script could start a step on the same tick the
  -- running step ended, before the idle check below gets a look. The trail
  -- goes with it: a scripted walk is not a run.
  mod.events:on("script.started", function()
    restore()
    clearTrail()
  end)

  -- Nothing shed on the last map belongs on this one, and nothing shed in
  -- the overworld belongs over a battle's opening frames.
  mod.events:on("map.exited", clearTrail)
  mod.events:on("battle.started", clearTrail)

  -- Every logic tick: the moment the player is not moving, the fast value
  -- has done its job and stops being true of anything. The trail is ticked
  -- on the same fixed clock as the step it belongs to, so it neither
  -- speeds up on a 144Hz display nor keeps moving while the game is paused
  -- behind a menu.
  mod.hooks:wrap("input.step", function(next, game, dt)
    local out = next(game, dt)
    if tracked and not tracked.moving then restore() end

    advance()
    local kind = fxKind()
    if kind ~= "off" and anchor and anchor.moving and running then
      -- B is re-read here rather than trusted from the step that started:
      -- a scripted walk never asks `movement.speed`, so without this the
      -- last run's flag would trail the player through a cutscene.
      local input = game and game.input
      if input and input.isDown and input:isDown("b") then
        spawnClock = spawnClock + 1
        if spawnClock % (CADENCE[kind] or 2) == 0 then emit(kind, anchor) end
      end
    end
    return out
  end)

  -- Call next() first and adjust what comes back, so a mod that also has an
  -- opinion about step duration -- a slowness field, a swamp, a status --
  -- keeps its say and this multiplies whatever it decided rather than
  -- overwriting it.
  mod.hooks:wrap("movement.speed", function(next, frames, ctx)
    local base = tonumber(next(frames, ctx)) or WALK_FRAMES
    if type(ctx) ~= "table" then return base end

    -- Every manual step passes through here, running or not, which makes
    -- this the honest place to answer both "is the player running?" and
    -- "which player?" -- and to answer NO the moment he stops.
    running = false
    if ctx.player then anchor = ctx.player end

    local input = ctx.input
    if not (input and input.isDown and input:isDown("b")) then return base end
    if ctx.onBike and not enabled("bike") then return base end
    if ctx.surfing and not enabled("surf") then return base end

    local f = factor()
    if f <= 1 then return base end
    running = true

    local sped = math.floor(base / f + 0.5)
    if sped < MIN_FRAMES then sped = MIN_FRAMES end
    -- Never hand back something slower than what we were given: a mod that
    -- already made this step quicker than our own floor should keep it.
    if sped > base then return base end

    -- remember the pair so the step can be handed back to the engine's own
    -- number once it is over (see "putting the duration back")
    tracked, ourFrames, vanillaFrames = ctx.player, sped, base
    return sped
  end)

  -- ------- grass
  --
  -- Asked on every step onto tall grass. Three answers, in the order they
  -- have to be checked:
  --
  --   already burnt   nothing lives there any more, running or walking
  --   burning it now  you set it alight this step, so nothing is left
  --   SAFE GRASS      you ran through, and nothing had time to notice
  --
  -- All three throw the vanilla dice first and discard the answer, so a
  -- suppressed step draws from love.math.random exactly what a vanilla
  -- step would have drawn (see the header).
  --
  -- Everything about burning hangs off the row being ON, the scorch marks
  -- included: switching BURN GRASS off puts the map back exactly as the
  -- engine draws it and gives the grass its Pokemon back. What was burnt
  -- is remembered rather than erased, so switching it on again returns the
  -- map you actually left -- but a row you turned off is a row that does
  -- nothing, and a player who tries this must not be stuck with a scarred
  -- save and no way back.
  mod.hooks:wrap("encounter.roll", function(next, encDef, ctx)
    if type(ctx) ~= "table" or ctx.terrain ~= "grass" then
      return next(encDef, ctx)
    end
    local burnOn, safeOn = enabled("burn"), enabled("safe")
    if not (burnOn or safeOn) then return next(encDef, ctx) end

    -- `encounter.roll` is handed the map but not the cell; the overworld
    -- has already moved the player onto it, so this is that cell.
    local here = mod.world and mod.world:current()
    local x, y = here and here.x, here and here.y
    local rolled = next(encDef, ctx)
    if not (x and y) then return rolled end

    if burnOn and isBurnt(ctx.mapId, x, y) then return nil end
    if not running then return rolled end
    if burnOn then
      burn(ctx.mapId, x, y)
      return nil
    end
    return nil   -- SAFE GRASS is the only row left that could be on
  end)

  -- The trail draws over the finished frame, after the world and the UI
  -- have composited, which is the one surface a mod is handed for
  -- screen-space drawing. Decorate after next(), the way every render.hud
  -- wrapper is expected to.
  mod.hooks:wrap("render.hud", function(next, game, viewport)
    local out = next(game, viewport)
    overlay(game, viewport)
    return out
  end)
end
