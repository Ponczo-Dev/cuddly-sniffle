-- core/vehicles.lua
-- Pojazdy: wagonik (jeździ po torach, gracz może go popychać) i łódka
-- (pływa po wodzie, sterowanie W/S/A/D). Prawy przycisk = wsiądź,
-- shift = wysiądź, kilka uderzeń = rozbicie (wypada przedmiot).

local entities = require("core.entities")
local physics = require("core.physics")
local rails = require("core.rails")
local blocks = require("core.blocks")

local V = {}

function V.spawnMinecart(game, x, y, z)
  local e = entities.base("minecart", x, y, z, 0.98, 0.7)
  e.isVehicle = true
  e.label = "Wagonik"
  e.damage = 0
  e.hurtTime = 0
  return game.entities:add(e)
end

function V.spawnBoat(game, x, y, z, yaw)
  local e = entities.base("boat", x, y, z, 1.5, 0.6)
  e.isVehicle = true
  e.label = "Lodka"
  e.damage = 0
  e.hurtTime = 0
  e.yaw = yaw or 0
  e.prevYaw = e.yaw
  return game.entities:add(e)
end

-- Wysokość siedzenia nad pozycją pojazdu
function V.seatOffset(e)
  if e.type == "boat" then return 0.25 end
  return 0.35
end

-- ---------------------------------------------------------------------------
-- Wagonik
-- ---------------------------------------------------------------------------
entities.TICK.minecart = function(game, e)
  if e.hurtTime > 0 then e.hurtTime = e.hurtTime - 1 end
  if e.damage > 0 then e.damage = e.damage - 1 end
  local onRail = rails.moveCart(game, e)
  if not onRail then
    e.onRail = false
    e.vy = e.vy - 0.04
    physics.move(game.world, e, e.vx, e.vy, e.vz, false)
    if e.collidedV then e.vy = 0 end
    local f = e.onGround and 0.5 or 0.95
    e.vx, e.vz = e.vx * f, e.vz * f
  end
  -- obrót w kierunku jazdy
  if math.abs(e.vx) + math.abs(e.vz) > 0.001 then
    local want = math.atan2 and math.atan2(-e.vx, -e.vz) or math.atan(-e.vx, -e.vz)
    -- wagonik jest symetryczny: wybierz obrót bliższy obecnemu
    local diff = (want - e.yaw + math.pi) % (2 * math.pi) - math.pi
    if math.abs(diff) > math.pi / 2 then want = want + math.pi end
    diff = (want - e.yaw + math.pi) % (2 * math.pi) - math.pi
    e.yaw = e.yaw + diff * 0.5
  end
end

-- ---------------------------------------------------------------------------
-- Łódka
-- ---------------------------------------------------------------------------
entities.TICK.boat = function(game, e)
  if e.hurtTime > 0 then e.hurtTime = e.hurtTime - 1 end
  if e.damage > 0 then e.damage = e.damage - 1 end
  local world = game.world
  -- ile łódki jest zanurzone
  local submerged = 0
  for i = 0, 4 do
    local yy = e.y - 0.125 + i * 0.125
    if physics.pointInLiquid(world, e.x, yy, e.z, "water") then submerged = submerged + 0.2 end
  end
  if submerged > 0 then
    e.vy = e.vy + (submerged * 2 - 1) * 0.04
    e.vy = e.vy * 0.8
  else
    e.vy = e.vy - 0.04
  end
  -- sterowanie
  if e.rider and e.input then
    local inp = e.input
    e.yaw = e.yaw - inp.strafe * 0.05
    local s = inp.forward * (submerged > 0 and 0.04 or 0.01)
    e.vx = e.vx - math.sin(e.yaw) * s
    e.vz = e.vz - math.cos(e.yaw) * s
  end
  local speed = math.sqrt(e.vx * e.vx + e.vz * e.vz)
  local maxSpeed = submerged > 0 and 0.35 or 0.08
  if speed > maxSpeed then
    e.vx, e.vz = e.vx / speed * maxSpeed, e.vz / speed * maxSpeed
  end
  local before = speed
  local mx, _, mz, wx, _, wz = physics.move(world, e, e.vx, e.vy, e.vz, false)
  if e.collidedV then e.vy = 0 end
  -- zderzenie przy dużej prędkości: łódka się rozbija
  if e.collidedH and before > 0.25 then
    V.destroy(game, e, true)
    return
  end
  if mx ~= wx then e.vx = 0 end
  if mz ~= wz then e.vz = 0 end
  local f = submerged > 0 and 0.95 or (e.onGround and 0.5 or 0.95)
  e.vx, e.vz = e.vx * f, e.vz * f
