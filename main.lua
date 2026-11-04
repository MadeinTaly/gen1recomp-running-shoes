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
-- Gold's own CUT is the same kind of whole-block swap, off a different
-- table (`FieldMoves.CUT_BLOCKS`, src/world/gen2/FieldMoves.lua:262) with no
-- tile ids in it at all, only block ids and an animation byte -- so the
-- one-clod trick above runs there too, built from a block DIFF instead of a
-- constant. See "cutting the grass on Gold" further down for the shape of
-- it and why Gold also needs a synthesized COLLISION entry alongside the
-- synthesized tile block, which Gen 1's tile-id walkability never required.
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
-- Gold has no `startDustAnim` to borrow (see "what changes on Gold" further
-- down), so there the coloured particles ARE the whole trail -- which is
-- also true the moment this mod runs on an engine build with no
-- `startDustAnim` at all, so nothing about the coloured layer assumes it.
--
-- The overlay's projection rests on one fact about the engine's camera, and
-- it holds in both games because both call the SAME module the same way:
-- `Camera:follow` (src/render/Camera.lua:14) centres on the player with no
-- lerp and no edge clamp, so the player is not somewhere on screen -- he is
-- ALWAYS at the same place. Gen 1's `OverworldController.lua:485` and Gold's
-- `World.lua:9928` both call `camera:follow(p.px, p.py, viewW, viewH)`, and
-- both size that view the same way -- forced to an even width and height, and
-- grown for tilt (`Renderer:worldViewSize`, src/render/Renderer.lua:236, vs
-- `World:draw`, World.lua:9906-9920) -- so the world canvas is blitted
-- centred in the window under either engine, and his cell's top-left corner
-- sits 16 world pixels left of that centre and 8 above it:
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

-- Five discrete shades cool with age; no interpolated gradients.
local RAMP = {
  dust = {
    { 1.00, 0.96, 0.85 }, { 0.85, 0.83, 0.73 }, { 0.62, 0.65, 0.60 },
    { 0.39, 0.45, 0.44 }, { 0.22, 0.28, 0.30 },
  },
  fire = {
    { 1.00, 0.98, 0.78 }, { 1.00, 0.80, 0.23 }, { 1.00, 0.43, 0.12 },
    { 0.82, 0.17, 0.14 }, { 0.38, 0.08, 0.16 },
  },
  bolt = {
    { 1.00, 1.00, 0.94 }, { 1.00, 0.94, 0.48 }, { 1.00, 0.72, 0.15 },
    { 0.70, 0.40, 0.09 }, { 0.31, 0.20, 0.16 },
  },
}

-- Original pixel art: 1 = rim, 2 = body, 3 = light, . = clear.
-- Each phase changes the silhouette as well as the lighting. Clouds roll,
-- flames split and lean, and lightning jumps between forked channels.
local ART = {
  dust = {
    { "..111...", ".13321..", "1333321.", "12332211", "12222221", ".122221.", "..1111..", "........" },
    { "...11...", ".11331..", "1333321.", "12332221", "12221221", ".122221.", "..1111..", "........" },
    { "..111...", ".133211.", "13332231", "12322221", ".122221.", "..1221..", "...11...", "........" },
  },
  fire = {
    { ".....1..", "....21..", ".1.121..", ".21221..", "1223221.", "12333221", ".2333321", "..12221." },
    { "..1.....", "..21..1.", "..22121.", ".122221.", ".2233221", "12333321", "1233321.", ".12221.." },
    { "....1...", ".1..21..", ".21.221.", ".222221.", "1223321.", "12333321", ".2333221", "..12221." },
  },
  bolt = {
    { "......1..", ".....21..", "....231..", "...231...", "..2331..1", "...231.21", "....2321.", "...2331..", "..2331...", "...231...", "....1...." },
    { "..1......", "..12.....", "...132...", "....132..", "1..1332..", "12..132..", ".12332...", "..1332...", "...1332..", "....132..", ".....1..." },
    { ".....1...", "....21...", "...231...", "..2331...", "...231..1", "....23221", "...2331..", "..2331...", "...231...", "....21...", "....1...." },
  },
}

