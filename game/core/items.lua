-- core/items.lua
-- Rejestr przedmiotów (ID od 256, jak w Minecraft Beta) + wspólny dostęp
-- do bloków jako przedmiotów. Stos przedmiotów to tabela:
--   { id = 257, count = 1, damage = 0 }
-- damage = zużycie narzędzia albo podtyp (np. kolor barwnika, węgiel drzewny).

local blocks = require("core.blocks")

local I = {}
I.defs = {}
I.ids = {}

-- Poziomy materiałów narzędzi: tier (co można wydobyć), speed, durability, damage
I.MATERIALS = {
  wood = { tier = 0, speed = 2, durability = 59, damage = 0, label = "drewniany" },
  stone = { tier = 1, speed = 4, durability = 131, damage = 1, label = "kamienny" },
  iron = { tier = 2, speed = 6, durability = 250, damage = 2, label = "zelazny" },
  diamond = { tier = 3, speed = 8, durability = 1561, damage = 3, label = "diamentowy" },
  gold = { tier = 0, speed = 12, durability = 32, damage = 0, label = "zloty" },
}

function I.define(def)
  assert(def.id and def.name)
  def.label = def.label or def.name
  def.stack = def.stack or (def.maxDamage and 1 or 64)
  def.isItem = true
  I.defs[def.id] = def
  I.ids[def.name] = def.id
  return def
end

-- Definicja przedmiotu albo bloku o danym id
function I.get(id)
  if id < 256 then return blocks.defs[id] end
  return I.defs[id]
end

function I.id(name)
  local id = I.ids[name] or blocks.ids[name]
  if not id then error("Nieznany przedmiot: " .. tostring(name), 2) end
  return id
end

function I.maxStack(id)
  local d = I.get(id)
  return d and d.stack or 64
end

function I.label(stack)
  local d = I.get(stack.id)
  if not d then return "?" end
  if d.labelFn then return d.labelFn(stack) end
  return d.label
end

function I.newStack(id, count, damage)
  return { id = id, count = count or 1, damage = damage or 0 }
end

-- Czy dwa stosy można połączyć
function I.canMerge(a, b)
  if not a or not b then return false end
  if a.id ~= b.id then return false end
  local d = I.get(a.id)
  if d and d.maxDamage then return false end -- narzędzia się nie łączą
  return (a.damage or 0) == (b.damage or 0)
end

-- ---------------------------------------------------------------------------
-- Narzędzia
-- ---------------------------------------------------------------------------
local TOOL_TYPES = {
  pickaxe = { label = "Kilof", attack = 2 },
  axe = { label = "Siekiera", attack = 3 },
  shovel = { label = "Lopata", attack = 1 },
  sword = { label = "Miecz", attack = 4 },
  hoe = { label = "Motyka", attack = 0 },
}

local function tool(id, toolType, matName)
  local m = I.MATERIALS[matName]
  local t = TOOL_TYPES[toolType]
  I.define {
    id = id, name = matName .. "_" .. toolType,
    label = t.label .. " " .. m.label,
    toolType = toolType, material = matName, tier = m.tier, speed = m.speed,
    maxDamage = m.durability, attack = 1 + t.attack + m.damage,
    icon = toolType, iconMaterial = matName,
  }
end

tool(256, "shovel", "iron"); tool(257, "pickaxe", "iron"); tool(258, "axe", "iron")
tool(267, "sword", "iron")
tool(268, "sword", "wood"); tool(269, "shovel", "wood"); tool(270, "pickaxe", "wood")
tool(271, "axe", "wood")
tool(272, "sword", "stone"); tool(273, "shovel", "stone"); tool(274, "pickaxe", "stone")
tool(275, "axe", "stone")
tool(276, "sword", "diamond"); tool(277, "shovel", "diamond"); tool(278, "pickaxe", "diamond")
tool(279, "axe", "diamond")
tool(283, "sword", "gold"); tool(284, "shovel", "gold"); tool(285, "pickaxe", "gold")
tool(286, "axe", "gold")
tool(290, "hoe", "wood"); tool(291, "hoe", "stone"); tool(292, "hoe", "iron")
tool(293, "hoe", "diamond"); tool(294, "hoe", "gold")

I.define { id = 259, name = "flint_and_steel", label = "Krzesiwo", maxDamage = 64,
  use = "flint_and_steel", icon = "flint_and_steel" }
I.define { id = 359, name = "shears", label = "Nozyce", maxDamage = 238, toolType = "shears",
  speed = 1, tier = 0, icon = "shears" }
I.define { id = 261, name = "bow", label = "Luk", maxDamage = 384, use = "bow", icon = "bow" }
I.define { id = 262, name = "arrow", label = "Strzala", icon = "arrow" }

-- ---------------------------------------------------------------------------
-- Surowce
-- ---------------------------------------------------------------------------
I.define { id = 263, name = "coal", label = "Wegiel", icon = "coal",
  labelFn = function(s) return s.damage == 1 and "Wegiel drzewny" or "Wegiel" end }
