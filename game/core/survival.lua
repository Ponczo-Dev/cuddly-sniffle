-- core/survival.lua
-- Przetrwanie (jak w Minecraft Beta 1.8):
--  * zdrowie 20 pkt, nietykalność po trafieniu, pancerz (4% na punkt),
--  * głód 20 pkt + ukryte nasycenie + zmęczenie (exhaustion),
--  * regeneracja przy głodzie >= 18, obrażenia z głodu zależne od trudności,
--  * upadek, tonięcie, lawa, ogień, kaktus, próżnia, duszenie w bloku,
--  * doświadczenie i poziomy, jedzenie z animacją, łuk, efekty mikstur,
--  * śmierć: wypadają przedmioty, odrodzenie w punkcie spawnu.

local items = require("core.items")
local blocks = require("core.blocks")
local physics = require("core.physics")

local S = {}

local floor = math.floor

function S.init(game)
  game.health = 20
  game.maxHealth = 20
  game.food = 20
  game.saturation = 5
  game.exhaustion = 0
  game.foodTimer = 0
  game.air = 300
  game.fireTicks = 0
  game.hurtTime = 0
  game.invulnerable = 0
  game.lastDamage = 0
  game.xpLevel = 0
  game.xpPoints = 0      -- punkty w obecnym poziomie
  game.xpTotal = 0
  game.effects = {}      -- nazwa -> { ticks, amp }
  game.using = nil       -- { kind = "eat"|"bow", ticks, slot }
  game.deathMessage = nil
  game.lastPosX, game.lastPosZ = nil, nil
end

-- ---------------------------------------------------------------------------
-- Doświadczenie
-- ---------------------------------------------------------------------------
function S.xpForLevel(level)
  return 7 + floor(level * 7 / 2)
end

function S.addXp(game, n)
  game.xpTotal = game.xpTotal + n
  game.xpPoints = game.xpPoints + n
  while game.xpPoints >= S.xpForLevel(game.xpLevel) do
    game.xpPoints = game.xpPoints - S.xpForLevel(game.xpLevel)
    game.xpLevel = game.xpLevel + 1
    game:emit("sound", "levelup", game.player.x, game.player.y, game.player.z)
  end
end

function S.xpProgress(game)
  return game.xpPoints / S.xpForLevel(game.xpLevel)
end

-- Wydanie poziomów (zaklinanie, kowadło)
function S.spendLevels(game, n)
  if game.player.gameMode == "creative" then return true end
  if game.xpLevel < n then return false end
  game.xpLevel = game.xpLevel - n
  if game.xpPoints >= S.xpForLevel(game.xpLevel) then game.xpPoints = 0 end
  return true
end

-- ---------------------------------------------------------------------------
-- Głód
-- ---------------------------------------------------------------------------
function S.addExhaustion(game, v)
  if game.player.gameMode == "creative" then return end
  game.exhaustion = math.min(game.exhaustion + v, 40)
end

function S.canSprint(game)
  return game.player.gameMode == "creative" or game.food > 6
end

function S.heal(game, amount)
  if game.dead then return end
  game.health = math.min(game.maxHealth, game.health + amount)
end

local function tickFood(game)
  local diff = game.difficulty
  if diff == 0 then
    -- tryb spokojny: wszystko się odnawia
    if game.time % 20 == 0 then
      S.heal(game, 1)
      if game.food < 20 then game.food = game.food + 1 end
    end
    return
  end
  if game.exhaustion > 4 then
    game.exhaustion = game.exhaustion - 4
    if game.saturation > 0 then
      game.saturation = math.max(game.saturation - 1, 0)
    else
      game.food = math.max(game.food - 1, 0)
    end
  end
  if game.food >= 18 and game.health < game.maxHealth then
    game.foodTimer = game.foodTimer + 1
    if game.foodTimer >= 80 then
      S.heal(game, 1)
      S.addExhaustion(game, 3)
      game.foodTimer = 0
    end
  elseif game.food <= 0 then
    game.foodTimer = game.foodTimer + 1
    if game.foodTimer >= 80 then
      if game.health > 10 or diff >= 3 or (game.health > 1 and diff >= 2) then
        S.damage(game, 1, "starve")
      end
      game.foodTimer = 0
    end
  else
    game.foodTimer = 0
  end
end

