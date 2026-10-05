-- core/mobs.lua
-- Moby, walka, pociski i wybuchy.
--  Zwierzęta: świnia, krowa, owca, kurczak, wilk (oswajany kością)
--  Potwory:   zombie, szkielet (łuk), pająk (skacze, wspina się),
--             creeper (wybucha), enderman (teleport, patrzenie mu w oczy)
--  AI: proste maszyny stanów + omijanie przeszkód skokiem i unikanie
--  urwisk ("uproszczony pathfinding"), spawn w ciemności, despawn z daleka.

local physics = require("core.physics")
local blocks = require("core.blocks")
local items = require("core.items")
local entities = require("core.entities")
local raycast = require("core.raycast")

local M = {}

local floor, sqrt, abs, min, max = math.floor, math.sqrt, math.abs, math.min, math.max
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local defs = blocks.defs

-- ---------------------------------------------------------------------------
-- Definicje mobów
-- ---------------------------------------------------------------------------
M.DEFS = {
  pig = { label = "Swinia", w = 0.9, h = 0.9, health = 10, speed = 0.09, passive = true,
    food = 296, xp = { 1, 3 },
    drops = function(rng, burning) return { { burning and 320 or 319, rng:int(1, 3) } } end },
  cow = { label = "Krowa", w = 0.9, h = 1.3, health = 10, speed = 0.08, passive = true,
    food = 296, xp = { 1, 3 },
    drops = function(rng, burning)
      return { { 334, rng:int(0, 2) }, { burning and 364 or 363, rng:int(1, 3) } }
    end },
  sheep = { label = "Owca", w = 0.9, h = 1.3, health = 8, speed = 0.08, passive = true,
    food = 296, xp = { 1, 3 },
    drops = function(rng, _, e)
      if e.sheared then return {} end
      return { { 35, 1, e.color or 0 } }
    end },
  chicken = { label = "Kurczak", w = 0.4, h = 0.7, health = 4, speed = 0.08, passive = true,
    food = 295, xp = { 1, 3 },
    drops = function(rng, burning)
      return { { 288, rng:int(0, 2) }, { burning and 366 or 365, 1 } }
    end },
  wolf = { label = "Wilk", w = 0.6, h = 0.85, health = 8, speed = 0.11, passive = true,
    neutral = true, damage = 2, xp = { 1, 3 }, drops = function() return {} end },
  zombie = { label = "Zombie", w = 0.6, h = 1.8, health = 20, speed = 0.1, hostile = true,
    damage = { 2, 3, 4 }, burns = true, xp = { 5, 5 },
    drops = function(rng) return { { 367, rng:int(0, 2) } } end },
  skeleton = { label = "Szkielet", w = 0.6, h = 1.8, health = 20, speed = 0.11,
    hostile = true, ranged = true, burns = true, xp = { 5, 5 },
    drops = function(rng) return { { 352, rng:int(0, 2) }, { 262, rng:int(0, 2) } } end },
  spider = { label = "Pajak", w = 1.4, h = 0.9, health = 16, speed = 0.14, hostile = true,
    damage = { 2, 2, 3 }, climbs = true, xp = { 5, 5 },
    drops = function(rng, _, e)
      local list = { { 287, rng:int(0, 2) } }
      if (e.lastHitByPlayer or 0) > 0 and rng:chance(1 / 3) then list[2] = { 375, 1 } end
      return list
    end },
  creeper = { label = "Creeper", w = 0.6, h = 1.7, health = 20, speed = 0.1, hostile = true,
    explodes = true, xp = { 5, 5 },
    drops = function(rng) return { { 289, rng:int(0, 2) } } end },
  pigman = { label = "Zombie pigman", w = 0.6, h = 1.8, health = 20, speed = 0.1, hostile = true,
    neutral = true, damage = { 5, 7, 9 }, xp = { 5, 5 }, nether = true,
    drops = function(rng) return { { 367, rng:int(0, 1) }, { 320, rng:int(0, 1) } } end },
  ghast = { label = "Ghast", w = 4, h = 4, health = 10, speed = 0.05, hostile = true, flying = true,
    xp = { 5, 5 }, nether = true, fireImmune = true,
    drops = function(rng) return { { 289, rng:int(0, 2) }, { 370, rng:int(0, 1) } } end },
  blaze = { label = "Plomyk", w = 0.6, h = 1.8, health = 20, speed = 0.06, hostile = true, flying = true,
    xp = { 10, 10 }, nether = true, fireImmune = true,
    drops = function(rng) return { { 369, rng:int(0, 1) } } end },
  dragon = { label = "Smok Endu", w = 6, h = 6, health = 200, speed = 0.6, hostile = true, flying = true,
    fireImmune = true, noclip = true, boss = true, xp = { 0, 0 }, drops = function() return {} end },
  enderman = { label = "Enderman", w = 0.6, h = 2.9, health = 40, speed = 0.15, hostile = true,
    neutral = true, damage = { 4, 7, 10 }, teleports = true, xp = { 5, 5 },
    drops = function(rng) return { { 368, rng:int(0, 1) } } end },
}
local DEFS = M.DEFS

-- Perła Endu (drop endermana): rzut teleportuje gracza
if not items.defs[368] then
  items.define { id = 368, name = "ender_pearl", label = "Perla Endu", icon = "ender_pearl",
    stack = 16, use = "throw" }
end

function M.init(game)
  game.mobState = { spawnTimer = 0, passiveTimer = 0 }
  game.biomeAt = game.biomeAt or nil
end

-- ---------------------------------------------------------------------------
-- Tworzenie moba
-- ---------------------------------------------------------------------------
function M.spawn(game, kind, x, y, z)
  local d = DEFS[kind]
  local e = entities.base("mob", x, y, z, d.w, d.h)
  e.kind = kind
  e.def = d
  e.label = d.label
  e.isMob = true
  e.health = d.health
  e.maxHealth = d.health
  e.stepHeight = 0.5
  e.hurtTime, e.invulnerable, e.deathTime = 0, 0, 0
  e.attackCooldown = 0
  e.state = "idle"
  e.stateTimer = 0
  e.yaw = game.rng:next() * math.pi * 2
  e.prevYaw = e.yaw
  e.limb, e.limbSpeed = 0, 0
  e.fireTicks = 0
  e.age = 0
  e.persistent = d.passive -- zwierzęta nie znikają
  if kind == "sheep" then
    local r = game.rng:next()
    e.color = r < 0.82 and 0 or (r < 0.9 and 5 or (r < 0.95 and 4 or 3))
  end
  if kind == "chicken" then e.eggTimer = game.rng:int(6000, 12000) end
  if kind == "creeper" then e.fuse = 0 end
  return game.entities:add(e)
end

local function isBaby(e) return e.growth and e.growth < 0 end
M.isBaby = isBaby

-- ---------------------------------------------------------------------------
-- Pomocnicze
-- ---------------------------------------------------------------------------
local function dist2(a, b)
  local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
  return dx * dx + dy * dy + dz * dz
end

local function difficultyDamage(game, dmg)
  if type(dmg) == "table" then
    local d = game.difficulty
    if d <= 1 then return dmg[1] end
    if d == 2 then return dmg[2] end
    return dmg[3]
  end
  return dmg or 1
end

-- Czy mob widzi punkt (brak litych bloków po drodze)
local function canSee(game, e, tx, ty, tz)
  local ex, ey, ez = e.x, e.y + e.height * 0.85, e.z
  local dx, dy, dz = tx - ex, ty - ey, tz - ez
  local d = sqrt(dx * dx + dy * dy + dz * dz)
  if d < 0.01 then return true end
  local hit = raycast.cast(game.world, ex, ey, ez, dx, dy, dz, d, function(def)
    return def.opaque and def.shape == "cube"
  end)
  return hit == nil
