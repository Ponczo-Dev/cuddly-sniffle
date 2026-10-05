-- core/util.lua
-- Drobne funkcje matematyczne i pomocnicze, używane w całym projekcie.
-- Bez love.*, więc można je testować przez lua.exe.

local M = {}

-- Lua 5.1/LuaJIT ma globalne unpack, Lua 5.2+ ma table.unpack
M.unpack = rawget(_G, "unpack") or table.unpack

function M.clamp(x, lo, hi)
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

function M.lerp(a, b, t)
  return a + (b - a) * t
end

-- Zaokrąglenie do najbliższej liczby całkowitej (0.5 w górę)
function M.round(x)
  return math.floor(x + 0.5)
end

function M.sign(x)
  if x > 0 then return 1 end
  if x < 0 then return -1 end
  return 0
end

-- Dzielenie całkowite z zaokrągleniem w dół (zamiast operatora //).
-- Działa poprawnie dla liczb ujemnych: floorDiv(-1, 16) == -1.
-- Przyda się do przeliczania pozycji bloku na numer chunka.
function M.floorDiv(a, b)
  return math.floor(a / b)
end

-- Reszta zawsze nieujemna (operator % w Lua już tak działa, tu dla czytelności)
function M.mod(a, b)
  return a % b
end

-- Płytka kopia tabeli
function M.copy(t)
  local out = {}
  for k, v in pairs(t) do
    out[k] = v
  end
  return out
end

return M