-- Zmęczenie od ruchu (na podstawie przesunięcia w ticku)
local function tickMovementExhaustion(game)
  local p = game.player
  local dx, dy, dz = p.x - p.prevX, p.y - p.prevY, p.z - p.prevZ
  local dist = math.sqrt(dx * dx + dz * dz)
  if p.inWater then
    S.addExhaustion(game, 0.015 * math.sqrt(dx * dx + dy * dy + dz * dz))
  elseif p.sprinting then
    S.addExhaustion(game, 0.1 * dist)
  elseif p.onGround then
    S.addExhaustion(game, 0.01 * dist)
  end
end

-- ---------------------------------------------------------------------------
-- Pancerz
-- ---------------------------------------------------------------------------
function S.armorPoints(game)
  local total = 0
  for i = 1, 4 do
    local s = game.armor.slots[i]
    local d = s and items.get(s.id)
    if d and d.armor then total = total + d.armor.points end
  end
  return total
end

local function damageArmor(game, amount)
  local dmg = math.max(1, floor(amount / 4))
  for i = 1, 4 do
    if game.armor.slots[i] then
      if game.armor:damageItem(i, dmg) then
        game:emit("sound", "break_tool", game.player.x, game.player.y + 1, game.player.z)
      end
    end
  end
end

local UNBLOCKABLE = { starve = true, void = true, poison = true, drown = true,
  suffocate = true }

-- ---------------------------------------------------------------------------
-- Obrażenia
-- ---------------------------------------------------------------------------
-- source: "fall", "lava", "fire", "drown", "starve", "cactus", "void", "mob",
--         "arrow", "explosion", "poison", "suffocate"
function S.damage(game, amount, source, attacker)
  if game.dead then return false end
  if game.player.gameMode == "creative" and source ~= "void" then return false end
  if amount <= 0 then return false end

  -- nietykalność po trafieniu: tylko silniejszy cios przechodzi (różnica)
  if game.invulnerable > 10 then
    if amount <= game.lastDamage then return false end
    local extra = amount - game.lastDamage
    game.lastDamage = amount
    amount = extra
  else
    game.lastDamage = amount
    game.invulnerable = 20
    game.hurtTime = 10
  end

  if not UNBLOCKABLE[source] then
    local points = S.armorPoints(game)
    if points > 0 then
      damageArmor(game, amount)
      amount = amount * (25 - points) / 25
    end
  end
  -- zaokrąglanie ułamków jak w MC (reszta kumuluje się losowo)
  local whole = floor(amount)
  if game.rng:next() < amount - whole then whole = whole + 1 end
  amount = whole
  if amount <= 0 then return true end

  game.health = game.health - amount
  S.addExhaustion(game, 0.3)
  game:emit("hurt", source, amount)
  game:emit("sound", "hurt", game.player.x, game.player.y + 1, game.player.z)

  -- odrzut od atakującego
  if attacker and attacker.x then
    local p = game.player
    local dx, dz = p.x - attacker.x, p.z - attacker.z
    local d = math.sqrt(dx * dx + dz * dz)
    if d > 0.01 then
      p.vx = p.vx / 2 + dx / d * 0.4
      p.vz = p.vz / 2 + dz / d * 0.4
      p.vy = math.min(0.4, p.vy / 2 + 0.4)
    end
  end

  if game.health <= 0 then
    S.die(game, source, attacker)
  end
  return true
end

local DEATH_MESSAGES = {
  fall = "spadl z wysokosci", lava = "probowal plywac w lawie", fire = "splonal",
  drown = "utonal", starve = "umarl z glodu", cactus = "zostal zakluty na smierc",
  void = "wypadl ze swiata", mob = "zostal zabity", arrow = "zostal zastrzelony",
  explosion = "wylecial w powietrze", poison = "zostal otruty", suffocate = "udusil sie w scianie",
}

function S.die(game, source, attacker)
  if game.dead then return end
  game.dead = true
  game.health = 0
  game.using = nil
  game.sleeping = nil
  local who = attacker and attacker.label and (" przez " .. attacker.label) or ""
  game.deathMessage = "Gracz " .. (DEATH_MESSAGES[source] or "zginal") .. who
  local p = game.player
  if game.player.gameMode ~= "creative" then
    for i = 1, game.inventory.size do
      local s = game.inventory.slots[i]
      if s then
        game:dropStack(p.x, p.y + 1, p.z, s)
      end
    end
    for i = 1, 4 do
      local s = game.armor.slots[i]
      if s then game:dropStack(p.x, p.y + 1, p.z, s) end
    end
    game.inventory:clear()
    game.armor:clear()
    local xp = math.min(game.xpLevel * 7, 100)
    if xp > 0 then game:spawnXp(p.x, p.y + 0.5, p.z, xp) end
  end
  game.xpLevel, game.xpPoints, game.xpTotal = 0, 0, 0
  game:emit("death", game.deathMessage)