I.define { id = 264, name = "diamond", label = "Diament", icon = "diamond" }
I.define { id = 265, name = "iron_ingot", label = "Sztabka zelaza", icon = "ingot",
  iconColor = { 220, 220, 220 } }
I.define { id = 266, name = "gold_ingot", label = "Sztabka zlota", icon = "ingot",
  iconColor = { 250, 220, 60 } }
I.define { id = 280, name = "stick", label = "Patyk", icon = "stick" }
I.define { id = 281, name = "bowl", label = "Miska", icon = "bowl" }
I.define { id = 287, name = "string", label = "Nic", icon = "string" }
I.define { id = 288, name = "feather", label = "Pioro", icon = "feather" }
I.define { id = 289, name = "gunpowder", label = "Proch", icon = "gunpowder" }
I.define { id = 295, name = "seeds", label = "Nasiona", icon = "seeds", plant = 59 }
I.define { id = 296, name = "wheat_item", label = "Pszenica", icon = "wheat" }
I.define { id = 318, name = "flint", label = "Krzemien", icon = "flint" }
I.define { id = 331, name = "redstone", label = "Czerwony pyl", icon = "redstone" }
I.define { id = 332, name = "snowball", label = "Sniezka", icon = "snowball", stack = 16,
  use = "throw" }
I.define { id = 334, name = "leather", label = "Skora", icon = "leather" }
I.define { id = 336, name = "brick", label = "Cegla", icon = "brick" }
I.define { id = 337, name = "clay_ball", label = "Kulka gliny", icon = "clay_ball" }
I.define { id = 338, name = "sugar_cane_item", label = "Trzcina cukrowa", icon = "sugar_cane",
  plant = 83 }
I.define { id = 339, name = "paper", label = "Papier", icon = "paper" }
I.define { id = 340, name = "book", label = "Ksiazka", icon = "book" }
I.define { id = 341, name = "slimeball", label = "Kulka szlamu", icon = "slimeball" }
I.define { id = 344, name = "egg", label = "Jajko", icon = "egg", stack = 16, use = "throw" }
I.define { id = 352, name = "bone", label = "Kosc", icon = "bone" }
I.define { id = 353, name = "sugar", label = "Cukier", icon = "sugar" }
-- Barwnik: damage 15 = mączka kostna, 4 = lapis lazuli
I.define { id = 351, name = "dye", label = "Barwnik", icon = "dye",
  labelFn = function(s)
    if s.damage == 15 then return "Maczka kostna" end
    if s.damage == 4 then return "Lapis lazuli" end
    return "Barwnik"
  end,
  use = "dye" }

-- ---------------------------------------------------------------------------
-- Jedzenie (Beta 1.8): hunger = punkty głodu, saturation = mnożnik nasycenia
-- ---------------------------------------------------------------------------
local function food(id, name, label, hunger, sat, extra)
  local d = { id = id, name = name, label = label, icon = name,
    food = { hunger = hunger, saturation = sat } }
  for k, v in pairs(extra or {}) do
    if k == "poison" or k == "alwaysEdible" or k == "returns" then d.food[k] = v else d[k] = v end
  end
  return I.define(d)
end
food(260, "apple", "Jablko", 4, 0.3)
food(282, "mushroom_stew", "Zupa grzybowa", 6, 0.6, { stack = 1, returns = 281 })
food(297, "bread", "Chleb", 5, 0.6)
food(319, "raw_porkchop", "Surowy schab", 3, 0.3)
food(320, "cooked_porkchop", "Pieczony schab", 8, 0.8)
food(322, "golden_apple", "Zlote jablko", 4, 1.2, { alwaysEdible = true })
food(357, "cookie", "Ciastko", 2, 0.1)
food(360, "melon_slice", "Kawalek arbuza", 2, 0.3)
food(363, "raw_beef", "Surowa wolowina", 3, 0.3)
food(364, "steak", "Stek", 8, 0.8)
food(365, "raw_chicken", "Surowy kurczak", 2, 0.3, { poison = { chance = 0.3, ticks = 600 } })
food(366, "cooked_chicken", "Pieczony kurczak", 6, 0.6)
food(367, "rotten_flesh", "Zgnile mieso", 4, 0.1, { poison = { chance = 0.8, ticks = 600 } })

-- ---------------------------------------------------------------------------
-- Wiadra
-- ---------------------------------------------------------------------------
I.define { id = 325, name = "bucket", label = "Wiadro", icon = "bucket", stack = 16,
  use = "bucket" }
I.define { id = 326, name = "water_bucket", label = "Wiadro wody", icon = "water_bucket",
  stack = 1, use = "bucket", fluid = 8 }
I.define { id = 327, name = "lava_bucket", label = "Wiadro lawy", icon = "lava_bucket",
  stack = 1, use = "bucket", fluid = 10, fuel = 20000 }