end
M.canSee = canSee

local function faceTowards(e, tx, tz, rate)
  local want = atan2(-(tx - e.x), -(tz - e.z))
  local diff = (want - e.yaw + math.pi) % (2 * math.pi) - math.pi
  rate = rate or 0.3
  if diff > rate then diff = rate elseif diff < -rate then diff = -rate end
  e.yaw = e.yaw + diff
end

-- Czy przed mobem jest urwisko (> 3 bloki w dół) albo lawa
local function dangerAhead(game, e, dx, dz)
  local w = game.world
  local fx, fz = floor(e.x + dx * 1.2), floor(e.z + dz * 1.2)
  local y = floor(e.y)
  for d = 0, 3 do
    local b = w:getBlock(fx, y - d - 1, fz)
    if b == 10 then return true end
    if blocks.SOLID[b] == 1 or b == 8 then return false end
  end
  return true
end

-- Ruch w stronę (dx, dz) z prędkością speed; skok przy przeszkodzie
local function moveTowards(game, e, dx, dz, speed, careful)
  local len = sqrt(dx * dx + dz * dz)
  if len > 0.001 then
    dx, dz = dx / len, dz / len
    if careful and e.onGround and dangerAhead(game, e, dx, dz) then
      dx, dz = 0, 0
    end
    local k = e.onGround and 0.4 or 0.08
    if e.inWater then k = 0.2 end
    if isBaby(e) then speed = speed * 1.3 end
    e.vx = e.vx + (dx * speed - e.vx) * k
    e.vz = e.vz + (dz * speed - e.vz) * k
  end
end

-- Fizyka moba (grawitacja, woda, wspinanie pająka)
local function physicsStep(game, e)
  local world = game.world
  if e.def.noclip then
    require("core.dragon").move(e)
    e.vx, e.vy, e.vz = e.vx * 0.98, e.vy * 0.98, e.vz * 0.98
    return
  end
  if e.def.flying and e.deathTime == 0 then
    physics.move(world, e, e.vx, e.vy, e.vz, false)
    e.vx, e.vy, e.vz = e.vx * 0.9, e.vy * 0.9, e.vz * 0.9
    return
  end
  e.inWater = physics.inLiquid(world, e, "water")
  e.inLava = physics.inLiquid(world, e, "lava")
  if e.inWater or e.inLava then
    e.vy = e.vy * 0.8 - 0.02
    -- pływanie: utrzymuj się na powierzchni
    if physics.pointInLiquid(world, e.x, e.y + e.height * 0.7, e.z, "water") or e.inLava then
      e.vy = e.vy + 0.05
    end
  else
    e.vy = (e.vy - 0.08) * 0.98
  end
  if e.kind == "chicken" and not e.onGround and e.vy < -0.1 then
    e.vy = e.vy * 0.6 -- kurczak trzepocze skrzydłami
  end
  local wasOnGround = e.onGround
  local mx, my, mz, wx, wy, wz = physics.move(world, e, e.vx, e.vy, e.vz, false)
  if my ~= wy then e.vy = 0 end
  if mx ~= wx then e.vx = 0 end
  if mz ~= wz then e.vz = 0 end
  -- skok przy przeszkodzie
  if e.collidedH and (e.onGround or e.inWater) and (abs(wx) > 0.01 or abs(wz) > 0.01) then
    e.vy = e.inWater and 0.3 or 0.42
  end
  if e.def.climbs and e.collidedH then e.vy = 0.2 end
  -- obrażenia od upadku
  if e.onGround then
    if (e.fall or 0) > 3 and not e.def.climbs and e.kind ~= "chicken" then
      M.damageMob(game, e, math.ceil(e.fall - 3), "fall")
    end
    e.fall = 0
  elseif my < 0 and not e.inWater then
    e.fall = (e.fall or 0) - my
  end
  if e.inWater then e.fall = 0 end
  local f = e.onGround and 0.6 * 0.91 or 0.91
  if e.onGround then
    e.vx, e.vz = e.vx * 0.85, e.vz * 0.85
  else
    e.vx, e.vz = e.vx * f, e.vz * f
  end
  -- animacja nóg
  local hd = sqrt((e.x - e.prevX) ^ 2 + (e.z - e.prevZ) ^ 2)
  e.limbSpeed = e.limbSpeed + (min(1, hd * 4) - e.limbSpeed) * 0.4
  e.limb = e.limb + e.limbSpeed
  local _ = wasOnGround
end

-- ---------------------------------------------------------------------------
-- Obrażenia mobów
-- ---------------------------------------------------------------------------
function M.damageMob(game, e, amount, source, attacker)
  if e.dead or e.health <= 0 then return false end
  if e.invulnerable > 10 then
    if amount <= (e.lastDamage or 0) then return false end
    amount = amount - e.lastDamage
  else
    e.lastDamage = amount
    e.invulnerable = 20
    e.hurtTime = 10
  end
  e.health = e.health - amount
  game:emit("sound", "mob_hurt", e.x, e.y + e.height / 2, e.z, e.kind)
  if attacker then
    local dx, dz = e.x - attacker.x, e.z - attacker.z
    local d = sqrt(dx * dx + dz * dz)
    if d > 0.01 then
      local kb = 0.4 * (attacker.knockback or 1)
      e.vx = e.vx / 2 + dx / d * kb
      e.vz = e.vz / 2 + dz / d * kb
      e.vy = min(0.4, e.vy / 2 + 0.4)
    end
    if attacker == game.player then e.lastHitByPlayer = 100 end
    -- reakcje
    if e.def.passive and not e.def.neutral then
      e.state, e.stateTimer = "panic", 60
    elseif e.def.neutral or e.kind == "spider" then
      e.angry = attacker
      e.target = attacker
    end
    if e.kind == "pigman" and attacker == game.player then
      for _, o in ipairs(game.entities:near(e.x, e.y, e.z, 32, "mob")) do
        if o.kind == "pigman" then o.angry = game.player end
      end
    end
    if e.def.teleports then M.teleportRandom(game, e) end
  end
  if e.health <= 0 then
    e.deathTime = 1
    game:emit("sound", "mob_death", e.x, e.y + e.height / 2, e.z, e.kind)
  end
  return true
end

local function dropLoot(game, e)
  local d = e.def
  if isBaby(e) then return end
  local burning = e.fireTicks > 0
  -- Grabież: więcej łupów
  local looting = (e.lastHitByPlayer or 0) > 0 and (e.looting or 0) or 0
  for _, s in ipairs(d.drops(game.rng, burning, e) or {}) do
    local n = s[2]
    if looting > 0 then n = n + game.rng:int(0, looting) end
    if n > 0 then
      game:dropStack(e.x, e.y + 0.5, e.z, { id = s[1], count = n, damage = s[3] or 0 })
    end
  end
  if (e.lastHitByPlayer or 0) > 0 then
    local xp = game.rng:int(d.xp[1], d.xp[2])
    if xp > 0 then game:spawnXp(e.x, e.y + 0.5, e.z, xp) end
  end
end

-- ---------------------------------------------------------------------------
-- Atak gracza
-- ---------------------------------------------------------------------------
-- Siła / osłabienie z mikstur
function M.effectAttackBonus(game)
  local fx = game.effects or {}
  local b = 0
  if fx.strength then b = b + 3 * (fx.strength.amp + 1) end
  if fx.weakness then b = b - 2 * (fx.weakness.amp + 1) end
  return b
end