end

function S.respawn(game)
  if game.hardcore then return false end
  local p = game.player
  local x, y, z = game.spawnX, game.spawnY, game.spawnZ
  if x then
    -- łóżko mogło zostać zniszczone
    local bx, by, bz = floor(x), floor(y) - 1, floor(z)
    if game.world:isLoadedAt(bx, bz) and game.world:getBlock(bx, by, bz) ~= 26 then
      game:emit("message", "Twoje lozko zniknelo")
      x = nil
    end
  end
  if not x then
    x, y, z = game.worldSpawnX, game.worldSpawnY, game.worldSpawnZ
  end
  p.x, p.y, p.z = x, y, z
  p.prevX, p.prevY, p.prevZ = x, y, z
  p.vx, p.vy, p.vz = 0, 0, 0
  p.fallDistance = 0
  game.health = 20
  game.food = 20
  game.saturation = 5
  game.exhaustion = 0
  game.air = 300
  game.fireTicks = 0
  game.effects = {}
  game.dead = false
  game.needsSpawnFix = true
  return true
end

-- ---------------------------------------------------------------------------
-- Efekty (trucizna, regeneracja, głód z zatrucia)
-- ---------------------------------------------------------------------------
function S.addEffect(game, name, ticks, amp)
  local e = game.effects[name]
  if not e or e.ticks < ticks or (e.amp or 0) < (amp or 0) then
    game.effects[name] = { ticks = ticks, amp = amp or 0 }
  end
end

function S.clearEffects(game)
  game.effects = {}
end

local function tickEffects(game)
  for name, e in pairs(game.effects) do
    e.ticks = e.ticks - 1
    if name == "poison" then
      local rate = math.max(1, floor(25 / (2 ^ e.amp)))
      if e.ticks % rate == 0 and game.health > 1 then S.damage(game, 1, "poison") end
    elseif name == "regeneration" then
      local rate = math.max(1, floor(50 / (2 ^ e.amp)))
      if e.ticks % rate == 0 then S.heal(game, 1) end
    elseif name == "hunger" then
      S.addExhaustion(game, 0.025 * (e.amp + 1))
    end
    if e.ticks <= 0 then game.effects[name] = nil end
  end
end

-- ---------------------------------------------------------------------------
-- Używanie przedmiotów: jedzenie i łuk (trzymanie prawego przycisku)
-- ---------------------------------------------------------------------------
function S.isUsingItem(game)
  return game.using ~= nil
end

function S.startEating(game)
  local s = game:heldStack()
  local d = s and items.get(s.id)
  if not d or not d.food then return false end
  if game.food >= 20 and not d.food.alwaysEdible and game.player.gameMode ~= "creative" then
    return false
  end
  game.using = { kind = "eat", ticks = 0, slot = game.selected, id = s.id }
  return true
end

function S.startBow(game)
  local creative = game.player.gameMode == "creative"
  if not creative and game.inventory:count(262) == 0 then return false end
  game.using = { kind = "bow", ticks = 0, slot = game.selected, id = 261 }
  return true
end

local function finishEating(game)
  local u = game.using
  local s = game.inventory.slots[u.slot]
  game.using = nil
  if not s or s.id ~= u.id then return end
  local d = items.get(s.id)
  local f = d.food
  game.food = math.min(20, game.food + f.hunger)
  game.saturation = math.min(game.food, game.saturation + f.hunger * f.saturation * 2)
  if f.poison and game.rng:chance(f.poison.chance) then
    S.addEffect(game, "hunger", f.poison.ticks, 0)
  end
  if s.id == 322 then S.addEffect(game, "regeneration", 600, 0) end
  game:emit("sound", "burp", game.player.x, game.player.y + 1.5, game.player.z)
  if game.player.gameMode ~= "creative" then
    game.inventory:decrement(u.slot, 1)
    if f.returns then game:giveItem(items.newStack(f.returns)) end
  end
end

