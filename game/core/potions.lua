-- core/potions.lua
-- Mikstury (jak w Minecraft 1.0): statyw alchemiczny warzy butelki ze
-- składnikiem. Rodzaj mikstury jest zapisany w damage przedmiotu 373:
--   damage = typ (0..99) + 100 (przedłużona, czerwony pył)
--            + 200 (wzmocniona II, pył jasnogłazu) + 1000 (rzucana, proch)
-- Tu są też efekty po wypiciu / trafieniu miksturą rzucaną.

local M = {}

local floor = math.floor

M.POTION = 373
M.BOTTLE = 374
M.BREW_TIME = 400

-- typ -> opis; effect = nazwa efektu (survival.addEffect) albo instant
M.TYPES = {
  [0] = { label = "Butelka wody", color = { 56, 93, 198 } },
  [1] = { label = "Dziwna mikstura", color = { 56, 93, 198 } },
  [2] = { label = "Zwykla mikstura", color = { 56, 93, 198 } },
  [3] = { label = "Gesta mikstura", color = { 56, 93, 198 } },
  [10] = { label = "Mikstura regeneracji", effect = "regeneration", color = { 205, 92, 171 },
    ticks = { 900, 2400, 440 } },
  [11] = { label = "Mikstura szybkosci", effect = "speed", color = { 124, 175, 198 },
    ticks = { 3600, 9600, 1800 } },
  [12] = { label = "Mikstura odpornosci na ogien", effect = "fire_resistance", color = { 228, 154, 58 },
    ticks = { 3600, 9600 } },
  [13] = { label = "Mikstura leczenia", instant = "heal", color = { 248, 36, 35 } },
  [14] = { label = "Mikstura sily", effect = "strength", color = { 147, 36, 35 },
    ticks = { 3600, 9600, 1800 } },
  [15] = { label = "Mikstura trucizny", effect = "poison", color = { 78, 147, 49 },
    ticks = { 900, 2400, 440 } },
  [16] = { label = "Mikstura oslabienia", effect = "weakness", color = { 72, 77, 72 },
    ticks = { 1800, 4800 } },
  [17] = { label = "Mikstura spowolnienia", effect = "slowness", color = { 90, 108, 129 },
    ticks = { 1800, 4800 } },
  [18] = { label = "Mikstura krzywdy", instant = "harm", color = { 67, 10, 9 } },
}

-- Nazwy efektów do HUD
M.EFFECT_LABEL = {
  regeneration = "Regeneracja", speed = "Szybkosc", fire_resistance = "Odpornosc na ogien",
  strength = "Sila", poison = "Trucizna", weakness = "Oslabienie", slowness = "Spowolnienie",
  hunger = "Glod",
}

function M.decode(damage)
  damage = damage or 0
  local splash = damage >= 1000
  if splash then damage = damage - 1000 end
  local variant = floor(damage / 100) -- 0 zwykła, 1 przedłużona, 2 wzmocniona
  local base = damage % 100
  return base, variant, splash
end

function M.encode(base, variant, splash)
  return base + (variant or 0) * 100 + (splash and 1000 or 0)
end

function M.label(damage)
  local base, variant, splash = M.decode(damage)
  local t = M.TYPES[base]
  if not t then return "Mikstura" end
  local s = t.label
  if splash and base >= 10 then s = s:gsub("^Mikstura", "Rzucana mikstura") end
  if variant == 2 then s = s .. " II" end
  return s
end

function M.color(damage)
  local base = M.decode(damage)
  local t = M.TYPES[base] or M.TYPES[0]
  return t.color
end

-- Czas działania (ticki) mikstury z efektem
function M.duration(damage)
  local base, variant = M.decode(damage)
  local t = M.TYPES[base]
  if not t or not t.ticks then return 0 end
  return t.ticks[variant + 1] or t.ticks[1]
end

-- Opis do podpowiedzi
function M.tooltip(damage)
  local base, variant = M.decode(damage)
  local t = M.TYPES[base]
  if not t then return nil end
  if t.effect then
    local secs = floor(M.duration(damage) / 20)
    return string.format("%s%s (%d:%02d)", M.EFFECT_LABEL[t.effect] or t.effect,
      variant == 2 and " II" or "", floor(secs / 60), secs % 60)
  elseif t.instant then
    return t.instant == "heal" and ("Leczenie" .. (variant == 2 and " II" or ""))
      or ("Krzywda" .. (variant == 2 and " II" or ""))
  end
  return "Brak efektow"
