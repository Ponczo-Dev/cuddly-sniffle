-- core/worldgen.lua
-- Generator świata w stylu Minecraft Beta 1.8:
--  * teren z szumu (kontynenty, wzgórza, góry), oceany i plaże,
--  * biomy z temperatury i wilgotności (równiny, las, pustynia, tajga,
--    bagno, góry, ocean, tundra),
--  * jaskinie (szum 3D "spaghetti" + komory), wąwozy, jeziora lawy na dnie,
--  * rudy na właściwych wysokościach, drzewa, trawa, kwiaty, kaktusy,
--    trzcina, dynie, glina.
-- Ten sam seed = ten sam świat.

local Noise = require("core.noise")
local Rng = require("core.rng")
local trees = require("core.trees")

local M = {}

local floor, max, min, abs, sqrt = math.floor, math.max, math.min, math.abs, math.sqrt

local SEA = 64              -- woda wypełnia y <= 63
local HEIGHT = 128

local AIR, STONE, GRASS, DIRT, COBBLE = 0, 1, 2, 3, 4
local BEDROCK, WATER, LAVA, SAND, GRAVEL = 7, 8, 10, 12, 13
local GOLD_ORE, IRON_ORE, COAL_ORE, LAPIS_ORE = 14, 15, 16, 21
local DIAMOND_ORE, REDSTONE_ORE = 56, 73
local SANDSTONE, TALL_GRASS, DEAD_BUSH = 24, 31, 32
local DANDELION, ROSE, BROWN_MUSH, RED_MUSH = 37, 38, 39, 40
local SNOW_LAYER, ICE, CACTUS, CLAY, SUGAR_CANE, PUMPKIN = 78, 79, 81, 82, 83, 86
local MOSSY, SPAWNER, CHEST = 48, 52, 54

-- Biomy: dane o powierzchni i roślinności
M.BIOMES = {
  plains = { name = "Rowniny", top = GRASS, filler = DIRT, trees = 0.15, grass = 24,
    flowers = 3, fog = { 0.6, 0.75, 1.0 } },
  forest = { name = "Las", top = GRASS, filler = DIRT, trees = 7, grass = 6, flowers = 2,
    birch = 0.2, fog = { 0.55, 0.72, 1.0 } },
  desert = { name = "Pustynia", top = SAND, filler = SAND, trees = 0, cactus = 3, deadBush = 2,
    dry = true, fog = { 0.75, 0.8, 0.9 } },
  taiga = { name = "Tajga", top = GRASS, filler = DIRT, trees = 5, pine = true, grass = 2,
    snowy = true, fog = { 0.7, 0.78, 0.95 } },
  tundra = { name = "Tundra", top = GRASS, filler = DIRT, trees = 0.3, pine = true, grass = 1,
    snowy = true, fog = { 0.75, 0.8, 0.95 } },
  swamp = { name = "Bagno", top = GRASS, filler = DIRT, trees = 2, grass = 5, mushrooms = 1,
    fog = { 0.45, 0.55, 0.6 }, waterTint = true },
  mountains = { name = "Gory", top = GRASS, filler = DIRT, trees = 1, grass = 4,
    fog = { 0.6, 0.7, 0.95 } },
  ocean = { name = "Ocean", top = SAND, filler = SAND, trees = 0, fog = { 0.5, 0.65, 1.0 } },
  beach = { name = "Plaza", top = SAND, filler = SAND, trees = 0, fog = { 0.6, 0.75, 1.0 } },
}
local BIOMES = M.BIOMES

-- ---------------------------------------------------------------------------
-- Generator (obiekt z szumami dla danego seeda)
-- ---------------------------------------------------------------------------
local Gen = {}
Gen.__index = Gen

