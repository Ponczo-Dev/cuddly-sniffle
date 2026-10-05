-- core/nethergen.lua
-- Generator Netheru: jaskiniowy świat z netherracku między skałą
-- macierzystą na dole i na górze, morze lawy (y <= 31), wiszące skupiska
-- jasnogłazu, łaty piasku dusz i żwiru, wieczny ogień.

local Noise = require("core.noise")
local Rng = require("core.rng")

local M = {}

local floor, min, max = math.floor, math.min, math.max
local HEIGHT = 128
local AIR, BEDROCK, LAVA, GRAVEL = 0, 7, 10, 13
local NETHERRACK, SOUL_SAND, GLOWSTONE, FIRE = 87, 88, 89, 51

local Gen = {}
Gen.__index = Gen

function M.new(seed)
  local self = setmetatable({}, Gen)
  self.seed = seed
  self.n1 = Noise.new(Rng.hash(seed, 101))
  self.n2 = Noise.new(Rng.hash(seed, 102))
  self.n3 = Noise.new(Rng.hash(seed, 103))
  return self
end

local CS = 4
local NX = 16 / CS + 1
local NY = HEIGHT / CS + 1

function Gen:density(cx, cz)
  local field = {}
  local bx, bz = cx * 16, cz * 16
  for sy = 0, NY - 1 do
    local y = sy * CS
    -- bliżej podłogi i sufitu więcej skały
    local edge = 0
    if y < 12 then edge = (12 - y) / 12 * 1.5 end
    if y > 104 then edge = (y - 104) / 23 * 1.5 end
    for sz = 0, NX - 1 do
      for sx = 0, NX - 1 do
        local x, z = bx + sx * CS, bz + sz * CS
        local d = self.n1:noise3(x / 64, y / 36, z / 64) * 0.7
          + self.n2:noise3(x / 22, y / 16, z / 22) * 0.35 + edge - 0.05
        field[sx + sz * NX + sy * NX * NX] = d
      end
    end
  end
  return field
end

local NXX = NX * NX
local function sample(field, lx, y, lz)
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
  local c00 = field[i000] + (field[i100] - field[i000]) * tx
  local c10 = field[i010] + (field[i110] - field[i010]) * tx
  local c01 = field[i001] + (field[i101] - field[i001]) * tx
  local c11 = field[i011] + (field[i111] - field[i011]) * tx
  local c0 = c00 + (c10 - c00) * ty
  local c1 = c01 + (c11 - c01) * ty
  return c0 + (c1 - c0) * tz
end

function Gen:generate(chunk)
  local cx, cz = chunk.cx, chunk.cz
  local rng = Rng.new(Rng.hash(self.seed, cx, cz, 66))
  local field = self:density(cx, cz)
  for lz = 0, 15 do
    for lx = 0, 15 do
      for y = 0, HEIGHT - 1 do
        local id = AIR
        if y == 0 or y == HEIGHT - 1 or (y < 5 and rng:int(0, y) == 0)
          or (y > HEIGHT - 6 and rng:int(0, HEIGHT - 1 - y) == 0) then
          id = BEDROCK
        elseif sample(field, lx, y, lz) > 0 then
          id = NETHERRACK
        elseif y <= 31 then
          id = LAVA
        end
        if id ~= AIR then chunk:setRaw(lx, y, lz, id, 0) end
      end
    end
  end

  -- piasek dusz i żwir na powierzchniach (wierzch netherracku)
  local bx, bz = cx * 16, cz * 16
  for lz = 0, 15 do
    for lx = 0, 15 do
      local n = self.n3:noise2((bx + lx) / 16, (bz + lz) / 16)
      for y = 30, 90 do
        if chunk:get(lx, y, lz) == NETHERRACK and chunk:get(lx, y + 1, lz) == AIR then
          if n > 0.45 then
            for d = 0, 2 do
              if chunk:get(lx, y - d, lz) == NETHERRACK then chunk:setRaw(lx, y - d, lz, SOUL_SAND, 0) end
            end
            -- kępki brodawek netherowych na piasku dusz
            if n > 0.55 and rng:chance(0.08) then chunk:setRaw(lx, y + 1, lz, 115, rng:int(1, 3)) end
          elseif n < -0.55 and y <= 34 then
            chunk:setRaw(lx, y, lz, GRAVEL, 0)
          end
        end
      end
    end
  end

  -- jasnogłaz zwisający z sufitu
  for _ = 1, 6 do
    local x, z = rng:int(2, 13), rng:int(2, 13)
    local y = rng:int(60, 120)
    -- szukaj sufitu: powietrze pod netherrackiem
    local found = false
    for yy = y, 40, -1 do
      if chunk:get(x, yy, z) == AIR and chunk:get(x, yy + 1, z) == NETHERRACK then
        y = yy
        found = true
        break
      end
    end
    if found then
      chunk:setRaw(x, y, z, GLOWSTONE, 0)
      for _ = 1, rng:int(10, 30) do
        local gx = x + rng:int(-2, 2)
        local gy = y - rng:int(0, 5)
        local gz = z + rng:int(-2, 2)
        if gx >= 0 and gx < 16 and gz >= 0 and gz < 16 and gy > 1 and chunk:get(gx, gy, gz) == AIR then
          -- przyczep do sąsiedniego jasnogłazu
          local attached = chunk:get(gx, gy + 1, gz) == GLOWSTONE
            or (gx > 0 and chunk:get(gx - 1, gy, gz) == GLOWSTONE)
            or (gx < 15 and chunk:get(gx + 1, gy, gz) == GLOWSTONE)
            or (gz > 0 and chunk:get(gx, gy, gz - 1) == GLOWSTONE)
            or (gz < 15 and chunk:get(gx, gy, gz + 1) == GLOWSTONE)
          if attached then chunk:setRaw(gx, gy, gz, GLOWSTONE, 0) end
        end
      end
    end
  end

  -- wieczny ogień na netherracku
  for _ = 1, rng:int(0, 3) do
    local x, z = rng:int(0, 15), rng:int(0, 15)
    for y = 32, 100 do
      if chunk:get(x, y, z) == NETHERRACK and chunk:get(x, y + 1, z) == AIR then
        if rng:chance(0.3) then chunk:setRaw(x, y + 1, z, FIRE, 0) end
        break
      end
    end
  end
  chunk:recalcHeights()
end

M.BIOME = { name = "Nether", fog = { 0.25, 0.04, 0.03 }, dry = true, nether = true }

return M
