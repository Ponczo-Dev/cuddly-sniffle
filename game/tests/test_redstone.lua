-- tests/test_redstone.lua
local T = require("tests.testlib")
local Game = require("core.game")

local suite = T.suite("redstone")

local function flatGame()
  local gen = function(chunk)
    for z = 0, 15 do
      for x = 0, 15 do
        chunk:setRaw(x, 0, z, 7)
        for y = 1, 63 do chunk:setRaw(x, y, z, 1) end
      end
    end
  end
  local g = Game.new({ seed = 1, generator = gen })
  g.world:updateLoading(0, 0, 1, 1000)
  g.player.x, g.player.y, g.player.z = 0.5, 64, -20.5
  g.difficulty = 0
  return g
end

local function run(g, n) for _ = 1, n do g:tick() end end

suite:test("dzwignia -> przewod -> lampa", function()
  local g = flatGame()
  local w = g.world
  -- dźwignia na podłodze, 3 przewody, lampa
  g:setBlock(2, 64, 2, 69, 0)
  for x = 3, 5 do g:setBlock(x, 64, 2, 55, 0) end
  g:setBlock(6, 64, 2, 123, 0)
  run(g, 2)
  T.eq(w:getBlock(6, 64, 2), 123, "lampa zgaszona")
  require("core.blocklogic").onUse(g, 2, 64, 2, 69, 0)
  run(g, 2)
  T.eq(w:getMeta(3, 64, 2), 15, "przewod przy dzwigni 15")
  T.eq(w:getMeta(5, 64, 2), 13, "slabnie o 1")
  T.eq(w:getBlock(6, 64, 2), 124, "lampa swieci")
  require("core.blocklogic").onUse(g, 2, 64, 2, 69, 8)
  run(g, 10)
  T.eq(w:getMeta(4, 64, 2), 0, "przewod bez mocy")
  T.eq(w:getBlock(6, 64, 2), 123, "lampa zgasla")
end)

suite:test("pochodnia odwraca sygnal", function()
  local g = flatGame()
  local w = g.world
  -- blok kamienia na ziemi, pochodnia na jego boku, dźwignia na górze
  g:setBlock(5, 64, 5, 1, 0)
  g:setBlock(6, 64, 5, 76, 1)   -- podpora z -X (blok 5,64,5)
  run(g, 4)
  T.eq(w:getBlock(6, 64, 5), 76, "pochodnia swieci")
  g:setBlock(5, 65, 5, 69, 0)   -- dźwignia na bloku
  require("core.blocklogic").onUse(g, 5, 65, 5, 69, 0)
  run(g, 4)
  T.eq(w:getBlock(6, 64, 5), 75, "zgasla - blok zasilony")
end)

suite:test("przekaznik z opoznieniem", function()
  local g = flatGame()
  local w = g.world
  g:setBlock(2, 64, 8, 69, 0)
  g:setBlock(3, 64, 8, 93, 3)   -- wyjście na +X (wschód)
  g:setBlock(4, 64, 8, 55, 0)
  require("core.blocklogic").onUse(g, 2, 64, 8, 69, 0)
  run(g, 1)
  T.eq(w:getMeta(4, 64, 8), 0, "jeszcze nie (opoznienie)")
  run(g, 3)
  T.eq(w:getBlock(3, 64, 8), 94, "wlaczony")
  T.eq(w:getMeta(4, 64, 8), 15, "przewod za przekaznikiem 15")
end)

suite:test("tlok pcha blok, lepki ciagnie", function()
  local g = flatGame()
  local w = g.world
  -- tłok skierowany na +X (facing 5), przed nim kamień
  g:setBlock(5, 64, 10, 33, 5)
  g:setBlock(6, 64, 10, 4, 0)
  g:setBlock(4, 64, 10, 69, 0)
  require("core.blocklogic").onUse(g, 4, 64, 10, 69, 0)
  run(g, 2)
  T.eq(w:getBlock(6, 64, 10), 34, "glowica")
  T.eq(w:getBlock(7, 64, 10), 4, "bruk przesuniety")
  require("core.blocklogic").onUse(g, 4, 64, 10, 69, 8)
  run(g, 2)
  T.eq(w:getBlock(6, 64, 10), 0, "glowica schowana")
  T.eq(w:getBlock(7, 64, 10), 4, "zwykly tlok nie ciagnie")
  -- lepki
  g:setBlock(5, 64, 12, 29, 5)
  g:setBlock(6, 64, 12, 3, 0)
  g:setBlock(4, 64, 12, 69, 0)
  require("core.blocklogic").onUse(g, 4, 64, 12, 69, 0)
  run(g, 2)
  T.eq(w:getBlock(7, 64, 12), 3)
  require("core.blocklogic").onUse(g, 4, 64, 12, 69, 8)
  run(g, 2)
  T.eq(w:getBlock(6, 64, 12), 3, "lepki przyciagnal ziemie")
  T.eq(w:getBlock(7, 64, 12), 0)
  -- obsydianu nie pcha
  g:setBlock(5, 64, 14, 33, 5)
  g:setBlock(6, 64, 14, 49, 0)
  g:setBlock(4, 64, 14, 69, 0)
  require("core.blocklogic").onUse(g, 4, 64, 14, 69, 0)
  run(g, 2)
  T.eq(w:getBlock(6, 64, 14), 49, "obsydian zostal")
end)

suite:test("plotek laczy sie z sasiadami", function()
  local g = flatGame()
  local w = g.world
  g:setBlock(8, 64, 3, 85, 0)
  g:setBlock(9, 64, 3, 85, require("core.blocklogic").fenceMeta(w, 9, 64, 3))
  T.eq(w:getMeta(8, 64, 3) % 2, 1, "polaczony na +X")
  T.eq(math.floor(w:getMeta(9, 64, 3) / 2) % 2, 1, "polaczony na -X")
end)

return suite