-- Compile nearest-neighbour size variants into disjoint horizontal runs.
-- Every pixel is composited once, avoiding muddy translucent overpainting.
-- Rendering allocates no masks and performs no per-pixel table traversal.
local FRAMES = {}
for kind, phases in pairs(ART) do
  FRAMES[kind] = {}
  for size = 1, 8 do
    local width = kind == "bolt" and (size * 3 - 2) or size
    local height = kind == "bolt" and (size * 3 + 2) or size
    local variants = {}
    for phase, rows in ipairs(phases) do
      local runs = {}
      for y = 0, height - 1 do
        local row = rows[math.floor(y * #rows / height) + 1]
        local x = 0
        while x < width do
          local ink = row:sub(math.floor(x * #row / width) + 1,
                              math.floor(x * #row / width) + 1)
          local start = x
          repeat
            x = x + 1
            local at = math.floor(x * #row / width) + 1
            if x >= width or row:sub(at, at) ~= ink then break end
          until false
          if ink ~= "." then
            runs[#runs + 1] = { x = start, y = y, w = x - start,
                                 ink = tonumber(ink) }
          end
        end
      end
      -- Tiny tail particles must remain legible even when sampling misses
      -- a narrow tongue or spark in the full-size drawing.
      if #runs == 0 then runs[1] = { x = 0, y = height - 1, w = 1, ink = 2 } end
      variants[phase] = { runs = runs, width = width, height = height }
    end
    FRAMES[kind][size] = variants
  end
end

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
-- The floor has to sit UNDER the fastest rung or it stops being a floor and
-- starts being the answer: at x4 a step is 4 frames, so the honest lifetime
-- is 14 ticks, and a floor of 24 stretched the trail to nearly six cells at
-- exactly the speed the cells measure exists to keep steady.
local LIFE_MIN, LIFE_MAX = 10, 96

-- particles per logic tick while running.  Two, side by side across the
-- width of the cell, so the trail is a band with texture in it rather than
-- a dotted line down the middle.
local PER_TICK = 2

-- ------- and where it is shed
--
-- Behind the HEELS, not under the middle of the sprite. The trail used to
-- spawn at the player's own centre and drift out from there, which put its
-- freshest and brightest marks inside the sprite's own 16x16 box -- and
-- because `render.hud` composites over the finished frame, inside that box
-- means ON TOP OF THE CHARACTER rather than behind him. It reads as the
-- effect covering the player's face on the sides where his art happens to
-- reach the trailing edge, which is why running rightwards was reported as
-- broken and running leftwards was not.
--
-- At the heels, not a cell and a quarter behind them.
--
-- This was 20 -- more than a whole cell back along the way you came --
-- because the trail kept reading as drawn ON the character and each
-- attempt to clear him pushed the number up. Twenty does clear him. It
-- also detaches the effect from the runner: at four frames a tile the
-- freshest mark is already a cell away by the time you see it, so the
-- trail does not follow the player, it trails a player-shaped gap. That is
-- what "the FX does not follow the character properly" is.
--
-- Fourteen is the closest it can honestly get, and the suite is what said
-- so: at ten the spawn lands INSIDE the grown sprite box, `onSprite` drops
-- every particle, and the trail does not merely sit wrong -- it vanishes.
-- ("RUN FX dust puts a trail on screen while running" is the check that
-- caught it.)
--
-- Eight world pixels from the centre reaches the sprite's trailing edge and
-- the particle's own reach is four more, so twelve is the floor and
-- fourteen clears it with the jitter. Six pixels closer than twenty is
-- most of the gap the player was looking at, and `onSprite` still culls
-- anything that drifts back onto him, every frame, in every direction.
local BEHIND = 14

-- The sprite's own box, relative to the cell origin the camera is anchored
-- on: `SpriteRenderer:draw` puts a 16x16 frame at (px, py - 4)
-- (src/world/OverworldController.lua:89), so the character occupies px..px+16
-- across and py-4..py+12 down. Nothing of ours may draw inside it.
local SPRITE_W, SPRITE_TOP, SPRITE_BOT = 16, -4, 12

-- How far a particle reaches from its own centre, which is what the box has
-- to be grown by before asking whether the mark is on the character: a
-- CENTRE outside the sprite says nothing when the rows around it are drawn
-- four pixels out. Puffs and flames fit an eight-pixel square; a bolt is a jagged line
-- climbing ten pixels UPWARD from its base, so it
-- reaches far above its centre and barely at all below.
local REACH = {
  dust = { x = 4, up = 4, down = 4 },
  fire = { x = 4, up = 5, down = 5 },
  bolt = { x = 5, up = 11, down = 1 },
  rainbow = { x = 4, up = 4, down = 4 },
}

-- How long the engine's own dust puff is held behind a running player.
-- `startDustAnim` hands out 32 frames, which is right for a boulder being
-- shoved and far too long for a footfall at four frames a tile.
local PUFF_FRAMES = 10

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
  -- Gen 3 is its own arm wherever the picture or the map is touched: a 240x160
  -- full-colour frame, 16x32 sprites and metatiles rather than Game Boy blocks.
  local GENERATION = mod.generation
  if GENERATION == nil then
    local okGen, generation = pcall(function()
      return require("src.core.GameVersion").generation()
    end)
    GENERATION = okGen and generation or 1
  end
  local GEN3 = GENERATION == 3

  local optionRows = {
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
        { "RAINBOW", "rainbow" },
      } },
    -- These two change the game rather than the picture, so they are off.
    { key = "burn", label = "BURN GRASS", type = "toggle", default = false },
    { key = "safe", label = "SAFE GRASS", type = "toggle", default = false },
    -- A wild Pokemon met at a run starts the battle hit by your trail.
    { key = "trail_status", label = "TRAIL STATUS", type = "toggle", default = false },
  }
  -- Worn shoes are drawn on one sheet's own feet, so a row only exists where that
  -- sheet does. For now that is Emerald's Brendan; the other carts' sprites have
  -- different feet, and a row there would be a switch that does nothing.
  local okCart, cart = pcall(function() return require("src.core.GameVersion").get() end)
  local OTHER_CART = { firered = true, leafgreen = true, ruby = true, sapphire = true }
  local SHOES_HERE = GEN3 and not (okCart and OTHER_CART[cart])
  if SHOES_HERE then
    optionRows[#optionRows + 1] = { key = "shoe_model", label = "SHOE MODEL",
      type = "choice", default = "off", choices = {
        { "OFF", "off" }, { "SNEAKERS", "sneaker" }, { "BOOTS", "boot" },
        { "WINGED", "winged" }, { "SKATES", "skate" }, { "SANDALS", "sandal" },
        { "CLOWN", "clown" }, { "ROCKET", "rocket" },
      } }
    optionRows[#optionRows + 1] = { key = "shoe_color", label = "SHOE COLOUR",
      type = "choice", default = "red", choices = {
        { "RED", "red" }, { "ORANGE", "orange" }, { "YELLOW", "yellow" },
        { "GREEN", "green" }, { "BLUE", "blue" }, { "PURPLE", "purple" },
        { "PINK", "pink" }, { "WHITE", "white" }, { "BLACK", "black" },
      } }
  end
  mod.options:define(optionRows)

  local function factor()
    local ok, value = pcall(function() return mod.options:get("speed") end)
    if not ok then return 1 end
    return tonumber(value) or 1
  end

  local function enabled(key)
    local ok, value = pcall(function() return mod.options:get(key) end)
    return ok and value and true or false
  end

  -- ------- which generation is running
  --
  -- Read off the live game rather than a version allow-list, which is the
  -- one shape that excludes a mod from Gold by construction. `live` is the
  -- game the hooks below are handed every logic tick; before the first one
  -- arrives nothing that asks this has anything to do anyway. `isGen2Save`
  -- takes a save table directly so the render.hud arm below -- which is
  -- handed its own `game` argument, not necessarily the same table `live`
  -- points at yet -- can ask the same question of whatever it was actually
  -- given, rather than of a global that might still be nil on the very
  -- first frame.
  local function isGen2Save(save)
    return save ~= nil and save.generation == 2
  end

  local function isGen2()
    return isGen2Save(live and live.save)
  end

  local function isGen2Game(game)
    return isGen2Save(game and game.save)
  end

  -- ------- what changes on Gold, and why
  --
  -- The speed crosses over unchanged: src/world/gen2/World.lua:8817 raises
  -- `movement.speed` with the same ctx keys the Gen 1 site offers (and adds
  -- `downhill` and `playerState`, because the Cycling Road already needed
  -- them). Better still, Gold rewrites the base duration from scratch every
  -- step -- World.lua:8787 for walking, :8807 for the bike, both BEFORE the
  -- hook -- so the "put the number back" dance the Gen 1 arm has to do is
  -- not merely unnecessary there, it has nothing to undo.
  --
  -- CUT GRASS and RUN FX used to stand down here too, on the strength of two
  -- claims that turned out to be about the WRONG place to look rather than
  -- about a missing capability:
  --
  --   CUT GRASS   "the swap table has no Gen 2 home" was true of
  --               `data.field.cutTreeSwaps` and beside the point, because
  --               Gold's own CUT does not read that table at all. It reads
  --               `FieldMoves.CUT_BLOCKS` (src/world/gen2/FieldMoves.lua:262),
  --               a per-tileset { facing block -> replacement block,
  --               animation } table, and `World:runCut` (World.lua:5271)
  --               swaps the whole block once the text box closes. That is
  --               reachable from a mod with `engine_internals` (already
  --               declared below) the same way this file already reaches
  --               `mod.world:replaceBlock`, which is `WorldAPI:replaceBlock`
  --               (src/world/gen2/WorldAPI.lua:134) calling straight through
  --               to `World:changeBlock` (World.lua:2014) -- the exact write
  --               `runCut` itself makes. See "cutting the grass on Gold"
  --               below for the one real difference: Gold's grass is not one
  --               tile id the way Red's is, so the one-clod trick has to
  --               diff BLOCKS instead of comparing against a constant.
  --
  --   RUN FX      "measured from the Gen 1 world canvas" was also beside the
  --               point: the projection below never reads anything Gen 1
  --               specific, only `Camera:follow` (src/render/Camera.lua:14)
  --               and the viewport `render.hud` hands over, and Gold's own
  --               `World:draw` (World.lua:9889) calls the SAME
  --               `self.camera:follow(p.px, p.py, vw, vh)` with the SAME
  --               even-size-and-tilt-growth view sizing Gen 1's
  --               `Renderer:worldViewSize` (src/render/Renderer.lua:236)
  --               works out for itself -- one module, one formula, two
  --               callers. What genuinely needed a Gen 2 arm was
  --               `topIsOverworld` below: Gold's overworld is not a stack
  --               state (see the note over it), so the Gen 1 test for "is it
  --               safe to draw" always answered no on a plain walk, which is
  --               what actually stood the trail down, not the projection.
  --
  -- One piece of each honestly does not cross, and both are gated rather
  -- than faked:
  --
  --   * the ENGINE's own dust puff behind a running step
  --     (`OverworldState.startDustAnim`) has no Gen 2 backing at all --
  --     Gold's World never gets a `game.overworld` (Game2.lua has no such
  --     field; WorldAPI.lua:39 reads `game.world` instead) and
  --     `src/world/gen2/World.lua` has no `startDustAnim` method to call.
  --     The `ow and ow.startDustAnim` guards in `world.stepped` below
  --     already answer nil on Gold and skip it; the mod's OWN coloured
  --     particles do not depend on that puff and keep drawing regardless
  --     (see "the puff is not a grass thing" further down).
  --   * an engine build with no `render.hud` call site is still a real gate,
  --     generation or not -- that is the `nohud` warning further down.
  local function cutOn()
    return enabled("burn")
  end

  -- The kinds this knows how to draw. It used to ask RAMP, which was the
  -- same question for as long as every effect was a five-colour ramp read
  -- by age -- and then RAINBOW arrived, whose colour comes from the MARK
  -- and lives in a table of its own. RAMP had no row for it, so `fxKind`
  -- answered "off", not one particle was ever emitted, and the option sat
  -- in the menu doing nothing. A list of names says what it means.
  local KINDS = { dust = true, fire = true, bolt = true, rainbow = true }

  local function fxKind()
    local ok, value = pcall(function() return mod.options:get("fx") end)
    if not ok or type(value) ~= "string" then return "off" end
    return KINDS[value] and value or "off"
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

  -- The same two facts, as the free-roam camera's continuous walk states
  -- them: whether it covered ground on the tick just gone (there is no
  -- `player.moving` to read there -- see "running under a camera that took
  -- the walk away" further down), and how many frames a cell is costing at
  -- the speed it is walking, which is the number the trail measures its
  -- length in. Both nil/false on the grid, and put back that way by
  -- `movement.speed` on every manual step.
  local freeMoving = false
  local freeFrames = nil

  -- The live Game, kept from the hook that is handed it every logic tick.
  -- `world.stepped` carries a payload and no game, and the cut needs the
  -- dataset and the running map; this is how it gets there.
  local live

  -- TRAIL STATUS: what the next wild battle starts with, and the cell a deferred
  -- cut is still waiting to take.
  local pendingTrail, lastCell

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

  -- ------- IT GROWS BACK, BECAUSE CUT'S GRASS GROWS BACK
  --
  -- This used to be kept in `mod.save`, keyed by map, and re-applied every
  -- time you walked back in. That made a run through a field permanent:
  -- one lap of Route 1 and the grass was gone from that save for good.
  --
  -- The engine's own CUT does not work that way, and it is the thing this
  -- is imitating. Cutting swaps a block in the RUNNING map
  -- (OverworldState:tryCut); nothing writes it down. Leave the map and it
  -- is rebuilt from its record, grass and all -- which is why you can cut
  -- the same bush twice in one playthrough.
  --
  -- So the cut lives exactly as long as the map is loaded, and there is
  -- nothing left here to remember it with. A run leaves a path behind you
  -- while you are in the field, and the field is whole again next time.
  local function forgetLegacyBurnt()
    -- Saves written before this release carry the old table. Clearing it
    -- is not tidiness: leaving it there would mean an old save still had
    -- its fields flattened by a version that no longer believes in that,
    -- and nothing would ever grow back for those players.
    local ok, all = pcall(function() return mod.save:get("burnt") end)
    if ok and type(all) == "table" then
      pcall(function() mod.save:set("burnt", nil) end)
    end
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
  local function cutGrassAtGen1(game, cx, cy, quiet)
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
    -- AnimCut .grass: tall grass gets the leaf-swirl / dust puff rather
    -- than the tree-split slide. Same call the engine's own Cut makes, and
    -- never over one already in flight -- that animation owns a callback
    -- and dropping it would strand whatever queued it.
    if not quiet and ow.startDustAnim and not ow.dustAnim then
      ow:startDustAnim(cx, cy)
    end
    return true
  end

  -- ------- cutting the grass on Gold
  --
  -- Gold's own CUT does not touch a tile at all. `FieldMoves.somethingToCut`
  -- (src/world/gen2/FieldMoves.lua:310) looks up the block the player is
  -- FACING in `FieldMoves.CUT_BLOCKS` (:262), a per-tileset { before block ->
  -- after block, animation } table transcribed from
  -- data/collision/field_move_blocks.asm, and `World:runCut` (World.lua:5271)
  -- swaps the WHOLE 32x32 block for the "after" one once the text box
  -- closes. That is the same "four tiles for one footstep" problem BURN
  -- GRASS exists to fix on Gen 1 -- so the same one-clod trick applies, on
  -- different raw material.
  --
  -- `CUT_BLOCKS` never names a tile id, only two BLOCK ids and an animation
  -- byte -- 1 for the grass swirl, 0 for the falling tree (World.lua:260-261)
  -- -- so there is no single GRASS_TILE constant to key off the way Red's
  -- OVERWORLD tileset allows. Instead, every GRASS row (animation 1) in a
  -- tileset's table has its "before" and "after" 16-tile blocks diffed
  -- against each other, and every position that changed becomes one entry
  -- in a SOURCE TILE -> DEST TILE table -- Gen 1's single substitution,
  -- generalised to however many distinct grass tiles Gold's edge and corner
  -- art actually uses.
  --
  -- One thing Gen 1's version never had to worry about: Gold's walkability
  -- is not a tile-id set, it is `Map:cellCollision` (src/world/gen2/Map.lua
  -- :55), ONE COLL_* byte per CELL taken from `tileset.collision[blockId+1]`
  -- -- a table built in lockstep with `tileset.blocks` off the same
  -- METATILE_COUNT loop (src/import/RomExtractorGen2.lua:803-820), so a
  -- synthesized block needs a synthesized collision QUAD at the same new id
  -- or the cut cell reads back as impassable rather than as plain ground.
  -- The byte for it is not a guess: it is the matching CUT_BLOCKS row's
  -- "after" block's own quad, at the SAME quadrant -- the actual cart answer
  -- for what a real cut of that quadrant collides as.
  local gen2Subst = {}   -- tileset def (by identity) -> { [srcTile] = dstTile }
  local gen2Synth = {}   -- tileset def (by identity) -> "block:qx,qy" -> new block id

  -- Every grass row's before/after pair, diffed and voted the same way Gen
  -- 1's cutTile above votes -- the most common destination wins when two
  -- rows disagree about what a shared tile id becomes.
  local function gen2GrassSubst(tilesetId, tilesetDef)
    local cached = gen2Subst[tilesetDef]
    if cached then return cached end
    local FieldMoves = require("src.world.gen2.FieldMoves")
    local rows = FieldMoves.CUT_BLOCKS[tilesetId]
    local votes, subst = {}, {}
    if rows and tilesetDef.blocks then
      for beforeId, row in pairs(rows) do
        local afterId, animation = row[1], row[2]
        if animation == 1 then      -- the grass swirl, not the tree-fall
          local src, dst = tilesetDef.blocks[beforeId + 1], tilesetDef.blocks[afterId + 1]
          if type(src) == "table" and type(dst) == "table" then
            for i = 1, 16 do
              if src[i] ~= dst[i] then
                votes[src[i]] = votes[src[i]] or {}
                votes[src[i]][dst[i]] = (votes[src[i]][dst[i]] or 0) + 1
              end
            end
          end
        end
      end
      for srcTile, dsts in pairs(votes) do
        local best, bestN = nil, 0
        for dstTile, n in pairs(dsts) do
          if n > bestN then best, bestN = dstTile, n end
        end
        subst[srcTile] = best
      end
    end
    gen2Subst[tilesetDef] = subst
    return subst
  end

  -- Whichever grass row's "after" block the collision byte for a cut
  -- quadrant should come from: the block actually being cut when CUT_BLOCKS
  -- has a row for it, or any grass row otherwise -- a tileset's tall grass
  -- collides the same way (COLL_TALL_GRASS or COLL_LONG_GRASS) wherever it
  -- stands, so any row's answer is the right one for a block CUT_BLOCKS was
  -- never told about.
  local function gen2AfterIdFor(rows, blockId)
    local row = rows[blockId]
    if row and row[2] == 1 then return row[1] end
    for _, r in pairs(rows) do
      if r[2] == 1 then return r[1] end
    end
    return nil
  end

  -- Gen 1's cutBlock, generalised: a per-tile substitution instead of one
  -- constant, and a collision quad appended alongside the tile block so the
  -- two arrays -- which Map:cellCollision indexes by the SAME block id --
  -- stay parallel. Returns nil when this cell's quadrant had no
  -- substitutable tile in it, same as Gen 1's "cut what?".
  local function gen2CutBlock(tilesetDef, blockId, qx, qy, subst, afterId)
    gen2Synth[tilesetDef] = gen2Synth[tilesetDef] or {}
    local cache = gen2Synth[tilesetDef]
    local key = blockId .. ":" .. qx .. "," .. qy
    local cached = cache[key]
    if cached then return cached end

    local srcTiles = tilesetDef.blocks[blockId + 1]
    if type(srcTiles) ~= "table" then return nil end
    local outTiles, changed = {}, false
    for i = 1, 16 do outTiles[i] = srcTiles[i] end
    for j = 0, 1 do
      for i = 0, 1 do
        local idx = (qy + j) * 4 + (qx + i) + 1
        local dst = subst[outTiles[idx]]
        if dst and dst ~= outTiles[idx] then
          outTiles[idx] = dst
          changed = true
        end
      end
    end
    if not changed then return nil end

    -- qx/qy are TILE offsets (0 or 2, the 4x4 tile grid); the collision
    -- quad is CELL-indexed (the 2x2 cell grid Map:cellCollision reads), so
    -- halved back down to the 0/1 local position Map.lua:61-62 itself uses.
    local srcQuad = tilesetDef.collision[blockId + 1]
    local afterQuad = tilesetDef.collision[afterId + 1]
    local outQuad = { srcQuad[1], srcQuad[2], srcQuad[3], srcQuad[4] }
    local localIdx = (qy / 2) * 2 + (qx / 2) + 1
    if afterQuad and afterQuad[localIdx] then outQuad[localIdx] = afterQuad[localIdx] end

    tilesetDef.blocks[#tilesetDef.blocks + 1] = outTiles
    tilesetDef.collision[#tilesetDef.collision + 1] = outQuad
    local id = #tilesetDef.blocks - 1
    cache[key] = id
    return id
  end

  local function cutGrassAtGen2(cx, cy, map)
    if not (map.isGrassCell and map:isGrassCell(cx, cy)) then return false end
    local tilesetId = map.def and map.def.tileset
    local tilesetDef = map.tileset
    if not (tilesetId and tilesetDef and tilesetDef.blocks and tilesetDef.collision) then
      return false
    end
    local FieldMoves = require("src.world.gen2.FieldMoves")
    local rows = FieldMoves.CUT_BLOCKS[tilesetId]
    if not rows then return false end

    local subst = gen2GrassSubst(tilesetId, tilesetDef)
    if not next(subst) then return false end

    local bx, by = math.floor(cx / 2), math.floor(cy / 2)
    local blockId = map:blockAt(bx, by)
    local afterId = gen2AfterIdFor(rows, blockId)
    if not afterId then return false end

    local qx, qy = (cx % 2) * 2, (cy % 2) * 2
    local id = gen2CutBlock(tilesetDef, blockId, qx, qy, subst, afterId)
    if not id then return false end

    local ok = mod.world and mod.world:replaceBlock(bx, by, id)
    if not ok then return false end
    -- No dust puff here: `World:runCut` plays one through its own script
    -- callback, not through anything a live map edit can reach mid-step, and
    -- there is no Gen 2 `startDustAnim` to borrow the way Gen 1's arm does.
    -- The mod's own coloured particles do not depend on it (see "the puff is
    -- not a grass thing" further down) and keep drawing regardless.
    return true
  end

  -- ------- cutting the grass on Gen 3
  --
  -- The easy one: a Gen 3 metatile is one 16px cell, so there is no clod to
  -- assemble. The cart's own CUT tables say what each grass metatile becomes
  -- (`cutGrassMetatile` on Hoenn, `CUT_GRASS_METATILES` on Kanto), and
  -- Field.setMetatile is the write CUT makes. `Map.load` clears those overrides
  -- (fieldmap.c:103), so the grass grows back when you leave, as it does on CUT.
  local function cutGrassAtGen3(cx, cy)
    local Collision = require("src.core.game3.collision")
    if not Collision.isGrass(cx, cy) then return false end
    local def = require("src.core.game3.map").currentDef()
    local layout = def and def.midLayout
    if not layout then return false end
    local FieldMoves = require("src.core.game3.field_moves")
    local mid = layout:midAt(cx, cy)
    local to
    if FieldMoves.isRse() then
      to = FieldMoves.cutGrassMetatile(mid)
    else
      to = FieldMoves.CUT_GRASS_METATILES[mid]
    end
    if not to then return false end
    require("src.core.game3.field").setMetatile(cx, cy, to, false)
    return true
  end

  local function cutGrassAt(game, cx, cy, quiet)
    if GEN3 then
      local ok, cut = pcall(cutGrassAtGen3, cx, cy)
      return ok and cut
    end
    if isGen2Game(game) then
      local world = game and game.world
      local map = world and world.map
      if not (map and map.def and map.tileset) then return false end
      return cutGrassAtGen2(cx, cy, map)
    end
    return cutGrassAtGen1(game, cx, cy, quiet)
  end

  -- ------- the particles

  local particles = {}
  local ribbon = {}
  local spawnClock = 0

  local function clearTrail()
    for i = #particles, 1, -1 do particles[i] = nil end
    for i = #ribbon, 1, -1 do ribbon[i] = nil end
  end

  -- ------- THE RAINBOW IS A RIBBON, NOT A CLOUD
  --
  -- It was particles at first, and particles are wrong for this: scattered
  -- discs with jitter and spread read as a handful of coloured specks
  -- trailing off, not as a rainbow. ("Sembrano scorregge" was the report,
  -- and it was fair.)
  --
  -- A Nyan Cat rainbow is a SOLID BAND: parallel stripes of flat colour
  -- laid along the path, continuous from the runner back to the tail. So
  -- this records the PATH -- one point per tick while running, with the
  -- direction it was travelling -- and paints stripes across it. No
  -- jitter, no spread, no drift: a ribbon does not billow.
  --
  -- It retracts on its own for the same reason the old trail did: every
  -- point dies `lifeSpan()` ticks after it was laid, and that span comes
  -- from the run's own frames-per-cell. Stop running and the far end goes
  -- out first, up the path, at the speed you were going.
  -- A FLAG, not a pinstripe. Four pixels a stripe puts the band at 24 --
  -- half again as wide as a cell -- which is what "enorme" asks for and
  -- what makes six colours legible at Game Boy scale in the first place.
  -- Three a stripe makes the band 18 tall, the height of the sprite it comes out
  -- of, so it reads as his wake rather than as a flag he is carrying.
  local RIBBON_STRIPE = 3                    -- pixels per colour band
  -- The far end narrows over this many points, in eight steps, like a comet's tail.
  local RIBBON_TAPER = 96

  -- And it runs the whole route rather than three cells of it. The
  -- particle trail is short on purpose -- a puff of dust that outlived the
  -- step that made it would read as smoke sitting in a field -- but a
  -- rainbow is the opposite: the point of it is the LINE you drew, all of
  -- it, from where you started to where you are.
  --
  -- The ceiling is on POINTS rather than on cells, so the band is as long
  -- as the run and stops growing before it can cost a frame. At one point
  -- a tick, six hundred is around a hundred and fifty cells of running.
  --
  -- And it does not age while you are RUNNING. A fixed lifetime would cap
  -- the band at however many ticks that was, which is the three-cell puff
  -- again wearing colours. So a point laid while running simply stays, and
  -- the moment the running stops the band RETRACTS from its far end -- one
  -- point a tick, the rate it was laid at, so it rolls back up the path at
  -- exactly the speed you ran it out. That is "follows you the whole way,
  -- then disappears along the trail" written as a rule rather than as a
  -- number.
  local RIBBON_MAX = 600
  local RIBBON_RETRACT = 3        -- fewest points dropped per tick once you stop
  local RIBBON_ABSORB_TICKS = 60  -- a band of any length is home in about this long
  -- A step ends and the next begins with a tick between them where nobody is
  -- moving. That is not stopping, so the band waits this long before coming in.
  local RIBBON_GRACE = 3
  local ribbonLaidAt = -100

  local ribbonHot = false

  local function layRibbon(player)
    if not (player and player.px and player.py) then return end
    local d = DIRV[player.facing] or DIRV.down
    -- ------- CENTRED ON THE CHARACTER, NOT NEAR HIM
    --
    -- Two things were pulling it off him. It was laid a few pixels BEHIND
    -- along the way he was going, which on a band this wide is a visible
    -- step where the ribbon meets him rather than a clean exit -- and a
    -- Nyan trail comes out of the middle, not off the back edge.
    --
    -- And the vertical was simply wrong. `py` is the top of the CELL, but
    -- SpriteRenderer draws the 16x16 frame at (px, py - 4), so the
    -- character occupies py-4 .. py+12 and his middle is py + 4. Using
    -- py + 8 -- the cell's own centre -- put the band four pixels low,
    -- which at 24 wide reads as the rainbow sagging past his feet.
    ribbon[#ribbon + 1] = {
      x = player.px + SPRITE_W / 2,
      -- Gen 3's sprite stands 16x32 on its cell, so its middle is lower down.
      y = player.py + (GEN3 and 0 or (SPRITE_TOP + SPRITE_BOT) / 2),
      dx = d[1], dy = d[2],
    }
    -- the same ceiling the particles keep: a decoration may not run the
    -- frame budget up on a long run
    while #ribbon > RIBBON_MAX do table.remove(ribbon, 1) end
  end

  -- How long a particle has to live for the trail to reach TRAIL_CELLS
  -- back. A step covers one cell in `frames` ticks, so a particle standing
  -- still in the world is that many ticks behind per cell.
  local function lifeSpan()
    local frames = freeFrames or ourFrames or 8
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
    -- over the width of the cell instead of stacking on one line -- and
    -- biased to alternating sides, because what is shedding this is a pair
    -- of feet rather than a hosepipe.
    local ax, ay = -d[2], d[1]
    local foot = (spawnClock % 2 == 0) and 1 or -1
    local spread = foot * (2 + rnd() * 3.5) + (rnd() * 2 - 1)
    -- ...but half of it when the spread lands on the VERTICAL axis.
    --
    -- Running left or right, "across the direction of travel" is up and
    -- down, and the two are not interchangeable. Sideways, six pixels of
    -- scatter is a band the width of the cell and reads as a pair of feet.
    -- Vertically it is most of the character's height: the same six pixels
    -- put marks at his knees and a hand's width below his shoes, so the
    -- trail stopped reading as coming off the heels and started reading as
    -- floating beside him -- which is why running rightwards was the one
    -- reported and running up and down was not.
    --
    -- The spawn itself is symmetric to the pixel either way (six clear of
    -- the sprite box on whichever side the trail is shed), so this is the
    -- part that was actually uneven.
    if d[1] ~= 0 then spread = spread * 0.5 end
    local life = lifeSpan()
    particles[#particles + 1] = {
      kind = kind,
      -- `px`,`py` is the top-left of the 16x16 cell, so +8/+12 is about
      -- where the feet are -- and then BEHIND back along the way he is
      -- going, which is what keeps the mark out of his own sprite box
      -- ON the feet, not behind them: every trail is now drawn under the sprite,
      -- so there is nothing to keep clear of and no gap for it to open up. It
      -- comes out of the runner the way a meteor's tail comes out of the meteor.
      x = player.px + 8 + ax * spread * 0.4,
      y = player.py + (GEN3 and 13 or 8) + ay * spread * 0.4,
      -- Barely any drift: a trail is something LEFT BEHIND, so it stays
      -- where it was shed and the player runs away from it. Give it a push
      -- backwards as well and the far end races the player, which is what
      -- kept the old trail hugging his heels instead of stretching out.
      vx = (rnd() * 0.16 - 0.08),
      vy = -(kind == "fire" and 0.22 or 0.10) + (rnd() * 0.10 - 0.05),
      life = life, max = life,
      -- the hue belongs to the MARK: one step per pair of feet, so the
      -- band walks the spectrum along the path rather than flickering
      hue = math.floor(spawnClock / 2),
      -- one number per particle, standing in for every per-particle random
      -- the draw wants: which way its smoke leans, which way its bolt jags
      seed = math.floor(rnd() * 64),
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

    -- The ribbon does not age; it RETRACTS. While a point was laid this
    -- tick the band is whole, and the moment it was not the far end starts
    -- rolling back -- oldest first, which is the end furthest from you.
    --
    -- It comes back in at a pace set by how long it is, so that a whole route
    -- is reabsorbed in about a second rather than crawling home for four.
    if not ribbonHot then
      local drop = math.max(RIBBON_RETRACT, math.ceil(#ribbon / RIBBON_ABSORB_TICKS))
      if drop >= #ribbon then
        for k = #ribbon, 1, -1 do ribbon[k] = nil end
      else
        local kept = 0
        for k = drop + 1, #ribbon do
          kept = kept + 1
          ribbon[kept] = ribbon[k]
        end
        for k = #ribbon, kept + 1, -1 do ribbon[k] = nil end
      end
    end
    ribbonHot = false
  end

  -- ------- drawing
  --
  -- Everything below is guarded so a headless run (no love, no graphics)
  -- and a frame with nothing to show both cost a single comparison.

  -- Where on the ramp this particle is drawing from. Fresh sits at the top
  -- (core white-hot, rim mid), old sits at the bottom (core mid, rim
  -- nearly gone) -- so age is a slide down one table rather than a second
  -- set of colours.
  -- ------- THE RAINBOW
  --
  -- The other three effects are a fixed five-colour ramp read by AGE, so
  -- every mark is the same colour at the same point in its life. A rainbow
  -- is the opposite: the colour belongs to the MARK, not to its age, so
  -- consecutive marks step through the spectrum and the band that comes
  -- out is a rainbow lying along the path you ran.
  --
  -- Nothing else has to change for it to behave. The trail already lives
  -- in world space and each mark already dies `lifeSpan()` ticks after it
  -- was shed -- a span computed from the run's own frames-per-cell -- so
  -- when you stop, the far end goes out first and the colour retreats up
  -- the path at exactly the speed you were running. That was in the
  -- machinery before this had a colour.
  --
  -- Six hues rather than a continuous sweep, and three flat shades each:
  -- a smooth gradient reads as somebody else's engine, and this has to sit
  -- next to a Game Boy.
  -- Six saturated bands, each edged with one discrete light and shade.
  local RAINBOW_BAND = {
    { 1.00, 0.22, 0.22 }, { 1.00, 0.60, 0.12 }, { 1.00, 0.92, 0.16 },
    { 0.24, 0.78, 0.28 }, { 0.20, 0.50, 0.98 }, { 0.62, 0.30, 0.92 },
  }

  local RAINBOW = {
    { { 1.00, 0.42, 0.42 }, { 0.88, 0.20, 0.20 }, { 0.55, 0.08, 0.08 } },
    { { 1.00, 0.72, 0.36 }, { 0.94, 0.54, 0.12 }, { 0.60, 0.30, 0.04 } },
    { { 1.00, 0.96, 0.50 }, { 0.94, 0.86, 0.20 }, { 0.58, 0.50, 0.06 } },
    { { 0.56, 0.92, 0.52 }, { 0.28, 0.74, 0.30 }, { 0.10, 0.44, 0.14 } },
    { { 0.52, 0.76, 1.00 }, { 0.22, 0.50, 0.92 }, { 0.06, 0.26, 0.58 } },
    { { 0.80, 0.60, 1.00 }, { 0.60, 0.34, 0.90 }, { 0.32, 0.14, 0.56 } },
  }

  local function window(kind, p)
    if kind == "rainbow" then
      local band = RAINBOW[((p.hue or 0) % #RAINBOW) + 1]
      return band[1], band[2], band[3]
    end
    local ramp = RAMP[kind] or RAMP.dust
    local i = math.floor((1 - p.life / p.max) * 2.999)   -- 0, 1 or 2
    return ramp[i + 1], ramp[i + 2], ramp[i + 3]
  end

  -- One shape for all three: big at the heel, tapering to a point at the
  -- tail. A trail should read as a trail -- you should be able to tell
  -- which end the player is at from the shape alone, without watching it
  -- move. An earlier pass had smoke EXPAND as it thinned, which is what
  -- real smoke does and which read as a smear rather than as a trail.
  local BIG = { dust = 6, fire = 7, bolt = 3, rainbow = 6 }

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
  --
  -- Gold has no such marker to read, because Gold's overworld is not a stack
  -- state at all -- `WorldAPI:overworld()` (src/world/gen2/WorldAPI.lua:39)
  -- reads `game.world` directly, and `game.stack` only ever holds what is
  -- PUSHED OVER it (a text box, a menu, a battle). So on a plain walk, with
  -- nothing pushed, `states` is an empty table -- not nil, so the Gen 1
  -- fallback above never fires -- and `states[#states]` is nil, which the
  -- Gen 1 test below reads as "not the overworld" on every single frame
  -- nothing is open. That hid the trail (and would have hidden the cut's
  -- puff, had Gen 2 had one) on ordinary walking, which is a stronger gate
  -- than Gen 1 ever had to clear.
  --
  -- `Game2:drawScene` already answers the question this needs, once a frame,
  -- for its OWN letterbox payload: `frameWorldActive` is true exactly when
  -- `World:draw()` painted the background this frame, and false the moment a
  -- battle or a full-screen page takes the window instead (src/core/Game2
  -- .lua:1454 the reset, :1578 the plain-overworld arm that sets it, :1301
  -- where render.letterbox's own `worldActive` field is the same read).
  -- `drawScene` always runs before `drawHud` in `Game2:draw` (:1372-1373 and
  -- :1383), so the flag this frame's `render.hud` call sees is never stale.
  local function topIsOverworld(game)
    if isGen2Game(game) then
      return game.frameWorldActive and true or false
    end
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

  local g1DrawBandFn, g1CamFn

  local function overlay(game, vp)
    if not (love and love.graphics and love.graphics.rectangle) then return end
    if type(vp) ~= "table" or not (vp.width and vp.height) then
      return once("viewport", "RUN FX: no viewport to draw into")
    end
    local player = anchor
    if not (player and player.px and player.py) then
      return once("anchor", "RUN FX: waiting for the first step to take an anchor")
    end

    if GENERATION ~= 1 then return end
    -- the ribbon counts too: with RAINBOW there are no particles at all,
    -- and standing down on an empty particle list drew nothing
    if #particles == 0 and #ribbon == 0 then return end
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

    -- ------- AFTER the state is made safe, not before
    --
    -- This block used to sit directly under the push, which is BEFORE the
    -- three lines above -- and on Gen 1 that meant drawing while the
    -- engine's palette shader was still bound, so every stripe was remapped
    -- to whatever four shades it pleased and the ribbon was simply not
    -- there. Gold binds no such shader, which is why it worked there and
    -- only there. An effect that is invisible on one generation and fine on
    -- the other is almost always this.
    if g1DrawBandFn and g1CamFn then
      local cam = g1CamFn()
      if cam then
        g1DrawBandFn(math.floor(ox + (cam[1] - player.px) * sx + 0.5),
          math.floor(oy + (cam[2] - player.py) * sy + 0.5), sx, sy)
      end
    end

    love.graphics.pop()
  end

  -- ------- the trail and the shoes on Gen 3
  --
  -- Every sprite here is art at GBA resolution, one texel to one pixel of the
  -- 240x160 frame, drawn at the frame's own scale from a whole-pixel position.
  -- So it sits on the same grid as the game instead of over it. The camera is
  -- `FieldView.draw`: camX = floor(px + 8 - 120) plus any scripted pan, no clamp.
  local G3_CELL = { dust = 16, fire = 16, bolt = 16, sparkle = 11 }
  local G3_FILE = { dust = "dust", fire = "flame", bolt = "bolt", sparkle = "sparkle" }
  local SHOE_MODEL = { sneaker = true, boot = true, winged = true, skate = true,
    sandal = true, clown = true, rocket = true }
  local SHOE_TINT = {
    red = { 1, 0.28, 0.25 }, orange = { 1, 0.58, 0.18 }, yellow = { 1, 0.9, 0.25 },
    green = { 0.35, 0.9, 0.4 }, blue = { 0.35, 0.55, 1 }, purple = { 0.72, 0.42, 1 },
    pink = { 1, 0.55, 0.8 }, white = { 1, 1, 1 }, black = { 0.42, 0.42, 0.48 },
  }
  -- `package.loaded` in a mod's sandbox is not the engine's, so this goes through
  -- require: nil rather than a throw, called only once the field is up.
  local function engine(name)
    local ok, m = pcall(require, name)
    return ok and m or nil
  end

  local g3Images, g3Quads = {}, {}
  local function g3Image(name)
    if g3Images[name] == nil then
      local ok, img = pcall(function() return mod.assets:image("assets/gen3/" .. name .. ".png") end)
      g3Images[name] = ok and img or false
      if ok then
        img:setFilter("nearest", "nearest")
        if name == "rainbow" then img:setWrap("repeat", "clamp") end
      else
        once("art" .. name, "RUN FX: cannot load %s: %s", name, tostring(img))
      end
    end
    return g3Images[name] or nil
  end

  local function g3Quad(img, x, y, w, h)
    local key = tostring(img) .. ":" .. x .. "," .. y .. "," .. w .. "," .. h
    local q = g3Quads[key]
    if not q then
      q = love.graphics.newQuad(x, y, w, h, img:getDimensions())
      g3Quads[key] = q
    end
    return q
  end

  local function g3Option(key, fallback)
    local ok, value = pcall(function() return mod.options:get(key) end)
    return ok and value or fallback
  end

  -- The frame for this moment of a mark's life: dust plays through once and
  -- fades, a flame flickers and then dies on its last frame, a bolt jumps.
  local function g3Frame(p)
    local age = 1 - p.life / p.max
    if p.kind == "dust" then
      local seq = { 2, 1, 0, 3 }
      return seq[math.min(4, math.floor(age * 4) + 1)]
    end
    if age > 0.75 then return 3 end
    return (math.floor((p.max - p.life) / 3) + p.seed) % 3
  end

  -- ------- the shoes
  --
  -- A shoe is not drawn near the feet, it is drawn ON them: each sheet holds, for
  -- every frame of the player's own 18-frame strip, the shoes for exactly that
  -- pose. So the frame has to be the one the engine just chose, and the moment
  -- has to be right after it drew the player, inside the world pass: tall grass,
  -- bridges and whatever else is drawn afterwards then cover the shoes as they
  -- cover the feet. No hook offers that, hence the wrap on OwSprites.draw, the
  -- third rung. If that module changes, the shoes go missing and nothing else.
  -- Other sheets (surf, bike) are different gids, so they never get any.
  local function drawWornShoes(Ow, gid, px, py, camX, camY, facing, walkPhase, stepFlip, opts)
    local model = g3Option("shoe_model", "off")
    if not (SHOES_HERE and SHOE_MODEL[model]) then return end
    local avatars = Ow.avatars()
    local who
    if gid == Ow.avatarGraphicsId("NORMAL", false, avatars) then who = "male"
    elseif gid == Ow.avatarGraphicsId("NORMAL", true, avatars) then who = "female" end
    if not who then return end
    local spr = Ow.getDraw(gid)
    local img = spr and g3Image("shoes_" .. who .. "_" .. model)
    if not (img and spr.frameCount == 18) then return end
    local frame, flip = Ow.pose(spr, facing, walkPhase, stepFlip, opts)
    if frame > 17 then return end
    local tint = SHOE_TINT[g3Option("shoe_color", "red")] or SHOE_TINT.white
    love.graphics.setColor(tint[1], tint[2], tint[3], opts and opts.alpha or 1)
    local x = px - camX + (16 - spr.width) / 2
    local y = py - camY + 16 - spr.height + (spr.drawOffY or 0)
    local quad = g3Quad(img, 0, frame * 32, 16, 32)
    if flip then
      love.graphics.draw(img, quad, x + spr.width, y, 0, -1, 1)
    else
      love.graphics.draw(img, quad, x, y)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- ------- the rainbow, under the character
  --
  -- A hud overlay composites over the finished frame, so it can only ever
  -- pretend to be behind anybody: it used to skip whatever stripes his box
  -- covered, which left a notch around him and a band that ran over NPCs. Being
  -- in the background means being drawn BEFORE the sprites, in the world pass,
  -- and no hook stands there. Each generation has one call that does, and each
  -- gets one wrap (third rung, declared): the first sprite of a frame on Gen 1,
  -- `World:drawPeople` on Gold, the player's own sheet on Gen 3. If a wrap's
  -- target changes, the rainbow goes missing and nothing else does.
  local ribbonDrawnAt = -1

  local function ribbonWidth(i)
    -- Measured so the head is always full width: a short run tapers over all of
    -- itself, a long one only over its last stretch.
    local over = math.min(RIBBON_TAPER, math.max(1, #ribbon))
    return math.max(0.125, math.ceil(math.min(1, i / over) * 8) / 8)
  end

  -- Game Boy rules on Gen 1 and Gold: flat colour, whole pixels, no fades and no
  -- glints. Anything finer reads as a different console on top of the map, and
  -- the tail narrows by whole pixels per stripe rather than by a smooth taper.
  local function drawRibbonStripes(camX, camY, s)
    local frames = freeFrames or ourFrames or 8
    local seg = 16 / frames + 2
    local function put(x, y, w, h)
      love.graphics.rectangle("fill",
        math.floor(x - camX) * s, math.floor(y - camY) * s,
        math.max(1, math.ceil(w)) * s, math.max(1, math.ceil(h)) * s)
    end
    for i = 1, #ribbon do
      local r = ribbon[i]
      local stripe = math.max(1, math.ceil(RIBBON_STRIPE * ribbonWidth(i)))
      local band = #RAINBOW_BAND * stripe
      for k = 1, #RAINBOW_BAND do
        local c = RAINBOW_BAND[k]
        local off = -band / 2 + (k - 1) * stripe
        love.graphics.setColor(c[1], c[2], c[3], 1)
        if r.dx ~= 0 then
          put(r.x - seg / 2, r.y + off, seg, stripe)
        else
          put(r.x + off, r.y - seg / 2, stripe, seg)
        end
      end
    end
  end

  -- Dust, flames and bolts on Gen 1 and Gold: two flat shades, no transparency.
  local function drawMarks(camX, camY, s)
    for i = 1, #particles do
      local p = particles[i]
      local _, body, rim = window(p.kind, p)
      local size = sizeOf(p.kind, p)
      local phase = 1 + ((math.floor((p.max - p.life) / 3) + p.seed) % 3)
      if p.kind ~= "bolt" or p.life % 2 == 1 then
        local artSize = p.kind == "fire" and math.min(8, size + 1) or size
        local frame = FRAMES[p.kind][artSize][phase]
        local left = math.floor(p.x - frame.width / 2)
        local top = math.floor(p.kind == "bolt" and p.y - frame.height + 1 or p.y - frame.height / 2)
        local previous
        for _, run in ipairs(frame.runs) do
          local ink = run.ink == 1 and 1 or 2
          if ink ~= previous then
            local shade = ink == 1 and rim or body
            love.graphics.setColor(shade[1], shade[2], shade[3], 1)
            previous = ink
          end
          love.graphics.rectangle("fill", (left + run.x - math.floor(camX)) * s,
            (top + run.y - math.floor(camY)) * s, run.w * s, s)
        end
      end
    end
  end

  local function drawTrailGen3(camX, camY)
    local img = #ribbon > 0 and g3Image("rainbow")
    if img then
      local step = 16 / (freeFrames or ourFrames or 8)
      local seg = math.ceil(step) + 1
      for i = 1, #ribbon do
        local r = ribbon[i]
        local along = math.floor(r.dx ~= 0 and r.x or r.y)
        local quad = g3Quad(img, along % 16, 0, seg, 24)
        local f = ribbonWidth(i)
        -- 36 pixels, taller than the character, stepping up and down every eight
        -- pixels of ground: the square wave is what makes it read as that rainbow.
        local tall = 1.5 * f
        local wave = math.floor(along / 8) % 2 == 0 and -1 or 1
        love.graphics.setColor(1, 1, 1, math.min(i, 8) / 8)
        if r.dx ~= 0 then
          love.graphics.draw(img, quad, math.floor(r.x - seg / 2 - camX),
            math.floor(r.y - 12 * tall + wave - camY), 0, 1, tall)
        else
          love.graphics.draw(img, quad, math.floor(r.x + 12 * tall + wave - camX),
            math.floor(r.y - seg / 2 - camY), math.pi / 2, 1, tall)
        end
      end
      local star = g3Image("sparkle")
      if star then
        love.graphics.setColor(1, 1, 1, 1)
        for i = 1, #ribbon do
          local r = ribbon[i]
          local along = r.dx ~= 0 and r.x or r.y
          if along % 32 < step and ribbonWidth(i) == 1 then
            local seed = math.floor(along / 32) * 7
            local frame = (math.floor(ticks / 6) + seed) % 4
            local cross = ((seed % 3) - 1) * 10
            local x = (r.dx ~= 0 and r.x or r.x + cross) - 5
            local y = (r.dx ~= 0 and r.y + cross or r.y) - 5
            love.graphics.draw(star, g3Quad(star, frame % 2 * 11, math.floor(frame / 2) * 11, 11, 11),
              math.floor(x - camX), math.floor(y - camY))
          end
        end
      end
    end
    love.graphics.setColor(1, 1, 1, 1)
    for i = 1, #particles do
      local p = particles[i]
      local mark = g3Image(G3_FILE[p.kind] or "dust")
      if mark then
        local cell = G3_CELL[p.kind] or 16
        local half = math.floor(cell / 2)
        local frame = g3Frame(p)
        love.graphics.draw(mark, g3Quad(mark, frame % 2 * cell, math.floor(frame / 2) * cell, cell, cell),
          math.floor(p.x - half - camX), math.floor(p.y - half - camY))
      end
    end
  end

  -- Once a frame, under the sprites, with the draw state made safe and put back.
  local function drawRibbon(camX, camY, s)
    if (#ribbon == 0 and #particles == 0) or ribbonDrawnAt == hudCalls then return end
    ribbonDrawnAt = hudCalls
    love.graphics.push("all")
    local ok, err = pcall(function()
      if GEN3 then
        drawTrailGen3(camX, camY)
      else
        drawRibbonStripes(camX, camY, s or 1)
        drawMarks(camX, camY, s or 1)
      end
    end)
    love.graphics.pop()
    if not ok then once("ribbonerr", "RUN FX: rainbow: %s", tostring(err)) end
    once("ribbondraw", "RUN FX: rainbow drawing under the sprites")
  end

  local function attachGen3(Ow)
    if Ow.runningShoesWrap and Ow.draw == Ow.runningShoesWrap then Ow.draw = Ow.runningShoesInner end
    local inner = Ow.draw
    local wrap = function(gid, px, py, camX, camY, facing, walkPhase, stepFlip, opts)
      if (#ribbon > 0 or #particles > 0) and live and Ow.playerGraphicsId
         and gid == Ow.playerGraphicsId(live) then
        drawRibbon(camX, camY, 1)
      end
      local drew = inner(gid, px, py, camX, camY, facing, walkPhase, stepFlip, opts)
      if drew then
        local ok, err = pcall(drawWornShoes, Ow, gid, px, py, camX, camY, facing, walkPhase, stepFlip, opts)
        if not ok then once("shoeerr", "SHOE MODEL: %s", tostring(err)) end
      end
      return drew
    end
    Ow.draw = wrap
    Ow.runningShoesWrap, Ow.runningShoesInner = wrap, inner
  end

  -- ------- Gen 1 is the exception
  --
  -- Its zone pass recolours the whole world canvas to four shades after the
  -- sprites are down, so a band drawn there comes out grey, and the true-colour
  -- opt-out only exists in one palette mode and bares the map around it. So on
  -- Gen 1 the band is painted over the finished frame after all, in real colour,
  -- and each sprite's exact silhouette is erased from it first. To do that, every
  -- sprite blit of the frame is also copied to a mask canvas, by listening to
  -- love.graphics.draw for the length of one SpriteRenderer.draw call.
  local g1Mask, g1Band, g1Cam, g1MaskFrame
  local g1MaskShader, g1EraseShader

  local function g1MaskReady(w, h)
    if not (g1MaskShader and g1EraseShader) then
      g1MaskShader = love.graphics.newShader([[
        vec4 effect(vec4 c, Image t, vec2 uv, vec2 s) {
          if (Texel(t, uv).a < 0.5) discard;
          return vec4(1.0);
        }]])
      g1EraseShader = love.graphics.newShader([[
        vec4 effect(vec4 c, Image t, vec2 uv, vec2 s) {
          if (Texel(t, uv).a < 0.5) discard;
          return vec4(0.0);
        }]])
    end
    if not g1Mask or g1Mask:getWidth() ~= w or g1Mask:getHeight() ~= h then
      g1Mask = love.graphics.newCanvas(w, h, { dpiscale = 1 })
      g1Band = love.graphics.newCanvas(w, h, { dpiscale = 1 })
      g1Mask:setFilter("nearest", "nearest")
      g1Band:setFilter("nearest", "nearest")
    end
  end

  -- Over the finished frame: `place` is where the world canvas's origin lands.
  local function g1DrawBand(placeX, placeY, sx, sy)
    if not (g1Band and g1Cam and g1MaskFrame == hudCalls) then return end
    love.graphics.push("all")
    love.graphics.setCanvas(g1Band)
    love.graphics.origin()
    love.graphics.setScissor()
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setBlendMode("alpha")
    drawRibbonStripes(g1Cam[1], g1Cam[2], 1)
    drawMarks(g1Cam[1], g1Cam[2], 1)
    love.graphics.setBlendMode("replace", "premultiplied")
    love.graphics.setShader(g1EraseShader)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(g1Mask, 0, 0)
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(g1Band, placeX, placeY, 0, sx, sy)
  end

  local function attachGen1(Sprites)
    if Sprites.runningShoesWrap and Sprites.draw == Sprites.runningShoesWrap then
      Sprites.draw = Sprites.runningShoesInner
    end
    local inner = Sprites.draw
    local wrap = function(self, px, py, camX, camY, ...)
      if not ((#ribbon > 0 or #particles > 0) and live and topIsOverworld(live) and camX) then
        return inner(self, px, py, camX, camY, ...)
      end
      local target = love.graphics.getCanvas()
      if not target then return inner(self, px, py, camX, camY, ...) end
      g1MaskReady(target:getDimensions())
      if g1MaskFrame ~= hudCalls then
        g1MaskFrame = hudCalls
        g1Cam = { camX, camY }
        love.graphics.push("all")
        love.graphics.setCanvas(g1Mask)
        love.graphics.origin()
        love.graphics.setScissor()
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.pop()
      end
      local realDraw = love.graphics.draw
      local blits = {}
      love.graphics.draw = function(...)
        blits[#blits + 1] = { ... }
        return realDraw(...)
      end
      local a, b, c = inner(self, px, py, camX, camY, ...)
      love.graphics.draw = realDraw
      love.graphics.push("all")
      love.graphics.setCanvas(g1Mask)
      love.graphics.setShader(g1MaskShader)
      love.graphics.setBlendMode("replace", "premultiplied")
      love.graphics.setColor(1, 1, 1, 1)
      for _, call in ipairs(blits) do realDraw(unpack(call)) end
      love.graphics.pop()
      return a, b, c
    end
    Sprites.draw = wrap
    Sprites.runningShoesWrap, Sprites.runningShoesInner = wrap, inner
  end

  local function attachGen2(World)
    if World.runningShoesWrap and World.drawPeople == World.runningShoesWrap then
      World.drawPeople = World.runningShoesInner
    end
    local inner = World.drawPeople
    local wrap = function(self, s, billboard)
      if (#ribbon > 0 or #particles > 0) and not billboard and self.camera then
        drawRibbon(self.camera.x, self.camera.y, s)
      end
      return inner(self, s, billboard)
    end
    World.drawPeople = wrap
    World.runningShoesWrap, World.runningShoesInner = wrap, inner
  end

  g1DrawBandFn = g1DrawBand
  g1CamFn = function() return g1Cam end

  -- The one seam the headless suite reads the trail through.
  mod.exports.drawTrail = function(camX, camY, s)
    drawRibbonStripes(camX, camY, s)
    drawMarks(camX, camY, s)
  end

  local function attachWorldPass()
    if not (love and love.graphics) then return end
    if GEN3 then
      local Ow = engine("src.core.game3.ow_sprites")
      if Ow and Ow.draw and Ow.pose and Ow.getDraw and Ow.avatars and Ow.avatarGraphicsId then
        return attachGen3(Ow)
      end
    elseif GENERATION == 2 then
      local World = engine("src.world.gen2.World")
      if World and World.drawPeople then return attachGen2(World) end
    else
      local Sprites = engine("src.render.SpriteRenderer")
      if Sprites and Sprites.draw then return attachGen1(Sprites) end
    end
    once("noseam", "RUN FX: no world-pass seam on this engine build; no rainbow or shoes")
  end

  -- ------- running under a camera that took the walk away
  --
  -- The Dramatic Shape voxel mod's 1ST and 3RD rungs do not walk the grid.
  -- Its `lib/FreeMove.lua` wraps `OverworldState:handleInput` and, while a
  -- free camera drives, replaces the walk outright with a continuous
  -- camera-relative one: a point in world pixels advanced by `FreeMove.WALK`
  -- (1.0) or `FreeMove.BIKE` (2.0) pixels a frame, with the player's logical
  -- cell kept honest and `OverworldState:onStepComplete` fired once per cell
  -- crossed -- so warps, encounters and step counters all still happen.
  --
  -- What does NOT happen is `movement.speed`. There is no step duration to
  -- ask about, because there is no step: the hook this whole mod is built on
  -- is never called while that camera is up. And it is not only the speed
  -- that goes with it -- CUT GRASS, SAFE GRASS and the trail all read
  -- `running`, and `movement.speed` is the only thing that ever sets it. So
  -- every row of the mod went quiet the moment the camera came off the
  -- ceiling, silently and with nothing in the log. That is issue #1.
  --
  -- The fix has to be paid in the currency the free walk deals in, and it
  -- converts exactly: sixteen frames for a sixteen-pixel cell IS one pixel a
  -- frame, which is why `FreeMove.WALK` is 1.0 in the first place. Dividing
  -- a step duration by f and multiplying a walk speed by f are the same
  -- sentence, and the floor is the same floor -- `MIN_FRAMES` frames per
  -- cell is 16/`MIN_FRAMES` pixels a frame -- so the ladder, the bike and
  -- surf gates, and the point at which the animation stops reading as
  -- walking are all the numbers the grid arm already argues for above.
  --
  -- The seam into that mod is its own front door: it publishes its module
  -- namespace as `mod.exports.lib` so that "a companion mod can pin its own
  -- tiles' shapes or read the camera without reaching into this mod's file
  -- layout", and `mod.find` (src/mods/Loader.lua:1071) is the engine's way
  -- to reach it -- a handle or nil, never a hard dependency.
  --
  -- Wrapping `FreeMove.tick` is NOT a front door, and is declared as what it
  -- is: a monkeypatch, the third rung of the ladder. It is confined to one
  -- call -- set the two constants, run the original, put them back whatever
  -- happened -- so if that module is ever restructured the failure mode is
  -- that running stops working inside the voxel camera, which is precisely
  -- where it stands today. Nothing else in this file depends on it.
  --
  -- One thing genuinely does not come back, and is not faked: RUN FX. The
  -- trail is a screen-space overlay measured off `Camera:follow`, and
  -- `flatWorld` above already stands it down whenever a render pipeline owns
  -- the world pass -- which the voxel pipeline does, at every rung including
  -- the overhead ones. A 2D overlay cannot follow a depth-buffered camera,
  -- and drawing it anyway would put the trail somewhere the player is not.
  local FREE_CAM_MOD = "DRAMATIC_SHAPE"

  -- The table we wrapped and the wrapper we put on it. Held as a PAIR, and
  -- re-checked every tick rather than latched on a "done" flag, because
  -- either half can go stale on its own: reloading the other mod hands out a
  -- fresh FreeMove (or a fresh tick on the same table), and reloading THIS
  -- one rebuilds these two as nil while its old wrapper is still installed
  -- over there. Two table reads a tick buys correctness across both.
  local freeTable, freeWrap = nil, nil

  local function freeCamAttach()
    if freeTable and freeTable.tick == freeWrap then return true end
    if type(mod.find) ~= "function" then return false end
    local handle = mod.find(FREE_CAM_MOD)
    local lib = handle and handle.exports and handle.exports.lib
    if type(lib) ~= "table" or type(lib.require) ~= "function" then return false end

    local ok, FreeMove = pcall(lib.require, "FreeMove")
    if not (ok and type(FreeMove) == "table"
            and type(FreeMove.tick) == "function"
            and tonumber(FreeMove.WALK) and tonumber(FreeMove.BIKE)) then
      return false
    end

    -- Unwind our own previous wrap before putting a new one on: reloading
    -- this mod rebuilds the closure while that module keeps its table, and
    -- two of these stacked would multiply the speed twice. Only ever unwind
    -- a wrapper that is still the CURRENT tick and is one of ours -- if
    -- somebody else has wrapped since, theirs is the tick, and putting our
    -- old inner back would throw their work away.
    if FreeMove.runningShoesTick ~= nil
       and FreeMove.tick == FreeMove.runningShoesTick
       and FreeMove.runningShoesInner ~= nil then
      FreeMove.tick = FreeMove.runningShoesInner
    end
    local inner = FreeMove.tick

    local wrapper
    wrapper = function(state)
      local player = state and state.player
      local px, py = player and player.px, player and player.py
      if player then anchor = player end

      -- Read the two constants fresh rather than caching them at attach:
      -- they are that mod's numbers to change, and restoring a cached copy
      -- would quietly undo a change it made after we arrived.
      local baseWalk, baseBike = FreeMove.WALK, FreeMove.BIKE

      local input = live and live.input
      local onBike = live and live.save and live.save.onBike
      local held = input and input.isDown and input:isDown("b")
      local f = 1
      if held
         and not (onBike and not enabled("bike"))
         and not (player and player.surfing and not enabled("surf")) then
        f = factor()
      end

      if f > 1 then
        local cap = 16 / MIN_FRAMES      -- the floor, in pixels a frame
        local walk = math.min(baseWalk * f, cap)
        local bike = math.min(baseBike * f, cap)
        -- Never hand back something slower than we were given, the same
        -- promise the movement.speed arm makes to a mod that got there first.
        FreeMove.WALK = math.max(walk, baseWalk)
        FreeMove.BIKE = math.max(bike, baseBike)
        running = true
        -- Off the BOOSTED speed on purpose: this is how long a cell is
        -- about to take, which is the number the trail measures its length
        -- in cells against (see lifeSpan).
        freeFrames = math.floor(16 / (onBike and FreeMove.BIKE or FreeMove.WALK) + 0.5)
      else
        running = false
        freeFrames = nil
      end

      local okTick, err = pcall(inner, state)

      FreeMove.WALK, FreeMove.BIKE = baseWalk, baseBike

      -- There is no `player.moving` to read here: the free walk leaves that
      -- false and moves px/py itself. Whether it covered ground IS the
      -- comparison, and it is what the trail's spawn gate asks for.
      freeMoving = player ~= nil and (player.px ~= px or player.py ~= py)

      if not okTick then error(err, 0) end
    end

    FreeMove.tick = wrapper
    FreeMove.runningShoesTick, FreeMove.runningShoesInner = wrapper, inner
    freeTable, freeWrap = FreeMove, wrapper
    mod.log:info("free-roam camera found (%s %s); the shoes work inside it too",
      tostring(handle.id), tostring(handle.version))
    return true
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
  mod.events:on("map.exited", function()
    clearTrail()
    lastCell, pendingTrail = nil, nil
  end)

  -- ------- TRAIL STATUS
  --
  -- A wild Pokemon you run into starts the battle hit by what you were trailing:
  -- flames burn, bolts paralyse, the rainbow confuses. Dust raises a sandstorm on
  -- Gen 3; Gen 1 has no weather and on Gold it stays what Gen 1 does, dust in the
  -- eyes, one stage of accuracy. Every generation goes through its own battle's
  -- own calls, so an immune Pokemon is immune here too. The roll is untouched.
  -- battle.started fires before the battle is on screen on Gen 3, and a message
  -- there sits on a black frame. So the effect lands now and is told at turn one.
  local trailSay
  if GEN3 then
    mod.events:on("battle.turn_started", function()
      if not trailSay then return end
      local text = trailSay
      trailSay = nil
      pcall(function() require("src.core.game3.battle")._adapter:say(text) end)
    end)
  end

  local function trailGen3(kind, ev)
    local Battle = require("src.core.game3.battle")
    local ad, st = Battle._adapter, ev.battle or Battle.getState()
    local foe = st and st.enemy
    if not (ad and foe) then return end
    if kind == "dust" then
      ad:setWeather("SAND", 5)
      trailSay = "Your dust whipped up a sandstorm!"
    elseif kind == "fire" then
      if ad:applyStatus(foe, "BRN") then trailSay = "Your flames burned the wild foe!" end
    elseif kind == "bolt" then
      if ad:applyStatus(foe, "PAR") then trailSay = "Your sparks paralyzed the wild foe!" end
    elseif kind == "rainbow" then
      if ad:applyConfusion(foe) then trailSay = "Your rainbow confused the wild foe!" end
    end
  end

  local function trailGen2(kind, ev)
    local battle = ev.battle and ev.battle.battle or ev.battle
    local foe = battle and battle.enemy
    if not (foe and battle.applyStatus) then return false end
    if kind == "dust" then battle:changeStage(foe, "accuracy", -1)
    elseif kind == "fire" then battle:applyStatus(foe, "burn")
    elseif kind == "bolt" then battle:applyStatus(foe, "paralyze")
    elseif kind == "rainbow" then battle:applyConfusion(foe) end
    return true
  end

  local function trailGen1(kind, ev)
    local battle = ev.battle
    local foe = battle and battle.enemy
    if not (foe and foe.mon) then return end
    local function say(text) if battle.sayNext then battle:sayNext(text) end end
    if kind == "dust" then
      foe.stages = foe.stages or {}
      foe.stages.accuracy = math.max(-6, (foe.stages.accuracy or 0) - 1)
      say("Your dust got in\nthe foe's eyes!")
    elseif kind == "rainbow" then
      if not foe.confusedTurns then
        foe.confusedTurns = battle.rng and battle.rng(2, 5) or 3
        say("Your rainbow\nconfused the foe!")
      end
    elseif not foe.mon.status then
      local msgs = require("src.battle.StatusRegistry").inflict(battle, foe,
        kind == "fire" and "BRN" or "PAR", {})
      for _, text in ipairs(msgs or {}) do say(text) end
    end
  end

  mod.events:on("battle.started", function(ev)
    clearTrail()
    local kind = pendingTrail
    pendingTrail = nil
    if not (kind and type(ev) == "table" and ev.kind == "wild") then return end
    local ok, err = pcall(function()
      if GEN3 then trailGen3(kind, ev)
      elseif GENERATION == 2 then trailGen2(kind, ev)
      else trailGen1(kind, ev) end
    end)
    if not ok then mod.log:warn("TRAIL STATUS: %s", tostring(err)) end
  end)

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

    pendingTrail = nil
    if cutOn() and running then
      -- The cut lands before the encounter check, so a cut cell can never start a
      -- battle. With TRAIL STATUS on the meeting is the point: the grass goes when
      -- you step off it instead, and the path behind you is still bare.
      if enabled("trail_status") then
        if lastCell then cutGrassAt(game, lastCell.x, lastCell.y) end
      else
        cutGrassAt(game, ev.x, ev.y)
      end
    end
    lastCell = { x = ev.x, y = ev.y }

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
    -- `game.overworld` is a Gen 1 field with no Gen 2 counterpart -- Gold
    -- hangs its world off `game.world` instead (WorldAPI.lua:39) -- so `ow`
    -- is always nil here on Gold and every guard below answers false. That
    -- is deliberate, not a gap this file should paper over: see "what
    -- changes on Gold" near the top for why there is no puff to borrow
    -- there, and why the coloured particles below do not need one.
  end)

  -- Entering a map used to re-cut everything this mod had ever run
  -- through. It does not any more -- the map comes back whole, the way it
  -- does after CUT -- so all that is left here is throwing away what older
  -- versions wrote down.
  mod.events:on("map.entered", function()
    forgetLegacyBurnt()
  end)

  -- Every logic tick: the moment the player is not moving, the fast value
  -- has done its job and stops being true of anything. The trail is ticked
  -- on the same fixed clock as the step it belongs to, so it neither
  -- speeds up on a 144Hz display nor keeps moving while the game is paused
  -- behind a menu.
  -- ------- WHAT'S NEW
  --
  -- As in the box and dex mods: once per NEWS_VERSION per save, so after an update
  -- or on a first install, never again until a page changes. There it opens with
  -- the screen it belongs to; this mod has no screen, so it opens on the first run.
  -- Bump NEWS_VERSION when a page changes, not on every release.
  local NEWS_VERSION = "1.11.0"
  local NEWS_WIDE = {
    { title = "NOW ON GEN 3", lines = {
      "Running Shoes runs on this game now.",
      "Hold B: RUN SPEED counts from walking,",
      "so x2 is the cart's own run and x3 and",
      "x4 go past it. Before you have shoes,",
      "B runs anyway.",
      "",
      "Every option is in the mod's options.",
    } },
    { title = "TRAIL STATUS", lines = {
      "New in the mod's options, and off until",
      "you turn it on. Meet a wild Pokemon at a",
      "run and it starts hit by your trail:",
      "",
      "FLAMES burn   BOLTS paralyze",
      "RAINBOW confuses",
      "DUST whips up a sandstorm",
    } },
    { title = "A TAIL, NOT A CLOUD", lines = {
      "Every trail now comes out of you and",
      "runs under your sprite, like a meteor's.",
      "The rainbow is drawn back in when you",
      "stop running.",
      "",
      "BURN GRASS with TRAIL STATUS cuts the",
      "cell as you leave it, so you can still",
      "meet something on it.",
    } },
    { title = "SHOES", lines = {
      "On Emerald, playing as the boy:",
      "SHOE MODEL and SHOE COLOUR put seven",
      "pairs in nine colours on your own feet.",
      "They are off until you pick a pair.",
    } },
  }
  local NEWS_SMALL = {
    { title = "NEW GAMES", lines = {
      "Running Shoes now", "also runs on", "Gen 3: Ruby,", "Sapphire, Emerald,", "FireRed and", "LeafGreen.",
    } },
    { title = "TRAIL STATUS", lines = {
      "New option, off", "until you turn it", "on. Meet a wild",
      "Pokemon at a run", "and it starts hit", "by your trail:", "",
      "FLAMES burn", "BOLTS paralyze", "RAINBOW confuses", "DUST: accuracy",
    } },
    { title = "A TAIL", lines = {
      "Trails now come", "out of you and", "run under your", "sprite, like a",
      "meteor's. The", "rainbow is drawn", "back in when you", "stop.",
    } },
  }
  local NEWS = GEN3 and NEWS_WIDE or NEWS_SMALL
  local newsPage, newsCanvas
  local newsDeaf = 0
  local newsChecked = false

  local function newsSeen()
    local ok, seen = pcall(function() return mod.save:get("newsSeen") end)
    return ok and seen == NEWS_VERSION
  end

  local function closeNews()
    newsPage = nil
    pcall(function() mod.save:set("newsSeen", NEWS_VERSION) end)
  end

  -- The player stands still while it is open: its keys are read here and go no
  -- further, and a direction or B held when it opened has to be pressed again.
  local function newsInput(game)
    local input = game and game.input
    if not input then return end
    -- It opens under a player who is running, so B is already in play: half a
    -- second of deafness, or a mashed B would close a page nobody has seen.
    newsDeaf = newsDeaf - 1
    for _, btn in ipairs(newsDeaf > 0 and {} or input.pressQueue or {}) do
      if btn == "b" then closeNews()
      elseif btn == "a" or btn == "right" then
        if newsPage and newsPage >= #NEWS then closeNews()
        elseif newsPage then newsPage = newsPage + 1 end
      elseif btn == "left" and newsPage and newsPage > 1 then newsPage = newsPage - 1 end
    end
    for i = #(input.pressQueue or {}), 1, -1 do input.pressQueue[i] = nil end
    for _, btn in ipairs({ "a", "b", "start", "select", "up", "down", "left", "right" }) do
      if input.state then input.state[btn] = false end
      if input.pressed then input.pressed[btn] = nil end
    end
  end

  local function drawNews(vp)
    local page = newsPage and NEWS[newsPage]
    if not page or type(vp) ~= "table" then return end
    local W, H = GEN3 and 240 or 160, GEN3 and 160 or 144
    if not newsCanvas then
      newsCanvas = love.graphics.newCanvas(W, H, { dpiscale = 1 })
      newsCanvas:setFilter("nearest", "nearest")
    end
    love.graphics.push("all")
    love.graphics.setCanvas(newsCanvas)
    love.graphics.origin()
    love.graphics.setScissor()
    love.graphics.setShader()
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(1, 1, 1, 1)
    if GEN3 then
      local Window = require("src.ui.game3.window")
      Window.stdFrame(Window.template(2, 2, 26, 16))
      Window.printPx(string.format("WHAT'S NEW %s  %d/%d", NEWS_VERSION, newsPage, #NEWS), 24, 20, { small = true })
      Window.printPx(page.title, 24, 34)
      for i, line in ipairs(page.lines) do
        Window.printPx(line, 24, 36 + i * 12, { small = true })
      end
      Window.printPx(newsPage < #NEWS and "A: NEXT   B: CLOSE" or "A / B: CLOSE", 24, 130, { small = true })
    else
      local Font = require("src.render.Font")
      love.graphics.rectangle("fill", 0, 0, W, H)
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.rectangle("line", 2.5, 2.5, W - 5, H - 5)
      Font.draw(page.title, 8, 8)
      for i, line in ipairs(page.lines) do Font.draw(line, 8, 12 + i * 10) end
      Font.draw(newsPage < #NEWS and "A:NEXT  B:CLOSE" or "A/B:CLOSE", 8, H - 14)
    end
    love.graphics.pop()
    local vw, vh = tonumber(vp.width) or W, tonumber(vp.height) or H
    local k = vp.gameWidth and vp.gameWidth / W or math.max(1, math.floor(math.min(vw / W, vh / H)))
    local x = vp.gameX or math.floor((vw - W * k) / 2)
    local y = vp.gameY or math.floor((vh - H * k) / 2)
    love.graphics.push("all")
    love.graphics.setShader()
    love.graphics.setScissor()
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(newsCanvas, x, y, 0, k, k)
    love.graphics.pop()
  end

  local worldAttached = false
  mod.hooks:wrap("input.step", function(next, game, dt)
    if newsPage then newsInput(game) end
    local out = next(game, dt)
    live = game
    if not newsChecked and running and anchor and (anchor.moving or freeMoving) then
      newsChecked = true
      if not newsSeen() then newsPage, newsDeaf = 1, 30 end
    end
    if not worldAttached and (not GEN3 or game.phase == "field") then
      worldAttached = true
      attachWorldPass()
    end
    if tracked and not tracked.moving then restore() end

    -- Attached from here rather than at load, because load order is not
    -- ours to pick: `mod.find` answers nil until the other mod has run, and
    -- a mod the player enables mid-session has not run at load at all. A
    -- miss is one table lookup and a nil test.
    freeCamAttach()

    advance()
    ticks = ticks + 1
    if ticks > 600 and hudCalls == 0 then
      once("nohud", "RUN FX cannot draw: this engine build never calls the "
        .. "render.hud hook. Update Gen1Recomp; the speed rows are unaffected.")
    end
    local kind = fxKind()
    if kind ~= "off" and anchor and (anchor.moving or freeMoving) and running then
      -- B is re-read here rather than trusted from the step that started:
      -- a scripted walk never asks `movement.speed`, so without this the
      -- last run's flag would trail the player through a cutscene.
      local input = game and game.input
      if input and input.isDown and input:isDown("b") then
        spawnClock = spawnClock + 1
        if kind == "rainbow" then
          layRibbon(anchor)
          ribbonLaidAt = ticks
          ribbonHot = true
        else
          -- A Gen 3 mark is a whole sprite rather than a speck, so it sheds
          -- four a cell: dense enough to be one tail, not a row of puffs.
          if not GEN3 then
            for _ = 1, PER_TICK do emit(kind, anchor) end
          elseif spawnClock % math.max(1, math.floor((ourFrames or 8) / 4)) == 0 then
            emit(kind, anchor)
          end
        end
        once("spawn", "RUN FX: %s trail spawning", kind)
      else
        once("nob", "RUN FX: running step, but B is not down at tick time")
      end
    elseif kind == "off" and running and anchor and (anchor.moving or freeMoving) then
      once("fxoff", "RUN FX: the RUN FX row is OFF")
    end
    -- However it stopped being a run, the band's near end stays on the runner
    -- while the far end comes in: it never lets go of him.
    if #ribbon > 0 and anchor and not ribbonHot then
      local input = game and game.input
      local held = input and input.isDown and input:isDown("b")
      if anchor.moving or freeMoving then
        layRibbon(anchor)
      end
      if held and running and ticks - ribbonLaidAt <= RIBBON_GRACE then
        ribbonHot = true
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
    -- A manual step is proof the grid has the walk back, so the free-roam
    -- camera's two readings stop being true of anything. Cleared here rather
    -- than on the way out of that camera, because there is no event for
    -- that: the free walk simply stops being called.
    freeMoving, freeFrames = false, nil
    if ctx.player then anchor = ctx.player end

    -- Gen 3 routes jumps through this hook too, and the cart's own rules say
    -- where nobody runs. A ledge hop that took half its frames would land wrong.
    if GEN3 and ctx.player then
      local p = ctx.player
      if p.jumping or p.surfHopping or p.dismounting or ctx.underwater then return base end
      if p.runningDisallowed and p.runningDisallowed(p.cellX, p.cellY) then return base end
    end

    local input = ctx.input
    if not (input and input.isDown and input:isDown("b")) then return base end
    if ctx.onBike and not enabled("bike") then return base end
    if ctx.surfing and not enabled("surf") then return base end

    local f = factor()
    if f <= 1 then return base end
    running = true

    -- RUN SPEED is a multiple of WALKING in every generation. A Gen 3 running
    -- step already arrives halved, so x2 is the cart's own run, and dividing that
    -- again would squeeze the whole ladder against the floor.
    local walking = base
    if GEN3 and ctx.running and not ctx.onBike and not ctx.surfing then walking = base * 2 end
    local sped = math.floor(walking / f + 0.5)
    if sped < MIN_FRAMES then sped = MIN_FRAMES end
    -- Never hand back something slower than what we were given: a mod that
    -- already made this step quicker than our own floor should keep it.
    if sped > base then
      ourFrames = base
      return base
    end

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
    local grassy = type(ctx) == "table" and ctx.terrain == "grass"
    -- Gen 3 calls grass and cave floors alike "land"; only the cell can tell.
    if GEN3 and type(ctx) == "table" and ctx.terrain == "land" then
      local Collision = engine("src.core.game3.collision")
      local at = ctx.opts or {}
      local ok, inGrass = pcall(function() return Collision.isGrass(at.x, at.y) end)
      grassy = ok and inGrass
    end
    if not grassy then
      return next(encDef, ctx)
    end
    local rolled = next(encDef, ctx)
    if running and enabled("safe") then return nil end
    if rolled and running and enabled("trail_status") then
      local kind = fxKind()
      if kind ~= "off" then pendingTrail = kind end
    end
    return rolled
  end)

  -- The trail draws over the finished frame, after the world and the UI
  -- have composited, which is the one surface a mod is handed for
  -- screen-space drawing. Decorate after next(), the way every render.hud
  -- wrapper is expected to.
  mod.hooks:wrap("render.hud", function(next, game, viewport)
    local out = next(game, viewport)
    if GENERATION == 1 then overlay(game, viewport) end
    if newsPage then
      local ok, err = pcall(drawNews, viewport)
      if not ok then
        once("newserr", "WHAT'S NEW: %s", tostring(err))
        closeNews()
      end
    end
    -- After the draw: the world pass of this same frame stamped its mask with
    -- this number, and the band above has to find it still current.
    hudCalls = hudCalls + 1
    return out
  end)
end