function M.playerAttack(game, e)
  local p = game.player
  if e.isCrystal then
    require("core.dragon").destroyCrystal(game, e)
    return
  end
  if e.isVehicle then
    require("core.vehicles").attack(game, e)
    return
  end
  local held = game:heldStack()
  local enchant = require("core.enchant")
  local dmg = items.attackDamage(held) + M.effectAttackBonus(game)
  -- cios krytyczny: w trakcie opadania (Beta 1.8)
  local crit = p.vy < 0 and not p.onGround and not p.inWater and p.fallDistance > 0
  if crit then
    dmg = dmg + game.rng:int(0, floor(dmg / 2) + 1)
    game:emit("particles", "crit", e.x, e.y + e.height * 0.7, e.z)
  end
  local bonus = enchant.attackBonus(held, e)
  if bonus > 0 then
    dmg = dmg + bonus
    game:emit("particles", "magic_crit", e.x, e.y + e.height * 0.7, e.z)
  end
  dmg = math.max(0, dmg)
  local attacker = { x = p.x, z = p.z,
    knockback = (p.sprinting and 2 or 1) + enchant.level(held, "knockback") }
  if M.damageMob(game, e, dmg, "player", attacker) then
    e.lastHitByPlayer = 100
    e.looting = enchant.level(held, "looting")
    local fire = enchant.level(held, "fire_aspect")
    if fire > 0 then e.fireTicks = math.max(e.fireTicks or 0, 80 * fire) end
    if e.def.neutral then e.angry = game.player; e.target = game.player end
    if e.kind == "wolf" and not e.tamed then e.angry = game.player end
    local hd = held and items.get(held.id)
    if hd and hd.maxDamage then game:damageHeld(hd.toolType == "sword" and 1 or 2) end
    game.survival.addExhaustion(game, 0.3)
    if p.sprinting then p.sprinting = false end
  end
end

-- Czy gracz celuje w moba (promień do AABB, bliżej niż blok)
function M.pickEntity(game, maxDist)
  local p = game.player
  local ex, ey, ez = p:eyePosition()
  local lx, ly, lz = p:lookVector()
  local best, bestD = nil, maxDist
  for _, e in ipairs(game.entities.list) do
    if (e.isMob and not e.dead and e.health > 0) or (e.isVehicle and not e.dead and e ~= p.riding)
      or (e.isCrystal and not e.dead) then
      local hw = e.width / 2 + 0.1
      local d = raycast.rayBox(ex, ey, ez, lx, ly, lz,
        e.x - hw, e.y - 0.1, e.z - hw, e.x + hw, e.y + e.height + 0.1, e.z + hw)
      if d and d >= 0 and d < bestD then best, bestD = e, d end
    end
  end
  return best
end

-- Prawy przycisk na mobie: karmienie, strzyżenie, dojenie, oswajanie
function M.interact(game, e)
  if e.isVehicle then
    return require("core.vehicles").mount(game, e)
  end
  local held = game:heldStack()
  local p = game.player
  local d = e.def
  if not held then
    if e.kind == "wolf" and e.tamed then
      e.sitting = not e.sitting
      return true
    end
    return false
  end
  local hd = items.get(held.id)
  if e.kind == "sheep" and hd and hd.toolType == "shears" and not e.sheared and not isBaby(e) then
    e.sheared = true
    for _ = 1, game.rng:int(1, 3) do
      game:dropStack(e.x, e.y + 1, e.z, { id = 35, count = 1, damage = e.color or 0 })
    end
    game:damageHeld(1)
    game:emit("sound", "shear", e.x, e.y + 1, e.z)
    return true
  end
  if e.kind == "cow" and held.id == 325 then
    game:consumeHeld(1)
    game:giveItem(items.newStack(335))
    return true
  end
  if e.kind == "wolf" then
    if not e.tamed and held.id == 352 then
      game:consumeHeld(1)
      if game.rng:chance(1 / 3) then
        e.tamed = true
        e.owner = p
        e.maxHealth, e.health = 20, 20
        e.angry = nil
        game:emit("particles", "heart", e.x, e.y + 1, e.z)
      else
        game:emit("particles", "smoke", e.x, e.y + 1, e.z)
      end
      return true
    end
    if e.tamed and hd and hd.food and (held.id == 319 or held.id == 320 or held.id == 363
      or held.id == 364 or held.id == 365 or held.id == 366 or held.id == 367) then
      if e.health < e.maxHealth then
        e.health = min(e.maxHealth, e.health + hd.food.hunger)
        game:consumeHeld(1)
        return true
      end
    end
    return false
  end
  -- rozmnażanie i karmienie młodych
  if d.food and held.id == d.food then
    if isBaby(e) then
      e.growth = min(0, e.growth + floor(-e.growth * 0.1))
      game:consumeHeld(1)
      return true
    end
    if (e.love or 0) <= 0 and (e.breedCooldown or 0) <= 0 then
      e.love = 600
      game:consumeHeld(1)
      game:emit("particles", "heart", e.x, e.y + e.height, e.z)
      return true
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Pociski
-- ---------------------------------------------------------------------------
function M.shootArrow(game, power)
  local p = game.player
  local ex, ey, ez = p:eyePosition()
  local lx, ly, lz = p:lookVector()
  local speed = power * 3
  local a = entities.newArrow(ex + lx * 0.5, ey - 0.1 + ly * 0.5, ez + lz * 0.5,
    lx * speed, ly * speed, lz * speed, p, 2)
  a.crit = power >= 1
  a.fromPlayer = true
  -- zaklęcia łuku
  local enchant = require("core.enchant")
  local bow = game:heldStack()
  local pw = enchant.level(bow, "power")
  if pw > 0 then a.damage = a.damage + pw * 0.5 + 0.5 end
  a.punch = enchant.level(bow, "punch")
  if enchant.level(bow, "flame") > 0 then a.flame = true end
  if game.noArrowPickup then a.fromPlayer = false end
  game.entities:add(a)
  game:emit("sound", "bow", p.x, p.y + 1.5, p.z)
end

function M.throwItem(game, id)
  local p = game.player
  local ex, ey, ez = p:eyePosition()
  local lx, ly, lz = p:lookVector()
  local kind = id == 332 and "snowball" or (id == 344 and "egg" or "pearl")
  local t = entities.newThrown(kind, ex + lx * 0.3, ey - 0.1, ez + lz * 0.3,
    lx * 1.5, ly * 1.5 + 0.1, lz * 1.5, p)
  game.entities:add(t)
  game:emit("sound", "throw", p.x, p.y + 1.5, p.z)
end

-- Trafienie pociskiem w byt (gracz lub mob) na drodze ruchu
local function projectileHit(game, a)
  local x0, y0, z0 = a.x, a.y, a.z
  local dx, dy, dz = a.vx, a.vy, a.vz
  local len = sqrt(dx * dx + dy * dy + dz * dz)
  if len < 1e-4 then return nil end
  local best, bestT = nil, 1
  local function test(e)
    local hw = e.width / 2 + 0.15
    local t = raycast.rayBox(x0, y0, z0, dx / len, dy / len, dz / len,
      e.x - hw, e.y, e.z - hw, e.x + hw, e.y + e.height, e.z + hw)
    if t and t >= 0 and t <= len and t / len < bestT then best, bestT = e, t / len end
  end
  for _, e in ipairs(game.entities.list) do
    if (e.isMob and not e.dead and e.health > 0 and e ~= a.shooter) or (e.isCrystal and not e.dead) then test(e) end
  end
  if a.shooter ~= game.player and not game.dead then test(game.player) end
  return best, bestT
end

