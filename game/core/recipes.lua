-- core/recipes.lua
-- Receptury craftingu (2x2 w ekwipunku, 3x3 na stole) i przetapiania w piecu.
-- Receptura kształtowa: wzór z liter + klucz litera -> przedmiot.
-- Receptura bezkształtna: lista składników w dowolnym układzie.

local items = require("core.items")

local M = {}

M.shaped = {}
M.shapeless = {}
M.smelting = {}

local function key(id, damage) return { id = id, damage = damage } end

-- pattern: { "XXX", " # ", " # " }, map: { X = id | {id, damage}, ... }
local function shaped(result, count, pattern, map, resultDamage)
  local h = #pattern
  local w = 0
  for _, row in ipairs(pattern) do if #row > w then w = #row end end
  local cells = {}
  for y = 1, h do
    for x = 1, w do
      local ch = pattern[y]:sub(x, x)
      local m = map[ch]
      if m then
        if type(m) == "number" then m = key(m) end
        cells[(y - 1) * w + x] = m
      else
        cells[(y - 1) * w + x] = false
      end
    end
  end
  M.shaped[#M.shaped + 1] = { w = w, h = h, cells = cells,
    result = { id = result, count = count or 1, damage = resultDamage or 0 } }
end

local function shapeless(result, count, list, resultDamage)
  local ing = {}
  for i, m in ipairs(list) do
    if type(m) == "number" then m = key(m) end
    ing[i] = m
  end
  M.shapeless[#M.shapeless + 1] = { ingredients = ing,
    result = { id = result, count = count or 1, damage = resultDamage or 0 } }
end

local function smelt(input, output, count, xp, outDamage, inDamage)
  M.smelting[#M.smelting + 1] = { input = input, inDamage = inDamage, xp = xp or 0.1,
    result = { id = output, count = count or 1, damage = outDamage or 0 } }
end

local id = items.id

-- ---------------------------------------------------------------------------
-- Podstawy
-- ---------------------------------------------------------------------------
shaped(id("planks"), 4, { "#" }, { ["#"] = id("log") })
shaped(id("stick"), 4, { "#", "#" }, { ["#"] = id("planks") })
shaped(id("crafting_table"), 1, { "##", "##" }, { ["#"] = id("planks") })
shaped(id("furnace"), 1, { "###", "# #", "###" }, { ["#"] = id("cobblestone") })
shaped(id("chest"), 1, { "###", "# #", "###" }, { ["#"] = id("planks") })
shaped(id("torch"), 4, { "C", "S" }, { C = id("coal"), S = id("stick") })
shaped(id("torch"), 4, { "C", "S" }, { C = { id = id("coal"), damage = 1 }, S = id("stick") })

-- ---------------------------------------------------------------------------
-- Narzędzia i broń dla każdego materiału
-- ---------------------------------------------------------------------------
local MATS = {
  { "wood", id("planks") }, { "stone", id("cobblestone") }, { "iron", id("iron_ingot") },
  { "gold", id("gold_ingot") }, { "diamond", id("diamond") },
}
local S = id("stick")
for _, m in ipairs(MATS) do
  local name, mat = m[1], m[2]
  shaped(id(name .. "_pickaxe"), 1, { "XXX", " S ", " S " }, { X = mat, S = S })
  shaped(id(name .. "_axe"), 1, { "XX", "XS", " S" }, { X = mat, S = S })
  shaped(id(name .. "_shovel"), 1, { "X", "S", "S" }, { X = mat, S = S })
  shaped(id(name .. "_sword"), 1, { "X", "X", "S" }, { X = mat, S = S })
  shaped(id(name .. "_hoe"), 1, { "XX", " S", " S" }, { X = mat, S = S })
end

