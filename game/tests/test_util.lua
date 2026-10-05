-- tests/test_util.lua
local T = require("tests.testlib")
local util = require("core.util")

local suite = T.suite("util")

suite:test("clamp", function()
  T.eq(util.clamp(5, 0, 10), 5)
  T.eq(util.clamp(-3, 0, 10), 0)
  T.eq(util.clamp(42, 0, 10), 10)
end)

suite:test("lerp", function()
  T.near(util.lerp(0, 10, 0.25), 2.5)
  T.near(util.lerp(4, 8, 0), 4)
  T.near(util.lerp(4, 8, 1), 8)
end)

suite:test("round i sign", function()
  T.eq(util.round(2.4), 2)
  T.eq(util.round(2.5), 3)
  T.eq(util.round(-2.6), -3)
  T.eq(util.sign(-7), -1)
  T.eq(util.sign(0), 0)
  T.eq(util.sign(3), 1)
end)

suite:test("floorDiv i mod dla ujemnych (numer chunka)", function()
  T.eq(util.floorDiv(0, 16), 0)
  T.eq(util.floorDiv(15, 16), 0)
  T.eq(util.floorDiv(16, 16), 1)
  T.eq(util.floorDiv(-1, 16), -1)
  T.eq(util.floorDiv(-16, 16), -1)
  T.eq(util.floorDiv(-17, 16), -2)
  T.eq(util.mod(-1, 16), 15)
end)

suite:test("unpack i copy", function()
  local a, b, c = util.unpack({ 1, 2, 3 })
  T.eq(a + b + c, 6)
  local src = { x = 1, y = 2 }
  local dst = util.copy(src)
  dst.x = 99
  T.eq(src.x, 1, "kopia nie zmienia oryginalu")
  T.eq(dst.y, 2)
end)

return suite