function M.new(seed)
  local self = setmetatable({}, Gen)
  self.seed = seed
  self.nContinent = Noise.new(Rng.hash(seed, 1))
  self.nHills = Noise.new(Rng.hash(seed, 2))
  self.nDetail = Noise.new(Rng.hash(seed, 3))
  self.nMountain = Noise.new(Rng.hash(seed, 4))
  self.nTemp = Noise.new(Rng.hash(seed, 5))
  self.nHumid = Noise.new(Rng.hash(seed, 6))
  self.nCave1 = Noise.new(Rng.hash(seed, 7))
  self.nCave2 = Noise.new(Rng.hash(seed, 8))
  self.nCavern = Noise.new(Rng.hash(seed, 9))
  self.nSurface = Noise.new(Rng.hash(seed, 10))
  self.cache = {}
  return self
end

-- Klimat w punkcie: temperatura i wilgotność 0..1
function Gen:climate(x, z)
  local t = self.nTemp:fbm2(x / 520, z / 520, 3) * 0.5 + 0.5
  local h = self.nHumid:fbm2(x / 380 + 50, z / 380, 3) * 0.5 + 0.5
  -- rozciągnięcie do pełnego zakresu
  t = min(1, max(0, (t - 0.5) * 1.6 + 0.5))
  h = min(1, max(0, (h - 0.5) * 1.6 + 0.5))
  return t, h
end

-- Wielkoskalowe pola terenu (wolno zmienne - można je interpolować)
function Gen:largeScale(x, z)
  local cont = self.nContinent:fbm2(x / 700, z / 700, 4)
  local hills = self.nHills:fbm2(x / 140, z / 140, 4)
  local mount = self.nMountain:fbm2(x / 300, z / 300, 3)
  local t, hum = self:climate(x, z)
  return cont, hills, mount, t, hum
end

-- Wysokość z pól wielkoskalowych + drobny szczegół
function Gen:finishTerrain(x, z, cont, hills, mount, t, hum)
  local detail = self.nDetail:fbm2(x / 36, z / 36, 2)
  local h = SEA + 2 + cont * 16
  -- amplituda wzgórz rośnie z wilgotnością (las bardziej pagórkowaty)
  local hillAmp = 4 + hum * 6
  h = h + hills * hillAmp + detail * 2.5
  -- oceany
  if cont < -0.25 then
    h = h - (-0.25 - cont) * 50
  end
  -- góry
  local m = (mount - 0.3) * 3.2
  if m > 0 then
    if m > 1 then m = 1 end
    local ridge = 1 - abs(self.nHills:noise2(x / 60 + 300, z / 60))
    h = h + m * m * (24 + ridge * 22)
  end
  -- bagna: płasko tuż przy poziomie wody
  if t > 0.45 and t < 0.8 and hum > 0.78 and cont > -0.2 then
    local f = min(1, (hum - 0.78) * 8)
    h = h + (SEA + 0.2 - h) * f * 0.85
  end
  if h < 4 then h = 4 end
  if h > HEIGHT - 8 then h = HEIGHT - 8 end
  return h, m, t, hum
end

-- Wysokość terenu i maska gór w pojedynczej kolumnie
function Gen:terrain(x, z)
  return self:finishTerrain(x, z, self:largeScale(x, z))
end

-- Wybór biomu z parametrów kolumny
local function pickBiome(h, m, t, hum)
  if h < SEA - 4 then return BIOMES.ocean end
  if m > 0.35 then
    if t < 0.25 then return BIOMES.taiga end
    return BIOMES.mountains
  end
  if h < SEA + 1.5 and h >= SEA - 4 and hum < 0.78 then return BIOMES.beach end
  if t < 0.2 then return (hum < 0.4) and BIOMES.tundra or BIOMES.taiga end
  if t > 0.68 and hum < 0.38 then return BIOMES.desert end
  if t > 0.45 and t < 0.8 and hum > 0.78 then return BIOMES.swamp end
  if hum > 0.5 then return BIOMES.forest end
  return BIOMES.plains
end

-- Biom w kolumnie (używany przez generator, pogodę i mgłę)
function Gen:biome(x, z)
  local h, m, t, hum = self:terrain(x, z)
  return pickBiome(h, m, t, hum), h
end

