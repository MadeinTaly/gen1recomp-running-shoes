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

-- Three shades each, oldest last, because three shades is what a Game Boy
-- sprite had and a smooth gradient would read as somebody else's engine.
--
-- Smoke greys, fire reds, lightning yellows -- and none of them pale,
-- because a pale anything at half opacity over Route 1's green is a rumour
-- rather than an effect.
-- ------- the ramps
--
-- Five shades each, brightest first, and a particle is drawn from a
-- three-shade WINDOW onto that ramp: core, middle, rim. Two things fall
-- out of one table that way.
--
-- Across the particle, the window gives it a lit core and a dark rim,
-- which is how a Game Boy sprite is shaded and the reason these now read
-- as objects rather than as coloured squares.
--
-- Along its life, the window SLIDES down the ramp: a flame starts with
-- white-yellow at the core and ends as an ember with nothing bright left
-- in it, without the colours ever being interpolated. Same trick, one
-- table, no gradients -- a smooth blend would look like somebody else's
-- engine.
local RAMP = {
  -- smoke: near-white where it leaves the ground, down to a grey that
  -- still has an edge on a pale tile
  dust = {
    { 0.95, 0.95, 0.94 }, { 0.80, 0.80, 0.78 }, { 0.60, 0.60, 0.58 },
    { 0.40, 0.40, 0.39 }, { 0.20, 0.20, 0.20 },
  },
  -- fire: white-hot, yellow, orange, red, ember
  fire = {
    { 1.00, 0.96, 0.72 }, { 1.00, 0.78, 0.16 }, { 0.98, 0.42, 0.06 },
    { 0.86, 0.12, 0.05 }, { 0.40, 0.04, 0.03 },
  },
  -- lightning: a white core cooling through yellow into a dark amber
  bolt = {
    { 1.00, 1.00, 0.95 }, { 1.00, 0.95, 0.45 }, { 1.00, 0.84, 0.10 },
    { 0.78, 0.52, 0.03 }, { 0.32, 0.20, 0.02 },
  },
}

-- ------- the silhouettes
--
-- A particle used to be four rectangles: two crossed bars whose overlap
-- knocked the corners off a square, the body inset in that, and a lit
-- square for the core. It read as round at a glance and as a box the moment
-- you stopped to look at one, which is not what a puff of smoke or a tongue
-- of flame is shaped like.
--
-- These are ROWS instead. One filled rectangle per scanline, its width read
-- out of a shape table, so the outline is whatever curve the table
-- describes and the fill still costs one draw call per row rather than one
-- per pixel. A puff is a DISC. A flame is a TEARDROP -- pinched to a point
-- at the tip, widest about two thirds of the way down, rounded off at the
-- base -- so it reads as a flame from its outline alone, standing still, in
-- a single frame.
--
-- Widths are worked out once at load and never again: a disc row is a
-- square root, and a square root per row per particle per frame is the one
-- cost a decoration cannot run up. Indexed by diameter, so `DISC[6][3]` is
-- how wide the third row of a six-pixel puff is.
local DISC, TEAR = {}, {}
for d = 1, 8 do
  local r, disc, tear = d / 2, {}, {}
  -- where the teardrop is at its widest: about two thirds down, which is
  -- where a flame's shoulder sits before it rounds into its base
  local waist = d * 0.68
  for i = 0, d - 1 do
    local mid = i + 0.5
    local dy = mid - r
    disc[i + 1] = math.max(1, math.floor(math.sqrt(math.max(0, r * r - dy * dy)) * 2 + 0.5))
    local w
    if mid <= waist then
      -- the pinch: a power curve rather than a straight line, so the tip is
      -- a point and the shoulder is a shoulder instead of a triangle
      w = d * (mid / waist) ^ 0.62
    else
      -- and the base is a quarter-circle off the same radius, so the bottom
      -- is round rather than chopped
      local t = (mid - waist) / math.max(0.5, d - waist)
      w = d * math.sqrt(math.max(0, 1 - t * t * 0.72))
    end
    tear[i + 1] = math.max(1, math.floor(w + 0.5))
  end
  DISC[d], TEAR[d] = disc, tear
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
-- A cell and a quarter back along the direction of travel. Eight world
-- pixels reaches the sprite's trailing edge from the spawn point at its
-- centre, and the particle's own half width plus the jitter eats most of
-- what is left -- so sixteen only just cleared the box, and on a play test
-- the trail still read as crowding the character on the way right. Twenty
-- puts daylight between the two, which is what it wanted.
local BEHIND = 20

