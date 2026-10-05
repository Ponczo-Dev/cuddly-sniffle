-- core/structures.lua
-- Struktury z Beta 1.8 / 1.0, sięgające przez wiele chunków:
--  * twierdze (3 na świat, 400-700 bloków od środka): korytarze z kamiennych
--    cegieł, biblioteka, fontanna, cele z kratami, skrzynie i sala
--    z portalem do Endu nad jeziorkiem lawy,
--  * opuszczone kopalnie: korytarze z drewnianymi podporami, tory,
--    pajęczyny, skrzynie ze skarbami, centralna komora,
--  * wioski (puste, jak w Beta 1.8): studnia, drogi ze żwiru, domy,
--    kuźnia z lawą i skrzynią, pole pszenicy, biblioteka, wieża.
-- Plan struktury liczony jest deterministycznie z seeda (od chunka
-- startowego), a każdy chunk rysuje tylko swoją część.

local Rng = require("core.rng")

local M = {}

local floor, max, min, abs = math.floor, math.max, math.min, math.abs

local AIR, STONE, DIRT, COBBLE, PLANKS = 0, 1, 3, 4, 5
local WATER, LAVA, GRAVEL, LOG, GLASS = 8, 10, 13, 17, 20
local COBWEB, FENCE, RAIL, CHEST, TORCH = 30, 85, 66, 54, 50
local FARMLAND, WHEAT, FURNACE, BOOKSHELF, DOOR = 60, 59, 61, 47, 64
local SLAB, GRASS, SAND, SANDSTONE, WOOL = 44, 2, 12, 24, 35
local CRAFTING = 58
local GLOWSTONE_BLOCK = 89

-- ---------------------------------------------------------------------------
-- Rysowanie z przycinaniem do chunka
-- ---------------------------------------------------------------------------
local Canvas = {}
Canvas.__index = Canvas

local function newCanvas(chunk)
  return setmetatable({ chunk = chunk, x0 = chunk.cx * 16, z0 = chunk.cz * 16 }, Canvas)
end

function Canvas:inside(x, y, z)
  return x >= self.x0 and x < self.x0 + 16 and z >= self.z0 and z < self.z0 + 16 and y >= 1 and y < 127
end

function Canvas:get(x, y, z)
  if not self:inside(x, y, z) then return nil end
  return self.chunk:get(x - self.x0, y, z - self.z0)
end

function Canvas:set(x, y, z, id, meta)
  if not self:inside(x, y, z) then return end
  self.chunk:setRaw(x - self.x0, y, z - self.z0, id, meta or 0)
end

function Canvas:fill(x0, y0, z0, x1, y1, z1, id, meta)
  for x = max(x0, self.x0), min(x1, self.x0 + 15) do
    for z = max(z0, self.z0), min(z1, self.z0 + 15) do
      for y = max(1, y0), min(126, y1) do
        self.chunk:setRaw(x - self.x0, y, z - self.z0, id, meta or 0)
      end
    end
  end
end

