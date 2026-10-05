-- core/noise.lua
-- Szum simplex 2D i 3D (algorytm Kena Perlina / Stefana Gustavsona) w czystej
-- Lua. Ten sam seed daje ten sam świat w LuaJIT i w Lua 5.4.

local Rng = require("core.rng")

local M = {}

local floor = math.floor

local GRAD3 = {
  { 1, 1, 0 }, { -1, 1, 0 }, { 1, -1, 0 }, { -1, -1, 0 },
  { 1, 0, 1 }, { -1, 0, 1 }, { 1, 0, -1 }, { -1, 0, -1 },
  { 0, 1, 1 }, { 0, -1, 1 }, { 0, 1, -1 }, { 0, -1, -1 },
}
-- spłaszczone gradienty dla szybkości
local GX, GY, GZ = {}, {}, {}
for i = 0, 11 do
  GX[i], GY[i], GZ[i] = GRAD3[i + 1][1], GRAD3[i + 1][2], GRAD3[i + 1][3]
end

local F2 = 0.5 * (math.sqrt(3) - 1)
local G2 = (3 - math.sqrt(3)) / 6
local F3 = 1 / 3
local G3 = 1 / 6

local Noise = {}
Noise.__index = Noise

function M.new(seed)
  local self = setmetatable({}, Noise)
  local rng = Rng.new(seed)
  local p = {}
  for i = 0, 255 do p[i] = i end
  for i = 255, 1, -1 do
    local j = rng:int(0, i)
    p[i], p[j] = p[j], p[i]
  end
  local perm, permMod12 = {}, {}
  for i = 0, 511 do
    perm[i] = p[i % 256]
    permMod12[i] = perm[i] % 12
  end
  self.perm, self.permMod12 = perm, permMod12
  return self
end

-- Szum 2D w zakresie ok. -1..1
function Noise:noise2(xin, yin)
  local perm, pm = self.perm, self.permMod12
  local s = (xin + yin) * F2
  local i = floor(xin + s)
  local j = floor(yin + s)
  local t = (i + j) * G2
  local x0 = xin - (i - t)
  local y0 = yin - (j - t)
  local i1, j1
  if x0 > y0 then i1, j1 = 1, 0 else i1, j1 = 0, 1 end
  local x1 = x0 - i1 + G2
  local y1 = y0 - j1 + G2
  local x2 = x0 - 1 + 2 * G2
  local y2 = y0 - 1 + 2 * G2
  local ii, jj = i % 256, j % 256
  local n0, n1, n2 = 0, 0, 0
  local t0 = 0.5 - x0 * x0 - y0 * y0
  if t0 > 0 then
    local g = pm[ii + perm[jj]]
    t0 = t0 * t0
    n0 = t0 * t0 * (GX[g] * x0 + GY[g] * y0)
  end
  local t1 = 0.5 - x1 * x1 - y1 * y1
  if t1 > 0 then
    local g = pm[ii + i1 + perm[jj + j1]]
    t1 = t1 * t1
    n1 = t1 * t1 * (GX[g] * x1 + GY[g] * y1)
  end
  local t2 = 0.5 - x2 * x2 - y2 * y2
  if t2 > 0 then
    local g = pm[ii + 1 + perm[jj + 1]]
    t2 = t2 * t2
    n2 = t2 * t2 * (GX[g] * x2 + GY[g] * y2)
  end
  return 70 * (n0 + n1 + n2)
end

-- Szum 3D w zakresie ok. -1..1
function Noise:noise3(xin, yin, zin)
  local perm, pm = self.perm, self.permMod12
  local s = (xin + yin + zin) * F3
  local i = floor(xin + s)
  local j = floor(yin + s)
  local k = floor(zin + s)
  local t = (i + j + k) * G3
  local x0 = xin - (i - t)
  local y0 = yin - (j - t)
  local z0 = zin - (k - t)
  local i1, j1, k1, i2, j2, k2
  if x0 >= y0 then
    if y0 >= z0 then i1, j1, k1, i2, j2, k2 = 1, 0, 0, 1, 1, 0
    elseif x0 >= z0 then i1, j1, k1, i2, j2, k2 = 1, 0, 0, 1, 0, 1
    else i1, j1, k1, i2, j2, k2 = 0, 0, 1, 1, 0, 1 end
  else
    if y0 < z0 then i1, j1, k1, i2, j2, k2 = 0, 0, 1, 0, 1, 1
    elseif x0 < z0 then i1, j1, k1, i2, j2, k2 = 0, 1, 0, 0, 1, 1
    else i1, j1, k1, i2, j2, k2 = 0, 1, 0, 1, 1, 0 end
  end
  local x1, y1, z1 = x0 - i1 + G3, y0 - j1 + G3, z0 - k1 + G3
  local x2, y2, z2 = x0 - i2 + 2 * G3, y0 - j2 + 2 * G3, z0 - k2 + 2 * G3
  local x3, y3, z3 = x0 - 1 + 3 * G3, y0 - 1 + 3 * G3, z0 - 1 + 3 * G3
  local ii, jj, kk = i % 256, j % 256, k % 256
  local n = 0
  local t0 = 0.6 - x0 * x0 - y0 * y0 - z0 * z0
  if t0 > 0 then
    local g = pm[ii + perm[jj + perm[kk]]]
    t0 = t0 * t0
    n = n + t0 * t0 * (GX[g] * x0 + GY[g] * y0 + GZ[g] * z0)
  end
  local t1 = 0.6 - x1 * x1 - y1 * y1 - z1 * z1
  if t1 > 0 then
    local g = pm[ii + i1 + perm[jj + j1 + perm[kk + k1]]]
    t1 = t1 * t1
    n = n + t1 * t1 * (GX[g] * x1 + GY[g] * y1 + GZ[g] * z1)
  end
  local t2 = 0.6 - x2 * x2 - y2 * y2 - z2 * z2
  if t2 > 0 then
    local g = pm[ii + i2 + perm[jj + j2 + perm[kk + k2]]]
    t2 = t2 * t2
    n = n + t2 * t2 * (GX[g] * x2 + GY[g] * y2 + GZ[g] * z2)
  end
  local t3 = 0.6 - x3 * x3 - y3 * y3 - z3 * z3
  if t3 > 0 then
    local g = pm[ii + 1 + perm[jj + 1 + perm[kk + 1]]]
    t3 = t3 * t3
    n = n + t3 * t3 * (GX[g] * x3 + GY[g] * y3 + GZ[g] * z3)
  end
  return 32 * n
end

-- Szum fraktalny (kilka oktaw): bardziej naturalny teren
function Noise:fbm2(x, y, octaves, lacunarity, gain)
  lacunarity, gain = lacunarity or 2, gain or 0.5
  local sum, amp, freq, norm = 0, 1, 1, 0
  for _ = 1, octaves do
    sum = sum + self:noise2(x * freq, y * freq) * amp
    norm = norm + amp
    amp = amp * gain
    freq = freq * lacunarity
  end
  return sum / norm
end

function Noise:fbm3(x, y, z, octaves)
  local sum, amp, freq, norm = 0, 1, 1, 0
  for _ = 1, octaves do
    sum = sum + self:noise3(x * freq, y * freq, z * freq) * amp
    norm = norm + amp
    amp = amp * 0.5
    freq = freq * 2
  end
  return sum / norm
end

return M
