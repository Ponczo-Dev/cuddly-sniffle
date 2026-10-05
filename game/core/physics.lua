-- core/physics.lua
-- Kolizje bytów (gracz, moby, przedmioty) z blokami. Algorytm jak w MC:
-- zbieramy prostopadłościany bloków wokół ruchu, potem przycinamy ruch
-- najpierw w osi Y, potem X i Z. Wchodzenie na stopnie (np. płyty).
--
-- Byt (entity) ma pola: x, y, z (środek stóp), width, height,
-- onGround, collidedH, collidedV, stepHeight (opcjonalnie).

local blocks = require("core.blocks")

local M = {}

local floor = math.floor
local defs = blocks.defs
local SOLID = blocks.SOLID

-- Bufor na prostopadłościany: płaska tablica po 6 liczb (bez alokacji)
local boxes = {}
local boxCount = 0

local function addBox(x0, y0, z0, x1, y1, z1)
  local i = boxCount * 6
  boxes[i + 1], boxes[i + 2], boxes[i + 3] = x0, y0, z0
  boxes[i + 4], boxes[i + 5], boxes[i + 6] = x1, y1, z1
  boxCount = boxCount + 1
end

-- Zbiera kolizyjne prostopadłościany bloków w obszarze.
-- Niezaładowane chunki są traktowane jak lite bloki (nie spadniemy w nicość).
local function collect(world, minX, minY, minZ, maxX, maxY, maxZ)
  boxCount = 0
  for x = floor(minX), floor(maxX) do
    for z = floor(minZ), floor(maxZ) do
      if not world:isLoadedAt(x, z) then
        addBox(x, floor(minY) - 1, z, x + 1, floor(maxY) + 2, z + 1)
      else
        for y = floor(minY) - 1, floor(maxY) do
          local id, meta = world:getBlockAndMeta(x, y, z)
          if SOLID[id] == 1 then
            local def = defs[id]
            if def.bounds then
              local x0, y0, z0, x1, y1, z1 = def.bounds(meta)
              -- płotki/skrzynie itp. mają własny kształt kolizji
              if def.collisionBounds then
                x0, y0, z0, x1, y1, z1 = def.collisionBounds(meta)
              end
              addBox(x + x0, y + y0, z + z0, x + x1, y + y1, z + z1)
            else
              addBox(x, y, z, x + 1, y + 1, z + 1)
            end
          end
        end
      end
    end
  end
end
M.collect = collect

-- Przycina przesunięcie d w danej osi tak, żeby AABB nie weszło w żaden blok
-- axis: 1 = X, 2 = Y, 3 = Z
local function clip(axis, d, bx0, by0, bz0, bx1, by1, bz1)
  for i = 0, boxCount - 1 do
    local o = i * 6
    local x0, y0, z0 = boxes[o + 1], boxes[o + 2], boxes[o + 3]
    local x1, y1, z1 = boxes[o + 4], boxes[o + 5], boxes[o + 6]
    if axis == 2 then
      if bx1 > x0 and bx0 < x1 and bz1 > z0 and bz0 < z1 then
        if d > 0 and by1 <= y0 then
          local m = y0 - by1
          if m < d then d = m end
        elseif d < 0 and by0 >= y1 then
          local m = y1 - by0
          if m > d then d = m end
        end
      end
    elseif axis == 1 then
      if by1 > y0 and by0 < y1 and bz1 > z0 and bz0 < z1 then
        if d > 0 and bx1 <= x0 then
          local m = x0 - bx1
          if m < d then d = m end
        elseif d < 0 and bx0 >= x1 then
          local m = x1 - bx0
          if m > d then d = m end
        end
      end
    else
      if bx1 > x0 and bx0 < x1 and by1 > y0 and by0 < y1 then
        if d > 0 and bz1 <= z0 then
          local m = z0 - bz1
          if m < d then d = m end
        elseif d < 0 and bz0 >= z1 then
          local m = z1 - bz0
          if m > d then d = m end
        end
      end
    end
  end
  return d
end

-- Ruch z kolizjami w kolejności Y, X, Z. Zwraca faktyczne przesunięcie.
local function moveBox(bx0, by0, bz0, bx1, by1, bz1, dx, dy, dz)
  dy = clip(2, dy, bx0, by0, bz0, bx1, by1, bz1)
  by0, by1 = by0 + dy, by1 + dy
  dx = clip(1, dx, bx0, by0, bz0, bx1, by1, bz1)
  bx0, bx1 = bx0 + dx, bx1 + dx
  dz = clip(3, dz, bx0, by0, bz0, bx1, by1, bz1)
  return dx, dy, dz
end

-- Czy AABB koliduje z jakimkolwiek blokiem
function M.intersects(world, x0, y0, z0, x1, y1, z1)
  collect(world, x0, y0, z0, x1, y1, z1)
  for i = 0, boxCount - 1 do
    local o = i * 6
    if x1 > boxes[o + 1] and x0 < boxes[o + 4] and y1 > boxes[o + 2] and y0 < boxes[o + 5]
      and z1 > boxes[o + 3] and z0 < boxes[o + 6] then
      return true
    end
  end
  return false
end

