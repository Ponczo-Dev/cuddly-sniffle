-- core/portal.lua
-- Portal do Netheru: rama z obsydianu (wnętrze 2 x 3, jak w Beta),
-- zapalona krzesiwem. Stanie w portalu przez 4 sekundy przenosi do
-- drugiego wymiaru (współrzędne / 8 w Netherze, * 8 w zwykłym świecie).
-- Po drugiej stronie szukamy istniejącego portalu albo budujemy nowy.

local P = {}

local OBSIDIAN, PORTAL, AIR, FIRE = 49, 90, 0, 51

-- Sprawdza ramę dla wnętrza zaczynającego się w (x0, y0, z0) wzdłuż osi
-- axis (0 = X, 1 = Z). Zwraca true, jeśli rama jest kompletna i wnętrze puste.
local function frameOk(world, x0, y0, z0, axis)
  local dx, dz = axis == 0 and 1 or 0, axis == 1 and 1 or 0
  for i = 0, 1 do
    for j = 0, 2 do
      local id = world:getBlock(x0 + dx * i, y0 + j, z0 + dz * i)
      if id ~= AIR and id ~= FIRE and id ~= PORTAL then return false end
    end
    if world:getBlock(x0 + dx * i, y0 - 1, z0 + dz * i) ~= OBSIDIAN then return false end
    if world:getBlock(x0 + dx * i, y0 + 3, z0 + dz * i) ~= OBSIDIAN then return false end
  end
  for j = 0, 2 do
    if world:getBlock(x0 - dx, y0 + j, z0 - dz) ~= OBSIDIAN then return false end
    if world:getBlock(x0 + dx * 2, y0 + j, z0 + dz * 2) ~= OBSIDIAN then return false end
  end
  return true
end

local function fill(world, x0, y0, z0, axis, id)
  local dx, dz = axis == 0 and 1 or 0, axis == 1 and 1 or 0
  for i = 0, 1 do
    for j = 0, 2 do
      world:setBlock(x0 + dx * i, y0 + j, z0 + dz * i, id, id == PORTAL and axis or 0)
    end
  end
end

-- Próba zapalenia portalu ogniem w (x, y, z). Zwraca true przy sukcesie.
function P.tryLight(game, x, y, z)
  local world = game.world
  for axis = 0, 1 do
    local dx, dz = axis == 0 and 1 or 0, axis == 1 and 1 or 0
    for i = 0, 1 do
      for j = 0, 2 do
        local x0, y0, z0 = x - dx * i, y - j, z - dz * i
        if frameOk(world, x0, y0, z0, axis) then
          fill(world, x0, y0, z0, axis, PORTAL)
          game:emit("sound", "teleport", x + 0.5, y + 0.5, z + 0.5)
          return true
        end
      end
    end
  end
  return false
end