-- The sprite's own box, relative to the cell origin the camera is anchored
-- on: `SpriteRenderer:draw` puts a 16x16 frame at (px, py - 4)
-- (src/world/OverworldController.lua:89), so the character occupies px..px+16
-- across and py-4..py+12 down. Nothing of ours may draw inside it.
local SPRITE_W, SPRITE_TOP, SPRITE_BOT = 16, -4, 12

-- How far a particle reaches from its own centre, which is what the box has
-- to be grown by before asking whether the mark is on the character: a
-- CENTRE outside the sprite says nothing when the rows around it are drawn
-- four pixels out. A puff and a flame are symmetric; a bolt is a jagged line
-- climbing BOLT_JOINTS * BOLT_RISE pixels UPWARD from its base, so it
-- reaches far above its centre and barely at all below.
local REACH = {
  dust = { x = 4, up = 4, down = 4 },
  fire = { x = 4, up = 5, down = 5 },
  bolt = { x = 5, up = 11, down = 1 },
}

-- How long the engine's own dust puff is held behind a running player.
-- `startDustAnim` hands out 32 frames, which is right for a boulder being
-- shoved and far too long for a footfall at four frames a tile.
local PUFF_FRAMES = 10

-- A bolt is not a blob and not a stack of dots: it is a jagged line, drawn
-- upward from the spawn point as five joints whose sideways kick alternates
-- and grows. Re-picked every other frame from the particle's own seed, so
-- it crackles into a new shape rather than sitting there being a shape.
local BOLT_JOINTS = 5
local BOLT_RISE = 2      -- world pixels between joints

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

  local function fxKind()
    local ok, value = pcall(function() return mod.options:get("fx") end)
    if not ok or type(value) ~= "string" then return "off" end
    return RAMP[value] and value or "off"
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
    remember(map.id, cx, cy)
    -- No dust puff here: `World:runCut` plays one through its own script
    -- callback, not through anything a live map edit can reach mid-step, and
    -- there is no Gen 2 `startDustAnim` to borrow the way Gen 1's arm does.
    -- The mod's own coloured particles do not depend on it (see "the puff is
    -- not a grass thing" further down) and keep drawing regardless.
    return true
  end

  local function cutGrassAt(game, cx, cy, quiet)
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
  local spawnClock = 0

  local function clearTrail()
    for i = #particles, 1, -1 do particles[i] = nil end
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
    local life = lifeSpan()
    particles[#particles + 1] = {
      kind = kind,
      -- `px`,`py` is the top-left of the 16x16 cell, so +8/+12 is about
      -- where the feet are -- and then BEHIND back along the way he is
      -- going, which is what keeps the mark out of his own sprite box
      x = player.px + 8 - d[1] * BEHIND + ax * spread + (rnd() * 3 - 1.5),
      y = player.py + 12 - d[2] * BEHIND + ay * spread + (rnd() * 3 - 1.5),
      -- Barely any drift: a trail is something LEFT BEHIND, so it stays
      -- where it was shed and the player runs away from it. Give it a push
      -- backwards as well and the far end races the player, which is what
      -- kept the old trail hugging his heels instead of stretching out.
      vx = (rnd() * 0.16 - 0.08),
      vy = -(kind == "fire" and 0.22 or 0.10) + (rnd() * 0.10 - 0.05),
      life = life, max = life,
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
  end

  -- ------- drawing
  --
  -- Everything below is guarded so a headless run (no love, no graphics)
  -- and a frame with nothing to show both cost a single comparison.

  -- Where on the ramp this particle is drawing from. Fresh sits at the top
  -- (core white-hot, rim mid), old sits at the bottom (core mid, rim
  -- nearly gone) -- so age is a slide down one table rather than a second
  -- set of colours.
  local function window(kind, p)
    local ramp = RAMP[kind] or RAMP.dust
    local i = math.floor((1 - p.life / p.max) * 2.999)   -- 0, 1 or 2
    return ramp[i + 1], ramp[i + 2], ramp[i + 3]
  end

  -- One shape for all three: big at the heel, tapering to a point at the
  -- tail. A trail should read as a trail -- you should be able to tell
  -- which end the player is at from the shape alone, without watching it
  -- move. An earlier pass had smoke EXPAND as it thinned, which is what
  -- real smoke does and which read as a smear rather than as a trail.
  local BIG = { dust = 6, fire = 7, bolt = 3 }

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
    --
    -- A particle is a rim, a body and a lit core -- three shades off the
    -- same ramp window -- laid on as three passes of NARROWING ROWS over one
    -- of the shape tables at the top of this file: the rim draws the whole
    -- outline, the body the same rows inset a pixel so the rim survives as
    -- an edge, the core inset two more over the band of rows where the thing
    -- is actually bright.
    --
    -- Rows rather than a per-pixel mask, for the same reason the four
    -- rectangles this replaces were four: it runs once per particle per
    -- frame on a phone, and a 7x7 mask at seventy live particles is three
    -- thousand draw calls for a decoration. A six-pixel puff is twelve, and
    -- unlike the four it is actually round.
    local function shaded(shape, cx, top, rim, body, core, alpha, lit)
      local n = #shape
      love.graphics.setColor(rim[1], rim[2], rim[3], alpha)
      for i = 1, n do
        local w = shape[i]
        put(cx - w / 2, top + i - 1, w, 1)
      end
      if n >= 4 then
        love.graphics.setColor(body[1], body[2], body[3], alpha)
        for i = 2, n - 1 do
          local w = shape[i] - 2
          if w >= 1 then put(cx - w / 2, top + i - 1, w, 1) end
        end
      end
      if n >= 5 then
        -- The lit core sits where the thing is actually bright rather than
        -- in the middle: low in a flame, which is hottest at its base, high
        -- in a puff of smoke, which catches the light on top. `lit` says
        -- which row, as a fraction of the height.
        love.graphics.setColor(core[1], core[2], core[3], alpha)
        local at = math.floor(lit * n + 0.5)
        for i = math.max(2, at - 1), math.min(n - 1, at + 1) do
          local w = shape[i] - 4
          if w >= 1 then put(cx - w / 2, top + i - 1, w, 1) end
        end
      end
    end

    -- Nothing of ours draws inside the player's own 16x16 sprite box.
    -- `render.hud` composites over the finished frame, so a mark inside that
    -- box is a mark ON the character, not behind him. Shedding the trail
    -- BEHIND him (see the BEHIND constant) keeps it clear on its own in
    -- three directions out of four; this is the backstop for the fourth,
    -- walking DOWN, where "behind" is "over his head", and for anything that
    -- drifts back in afterwards.
    local function onSprite(p)
      local r = REACH[p.kind] or REACH.dust
      -- Grown by the particle's own reach, and asymmetrically: a mark ABOVE
      -- the box can still put pixels in it by reaching DOWN, and one below
      -- by reaching up, so each edge is pushed out by the reach that crosses
      -- it rather than by one number for all four.
      return p.x >= player.px - r.x
         and p.x <= player.px + SPRITE_W + r.x
         and p.y >= player.py + SPRITE_TOP - r.down
         and p.y <= player.py + SPRITE_BOT + r.up
    end

    for i = 1, #particles do
      local p = particles[i]
      local core, body, rim = window(p.kind, p)
      local size = sizeOf(p.kind, p)
      -- Fades the whole way out rather than snapping off at the end of the
      -- trail, but never down to nothing you can see: the far end is a
      -- ghost, not an absence.
      local alpha = 0.30 + 0.70 * (p.life / p.max)
      local age = p.max - p.life

      if onSprite(p) then                     -- behind the player, or not at all
        -- nothing
      elseif p.kind == "bolt" then
        -- Lit on alternate ticks, and re-drawn to a different jag each
        -- time: a spark that burns steadily in one shape for ten frames is
        -- a lamp, not lightning.
        if p.life % 2 == 1 then
          local kick, x, y = 0, p.x, p.y
          for j = 1, BOLT_JOINTS do
            -- deterministic from the particle's own seed and the frame, so
            -- the whole arc re-jags together instead of each joint
            -- twitching on its own
            kick = ((p.seed + j * 7 + age) % 5) - 2
            local nx, ny = x + kick, y - BOLT_RISE
            local shade = j <= 2 and core or (j <= 4 and body or rim)
            love.graphics.setColor(shade[1], shade[2], shade[3], alpha)
            -- one rectangle per joint, spanning the gap it just crossed,
            -- and thinning as it climbs: a bolt is thick where it leaves
            -- the ground and a hair at its tip, which is the difference
            -- between lightning and a ladder
            put(math.min(x, nx), ny,
                math.abs(kick) + math.max(1, size + 2 - j), BOLT_RISE + 1)
            x, y = nx, ny
          end
          drew = drew + 1
        end
      elseif p.kind == "fire" then
        -- A tongue rather than a ball, and now shaped like one: the
        -- teardrop is pinched to a point at the tip and rounded at the
        -- base, so a flame reads as a flame in a single still frame. The
        -- lit core sits low, where a flame is hottest.
        local h = math.min(8, size + 1)
        shaded(TEAR[h], p.x, p.y - h / 2, rim, body, core, alpha, 0.80)
        drew = drew + 1
      else
        -- Smoke sways as it rises. The sway comes off the particle's age
        -- and its own seed, so no two puffs lean the same way at the same
        -- time and none of it needs storing. A disc rather than a boxy
        -- blob, with the highlight up top where a puff catches the light.
        local sway = math.sin(age * 0.22 + p.seed) * 1.6
        local d = math.min(8, size)
        shaded(DISC[d], p.x + sway, p.y - d / 2, rim, body, core, alpha, 0.30)
        drew = drew + 1
      end
    end

    love.graphics.pop()
    if drew > 0 then
      once("drawing", "RUN FX: drawing (%d marks this frame, scale %g)", drew, sp)
    end
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

    if cutOn() and running then
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
    -- `game.overworld` is a Gen 1 field with no Gen 2 counterpart -- Gold
    -- hangs its world off `game.world` instead (WorldAPI.lua:39) -- so `ow`
    -- is always nil here on Gold and every guard below answers false. That
    -- is deliberate, not a gap this file should paper over: see "what
    -- changes on Gold" near the top for why there is no puff to borrow
    -- there, and why the coloured particles below do not need one.
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
    if not (game and mapId and cutOn()) then return end
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
        for _ = 1, PER_TICK do emit(kind, anchor) end
        once("spawn", "RUN FX: %s trail spawning", kind)
      else
        once("nob", "RUN FX: running step, but B is not down at tick time")
      end
    elseif kind == "off" and running and anchor and (anchor.moving or freeMoving) then
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
    -- A manual step is proof the grid has the walk back, so the free-roam
    -- camera's two readings stop being true of anything. Cleared here rather
    -- than on the way out of that camera, because there is no event for
    -- that: the free walk simply stops being called.
    freeMoving, freeFrames = false, nil
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
