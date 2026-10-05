-- tests/test_strict.lua
-- Testujemy strict na osobnej tabeli-środowisku, a nie na _G,
-- żeby nie wpływać na resztę testów.
local T = require("tests.testlib")
local strict = require("core.strict")

local suite = T.suite("strict")

-- Kompiluje kod tak, jakby był plikiem .lua (nazwa źródła zaczyna się od "@")
local function compile(code, env)
  local setfenv = rawget(_G, "setfenv")
  if setfenv then
    -- Lua 5.1 / LuaJIT
    local fn = assert(loadstring(code, "@test_chunk.lua"))
    return setfenv(fn, env)
  end
  -- Lua 5.2+
  return assert(load(code, "@test_chunk.lua", "t", env))
end

suite:test("zapis do nowej zmiennej globalnej = blad", function()
  local env = strict.enable({})
  T.raises(compile("zycie = 20", env), "zycie")
end)

suite:test("odczyt nieistniejacej zmiennej = blad", function()
  local env = strict.enable({})
  T.raises(compile("return zdrowie", env), "zdrowie")
end)

suite:test("zadeklarowana zmienna dziala", function()
  local env = strict.enable({})
  strict.declare(env, "glod", 20)
  local fn = compile("glod = glod - 1; return glod", env)
  T.eq(fn(), 19)
end)

suite:test("kod spoza plikow .lua nie jest blokowany", function()
  local env = strict.enable({})
  -- rawget/rawset z C oraz odczyt przez kod z nazwa "=..." przechodzi
  local setfenv = rawget(_G, "setfenv")
  local fn
  if setfenv then
    fn = setfenv(assert(loadstring("return brak", "=[love \"boot.lua\"]")), env)
  else
    fn = assert(load("return brak", "=[love \"boot.lua\"]", "t", env))
  end
  T.eq(fn(), nil)
end)

return suite
