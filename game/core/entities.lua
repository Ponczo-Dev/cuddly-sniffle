-- core/entities.lua
-- Byty świata poza blokami: leżące przedmioty, kulki doświadczenia,
-- spadający piasek, podpalone TNT, strzały. Moby są w core/mobs.lua.
-- Każdy byt to tabela z polami pozycji/prędkości i funkcją tick.

local physics = require("core.physics")
local items = require("core.items")
local blocks = require("core.blocks")

local M = {}

local Manager = {}
Manager.__index = Manager

local nextId = 1

function M.new(game)
  return setmetatable({ game = game, list = {}, byType = {} }, Manager)
end

-- Tworzy bazowy byt
function M.base(kind, x, y, z, width, height)
  local e = {
    id = nextId, type = kind,
    x = x, y = y, z = z, prevX = x, prevY = y, prevZ = z,
    vx = 0, vy = 0, vz = 0, yaw = 0, prevYaw = 0,
    width = width or 0.25, height = height or 0.25,
    onGround = false, age = 0, dead = false,
  }
  nextId = nextId + 1
  return e
end

function Manager:add(e)
  self.list[#self.list + 1] = e
  return e
end

function Manager:count(kind)
  if not kind then return #self.list end
  local n = 0
  for _, e in ipairs(self.list) do
    if e.type == kind and not e.dead then n = n + 1 end
  end
  return n
end

-- Byty w promieniu od punktu (opcjonalnie tylko danego typu)
function Manager:near(x, y, z, r, kind)
  local out = {}
  local r2 = r * r
  for _, e in ipairs(self.list) do
    if not e.dead and (not kind or e.type == kind) then
      local dx, dy, dz = e.x - x, e.y - y, e.z - z
      if dx * dx + dy * dy + dz * dz <= r2 then out[#out + 1] = e end
    end
  end
  return out
end

function Manager:tick()
  local game = self.game
  local list = self.list
  for i = 1, #list do
    local e = list[i]
    if not e.dead then
      e.prevX, e.prevY, e.prevZ, e.prevYaw = e.x, e.y, e.z, e.yaw
      e.age = e.age + 1
      local fn = M.TICK[e.type]
      if fn then fn(game, e) end
      -- wypadnięcie poza świat
      if e.y < -64 then e.dead = true end
    end
  end
  -- usuń martwe
  local j = 1
  for i = 1, #list do
    local e = list[i]
    if not e.dead then
      list[j] = e
      j = j + 1
    elseif e.onRemove then
      e.onRemove(game, e)
    end
  end
  for i = j, #list do list[i] = nil end
end

-- Usuwa byty w chunkach, które zostały zwolnione
function Manager:removeOutside(world)
  for _, e in ipairs(self.list) do
    if not world:isLoadedAt(math.floor(e.x), math.floor(e.z)) and e.type ~= "player" then
      e.dead = true
      e.unloaded = true
    end
  end
end

-- ---------------------------------------------------------------------------
-- Prosta fizyka "rzuconego przedmiotu"
-- ---------------------------------------------------------------------------
local function simpleMove(game, e, gravity, drag)
  e.vy = e.vy - gravity
  physics.move(game.world, e, e.vx, e.vy, e.vz, false)
  if e.collidedV then e.vy = 0 end
  local f = drag
  if e.onGround then f = 0.6 * 0.98 end
  e.vx, e.vz = e.vx * f, e.vz * f
  e.vy = e.vy * 0.98
end

-- Wypychanie z wnętrza bloku (gdy przedmiot utknie w ścianie)
local function pushOut(game, e)
  local bx, by, bz = math.floor(e.x), math.floor(e.y + 0.1), math.floor(e.z)
  if blocks.OPAQUE[game.world:getBlock(bx, by, bz)] == 1 then
    e.vy = 0.2
    e.y = e.y + 0.05
  end
end

-- ---------------------------------------------------------------------------
-- Typy bytów
-- ---------------------------------------------------------------------------
M.TICK = {}

-- Leżący przedmiot
function M.newItem(x, y, z, stack, vx, vy, vz)
  local e = M.base("item", x, y, z, 0.25, 0.25)
  e.stack = { id = stack.id, count = stack.count, damage = stack.damage or 0 }
  e.vx, e.vy, e.vz = vx or 0, vy or 0.2, vz or 0
  e.pickupDelay = 10
  e.spin = math.random() * math.pi * 2
  return e
end

M.TICK.item = function(game, e)
  if e.pickupDelay > 0 then e.pickupDelay = e.pickupDelay - 1 end
  local inWater = physics.inLiquid(game.world, { x = e.x, y = e.y - 0.4, z = e.z, width = 0.25,
    height = 1 }, "water")
  if inWater then
    e.vy = e.vy + 0.05
    if e.vy > 0.1 then e.vy = 0.1 end
  end
  if physics.inLiquid(game.world, { x = e.x, y = e.y - 0.4, z = e.z, width = 0.25, height = 1 },
    "lava") then
    e.dead = true
    game:emit("sound", "fizz", e.x, e.y, e.z)
    return
  end
  pushOut(game, e)
  simpleMove(game, e, 0.04, 0.98)
  -- zanik po 5 minutach
  if e.age >= 6000 then e.dead = true return end
  -- łączenie pobliskich takich samych przedmiotów (co 20 ticków)
  if e.age % 20 == 0 then
    for _, o in ipairs(game.entities:near(e.x, e.y, e.z, 0.8, "item")) do
      if o ~= e and not o.dead and items.canMerge(o.stack, e.stack)
        and o.stack.count + e.stack.count <= items.maxStack(e.stack.id) then
        e.stack.count = e.stack.count + o.stack.count
        o.dead = true
      end
    end
  end
  -- podnoszenie przez gracza
  local p = game.player
  if e.pickupDelay == 0 and not game.dead then
    local dx, dz = p.x - e.x, p.z - e.z
    local dy = (p.y + 0.9) - e.y
    if math.abs(dx) < 1.3 and math.abs(dz) < 1.3 and math.abs(dy) < 1.4 then
      local left = game:addToInventory(e.stack)
      local taken = e.stack.count - left
      if taken > 0 then
        game:emit("sound", "pop", e.x, e.y, e.z)
        game:emit("pickup", e, taken)
        game.stats.collected = (game.stats.collected or 0) + taken
      end
      if left <= 0 then e.dead = true else e.stack.count = left end
    end
  end
end

-- Kulka doświadczenia
function M.newXp(x, y, z, value)
  local e = M.base("xp", x, y, z, 0.25, 0.25)
  e.value = value
  e.vx = (math.random() - 0.5) * 0.2
  e.vy = math.random() * 0.2 + 0.1
  e.vz = (math.random() - 0.5) * 0.2
  e.pickupDelay = 10
  return e
end

-- Rozbija wartość XP na kulki jak w MC
function M.splitXp(value)
  local out = {}
  local sizes = { 2477, 1237, 617, 307, 149, 73, 37, 17, 7, 3, 1 }
  while value > 0 do
    for _, s in ipairs(sizes) do
      if value >= s then
        out[#out + 1] = s
        value = value - s
        break
      end
    end
  end
  return out
end

M.TICK.xp = function(game, e)
  if e.pickupDelay > 0 then e.pickupDelay = e.pickupDelay - 1 end
  local p = game.player
  -- kulki lecą do gracza z odległości 8 bloków
  local dx, dy, dz = p.x - e.x, (p.y + 0.8) - e.y, p.z - e.z
  local d = math.sqrt(dx * dx + dy * dy + dz * dz)
  if d < 8 and not game.dead then
    local f = (1 - d / 8)
    f = f * f * 0.1
    e.vx = e.vx + dx / d * f
    e.vy = e.vy + dy / d * f
    e.vz = e.vz + dz / d * f
  end
  simpleMove(game, e, 0.03, 0.98)
  if e.age >= 6000 then e.dead = true return end
  if e.pickupDelay == 0 and d < 1.2 and not game.dead then
    game:addXp(e.value)
    game:emit("sound", "orb", e.x, e.y, e.z)
    e.dead = true
  end
end

-- Spadający piasek/żwir
function M.newFalling(x, y, z, blockId, meta)
  local e = M.base("falling", x + 0.5, y, z + 0.5, 0.98, 0.98)
  e.block, e.meta = blockId, meta
  return e
end

M.TICK.falling = function(game, e)
  e.vy = e.vy - 0.04
  physics.move(game.world, e, e.vx, e.vy, e.vz, false)
  e.vy = e.vy * 0.98
  if e.onGround or e.age > 600 then
    e.dead = true
    local bx, by, bz = math.floor(e.x), math.floor(e.y + 0.5), math.floor(e.z)
    local cur = game.world:getBlock(bx, by, bz)
    local d = blocks.defs[cur]
    if cur == 0 or (d and (d.replaceable or d.liquid)) then
      game.world:setBlock(bx, by, bz, e.block, e.meta)
      game:notifyNeighbors(bx, by, bz)
    else
      game:dropStack(e.x, e.y, e.z, { id = e.block, count = 1, damage = 0 })
    end
  end
end

-- Podpalone TNT
function M.newTnt(x, y, z, fuse)
  local e = M.base("tnt", x + 0.5, y, z + 0.5, 0.98, 0.98)
  e.fuse = fuse or 80
  e.vy = 0.2
  e.vx = (math.random() - 0.5) * 0.04
  e.vz = (math.random() - 0.5) * 0.04
  return e
end

M.TICK.tnt = function(game, e)
  simpleMove(game, e, 0.04, 0.98)
  e.fuse = e.fuse - 1
  if e.fuse <= 0 then
    e.dead = true
    game:explode(e.x, e.y + 0.5, e.z, 4, e)
  end
end

-- Strzała (od gracza albo szkieleta)
function M.newArrow(x, y, z, vx, vy, vz, shooter, damage)
  local e = M.base("arrow", x, y, z, 0.2, 0.2)
  e.vx, e.vy, e.vz = vx, vy, vz
  e.shooter = shooter
  e.damage = damage or 2
  e.stuck = false
  return e
end

-- Rzucany pocisk (śnieżka, jajko)
function M.newThrown(kind, x, y, z, vx, vy, vz, shooter)
  local e = M.base(kind, x, y, z, 0.2, 0.2)
  e.vx, e.vy, e.vz = vx, vy, vz
  e.shooter = shooter
  return e
end

return M
