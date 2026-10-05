-- tests/run_all.lua
-- Uruchamia wszystkie testy logiki gry (bez grafiki) przez zwykłe lua.exe:
--   test.bat                      (z głównego folderu projektu)
--   lua.exe tests\run_all.lua     (z folderu game)

-- Ustalamy folder "game" na podstawie ścieżki tego pliku,
-- żeby require("core.xxx") działało niezależnie od miejsca uruchomienia.
local script = (arg and arg[0]) or "tests/run_all.lua"
local base = script:gsub("[/\\]?tests[/\\]run_all%.lua$", "")
if base == "" then base = "." end
package.path = base .. "/?.lua;" .. base .. "/?/init.lua;" .. package.path

local T = require("tests.testlib")

-- Dopisuj tu nowe pliki testów
local files = {
  "test_bit",
  "test_util",
  "test_clock",
  "test_strict",
  "test_states",
  "test_world",
  "test_gameplay",
}

local jit = rawget(_G, "jit")
print("Testy logiki gry - " .. (jit and jit.version or _VERSION))
print(string.rep("-", 50))

local suites = {}
for _, name in ipairs(files) do
  local ok, suite = pcall(require, "tests." .. name)
  if ok then
    suites[#suites + 1] = suite
  else
    -- Błąd składni albo require w pliku testu: zgłaszamy jako nieudany test
    local broken = T.suite(name)
    broken:test("wczytanie pliku", function() error(suite, 0) end)
    suites[#suites + 1] = broken
  end
end

local failed = T.run(suites)
os.exit(failed == 0 and 0 or 1)
