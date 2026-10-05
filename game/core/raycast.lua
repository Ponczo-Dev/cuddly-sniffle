-- core/raycast.lua
-- Szukanie bloku pod celownikiem: algorytm DDA (Amanatides & Woo).
-- Idziemy promieniem przez kolejne komórki siatki i w każdej sprawdzamy
-- przecięcie z prostopadłościanem bloku (działa też dla płyt, pochodni itd.).

local blocks = require("core.blocks")

local M = {}

local floor = math.floor
local INF = math.huge

-- Przecięcie promienia z AABB (metoda "slab"). Zwraca odległość i ścianę.
-- Ściana: 1=+X, 2=-X, 3=+Y, 4=-Y, 5=+Z, 6=-Z (jak w blocks.lua)
local function rayBox(ox, oy, oz, dx, dy, dz, x0, y0, z0, x1, y1, z1)
  local tmin, tmax = -INF, INF
  local face = nil

  if dx ~= 0 then
    local t1, t2 = (x0 - ox) / dx, (x1 - ox) / dx
    local f = 2 -- wchodzimy od strony -X
    if t1 > t2 then t1, t2 = t2, t1; f = 1 end
    if t1 > tmin then tmin = t1; face = f end
    if t2 < tmax then tmax = t2 end
  elseif ox < x0 or ox > x1 then
    return nil
  end

  if dy ~= 0 then
    local t1, t2 = (y0 - oy) / dy, (y1 - oy) / dy
    local f = 4
    if t1 > t2 then t1, t2 = t2, t1; f = 3 end
    if t1 > tmin then tmin = t1; face = f end
    if t2 < tmax then tmax = t2 end
  elseif oy < y0 or oy > y1 then
    return nil
  end

  if dz ~= 0 then
    local t1, t2 = (z0 - oz) / dz, (z1 - oz) / dz
    local f = 6
    if t1 > t2 then t1, t2 = t2, t1; f = 5 end
    if t1 > tmin then tmin = t1; face = f end
    if t2 < tmax then tmax = t2 end
  elseif oz < z0 or oz > z1 then
    return nil
  end

  if tmax < 0 or tmin > tmax then return nil end
  return tmin, face
end
M.rayBox = rayBox

M.FACE_NORMALS = {
  { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 },
}

-- Rzuca promień. filter(def, id, meta) -> true, jeśli blok ma być trafiony
-- (domyślnie: bloki "selectable"). Zwraca tabelę:
--   x, y, z (blok), face, nx, ny, nz (normalna ściany), dist, id, meta
function M.cast(world, ox, oy, oz, dx, dy, dz, maxDist, filter)
  local len = math.sqrt(dx * dx + dy * dy + dz * dz)
  if len == 0 then return nil end
  dx, dy, dz = dx / len, dy / len, dz / len

  local x, y, z = floor(ox), floor(oy), floor(oz)
  local stepX = dx > 0 and 1 or -1
  local stepY = dy > 0 and 1 or -1
  local stepZ = dz > 0 and 1 or -1
  local tDeltaX = dx ~= 0 and math.abs(1 / dx) or INF
  local tDeltaY = dy ~= 0 and math.abs(1 / dy) or INF
  local tDeltaZ = dz ~= 0 and math.abs(1 / dz) or INF
  local tMaxX = dx ~= 0 and ((dx > 0 and (x + 1 - ox) or (ox - x)) * tDeltaX) or INF
  local tMaxY = dy ~= 0 and ((dy > 0 and (y + 1 - oy) or (oy - y)) * tDeltaY) or INF
  local tMaxZ = dz ~= 0 and ((dz > 0 and (z + 1 - oz) or (oz - z)) * tDeltaZ) or INF

  local t = 0
  while t <= maxDist do
    local id, meta = world:getBlockAndMeta(x, y, z)
    if id ~= 0 then
      local def = blocks.defs[id]
      local accept
      if filter then accept = def and filter(def, id, meta) else accept = def and def.selectable end
      if accept then
        local bx0, by0, bz0, bx1, by1, bz1 = blocks.bounds(def, meta)
        local dist, face = rayBox(ox, oy, oz, dx, dy, dz,
          x + bx0, y + by0, z + bz0, x + bx1, y + by1, z + bz1)
        if dist and dist <= maxDist then
          if not face then face = 3 end -- start wewnątrz bloku
          local n = M.FACE_NORMALS[face]
          return {
            x = x, y = y, z = z, face = face, nx = n[1], ny = n[2], nz = n[3],
            dist = math.max(0, dist), id = id, meta = meta,
            hx = ox + dx * dist, hy = oy + dy * dist, hz = oz + dz * dist,
          }
        end
      end
    end
    -- krok do następnej komórki
    if tMaxX < tMaxY and tMaxX < tMaxZ then
      x = x + stepX; t = tMaxX; tMaxX = tMaxX + tDeltaX
    elseif tMaxY < tMaxZ then
      y = y + stepY; t = tMaxY; tMaxY = tMaxY + tDeltaY
    else
      z = z + stepZ; t = tMaxZ; tMaxZ = tMaxZ + tDeltaZ
    end
  end
  return nil
end

return M
