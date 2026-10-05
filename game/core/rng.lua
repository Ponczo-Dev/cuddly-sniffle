-- core/rng.lua
-- Deterministyczny generator liczb losowych (Park-Miller, "minimal standard").
-- Ten sam seed = te same liczby w LuaJIT i w Lua 5.4 (math.random tego nie
-- gwarantuje). Wszystkie obliczenia mieszczą się dokładnie w liczbach double.

local M = {}

local MOD = 2147483647 -- 2^31 - 1
local MUL = 16807

local Rng = {}
Rng.__index = Rng

-- Miesza liczbę całkowitą w ziarno 1..MOD-1
local function normalize(seed)
  seed = math.floor(seed) % MOD
  if seed <= 0 then seed = seed + MOD - 1 end
  return seed
end

function M.new(seed)
  local self = setmetatable({ state = normalize(seed or 1) }, Rng)
  -- kilka pierwszych liczb jest słabo losowych - pomijamy je
  for _ = 1, 3 do self:nextInt() end
  return self
end

-- Następna liczba całkowita 1..MOD-1
function Rng:nextInt()
  self.state = (self.state * MUL) % MOD
  return self.state
end

-- Liczba z przedziału [0, 1)
function Rng:next()
  return (self:nextInt() - 1) / (MOD - 1)
end

-- Liczba całkowita z przedziału [a, b]
function Rng:int(a, b)
  return a + math.floor(self:next() * (b - a + 1))
end

-- Liczba rzeczywista z przedziału [a, b)
function Rng:range(a, b)
  return a + self:next() * (b - a)
end

-- true z prawdopodobieństwem p
function Rng:chance(p)
  return self:next() < p
end

-- Haszuje kilka liczb całkowitych (np. seed + współrzędne chunka) w jedno ziarno.
-- Każde ziarno miesza się osobno, więc (1,2) i (2,1) dają inne wyniki.
function M.hash(...)
  local h = 1234567
  local n = select("#", ...)
  for i = 1, n do
    local v = math.floor(select(i, ...)) % MOD
    h = (h * 31 + v + i * 7919) % MOD
    h = (h * MUL) % MOD
    h = (h * MUL) % MOD
  end
  return normalize(h)
end

return M