-- Wysokości i biomy całego chunka: pola wielkoskalowe liczone co 4 bloki
-- i interpolowane (10x szybciej niż liczenie każdej kolumny osobno)
function Gen:chunkColumns(cx, cz)
  local bx, bz = cx * 16, cz * 16
  local grid = {}
  for gz = 0, 4 do
    for gx = 0, 4 do
      local a, b, c, d, e = self:largeScale(bx + gx * 4, bz + gz * 4)
      grid[gx + gz * 5] = { a, b, c, d, e }
    end
  end
  local heights, biomes = {}, {}
  for lz = 0, 15 do
    local gz = floor(lz / 4)
    local tz = (lz % 4) / 4
    for lx = 0, 15 do
      local gx = floor(lx / 4)
      local tx = (lx % 4) / 4
      local g00, g10 = grid[gx + gz * 5], grid[gx + 1 + gz * 5]
      local g01, g11 = grid[gx + (gz + 1) * 5], grid[gx + 1 + (gz + 1) * 5]
      local w00 = (1 - tx) * (1 - tz)
      local w10 = tx * (1 - tz)
      local w01 = (1 - tx) * tz
      local w11 = tx * tz
      local h, m, t, hum = self:finishTerrain(bx + lx, bz + lz,
        g00[1] * w00 + g10[1] * w10 + g01[1] * w01 + g11[1] * w11,
        g00[2] * w00 + g10[2] * w10 + g01[2] * w01 + g11[2] * w11,
        g00[3] * w00 + g10[3] * w10 + g01[3] * w01 + g11[3] * w11,
        g00[4] * w00 + g10[4] * w10 + g01[4] * w01 + g11[4] * w11,
        g00[5] * w00 + g10[5] * w10 + g01[5] * w01 + g11[5] * w11)
      heights[lx + lz * 16] = h
      biomes[lx + lz * 16] = pickBiome(h, m, t, hum)
    end
  end
  return heights, biomes
end

-- ---------------------------------------------------------------------------
-- Jaskinie: szum 3D liczony co 4 bloki i interpolowany (szybko)
-- ---------------------------------------------------------------------------
local CS = 4                    -- krok próbkowania
local NX = 16 / CS + 1          -- 5 próbek w poziomie
local NY = HEIGHT / CS + 1      -- 33 próbki w pionie

function Gen:caveField(cx, cz, maxY)
  local field = {}
  local bx, bz = cx * 16, cz * 16
  local syMax = NY - 1
  if maxY then syMax = min(NY - 1, floor(maxY / CS) + 2) end
  for sy = 0, syMax do
    for sz = 0, NX - 1 do
      for sx = 0, NX - 1 do
        local x, y, z = bx + sx * CS, sy * CS, bz + sz * CS
        local a = self.nCave1:noise3(x / 28, y / 18, z / 28)
        local b = self.nCave2:noise3(x / 28, y / 18, z / 28)
        local tunnel = a * a + b * b          -- małe = tunel
        local v = tunnel
        if y < 52 then
          local cav = self.nCavern:noise3(x / 70, y / 34, z / 70)
          if cav > 0.55 then v = v - (cav - 0.55) * 0.5 end
        end
        field[sx + sz * NX + sy * NX * NX] = v
      end
    end
  end
  return field
end

local NXX = NX * NX
local function sampleField(field, lx, y, lz)
  local fx, fy, fz = lx / CS, y / CS, lz / CS
  local x0, y0, z0 = floor(fx), floor(fy), floor(fz)
  if x0 >= NX - 1 then x0 = NX - 2 end
  if z0 >= NX - 1 then z0 = NX - 2 end
  if y0 >= NY - 1 then y0 = NY - 2 end
  local tx, ty, tz = fx - x0, fy - y0, fz - z0
  local i000 = x0 + z0 * NX + y0 * NXX
  local i100, i010, i001 = i000 + 1, i000 + NXX, i000 + NX
  local i110, i101, i011 = i100 + NXX, i100 + NX, i010 + NX
  local i111 = i110 + NX
  local f000, f100, f010, f001 = field[i000], field[i100], field[i010], field[i001]
  local f110, f101, f011, f111 = field[i110], field[i101], field[i011], field[i111]
  local c00 = f000 + (f100 - f000) * tx
  local c10 = f010 + (f110 - f010) * tx
  local c01 = f001 + (f101 - f001) * tx
  local c11 = f011 + (f111 - f011) * tx
  local c0 = c00 + (c10 - c00) * ty
  local c1 = c01 + (c11 - c01) * ty
  return c0 + (c1 - c0) * tz
