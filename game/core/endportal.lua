-- core/endportal.lua
-- Oko Endu i portal do Endu:
--  * rzucone oko leci ~12 bloków w stronę najbliższej twierdzy i spada
--    (zwykle zostaje, czasem pęka),
--  * oko włożone do ramy portalu; gdy cały pierścień 12 ramek ma oczy,
--    w środku 3x3 pojawia się portal,
--  * wejście do portalu: podróż do Endu (platforma z obsydianu), a portal
--    wyjścia po pokonaniu smoka wraca do zwykłego świata.

local entities = require("core.entities")

local M = {}

local floor, sqrt = math.floor, math.sqrt
local FRAME, PORTAL = 120, 119

M.ARRIVAL = { 100, 64, 0 } -- platforma na wysokości wyspy (jak w MC: obok niej)

-- ---------------------------------------------------------------------------
-- Rzucanie oka
-- ---------------------------------------------------------------------------
function M.throwEye(game)
  local p = game.player
  if game.dimension ~= "overworld" then
    game:emit("message", "Oko Endu nie wskazuje niczego w tym wymiarze")
    return false
  end
  local structures = require("core.structures")
  local target = structures.findStronghold(game.seed, p.x, p.z)
  if not target then return false end
  local e = entities.base("eye", p.x, p.y + 1.6, p.z, 0.25, 0.25)
  e.tx, e.tz = target[1] + 0.5, target[3] + 0.5
  e.startY = p.y + 1.6
  game.entities:add(e)
  game:emit("sound", "throw", p.x, p.y + 1.5, p.z)
  game:consumeHeld(1)
  return true
end

entities.TICK.eye = function(game, e)
  local dx, dz = e.tx - e.x, e.tz - e.z
  local d = sqrt(dx * dx + dz * dz)
  local travelled = e.age
  if d > 0.5 and travelled < 50 then
    local sp = 0.25
    e.x, e.z = e.x + dx / d * sp, e.z + dz / d * sp
    -- wznosi się, a nad celem opada
    if d < 12 then e.y = e.y - 0.05 else e.y = e.y + 0.04 end
  end
  if game.rng:chance(0.7) then game:emit("particles", "portal", e.x, e.y, e.z) end
  if e.age >= 80 then
    e.dead = true
    if game.rng:chance(0.8) then
      game:dropStack(e.x, e.y, e.z, { id = 381, count = 1, damage = 0 })
    else
      game:emit("particles", "poof", e.x, e.y, e.z)
      game:emit("sound", "glass", e.x, e.y, e.z)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Rama i aktywacja portalu
-- ---------------------------------------------------------------------------
local function hasEye(world, x, y, z)
  return world:getBlock(x, y, z) == FRAME and world:getMeta(x, y, z) >= 4
end

-- Czy wokół 3x3 o lewym górnym rogu (x0, z0) stoi 12 ramek z oczami
local function ringComplete(world, x0, y, z0)
  for i = 0, 2 do
    if not hasEye(world, x0 - 1, y, z0 + i) then return false end
    if not hasEye(world, x0 + 3, y, z0 + i) then return false end
    if not hasEye(world, x0 + i, y, z0 - 1) then return false end
    if not hasEye(world, x0 + i, y, z0 + 3) then return false end
  end
  return true
end

-- Szuka pełnego pierścienia obok ramki (x, y, z); zapala portal
function M.tryActivate(game, x, y, z)
  local world = game.world
  for x0 = x - 4, x + 1 do
    for z0 = z - 4, z + 1 do
      if ringComplete(world, x0, y, z0) then
        for i = 0, 2 do
          for j = 0, 2 do world:setBlock(x0 + i, y, z0 + j, PORTAL, 0) end
        end
        game:emit("sound", "portal_end", x0 + 1.5, y, z0 + 1.5)
        game:emit("message", "Portal do Endu otwarty!")
        return true
      end
    end
  end
  return false
end

function M.insertEye(game, x, y, z, meta)
  game.world:setBlock(x, y, z, FRAME, meta + 4)
  game:consumeHeld(1)
  game:emit("sound", "enchant", x + 0.5, y + 1, z + 0.5)
  game:emit("particles", "portal", x + 0.5, y + 1, z + 0.5)
  M.tryActivate(game, x, y, z)
  return true
end

-- ---------------------------------------------------------------------------
-- Podróż
-- ---------------------------------------------------------------------------
function M.travel(game)
  if game.net then
    game:emit("message", "Portale nie dzialaja w grze wieloosobowej")
    return
  end
  local p = game.player
  if game.dimension == "end" then
    -- powrót: łóżko albo punkt startu świata
    local x, y, z = game.spawnX or game.worldSpawnX, game.spawnY or game.worldSpawnY,
      game.spawnZ or game.worldSpawnZ
    game:changeDimension("overworld", x, y, z)
    game.needsSpawnFix = true
    game:emit("message", "Wrociles z Endu. Brawo!")
    return
  end
  local a = M.ARRIVAL
  game:changeDimension("end", a[1] + 0.5, a[2], a[3] + 0.5)
  -- platforma z obsydianu i miejsce nad nią
  local w = game.world
  for x = a[1] - 2, a[1] + 2 do
    for z = a[3] - 2, a[3] + 2 do
      w:setBlock(x, a[2] - 1, z, 49, 0)
      for y = a[2], a[2] + 2 do w:setBlock(x, y, z, 0, 0) end
    end
  end
  p.vx, p.vy, p.vz = 0, 0, 0
  p.fallDistance = 0
  game:emit("message", "Wszedles do Endu. Pokonaj smoka!")
end

-- Co tick (z game.lua): wejście w portal Endu
function M.tick(game)
  local p = game.player
  if (game.endCooldown or 0) > 0 then
    game.endCooldown = game.endCooldown - 1
    return
  end
  local w = game.world
  local bx, bz = floor(p.x), floor(p.z)
  if w:getBlock(bx, floor(p.y + 0.2), bz) == PORTAL or w:getBlock(bx, floor(p.y - 0.2), bz) == PORTAL then
    game.endCooldown = 60
    M.travel(game)
  end
end

-- Portal wyjścia (fontanna ze skały macierzystej) na środku wyspy
function M.buildExitPortal(game, y)
  local w = game.world
  local BEDROCK = 7
  for x = -3, 3 do
    for z = -3, 3 do
      local d2 = x * x + z * z
      if d2 <= 12 then
        w:setBlock(x, y - 1, z, BEDROCK, 0)
        if d2 <= 6 then
          w:setBlock(x, y, z, PORTAL, 0)
        else
          w:setBlock(x, y, z, BEDROCK, 0)
        end
        for yy = y + 1, y + 4 do if not (x == 0 and z == 0) then w:setBlock(x, yy, z, 0, 0) end end
      end
    end
  end
  for yy = y, y + 3 do w:setBlock(0, yy, 0, BEDROCK, 0) end
  w:setBlock(0, y + 4, 0, 122, 0) -- jajo smoka
  for _, o in ipairs({ { 1, 0, 1 }, { -1, 0, 2 }, { 0, 1, 3 }, { 0, -1, 4 } }) do
    w:setBlock(o[1], y + 2, o[2], 50, o[3])
  end
end

return M