-- Puszczenie prawego przycisku: strzał z łuku albo przerwanie jedzenia
function S.stopUsing(game)
  local u = game.using
  if not u then return end
  game.using = nil
  if u.kind == "bow" and game.mobs then
    local f = u.ticks / 20
    f = (f * f + f * 2) / 3
    if f < 0.1 then return end
    if f > 1 then f = 1 end
    local creative = game.player.gameMode == "creative"
    if not creative then
      if game.inventory:removeItem(262, 1) == 0 then return end
      game:damageHeld(1)
    end
    game.mobs.shootArrow(game, f)
  end
end

local function tickUsing(game)
  local u = game.using
  if not u then return end
  local s = game.inventory.slots[u.slot]
  if game.selected ~= u.slot or not s or s.id ~= u.id then
    game.using = nil
    return
  end
  u.ticks = u.ticks + 1
  if u.kind == "eat" then
    if u.ticks % 4 == 0 then
      game:emit("sound", "eat", game.player.x, game.player.y + 1.5, game.player.z)
      game:emit("particles", "eat", u.id)
    end
    if u.ticks >= 32 then finishEating(game) end
  end
end

-- ---------------------------------------------------------------------------
-- Środowisko: upadek, woda, lawa, ogień, kaktus, próżnia
-- ---------------------------------------------------------------------------
local function tickEnvironment(game)
  local p = game.player
  local world = game.world

  -- zdarzenia z fizyki gracza
  for _, ev in ipairs(p.events) do
    if ev[1] == "land" then
      local d = ev[2]
      if not p.inWater and d > 3 then
        local dmg = math.ceil(d - 3)
        S.damage(game, dmg, "fall")
        game:emit("sound", dmg > 4 and "fall_big" or "fall_small", p.x, p.y, p.z)
      end
      -- skok na pole uprawne zadeptuje je
      local bx, by, bz = floor(p.x), floor(p.y - 0.2), floor(p.z)
      if d > 0.5 and world:getBlock(bx, by, bz) == 60 then
        game:setBlock(bx, by, bz, 3, 0)
      end
    elseif ev[1] == "jump" then
      S.addExhaustion(game, ev[2] and 0.8 or 0.2)
    end
  end
  p.events = {}

  -- tonięcie
  if p.headInWater and game.player.gameMode ~= "creative" then
    game.air = game.air - 1
    if game.air <= -20 then
      game.air = 0
      S.damage(game, 2, "drown")
    end
  else
    game.air = 300
  end

  -- lawa i ogień
  if p.inLava then
    S.damage(game, 4, "lava")
    game.fireTicks = 300
  end
  if p.inWater and game.fireTicks > 0 then
    game.fireTicks = 0
    game:emit("sound", "fizz", p.x, p.y, p.z)
  end
  if game.fireTicks > 0 and game:isRainingAt(p.x, p.y + 1, p.z) then
    game.fireTicks = 0
  end

  local touchingFire, touchingCactus = false, false
  physics.touchingBlocks(world, p, function(id)
    if id == 51 then touchingFire = true end
    if id == 81 then touchingCactus = true end
  end)
  if touchingFire then
    S.damage(game, 1, "fire")
    if game.fireTicks < 160 then game.fireTicks = 160 end
  end
  if touchingCactus then S.damage(game, 1, "cactus") end

  if game.fireTicks > 0 then
    game.fireTicks = game.fireTicks - 1
    if game.fireTicks % 20 == 0 then S.damage(game, 1, "fire") end
  end

  -- duszenie: głowa w litym bloku
  local ex, ey, ez = p:eyePosition()
  if blocks.OPAQUE[world:getBlock(floor(ex), floor(ey), floor(ez))] == 1
    and game.player.gameMode ~= "creative" and world:isLoadedAt(floor(ex), floor(ez)) then
    S.damage(game, 1, "suffocate")
  end

  -- próżnia
  if p.y < -64 then S.damage(game, 4, "void") end
end

-- ---------------------------------------------------------------------------
-- Tick przetrwania
-- ---------------------------------------------------------------------------
function S.tick(game)
  if game.hurtTime > 0 then game.hurtTime = game.hurtTime - 1 end
  if game.invulnerable > 0 then game.invulnerable = game.invulnerable - 1 end
  if game.dead then return end
  tickEnvironment(game)
  if game.dead then return end
  tickUsing(game)
  if game.player.gameMode ~= "creative" then
    tickMovementExhaustion(game)
    tickFood(game)
  else
    game.food, game.saturation = 20, 5
  end
  tickEffects(game)
end

return S
