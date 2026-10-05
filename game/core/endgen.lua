-- core/endgen.lua
-- Generator wymiaru End: pływająca wyspa z kamienia Endu nad pustką
-- (środek w 0,0), dziesięć obsydianowych kolumn w kręgu, na każdej
-- skała macierzysta, na której stoi kryształ Endu (kryształy i smoka
-- tworzy core/dragon.lua).

local Rng = require("core.rng")
local Noise = require("core.noise")

local M = {}

local floor, sqrt = math.floor, math.sqrt
local END_STONE, OBSIDIAN, BEDROCK = 121, 49, 7

M.ISLAND_RADIUS = 72
M.PILLAR_RING = 42
M.PILLARS = 10
M.SURFACE = 62

local Gen = {}
Gen.__index = Gen

function M.new(seed)
  local self = setmetatable({}, Gen)
  self.seed = seed
  self.noise = Noise.new(Rng.hash(seed, 1, 2, 3))
  self.pillars = M.pillars(seed)
  return self
end

-- Kolumny: { x, z, radius, height } (deterministyczne z seeda)
function M.pillars(seed)
  local rng = Rng.new(Rng.hash(seed, 77, 77, 77))
  local a0 = rng:next() * math.pi * 2
  local list = {}
  for i = 0, M.PILLARS - 1 do
    local a = a0 + i * math.pi * 2 / M.PILLARS
    list[#list + 1] = {
      x = floor(math.cos(a) * M.PILLAR_RING + 0.5), z = floor(math.sin(a) * M.PILLAR_RING + 0.5),
      r = rng:int(2, 4), h = 76 + rng:int(0, 9) * 3,
    }
  end
  return list
end

-- Wysokość wierzchu i spodu wyspy w kolumnie (nil = pustka)
function Gen:column(x, z)
  local d = sqrt(x * x + z * z)
  local n = self.noise:noise2(x / 40, z / 40)
  local R = M.ISLAND_RADIUS + n * 14
  if d >= R then return nil end
  local f = 1 - d / R
  local top = floor(M.SURFACE + f * 6 + self.noise:noise2(x / 14, z / 14) * 2)
  local bottom = floor(M.SURFACE - sqrt(f) * 42 - self.noise:noise2(x / 9 + 50, z / 9) * 4)
  return top, bottom
end

function Gen:generate(chunk)
  local bx, bz = chunk.cx * 16, chunk.cz * 16
  for lz = 0, 15 do
    for lx = 0, 15 do
      local top, bottom = self:column(bx + lx, bz + lz)
      if top then
        for y = math.max(1, bottom), top do chunk:setRaw(lx, y, lz, END_STONE, 0) end
      end
    end
  end
  -- obsydianowe kolumny
  for _, p in ipairs(self.pillars) do
    if p.x + p.r >= bx and p.x - p.r < bx + 16 and p.z + p.r >= bz and p.z - p.r < bz + 16 then
      for x = p.x - p.r, p.x + p.r do
        for z = p.z - p.r, p.z + p.r do
          if x >= bx and x < bx + 16 and z >= bz and z < bz + 16
            and (x - p.x) ^ 2 + (z - p.z) ^ 2 <= p.r * p.r + 1 then
            for y = M.SURFACE - 10, p.h do chunk:setRaw(x - bx, y, z - bz, OBSIDIAN, 0) end
          end
        end
      end
      if p.x >= bx and p.x < bx + 16 and p.z >= bz and p.z < bz + 16 then
        chunk:setRaw(p.x - bx, p.h + 1, p.z - bz, BEDROCK, 0)
      end
    end
  end
  chunk:recalcHeights()
end

-- Najwyższy blok wyspy w danej kolumnie (do postawienia portalu wyjścia)
function Gen:surfaceAt(x, z)
  local top = self:column(x, z)
  return top or M.SURFACE
end

M.BIOME = { name = "End", fog = { 0.1, 0.08, 0.13 }, dry = true, theEnd = true }

return M
