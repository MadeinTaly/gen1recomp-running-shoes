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

-- ------- what a run leaves behind
--
-- Three opt-in extras, and they are deliberately three separate rows
-- because they are three separate promises:
--
--   RUN FX      a trail behind the player.
--   BURN GRASS  the clod you ran across is CUT, the way CUT cuts it.
--   SAFE GRASS  running through tall grass never starts a battle.
--
-- ------- the cut, and the version of it that was wrong
--
-- The first attempt drew a dark patch over the tile through `render.hud`
-- and called the grass burnt. It was not burnt. It was a shadow lying on
-- grass that was still standing, the grass still had Pokemon in it, and
-- the whole thing hung off one screen-space overlay that had to be right
-- about the camera, the zoom, the dpi and the compositor to show up at
-- all. Every one of those is a way for the feature to be silently absent.
--
-- The engine already knew how to do this. OverworldState:tryCut cuts tall
-- grass by SWAPPING A BLOCK: `field.cutTreeSwaps` is a before/after table
-- of block ids out of the ROM, and cutting writes the "after" id into the
-- map and rebuilds the renderer. So the grass is genuinely gone -- gone
-- from the picture, and gone from `Map:isGrassCell`, which is the exact
-- predicate the wild-encounter check gates on. Nothing is drawn by us,
-- nothing is suppressed, and it cannot fail to be visible, because it is
-- the map.
--
-- One thing has to be better than the engine's own Cut: a block is 2x2
-- cells, so swapping it whole would take four tiles for one footstep. This
-- assembles a block that is the CURRENT block everywhere except the one
-- cell's 2x2 tile quadrant, which comes from the cut one -- a cut exactly
-- one clod wide, built only from tile ids the tileset already has.
--
-- ------- the trail
--
-- Two layers, and only the second one can fail. The anchor is the ENGINE's
-- own dust puff (`startDustAnim`, the same animation Cut leaves on grass),
-- dropped on the cell just vacated: drawn in the world pass, at the right
-- place under every camera the engine has. On top of it, coloured
-- particles through `render.hud` give dust, flames and bolts their
-- different looks. If that surface is unavailable -- an engine build older
-- than the hook -- the puff is still there and the mod says so in the log.
--
-- The overlay's projection rests on one fact about this engine's camera:
-- `Camera:follow` centres on the player with no lerp and no edge clamp, so
-- the player is not somewhere on screen -- he is ALWAYS at the same place.
-- The world canvas is blitted centred in the window and his cell's
-- top-left corner sits 16 world pixels left of that centre and 8 above it:
--
--     screenX = width/2  - 16*sx + (worldX - player.px) * sx
--     screenY = height/2 -  8*sy + (worldY - player.py) * sy
--
-- ------- SAFE GRASS, and why the dice are still thrown
--
-- The one extra that really is a rule rather than a change to the world.
-- Suppressing by returning nil WITHOUT calling next() would leave the
-- vanilla roll undrawn and shift every later draw off the stream this
-- engine works hard to keep in parity. So a suppressed step calls next()
-- and throws the answer away: it consumes exactly what a vanilla step
-- consumed, and only the battle is missing.

local WALK_FRAMES = 16   -- what the engine uses; only ever read as a fallback
local MIN_FRAMES = 4     -- see "the floor" above

-- ------- the trail

local TRAIL_MAX = 128    -- hard ceiling on live particles; a strobe of them
                         -- is a frame cost, not an effect

local DIRV = { up = { 0, -1 }, down = { 0, 1 },
               left = { -1, 0 }, right = { 1, 0 } }

-- Three shades each, oldest last, because three shades is what a Game Boy
-- sprite had and a smooth gradient would read as somebody else's engine.
--
-- Smoke greys, fire reds, lightning yellows -- and none of them pale,
-- because a pale anything at half opacity over Route 1's green is a rumour
-- rather than an effect.
local SHADES = {
  -- smoke: light where it leaves the ground, darkening as it thins out
  dust = { { 0.88, 0.88, 0.86 }, { 0.60, 0.60, 0.58 }, { 0.34, 0.34, 0.33 } },
  -- fire: orange at the heel, red through the middle, ember at the end
  fire = { { 1.00, 0.55, 0.12 }, { 0.92, 0.16, 0.07 }, { 0.48, 0.05, 0.03 } },
  -- lightning: a white-hot core cooling through yellow into amber
  bolt = { { 1.00, 1.00, 0.88 }, { 1.00, 0.88, 0.15 }, { 0.80, 0.55, 0.04 } },
}