end

-- ---------------------------------------------------------------------------
-- Warzenie
-- ---------------------------------------------------------------------------
local AWKWARD_RECIPES = {
  [370] = 10, -- łza ghasta -> regeneracja
  [353] = 11, -- cukier -> szybkość
  [378] = 12, -- magmowy krem -> odporność na ogień
  [382] = 13, -- błyszczący arbuz -> leczenie
  [377] = 14, -- płomienny proszek -> siła
  [375] = 15, -- oko pająka -> trucizna
}
local FERMENT = { [0] = 16, [2] = 16, [3] = 16, [10] = 16, [14] = 16, [11] = 17, [12] = 17,
  [13] = 18, [15] = 18 }

M.INGREDIENTS = { [372] = true, [331] = true, [348] = true, [289] = true, [376] = true }
for id in pairs(AWKWARD_RECIPES) do M.INGREDIENTS[id] = true end

-- Wynik warzenia butelki (damage) składnikiem (id) albo nil
function M.brewResult(damage, ingredient)
  local base, variant, splash = M.decode(damage)
  if ingredient == 372 then
    if base == 0 then return M.encode(1, 0, splash) end
    return nil
  elseif ingredient == 331 then
    if base == 0 then return M.encode(2, 0, splash) end
    local t = M.TYPES[base]
    if t and t.ticks and t.ticks[2] and variant ~= 1 then return M.encode(base, 1, splash) end
    return nil
  elseif ingredient == 348 then
    if base == 0 then return M.encode(3, 0, splash) end
    local t = M.TYPES[base]
    if t and (t.instant or (t.ticks and t.ticks[3])) and variant ~= 2 then return M.encode(base, 2, splash) end
    return nil
  elseif ingredient == 289 then
    if base >= 10 and not splash then return M.encode(base, variant, true) end
    return nil
  elseif ingredient == 376 then
    local to = FERMENT[base]
    if not to then return nil end
    local t = M.TYPES[to]
    local v = variant
    if t.instant then v = variant == 2 and 2 or 0 elseif variant == 2 then v = 0 end
    return M.encode(to, v, splash)
  end
  local to = AWKWARD_RECIPES[ingredient]
  if to and base == 1 then return M.encode(to, 0, splash) end
  return nil
end

-- Czy w statywie jest coś do uwarzenia
function M.canBrew(inv)
  local ing = inv.slots[4]
  if not ing then return false end
  for i = 1, 3 do
    local s = inv.slots[i]
    if s and s.id == M.POTION and M.brewResult(s.damage, ing.id) then return true end
  end
  return false
end

-- Tick statywu (tile.brew = pozostały czas)
function M.tickStand(game, tile, x, y, z)
  local inv = tile.inventory
  if not inv then return end
  if M.canBrew(inv) then
    if (tile.brew or 0) <= 0 then
      tile.brew = M.BREW_TIME
      tile.brewIng = inv.slots[4].id
    end
    if inv.slots[4].id ~= tile.brewIng then tile.brew = M.BREW_TIME; tile.brewIng = inv.slots[4].id end
    tile.brew = tile.brew - 1
    if tile.brew <= 0 then
      local ing = inv.slots[4]
      for i = 1, 3 do
        local s = inv.slots[i]
        if s and s.id == M.POTION then
          local r = M.brewResult(s.damage, ing.id)
          if r then s.damage = r end
        end
      end
      ing.count = ing.count - 1
      if ing.count <= 0 then inv.slots[4] = nil end
      inv.changed = true
      tile.brew = 0
      game:emit("sound", "brew", x + 0.5, y + 0.5, z + 0.5)
      local c = game.world:getChunkAt(x, z)
      if c then c.modified = true end
    end
  else
    tile.brew = 0
  end
end

-- ---------------------------------------------------------------------------
-- Działanie
-- ---------------------------------------------------------------------------
-- Efekt mikstury na graczu (scale: 0..1 dla rzucanych z odległości)
function M.applyToPlayer(game, damage, scale)
  local survival = game.survival
  local base, variant = M.decode(damage)
  local t = M.TYPES[base]
  if not t then return end
  scale = scale or 1
  local amp = variant == 2 and 1 or 0
  if t.effect then
    local ticks = floor(M.duration(damage) * scale)
    if ticks > 20 then survival.addEffect(game, t.effect, ticks, amp) end
  elseif t.instant == "heal" then
    survival.heal(game, floor(4 * (2 ^ amp) * scale + 0.5))
  elseif t.instant == "harm" then
    survival.damage(game, floor(6 * (2 ^ amp) * scale + 0.5), "magic")
  end