function Canvas:chest(x, y, z, facing, loot, rng)
  if not self:inside(x, y, z) then return end
  self:set(x, y, z, CHEST, facing or 0)
  local slots = {}
  for _ = 1, rng:int(3, 7) do
    local l = loot[rng:int(1, #loot)]
    slots[rng:int(1, 27)] = { id = l[1], count = rng:int(l[2], l[3]), damage = l[4] or 0 }
  end
  local lx, lz = x - self.x0, z - self.z0
  self.chunk.tiles[lx + lz * 16 + y * 256] = { kind = "chest", pendingSlots = slots }
end

local function overlaps(canvas, box)
  return box[1] <= canvas.x0 + 15 and box[4] >= canvas.x0 and box[3] <= canvas.z0 + 15 and box[6] >= canvas.z0
end

-- ---------------------------------------------------------------------------
-- Opuszczone kopalnie
-- ---------------------------------------------------------------------------
local MINE_LOOT = {
  { 297, 1, 3 }, { 265, 1, 5 }, { 266, 1, 3 }, { 331, 4, 9 }, { 351, 4, 9, 4 }, { 264, 1, 2 },
  { 263, 3, 8 }, { 66, 4, 8 }, { 50, 4, 12 }, { 260, 1, 2 },
}

local function mineshaftPlan(seed, sx, sz)
  local rng = Rng.new(Rng.hash(seed, sx, sz, 4242))
  local cx, cz = sx * 16 + 8, sz * 16 + 8
  local cy = rng:int(25, 45)
  local pieces = {}
  -- komora centralna
  local rw, rl = rng:int(4, 7), rng:int(4, 7)
  pieces[#pieces + 1] = { kind = "room", box = { cx - rw, cy, cz - rl, cx + rw, cy + 4, cz + rl } }
  local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
  -- korytarze: drzewo losowych odgałęzień
  local queue = {}
  for _, d in ipairs(DIRS) do
    local ox = d[1] ~= 0 and (cx + d[1] * (rw + 1)) or (cx + rng:int(-rw + 1, rw - 1))
    local oz = d[2] ~= 0 and (cz + d[2] * (rl + 1)) or (cz + rng:int(-rl + 1, rl - 1))
    queue[#queue + 1] = { ox, cy, oz, d, 0 }
  end
  local count = 0
  while #queue > 0 and count < 40 do
    local q = table.remove(queue, 1)
    local x, y, z, d, depth = q[1], q[2], q[3], q[4], q[5]
    local len = rng:int(2, 5) * 5
    local x1, z1 = x + d[1] * (len - 1), z + d[2] * (len - 1)
    local box
    if d[1] ~= 0 then
      box = { min(x, x1), y, z - 1, max(x, x1), y + 2, z + 1 }
    else
      box = { x - 1, y, min(z, z1), x + 1, y + 2, max(z, z1) }
    end
    -- nie oddalamy się za bardzo od startu
    if abs(x1 - cx) < 100 and abs(z1 - cz) < 100 then
      pieces[#pieces + 1] = { kind = "corridor", box = box, dir = d, len = len,
        rails = rng:chance(0.45), webs = rng:chance(0.3), chest = rng:chance(0.25),
        seed = rng:int(1, 1000000) }
      count = count + 1
      if depth < 5 then
        local nx, nz = x1 + d[1], z1 + d[2]
        local r = rng:next()
        local ny = y
        if rng:chance(0.2) then ny = y + rng:int(-4, 4) end
        if r < 0.5 then
          queue[#queue + 1] = { nx, ny, nz, d, depth + 1 }
        end
        -- skrzyżowanie: odgałęzienia w bok
        if r > 0.3 then
          pieces[#pieces + 1] = { kind = "crossing", box = { nx - 1, y, nz - 1, nx + 1, y + 2, nz + 1 } }
          local left = { -d[2], d[1] }
          local right = { d[2], -d[1] }
          if rng:chance(0.7) then queue[#queue + 1] = { nx + left[1] * 2, y, nz + left[2] * 2, left, depth + 1 } end
          if rng:chance(0.7) then queue[#queue + 1] = { nx + right[1] * 2, y, nz + right[2] * 2, right, depth + 1 } end
          if rng:chance(0.5) then queue[#queue + 1] = { nx + d[1] * 2, y, nz + d[2] * 2, d, depth + 1 } end
        end
      end
    end
  end
  return pieces
end

local function drawMineshaft(canvas, pieces)
  for _, pc in ipairs(pieces) do
    local b = pc.box
    if overlaps(canvas, b) then
      if pc.kind == "room" then
        canvas:fill(b[1], b[2] + 1, b[3], b[4], b[5], b[6], AIR)
        canvas:fill(b[1], b[2], b[3], b[4], b[2], b[6], DIRT)
      elseif pc.kind == "crossing" then
        canvas:fill(b[1], b[2], b[3], b[4], b[5], b[6], AIR)
        for x = b[1], b[4] do
          for z = b[3], b[6] do
            local below = canvas:get(x, b[2] - 1, z)
            if below == AIR or below == WATER or below == LAVA then canvas:set(x, b[2] - 1, z, PLANKS) end
          end
        end
      else
        local rng = Rng.new(pc.seed)
        canvas:fill(b[1], b[2], b[3], b[4], b[5], b[6], AIR)
        local d = pc.dir
        local horizontalX = d[1] ~= 0
        local x0 = horizontalX and min(b[1], b[4]) or b[1] + 1
        local z0 = horizontalX and b[3] + 1 or min(b[3], b[6])
        for i = 0, pc.len - 1 do
          local x = horizontalX and (b[1] + i) or (b[1] + 1)
          local z = horizontalX and (b[3] + 1) or (b[3] + i)
          -- mostek nad dziurą
          local below = canvas:get(x, b[2] - 1, z)
          if below == AIR or below == WATER or below == LAVA then canvas:set(x, b[2] - 1, z, PLANKS) end
          -- podpory co 5 bloków
          if i % 5 == 2 then
            if horizontalX then
              canvas:set(x, b[2], z - 1, FENCE, 4 + 8)
              canvas:set(x, b[2] + 1, z - 1, FENCE, 4 + 8)
              canvas:set(x, b[2], z + 1, FENCE, 4 + 8)
              canvas:set(x, b[2] + 1, z + 1, FENCE, 4 + 8)
              for k = -1, 1 do canvas:set(x, b[2] + 2, z + k, PLANKS) end
            else
              canvas:set(x - 1, b[2], z, FENCE, 1 + 2)
              canvas:set(x - 1, b[2] + 1, z, FENCE, 1 + 2)
              canvas:set(x + 1, b[2], z, FENCE, 1 + 2)
              canvas:set(x + 1, b[2] + 1, z, FENCE, 1 + 2)
              for k = -1, 1 do canvas:set(x + k, b[2] + 2, z, PLANKS) end
            end
          end
          if pc.rails and rng:chance(0.9) then canvas:set(x, b[2], z, RAIL, horizontalX and 1 or 0) end
          if pc.webs and rng:chance(0.15) then
            local wx = horizontalX and x or x + rng:int(-1, 1)
            local wz = horizontalX and z + rng:int(-1, 1) or z
            if canvas:get(wx, b[2] + 2, wz) == AIR then canvas:set(wx, b[2] + 2, wz, COBWEB) end
          end
        end
        if pc.chest then
          local i = rng:int(1, pc.len - 2)
          local x = horizontalX and (b[1] + i) or (b[1] + 2)
          local z = horizontalX and (b[3] + 2) or (b[3] + i)
          if canvas:get(x, b[2], z) == AIR then canvas:chest(x, b[2], z, 0, MINE_LOOT, rng) end
        end
        local _ = x0 + z0
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Wioski (Beta 1.8: bez mieszkańców)
-- ---------------------------------------------------------------------------
local SMITH_LOOT = {
  { 264, 1, 3 }, { 265, 1, 5 }, { 266, 1, 3 }, { 297, 1, 3 }, { 260, 1, 3 }, { 257, 1, 1 },
  { 267, 1, 1 }, { 307, 1, 1 }, { 306, 1, 1 }, { 49, 3, 7 }, { 6, 3, 7 },
}

local function villagePlan(gen, seed, sx, sz)
  local rng = Rng.new(Rng.hash(seed, sx, sz, 777999))
  local cx, cz = sx * 16 + 8, sz * 16 + 8
  local biome = gen:biome(cx, cz)
  local desert = biome.name == "Pustynia"
  local function groundY(x, z) return floor(gen:terrain(x, z)) end
  local pieces = {}
  local cy = groundY(cx, cz)
  pieces[#pieces + 1] = { kind = "well", x = cx, y = cy, z = cz, box = { cx - 3, cy - 4, cz - 3, cx + 3, cy + 5, cz + 3 } }
  local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
  local kinds = { "house", "house", "house", "smith", "farm", "farm", "library", "tower", "hut", "hut" }
  for _, d in ipairs(DIRS) do
    local len = rng:int(14, 26)
    local road = { kind = "road", x = cx + d[1] * 3, z = cz + d[2] * 3, dir = d, len = len }
    local ex, ez = road.x + d[1] * len, road.z + d[2] * len
    road.box = { min(road.x, ex) - 1, 0, min(road.z, ez) - 1, max(road.x, ex) + 1, 127, max(road.z, ez) + 1 }
    pieces[#pieces + 1] = road
    -- budynki po obu stronach drogi
    local pos = 3
    while pos < len - 4 do
      for _, side in ipairs({ -1, 1 }) do
        if rng:chance(0.7) then
          local kind = kinds[rng:int(1, #kinds)]
          local w, l = 5, 5
          if kind == "smith" then w, l = 7, 6 elseif kind == "farm" then w, l = 7, 9
          elseif kind == "library" then w, l = 7, 6 elseif kind == "tower" then w, l = 5, 5
          elseif kind == "hut" then w, l = 4, 4 end
          -- przesunięcie w bok od drogi
          local px = road.x + d[1] * pos
          local pz = road.z + d[2] * pos
          local nx, nz = -d[2] * side, d[1] * side
          local bx0 = px + nx * 2
          local bz0 = pz + nz * 2
          local x0 = nx < 0 and bx0 - w + 1 or (nx > 0 and bx0 or px)
          local z0 = nz < 0 and bz0 - l + 1 or (nz > 0 and bz0 or pz)
          if nx == 0 then x0 = px end
          if nz == 0 then z0 = pz end
          local by = groundY(x0 + floor(w / 2), z0 + floor(l / 2))
          if by >= 63 then
            pieces[#pieces + 1] = { kind = kind, x0 = x0, z0 = z0, w = w, l = l, y = by,
              doorSide = { -nx, -nz }, desert = desert, seed = rng:int(1, 1000000),
              box = { x0 - 1, by - 4, z0 - 1, x0 + w, by + 12, z0 + l } }
          end
        end
      end
      pos = pos + rng:int(8, 11)
    end
  end
  return pieces, desert, groundY
end

-- Prostokątne pudełko budynku (ściany, podłoga, dach), drzwi od strony drogi
local function building(canvas, pc, wallId, floorId, roofId, height)
  local x0, z0, x1, z1, y = pc.x0, pc.z0, pc.x0 + pc.w - 1, pc.z0 + pc.l - 1, pc.y
  -- fundament do ziemi i wyczyszczenie wnętrza
  canvas:fill(x0, y - 3, z0, x1, y, z1, COBBLE)
  canvas:fill(x0, y + 1, z0, x1, y + height + 2, z1, AIR)
  canvas:fill(x0, y, z0, x1, y, z1, floorId)
  for yy = y + 1, y + height do
    for x = x0, x1 do
      canvas:set(x, yy, z0, wallId); canvas:set(x, yy, z1, wallId)
    end
    for z = z0, z1 do
      canvas:set(x0, yy, z, wallId); canvas:set(x1, yy, z, wallId)
    end
  end
  -- narożniki z pni
  for yy = y + 1, y + height do
    if not pc.desert then
      canvas:set(x0, yy, z0, LOG); canvas:set(x1, yy, z0, LOG)
      canvas:set(x0, yy, z1, LOG); canvas:set(x1, yy, z1, LOG)
    end
  end
  canvas:fill(x0, y + height + 1, z0, x1, y + height + 1, z1, roofId)
  -- okna
  local mz = floor((z0 + z1) / 2)
  local mx = floor((x0 + x1) / 2)
  canvas:set(x0, y + 2, mz, GLASS); canvas:set(x1, y + 2, mz, GLASS)
  canvas:set(mx, y + 2, z0, GLASS); canvas:set(mx, y + 2, z1, GLASS)
  -- drzwi od strony drogi
  local ds = pc.doorSide
  local dx, dz
  if ds[1] > 0 then dx, dz = x1, mz elseif ds[1] < 0 then dx, dz = x0, mz
  elseif ds[2] > 0 then dx, dz = mx, z1 else dx, dz = mx, z0 end
  local facing = 0
  if ds[1] > 0 then facing = 1 elseif ds[1] < 0 then facing = 3 elseif ds[2] > 0 then facing = 2 end
  canvas:set(dx, y + 1, dz, DOOR, facing)
  canvas:set(dx, y + 2, dz, DOOR, facing + 8)
  -- pochodnia w środku
  canvas:set(mx, y + 1, mz, TORCH, 0)
  return x0, z0, x1, z1, y
end

local function drawVillage(canvas, pieces)
  for _, pc in ipairs(pieces) do
    if overlaps(canvas, pc.box) then
      local rng = Rng.new(pc.seed or 1)
      local wall = pc.desert and SANDSTONE or COBBLE
      if pc.kind == "well" then
        local x, y, z = pc.x, pc.y, pc.z
        canvas:fill(x - 2, y - 3, z - 2, x + 2, y, z + 2, COBBLE)
        canvas:fill(x - 1, y - 3, z - 1, x + 1, y, z + 1, WATER)
        canvas:fill(x - 2, y + 1, z - 2, x + 2, y + 4, z + 2, AIR)
        canvas:fill(x - 2, y + 1, z - 2, x + 2, y + 1, z + 2, COBBLE)
        canvas:fill(x - 1, y + 1, z - 1, x + 1, y + 1, z + 1, AIR)
        for _, c in ipairs({ { -2, -2 }, { 2, -2 }, { -2, 2 }, { 2, 2 } }) do
          canvas:set(x + c[1], y + 2, z + c[2], FENCE, 0)
          canvas:set(x + c[1], y + 3, z + c[2], FENCE, 0)
        end
        canvas:fill(x - 2, y + 4, z - 2, x + 2, y + 4, z + 2, COBBLE)
      elseif pc.kind == "road" then
        local d = pc.dir
        for i = 0, pc.len do
          for w = -1, 1 do
            local x = pc.x + d[1] * i + (-d[2]) * w
            local z = pc.z + d[2] * i + d[1] * w
            if canvas:inside(x, 64, z) then
              -- powierzchnia w tej kolumnie (z bieżącego chunka)
              for y = 120, 50, -1 do
                local id = canvas:get(x, y, z)
                if id and id ~= AIR and id ~= 18 and id ~= 17 and id ~= 31 and id ~= 78 and id ~= 37
                  and id ~= 38 then
                  if id ~= WATER then canvas:set(x, y, z, pc.desert and SANDSTONE or GRAVEL) end
                  if canvas:get(x, y + 1, z) ~= AIR and canvas:get(x, y + 1, z) ~= DOOR then
                    local above = canvas:get(x, y + 1, z)
                    if above == 31 or above == 37 or above == 38 or above == 78 then canvas:set(x, y + 1, z, AIR) end
                  end
                  break
                end
              end
            end
          end
        end
      elseif pc.kind == "house" then
        building(canvas, pc, wall, PLANKS, pc.desert and SANDSTONE or PLANKS, 3)
      elseif pc.kind == "hut" then
        building(canvas, pc, pc.desert and SANDSTONE or COBBLE, DIRT, pc.desert and SANDSTONE or LOG, 2)
      elseif pc.kind == "tower" then
        local x0, z0, x1, z1, y = building(canvas, pc, wall, COBBLE, COBBLE, 7)
        canvas:fill(x0 + 1, y + 4, z0 + 1, x1 - 1, y + 4, z1 - 1, PLANKS)
        canvas:set(x0 + 1, y + 1, z0 + 1, 65, 3) -- drabina
      elseif pc.kind == "library" then
        local x0, z0, x1, z1, y = building(canvas, pc, wall, PLANKS, PLANKS, 4)
        for x = x0 + 1, x1 - 1 do
          canvas:set(x, y + 1, z1 - 1, BOOKSHELF)
          canvas:set(x, y + 2, z1 - 1, BOOKSHELF)
        end
        canvas:set(x0 + 1, y + 1, z0 + 1, CRAFTING)
      elseif pc.kind == "smith" then
        local x0, z0, x1, z1, y = building(canvas, pc, wall, COBBLE, SLAB, 3)
        canvas:set(x0 + 1, y, z0 + 1, LAVA); canvas:set(x0 + 2, y, z0 + 1, LAVA)
        canvas:set(x0 + 3, y + 1, z0 + 1, FURNACE, 0)
        canvas:chest(x1 - 1, y + 1, z1 - 1, 1, SMITH_LOOT, rng)
      elseif pc.kind == "farm" then
        local x0, z0, x1, z1, y = pc.x0, pc.z0, pc.x0 + pc.w - 1, pc.z0 + pc.l - 1, pc.y
        canvas:fill(x0, y - 2, z0, x1, y - 1, z1, DIRT)
        canvas:fill(x0, y + 1, z0, x1, y + 3, z1, AIR)
        for x = x0, x1 do
          for z = z0, z1 do
            local border = x == x0 or x == x1 or z == z0 or z == z1
            if border then
              canvas:set(x, y, z, LOG)
            elseif x == floor((x0 + x1) / 2) then
              canvas:set(x, y, z, WATER)
            else
              canvas:set(x, y, z, FARMLAND, 7)
              canvas:set(x, y + 1, z, WHEAT, rng:int(2, 7))
            end
          end
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Twierdza
-- ---------------------------------------------------------------------------
local BRICK, BRICK_MOSSY, BRICK_CRACKED, IRON_BARS = 98, 97, 99, 101
local FRAME, SPAWNER = 120, 52

local SH_LOOT = {
  { 368, 1, 1 }, { 265, 1, 5 }, { 266, 1, 3 }, { 331, 4, 9 }, { 297, 1, 3 }, { 260, 1, 3 },
  { 257, 1, 1 }, { 267, 1, 1 }, { 307, 1, 1 }, { 306, 1, 1 }, { 309, 1, 1 }, { 322, 1, 1 },
}
local LIBRARY_LOOT = { { 339, 1, 3 }, { 340, 1, 3 }, { 345, 1, 1 }, { 395, 1, 1 }, { 340, 2, 5 } }

M.STRONGHOLD_COUNT = 3
M.STRONGHOLD_MIN, M.STRONGHOLD_MAX = 25, 44 -- odległość w chunkach

-- Pozycje (chunk) trzech twierdz w pierścieniu wokół środka świata
function M.strongholdPositions(seed)
  local rng = Rng.new(Rng.hash(seed, 7, 7, 1907))
  local a0 = rng:next() * math.pi * 2
  local list = {}
  for i = 0, M.STRONGHOLD_COUNT - 1 do
    local a = a0 + i * math.pi * 2 / M.STRONGHOLD_COUNT
    local d = rng:int(M.STRONGHOLD_MIN, M.STRONGHOLD_MAX)
    list[#list + 1] = { floor(math.cos(a) * d + 0.5), floor(math.sin(a) * d + 0.5) }
  end
  return list
end

-- Prostopadłościan pomieszczenia o długości L (wzdłuż d) i szerokości W, drzwi na środku ściany
local function roomBox(x, y, z, d, L, W, H)
  local hw = floor(W / 2)
  if d[1] > 0 then return { x, y, z - hw, x + L - 1, y + H - 1, z + hw } end
  if d[1] < 0 then return { x - L + 1, y, z - hw, x, y + H - 1, z + hw } end
  if d[2] > 0 then return { x - hw, y, z, x + hw, y + H - 1, z + L - 1 } end
  return { x - hw, y, z - L + 1, x + hw, y + H - 1, z }
end

local function boxesClash(a, b)
  -- kolizja wnętrz (ściany mogą być wspólne)
  return a[1] + 1 <= b[4] - 1 and a[4] - 1 >= b[1] + 1 and a[2] + 1 <= b[5] - 1 and a[5] - 1 >= b[2] + 1
    and a[3] + 1 <= b[6] - 1 and a[6] - 1 >= b[3] + 1
end

local ROOMS = {
  library = { L = 14, W = 13, H = 8 }, fountain = { L = 9, W = 9, H = 7 },
  prison = { L = 11, W = 9, H = 5 }, chestroom = { L = 7, W = 7, H = 5 },
  crossing = { L = 7, W = 7, H = 6 }, portal = { L = 16, W = 11, H = 8 },
}

local function strongholdPlan(seed, sx, sz)
  local rng = Rng.new(Rng.hash(seed, sx, sz, 5150))
  local cx, cz = sx * 16 + 8, sz * 16 + 8
  local y = rng:int(16, 26)
  local pieces = {}
  local function free(box)
    for _, p in ipairs(pieces) do if boxesClash(box, p.box) then return false end end
    return true
  end
  local function add(kind, box, d, extra)
    local p = { kind = kind, box = box, dir = d, seed = rng:int(1, 1000000) }
    for k, v in pairs(extra or {}) do p[k] = v end
    pieces[#pieces + 1] = p
    return p
  end
  add("start", { cx - 4, y, cz - 4, cx + 4, y + 6, cz + 4 })
  local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
  local function exitOf(box, d)
    -- środek ściany w kierunku d
    local mx, mz = floor((box[1] + box[4]) / 2), floor((box[3] + box[6]) / 2)
    if d[1] > 0 then return box[4], mz end
    if d[1] < 0 then return box[1], mz end
    if d[2] > 0 then return mx, box[6] end
    return mx, box[3]
  end
  -- sala z portalem: zawsze, w losowym kierunku od startu
  local pd = DIRS[rng:int(1, 4)]
  local ex, ez = exitOf(pieces[1].box, pd)
  local clen = rng:int(10, 16)
  local cbox = roomBox(ex, y, ez, pd, clen, 5, 5)
  add("corridor", cbox, pd)
  local px, pz = ex + pd[1] * (clen - 1), ez + pd[2] * (clen - 1)
  local R = ROOMS.portal
  local portal = add("portal", roomBox(px, y, pz, pd, R.L, R.W, R.H), pd)
  -- pozostałe gałęzie
  local queue = {}
  for _, d in ipairs(DIRS) do
    if d ~= pd then
      local qx, qz = exitOf(pieces[1].box, d)
      queue[#queue + 1] = { qx, qz, d, 0 }
    end
  end
  local kinds = { "library", "fountain", "prison", "chestroom", "crossing", "crossing" }
  local count = 0
  while #queue > 0 and count < 24 do
    local q = table.remove(queue, 1)
    local x, z, d, depth = q[1], q[2], q[3], q[4]
    local len = rng:int(6, 14)
    local box = roomBox(x, y, z, d, len, 5, 5)
    if free(box) then
      add("corridor", box, d, { webs = rng:chance(0.3) })
      count = count + 1
      local rx, rz = x + d[1] * (len - 1), z + d[2] * (len - 1)
      local kind = kinds[rng:int(1, #kinds)]
      local r = ROOMS[kind]
      local rb = roomBox(rx, y, rz, d, r.L, r.W, r.H)
      if free(rb) then
        local room = add(kind, rb, d)
        count = count + 1
        if depth < 3 then
          local left, right = { -d[2], d[1] }, { d[2], -d[1] }
          for _, nd in ipairs({ d, left, right }) do
            if rng:chance(kind == "crossing" and 0.85 or 0.45) then
              local nx, nz = exitOf(room.box, nd)
              queue[#queue + 1] = { nx, nz, nd, depth + 1 }
            end
          end
        end
      end
    end
  end
  -- środek pierścienia ramek (cel oka Endu)
  local function local2world(p, u, v)
    local b, d = p.box, p.dir
    if d[1] > 0 then return b[1] + v, b[3] + u end
    if d[1] < 0 then return b[4] - v, b[6] - u end
    if d[2] > 0 then return b[4] - u, b[3] + v end
    return b[1] + u, b[6] - v
  end
  local fx, fz = local2world(portal, 5, 11)
  return pieces, { fx, y + 3, fz }
end
M.strongholdPlan = strongholdPlan

-- Czy komórka leży we wnętrzu któregoś elementu (np. wycięte drzwi)
local function carvedBy(pieces, x, y, z)
  for _, p in ipairs(pieces) do
    local b = p.box
    if p.kind == "corridor" then
      local d = p.dir
      local ax0, ax1, az0, az1 = b[1] + 1, b[4] - 1, b[3] + 1, b[6] - 1
      if d[1] ~= 0 then ax0, ax1 = b[1], b[4] else az0, az1 = b[3], b[6] end
      if x >= ax0 and x <= ax1 and z >= az0 and z <= az1 and y > b[2] and y < b[5] then return true end
    elseif x > b[1] and x < b[4] and z > b[3] and z < b[6] and y > b[2] and y < b[5] then
      return true
    end
  end
  return false
end

local function brickAt(x, y, z, seed)
  local h = Rng.hash(seed, x, y, z) % 100
  if h < 14 then return BRICK_MOSSY end
  if h < 24 then return BRICK_CRACKED end
  return BRICK
end

-- Pochodnia przy ścianie: meta zależnie od strony podpory
local function torchMeta(dx, dz)
  if dx < 0 then return 1 elseif dx > 0 then return 2 elseif dz < 0 then return 3 end
  return 4
end

local function drawStronghold(canvas, pieces, seed)
  local any = false
  for _, p in ipairs(pieces) do
    if overlaps(canvas, p.box) then any = true break end
  end
  if not any then return end
  -- 1) ściany
  for _, p in ipairs(pieces) do
    local b = p.box
    if overlaps(canvas, b) then
      for x = max(b[1], canvas.x0), min(b[4], canvas.x0 + 15) do
        for z = max(b[3], canvas.z0), min(b[6], canvas.z0 + 15) do
          for y = b[2], b[5] do canvas:set(x, y, z, brickAt(x, y, z, seed)) end
        end
      end
    end
  end
  -- 2) wnętrza (korytarze przebijają ściany sal = drzwi)
  for _, p in ipairs(pieces) do
    local b = p.box
    if overlaps(canvas, b) then
      for x = max(b[1], canvas.x0), min(b[4], canvas.x0 + 15) do
        for z = max(b[3], canvas.z0), min(b[6], canvas.z0 + 15) do
          for y = b[2] + 1, b[5] - 1 do
            if carvedBy({ p }, x, y, z) then canvas:set(x, y, z, AIR) end
          end
        end
      end
    end
  end
  -- 3) wyposażenie
  for _, p in ipairs(pieces) do
    local b = p.box
    if overlaps(canvas, b) then
      local rng = Rng.new(p.seed)
      local d = p.dir or { 1, 0 }
      local function L2W(u, v)
        if d[1] > 0 then return b[1] + v, b[3] + u end
        if d[1] < 0 then return b[4] - v, b[6] - u end
        if d[2] > 0 then return b[4] - u, b[3] + v end
        return b[1] + u, b[6] - v
      end
      local W = (d[1] ~= 0) and (b[6] - b[3] + 1) or (b[4] - b[1] + 1)
      local Ln = (d[1] ~= 0) and (b[4] - b[1] + 1) or (b[6] - b[3] + 1)
      local y0 = b[2]
      -- przy ścianie bocznej (u = 1 lub W-2), jeśli ściana nie jest przebita
      local function wallTorch(u, v, y)
        local x, z = L2W(u, v)
        local wu = u == 1 and 0 or W - 1
        local wx, wz = L2W(wu, v)
        if not carvedBy(pieces, wx, y, wz) then canvas:set(x, y, z, TORCH, torchMeta(wx - x, wz - z)) end
      end
      if p.kind == "corridor" then
        for v = 3, Ln - 2, 6 do
          if rng:chance(0.5) then wallTorch(rng:chance(0.5) and 1 or W - 2, v, y0 + 2) end
        end
        if p.webs then
          for _ = 1, 3 do
            local x, z = L2W(rng:int(1, W - 2), rng:int(1, Ln - 2))
            canvas:set(x, y0 + 3, z, COBWEB)
          end
        end
      elseif p.kind == "start" then
        canvas:fill(b[1] + 4, y0 + 1, b[3] + 4, b[1] + 4, y0 + 5, b[3] + 4, BRICK)
        for _, o in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
          canvas:set(b[1] + 4 + o[1], y0 + 3, b[3] + 4 + o[2], TORCH, torchMeta(-o[1], -o[2]))
        end
      elseif p.kind == "library" then
        for v = 1, Ln - 2 do
          for _, u in ipairs({ 1, W - 2 }) do
            local wx, wz = L2W(u == 1 and 0 or W - 1, v)
            for y = y0 + 1, y0 + 5 do
              if not carvedBy(pieces, wx, y, wz) or y > y0 + 3 then
                local x, z = L2W(u, v)
                canvas:set(x, y, z, BOOKSHELF)
              end
            end
          end
        end
        for u = 2, W - 3 do
          local wx, wz = L2W(u, Ln - 1)
          for y = y0 + 1, y0 + 5 do
            if not carvedBy(pieces, wx, y, wz) or y > y0 + 3 then
              local x, z = L2W(u, Ln - 2)
              canvas:set(x, y, z, BOOKSHELF)
            end
          end
        end
        -- regały w środku
        for _, u in ipairs({ 4, W - 5 }) do
          for v = 3, Ln - 5 do
            local x, z = L2W(u, v)
            canvas:fill(x, y0 + 1, z, x, y0 + 3, z, BOOKSHELF)
          end
        end
        for _ = 1, 8 do
          local x, z = L2W(rng:int(2, W - 3), rng:int(2, Ln - 3))
          canvas:set(x, y0 + rng:int(4, 6), z, COBWEB)
        end
        local cx, cz = L2W(floor(W / 2), Ln - 3)
        canvas:chest(cx, y0 + 1, cz, 0, LIBRARY_LOOT, rng)
        -- żyrandol z płotków
        local mx, mz = L2W(floor(W / 2), floor(Ln / 2))
        canvas:fill(mx, y0 + 5, mz, mx, y0 + 6, mz, FENCE)
        canvas:set(mx, y0 + 4, mz, GLOWSTONE_BLOCK)
      elseif p.kind == "fountain" then
        local mx, mz = L2W(floor(W / 2), floor(Ln / 2))
        canvas:fill(mx, y0 + 1, mz, mx, y0 + 3, mz, BRICK)
        canvas:set(mx, y0 + 4, mz, WATER)
        for _, o in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
          canvas:set(mx + o[1], y0 + 1, mz + o[2], WATER)
        end
        wallTorch(1, 2, y0 + 3)
        wallTorch(W - 2, Ln - 3, y0 + 3)
      elseif p.kind == "prison" then
        for v = 2, Ln - 3 do
          for _, u in ipairs({ 3, W - 4 }) do
            local x, z = L2W(u, v)
            canvas:fill(x, y0 + 1, z, x, y0 + 3, z, IRON_BARS)
          end
        end
        for _, v in ipairs({ 5, 8 }) do
          for _, us in ipairs({ { 1, 2 }, { W - 3, W - 2 } }) do
            for u = us[1], us[2] do
              local x, z = L2W(u, v)
              canvas:fill(x, y0 + 1, z, x, y0 + 3, z, BRICK)
            end
          end
        end
        wallTorch(1, 1, y0 + 2)
      elseif p.kind == "chestroom" then
        local x, z = L2W(floor(W / 2), Ln - 2)
        canvas:chest(x, y0 + 1, z, 0, SH_LOOT, rng)
        local sx, sz = L2W(floor(W / 2) - 1, Ln - 2)
        canvas:set(sx, y0 + 1, sz, SLAB)
        wallTorch(1, 2, y0 + 3)
      elseif p.kind == "crossing" then
        local mx, mz = L2W(floor(W / 2), floor(Ln / 2))
        canvas:fill(mx, y0 + 1, mz, mx, y0 + 4, mz, BRICK)
        canvas:set(mx + 1, y0 + 2, mz, TORCH, 1)
        canvas:set(mx - 1, y0 + 2, mz, TORCH, 2)
      elseif p.kind == "portal" then
        -- jezioro lawy pod portalem
        for u = 3, 7 do
          for v = 9, 13 do
            local x, z = L2W(u, v)
            canvas:set(x, y0, z, LAVA)
            canvas:set(x, y0 - 1, z, BRICK)
          end
        end
        -- schody do platformy
        for v = 5, 8 do
          local h = v == 5 and 0 or (v == 6 and 1 or 2)
          for u = 4, 6 do
            local x, z = L2W(u, v)
            if h > 0 then canvas:fill(x, y0 + 1, z, x, y0 + h, z, BRICK) end
          end
        end
        -- ramki na filarach dookoła 3x3
        local frames = {}
        for v = 10, 12 do frames[#frames + 1] = { 3, v, 1 }; frames[#frames + 1] = { 7, v, 3 } end
        for u = 4, 6 do frames[#frames + 1] = { u, 9, 0 }; frames[#frames + 1] = { u, 13, 2 } end
        for _, f in ipairs(frames) do
          local x, z = L2W(f[1], f[2])
          canvas:fill(x, y0 + 1, z, x, y0 + 2, z, BRICK)
          canvas:set(x, y0 + 3, z, FRAME, f[3] + (rng:chance(0.1) and 4 or 0))
        end
        -- narożniki ramy: cegły
        for _, c in ipairs({ { 3, 9 }, { 7, 9 }, { 3, 13 }, { 7, 13 } }) do
          local x, z = L2W(c[1], c[2])
          canvas:fill(x, y0 + 1, z, x, y0 + 2, z, BRICK)
        end
        -- spawner i pochodnie
        local sx, sz = L2W(9, 5)
        if canvas:inside(sx, y0 + 1, sz) then
          canvas:set(sx, y0 + 1, sz, SPAWNER)
          canvas.chunk.tiles[(sx - canvas.x0) + (sz - canvas.z0) * 16 + (y0 + 1) * 256] =
            { kind = "spawner", mob = "skeleton", delay = 200 }
        end
        for _, v in ipairs({ 3, 8, 13 }) do
          wallTorch(1, v, y0 + 4)
          wallTorch(W - 2, v, y0 + 4)
        end
        -- okna z kraty w ścianach bocznych
        for _, v in ipairs({ 5, 11 }) do
          for _, u in ipairs({ 0, W - 1 }) do
            local x, z = L2W(u, v)
            if not carvedBy(pieces, x, y0 + 3, z) then canvas:set(x, y0 + 3, z, IRON_BARS) end
          end
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Wywołanie z generatora świata
-- ---------------------------------------------------------------------------
local cache = setmetatable({}, { __mode = "v" })
local cacheKeys = {}

local function cached(key, fn)
  local v = cache[key]
  if not v then
    v = { fn() }
    cache[key] = v
    cacheKeys[#cacheKeys + 1] = v -- silna referencja na chwilę
    if #cacheKeys > 64 then table.remove(cacheKeys, 1) end
  end
  return v[1], v[2]
end

function M.mineshaftAt(seed, sx, sz)
  local rng = Rng.new(Rng.hash(seed, sx, sz, 31337))
  return rng:chance(0.006)
end

function M.villageAt(gen, seed, sx, sz)
  -- wioski w siatce 20x20 chunków, jedna losowa pozycja w każdej komórce
  local gx, gz = floor(sx / 20), floor(sz / 20)
  local rng = Rng.new(Rng.hash(seed, gx, gz, 9090))
  local vx, vz = gx * 20 + rng:int(2, 17), gz * 20 + rng:int(2, 17)
  if vx ~= sx or vz ~= sz then return false end
  if not rng:chance(0.7) then return false end
  local b, h = gen:biome(sx * 16 + 8, sz * 16 + 8)
  if h < 64 then return false end
  return b.name == "Rowniny" or b.name == "Pustynia"
end

-- Plan twierdzy (z pamięci podręcznej): pieces, środek portalu
function M.stronghold(seed, sx, sz)
  return cached("s" .. sx .. "," .. sz, function() return strongholdPlan(seed, sx, sz) end)
end

function M.applyUnderground(gen, chunk)
  local seed = gen.seed
  local canvas = newCanvas(chunk)
  local cx, cz = chunk.cx, chunk.cz
  -- twierdze (zasięg do ~6 chunków od środka)
  for _, pos in ipairs(M.strongholdPositions(seed)) do
    if abs(pos[1] - cx) <= 6 and abs(pos[2] - cz) <= 6 then
      local pieces = M.stronghold(seed, pos[1], pos[2])
      drawStronghold(canvas, pieces, seed)
    end
  end
  -- kopalnie (zasięg do ~7 chunków od startu)
  for sz = cz - 7, cz + 7 do
    for sx = cx - 7, cx + 7 do
      if M.mineshaftAt(seed, sx, sz) then
        local pieces = cached("m" .. sx .. "," .. sz, function() return mineshaftPlan(seed, sx, sz) end)
        drawMineshaft(canvas, pieces)
      end
    end
  end
end

function M.applySurface(gen, chunk)
  local seed = gen.seed
  local canvas = newCanvas(chunk)
  local cx, cz = chunk.cx, chunk.cz
  -- wioski (zasięg do ~3 chunków)
  for sz = cz - 3, cz + 3 do
    for sx = cx - 3, cx + 3 do
      if M.villageAt(gen, seed, sx, sz) then
        local pieces = cached("v" .. sx .. "," .. sz, function() return villagePlan(gen, seed, sx, sz) end)
        drawVillage(canvas, pieces)
      end
    end
  end
end

-- Najbliższa wioska (do komendy /locate)
function M.findVillage(gen, fromCx, fromCz, radius)
  local best, bestD
  for sz = fromCz - radius, fromCz + radius do
    for sx = fromCx - radius, fromCx + radius do
      if M.villageAt(gen, gen.seed, sx, sz) then
        local d = (sx - fromCx) ^ 2 + (sz - fromCz) ^ 2
        if not best or d < bestD then best, bestD = { sx * 16 + 8, sz * 16 + 8 }, d end
      end
    end
  end
  return best
end

-- Najbliższa twierdza: współrzędne środka sali z portalem
function M.findStronghold(seed, x, z)
  local best, bestD
  for _, pos in ipairs(M.strongholdPositions(seed)) do
    local _, portal = M.stronghold(seed, pos[1], pos[2])
    local d = (portal[1] - x) ^ 2 + (portal[3] - z) ^ 2
    if not best or d < bestD then best, bestD = portal, d end
  end
  return best
end

function M.findMineshaft(gen, fromCx, fromCz, radius)
  local best, bestD
  for sz = fromCz - radius, fromCz + radius do
    for sx = fromCx - radius, fromCx + radius do
      if M.mineshaftAt(gen.seed, sx, sz) then
        local d = (sx - fromCx) ^ 2 + (sz - fromCz) ^ 2
        if not best or d < bestD then best, bestD = { sx * 16 + 8, sz * 16 + 8 }, d end
      end
    end
  end
  return best
end

local _ = { GRASS, SAND, WOOL, STONE }
return M
