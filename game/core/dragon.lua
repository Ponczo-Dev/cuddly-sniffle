-- core/dragon.lua
-- Smok Endu i kryształy Endu.
--  * stan walki w game.endState (zapisywany z poziomem): życie smoka,
--    zniszczone kryształy, czy smok pokonany,
--  * kryształy stoją na obsydianowych kolumnach i leczą smoka; uderzenie
--    albo strzała je wysadza,
--  * smok krąży nad wyspą i co jakiś czas szarżuje na gracza, niszcząc
--    bloki na drodze (poza kamieniem Endu, obsydianem i skałą macierzystą),
--  * po śmierci: wielki wybuch światła, dużo doświadczenia, portal powrotny
--    i jajo smoka na środku wyspy.

local entities = require("core.entities")
local endgen = require("core.endgen")

local M = {}

local floor, sqrt, abs = math.floor, math.sqrt, math.abs
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

M.MAX_HEALTH = 200
local PROTECTED = { [121] = true, [49] = true, [7] = true, [119] = true, [120] = true, [122] = true }

function M.state(game)
  if not game.endState then
    game.endState = { dragonDead = false, health = M.MAX_HEALTH, crystals = {} }
  end
  game.endState.crystals = game.endState.crystals or {}
  return game.endState
end

-- ---------------------------------------------------------------------------
-- Kryształy
-- ---------------------------------------------------------------------------
entities.TICK.crystal = function(game, e)
  e.y = e.baseY + math.sin(e.age * 0.08) * 0.25
  if game.dimension == "end" and game.rng:chance(0.1) then
    game:emit("particles", "portal", e.x, e.y + 0.5, e.z)
  end
end

local function spawnCrystal(game, i, p)
  local e = entities.base("crystal", p.x + 0.5, p.h + 2, p.z + 0.5, 2, 2)
  e.kind = "crystal"
  e.baseY = p.h + 2
  e.pillar = i
  e.isCrystal = true
  game.entities:add(e)
  return e
end

function M.destroyCrystal(game, e)
  if e.dead then return end
  e.dead = true
  local st = M.state(game)
  if e.pillar then st.crystals[e.pillar] = false end
  game:explode(e.x, e.y, e.z, 6, e)
end

-- ---------------------------------------------------------------------------
-- Pilnowanie obecności smoka i kryształów (co tick w Endzie)
-- ---------------------------------------------------------------------------
function M.tick(game)
  local st = M.state(game)
  local world = game.world
  game.endCrystals = game.endCrystals or {}
  for i, p in ipairs(endgen.pillars(game.seed)) do
    if st.crystals[i] ~= false then
      local e = game.endCrystals[i]
      local c = world:getChunkAt(p.x, p.z)
      if (not e or e.dead) and c and c.lit then
        game.endCrystals[i] = spawnCrystal(game, i, p)
      end
    end
  end
  if not st.dragonDead then
    local d = game.endDragon
    local c = world:getChunk(0, 0)
    if (not d or d.dead) and c and c.lit then
      local mobs = require("core.mobs")
      d = mobs.spawn(game, "dragon", 0.5, 95, 40.5)
      d.health = math.max(1, st.health or M.MAX_HEALTH)
      d.maxHealth = M.MAX_HEALTH
      d.modelScale = 2
      d.persistent = true
      d.angle = 0
      game.endDragon = d
      game:emit("sound", "dragon_growl", d.x, d.y, d.z)
    end
    if d and not d.dead and d.deathTime == 0 then st.health = d.health end
  end
end

