-- tests/test_gameplay.lua
-- Testy logiki rozgrywki: ekwipunek, crafting, piec, survival, fizyka,
-- oświetlenie, zapis chunków.
local T = require("tests.testlib")
local Inventory = require("core.inventory")
local Container = require("core.container")
local recipes = require("core.recipes")
local items = require("core.items")
local World = require("core.world")
local Chunk = require("core.chunk")
local lighting = require("core.lighting")
local save = require("core.save")
local serialize = require("core.serialize")
local Game = require("core.game")

local suite = T.suite("gameplay")

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

suite:test("ekwipunek: stackowanie i limity", function()
  local inv = Inventory.new(36)
  T.eq(inv:add({ id = 4, count = 100 }), 0)
  T.eq(inv.slots[1].count, 64)
  T.eq(inv.slots[2].count, 36)
  T.eq(inv:add({ id = 257, count = 2 }), 0, "narzedzia po 1 w slocie")
  T.eq(inv.slots[3].count, 1)
  T.eq(inv.slots[4].count, 1)
  T.eq(inv:count(4), 100)
  T.eq(inv:removeItem(4, 70), 70)
  T.eq(inv:count(4), 30)
end)

suite:test("ekwipunek: zuzycie narzedzia", function()
  local inv = Inventory.new(9)
  inv:set(1, { id = 270, count = 1, damage = 57 }) -- drewniany kilof, 59 wytrzymałości
  T.eq(inv:damageItem(1, 1), false)
  T.eq(inv:damageItem(1, 1), true, "zepsuty")
  T.eq(inv.slots[1], nil)
end)

suite:test("crafting: deski, patyki, kilof, lustrzane odbicie", function()
  local grid = { { id = 17, count = 1, damage = 0 } }
  local r = recipes.match(grid, 2)
  T.eq(r.id, 5); T.eq(r.count, 4)
  local g3 = {}
  g3[1] = { id = 5, count = 1 }; g3[2] = { id = 5, count = 1 }; g3[3] = { id = 5, count = 1 }
  g3[5] = { id = 280, count = 1 }; g3[8] = { id = 280, count = 1 }
  T.eq(recipes.match(g3, 3).id, 270, "drewniany kilof")
  -- siekiera i jej lustrzane odbicie
  local axe = { [1] = { id = 4 }, [2] = { id = 4 }, [4] = { id = 4 }, [5] = { id = 280 }, [8] = { id = 280 } }
  T.eq(recipes.match(axe, 3).id, 275)
  local axeM = { [2] = { id = 4 }, [3] = { id = 4 }, [6] = { id = 4 }, [5] = { id = 280 }, [8] = { id = 280 } }
  T.eq(recipes.match(axeM, 3).id, 275, "odbicie")
  T.eq(recipes.match({ [1] = { id = 3 } }, 2), nil, "ziemia nic nie robi")
  -- przesunięta receptura (patyki w prawej kolumnie)
  local sticks = { [2] = { id = 5 }, [4] = { id = 5 } }
  T.eq(recipes.match(sticks, 2).id, 280)
  -- pochodnia z węgla drzewnego
  local torch = { [1] = { id = 263, damage = 1 }, [3] = { id = 280 } }
  T.eq(recipes.match(torch, 2).id, 50)
end)

