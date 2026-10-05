-- tests/test_magic.lua
-- Zaklinanie i mikstury.
local T = require("tests.testlib")
local Game = require("core.game")
local enchant = require("core.enchant")
local potions = require("core.potions")
local items = require("core.items")
local Rng = require("core.rng")
local Inventory = require("core.inventory")
local mobs = require("core.mobs")

local suite = T.suite("magia")

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

suite:test("zaklinanie: oferty, losowanie i koszt w poziomach", function()
  local rng = Rng.new(5)
  local offers = enchant.offerLevels(rng, 15)
  T.truthy(offers[3] >= 30, "15 biblioteczek daje oferte 30")
  local found = false
  for _ = 1, 50 do
    local e = enchant.select(rng, { id = 276, count = 1, damage = 0 }, 30)
    T.truthy(e and next(e), "miecz zawsze dostaje zaklecie")
    for id in pairs(e) do
      local d = enchant.BY_ID[id]
      T.truthy(d.target == "weapon" or d.target == "durable", "zaklecie pasuje do miecza")
    end
    if e[16] or e[17] or e[18] then found = true end
  end
  T.truthy(found, "trafia sie ostrosc/pogromca")
  local g = flatGame()
  g.player.gameMode = "survival"
  g.xpLevel = 31
  local st = { id = 278, count = 1, damage = 0 }
  T.truthy(enchant.apply(g, st, 30), "zaklety kilof")
  T.eq(g.xpLevel, 1, "zabrano 30 poziomow")
  T.truthy(st.ench, "ma zaklecia")
  T.eq(enchant.canEnchant(st), false, "drugi raz nie mozna")
  T.eq(enchant.canEnchant({ id = 4, count = 1 }), false, "bruku nie zaklniesz")
end)

suite:test("zaklinanie: efekty (wydajnosc, jedwabny dotyk, ochrona, niezniszczalnosc)", function()
  local def = require("core.blocks").defs[1]
  local plain = items.breakStrength({ id = 278, count = 1 }, def, true, false)
  local fast = items.breakStrength({ id = 278, count = 1, ench = { [32] = 5 } }, def, true, false)
  T.truthy(fast > plain * 3, "wydajnosc V przyspiesza kopanie")

  local g = flatGame()
  g.player.gameMode = "survival"
  g.world:setBlock(5, 63, 5, 56, 0)
  g.inventory:set(1, { id = 278, count = 1, damage = 0, ench = { [33] = 1 } })
  g.selected = 1
  g:breakBlock(5, 63, 5, true)
  local ore = false
  for _, e in ipairs(g.entities.list) do
    if e.type == "item" and e.stack.id == 56 then ore = true end
  end
  T.truthy(ore, "jedwabny dotyk daje rude diamentu")

  local armor = Inventory.new(4)
  armor.slots[2] = { id = 311, count = 1, damage = 0, ench = { [0] = 4 } }
  T.truthy(enchant.protectionFactor(armor, "mob", 1) > 0.1, "ochrona IV zmniejsza obrazenia")
  armor.slots[4] = { id = 313, count = 1, damage = 0, ench = { [2] = 4 } }
  T.truthy(enchant.protectionFactor(armor, "fall", 1) > enchant.protectionFactor(armor, "mob", 1),
    "powolne opadanie dziala na upadek")

  local inv = Inventory.new(1)
  inv.slots[1] = { id = 278, count = 1, damage = 0, ench = { [34] = 3 } }
  for _ = 1, 400 do inv:damageItem(1, 1) end
  T.truthy(inv.slots[1].damage < 250, "niezniszczalnosc III zuzywa ok. 4x wolniej")
end)

suite:test("zaklinanie: zapis zaklec w ekwipunku", function()
  local inv = Inventory.new(3)
  inv.slots[2] = { id = 276, count = 1, damage = 5, ench = { [16] = 3, [20] = 1 } }
  local inv2 = Inventory.new(3)
  inv2:deserialize(inv:serialize())
  T.eq(inv2.slots[2].ench[16], 3)
  T.eq(inv2.slots[2].ench[20], 1)
  T.eq(items.canMerge({ id = 276, count = 1, ench = { [16] = 1 } }, { id = 276, count = 1 }), false)
end)

suite:test("mikstury: receptury warzenia", function()
  T.eq(potions.brewResult(0, 372), 1, "woda + brodawka = dziwna")
  T.eq(potions.brewResult(1, 382), 13, "dziwna + arbuz = leczenie")
  T.eq(potions.brewResult(13, 348), 213, "leczenie + jasnoglaz = leczenie II")
  T.eq(potions.brewResult(11, 331), 111, "szybkosc + redstone = przedluzona")
  T.eq(potions.brewResult(13, 376), 18, "leczenie + fermentowane oko = krzywda")
  T.eq(potions.brewResult(213, 289), 1213, "proch = rzucana")
  T.eq(potions.brewResult(0, 382), nil, "woda + arbuz = nic")
  T.eq(potions.label(1213), "Rzucana mikstura leczenia II")
end)

suite:test("mikstury: statyw warzy w 20 sekund", function()
  local g = flatGame()
  g.world:setBlock(3, 64, 3, 117, 0)
  local tile = g:getOrCreateTile(3, 64, 3)
  tile.inventory.slots[1] = { id = 373, count = 1, damage = 0 }
  tile.inventory.slots[2] = { id = 373, count = 1, damage = 0 }
  tile.inventory.slots[4] = { id = 372, count = 2, damage = 0 }
  for _ = 1, 401 do g:tickTiles() end
  T.eq(tile.inventory.slots[1].damage, 1, "dziwna mikstura")
  T.eq(tile.inventory.slots[2].damage, 1)
  T.eq(tile.inventory.slots[4].count, 1, "zuzyto jedna brodawke")
end)

suite:test("mikstury: picie i efekty", function()
  local g = flatGame()
  g.player.gameMode = "survival"
  g.health = 10
  g.inventory:set(1, { id = 373, count = 1, damage = 13 })
  g.selected = 1
  potions.drink(g, 1)
  T.eq(g.health, 14, "leczenie +4")
  T.eq(g.inventory.slots[1].id, 374, "zostaje butelka")
  potions.applyToPlayer(g, 12, 1)
  T.truthy(g.effects.fire_resistance, "odpornosc na ogien")
  T.eq(g.survival.damage(g, 4, "lava"), false, "lawa nie rani")
  potions.applyToPlayer(g, 11, 1)
  g.survival.tick(g)
  T.truthy(g.player.speedMul > 1.1, "szybkosc przyspiesza")
  potions.applyToPlayer(g, 14, 1)
  T.eq(mobs.effectAttackBonus(g), 3, "sila +3")
end)

suite:test("mikstury: rzucana krzywda rani moba, leczy zombie", function()
  local g = flatGame()
  local pig = mobs.spawn(g, "pig", 10.5, 64, 10.5)
  local z = mobs.spawn(g, "zombie", 11.5, 64, 10.5)
  z.health = 10
  potions.splash(g, { x = 10.5, y = 64.5, z = 10.5, potion = 18 })
  T.truthy(pig.health < 10, "swinia oberwala")
  T.truthy(z.health > 10, "zombie sie wyleczyl")
end)

return suite
