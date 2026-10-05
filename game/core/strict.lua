-- core/strict.lua
-- Tryb "strict": wyłapuje literówki w nazwach zmiennych.
-- Po włączeniu każdy odczyt albo zapis NIEZADEKLAROWANEJ zmiennej globalnej
-- z naszego kodu kończy się czytelnym błędem, zamiast cicho dawać nil.
--
-- Wbudowane skrypty LÖVE (boot.lua itd.) i funkcje w C są pomijane,
-- bo ich nazwy źródła zaczynają się od "=" albo nie są kodem Lua.
-- Komunikaty bez polskich znaków, bo konsola Windows źle wyświetla UTF-8.

local M = {}

-- Czy funkcja na danym poziomie stosu to nasz plik .lua?
local function isOurCode(level)
  local info = debug.getinfo(level, "S")
  if not info or info.what == "C" then
    return false
  end
  local src = info.source or ""
  return src:sub(1, 1) == "@"
end

-- Włącza strict dla podanej tabeli (domyślnie _G).
function M.enable(env)
  env = env or _G
  local mt = getmetatable(env) or {}

  -- isOurCode(3): poziom 1 = isOurCode, 2 = metametoda, 3 = kod, który sięga po zmienną
  mt.__newindex = function(t, key, value)
    if isOurCode(3) then
      error("strict: przypisanie do niezadeklarowanej zmiennej globalnej '"
        .. tostring(key) .. "' (uzyj 'local' albo strict.declare)", 2)
    end
    rawset(t, key, value)
  end

  mt.__index = function(_, key)
    if isOurCode(3) then
      error("strict: odczyt niezadeklarowanej zmiennej globalnej '"
        .. tostring(key) .. "' (literowka?)", 2)
    end
    return nil
  end

  setmetatable(env, mt)
  return env
end

-- Świadome utworzenie zmiennej globalnej (używaj rzadko).
function M.declare(env, key, value)
  rawset(env or _G, key, value)
end

return M
