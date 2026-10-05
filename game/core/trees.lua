-- core/trees.lua
-- Kształty drzew: dąb, brzoza, świerk. Używane przez generator świata
-- i przy wyrastaniu sadzonek. Rysowanie przez funkcje get/set, więc ten sam
-- kod działa na chunku (generator) i na całym świecie (sadzonka).

local M = {}

local LOG, LEAVES = 17, 18
local AIR, TALL_GRASS, SAPLING, SNOW_LAYER = 0, 31, 6, 78

local function canReplace(id)
  return id == AIR or id == LEAVES or id == TALL_GRASS or id == SAPLING or id == SNOW_LAYER
end

-- kind: 0 = dąb, 1 = świerk, 2 = brzoza
function M.generate(get, set, x, y, z, kind, rng, checkSpace)
  local below = get(x, y - 1, z)
  if below ~= 2 and below ~= 3 then return false end

  if kind == 1 then
    -- świerk: wysoki pień, stożek z liści
    local height = rng:int(6, 9)
    if y + height + 1 >= 128 then return false end
    if checkSpace then
      for i = 1, height do
        if not canReplace(get(x, y + i, z)) then return false end
      end
    end
    local radius = 0
    local maxR = rng:int(2, 3)
    for ly = y + height, y + 2, -1 do
      for dx = -radius, radius do
        for dz = -radius, radius do
          if math.abs(dx) + math.abs(dz) <= radius + 1 or radius == 0 then
            if not (dx == 0 and dz == 0 and ly < y + height) then
              if canReplace(get(x + dx, ly, z + dz)) and get(x + dx, ly, z + dz) ~= LEAVES then
                set(x + dx, ly, z + dz, LEAVES, 1)
              end
            end
          end
        end
      end
      radius = radius + 1
      if radius > maxR then radius = 1 end
    end
    set(x, y + height + 1, z, LEAVES, 1)
    for i = 0, height - 1 do set(x, y + i, z, LOG, 1) end
    set(x, y - 1, z, 3, 0)
    return true
  end

  -- dąb i brzoza
  local birch = kind == 2
  local height = birch and rng:int(5, 7) or rng:int(4, 6)
  if y + height + 2 >= 128 then return false end
  if checkSpace then
    for i = 1, height + 1 do
      if not canReplace(get(x, y + i, z)) then return false end
    end
  end
  local meta = birch and 2 or 0
  local top = y + height
  for ly = top - 3, top do
    local r = (ly >= top - 1) and 1 or 2
    for dx = -r, r do
      for dz = -r, r do
        local corner = math.abs(dx) == r and math.abs(dz) == r
        -- zaokrąglone narożniki (losowo brakujące jak w MC)
        if not corner or (ly < top and rng:next() < 0.5) then
          if canReplace(get(x + dx, ly, z + dz)) and get(x + dx, ly, z + dz) ~= LEAVES then
            set(x + dx, ly, z + dz, LEAVES, meta)
          end
        end
      end
    end
  end
  set(x, top + 1, z, LEAVES, meta)
  for i = 0, height - 1 do set(x, y + i, z, LOG, meta) end
  set(x, y - 1, z, 3, 0)
  return true
end

-- Wyrośnięcie drzewa w świecie (z sadzonki)
function M.grow(world, x, y, z, kind, rng, checkSpace)
  local get = function(a, b, c) return world:getBlock(a, b, c) end
  local set = function(a, b, c, id, meta) world:setBlock(a, b, c, id, meta) end
  return M.generate(get, set, x, y, z, kind, rng, checkSpace)
end

return M