end

-- ---------------------------------------------------------------------------
-- Wąwozy (Beta 1.8): długie, wąskie i głębokie. Ścieżkę liczymy od chunka
-- startowego, a wycinamy tylko część w bieżącym chunku.
-- ---------------------------------------------------------------------------
function Gen:carveRavines(chunk)
  local cx, cz = chunk.cx, chunk.cz
  local R = 7
  for ocz = cz - R, cz + R do
    for ocx = cx - R, cx + R do
      local rng = Rng.new(Rng.hash(self.seed, ocx, ocz, 777))
      if rng:chance(0.012) then
        local x = ocx * 16 + rng:int(0, 15)
        local z = ocz * 16 + rng:int(0, 15)
        local y = rng:int(22, 46)
        local yaw = rng:next() * math.pi * 2
        local pitch = (rng:next() - 0.5) * 0.25
        local length = rng:int(70, 110)
        local width = rng:range(1.6, 3.2)
        for step = 0, length do
          local prog = step / length
          local r = 1 + math.sin(prog * math.pi) * width
          local rh = r * 3
          x = x + math.cos(yaw) * 1
          z = z + math.sin(yaw) * 1
          y = y + math.sin(pitch)
          yaw = yaw + (rng:next() - 0.5) * 0.15
          pitch = pitch * 0.7 + (rng:next() - 0.5) * 0.1
          -- tylko jeśli elipsa dotyka bieżącego chunka
          local bx0, bz0 = cx * 16, cz * 16
          if x + r >= bx0 and x - r < bx0 + 16 and z + r >= bz0 and z - r < bz0 + 16 then
            for wx = floor(x - r), floor(x + r) do
              for wz = floor(z - r), floor(z + r) do
                local lx, lz = wx - bx0, wz - bz0
                if lx >= 0 and lx < 16 and lz >= 0 and lz < 16 then
                  local dx, dz = (wx + 0.5 - x) / r, (wz + 0.5 - z) / r
                  if dx * dx + dz * dz < 1 then
                    for wy = max(1, floor(y - rh)), min(HEIGHT - 2, floor(y + rh)) do
                      local dy = (wy + 0.5 - y) / rh
                      if dx * dx + dz * dz + dy * dy < 1 then
                        self:carve(chunk, lx, wy, lz)
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end

-- Wycina blok (nie przebija się do wody i nie rusza skały macierzystej)
function Gen:carve(chunk, lx, y, lz)
  local id = chunk:get(lx, y, lz)
  if id == AIR or id == BEDROCK or id == WATER then return end
  if y + 1 < HEIGHT and chunk:get(lx, y + 1, lz) == WATER then return end
  local wasGrass = id == GRASS
  if y <= 10 then
    chunk:setRaw(lx, y, lz, LAVA, 0)
  else
    chunk:setRaw(lx, y, lz, AIR, 0)
    -- trawa "przechodzi" niżej, gdy wycinamy wierzch
    if wasGrass and y > 0 and chunk:get(lx, y - 1, lz) == DIRT then
      chunk:setRaw(lx, y - 1, lz, GRASS, 0)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Rudy: żyły w kształcie małych "robaków" w kamieniu
-- ---------------------------------------------------------------------------
local ORES = {
  { DIRT, 20, 0, 127, 24 },
  { GRAVEL, 10, 0, 127, 24 },
  { COAL_ORE, 20, 0, 127, 14 },
  { IRON_ORE, 20, 0, 63, 8 },
  { GOLD_ORE, 2, 0, 31, 8 },
  { REDSTONE_ORE, 8, 0, 15, 7 },
  { DIAMOND_ORE, 1, 0, 15, 7 },
  { LAPIS_ORE, 1, 0, 30, 6 },
}