-- ---------------------------------------------------------------------------
-- Pancerz
-- ---------------------------------------------------------------------------
local ARMOR_MATS = {
  { "leather", id("leather") }, { "iron", id("iron_ingot") }, { "gold", id("gold_ingot") },
  { "diamond", id("diamond") },
}
for _, m in ipairs(ARMOR_MATS) do
  local name, mat = m[1], m[2]
  shaped(id(name .. "_helmet"), 1, { "XXX", "X X" }, { X = mat })
  shaped(id(name .. "_chestplate"), 1, { "X X", "XXX", "XXX" }, { X = mat })
  shaped(id(name .. "_leggings"), 1, { "XXX", "X X", "X X" }, { X = mat })
  shaped(id(name .. "_boots"), 1, { "X X", "X X" }, { X = mat })
end

-- ---------------------------------------------------------------------------
-- Bloki
-- ---------------------------------------------------------------------------
local function block9(blockName, itemId, itemDamage)
  local m = itemDamage and { id = itemId, damage = itemDamage } or itemId
  shaped(id(blockName), 1, { "###", "###", "###" }, { ["#"] = m })
  shapeless(itemId, 9, { id(blockName) }, itemDamage)
end
block9("iron_block", id("iron_ingot"))
block9("gold_block", id("gold_ingot"))
block9("diamond_block", id("diamond"))
block9("lapis_block", id("dye"), 4)

shaped(id("sandstone"), 1, { "##", "##" }, { ["#"] = id("sand") })
shaped(id("bricks"), 1, { "##", "##" }, { ["#"] = id("brick") })
shaped(id("clay"), 1, { "##", "##" }, { ["#"] = id("clay_ball") })
shaped(id("snow"), 1, { "##", "##" }, { ["#"] = id("snowball") })
shaped(id("wool"), 1, { "##", "##" }, { ["#"] = id("string") })
shaped(id("stone_bricks"), 4, { "##", "##" }, { ["#"] = id("stone") })
shaped(id("slab"), 3, { "###" }, { ["#"] = id("cobblestone") })
shaped(id("tnt"), 1, { "X#X", "#X#", "X#X" }, { X = id("gunpowder"), ["#"] = id("sand") })
shaped(id("bookshelf"), 1, { "###", "XXX", "###" }, { ["#"] = id("planks"), X = id("book") })
shaped(id("ladder"), 2, { "S S", "SSS", "S S" }, { S = S })
shaped(id("door_item"), 1, { "##", "##", "##" }, { ["#"] = id("planks") })
shaped(id("bed_item"), 1, { "WWW", "PPP" }, { W = id("wool"), P = id("planks") })
shaped(id("jack_o_lantern"), 1, { "P", "T" }, { P = id("pumpkin"), T = id("torch") })

-- kolorowa wełna z barwników (uproszczone kolory)
shapeless(id("wool"), 1, { id("wool"), { id = id("dye"), damage = 1 } }, 1)

-- ---------------------------------------------------------------------------
-- Przedmioty
-- ---------------------------------------------------------------------------
shaped(id("bowl"), 4, { "# #", " # " }, { ["#"] = id("planks") })
shaped(id("mushroom_stew"), 1, { "B", "R", "W" },
  { B = id("brown_mushroom"), R = id("red_mushroom"), W = id("bowl") })
shaped(id("bread"), 1, { "###" }, { ["#"] = id("wheat_item") })
shaped(id("cookie"), 8, { "#C#" }, { ["#"] = id("wheat_item"), C = { id = id("dye"), damage = 3 } })
shaped(id("bucket"), 1, { "# #", " # " }, { ["#"] = id("iron_ingot") })
shaped(id("shears"), 1, { " #", "# " }, { ["#"] = id("iron_ingot") })
shapeless(id("flint_and_steel"), 1, { id("iron_ingot"), id("flint") })
shaped(id("bow"), 1, { " #X", "# X", " #X" }, { ["#"] = S, X = id("string") })
shaped(id("arrow"), 4, { "F", "S", "P" }, { F = id("flint"), S = S, P = id("feather") })
shaped(id("paper"), 3, { "###" }, { ["#"] = id("sugar_cane_item") })
shapeless(id("book"), 1, { id("paper"), id("paper"), id("paper") })
shapeless(id("sugar"), 1, { id("sugar_cane_item") })
shapeless(id("dye"), 3, { id("bone") }, 15)
shapeless(id("dye"), 2, { id("rose") }, 1)
shapeless(id("dye"), 2, { id("dandelion") }, 11)
shaped(id("golden_apple"), 1, { "###", "#A#", "###" }, { ["#"] = id("gold_block"),
  A = id("apple") })

