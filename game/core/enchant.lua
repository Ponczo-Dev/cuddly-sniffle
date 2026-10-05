-- core/enchant.lua
-- Zaklinanie (jak w Minecraft 1.0): stół do zaklinania + biblioteczki,
-- trzy oferty za poziomy doświadczenia, losowe zaklęcia zależne od
-- "zaklinalności" materiału. Zaklęcia trzymamy w stosie: stack.ench = { [id] = poziom }.
-- Tu są też efekty zaklęć używane w walce, kopaniu, pancerzu i łuku.

local items = require("core.items")

local M = {}

local floor = math.floor

-- id = jak w MC; max = najwyższy poziom; min(L) = minimalna "moc" dla poziomu L;
-- weight = częstość; target = na co (armor/helmet/boots/weapon/tool/bow); group = wykluczanie
M.LIST = {
  { id = 0, name = "protection", label = "Ochrona", max = 4, weight = 10, target = "armor", group = "prot",
    min = function(l) return 1 + (l - 1) * 11 end },
  { id = 1, name = "fire_protection", label = "Ochrona przed ogniem", max = 4, weight = 5, target = "armor",
    group = "prot", min = function(l) return 10 + (l - 1) * 8 end },
  { id = 2, name = "feather_falling", label = "Powolne opadanie", max = 4, weight = 5, target = "boots",
    min = function(l) return 5 + (l - 1) * 6 end },
  { id = 3, name = "blast_protection", label = "Ochrona przed wybuchami", max = 4, weight = 2,
    target = "armor", group = "prot", min = function(l) return 5 + (l - 1) * 8 end },
  { id = 4, name = "projectile_protection", label = "Ochrona przed pociskami", max = 4, weight = 5,
    target = "armor", group = "prot", min = function(l) return 3 + (l - 1) * 6 end },
  { id = 5, name = "respiration", label = "Oddychanie", max = 3, weight = 2, target = "helmet",
    min = function(l) return 10 * l end },
  { id = 6, name = "aqua_affinity", label = "Wydajnosc pod woda", max = 1, weight = 2, target = "helmet",
    min = function() return 1 end },
  { id = 16, name = "sharpness", label = "Ostrosc", max = 5, weight = 10, target = "weapon", group = "dmg",
    min = function(l) return 1 + (l - 1) * 11 end },
  { id = 17, name = "smite", label = "Pogromca nieumarlych", max = 5, weight = 5, target = "weapon",
    group = "dmg", min = function(l) return 5 + (l - 1) * 8 end },
  { id = 18, name = "bane_of_arthropods", label = "Zmora stawonogow", max = 5, weight = 5,
    target = "weapon", group = "dmg", min = function(l) return 5 + (l - 1) * 8 end },
  { id = 19, name = "knockback", label = "Odrzut", max = 2, weight = 5, target = "weapon",
    min = function(l) return 5 + (l - 1) * 20 end },
  { id = 20, name = "fire_aspect", label = "Zaklety ogien", max = 2, weight = 2, target = "weapon",
    min = function(l) return 10 + (l - 1) * 20 end },
  { id = 21, name = "looting", label = "Grabiez", max = 3, weight = 2, target = "weapon",
    min = function(l) return 15 + (l - 1) * 9 end },
  { id = 32, name = "efficiency", label = "Wydajnosc", max = 5, weight = 10, target = "tool",
    min = function(l) return 1 + (l - 1) * 10 end },
  { id = 33, name = "silk_touch", label = "Jedwabny dotyk", max = 1, weight = 1, target = "tool",
    group = "loot", min = function() return 15 end },
  { id = 34, name = "unbreaking", label = "Niezniszczalnosc", max = 3, weight = 5, target = "durable",
    min = function(l) return 5 + (l - 1) * 8 end },
  { id = 35, name = "fortune", label = "Szczescie", max = 3, weight = 2, target = "tool", group = "loot",
    min = function(l) return 15 + (l - 1) * 9 end },
  { id = 48, name = "power", label = "Moc", max = 5, weight = 10, target = "bow",
    min = function(l) return 1 + (l - 1) * 10 end },
  { id = 49, name = "punch", label = "Uderzenie", max = 2, weight = 2, target = "bow",
    min = function(l) return 12 + (l - 1) * 20 end },
  { id = 50, name = "flame", label = "Plomien", max = 1, weight = 2, target = "bow",
    min = function() return 20 end },
  { id = 51, name = "infinity", label = "Nieskonczonosc", max = 1, weight = 1, target = "bow",
    min = function() return 20 end },
}

