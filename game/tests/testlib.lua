-- tests/testlib.lua
-- Minimalny framework testów: zestawy (suite), testy i asercje.
-- Komunikaty bez polskich znaków (konsola Windows).

local T = {}

local Suite = {}
Suite.__index = Suite

function T.suite(name)
  return setmetatable({ name = name, cases = {} }, Suite)
end

function Suite:test(name, fn)
  self.cases[#self.cases + 1] = { name = name, fn = fn }
end

-- Ładny zapis wartości w komunikatach błędów
local function show(v)
  if type(v) == "string" then
    return string.format("%q", v)
  end
  return tostring(v)
end

function T.eq(actual, expected, msg)
  if actual ~= expected then
    error((msg and (msg .. ": ") or "") .. "oczekiwano " .. show(expected)
      .. ", jest " .. show(actual), 2)
  end
end

function T.near(actual, expected, eps, msg)
  eps = eps or 1e-9
  if type(actual) ~= "number" or math.abs(actual - expected) > eps then
    error((msg and (msg .. ": ") or "") .. "oczekiwano ~" .. show(expected)
      .. " (+-" .. eps .. "), jest " .. show(actual), 2)
  end
end

function T.truthy(value, msg)
  if not value then
    error(msg or ("oczekiwano prawdy, jest " .. show(value)), 2)
  end
end

-- Sprawdza, że fn rzuca błąd (opcjonalnie zawierający podany tekst)
function T.raises(fn, pattern, msg)
  local ok, err = pcall(fn)
  if ok then
    error(msg or "oczekiwano bledu, a funkcja przeszla", 2)
  end
  if pattern and not tostring(err):find(pattern, 1, true) then
    error((msg and (msg .. ": ") or "") .. "blad nie zawiera "
      .. show(pattern) .. ": " .. tostring(err), 2)
  end
end

-- Uruchamia listę zestawów, wypisuje wyniki, zwraca liczbę błędów
function T.run(suites)
  local passed, failed = 0, 0
  for _, suite in ipairs(suites) do
    for _, case in ipairs(suite.cases) do
      local ok, err = pcall(case.fn)
      if ok then
        passed = passed + 1
        print("[OK]   " .. suite.name .. ": " .. case.name)
      else
        failed = failed + 1
        print("[BLAD] " .. suite.name .. ": " .. case.name)
        print("       " .. tostring(err))
      end
    end
  end
  print(string.rep("-", 50))
  print(string.format("Wynik: %d OK, %d BLAD", passed, failed))
  return failed
end

return T
