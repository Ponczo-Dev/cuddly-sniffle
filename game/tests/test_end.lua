-- tests/test_end.lua
-- Twierdza, portal Endu, wymiar End i smok.
local T = require("tests.testlib")
local Game = require("core.game")
local Chunk = require("core.chunk")
local structures = require("core.structures")
local endportal = require("core.endportal")
local dragon = require("core.dragon")
local mobs = require("core.mobs")

local suite = T.suite("end")

local function flatGame()
  local gen = function(chunk)
    for z = 0, 15 do
      for x = 0, 15 do
        chunk:setRaw(x, 0, z, 7)
        for y = 1, 62 do chunk:setRaw(x, y, z, 1) end
        chunk:setRaw(x, 63, z, 2)
      end
    end
  end
  local g = Game.new({ seed = 1, generator = gen })
  g.world:updateLoading(0, 0, 1, 1000)
  local p = g.player
  p.x, p.y, p.z = 8.5, 64, 8.5
  p.prevX, p.prevY, p.prevZ = p.x, p.y, p.z
  g.difficulty = 0
  return g
end

suite:test("twierdza: 3 twierdze, sala z 12 ramkami portalu", function()
  local seed = 4321
  local list = structures.strongholdPositions(seed)
  T.eq(#list, 3)
  for _, pos in ipairs(list) do
    local d = math.sqrt(pos[1] ^ 2 + pos[2] ^ 2)
    T.truthy(d >= 24 and d <= 45, "odleglosc w chunkach")
  end
  local _, portal = structures.stronghold(seed, list[1][1], list[1][2])
  -- rysujemy chunki wokół środka ramek i liczymy ramki
  local frames, lava, bricks = 0, 0, 0
  local pcx, pcz = math.floor(portal[1] / 16), math.floor(portal[3] / 16)
  for cz = pcz - 1, pcz + 1 do
    for cx = pcx - 1, pcx + 1 do
      local c = Chunk.new(cx, cz)
      for i = 0, Chunk.VOLUME - 1 do c.blocks[i] = 1 end
      structures.applyUnderground({ seed = seed }, c)
      for i = 0, Chunk.VOLUME - 1 do
        local id = c.blocks[i]
        if id == 120 then frames = frames + 1 elseif id == 10 then lava = lava + 1
        elseif id == 98 or id == 97 or id == 99 then bricks = bricks + 1 end
      end
    end
  end
  T.eq(frames, 12, "12 ramek portalu")
  T.truthy(lava >= 9, "jezioro lawy")
  T.truthy(bricks > 200, "kamienne cegly")
  T.truthy(structures.findStronghold(seed, 0, 0), "/locate stronghold")
end)

suite:test("portal Endu: 12 oczu otwiera portal 3x3", function()
  local g = flatGame()
  local y = 64
  local x0, z0 = 4, 4
  local frames = {}
  for i = 0, 2 do
    frames[#frames + 1] = { x0 - 1, z0 + i }; frames[#frames + 1] = { x0 + 3, z0 + i }
    frames[#frames + 1] = { x0 + i, z0 - 1 }; frames[#frames + 1] = { x0 + i, z0 + 3 }
  end
  for k, f in ipairs(frames) do g.world:setBlock(f[1], y, f[2], 120, k < 12 and 4 or 0) end
  T.eq(g.world:getBlock(x0 + 1, y, z0 + 1), 0, "jeszcze bez portalu")
  g.inventory:set(1, { id = 381, count = 1, damage = 0 })
  g.selected = 1
  local last = frames[12]
  local blocklogic = require("core.blocklogic")
  T.truthy(blocklogic.onUse(g, last[1], y, last[2], 120, 0), "wlozenie oka")
  for i = 0, 2 do
    for j = 0, 2 do T.eq(g.world:getBlock(x0 + i, y, z0 + j), 119, "portal") end
  end
end)

suite:test("End: podroz, platforma, smok i krysztaly, zwyciestwo", function()
  local g = flatGame()
  g.player.gameMode = "survival"
  endportal.travel(g)
  T.eq(g.dimension, "end")
  T.eq(g.world:getBlock(100, 63, 0), 49, "platforma z obsydianu")
  T.truthy(g.world.noSky, "End bez nieba")
  -- wczytaj środek wyspy
  g.world:updateLoading(0, 0, 4, 1000)
  T.eq(g.world:getBlock(0, 60, 0), 121, "kamien Endu")
  dragon.tick(g)
  T.truthy(g.endDragon and g.endDragon.kind == "dragon", "smok sie pojawil")
  local crystals = 0
  for _, e in ipairs(g.entities.list) do if e.type == "crystal" then crystals = crystals + 1 end end
  T.eq(crystals, 10, "10 krysztalow na kolumnach")
  local c
  for _, e in ipairs(g.entities.list) do if e.type == "crystal" then c = e break end end
  mobs.playerAttack(g, c)
  T.eq(g.endState.crystals[c.pillar], false, "krysztal zniszczony")
  -- pokonanie smoka
  local d = g.endDragon
  d.invulnerable = 0
  mobs.damageMob(g, d, 500, "player")
  for _ = 1, 160 do g:tick() end
  T.eq(g.endState.dragonDead, true, "smok pokonany")
  local top = g.endGen:surfaceAt(0, 0) + 1
  T.eq(g.world:getBlock(1, top, 1), 119, "portal powrotny")
  T.eq(g.world:getBlock(0, top + 4, 0), 122, "jajo smoka")
  -- powrót
  endportal.travel(g)
  T.eq(g.dimension, "overworld")
end)

return suite