M.BY_ID = {}
M.ID = {}
for _, e in ipairs(M.LIST) do
  M.BY_ID[e.id] = e
  M.ID[e.name] = e.id
end

local ROMAN = { "I", "II", "III", "IV", "V" }
function M.roman(n) return ROMAN[n] or tostring(n) end

-- Zaklinalność: im wyższa, tym lepsze zaklęcia
local ENCHANTABILITY = { wood = 15, stone = 5, iron = 14, diamond = 10, gold = 22 }
local ARMOR_ENCH = { leather = 15, chain = 12, iron = 9, diamond = 10, gold = 25 }
local ARMOR_IDS = { leather = 298, chain = 302, iron = 306, diamond = 310, gold = 314 }

function M.enchantability(stack)
  local d = stack and items.get(stack.id)
  if not d then return 0 end
  if d.toolType and d.material then return ENCHANTABILITY[d.material] or 0 end
  if d.armor then
    for mat, base in pairs(ARMOR_IDS) do
      if stack.id >= base and stack.id < base + 4 then return ARMOR_ENCH[mat] end
    end
  end
  if stack.id == 261 then return 1 end
  return 0
end

-- Czy zaklęcie pasuje do przedmiotu
local function fits(e, d)
  local t = e.target
  if t == "armor" then return d.armor ~= nil end
  if t == "helmet" then return d.armor ~= nil and d.armor.slot == 1 end
  if t == "boots" then return d.armor ~= nil and d.armor.slot == 4 end
  if t == "weapon" then return d.toolType == "sword" end
  if t == "tool" then
    return d.toolType == "pickaxe" or d.toolType == "axe" or d.toolType == "shovel"
  end
  if t == "durable" then return d.maxDamage ~= nil and d.id ~= 359 and d.id ~= 259 end
  if t == "bow" then return d.id == 261 end
  return false
end

function M.canEnchant(stack)
  if not stack or stack.ench then return false end
  if stack.count ~= 1 then return false end
  return M.enchantability(stack) > 0
end

-- ---------------------------------------------------------------------------
-- Stół do zaklinania
-- ---------------------------------------------------------------------------
-- Ile biblioteczek otacza stół (pierścień 5x5 na wysokości stołu i +1, max 15)
function M.countBookshelves(world, x, y, z)
  local n = 0
  for dz = -2, 2 do
    for dx = -2, 2 do
      if math.abs(dx) == 2 or math.abs(dz) == 2 then
        -- między stołem a biblioteczką musi być powietrze
        local mx, mz = x + (dx > 0 and 1 or (dx < 0 and -1 or 0)), z + (dz > 0 and 1 or (dz < 0 and -1 or 0))
        if world:getBlock(mx, y, mz) == 0 and world:getBlock(mx, y + 1, mz) == 0 then
          for dy = 0, 1 do
            if world:getBlock(x + dx, y + dy, z + dz) == 47 then n = n + 1 end
          end
        end
      end
    end
  end
  return math.min(15, n)
end

-- Koszty trzech ofert w poziomach (jak w 1.0)
function M.offerLevels(rng, shelves)
  local base = rng:int(1, 8) + floor(shelves / 2) + rng:int(0, shelves)
  return { math.max(floor(base / 3), 1), floor(base * 2 / 3) + 1, math.max(base, shelves * 2) }
end