-- Przesuwa byt o (dx, dy, dz) z kolizjami, ustawia onGround/collidedH/collidedV.
-- sneakEdge = true: nie pozwala zejść z krawędzi (kucanie).
function M.move(world, e, dx, dy, dz, sneakEdge)
  local hw = e.width / 2
  local bx0, by0, bz0 = e.x - hw, e.y, e.z - hw
  local bx1, by1, bz1 = e.x + hw, e.y + e.height, e.z + hw

  -- kucanie: zmniejszamy ruch, dopóki pod nogami jest grunt
  if sneakEdge and e.onGround then
    local step = 0.05
    while dx ~= 0 and not M.intersects(world, bx0 + dx, by0 - 1, bz0, bx1 + dx, by0, bz1) do
      if math.abs(dx) < step then dx = 0
      elseif dx > 0 then dx = dx - step else dx = dx + step end
    end
    while dz ~= 0 and not M.intersects(world, bx0, by0 - 1, bz0 + dz, bx1, by0, bz1 + dz) do
      if math.abs(dz) < step then dz = 0
      elseif dz > 0 then dz = dz - step else dz = dz + step end
    end
    while dx ~= 0 and dz ~= 0
      and not M.intersects(world, bx0 + dx, by0 - 1, bz0 + dz, bx1 + dx, by0, bz1 + dz) do
      if math.abs(dx) < step then dx = 0 elseif dx > 0 then dx = dx - step else dx = dx + step end
      if math.abs(dz) < step then dz = 0 elseif dz > 0 then dz = dz - step else dz = dz + step end
    end
  end

  local wantX, wantY, wantZ = dx, dy, dz
  local margin = (e.stepHeight or 0) + 1
  collect(world, math.min(bx0, bx0 + dx), math.min(by0, by0 + dy), math.min(bz0, bz0 + dz),
    math.max(bx1, bx1 + dx), math.max(by1, by1 + dy) + margin, math.max(bz1, bz1 + dz))

  local mx, my, mz = moveBox(bx0, by0, bz0, bx1, by1, bz1, dx, dy, dz)

  -- wchodzenie na stopień: gdy uderzyliśmy bokiem będąc na ziemi
  local step = e.stepHeight or 0
  if step > 0 and (e.onGround or (wantY < 0 and my ~= wantY)) and (mx ~= wantX or mz ~= wantZ) then
    local sx, sy, sz = moveBox(bx0, by0, bz0, bx1, by1, bz1, wantX, step, wantZ)
    -- opuść z powrotem na podłoże
    local ny0 = by0 + sy
    local down = clip(2, -step, bx0 + sx, ny0, bz0 + sz, bx1 + sx, by1 + sy, bz1 + sz)
    sy = sy + down
    if sx * sx + sz * sz > mx * mx + mz * mz then
      mx, my, mz = sx, sy, sz
    end
  end

  e.x = e.x + mx
  e.y = e.y + my
  e.z = e.z + mz
  e.collidedH = (mx ~= wantX) or (mz ~= wantZ)
  e.collidedV = my ~= wantY
  e.onGround = wantY < 0 and my ~= wantY
  return mx, my, mz, wantX, wantY, wantZ
end

-- Sprawdza, czy AABB bytu dotyka danego rodzaju cieczy ("water"/"lava")
function M.inLiquid(world, e, kind, shrink)
  shrink = shrink or 0.001
  local hw = e.width / 2 - shrink
  local x0, y0, z0 = e.x - hw, e.y + 0.4, e.z - hw
  local x1, y1, z1 = e.x + hw, e.y + e.height - 0.4, e.z + hw
  for x = floor(x0), floor(x1) do
    for z = floor(z0), floor(z1) do
      for y = floor(y0), floor(y1) do
        local def = defs[world:getBlock(x, y, z)]
        if def and def.liquid == kind then return true end
      end
    end
  end
  return false
end

-- Czy punkt (np. oczy) jest w cieczy danego rodzaju
function M.pointInLiquid(world, x, y, z, kind)
  local bx, by, bz = floor(x), floor(y), floor(z)
  local id, meta = world:getBlockAndMeta(bx, by, bz)
  local def = defs[id]
  if not def or def.liquid ~= kind then return false end
  local h
  if meta == 0 or meta >= 8 then h = 14 / 16 else h = (8 - meta) / 9 end
  local aboveDef = defs[world:getBlock(bx, by + 1, bz)]
  if aboveDef and aboveDef.liquid == kind then h = 1 end
  return y - by < h
end

-- Czy byt stoi przy drabinie
function M.onClimbable(world, e)
  local def = defs[world:getBlock(floor(e.x), floor(e.y), floor(e.z))]
  return def and def.climbable or false
end

-- Lista bloków, których dotyka AABB bytu (do kaktusów, ognia, płyt naciskowych)
function M.touchingBlocks(world, e, fn)
  local hw = e.width / 2
  for x = floor(e.x - hw - 0.001), floor(e.x + hw + 0.001) do
    for z = floor(e.z - hw - 0.001), floor(e.z + hw + 0.001) do
      for y = floor(e.y - 0.001), floor(e.y + e.height) do
        local id = world:getBlock(x, y, z)
        if id ~= 0 then fn(id, x, y, z) end
      end
    end
  end
end

return M