end

local UNDEAD = { zombie = true, skeleton = true, pigman = true }

-- Rzucana mikstura trafiająca moba (tylko natychmiastowe efekty i trucizna)
function M.applyToMob(game, e, damage, scale)
  local mobs = require("core.mobs")
  local base, variant = M.decode(damage)
  local t = M.TYPES[base]
  if not t then return end
  local amp = variant == 2 and 1 or 0
  local kind = t.instant
  if kind and UNDEAD[e.kind] then kind = kind == "heal" and "harm" or "heal" end
  if kind == "heal" then
    e.health = math.min(e.maxHealth or e.health, e.health + floor(4 * (2 ^ amp) * scale + 0.5))
  elseif kind == "harm" then
    mobs.damageMob(game, e, floor(6 * (2 ^ amp) * scale + 0.5), "magic")
  elseif t.effect == "poison" and not UNDEAD[e.kind] and e.kind ~= "spider" then
    e.poison = floor(M.duration(damage) * scale)
  end
end

-- Wypicie (po 32 tickach trzymania prawego przycisku)
function M.drink(game, slot)
  local s = game.inventory.slots[slot]
  if not s or s.id ~= M.POTION then return end
  M.applyToPlayer(game, s.damage, 1)
  game:emit("sound", "drink", game.player.x, game.player.y + 1.5, game.player.z)
  if game.player.gameMode ~= "creative" then
    game.inventory:set(slot, { id = M.BOTTLE, count = 1, damage = 0 })
  end
end

-- ---------------------------------------------------------------------------
-- Rzucana mikstura (byt "potion")
-- ---------------------------------------------------------------------------
function M.throw(game, damage)
  local entities = require("core.entities")
  local p = game.player
  local ex, ey, ez = p:eyePosition()
  local lx, ly, lz = p:lookVector()
  local e = entities.base("potion", ex + lx * 0.4, ey - 0.1, ez + lz * 0.4, 0.25, 0.25)
  e.vx, e.vy, e.vz = lx * 0.5, ly * 0.5 + 0.1, lz * 0.5
  e.potion = damage
  e.shooter = p
  game.entities:add(e)
  game:emit("sound", "throw", p.x, p.y + 1.5, p.z)
end

function M.splash(game, e)
  local x, y, z = e.x, e.y, e.z
  local c = M.color(e.potion)
  game:emit("particles", "potion", x, y, z, c)
  game:emit("sound", "glass", x, y, z)
  local p = game.player
  if not game.dead then
    local d = math.sqrt((p.x - x) ^ 2 + (p.y + 0.9 - y) ^ 2 + (p.z - z) ^ 2)
    if d < 4 then M.applyToPlayer(game, e.potion, 1 - d / 4 * 0.75) end
  end
  for _, m in ipairs(game.entities:near(x, y, z, 4)) do
    if m.isMob and not m.dead and m.health > 0 then
      local d = math.sqrt((m.x - x) ^ 2 + (m.y - y) ^ 2 + (m.z - z) ^ 2)
      M.applyToMob(game, m, e.potion, 1 - d / 4 * 0.75)
    end
  end
end

-- tick bytu: lot z grawitacją, rozbicie o blok albo moba
function M.registerEntity()
  local entities = require("core.entities")
  local raycast = require("core.raycast")
  entities.TICK.potion = function(game, e)
    local len = math.sqrt(e.vx * e.vx + e.vy * e.vy + e.vz * e.vz)
    local hit = len > 0 and raycast.cast(game.world, e.x, e.y, e.z, e.vx, e.vy, e.vz, len, function(def)
      return def.solid
    end)
    local mobHit = false
    for _, m in ipairs(game.entities:near(e.x, e.y, e.z, 1.5)) do
      if m.isMob and not m.dead and m.health > 0 then mobHit = true end
    end
    if hit or mobHit or e.age > 200 then
      if hit then e.x, e.y, e.z = hit.hx, hit.hy, hit.hz end
      e.dead = true
      M.splash(game, e)
      return
    end
    e.x, e.y, e.z = e.x + e.vx, e.y + e.vy, e.z + e.vz
    e.vx, e.vy, e.vz = e.vx * 0.99, e.vy * 0.99 - 0.05, e.vz * 0.99
  end
end
M.registerEntity()

return M
