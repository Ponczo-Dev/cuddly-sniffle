-- core/furnace.lua
-- Piec: slot 1 = składnik, 2 = paliwo, 3 = wynik.
-- Przetopienie trwa 200 ticków (10 s). Paliwo pali się przez fuelTime ticków.
-- Palący się piec zmienia blok na "lit_furnace" (świeci).

local items = require("core.items")
local recipes = require("core.recipes")

local M = {}

M.COOK_TIME = 200

local function canSmelt(tile)
  local inv = tile.inventory
  local input = inv.slots[1]
  if not input then return false end
  local result = recipes.smeltResult(input)
  if not result then return false end
  local out = inv.slots[3]
  if not out then return true end
  if not items.canMerge(out, result) then return false end
  return out.count + result.count <= items.maxStack(out.id)
end
M.canSmelt = canSmelt

function M.tick(game, tile, x, y, z)
  local inv = tile.inventory
  local wasBurning = tile.burn > 0
  if tile.burn > 0 then tile.burn = tile.burn - 1 end

  if tile.burn == 0 and canSmelt(tile) then
    local fuel = inv.slots[2]
    local t = items.fuelTime(fuel)
    if t > 0 then
      tile.burn, tile.burnMax = t, t
      if fuel.id == 327 then
        inv.slots[2] = { id = 325, count = 1, damage = 0 } -- zostaje puste wiadro
      else
        inv:decrement(2, 1)
      end
      inv.changed = true
    end
  end

  if tile.burn > 0 and canSmelt(tile) then
    tile.cook = tile.cook + 1
    if tile.cook >= M.COOK_TIME then
      tile.cook = 0
      local result, xp = recipes.smeltResult(inv.slots[1])
      local out = inv.slots[3]
      if out then
        out.count = out.count + result.count
      else
        inv.slots[3] = { id = result.id, count = result.count, damage = result.damage }
      end
      inv:decrement(1, 1)
      tile.xp = (tile.xp or 0) + (xp or 0)
      inv.changed = true
    end
  else
    tile.cook = 0
  end

  local burning = tile.burn > 0
  if burning ~= wasBurning then
    local id = game.world:getBlock(x, y, z)
    local meta = game.world:getMeta(x, y, z)
    if burning and id == 61 then
      game.world:setBlock(x, y, z, 62, meta)
    elseif not burning and id == 62 then
      game.world:setBlock(x, y, z, 61, meta)
    end
    game.world:setTile(x, y, z, tile)
  end
end

-- Zabranie wyniku daje zgromadzone doświadczenie
function M.takeXp(tile)
  local xp = tile.xp or 0
  local whole = math.floor(xp)
  if math.random() < xp - whole then whole = whole + 1 end
  tile.xp = 0
  return whole
end

return M