local function placeOres(chunk, rng)
  for _, o in ipairs(ORES) do
    local ore, count, y0, y1, size = o[1], o[2], o[3], o[4], o[5]
    for _ = 1, count do
      local x, y, z = rng:int(1, 14), rng:int(y0, y1), rng:int(1, 14)
      for _ = 1, size do
        if x >= 0 and x < 16 and z >= 0 and z < 16 and y > 0 and y < HEIGHT then
          if chunk:get(x, y, z) == STONE then chunk:setRaw(x, y, z, ore, 0) end
        end
        local d = rng:int(1, 6)
        if d == 1 then x = x + 1 elseif d == 2 then x = x - 1
        elseif d == 3 then y = y + 1 elseif d == 4 then y = y - 1
        elseif d == 5 then z = z + 1 else z = z - 1 end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Lochy: komnata z bruku i mchu, spawner i skrzynia ze skarbami
-- ---------------------------------------------------------------------------
local DUNGEON_LOOT = {
  { 296, 1, 4 }, { 289, 1, 4 }, { 287, 1, 4 }, { 325, 1, 1 }, { 265, 1, 4 },
  { 297, 1, 1 }, { 260, 1, 1 }, { 331, 1, 4 }, { 322, 1, 1 }, { 264, 1, 2 },
}

