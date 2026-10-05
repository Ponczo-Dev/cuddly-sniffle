-- tests/test_clock.lua
local T = require("tests.testlib")
local Clock = require("core.clock")

local suite = T.suite("clock")

suite:test("60 FPS przez sekunde daje 20 tickow", function()
  local clock = Clock.new(20, 10)
  local total = 0
  for _ = 1, 60 do
    total = total + clock:advance(1 / 60)
  end
  T.eq(total, 20)
end)

suite:test("144 FPS przez 10 sekund daje 200 tickow", function()
  local clock = Clock.new(20, 10)
  local total = 0
  for _ = 1, 1440 do
    total = total + clock:advance(1 / 144)
  end
  T.eq(total, 200)
end)

suite:test("dokladnie jeden tick (bledy zaokraglen)", function()
  local clock = Clock.new(20, 10)
  T.eq(clock:advance(0.05), 1)
  T.eq(clock:advance(0.1), 2)
end)

suite:test("alpha miedzy 0 a 1", function()
  local clock = Clock.new(20, 10)
  clock:advance(0.025)
  T.near(clock:alpha(), 0.5, 1e-6)
  clock:advance(0.025)
  T.near(clock:alpha(), 0, 1e-6)
end)

suite:test("przyciecie gry nie powoduje lawiny tickow", function()
  local clock = Clock.new(20, 10)
  T.eq(clock:advance(5), 10, "maks. 10 tickow na klatke")
  T.eq(clock.accumulator, 0)
  T.truthy(clock.droppedTime > 0, "zapisano utracony czas")
end)

suite:test("ujemny czas jest ignorowany", function()
  local clock = Clock.new(20, 10)
  T.eq(clock:advance(-1), 0)
  T.eq(clock.totalTicks, 0)
end)

return suite