local function stepProjectile(game, a, gravity, drag)
  local target = projectileHit(game, a)
  -- blok na drodze
  local len = sqrt(a.vx * a.vx + a.vy * a.vy + a.vz * a.vz)
  local hit = raycast.cast(game.world, a.x, a.y, a.z, a.vx, a.vy, a.vz, len, function(def)
    return def.solid
  end)
  if target and (not hit or dist2(target, a) < (hit.dist * hit.dist + 1)) then
    return "entity", target
  end
  if hit then
    a.x, a.y, a.z = hit.hx - a.vx / len * 0.05, hit.hy - a.vy / len * 0.05, hit.hz - a.vz / len * 0.05
    return "block", hit
  end
  a.x, a.y, a.z = a.x + a.vx, a.y + a.vy, a.z + a.vz
  a.vx, a.vy, a.vz = a.vx * drag, a.vy * drag - gravity, a.vz * drag
  if physics.pointInLiquid(game.world, a.x, a.y, a.z, "water") then
    a.vx, a.vy, a.vz = a.vx * 0.8, a.vy * 0.8, a.vz * 0.8
  end
  a.yaw = atan2(-a.vx, -a.vz)
  return nil
end

entities.TICK.arrow = function(game, a)
  if a.stuck then
    if a.age > 1200 then a.dead = true end
    -- podniesienie strzały wystrzelonej przez gracza
    if a.fromPlayer and not game.dead then
      local p = game.player
      if abs(p.x - a.x) < 1.2 and abs(p.z - a.z) < 1.2 and abs(p.y + 0.9 - a.y) < 1.4 then
        if game.player.gameMode ~= "creative" then
          if game:addToInventory({ id = 262, count = 1, damage = 0 }) == 0 then a.dead = true end
        else
          a.dead = true
        end
        if a.dead then game:emit("sound", "pop", a.x, a.y, a.z) end
      end
    end
    return
  end
  local kind, what = stepProjectile(game, a, 0.05, 0.99)
  if kind == "entity" then
    local speed = sqrt(a.vx * a.vx + a.vy * a.vy + a.vz * a.vz)
    local dmg = math.ceil(speed * a.damage)
    if a.crit then dmg = dmg + game.rng:int(0, floor(dmg / 2) + 1) end
    if what.isCrystal then
      require("core.dragon").destroyCrystal(game, what)
    elseif what == game.player then
      game.survival.damage(game, dmg, "arrow", a.shooter)
    else
      M.damageMob(game, what, dmg, "arrow", { x = a.x - a.vx, z = a.z - a.vz,
        knockback = 1 + (a.punch or 0) * 1.5 })
      if a.fromPlayer or a.shooter == game.player then what.lastHitByPlayer = 100 end
      if a.flame then what.fireTicks = math.max(what.fireTicks or 0, 100) end
    end
    game:emit("sound", "arrow_hit", a.x, a.y, a.z)
    a.dead = true
  elseif kind == "block" then
    a.stuck = true
    a.age = 0
    game:emit("sound", "arrow_hit", a.x, a.y, a.z)
  end
  if a.age > 1200 then a.dead = true end
end

local function thrownTick(game, t)
  local kind, what = stepProjectile(game, t, 0.03, 0.99)
  if kind then
    if kind == "entity" then
      if what == game.player then
        game.survival.damage(game, 0.01, "mob", t)
      else
        M.damageMob(game, what, t.type == "snowball" and 0 or 0, "throw", { x = t.x - t.vx, z = t.z - t.vz })
      end
    end
    if t.type == "egg" and game.rng:chance(1 / 8) then
      local c = M.spawn(game, "chicken", t.x, t.y, t.z)
      c.growth = -24000
    elseif t.type == "pearl" then
      local p = game.player
      p.x, p.y, p.z = t.x, t.y, t.z
      p.prevX, p.prevY, p.prevZ = t.x, t.y, t.z
      p.fallDistance = 0
      game.survival.damage(game, 5, "fall")
    end
    game:emit("particles", t.type == "egg" and "egg" or "snow", t.x, t.y, t.z)
    t.dead = true
  end
  if t.age > 400 then t.dead = true end
end
entities.TICK.snowball = thrownTick
entities.TICK.egg = thrownTick
entities.TICK.pearl = thrownTick