-- Every particle gets a darker skirt underneath it, the way a GB sprite
-- gets its darkest shade: without one, a blob on a bright tile has no edge
-- and stops reading as anything. Smoke gets a grey rather than a black,
-- because smoke outlined in black is a rock.
local OUTLINE = { 0.05, 0.04, 0.04 }
local SKIRT = {
  dust = { 0.22, 0.22, 0.21 },
  fire = OUTLINE,
  bolt = OUTLINE,
}

-- ------- how long a trail is
--
-- Measured in CELLS OF GROUND rather than in frames, because frames are
-- not a length: a step is 8 frames at x2 and 4 at x4, so a fixed lifetime
-- would draw a trail twice as long at half the speed. Particles are left
-- in world space and the player runs away from them, so the trail's length
-- is the player's speed times the lifetime -- and pinning the length means
-- deriving the lifetime from the step duration instead of guessing it.
--
-- Three and a half cells: three clear ones behind the player and the tail
-- of a fourth going out, so the far end fades rather than stops.
local TRAIL_CELLS = 3.5
local LIFE_MIN, LIFE_MAX = 24, 96

-- particles per logic tick while running.  Two, side by side across the
-- width of the cell, so the trail is a band with texture in it rather than
-- a dotted line down the middle.
local PER_TICK = 2

