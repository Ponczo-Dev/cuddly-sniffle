-- core/bit.lua
-- Operacje bitowe działające wszędzie:
--   * LuaJIT (LÖVE)  -> biblioteka "bit"
--   * Lua 5.3 / 5.4  -> natywne operatory & | ~ << >> (kompilowane przez load,
--                       żeby LuaJIT nie wywalił się na nieznanej składni)
--   * Lua 5.2        -> bit32
--   * Lua 5.1        -> wersja arytmetyczna (wolniejsza)
--
-- Umowa: argumenty to liczby całkowite, wyniki to liczby 32-bitowe BEZ znaku
-- (0 .. 4294967295). Dzięki temu LuaJIT i Lua 5.4 dają identyczne wyniki.

local M = {}

local TWO32 = 4294967296

-- ---------------------------------------------------------------------------
-- Wersja arytmetyczna (zawsze dostępna jako M.pure, używana też w testach)
-- ---------------------------------------------------------------------------
local pure = {}

local function toU32(x)
  x = math.floor(x) % TWO32
  return x
end

-- Łączy dwie liczby bit po bicie według tabeli prawdy fn(bitA, bitB)
local function bitwise(a, b, fn)
  a, b = toU32(a), toU32(b)
  local result, place = 0, 1
  for _ = 1, 32 do
    local ba, bb = a % 2, b % 2
    if fn(ba, bb) then
      result = result + place
    end
    a = (a - ba) / 2
    b = (b - bb) / 2
    place = place * 2
  end
  return result
end

local function fAnd(x, y) return x == 1 and y == 1 end
local function fOr(x, y) return x == 1 or y == 1 end
local function fXor(x, y) return x ~= y end

function pure.band(a, b) return bitwise(a, b, fAnd) end
function pure.bor(a, b) return bitwise(a, b, fOr) end
function pure.bxor(a, b) return bitwise(a, b, fXor) end
function pure.bnot(a) return TWO32 - 1 - toU32(a) end

function pure.lshift(a, n)
  if n >= 32 then return 0 end
  return (toU32(a) * 2 ^ n) % TWO32
end

function pure.rshift(a, n)
  if n >= 32 then return 0 end
  return math.floor(toU32(a) / 2 ^ n)
end

M.pure = pure

-- ---------------------------------------------------------------------------
-- Wybór najszybszej implementacji
-- ---------------------------------------------------------------------------
local ok, lj = pcall(require, "bit")

if ok and type(lj) == "table" and lj.band then
  -- LuaJIT zwraca liczby ZE znakiem (int32), więc je normalizujemy
  local band, bor, bxor, bnot = lj.band, lj.bor, lj.bxor, lj.bnot
  local lshift, rshift = lj.lshift, lj.rshift
  local function u(x)
    if x < 0 then return x + TWO32 end
    return x
  end
  M.impl = "luajit"
  function M.band(a, b) return u(band(a, b)) end
  function M.bor(a, b) return u(bor(a, b)) end
  function M.bxor(a, b) return u(bxor(a, b)) end
  function M.bnot(a) return u(bnot(a)) end
  function M.lshift(a, n)
    if n >= 32 then return 0 end
    return u(lshift(a, n))
  end
  function M.rshift(a, n)
    if n >= 32 then return 0 end
    return u(rshift(a, n))
  end
else
  -- Lua 5.3+: kod z operatorami trzymamy w stringu
  -- (w Lua 5.1 "load" nie przyjmuje stringa, stąd loadstring najpierw)
  local loader = rawget(_G, "loadstring") or load
  local native = loader and loader([[
    local M = ...
    local MASK = 0xFFFFFFFF
    M.band = function(a, b) return (a & b) & MASK end
    M.bor = function(a, b) return (a | b) & MASK end
    M.bxor = function(a, b) return (a ~ b) & MASK end
    M.bnot = function(a) return (~a) & MASK end
    M.lshift = function(a, n)
      if n >= 32 then return 0 end
      return (a << n) & MASK
    end
    M.rshift = function(a, n)
      if n >= 32 then return 0 end
      return (a & MASK) >> n
    end
  ]])

  if native then
    native(M)
    M.impl = "native"
  elseif rawget(_G, "bit32") then
    local b32 = rawget(_G, "bit32")
    M.impl = "bit32"
    M.band, M.bor, M.bxor, M.bnot = b32.band, b32.bor, b32.bxor, b32.bnot
    M.lshift, M.rshift = b32.lshift, b32.rshift
  else
    M.impl = "pure"
    for name, fn in pairs(pure) do
      M[name] = fn
    end
  end
end

return M