end

-- Rozbicie pojazdu (drop przedmiotu albo desek i patyków dla łódki)
function V.destroy(game, e, crashed)
  if e.dead then return end
  e.dead = true
  if e.rider then V.dismount(game) end
  if game.player.gameMode == "creative" and not crashed then return end
  if e.type == "boat" then
    if crashed then
      game:dropStack(e.x, e.y + 0.5, e.z, { id = 5, count = 3, damage = 0 })
      game:dropStack(e.x, e.y + 0.5, e.z, { id = 280, count = 2, damage = 0 })
    else
      game:dropStack(e.x, e.y + 0.5, e.z, { id = 333, count = 1, damage = 0 })
    end
  else
    game:dropStack(e.x, e.y + 0.5, e.z, { id = 328, count = 1, damage = 0 })
  end
end

function V.attack(game, e)
  e.damage = e.damage + 10
  e.hurtTime = 10
  game:emit("sound", "dig_wood", e.x, e.y, e.z)
  if e.damage > 40 or game.player.gameMode == "creative" then V.destroy(game, e, false) end
end

function V.mount(game, e)
  if e.rider then return false end
  local p = game.player
  e.rider = p
  p.riding = e
  p.vx, p.vy, p.vz = 0, 0, 0
  return true
end

function V.dismount(game)
  local p = game.player
  local e = p.riding
  if not e then return end
  e.rider = nil
  p.riding = nil
  -- wysiadanie obok pojazdu w wolnym miejscu
  local spots = { { 0, 1, 0 }, { 1, 0, 0 }, { -1, 0, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }
  for _, s in ipairs(spots) do
    local x, y, z = e.x + s[1] * 1.2, e.y + s[2] + 0.1, e.z + s[3] * 1.2
    if not physics.intersects(game.world, x - 0.3, y, z - 0.3, x + 0.3, y + 1.8, z + 0.3) then
      p.x, p.y, p.z = x, y, z
      break
    end
  end
  p.prevX, p.prevY, p.prevZ = p.x, p.y, p.z
  p.fallDistance = 0
end

-- Tick jazdy: gracz siedzi w pojeździe i przekazuje mu sterowanie
function V.tickRider(game)
  local p = game.player
  local e = p.riding
  if not e then return end
  if e.dead then
    p.riding = nil
    return
  end
  local inp = game.input
  if inp.sneak then
    V.dismount(game)
    return
  end
  p.prevX, p.prevY, p.prevZ = p.x, p.y, p.z
  p.prevWalkDist = p.walkDist
  if e.type == "boat" then
    e.input = { forward = inp.forward, strafe = inp.strafe }
  else
    local lx, lz = -math.sin(p.yaw), -math.cos(p.yaw)
    e.pushX, e.pushZ = lx * inp.forward, lz * inp.forward
  end
  p.fallDistance = 0
  p.onGround = true
  p.inWater = false
  p.headInWater = false
end

-- Po ruchu bytów: gracz podąża za pojazdem
function V.followVehicle(game)
  local p = game.player
  local e = p.riding
  if not e or e.dead then return end
  p.x, p.y, p.z = e.x, e.y + V.seatOffset(e) - 0.6, e.z
end

-- Postawienie wagonika/łódki z ręki
function V.placeFromItem(game, hit, itemId)
  if not hit then return false end
  local world = game.world
  if itemId == 328 then
    if not rails.isRail(hit.id) then return false end
    V.spawnMinecart(game, hit.x + 0.5, hit.y + 0.0625, hit.z + 0.5)
    game:consumeHeld(1)
    return true
  elseif itemId == 333 then
    local x, y, z = hit.x + 0.5, hit.y + 1, hit.z + 0.5
    local p = game.player
    V.spawnBoat(game, x, y, z, p.yaw)
    game:consumeHeld(1)
    return true
  end
  local _ = world
  return false
end

-- Celowanie w łódkę na wodzie (raycast przez ciecz)
function V.waterHit(game)
  local raycast = require("core.raycast")
  local p = game.player
  local ex, ey, ez = p:eyePosition()
  local lx, ly, lz = p:lookVector()
  return raycast.cast(game.world, ex, ey, ez, lx, ly, lz, game:reach(), function(def, _, meta)
    return (def.liquid == "water" and meta == 0) or def.selectable
  end)
end

local _ = blocks
return V