-- How long the engine's own dust puff is held behind a running player.
-- `startDustAnim` hands out 32 frames, which is right for a boulder being
-- shoved and far too long for a footfall at four frames a tile.
local PUFF_FRAMES = 10

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

  -- The live Game, kept from the hook that is handed it every logic tick.
  -- `world.stepped` carries a payload and no game, and the cut needs the
  -- dataset and the running map; this is how it gets there.
  local live

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

  local function remember(mapId, x, y)
    local cells = burntCells(mapId, true)
    if cells then cells[x .. "," .. y] = true end
  end

  -- ------- cutting the grass for real
  --
  -- The first attempt at this drew a dark patch over the tile and called it
  -- burnt. It was not burnt; it was a shadow lying on grass that was still
  -- there, and the grass still had Pokemon in it because nothing about the
  -- map had changed.
  --
  -- What the engine itself does for CUT is the answer, and it is in
  -- OverworldState:tryCut. Cutting grass is a BLOCK SWAP: `field.cutTreeSwaps`
  -- is a table of before/after block ids extracted from the ROM, and cutting
  -- writes the "after" id into the map and rebuilds the renderer. The grass
  -- is then genuinely gone -- gone from the picture, and gone from
  -- `Map:isGrassCell`, which is what the encounter check reads. No overlay,
  -- no hook, no suppression: the tile simply is not tall grass any more.
  --
  -- One thing has to be better than the engine's own Cut, though, because
  -- of what was asked for: a block is 2x2 cells, so swapping it whole would
  -- cut four tiles for one footstep.
  --
  -- And matching a swap by BLOCK ID has a second problem, which is why the
  -- cut used to skip cells and leave holes down the player's path: the
  -- swap table only names the specific blocks CUT was ever meant to be
  -- used on. Run across a grass block that is not in it and there was no
  -- pair to take tiles from, so nothing happened and the trail broke.
  --
  -- So the swap table is read for ONE thing instead: which tile the grass
  -- becomes. Compare any before/after pair tile by tile, and wherever the
  -- before is grass and the after is not, the after is the ground the
  -- grass was standing on. With that single tile id, ANY block can be cut,
  -- one cell at a time, by replacing just that cell's grass tiles -- so
  -- every cell the player runs over is cut and the trail is unbroken.

  local GRASS_TILE = 0x52     -- $52, the OVERWORLD tall-grass tile (tryCut)
  local GRASS_TILESET = "OVERWORLD"

  local synthesized = {}
  local cutTileFor = {}

  -- The tile tall grass leaves behind, learned from the engine's own swap
  -- table rather than guessed. Falls back to the most common walkable tile
  -- in the tileset, which on an outdoor tileset is the plain ground the
  -- grass sits on, so a dataset with no swaps at all still cuts.
  local function cutTile(data, tileset)
    local known = cutTileFor[tileset]
    if known ~= nil then return known or nil end
    local votes, best, bestN = {}, nil, 0
    for _, sw in ipairs(data and data.field and data.field.cutTreeSwaps or {}) do
      local src, dst = tileset.blocks[sw.before + 1], tileset.blocks[sw.after + 1]
      if type(src) == "table" and type(dst) == "table" then
        for i = 1, 16 do
          if src[i] == GRASS_TILE and dst[i] ~= GRASS_TILE then
            votes[dst[i]] = (votes[dst[i]] or 0) + 1
          end
        end
      end
    end
    for tile, n in pairs(votes) do
      if n > bestN then best, bestN = tile, n end
    end
    if not best then
      local walkable, counts = {}, {}
      for _, t in ipairs(tileset.walkable or {}) do walkable[t] = true end
      for _, block in ipairs(tileset.blocks or {}) do
        for i = 1, 16 do
          local t = block[i]
          if walkable[t] and t ~= GRASS_TILE then
            counts[t] = (counts[t] or 0) + 1
            if counts[t] > bestN then best, bestN = t, counts[t] end
          end
        end
      end
    end
    cutTileFor[tileset] = best or false
    return best
  end

  -- `block` with the grass taken out of ONE cell's 2x2 tile quadrant,
  -- appended to the tileset's own block list and cached. Tilesets are
  -- shared tables -- Map.new binds tilesetDef by reference -- so an
  -- appended block is visible to every map drawn from that tileset, and
  -- Map:tileAt reads the list live. Returns nil when that cell had no
  -- grass in it, which is the honest answer to "cut what?".
  local function cutBlock(tileset, block, qx, qy, tile)
    local key = block .. ":" .. qx .. "," .. qy
    local cached = synthesized[key]
    if cached then return cached end
    local src = tileset.blocks[block + 1]
    if type(src) ~= "table" then return nil end
    local out, changed = {}, false
    for i = 1, 16 do out[i] = src[i] end
    for j = 0, 1 do
      for i = 0, 1 do
        local idx = (qy + j) * 4 + (qx + i) + 1
        if out[idx] == GRASS_TILE then
          out[idx] = tile
          changed = true
        end
      end
    end
    if not changed then return nil end
    tileset.blocks[#tileset.blocks + 1] = out
    local id = #tileset.blocks - 1
    synthesized[key] = id
    return id
  end

  -- Reads the LIVE map rather than the map record: a block already cut once
  -- has to be read back as it now stands, or the second cut in the same
  -- block would start again from the uncut original and undo the first.
  -- The write goes through mod.world:replaceBlock, which is the supported
  -- way to change the running map and rebuilds the renderer for us.
  local function cutGrassAt(game, cx, cy, quiet)
    local ow = game and game.overworld
    local map = ow and ow.map
    if not (map and map.def and map.tileset) then return false end
    if map.def.tileset ~= GRASS_TILESET then return false end
    if map.cellTile and map:cellTile(cx, cy) ~= GRASS_TILE then return false end

    local tile = cutTile(game.data, map.tileset)
    if not tile then return false end

    local bx, by = math.floor(cx / 2), math.floor(cy / 2)
    -- which 2x2 tile quadrant of the block this cell is
    local qx, qy = (cx % 2) * 2, (cy % 2) * 2
    local id = cutBlock(map.tileset, map:blockAt(bx, by), qx, qy, tile)
    if not id then return false end

    local ok = mod.world and mod.world:replaceBlock(bx, by, id)
    if not ok then return false end
    remember(map.id, cx, cy)
    -- AnimCut .grass: tall grass gets the leaf-swirl / dust puff rather
    -- than the tree-split slide. Same call the engine's own Cut makes, and
    -- never over one already in flight -- that animation owns a callback
    -- and dropping it would strand whatever queued it.
    if not quiet and ow.startDustAnim and not ow.dustAnim then
      ow:startDustAnim(cx, cy)
    end
    return true
  end

  -- ------- the particles

  local particles = {}
  local spawnClock = 0

  local function clearTrail()
    for i = #particles, 1, -1 do particles[i] = nil end
  end

  -- How long a particle has to live for the trail to reach TRAIL_CELLS
  -- back. A step covers one cell in `frames` ticks, so a particle standing
  -- still in the world is that many ticks behind per cell.
  local function lifeSpan()
    local frames = ourFrames or 8
    local life = math.floor(TRAIL_CELLS * frames + 0.5)
    if life < LIFE_MIN then life = LIFE_MIN end
    if life > LIFE_MAX then life = LIFE_MAX end
    return life
  end

  local function emit(kind, player)
    if #particles >= TRAIL_MAX then return end
    if not (player.px and player.py) then return end
    local d = DIRV[player.facing] or DIRV.down
    -- Across the direction of travel, so the two particles a tick spread
    -- over the width of the cell instead of stacking on one line.
    local ax, ay = -d[2], d[1]
    local spread = rnd() * 10 - 5
    local life = lifeSpan()
    particles[#particles + 1] = {
      kind = kind,
      -- `px`,`py` is the top-left of the 16x16 cell, so +8/+12 is about
      -- where the feet are
      x = player.px + 8 + ax * spread + (rnd() * 3 - 1.5),
      y = player.py + 12 + ay * spread + (rnd() * 3 - 1.5),
      -- Barely any drift: a trail is something LEFT BEHIND, so it stays
      -- where it was shed and the player runs away from it. Give it a push
      -- backwards as well and the far end races the player, which is what
      -- kept the old trail hugging his heels instead of stretching out.
      vx = (rnd() * 0.16 - 0.08),
      vy = -(kind == "fire" and 0.22 or 0.10) + (rnd() * 0.10 - 0.05),
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

  -- One shape for all three: big at the heel, tapering to a point at the
  -- tail. A trail should read as a trail -- you should be able to tell
  -- which end the player is at from the shape alone, without watching it
  -- move. An earlier pass had smoke EXPAND as it thinned, which is what
  -- real smoke does and which read as a smear rather than as a trail.
  local BIG = { dust = 6, fire = 6, bolt = 3 }

  local function sizeOf(kind, p)
    local big = BIG[kind] or 5
    local size = 1 + math.floor((p.life / p.max) * big)
    return size > big and big or size
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

  -- The overworld has to be the state actually on top -- not merely on the
  -- stack -- or the trail would drift over a menu or a battle. `isOverworld`
  -- is read as truthy rather than compared to `true`: it is a marker, and
  -- what a marker is set TO is the engine's business, not ours.
  local function topIsOverworld(game)
    local states = game and game.stack and game.stack.states
    if not states then return true end   -- nothing to gate on; do not vanish
    local top = states[#states]
    return top ~= nil and top.isOverworld and true or false
  end

  -- ------- saying why, once
  --
  -- An effect that is simply absent is the worst thing to debug from the
  -- outside, so every reason the overlay declines to draw is logged the
  -- first time it happens, and the first frame it DOES draw says so too.
  -- One line each, ever: this is a per-frame path.
  local told = {}
  local function once(key, fmt, ...)
    if told[key] then return end
    told[key] = true
    mod.log:info(fmt, ...)
  end

  -- `render.hud` is the surface this draws on, and an engine build from
  -- before it existed simply never calls it: no error, no warning, and an
  -- effect that is silently impossible. Ten seconds of logic ticks with the
  -- hook never once reached is that build, and it is worth saying out loud
  -- rather than leaving somebody staring at a working option that does
  -- nothing.
  local hudCalls, ticks = 0, 0

  local function overlay(game, vp)
    if not (love and love.graphics and love.graphics.rectangle) then return end
    if type(vp) ~= "table" or not (vp.width and vp.height) then
      return once("viewport", "RUN FX: no viewport to draw into")
    end
    local player = anchor
    if not (player and player.px and player.py) then
      return once("anchor", "RUN FX: waiting for the first step to take an anchor")
    end

    if #particles == 0 then return end
    if not topIsOverworld(game) then
      return once("top", "RUN FX: the overworld is not the top state; standing down")
    end
    if not flatWorld(game) then
      return once("flat", "RUN FX: tilt or a world pipeline owns the camera; standing down")
    end

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
    -- The engine leaves this surface clean, but "leaves it clean" is a
    -- promise about today's compositor and this is somebody else's frame.
    -- A palette shader still bound would remap these colours to whatever it
    -- pleased, which is one of the ways an effect ends up invisible rather
    -- than wrong. Say what we need.
    love.graphics.setShader()
    love.graphics.setScissor()
    if love.graphics.setBlendMode then love.graphics.setBlendMode("alpha") end

    local drew = 0

    -- The cut is not drawn here any more, and that is the point: it is a
    -- real block swap in the map, so the engine draws it along with every
    -- other tile. Nothing below is load-bearing -- switch the whole overlay
    -- off and BURN GRASS still cuts, SAFE GRASS still works, and the puff
    -- behind a running player is still there, because all three are the
    -- engine's own drawing rather than ours.

    -- ------- the trail
    for i = 1, #particles do
      local p = particles[i]
      local c = shadeOf(p.kind, p)
      local size = sizeOf(p.kind, p)
      -- Fades the whole way out rather than snapping off at the end of the
      -- trail, but never down to nothing you can see: the far end is a
      -- ghost, not an absence.
      local alpha = 0.30 + 0.70 * (p.life / p.max)
      local skirt = SKIRT[p.kind] or OUTLINE
      if p.kind == "bolt" then
        -- a bolt is lit on alternate ticks: a spark that burns steadily
        -- for ten frames is a lamp, not lightning
        if p.life % 2 == 1 then
          love.graphics.setColor(skirt[1], skirt[2], skirt[3], alpha * 0.85)
          for _, off in ipairs(BOLT) do
            put(p.x + off[1], p.y + off[2] * size / 2 + 1, size, size)
          end
          love.graphics.setColor(c[1], c[2], c[3], alpha)
          for _, off in ipairs(BOLT) do
            put(p.x + off[1], p.y + off[2] * size / 2, size, size)
          end
          drew = drew + 1
        end
      else
        -- Every kind gets a darker skirt, smoke included. A soft grey blob
        -- on a bright tile has no edge and stops reading as anything at
        -- all -- which is how the trail came to look like it only existed
        -- over tall grass, where the tile behind it happens to be dark.
        if size > 2 then
          love.graphics.setColor(skirt[1], skirt[2], skirt[3], alpha * 0.8)
          put(p.x - 1, p.y + 1, size + 2, size + 2)
        end
        love.graphics.setColor(c[1], c[2], c[3], alpha)
        put(p.x, p.y, size, size)
        drew = drew + 1
      end
    end

    love.graphics.pop()
    if drew > 0 then
      once("drawing", "RUN FX: drawing (%d marks this frame, scale %g)", drew, sp)
    end
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

  -- ------- the step that lands
  --
  -- `world.stepped` fires from OverworldState:onStepComplete, and it fires
  -- EARLY in it -- a long way above the wild-encounter check at the bottom
  -- of the same function. That ordering is the whole trick: cut the grass
  -- here and by the time the encounter check looks, `Map:isGrassCell` is
  -- already false and the engine declines the battle by itself. There is
  -- nothing to suppress and no dice to second-guess.
  mod.events:on("world.stepped", function(ev)
    if type(ev) ~= "table" then return end
    local game = live
    if not game then return end

    if enabled("burn") and running then
      cutGrassAt(game, ev.x, ev.y)
    end

    -- The puff behind a running player is the ENGINE's dust animation --
    -- the same one Cut leaves on grass -- placed on the cell just vacated.
    -- It is drawn in the world pass at the right anchor under every camera
    -- the engine has, which is the one thing a screen-space overlay can
    -- never promise. The coloured particles ride on top of it.
    --
    -- EVERY kind gets it, and every step, on any ground. A previous pass
    -- gave the puff to smoke alone on the theory that a grey cloud under a
    -- red flame would look like the fire was smoking -- but the puff is
    -- also the most solidly visible thing in the trail, so withholding it
    -- is what made flames and bolts read as "only over tall grass", where
    -- the dark tile behind them happened to give the particles an edge.
    -- Something you can see everywhere beats a purer palette.
    local kind = fxKind()
    local ow = game.overworld
    if kind ~= "off" and running and ow and ow.startDustAnim
       and not ow.dustAnim and anchor and anchor.facing then
      local d = DIRV[anchor.facing]
      if d then
        ow:startDustAnim(ev.x - d[1], ev.y - d[2])
        -- a trail is a flicker, not the eight beats a boulder gets
        if ow.dustAnim then ow.dustAnim.frames = PUFF_FRAMES end
      end
    end
  end)

  -- A cut is a change to the running map, and the running map is rebuilt
  -- from its record every time the game is loaded afresh. What was cut
  -- lives in mod.save, so entering a map re-applies it -- quietly, with no
  -- puff, because this is restoring a state rather than cutting anything.
  mod.events:on("map.entered", function(ev)
    local game, mapId = live, type(ev) == "table" and ev.mapId or nil
    if not (game and mapId and enabled("burn")) then return end
    local cells = burntCells(mapId, false)
    if not cells then return end
    for key in pairs(cells) do
      if type(key) == "string" then
        local cx, cy = key:match("^(-?%d+),(-?%d+)$")
        cx, cy = tonumber(cx), tonumber(cy)
        if cx and cy then cutGrassAt(game, cx, cy, true) end
      end
    end
  end)

  -- Every logic tick: the moment the player is not moving, the fast value
  -- has done its job and stops being true of anything. The trail is ticked
  -- on the same fixed clock as the step it belongs to, so it neither
  -- speeds up on a 144Hz display nor keeps moving while the game is paused
  -- behind a menu.
  mod.hooks:wrap("input.step", function(next, game, dt)
    local out = next(game, dt)
    live = game
    if tracked and not tracked.moving then restore() end

    advance()
    ticks = ticks + 1
    if ticks > 600 and hudCalls == 0 then
      once("nohud", "RUN FX cannot draw: this engine build never calls the "
        .. "render.hud hook. Update Gen1Recomp; the speed rows are unaffected.")
    end
    local kind = fxKind()
    if kind ~= "off" and anchor and anchor.moving and running then
      -- B is re-read here rather than trusted from the step that started:
      -- a scripted walk never asks `movement.speed`, so without this the
      -- last run's flag would trail the player through a cutscene.
      local input = game and game.input
      if input and input.isDown and input:isDown("b") then
        spawnClock = spawnClock + 1
        for _ = 1, PER_TICK do emit(kind, anchor) end
        once("spawn", "RUN FX: %s trail spawning", kind)
      else
        once("nob", "RUN FX: running step, but B is not down at tick time")
      end
    elseif kind == "off" and running and anchor and anchor.moving then
      once("fxoff", "RUN FX: the RUN FX row is OFF")
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

  -- ------- SAFE GRASS, and only SAFE GRASS
  --
  -- BURN GRASS used to live here too, suppressing the battle on a cell it
  -- had decided was burnt. It does not need to any more: the cut is a real
  -- block swap, so `Map:isGrassCell` answers no and the engine never calls
  -- this hook for that cell at all. A feature that needs no hook is the
  -- better version of the feature.
  --
  -- What is left is the one thing that genuinely is a rule rather than a
  -- change to the world: while you are RUNNING, tall grass starts no wild
  -- battle. The vanilla dice are thrown first and the answer discarded, so
  -- a suppressed step draws from love.math.random exactly what a vanilla
  -- step would have drawn -- only the battle is missing, not the draw
  -- underneath it.
  mod.hooks:wrap("encounter.roll", function(next, encDef, ctx)
    if type(ctx) ~= "table" or ctx.terrain ~= "grass" then
      return next(encDef, ctx)
    end
    local rolled = next(encDef, ctx)
    if running and enabled("safe") then return nil end
    return rolled
  end)

  -- The trail draws over the finished frame, after the world and the UI
  -- have composited, which is the one surface a mod is handed for
  -- screen-space drawing. Decorate after next(), the way every render.hud
  -- wrapper is expected to.
  mod.hooks:wrap("render.hud", function(next, game, viewport)
    local out = next(game, viewport)
    hudCalls = hudCalls + 1
    overlay(game, viewport)
    return out
  end)
end