-- Po zmianie sąsiada: portal z niekompletną ramą znika
function P.validate(game, x, y, z)
  local world = game.world
  local axis = world:getMeta(x, y, z)
  local dx, dz = axis == 0 and 1 or 0, axis == 1 and 1 or 0
  -- znajdź lewy dolny róg wnętrza
  local x0, y0, z0 = x, y, z
  while world:getBlock(x0 - dx, y0, z0 - dz) == PORTAL do x0, z0 = x0 - dx, z0 - dz end
  while world:getBlock(x0, y0 - 1, z0) == PORTAL do y0 = y0 - 1 end
  if not frameOk(world, x0, y0, z0, axis) then
    -- usuń wszystkie połączone bloki portalu
    local queue = { { x, y, z } }
    local seen = {}
    while #queue > 0 do
      local q = table.remove(queue)
      local k = q[1] .. "," .. q[2] .. "," .. q[3]
      if not seen[k] and world:getBlock(q[1], q[2], q[3]) == PORTAL then
        seen[k] = true
        world:setBlock(q[1], q[2], q[3], AIR, 0)
        for _, d in ipairs({ { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }) do
          queue[#queue + 1] = { q[1] + d[1], q[2] + d[2], q[3] + d[3] }
        end
      end
    end
  end
end

-- Szuka portalu w promieniu (w załadowanym świecie). Zwraca dolny blok.
local function findPortal(world, x, z, radius)
  local best, bestD
  for dx = -radius, radius do
    for dz = -radius, radius do
      local px, pz = x + dx, z + dz
      if world:isLoadedAt(px, pz) then
        for y = 1, 126 do
          if world:getBlock(px, y, pz) == PORTAL and world:getBlock(px, y - 1, pz) ~= PORTAL then
            local d = dx * dx + dz * dz
            if not best or d < bestD then best, bestD = { px, y, pz }, d end
          end
        end
      end
    end
  end
  return best
end

-- Buduje portal z platformą w okolicy (x, z)
local function buildPortal(world, x, z, nether)
  -- znajdź wysokość: w Netherze wolna przestrzeń nad podłożem, w świecie powierzchnia
  local y
  if nether then
    for yy = 32, 100 do
      local ok = true
      for i = -1, 2 do
        for j = 0, 4 do
          if world:getBlock(x + i, yy + j, z) ~= AIR then ok = false end
        end
      end
      if ok then y = yy break end
    end
    y = y or 64
  else
    y = math.max(world:getHeight(x, z), 64)
  end
  -- wyczyść miejsce i postaw platformę
  for i = -2, 3 do
    for k = -2, 2 do
      for j = 0, 4 do world:setBlock(x + i, y + j, z + k, AIR, 0) end
      world:setBlock(x + i, y - 1, z + k, OBSIDIAN, 0)
    end
  end
  for i = -1, 2 do
    world:setBlock(x + i, y - 1, z, OBSIDIAN, 0)
    world:setBlock(x + i, y + 3, z, OBSIDIAN, 0)
  end
  for j = 0, 3 do
    world:setBlock(x - 1, y + j, z, OBSIDIAN, 0)
    world:setBlock(x + 2, y + j, z, OBSIDIAN, 0)
  end
  fill(world, x, y, z, 0, PORTAL)
  return { x, y, z }
end

-- Tick gracza: odliczanie w portalu i podróż
function P.tick(game)
  local p = game.player
  if game.dead or p.riding then return end
  local inside = false
  require("core.physics").touchingBlocks(game.world, p, function(id)
    if id == PORTAL then inside = true end
  end)
  if game.portalCooldown and game.portalCooldown > 0 then
    if not inside then game.portalCooldown = game.portalCooldown - 1 end
    game.portalTimer = 0
    return
  end
  if not inside then
    game.portalTimer = 0
    return
  end
  game.portalTimer = (game.portalTimer or 0) + 1
  local need = p.gameMode == "creative" and 1 or 80
  if game.portalTimer >= need then
    game.portalTimer = 0
    game.portalCooldown = 100
    P.travel(game)
  end
end

function P.travel(game)
  if game.net then
    game:emit("message", "Portale nie dzialaja w grze wieloosobowej")
    return false
  end
  local p = game.player
  local toNether = game.dimension ~= "nether"
  local scale = toNether and 1 / 8 or 8
  local tx, tz = math.floor(p.x * scale), math.floor(p.z * scale)
  local target = toNether and "nether" or "overworld"
  game:changeDimension(target, tx + 0.5, 70, tz + 0.5)
  local world = game.world
  local found = findPortal(world, tx, tz, 16)
  if not found then found = buildPortal(world, tx, tz, toNether) end
  p.x, p.y, p.z = found[1] + 0.5, found[2], found[3] + 0.5
  p.prevX, p.prevY, p.prevZ = p.x, p.y, p.z
  p.vx, p.vy, p.vz = 0, 0, 0
  p.fallDistance = 0
  game:emit("sound", "teleport", p.x, p.y, p.z)
end

return P