-- ---------------------------------------------------------------------------
-- Zachowanie smoka
-- ---------------------------------------------------------------------------
function M.ai(game, e)
  local p = game.player
  local rng = game.rng
  e.phase = e.phase or "circle"
  e.angle = e.angle or 0
  local tx, ty, tz
  local playerOk = not game.dead and p.gameMode ~= "creative" and game.dimension == "end"
  if e.phase == "circle" then
    e.angle = e.angle + 0.01
    tx, tz = math.cos(e.angle) * 48, math.sin(e.angle) * 48
    ty = 88 + math.sin(e.angle * 3) * 8
    if playerOk and rng:chance(1 / 260) then
      e.phase = "charge"
      e.phaseTimer = 140
      game:emit("sound", "dragon_growl", e.x, e.y, e.z)
    end
  else
    tx, ty, tz = p.x, p.y + 0.5, p.z
    e.phaseTimer = (e.phaseTimer or 0) - 1
    local d2 = (p.x - e.x) ^ 2 + (p.z - e.z) ^ 2
    if e.phaseTimer <= 0 or not playerOk or d2 < 4 then
      e.phase = "circle"
      e.angle = atan2(e.z, e.x)
    end
  end
  local dx, dy, dz = tx - e.x, ty - e.y, tz - e.z
  local d = sqrt(dx * dx + dy * dy + dz * dz)
  local speed = e.phase == "charge" and 0.75 or 0.55
  if d > 0.1 then
    e.vx = e.vx + (dx / d * speed - e.vx) * 0.06
    e.vy = e.vy + (dy / d * speed * 0.6 - e.vy) * 0.06
    e.vz = e.vz + (dz / d * speed - e.vz) * 0.06
  end
  e.yaw = atan2(-e.vx, -e.vz)
  e.headPitch = -e.vy * 0.8

  -- uderzenie gracza
  if playerOk and (e.attackCooldown or 0) == 0 then
    local hx, hz = p.x - e.x, p.z - e.z
    if abs(hx) < 4 and abs(hz) < 4 and p.y > e.y - 1 and p.y < e.y + 6 then
      game.survival.damage(game, 10, "mob", e)
      p.vy = 0.7
      local hl = sqrt(hx * hx + hz * hz) + 0.01
      p.vx, p.vz = p.vx + hx / hl * 1.2, p.vz + hz / hl * 1.2
      e.attackCooldown = 30
      e.phase = "circle"
      e.angle = atan2(e.z, e.x)
    end
  end

  -- niszczenie bloków na drodze
  if e.age % 4 == 0 then
    local world = game.world
    for x = floor(e.x - 3), floor(e.x + 3) do
      for z = floor(e.z - 3), floor(e.z + 3) do
        for y = floor(e.y + 1), floor(e.y + 5) do
          local id = world:getBlock(x, y, z)
          if id ~= 0 and not PROTECTED[id] then
            world:setBlock(x, y, z, 0, 0)
            if rng:chance(0.1) then game:emit("particles", "explosion", x + 0.5, y + 0.5, z + 0.5) end
          end
        end
      end
    end
  end

  -- leczenie od najbliższego kryształu
  e.healCrystal = nil
  local best, bestD = nil, 32 * 32
  for _, c in ipairs(game.entities.list) do
    if c.type == "crystal" and not c.dead then
      local cd = (c.x - e.x) ^ 2 + (c.y - e.y) ^ 2 + (c.z - e.z) ^ 2
      if cd < bestD then best, bestD = c, cd end
    end
  end
  if best then
    e.healCrystal = best
    if e.health < M.MAX_HEALTH and e.age % 10 == 0 then e.health = math.min(M.MAX_HEALTH, e.health + 1) end
    if e.age % 3 == 0 then
      local t = rng:next()
      game:emit("particles", "portal", best.x + (e.x - best.x) * t, best.y + 0.8 + (e.y + 3 - best.y) * t,
        best.z + (e.z - best.z) * t)
    end
  end

  if e.age % 40 == 0 then game:emit("sound", "dragon_wings", e.x, e.y, e.z) end
  if rng:chance(1 / 500) then game:emit("sound", "dragon_growl", e.x, e.y, e.z) end
end

-- Ruch bez kolizji (smok przelatuje przez bloki)
function M.move(e)
  e.x, e.y, e.z = e.x + e.vx, e.y + e.vy, e.z + e.vz
  if e.y < 40 then e.y, e.vy = 40, math.abs(e.vy) end
  if e.y > 120 then e.y, e.vy = 120, -math.abs(e.vy) end
end

-- Śmierć: 7 sekund wybuchów światła, potem nagroda i portal powrotny
function M.dying(game, e)
  e.deathTime = e.deathTime + 1
  e.vx, e.vy, e.vz = 0, 0.03, 0
  e.y = e.y + 0.03
  local rng = game.rng
  if e.deathTime % 3 == 0 then
    game:emit("particles", "explosion", e.x + (rng:next() - 0.5) * 8, e.y + rng:next() * 6,
      e.z + (rng:next() - 0.5) * 8)
  end
  if e.deathTime % 20 == 0 then game:emit("sound", "explosion", e.x, e.y, e.z) end
  if e.deathTime > 40 and e.deathTime % 5 == 0 then
    game:spawnXp(e.x + (rng:next() - 0.5) * 4, e.y + 2, e.z + (rng:next() - 0.5) * 4, 60)
  end
  if e.deathTime >= 140 then
    e.dead = true
    local st = M.state(game)
    st.dragonDead = true
    st.health = 0
    local gen = game.endGen
    local top = gen and gen:surfaceAt(0, 0) or endgen.SURFACE
    require("core.endportal").buildExitPortal(game, top + 1)
    game:emit("sound", "dragon_growl", e.x, e.y, e.z)
    game:emit("message", "Smok Endu zostal pokonany! Portal powrotny czeka na srodku wyspy.")
    game.stats.dragonKilled = (game.stats.dragonKilled or 0) + 1
  end
end

return M