local function tryDungeon(self, chunk, rng)
  local x, y, z = rng:int(4, 11), rng:int(10, 50), rng:int(4, 11)
  local hw = rng:int(2, 3)
  -- musi być pod ziemią: podłoga i sufit z litej skały, a w środku choć trochę jaskini
  local open = 0
  for dx = -hw - 1, hw + 1 do
    for dz = -hw - 1, hw + 1 do
      local lx, lz = x + dx, z + dz
      if lx < 0 or lx > 15 or lz < 0 or lz > 15 then return end
      local floorB = chunk:get(lx, y - 1, lz)
      local ceilB = chunk:get(lx, y + 4, lz)
      if floorB == AIR or floorB == WATER or ceilB == AIR or ceilB == WATER then return end
      for dy = 0, 3 do
        if chunk:get(lx, y + dy, lz) == AIR and (abs(dx) == hw + 1 or abs(dz) == hw + 1) then
          open = open + 1
        end
      end
    end
  end
  if open < 1 or open > 12 then return end
  for dx = -hw - 1, hw + 1 do
    for dz = -hw - 1, hw + 1 do
      for dy = -1, 4 do
        local lx, ly, lz = x + dx, y + dy, z + dz
        local wall = abs(dx) == hw + 1 or abs(dz) == hw + 1 or dy == -1 or dy == 4
        if wall then
          if chunk:get(lx, ly, lz) ~= AIR then
            local b = (dy == -1 and rng:chance(0.6)) and MOSSY or COBBLE
            chunk:setRaw(lx, ly, lz, b, 0)
          end
        else
          chunk:setRaw(lx, ly, lz, AIR, 0)
        end
      end
    end
  end
  chunk:setRaw(x, y, z, SPAWNER, 0)
  local mobsList = { "zombie", "zombie", "skeleton", "spider" }
  chunk.tiles[x + z * 16 + y * 256] = { kind = "spawner", mob = mobsList[rng:int(1, 4)], delay = 200 }
  -- skrzynie przy ścianach
  for _ = 1, 2 do
    local cxp = x + (rng:chance(0.5) and -hw or hw)
    local czp = z + rng:int(-hw, hw)
    if chunk:get(cxp, y, czp) == AIR then
      chunk:setRaw(cxp, y, czp, CHEST, rng:int(0, 3))
      local slots = {}
      for _ = 1, rng:int(3, 7) do
        local l = DUNGEON_LOOT[rng:int(1, #DUNGEON_LOOT)]
        slots[rng:int(1, 27)] = { id = l[1], count = rng:int(l[2], l[3]), damage = 0 }
      end
      chunk.tiles[cxp + czp * 16 + y * 256] = { kind = "chest", pendingSlots = slots }
    end
  end
end

-- ---------------------------------------------------------------------------
-- Główna funkcja generowania chunka
-- ---------------------------------------------------------------------------
function Gen:generate(chunk)
  local cx, cz = chunk.cx, chunk.cz
  local bx, bz = cx * 16, cz * 16
  local rng = Rng.new(Rng.hash(self.seed, cx, cz))
  local heights, biomes = self:chunkColumns(cx, cz)
  local maxH = 0
  for i = 0, 255 do
    heights[i] = floor(heights[i])
    if heights[i] > maxH then maxH = heights[i] end
  end

  local field = self:caveField(cx, cz, maxH)

  for lz = 0, 15 do
    for lx = 0, 15 do
      local x, z = bx + lx, bz + lz
      local col = lx + lz * 16
      local h, biome = heights[col], biomes[col]

      -- głębokość warstwy wierzchniej zmienia się lekko
      local depth = 3 + floor((self.nSurface:noise2(x / 12, z / 12) + 1) * 1.2)
      local top, filler = biome.top, biome.filler
      local underwater = h < SEA - 1
      if underwater then
        local n = self.nSurface:noise2(x / 20 + 100, z / 20)
        if n > 0.4 then top, filler = GRAVEL, GRAVEL
        elseif n < -0.5 and h > SEA - 8 then top, filler = CLAY, DIRT
        else top, filler = SAND, SAND end
        if biome == BIOMES.swamp then top, filler = DIRT, DIRT end
      end
      if biome == BIOMES.mountains and h > 98 then top, filler = STONE, STONE end

      for y = 0, HEIGHT - 1 do
        local id = AIR
        if y == 0 or (y < 4 and rng:int(0, y) == 0) then
          id = BEDROCK
        elseif y < h - depth then
          id = STONE
        elseif y < h then
          id = filler
        elseif y == h then
          id = top
          if top == GRASS and h < SEA - 1 then id = DIRT end
        elseif y < SEA then
          id = WATER
        end
        if id ~= AIR then chunk:setRaw(lx, y, lz, id, 0) end
      end
      -- piaskowiec pod pustynnym piaskiem
      if filler == SAND then
        for y = h - depth - 3, h - depth - 1 do
          if y > 0 and chunk:get(lx, y, lz) == STONE then chunk:setRaw(lx, y, lz, SANDSTONE, 0) end
        end
      end

      -- jaskinie
      local caveTop = min(h + 1, HEIGHT - 2)
      for y = 1, caveTop do
        local v = sampleField(field, lx, y, lz)
        -- tunele cieńsze przy powierzchni, żeby nie dziurawić całego terenu
        local limit = 0.012
        if y > h - 6 then limit = 0.006 end
        if v < limit then self:carve(chunk, lx, y, lz) end
      end
    end
  end

  self:carveRavines(chunk)
  placeOres(chunk, rng)
  if rng:chance(0.25) then tryDungeon(self, chunk, rng) end

  -- powierzchnia po wycięciu jaskiń: lód, śnieg i roślinność
  chunk:recalcHeights()
  self:decorate(chunk, rng, heights, biomes)
end

-- ---------------------------------------------------------------------------
-- Dekoracje: drzewa, trawa, kwiaty, kaktusy, trzcina, dynie, śnieg
-- ---------------------------------------------------------------------------
function Gen:decorate(chunk, rng, heights, biomes)
  local center = biomes[8 + 8 * 16]

  local get = function(x, y, z)
    if x < 0 or x > 15 or z < 0 or z > 15 or y < 0 or y >= HEIGHT then return STONE end
    return chunk:get(x, y, z)
  end
  local set = function(x, y, z, id, meta)
    if x < 0 or x > 15 or z < 0 or z > 15 or y < 0 or y >= HEIGHT then return end
    chunk:setRaw(x, y, z, id, meta)
  end
  local function surfaceY(lx, lz) return chunk:height(lx, lz) end

  -- drzewa (z dala od krawędzi chunka, żeby liście się mieściły)
  local nTrees = center.trees
  local count = floor(nTrees)
  if rng:next() < nTrees - count then count = count + 1 end
  for _ = 1, count do
    local lx, lz = rng:int(2, 13), rng:int(2, 13)
    local y = surfaceY(lx, lz)
    local below = get(lx, y - 1, lz)
    if (below == GRASS or below == DIRT) and y > SEA - 1 then
      local kind = 0
      if center.pine then kind = 1
      elseif center.birch and rng:chance(center.birch) then kind = 2 end
      trees.generate(get, set, lx, y, lz, kind, rng, true)
    end
  end

  -- wysoka trawa, kwiaty, grzyby
  local function scatter(n, id, needBelow)
    for _ = 1, n do
      local lx, lz = rng:int(0, 15), rng:int(0, 15)
      local y = surfaceY(lx, lz)
      if y < HEIGHT and get(lx, y, lz) == AIR and get(lx, y - 1, lz) == needBelow then
        set(lx, y, lz, id, 0)
      end
    end
  end
  if center.grass then scatter(center.grass, TALL_GRASS, GRASS) end
  if center.flowers then
    scatter(rng:int(0, center.flowers), DANDELION, GRASS)
    if rng:chance(0.5) then scatter(rng:int(0, center.flowers), ROSE, GRASS) end
  end
  if center.mushrooms then
    scatter(1, BROWN_MUSH, GRASS)
    if rng:chance(0.3) then scatter(1, RED_MUSH, GRASS) end
  end
  if center.deadBush then scatter(center.deadBush, DEAD_BUSH, SAND) end

  -- kaktusy
  if center.cactus then
    for _ = 1, center.cactus do
      local lx, lz = rng:int(1, 14), rng:int(1, 14)
      local y = surfaceY(lx, lz)
      if get(lx, y - 1, lz) == SAND then
        local free = true
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
          if get(lx + d[1], y, lz + d[2]) ~= AIR then free = false end
        end
        if free then
          for i = 0, rng:int(0, 2) do set(lx, y + i, lz, CACTUS, 0) end
        end
      end
    end
  end

  -- trzcina cukrowa przy wodzie
  for _ = 1, 10 do
    local lx, lz = rng:int(1, 14), rng:int(1, 14)
    local y = surfaceY(lx, lz)
    local below = get(lx, y - 1, lz)
    if y == SEA and (below == GRASS or below == SAND or below == DIRT) and get(lx, y, lz) == AIR then
      local nearWater = false
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        if get(lx + d[1], y - 1, lz + d[2]) == WATER then nearWater = true end
      end
      if nearWater then
        for i = 0, rng:int(1, 2) do set(lx, y + i, lz, SUGAR_CANE, 0) end
      end
    end
  end

  -- dynie (rzadko)
  if rng:chance(1 / 24) then
    for _ = 1, 6 do
      local lx, lz = rng:int(0, 15), rng:int(0, 15)
      local y = surfaceY(lx, lz)
      if get(lx, y - 1, lz) == GRASS and get(lx, y, lz) == AIR then
        set(lx, y, lz, PUMPKIN, rng:int(0, 3))
      end
    end
  end

  -- śnieg i lód w zimnych biomach
  for lz = 0, 15 do
    for lx = 0, 15 do
      local b = biomes[lx + lz * 16]
      if b.snowy then
        local y = surfaceY(lx, lz)
        local below = get(lx, y - 1, lz)
        if below == WATER then
          set(lx, y - 1, lz, ICE, 0)
        elseif y < HEIGHT and get(lx, y, lz) == AIR and below ~= ICE and below ~= CACTUS
          and below ~= 18 and below ~= SNOW_LAYER then
          set(lx, y, lz, SNOW_LAYER, 0)
          if below == GRASS then set(lx, y - 1, lz, GRASS, 1) end
        end
      end
    end
  end
  chunk:recalcHeights()
end

-- Funkcja generatora dla World.new
function M.generator(seed)
  local gen = M.new(seed)
  return function(chunk) gen:generate(chunk) end, gen
end

M.SEA = SEA
return M