-- ---------------------------------------------------------------------------
-- Piec
-- ---------------------------------------------------------------------------
smelt(id("iron_ore"), id("iron_ingot"), 1, 0.7)
smelt(id("gold_ore"), id("gold_ingot"), 1, 1.0)
smelt(id("diamond_ore"), id("diamond"), 1, 1.0)
smelt(id("sand"), id("glass"), 1, 0.1)
smelt(id("cobblestone"), id("stone"), 1, 0.1)
smelt(id("log"), id("coal"), 1, 0.15, 1)
smelt(id("clay_ball"), id("brick"), 1, 0.3)
smelt(id("raw_porkchop"), id("cooked_porkchop"), 1, 0.35)
smelt(id("raw_beef"), id("steak"), 1, 0.35)
smelt(id("raw_chicken"), id("cooked_chicken"), 1, 0.35)
smelt(id("cactus"), id("dye"), 1, 0.2, 2)

-- ---------------------------------------------------------------------------
-- Dopasowanie siatki craftingu
-- ---------------------------------------------------------------------------
local function matches(m, stack)
  if not m then return stack == nil end
  if not stack then return false end
  if stack.id ~= m.id then return false end
  if m.damage ~= nil and (stack.damage or 0) ~= m.damage then return false end
  return true
end

-- grid: tablica size*size stosów (indeks (y-1)*size + x), może mieć dziury (nil)
-- Zwraca stos wyniku albo nil.
function M.match(grid, size)
  -- obszar zajęty przez przedmioty
  local minX, minY, maxX, maxY = size + 1, size + 1, 0, 0
  local count = 0
  for y = 1, size do
    for x = 1, size do
      if grid[(y - 1) * size + x] then
        count = count + 1
        if x < minX then minX = x end
        if x > maxX then maxX = x end
        if y < minY then minY = y end
        if y > maxY then maxY = y end
      end
    end
  end
  if count == 0 then return nil end
  local w, h = maxX - minX + 1, maxY - minY + 1

  for _, r in ipairs(M.shaped) do
    if r.w == w and r.h == h then
      for mirror = 0, 1 do
        local ok = true
        for y = 1, h do
          for x = 1, w do
            local rx = mirror == 1 and (w - x + 1) or x
            local m = r.cells[(y - 1) * w + rx]
            local s = grid[(minY + y - 2) * size + (minX + x - 1)]
            if not matches(m or nil, s) then ok = false; break end
          end
          if not ok then break end
        end
        if ok then
          return { id = r.result.id, count = r.result.count, damage = r.result.damage }
        end
      end
    end
  end

  for _, r in ipairs(M.shapeless) do
    if #r.ingredients == count then
      local used = {}
      local ok = true
      for _, m in ipairs(r.ingredients) do
        local found = false
        for i = 1, size * size do
          if not used[i] and grid[i] and matches(m, grid[i]) then
            used[i] = true
            found = true
            break
          end
        end
        if not found then ok = false; break end
      end
      if ok then
        return { id = r.result.id, count = r.result.count, damage = r.result.damage }
      end
    end
  end
  return nil
end

-- Wynik przetopienia stosu (albo nil)
function M.smeltResult(stack)
  if not stack then return nil end
  for _, r in ipairs(M.smelting) do
    if r.input == stack.id and (r.inDamage == nil or r.inDamage == (stack.damage or 0)) then
      return r.result, r.xp
    end
  end
  return nil
end

return M