I.define { id = 335, name = "milk_bucket", label = "Wiadro mleka", icon = "milk_bucket",
  stack = 1, use = "milk" }

-- ---------------------------------------------------------------------------
-- Przedmioty stawiające bloki
-- ---------------------------------------------------------------------------
I.define { id = 324, name = "door_item", label = "Drzwi", icon = "door", stack = 1,
  placeBlock = 64 }
I.define { id = 355, name = "bed_item", label = "Lozko", icon = "bed", stack = 1,
  placeBlock = 26 }

-- ---------------------------------------------------------------------------
-- Pancerz: slot 1 = hełm, 2 = napierśnik, 3 = spodnie, 4 = buty
-- ---------------------------------------------------------------------------
local ARMOR_PARTS = {
  { "helmet", "Helm", 11 }, { "chestplate", "Napiersnik", 16 },
  { "leggings", "Spodnie", 15 }, { "boots", "Buty", 13 },
}
-- punkty ochrony dla [materiał][część]
local ARMOR_POINTS = {
  leather = { 1, 3, 2, 1 }, chain = { 2, 5, 4, 1 }, iron = { 2, 6, 5, 2 },
  diamond = { 3, 8, 6, 3 }, gold = { 2, 5, 3, 1 },
}
local ARMOR_DURABILITY = { leather = 5, chain = 15, iron = 15, diamond = 33, gold = 7 }
local ARMOR_LABEL = { leather = "skorzany", chain = "kolczy", iron = "zelazny",
  diamond = "diamentowy", gold = "zloty" }
local ARMOR_BASE = { leather = 298, chain = 302, iron = 306, diamond = 310, gold = 314 }

for mat, base in pairs(ARMOR_BASE) do
  for slot = 1, 4 do
    local part = ARMOR_PARTS[slot]
    I.define {
      id = base + slot - 1, name = mat .. "_" .. part[1],
      label = part[2] .. " " .. ARMOR_LABEL[mat],
      armor = { slot = slot, points = ARMOR_POINTS[mat][slot] },
      maxDamage = part[3] * ARMOR_DURABILITY[mat],
      icon = part[1], iconMaterial = mat,
    }
  end
end

-- ---------------------------------------------------------------------------
-- Paliwo do pieca (w tickach; 200 ticków = 1 przetopiony przedmiot)
-- ---------------------------------------------------------------------------
I.FUEL = {
  [263] = 1600, [327] = 20000, [280] = 100, [5] = 300, [17] = 300, [6] = 100,
  [58] = 300, [54] = 300, [47] = 300, [268] = 200, [269] = 200, [270] = 200, [271] = 200,
  [290] = 200,
}
function I.fuelTime(stack)
  if not stack then return 0 end
  return I.FUEL[stack.id] or 0
end

-- ---------------------------------------------------------------------------
-- Kopanie: prędkość niszczenia bloku danym przedmiotem (jak w Beta)
-- ---------------------------------------------------------------------------
-- Zwraca mnożnik szybkości narzędzia dla bloku
function I.toolSpeed(stack, blockDef)
  local d = stack and I.get(stack.id)
  if not d or not d.toolType then return 1 end
  local t = d.toolType
  if t == "sword" then
    if blockDef.name == "cobweb" then return 15 end
    return 1.5
  end
  if t == "shears" then
    if blockDef.name == "leaves" or blockDef.name == "cobweb" then return 15 end
    if blockDef.name == "wool" then return 5 end
    return 1
  end
  if blockDef.tool == t then return d.speed end
  return 1
end

-- Czy tym przedmiotem z bloku wypadnie drop
function I.canHarvest(stack, blockDef)
  if blockDef.tier == nil then
    -- liście i pajęczyna dają drop tylko z odpowiednim narzędziem
    if blockDef.name == "cobweb" then
      local d = stack and I.get(stack.id)
      return d and (d.toolType == "shears" or d.toolType == "sword") or false
    end
    return true
  end
  local d = stack and I.get(stack.id)
  if not d or d.toolType ~= blockDef.tool then return false end
  return (d.tier or 0) >= blockDef.tier
end

-- Postęp niszczenia na tick (1.0 = zniszczony)
function I.breakStrength(stack, blockDef, onGround, inWater)
  local h = blockDef.hardness
  if h < 0 then return 0 end
  if h == 0 then return 1 end
  local speed = I.toolSpeed(stack, blockDef)
  local s
  if not I.canHarvest(stack, blockDef) and blockDef.tier ~= nil then
    s = 1 / h / 100
  else
    s = speed / h / 30
  end
  if inWater then s = s / 5 end
  if not onGround then s = s / 5 end
  return s
end

-- Obrażenia zadawane przedmiotem w ręku
function I.attackDamage(stack)
  local d = stack and I.get(stack.id)
  if d and d.attack then return d.attack end
  return 1
end

return I
