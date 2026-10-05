-- tests/test_nether.lua
local T = require("tests.testlib")
local Game = require("core.game")

local suite = T.suite("nether")

local function flatGame()
  local gen = function(chunk)
    for z = 0, 15 do
      for x = 0, 15 do
        chunk:setRaw(x, 0, z, 7)
        for y = 1, 63 do chunk:setRaw(x, y, z, 1) end
      end
    end
  end
  local g = Game.new({ seed = 7, generator = gen })
  g.world:updateLoading(0, 0, 1, 1000)
  g.difficulty = 0
  return g
end

suite:test("portal: zapalenie, podroz i powrot", function()
  local g = flatGame()
  local w = g.world
  -- rama 4x5 wzdłuż X: wnętrze x=4..5, y=65..67, z=8
  for x = 3, 6 do w:setBlock(x, 64, 8, 49, 0); w:setBlock(x, 68, 8, 49, 0) end
  for y = 65, 67 do w:setBlock(3, y, 8, 49, 0); w:setBlock(6, y, 8, 49, 0) end
  local portal = require("core.portal")
  T.truthy(portal.tryLight(g, 4, 65, 8), "portal zapalony")
  T.eq(w:getBlock(5, 67, 8), 90)
  local p = g.player
  p.x, p.y, p.z = 4.9, 65, 8.5
  p.prevX, p.prevY, p.prevZ = p.x, p.y, p.z
  for _ = 1, 90 do
    g:tick()
    if g.dimension == "nether" then break end
  end
  T.eq(g.dimension, "nether", "jestesmy w Netherze")
  T.truthy(g.world.noSky, "bez nieba")
  -- w pobliżu jest portal powrotny
  local bx, by, bz = math.floor(p.x), math.floor(p.y), math.floor(p.z)
  T.eq(g.world:getBlock(bx, by, bz), 90, "stoimy w portalu po drugiej stronie")
  -- netherrack w okolicy
  local found = false
  for y = 1, 120 do if g.world:getBlock(bx + 8, y, bz + 8) == 87 then found = true break end end
  T.truthy(found, "netherrack")
  -- powrót
  g.portalCooldown = 0
  for _ = 1, 90 do
    g:tick()
    if g.dimension == "overworld" then break end
  end
  T.eq(g.dimension, "overworld", "powrot")
end)

suite:test("rama niepelna nie zapala sie, rozbicie ramy gasi portal", function()
  local g = flatGame()
  local w = g.world
  for x = 3, 6 do w:setBlock(x, 64, 2, 49, 0); w:setBlock(x, 68, 2, 49, 0) end
  for y = 65, 67 do w:setBlock(3, y, 2, 49, 0) end
  local portal = require("core.portal")
  T.eq(portal.tryLight(g, 4, 65, 2), false, "brak prawego boku")
  for y = 65, 67 do w:setBlock(6, y, 2, 49, 0) end
  T.truthy(portal.tryLight(g, 4, 65, 2))
  g:setBlock(6, 66, 2, 0, 0)
  T.eq(w:getBlock(5, 66, 2), 0, "portal zgasl")
end)

return suite