-- Losuje zaklęcia dla przedmiotu przy danym koszcie. Zwraca tablicę { [id] = poziom }.
function M.select(rng, stack, cost)
  local d = items.get(stack.id)
  local ench = M.enchantability(stack)
  if not d or ench <= 0 then return nil end
  local power = cost + rng:int(0, floor(ench / 2)) + rng:int(0, floor(ench / 2)) + 1
  power = floor(power * (0.85 + rng:next() * 0.3) + 0.5)
  if power < 1 then power = 1 end

  local function candidates(taken)
    local list, total = {}, 0
    for _, e in ipairs(M.LIST) do
      if fits(e, d) and not taken[e.id] then
        local clash = false
        for tid in pairs(taken) do
          local te = M.BY_ID[tid]
          if te.group and te.group == e.group then clash = true end
        end
        if not clash then
          local lvl = 0
          for l = e.max, 1, -1 do
            if power >= e.min(l) then lvl = l break end
          end
          if lvl > 0 then
            list[#list + 1] = { e = e, l = lvl }
            total = total + e.weight
          end
        end
      end
    end
    return list, total
  end

  local result = {}
  local any = false
  repeat
    local list, total = candidates(result)
    if #list == 0 then break end
    local r = rng:next() * total
    for _, c in ipairs(list) do
      r = r - c.e.weight
      if r <= 0 then
        result[c.e.id] = c.l
        any = true
        break
      end
    end
    -- kolejne zaklęcie z malejącą szansą
    local more = rng:next() < (power + 1) / 50
    power = floor(power / 2)
  until not more
  return any and result or nil
end

-- Zaklina przedmiot z oferty 1..3: pobiera poziomy, zwraca true przy sukcesie
function M.apply(game, stack, cost)
  if not M.canEnchant(stack) then return false end
  local creative = game.player.gameMode == "creative"
  if not creative and game.xpLevel < cost then return false end
  local ench = M.select(game.rng, stack, cost)
  if not ench then return false end
  stack.ench = ench
  if not creative then
    game.survival.spendLevels(game, cost)
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Odczyt i opis
-- ---------------------------------------------------------------------------
function M.level(stack, name)
  if not stack or not stack.ench then return 0 end
  return stack.ench[M.ID[name]] or 0
end

-- Linie do podpowiedzi (np. "Ostrosc III")
function M.lines(stack)
  local out = {}
  if not stack or not stack.ench then return out end
  local ids = {}
  for id in pairs(stack.ench) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local e = M.BY_ID[id]
    if e then out[#out + 1] = e.label .. (e.max > 1 and (" " .. M.roman(stack.ench[id])) or "") end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Efekty zaklęć
-- ---------------------------------------------------------------------------
local UNDEAD = { zombie = true, skeleton = true, pigman = true }
local ARTHROPOD = { spider = true }

-- Dodatkowe obrażenia miecza dla danego celu
function M.attackBonus(stack, target)
  if not stack or not stack.ench then return 0 end
  local bonus = M.level(stack, "sharpness") * 1.25
  if target and UNDEAD[target.kind] then bonus = bonus + M.level(stack, "smite") * 2.5 end
  if target and ARTHROPOD[target.kind] then bonus = bonus + M.level(stack, "bane_of_arthropods") * 2.5 end
  return bonus
end

-- Mnożnik szybkości kopania (Wydajność) dla właściwego narzędzia
function M.efficiencyBonus(stack)
  local l = M.level(stack, "efficiency")
  if l <= 0 then return 0 end
  return l * l + 1
end

-- Czy zużyć wytrzymałość (Niezniszczalność daje szansę uniknięcia)
function M.shouldDamage(stack, rnd)
  local l = M.level(stack, "unbreaking")
  if l <= 0 then return true end
  return (rnd or math.random()) < 1 / (l + 1)
end

-- Ochrona pancerza: zmniejszenie obrażeń 0..0.8 dla danego źródła
local PROT_TYPES = {
  protection = function() return 0.75 end,
  fire_protection = function(src) return (src == "fire" or src == "lava") and 1.25 or 0 end,
  blast_protection = function(src) return src == "explosion" and 1.5 or 0 end,
  projectile_protection = function(src) return src == "arrow" and 1.5 or 0 end,
  feather_falling = function(src) return src == "fall" and 2.5 or 0 end,
}
function M.protectionFactor(armorInv, source, rnd)
  local epf = 0
  for i = 1, 4 do
    local s = armorInv.slots[i]
    if s and s.ench then
      for name, fn in pairs(PROT_TYPES) do
        local l = M.level(s, name)
        if l > 0 then epf = epf + floor((6 + l * l) * fn(source) / 3) end
      end
    end
  end
  if epf <= 0 then return 0 end
  epf = math.min(25, epf)
  epf = math.ceil(epf * (0.5 + (rnd or math.random()) * 0.5))
  epf = math.min(20, epf)
  return epf / 25
end

-- Szczęście: mnożnik dropu z rud
function M.fortuneCount(stack, count, rng)
  local l = M.level(stack, "fortune")
  if l <= 0 then return count end
  local extra = rng:int(0, l + 1) - 1
  if extra < 0 then extra = 0 end
  return count * (extra + 1)
end

return M
