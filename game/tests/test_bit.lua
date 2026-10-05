-- tests/test_bit.lua
local T = require("tests.testlib")
local bit = require("core.bit")

local suite = T.suite("bit")

suite:test("band / bor / bxor", function()
  T.eq(bit.band(0xF0, 0x3C), 0x30)
  T.eq(bit.bor(0xF0, 0x0F), 0xFF)
  T.eq(bit.bxor(0xFF, 0x0F), 0xF0)
end)

suite:test("przesuniecia", function()
  T.eq(bit.lshift(1, 4), 16)
  T.eq(bit.rshift(256, 4), 16)
  T.eq(bit.lshift(1, 31), 2147483648, "bit 31 bez znaku")
  T.eq(bit.rshift(0xFFFFFFFF, 28), 15, "rshift logiczny")
  T.eq(bit.lshift(1, 32), 0)
end)

suite:test("bnot daje liczbe bez znaku", function()
  T.eq(bit.bnot(0), 4294967295)
  T.eq(bit.bnot(0xFFFFFFFF), 0)
end)

suite:test("pakowanie wspolrzednych bloku", function()
  -- x, z: 0..15 (4 bity), y: 0..127 (7 bitow)
  local x, y, z = 13, 100, 7
  local packed = bit.bor(bit.bor(x, bit.lshift(z, 4)), bit.lshift(y, 8))
  T.eq(bit.band(packed, 15), x)
  T.eq(bit.band(bit.rshift(packed, 4), 15), z)
  T.eq(bit.rshift(packed, 8), y)
end)

suite:test("wersja arytmetyczna zgodna z szybka", function()
  local pure = bit.pure
  local values = { 0, 1, 2, 3, 15, 255, 1000, 65535, 123456789,
    2147483647, 2147483648, 4294967295 }
  for _, a in ipairs(values) do
    for _, b in ipairs(values) do
      T.eq(pure.band(a, b), bit.band(a, b), "band " .. a .. "," .. b)
      T.eq(pure.bor(a, b), bit.bor(a, b), "bor " .. a .. "," .. b)
      T.eq(pure.bxor(a, b), bit.bxor(a, b), "bxor " .. a .. "," .. b)
    end
    T.eq(pure.bnot(a), bit.bnot(a), "bnot " .. a)
    for n = 0, 31, 5 do
      T.eq(pure.lshift(a, n), bit.lshift(a, n), "lshift " .. a .. "," .. n)
      T.eq(pure.rshift(a, n), bit.rshift(a, n), "rshift " .. a .. "," .. n)
    end
  end
end)

return suite