suite:test("okno: klik, prawy klik, shift, crafting z wynikiem", function()
  local player = Inventory.new(36)
  local craft = Inventory.new(5)
  player:set(1, { id = 17, count = 3, damage = 0 })
  local slots = {}
  for i = 1, 4 do slots[#slots + 1] = { inv = craft, i = i, group = "craft" } end
  slots[#slots + 1] = { inv = craft, i = 5, group = "result" }
  for i = 1, 9 do slots[#slots + 1] = { inv = player, i = i, group = "hotbar" } end
  for i = 10, 36 do slots[#slots + 1] = { inv = player, i = i, group = "main" } end
  local c = Container.new(slots, { craftSize = 2 })
  c:click(6, "left", false)          -- weź 3 pnie
  T.eq(c.cursor.count, 3)
  c:click(1, "right", false)         -- połóż 1 w siatce
  T.eq(c.cursor.count, 2)
  T.eq(craft.slots[5].id, 5, "wynik: deski")
  c:click(5, "left", false)          -- zabierz deski -> kursor zajęty pniami, nie można
  T.eq(c.cursor.id, 17)
  c:click(7, "left", false)          -- odłóż pnie do slotu 2 paska
  T.eq(c.cursor, nil)
  c:click(5, "left", false)          -- zabierz 4 deski
  T.eq(c.cursor.id, 5)
  T.eq(c.cursor.count, 4)
  T.eq(craft.slots[1], nil, "pien zuzyty")
  T.eq(craft.slots[5], nil, "brak wyniku")
  c:click(8, "left", false)
  -- shift-craft: 2 pnie -> 8 desek
  c:click(7, "left", false)          -- weź 2 pnie
  c:click(1, "left", false)          -- wszystkie do siatki
  c:click(5, "left", true)           -- shift na wyniku
  T.eq(player:count(5), 12)
  T.eq(craft.slots[1], nil)
end)

suite:test("piec: przetapia rude zelaza", function()
  local g = flatGame()
  g.world:setBlock(5, 64, 5, 61, 0)
  local tile = g:getOrCreateTile(5, 64, 5)
  tile.inventory:set(1, { id = 15, count = 2 })
  tile.inventory:set(2, { id = 263, count = 1 })
  for _ = 1, 410 do g:tickTiles() end
  T.eq(tile.inventory.slots[3].id, 265)
  T.eq(tile.inventory.slots[3].count, 2)
  T.eq(tile.inventory.slots[1], nil)
end)

suite:test("survival: obrazenia od upadku i pancerz", function()
  local g = flatGame()
  local p = g.player
  for _ = 1, 20 do g:tick() end
  T.truthy(p.onGround, "stoi na ziemi")
  p.y = 74; p.prevY = 74; p.vy = 0
  for _ = 1, 60 do g:tick() end
  T.truthy(g.health < 20, "upadek z 10 kratek boli")
  T.truthy(g.health >= 12, "ale nie za mocno: " .. g.health)
  -- pancerz zmniejsza obrażenia
  g.health = 20
  g.invulnerable = 0
  g.armor:set(2, { id = 311, count = 1, damage = 0 }) -- diamentowy napierśnik (8)
  g.survival.damage(g, 10, "mob")
  T.truthy(g.health >= 13, "z pancerzem: " .. g.health)
end)

suite:test("survival: glod i regeneracja", function()
  local g = flatGame()
  g.difficulty = 2
  g.health = 10
  for _ = 1, 400 do g:tick() end
  T.truthy(g.health > 10, "regeneracja przy pelnym glodzie")
  g.food = 0
  g.saturation = 0
  g.health = 20
  for _ = 1, 2000 do g:tick() end
  T.truthy(g.health <= 10, "glod na normalnym zabiera do 1 serca... jest " .. g.health)
  T.truthy(g.health >= 1, "ale nie zabija")
end)

suite:test("kopanie i drop", function()
  local g = flatGame()
  local p = g.player
  p.pitch = -math.pi / 2 + 0.01
  for _ = 1, 5 do g:tick() end
  g.input.attack = true
  for _ = 1, 60 do g:tick() end
  g.input.attack = false
  T.eq(g.world:getBlock(8, 63, 8), 0, "trawa wykopana")
  for _ = 1, 40 do g:tick() end
  T.eq(g.inventory:count(3), 1, "ziemia w ekwipunku")
end)

suite:test("stawianie bloku i zakaz w graczu", function()
  local g = flatGame()
  local p = g.player
  g.inventory:set(1, { id = 4, count = 5 })
  p.pitch = -0.6
  for _ = 1, 5 do g:tick() end
  local hit = g:target()
  T.truthy(hit, "celuje w ziemie")
  T.truthy(g:placeFromHand(hit))
  T.eq(g.inventory.slots[1].count, 4)
  -- nie można postawić w miejscu gracza
  local fake = { x = 8, y = 63, z = 8, nx = 0, ny = 1, nz = 0, id = 2, meta = 0, face = 3 }
  T.eq(g:placeFromHand(fake), false)
end)

suite:test("oswietlenie: pochodnia i cien", function()
  local w = World.new({ lighting = lighting })
  for cz = -1, 1 do
    for cx = -1, 1 do
      local c = Chunk.new(cx, cz)
      for z = 0, 15 do for x = 0, 15 do c:setRaw(x, 10, z, 1) end end
      c:recalcHeights()
      c.generated = true
      w:addChunk(c)
    end
  end
  for _, c in pairs(w.chunks) do w:lightChunk(c) end
  T.eq(w:getSkyLight(5, 11, 5), 15)
  T.eq(w:getSkyLight(5, 9, 5), 0, "pod kamieniem ciemno")
  -- dach nad głową: cień, potem światło z boku
  w:setBlock(5, 14, 5, 1)
  T.eq(w:getSkyLight(5, 13, 5), 14, "pod pojedynczym blokiem swiatlo z boku")
  w:setBlock(5, 11, 5, 50, 0)
  T.eq(w:getBlockLight(5, 11, 5), 14)
  T.eq(w:getBlockLight(8, 11, 5), 11)
  w:setBlock(5, 11, 5, 0, 0)
  T.eq(w:getBlockLight(8, 11, 5), 0, "po zgaszeniu")
  w:setBlock(5, 14, 5, 0)
  T.eq(w:getSkyLight(5, 13, 5), 15)
end)

suite:test("zapis: chunk i serializacja", function()
  local c = Chunk.new(3, -2)
  for i = 0, 2000 do c.blocks[i] = (i % 7 == 0) and 4 or 1 end
  c.meta[100] = 5
  c.tiles[17] = { kind = "chest", inventory = Inventory.new(27) }
  c.tiles[17].inventory:set(3, { id = 264, count = 7 })
  local data = save.encodeChunk(c)
  local c2 = save.decodeChunk(3, -2, data)
  for i = 0, 2100 do T.eq(c2.blocks[i], c.blocks[i]) end
  T.eq(c2.meta[100], 5)
  T.eq(c2.tiles[17].inventory.slots[3].count, 7)
  local t = { a = 1, b = { 1, 2, "x" }, c = true, d = 1.5 }
  local back = serialize.decode(serialize.encode(t))
  T.eq(back.a, 1); T.eq(back.b[3], "x"); T.eq(back.c, true); T.eq(back.d, 1.5)
  T.eq(serialize.decode("os.exit()"), nil, "obcy kod nie dziala")
end)

suite:test("moby: spawn, atak i drop", function()
  local g = flatGame()
  local mobs = require("core.mobs")
  local pig = mobs.spawn(g, "pig", 10.5, 64, 8.5)
  for _ = 1, 10 do g:tick() end
  T.truthy(pig.onGround, "swinia na ziemi")
  for _ = 1, 3 do
    pig.invulnerable = 0
    mobs.damageMob(g, pig, 5, "player", g.player)
  end
  pig.lastHitByPlayer = 100
  for _ = 1, 30 do g:tick() end
  T.truthy(pig.dead, "martwa")
  local drops = 0
  for _, e in ipairs(g.entities.list) do if e.type == "item" then drops = drops + 1 end end
  T.truthy(drops > 0, "zostawila schab")
end)

suite:test("ciecze: woda rozlewa sie i znika", function()
  local g = flatGame()
  g:setBlock(8, 64, 8, 8, 0)
  g:scheduleTick(8, 64, 8, 1)
  for _ = 1, 80 do g:tick() end
  T.eq(g.world:getBlock(9, 64, 8), 8, "rozlala sie")
  T.truthy(g.world:getMeta(12, 64, 8) > 0 or g.world:getBlock(12, 64, 8) == 8, "daleko")
  g:setBlock(8, 64, 8, 0, 0)
  for _ = 1, 200 do g:tick() end
  T.eq(g.world:getBlock(9, 64, 8), 0, "wyschla")
end)

return suite