-- ---------------------------------------------------------------------------
-- Wybuch (TNT, creeper)
-- ---------------------------------------------------------------------------
function M.explode(game, x, y, z, power, source)
  local world = game.world
  local rng = game.rng
  local destroyed = {}
  local list = {}
  local N = 10
  for i = 0, N - 1 do
    for j = 0, N - 1 do
      for k = 0, N - 1 do
        if i == 0 or i == N - 1 or j == 0 or j == N - 1 or k == 0 or k == N - 1 then
          local dx, dy, dz = i / (N - 1) * 2 - 1, j / (N - 1) * 2 - 1, k / (N - 1) * 2 - 1
          local len = sqrt(dx * dx + dy * dy + dz * dz)
          dx, dy, dz = dx / len * 0.3, dy / len * 0.3, dz / len * 0.3
          local intensity = power * (0.7 + rng:next() * 0.6)
          local px, py, pz = x, y, z
          while intensity > 0 do
            local bx, by, bz = floor(px), floor(py), floor(pz)
            local id = world:getBlock(bx, by, bz)
            if id ~= 0 then
              local d = defs[id]
              local res = d and d.resistance or 1
              intensity = intensity - (res + 0.3) * 0.3
            end
            if intensity > 0 and id ~= 0 and by >= 0 and by < 128 then
              local key = bx .. "," .. by .. "," .. bz
              if not destroyed[key] then
                destroyed[key] = true
                list[#list + 1] = { bx, by, bz, id }
              end
            end
            px, py, pz = px + dx, py + dy, pz + dz
            intensity = intensity - 0.225
          end
        end
      end
    end
  end

  -- bloki: TNT odpala się łańcuchowo, reszta znika (część daje drop)
  for _, b in ipairs(list) do
    local bx, by, bz, id = b[1], b[2], b[3], b[4]
    local d = defs[id]
    if id == 46 then
      game:primeTnt(bx, by, bz, rng:int(10, 30))
    elseif d and not d.liquid then
      if rng:chance(1 / power) and game.player.gameMode then
        local drops = d.drops and d.drops(world:getMeta(bx, by, bz), rng)
          or { { id = id, count = 1, damage = 0 } }
        for _, s in ipairs(drops or {}) do
          if s.count > 0 then game:dropStack(bx + 0.5, by + 0.5, bz + 0.5, s) end
        end
      end
      -- zawartość skrzyń
      local tile = world:getTile(bx, by, bz)
      if tile and tile.inventory then
        for i = 1, tile.inventory.size do
          local s = tile.inventory.slots[i]
          if s then game:dropStack(bx + 0.5, by + 0.5, bz + 0.5, s) end
        end
      end
      world:setBlock(bx, by, bz, 0, 0)
    end
  end
  for _, b in ipairs(list) do game:notifyNeighbors(b[1], b[2], b[3]) end

  -- byty: obrażenia i odrzut
  local radius = power * 2
  local function affect(e, isPlayer)
    local ex, ey, ez = e.x, e.y + e.height / 2, e.z
    local dx, dy, dz = ex - x, ey - y, ez - z
    local dist = sqrt(dx * dx + dy * dy + dz * dz)
    if dist >= radius or dist < 0.001 then return end
    local impact = 1 - dist / radius
    local dmg = floor((impact * impact + impact) / 2 * 8 * power + 1)
    dx, dy, dz = dx / dist, dy / dist, dz / dist
    if isPlayer then
      if game.survival.damage(game, dmg, "explosion") or true then
        local p = game.player
        p.vx, p.vy, p.vz = p.vx + dx * impact, p.vy + dy * impact, p.vz + dz * impact
      end
    else
      if e.isMob then M.damageMob(game, e, dmg, "explosion") end
      e.vx, e.vy, e.vz = (e.vx or 0) + dx * impact, (e.vy or 0) + dy * impact,
        (e.vz or 0) + dz * impact
    end
  end
  if not game.dead then affect(game.player, true) end
  for _, e in ipairs(game.entities.list) do
    if e ~= source and not e.dead and e.type ~= "xp" then affect(e, false) end
  end
  game:emit("explosion", x, y, z, power)
end

-- ---------------------------------------------------------------------------
-- Piorun: naładowany creeper, ogień, obrażenia
-- ---------------------------------------------------------------------------
function M.lightningStrike(game, x, y, z)
  local w = game.world
  local bx, by, bz = floor(x), floor(y), floor(z)
  if w:getBlock(bx, by, bz) == 0 and blocks.OPAQUE[w:getBlock(bx, by - 1, bz)] == 1
    and game.difficulty > 0 then
    w:setBlock(bx, by, bz, 51, 0)
  end
  for _, e in ipairs(game.entities:near(x, y, z, 3)) do
    if e.isMob then
      if e.kind == "creeper" then e.charged = true end
      M.damageMob(game, e, 5, "lightning")
      e.fireTicks = 160
    end
  end
  local p = game.player
  if (p.x - x) ^ 2 + (p.z - z) ^ 2 < 9 and abs(p.y - y) < 4 then
    game.survival.damage(game, 5, "fire")
    game.fireTicks = 160
  end
end

function M.hostileNear(game, x, y, z, r)
  for _, e in ipairs(game.entities:near(x, y, z, r)) do
    if e.isMob and e.def.hostile and e.health > 0 then return true end
  end
  return false
end

function M.teleportRandom(game, e)
  for _ = 1, 16 do
    local tx = e.x + (game.rng:next() - 0.5) * 32
    local tz = e.z + (game.rng:next() - 0.5) * 32
    local bx, bz = floor(tx), floor(tz)
    if game.world:isLoadedAt(bx, bz) then
      local ty = game.world:getHeight(bx, bz)
      local below = game.world:getBlock(bx, ty - 1, bz)
      if blocks.SOLID[below] == 1 and not physics.intersects(game.world, tx - 0.3, ty, tz - 0.3,
        tx + 0.3, ty + e.height, tz + 0.3) then
        game:emit("particles", "portal", e.x, e.y + 1, e.z)
        e.x, e.y, e.z = tx, ty, tz
        e.prevX, e.prevY, e.prevZ = tx, ty, tz
        game:emit("sound", "teleport", tx, ty, tz)
        return true
      end
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- AI
-- ---------------------------------------------------------------------------
local function wander(game, e, speed)
  e.stateTimer = e.stateTimer - 1
  if e.stateTimer <= 0 then
    if game.rng:chance(0.6) then
      e.wanderX = e.x + (game.rng:next() - 0.5) * 16
      e.wanderZ = e.z + (game.rng:next() - 0.5) * 16
      e.stateTimer = game.rng:int(60, 160)
    else
      e.wanderX = nil
      e.stateTimer = game.rng:int(40, 120)
    end
  end
  if e.wanderX then
    local dx, dz = e.wanderX - e.x, e.wanderZ - e.z
    if dx * dx + dz * dz < 1 then
      e.wanderX = nil
    else
      faceTowards(e, e.wanderX, e.wanderZ, 0.2)
      moveTowards(game, e, dx, dz, speed, true)
    end
  end
end

local function passiveAI(game, e)
  local d = e.def
  local p = game.player
  if e.love and e.love > 0 then e.love = e.love - 1 end
  if e.breedCooldown and e.breedCooldown > 0 then e.breedCooldown = e.breedCooldown - 1 end
  if e.growth and e.growth < 0 then e.growth = e.growth + 1 end

  if e.state == "panic" then
    e.stateTimer = e.stateTimer - 1
    if e.stateTimer <= 0 or not e.panicX then
      e.panicX = e.x + (game.rng:next() - 0.5) * 20
      e.panicZ = e.z + (game.rng:next() - 0.5) * 20
    end
    faceTowards(e, e.panicX, e.panicZ, 0.5)
    moveTowards(game, e, e.panicX - e.x, e.panicZ - e.z, d.speed * 1.8, true)
    if e.stateTimer <= 0 then e.state = "idle" end
    return
  end

  -- szukanie partnera
  if e.love and e.love > 0 then
    local mate
    for _, o in ipairs(game.entities:near(e.x, e.y, e.z, 8, "mob")) do
      if o ~= e and o.kind == e.kind and (o.love or 0) > 0 and not isBaby(o) then mate = o break end
    end
    if mate then
      faceTowards(e, mate.x, mate.z, 0.4)
      moveTowards(game, e, mate.x - e.x, mate.z - e.z, d.speed, true)
      if dist2(e, mate) < 2.5 then
        e.love, mate.love = 0, 0
        e.breedCooldown, mate.breedCooldown = 6000, 6000
        local baby = M.spawn(game, e.kind, (e.x + mate.x) / 2, e.y, (e.z + mate.z) / 2)
        baby.growth = -24000
        game:emit("particles", "heart", baby.x, baby.y + 0.5, baby.z)
        game:spawnXp(e.x, e.y + 0.5, e.z, game.rng:int(1, 7))
      end
      return
    end
  end

  -- podążanie za graczem z jedzeniem w ręku
  local held = game:heldStack()
  if d.food and held and held.id == d.food and not game.dead and dist2(e, p) < 100 then
    faceTowards(e, p.x, p.z, 0.4)
    if dist2(e, p) > 4 then moveTowards(game, e, p.x - e.x, p.z - e.z, d.speed, true) end
    return
  end

  -- owca je trawę i odrasta jej wełna
  if e.kind == "sheep" and game.rng:chance(1 / 1000) then
    local bx, by, bz = floor(e.x), floor(e.y) - 1, floor(e.z)
    if game.world:getBlock(bx, by, bz) == 2 then
      game.world:setBlock(bx, by, bz, 3, 0)
      e.sheared = false
      if isBaby(e) then e.growth = min(0, e.growth + 1200) end
    end
  end
  -- kurczak znosi jajka
  if e.kind == "chicken" and not isBaby(e) then
    e.eggTimer = e.eggTimer - 1
    if e.eggTimer <= 0 then
      game:dropStack(e.x, e.y + 0.3, e.z, { id = 344, count = 1, damage = 0 })
      game:emit("sound", "pop", e.x, e.y, e.z)
      e.eggTimer = game.rng:int(6000, 12000)
    end
  end
  wander(game, e, d.speed * 0.7)
end

local function wolfAI(game, e)
  local p = game.player
  if e.tamed then
    if e.sitting then return end
    -- atakuj cel gracza
    local target = e.target
    if target and (target.dead or target.health <= 0) then target = nil; e.target = nil end
    if target then
      faceTowards(e, target.x, target.z, 0.5)
      moveTowards(game, e, target.x - e.x, target.z - e.z, e.def.speed * 1.4, false)
      if dist2(e, target) < 2.5 and e.attackCooldown <= 0 then
        M.damageMob(game, target, 4, "mob", e)
        e.attackCooldown = 20
      end
      return
    end
    local d2 = dist2(e, p)
    if d2 > 144 and not game.dead then
      -- teleport do właściciela
      e.x, e.y, e.z = p.x + 1, p.y, p.z + 1
      e.prevX, e.prevY, e.prevZ = e.x, e.y, e.z
    elseif d2 > 9 then
      faceTowards(e, p.x, p.z, 0.4)
      moveTowards(game, e, p.x - e.x, p.z - e.z, e.def.speed * 1.2, true)
    else
      wander(game, e, e.def.speed * 0.4)
    end
    return
  end
  if e.angry and not game.dead then
    faceTowards(e, p.x, p.z, 0.5)
    moveTowards(game, e, p.x - e.x, p.z - e.z, e.def.speed * 1.4, false)
    if dist2(e, p) < 2.5 and e.attackCooldown <= 0 then
      game.survival.damage(game, difficultyDamage(game, { 2, 3, 4 }), "mob", e)
      e.attackCooldown = 20
    end
    return
  end
  wander(game, e, e.def.speed * 0.6)
end

local function hostileAI(game, e)
  local d = e.def
  local p = game.player
  local world = game.world

  -- palenie się w słońcu
  if d.burns and game.dimension == "overworld" and game:daylight() > 0.6 and not e.inWater then
    local bx, by, bz = floor(e.x), floor(e.y + e.height - 0.2), floor(e.z)
    if world:getSkyLight(bx, by, bz) >= 15 and not game:isRainingAt(e.x, e.y + 1, e.z)
      and game.rng:chance(0.05) then
      e.fireTicks = 160
    end
  end

  -- pająk w dzień jest neutralny
  local aggressive = true
  if e.kind == "spider" and not e.angry then
    local l = game:lightAt(floor(e.x), floor(e.y + 0.5), floor(e.z))
    if l > 11 then aggressive = false end
  end
  if d.neutral and not e.angry then aggressive = false end

  -- enderman: złości się, gdy gracz patrzy mu w oczy
  if e.kind == "enderman" and not e.angry and not game.dead and e.age % 5 == 0 then
    local ex, ey, ez = p:eyePosition()
    local lx, ly, lz = p:lookVector()
    local dx, dy, dz = e.x - ex, e.y + 2.6 - ey, e.z - ez
    local dd = sqrt(dx * dx + dy * dy + dz * dz)
    if dd < 32 and (dx * lx + dy * ly + dz * lz) / dd > 1 - 0.025 / dd * 4
      and canSee(game, e, ex, ey, ez) then
      e.angry = p
      game:emit("sound", "enderman_stare", e.x, e.y + 2, e.z)
    end
  end
  if e.kind == "enderman" then
    if (e.inWater or game:isRainingAt(e.x, e.y + 2, e.z)) and game.rng:chance(0.1) then
      M.teleportRandom(game, e)
    end
    if e.angry and dist2(e, p) > 64 and game.rng:chance(0.02) then
      -- skok bliżej gracza
      local ox, oz = e.x, e.z
      e.x, e.z = p.x + (e.x - p.x) * 0.3, p.z + (e.z - p.z) * 0.3
      if not M.teleportRandom(game, { x = e.x, y = e.y, z = e.z, height = e.height }) then
        e.x, e.z = ox, oz
      end
    end
  end

  local target = nil
  if aggressive and not game.dead and game.player.gameMode ~= "creative" then
    local d2 = dist2(e, p)
    if d2 < 256 or (e.target == p and d2 < 1024) then
      if e.age % 10 == 0 then
        local ex, ey, ez = p:eyePosition()
        e.seesTarget = canSee(game, e, ex, ey, ez)
      end
      if e.seesTarget or e.target == p then target = p end
    end
  end
  e.target = target

  if not target then
    if e.kind == "creeper" and e.fuse > 0 then e.fuse = e.fuse - 1 end
    wander(game, e, d.speed * 0.6)
    return
  end

  local dx, dz = target.x - e.x, target.z - e.z
  local dist = sqrt(dx * dx + dz * dz + (target.y - e.y) ^ 2)
  faceTowards(e, target.x, target.z, 0.5)

  if e.kind == "creeper" then
    if dist < 3 and e.seesTarget then
      if e.fuse == 0 then game:emit("sound", "fuse", e.x, e.y + 1, e.z) end
      e.fuse = e.fuse + 1
      if e.fuse >= 30 then
        e.dead = true
        M.explode(game, e.x, e.y + 0.5, e.z, e.charged and 6 or 3, e)
      end
      return
    elseif dist > 7 and e.fuse > 0 then
      e.fuse = e.fuse - 1
    elseif e.fuse > 0 and dist >= 3 then
      e.fuse = max(0, e.fuse - 1)
    end
    moveTowards(game, e, dx, dz, d.speed, false)
    return
  end

  if d.ranged then
    -- szkielet trzyma dystans i strzela
    if dist < 8 then
      moveTowards(game, e, -dx, -dz, d.speed * 0.6, true)
    elseif dist > 12 then
      moveTowards(game, e, dx, dz, d.speed, false)
    end
    if e.attackCooldown <= 0 and dist < 16 and e.seesTarget then
      local ey = e.y + 1.5
      local ty = target.y + 1.3
      local hd = sqrt(dx * dx + dz * dz)
      local vy = (ty - ey) + hd * 0.2
      local len = sqrt(dx * dx + vy * vy + dz * dz)
      local speed = 1.6
      local inacc = 0.08 * (4 - game.difficulty)
      local a = entities.newArrow(e.x + dx / hd * 0.5, ey, e.z + dz / hd * 0.5,
        dx / len * speed + (game.rng:next() - 0.5) * inacc,
        vy / len * speed + (game.rng:next() - 0.5) * inacc,
        dz / len * speed + (game.rng:next() - 0.5) * inacc, e, 2)
      game.entities:add(a)
      game:emit("sound", "bow", e.x, e.y + 1.5, e.z)
      e.attackCooldown = game.rng:int(40, 60)
    end
    return
  end

  -- pająk skacze na cel
  if e.kind == "spider" and dist > 2 and dist < 6 and e.onGround and game.rng:chance(0.1) then
    local hd = sqrt(dx * dx + dz * dz)
    e.vx = dx / hd * 0.4
    e.vz = dz / hd * 0.4
    e.vy = 0.4
  end

  moveTowards(game, e, dx, dz, d.speed * (e.kind == "enderman" and 1.4 or 1), false)

  -- atak wręcz
  local reach = e.width / 2 + 0.3 + 0.6
  local hx, hz = abs(target.x - e.x), abs(target.z - e.z)
  if hx < reach and hz < reach and abs(target.y - e.y) < 1.5 and e.attackCooldown <= 0 then
    game.survival.damage(game, difficultyDamage(game, d.damage), "mob", e)
    e.attackCooldown = 20
    e.swing = 8
  end
end

-- ---------------------------------------------------------------------------
-- Tick moba
-- ---------------------------------------------------------------------------
entities.TICK.mob = function(game, e)
  if e.hurtTime > 0 then e.hurtTime = e.hurtTime - 1 end
  if e.invulnerable > 0 then e.invulnerable = e.invulnerable - 1 end
  if e.attackCooldown > 0 then e.attackCooldown = e.attackCooldown - 1 end
  if e.swing and e.swing > 0 then e.swing = e.swing - 1 end
  if e.lastHitByPlayer and e.lastHitByPlayer > 0 then e.lastHitByPlayer = e.lastHitByPlayer - 1 end

  if e.deathTime > 0 and e.kind == "dragon" then
    require("core.dragon").dying(game, e)
    return
  end
  if e.deathTime > 0 then
    e.deathTime = e.deathTime + 1
    if e.deathTime >= 20 then
      e.dead = true
      dropLoot(game, e)
      game:emit("particles", "poof", e.x, e.y + e.height / 2, e.z)
    end
    physicsStep(game, e)
    return
  end

  -- ogień i lawa
  if e.inLava then
    if not e.def.fireImmune then M.damageMob(game, e, 4, "lava") end
    e.fireTicks = 300
  end
  if e.fireTicks > 0 then
    e.fireTicks = e.fireTicks - 1
    if e.inWater then e.fireTicks = 0 end
    if e.fireTicks % 20 == 0 and not e.def.fireImmune then M.damageMob(game, e, 1, "fire") end
  end
  if e.inWater and e.kind == "blaze" then M.damageMob(game, e, 1, "water") end
  if e.inWater and e.kind == "enderman" then M.damageMob(game, e, 1, "water") end
  if (e.poison or 0) > 0 then
    e.poison = e.poison - 1
    if e.poison % 25 == 0 and e.health > 1 then M.damageMob(game, e, 1, "poison") end
  end
  physics.touchingBlocks(game.world, e, function(id)
    if id == 81 then M.damageMob(game, e, 1, "cactus") end
  end)

  local d = e.def
  if e.kind == "wolf" then
    wolfAI(game, e)
  elseif e.kind == "blaze" then
    M.blazeAI(game, e)
  elseif e.kind == "dragon" then
    require("core.dragon").ai(game, e)
  elseif e.kind == "ghast" then
    M.ghastAI(game, e)
  elseif d.hostile then
    hostileAI(game, e)
  else
    passiveAI(game, e)
  end
  physicsStep(game, e)

  -- despawn potworów daleko od gracza
  if not e.persistent and not e.tamed then
    local d2 = dist2(e, game.player)
    if d2 > 128 * 128 then
      e.dead = true
    elseif d2 > 32 * 32 and game.rng:chance(1 / 800) then
      e.dead = true
    end
  end
  if game.difficulty == 0 and d.hostile and not d.boss then e.dead = true end
end

-- ---------------------------------------------------------------------------
-- Ghast: lata, strzela kulami ognia, które wybuchają i podpalają
-- ---------------------------------------------------------------------------
function M.ghastAI(game, e)
  local p = game.player
  e.stateTimer = e.stateTimer - 1
  if e.stateTimer <= 0 or not e.wanderX then
    e.wanderX = e.x + (game.rng:next() - 0.5) * 32
    e.wanderY = math.max(35, math.min(110, e.y + (game.rng:next() - 0.5) * 16))
    e.wanderZ = e.z + (game.rng:next() - 0.5) * 32
    e.stateTimer = game.rng:int(60, 160)
  end
  local dx, dy, dz = e.wanderX - e.x, e.wanderY - e.y, e.wanderZ - e.z
  local d = sqrt(dx * dx + dy * dy + dz * dz)
  if d > 1 then
    e.vx = e.vx + dx / d * 0.02
    e.vy = e.vy + dy / d * 0.02
    e.vz = e.vz + dz / d * 0.02
  end
  if e.collidedH then e.wanderX = nil end
  local tdx, tdz = p.x - e.x, p.z - e.z
  local dist = sqrt(tdx * tdx + tdz * tdz + (p.y - e.y) ^ 2)
  if dist < 64 and not game.dead and p.gameMode ~= "creative" then
    faceTowards(e, p.x, p.z, 0.3)
    if e.age % 10 == 0 then
      local ex, ey, ez = p:eyePosition()
      e.seesTarget = canSee(game, e, ex, ey, ez)
    end
    if e.seesTarget then
      e.charge = (e.charge or 0) + 1
      if e.charge == 10 then game:emit("sound", "voice_ghast", e.x, e.y + 2, e.z) end
      if e.charge >= 20 then
        e.charge = -40
        local sx, sy, sz = e.x, e.y + 2, e.z
        local fx, fy, fz = p.x - sx, p.y + 1 - sy, p.z - sz
        local fl = sqrt(fx * fx + fy * fy + fz * fz)
        local f = entities.newThrown("fireball", sx + fx / fl * 2.5, sy + fy / fl * 2.5, sz + fz / fl * 2.5,
          fx / fl * 0.6, fy / fl * 0.6, fz / fl * 0.6, e)
        game.entities:add(f)
        game:emit("sound", "bow", sx, sy, sz)
      end
    elseif (e.charge or 0) > 0 then
      e.charge = e.charge - 1
    end
  end
end

-- ---------------------------------------------------------------------------
-- Płomyk: unosi się nad ziemią i strzela seriami małych kul ognia
-- ---------------------------------------------------------------------------
function M.blazeAI(game, e)
  local p = game.player
  local world = game.world
  -- unoszenie: ok. 2 bloki nad podłożem, powoli opada
  local ground = floor(e.y)
  while ground > 0 and world:getBlock(floor(e.x), ground - 1, floor(e.z)) == 0 and e.y - ground < 6 do
    ground = ground - 1
  end
  local want = ground + 2 + math.sin((e.age + e.id) * 0.05) * 0.5
  local d = sqrt((p.x - e.x) ^ 2 + (p.z - e.z) ^ 2)
  if d < 32 and not game.dead and p.gameMode ~= "creative" then want = math.max(want, p.y + 1) end
  e.vy = e.vy + (want > e.y and 0.02 or -0.015)
  if e.vy > 0.15 then e.vy = 0.15 elseif e.vy < -0.15 then e.vy = -0.15 end
  if game.rng:chance(0.3) then game:emit("particles", "smoke", e.x, e.y + 1.2, e.z) end
  if d < 32 and not game.dead and p.gameMode ~= "creative" then
    faceTowards(e, p.x, p.z, 0.4)
    if d > 6 then moveTowards(game, e, p.x - e.x, p.z - e.z, e.def.speed, false) end
    if e.age % 10 == 0 then
      local ex, ey, ez = p:eyePosition()
      e.seesTarget = canSee(game, e, ex, ey, ez)
    end
    e.charge = (e.charge or 0) + 1
    -- seria 3 kul co ~5 sekund
    if e.seesTarget and d < 24 and e.charge >= 100 and e.charge % 6 == 0 then
      local sx, sy, sz = e.x, e.y + 1.4, e.z
      local fx, fy, fz = p.x - sx + (game.rng:next() - 0.5) * 1.5, p.y + 1 - sy, p.z - sz + (game.rng:next() - 0.5) * 1.5
      local fl = sqrt(fx * fx + fy * fy + fz * fz)
      local f = entities.newThrown("smallfireball", sx + fx / fl, sy + fy / fl, sz + fz / fl,
        fx / fl * 0.5, fy / fl * 0.5, fz / fl * 0.5, e)
      game.entities:add(f)
      game:emit("sound", "ignite", sx, sy, sz)
      if e.charge >= 112 then e.charge = 0 end
    end
  else
    wander(game, e, e.def.speed * 0.5)
  end
end

entities.TICK.smallfireball = function(game, f)
  local kind, what = stepProjectile(game, f, 0, 1.0)
  if game.rng:chance(0.4) then game:emit("particles", "flame", f.x, f.y, f.z) end
  if kind then
    f.dead = true
    if kind == "entity" and what == game.player then
      game.survival.damage(game, 5, "fire", f.shooter)
      if not game.effects.fire_resistance then game.fireTicks = math.max(game.fireTicks, 100) end
    elseif kind == "entity" and not what.def.fireImmune then
      M.damageMob(game, what, 5, "fire")
      what.fireTicks = 100
    elseif kind == "block" then
      local x, y, z = floor(f.x), floor(f.y), floor(f.z)
      if game.world:getBlock(x, y, z) == 0 and blocks.OPAQUE[game.world:getBlock(x, y - 1, z)] == 1 then
        game.world:setBlock(x, y, z, 51, 0)
      end
    end
  end
  if f.age > 200 then f.dead = true end
end

entities.TICK.fireball = function(game, f)
  local kind, what = stepProjectile(game, f, 0, 1.0)
  if game.rng:chance(0.5) then game:emit("particles", "flame", f.x, f.y, f.z) end
  if kind then
    f.dead = true
    if kind == "entity" and what == game.player then
      game.survival.damage(game, 4, "fire", f.shooter)
      game.fireTicks = 100
    elseif kind == "entity" then
      M.damageMob(game, what, 4, "fire")
    end
    M.explode(game, f.x, f.y, f.z, 1, f)
    -- podpalenie okolicy
    for _ = 1, 6 do
      local x = math.floor(f.x) + game.rng:int(-2, 2)
      local y = math.floor(f.y) + game.rng:int(-1, 1)
      local z = math.floor(f.z) + game.rng:int(-2, 2)
      if game.world:getBlock(x, y, z) == 0 and blocks.OPAQUE[game.world:getBlock(x, y - 1, z)] == 1 then
        game.world:setBlock(x, y, z, 51, 0)
      end
    end
  end
  if f.age > 300 then f.dead = true end
end

-- ---------------------------------------------------------------------------
-- Spawnowanie
-- ---------------------------------------------------------------------------
local HOSTILE_KINDS = { "zombie", "zombie", "skeleton", "skeleton", "spider", "creeper",
  "creeper", "enderman" }
local NETHER_KINDS = { "pigman", "pigman", "pigman", "pigman", "ghast", "blaze" }
local PASSIVE_KINDS = { "pig", "cow", "sheep", "sheep", "chicken", "wolf" }

local function canSpawnAt(game, x, y, z, w, h)
  local world = game.world
  local below = world:getBlock(x, y - 1, z)
  if blocks.OPAQUE[below] ~= 1 then return false end
  for dy = 0, math.ceil(h) - 1 do
    local b = world:getBlock(x, y + dy, z)
    if b ~= 0 and (blocks.SOLID[b] == 1 or (defs[b] and defs[b].liquid)) then return false end
  end
  if w > 1 then
    for _, o in ipairs({ { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
      if blocks.SOLID[world:getBlock(x + o[1], y, z + o[2])] == 1 then return false end
    end
  end
  return true
end

local function trySpawnHostile(game)
  local p = game.player
  local rng = game.rng
  local world = game.world
  local r = min(game.renderDistance, 8) * 16
  local x = floor(p.x) + rng:int(-r, r)
  local z = floor(p.z) + rng:int(-r, r)
  if not world:isLoadedAt(x, z) then return end
  local top = world:getHeight(x, z)
  local y = rng:int(1, max(2, top))
  if world:getBlock(x, y, z) ~= 0 then return end
  -- zejdź do podłoża
  while y > 1 and world:getBlock(x, y - 1, z) == 0 do y = y - 1 end
  local dx, dy, dz = x + 0.5 - p.x, y - p.y, z + 0.5 - p.z
  local d2 = dx * dx + dy * dy + dz * dz
  if d2 < 24 * 24 then return end
  local nether = game.dimension == "nether"
  if not nether and game:lightAt(x, y, z) > 7 then return end
  local kind = HOSTILE_KINDS[rng:int(1, #HOSTILE_KINDS)]
  if game.dimension == "end" then kind = "enderman" end
  if nether then
    kind = NETHER_KINDS[rng:int(1, #NETHER_KINDS)]
    if kind == "ghast" then
      -- ghast potrzebuje dużo miejsca w powietrzu
      local gy = y + 3
      for ox = -2, 2 do for oy = 0, 4 do for oz = -2, 2 do
        if world:getBlock(x + ox, gy + oy, z + oz) ~= 0 then return end
      end end end
      M.spawn(game, "ghast", x + 0.5, gy, z + 0.5)
      return
    end
  end
  if kind == "enderman" and rng:chance(0.7) and game.dimension ~= "end" then kind = "zombie" end
  local d = DEFS[kind]
  local group = rng:int(1, kind == "enderman" and 1 or 3)
  for _ = 1, group do
    local sx, sz = x + rng:int(-2, 2), z + rng:int(-2, 2)
    local sy = y
    if world:getBlock(sx, sy, sz) == 0 and canSpawnAt(game, sx, sy, sz, d.w, d.h)
      and (nether or game:lightAt(sx, sy, sz) <= 7) then
      M.spawn(game, kind, sx + 0.5, sy, sz + 0.5)
    end
  end
end

local function trySpawnPassive(game, cx, cz)
  local rng = game.rng
  local world = game.world
  local kind = PASSIVE_KINDS[rng:int(1, #PASSIVE_KINDS)]
  if kind == "wolf" and game.biomeAt then
    local b = game.biomeAt(cx * 16 + 8, cz * 16 + 8)
    if not (b and (b.pine or b.name == "Las")) then kind = "pig" end
  end
  local d = DEFS[kind]
  local n = rng:int(2, 4)
  local spawned = 0
  for _ = 1, n * 3 do
    if spawned >= n then break end
    local x, z = cx * 16 + rng:int(1, 14), cz * 16 + rng:int(1, 14)
    local y = world:getHeight(x, z)
    if world:getBlock(x, y - 1, z) == 2 and canSpawnAt(game, x, y, z, d.w, d.h) then
      M.spawn(game, kind, x + 0.5, y, z + 0.5)
      spawned = spawned + 1
    end
  end
end
M.trySpawnPassive = trySpawnPassive

-- Spawnery w lochach
local function tickSpawners(game)
  local p = game.player
  local pcx, pcz = floor(p.x / 16), floor(p.z / 16)
  for dz = -1, 1 do
    for dx = -1, 1 do
      local c = game.world:getChunk(pcx + dx, pcz + dz)
      if c then
        for idx, tile in pairs(c.tiles) do
          if tile.kind == "spawner" then
            local lx, lz, y = idx % 16, floor(idx / 16) % 16, floor(idx / 256)
            local x, z = c.cx * 16 + lx, c.cz * 16 + lz
            if (x - p.x) ^ 2 + (y - p.y) ^ 2 + (z - p.z) ^ 2 < 256 then
              tile.delay = (tile.delay or 200) - 1
              if tile.delay % 10 == 0 then
                game:emit("particles", "flame", x + 0.5, y + 0.5, z + 0.5)
              end
              if tile.delay <= 0 then
                tile.delay = game.rng:int(200, 800)
                local near = 0
                for _, e in ipairs(game.entities:near(x, y, z, 8, "mob")) do
                  if e.kind == tile.mob then near = near + 1 end
                end
                if near < 6 and game.difficulty > 0 then
                  for _ = 1, 4 do
                    local sx = x + game.rng:int(-4, 4)
                    local sz = z + game.rng:int(-4, 4)
                    local sy = y + game.rng:int(-1, 1)
                    local d = DEFS[tile.mob]
                    if canSpawnAt(game, sx, sy, sz, d.w, d.h) and game:lightAt(sx, sy, sz) <= 11 then
                      M.spawn(game, tile.mob, sx + 0.5, sy, sz + 0.5)
                      game:emit("particles", "poof", sx + 0.5, sy + 0.5, sz + 0.5)
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end

function M.tick(game)
  local st = game.mobState
  -- potwory: próba spawnu co tick, limit 30 w okolicy
  if game.difficulty > 0 then
    local hostiles = 0
    for _, e in ipairs(game.entities.list) do
      if e.isMob and e.def.hostile and not e.dead then hostiles = hostiles + 1 end
    end
    if hostiles < 30 and game.time % 2 == 0 then trySpawnHostile(game) end
  end
  -- zwierzęta: w nowo wygenerowanych chunkach
  if game.pendingAnimalChunks then
    for i = #game.pendingAnimalChunks, 1, -1 do
      local c = game.pendingAnimalChunks[i]
      if game.world:getChunk(c[1], c[2]) and game.world:getChunk(c[1], c[2]).lit then
        trySpawnPassive(game, c[1], c[2])
        table.remove(game.pendingAnimalChunks, i)
      end
    end
  end
  -- powolne odnawianie zwierząt
  st.passiveTimer = st.passiveTimer + 1
  if st.passiveTimer >= 1200 then
    st.passiveTimer = 0
    local animals = 0
    for _, e in ipairs(game.entities.list) do
      if e.isMob and e.def.passive and not e.dead then animals = animals + 1 end
    end
    if animals < 12 and game.dimension == "overworld" then
      local p = game.player
      local cx = floor(p.x / 16) + game.rng:int(-4, 4)
      local cz = floor(p.z / 16) + game.rng:int(-4, 4)
      local c = game.world:getChunk(cx, cz)
      if c and c.lit and (abs(cx - floor(p.x / 16)) > 1 or abs(cz - floor(p.z / 16)) > 1) then
        trySpawnPassive(game, cx, cz)
      end
    end
  end
  tickSpawners(game)
end

return M
