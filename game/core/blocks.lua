-- core/blocks.lua
-- Rejestr bloków: same DANE (wygląd, twardość, narzędzie, światło, drop...).
-- Zachowania (rośnięcie, płynięcie, otwieranie drzwi) są w core/blocklogic.lua.
-- Numery ID jak w Minecraft Beta, żeby łatwiej było porównywać z wiki.

local tiles = require("core.tiles")

local B = {}

B.defs = {}   -- id -> definicja
B.ids = {}    -- nazwa -> id

-- Indeksy ścian (używane w mesherze, raycaście i przy obracaniu bloków)
B.FACE_EAST, B.FACE_WEST = 1, 2     -- +X, -X
B.FACE_TOP, B.FACE_BOTTOM = 3, 4    -- +Y, -Y
B.FACE_SOUTH, B.FACE_NORTH = 5, 6   -- +Z, -Z

-- Kierunek "przodu" bloku w meta (piec, skrzynia, dynia): 0=S, 1=W, 2=N, 3=E
B.FACING_TO_FACE = { [0] = 5, [1] = 2, [2] = 6, [3] = 1 }

-- Wartości domyślne dla każdej definicji
local DEFAULTS = {
  solid = true,        -- czy ma kolizję
  opaque = true,       -- pełny, nieprzezroczysty sześcian (zasłania ściany, AO)
  shape = "cube",      -- cube | box | cross | liquid | none
  hardness = 1,        -- czas kopania (jak w MC), -1 = niezniszczalny
  resistance = 1,      -- odporność na wybuchy
  light = 0,           -- emitowane światło 0..15
  replaceable = false, -- można postawić blok "w miejsce" tego bloku (trawa, woda)
  selectable = true,   -- czy celownik może go zaznaczyć
  stack = 64,          -- maksymalny stos jako przedmiot
  cullSame = false,    -- nie rysuj ścian między dwoma takimi samymi blokami
  metaMask = 0,        -- które bity meta przechodzą na przedmiot (np. kolor wełny)
}

local function resolveTex(tex)
  -- tex: "nazwa" albo { top=, bottom=, side=, east=, ... }
  local faces = {}
  if type(tex) == "string" then
    local t = tiles.get(tex)
    for f = 1, 6 do faces[f] = t end
  elseif type(tex) == "table" then
    local side = tex.side and tiles.get(tex.side)
    local top = tex.top and tiles.get(tex.top) or side
    local bottom = tex.bottom and tiles.get(tex.bottom) or top
    faces[1], faces[2], faces[5], faces[6] = side, side, side, side
    faces[3], faces[4] = top, bottom
  else
    local t = tiles.get("white")
    for f = 1, 6 do faces[f] = t end
  end
  return faces
end

function B.define(def)
  assert(def.id and def.name, "blok musi miec id i name")
  for k, v in pairs(DEFAULTS) do
    if def[k] == nil then def[k] = v end
  end
  if def.opacity == nil then
    def.opacity = def.opaque and 15 or 0
  end
  if def.layer == nil then
    def.layer = def.opaque and "opaque" or "cutout"
  end
  def.label = def.label or def.name
  def.faceTiles = resolveTex(def.tex)
  def.isBlock = true
  B.defs[def.id] = def
  B.ids[def.name] = def.id
  return def
end

function B.get(id)
  return B.defs[id]
end

function B.id(name)
  local id = B.ids[name]
  if not id then error("Nieznany blok: " .. tostring(name), 2) end
  return id
end

-- Kafelek tekstury dla ściany (uwzględnia meta, np. stopień wzrostu pszenicy)
function B.faceTile(def, face, meta)
  if def.texFn then
    return def.texFn(face, meta, def)
  end
  return def.faceTiles[face]
end

-- Prostopadłościan bloku (kolizja / zaznaczenie / render "box").
-- Zwraca x0, y0, z0, x1, y1, z1 w zakresie 0..1.
function B.bounds(def, meta)
  if def.bounds then
    return def.bounds(meta)
  end
  return 0, 0, 0, 1, 1, 1
end

-- ---------------------------------------------------------------------------
-- Pomocnicze kształty
-- ---------------------------------------------------------------------------
local P = 1 / 16

local function box(x0, y0, z0, x1, y1, z1)
  return function() return x0, y0, z0, x1, y1, z1 end
end

-- Pochodnia: meta 0 = na podłodze, 1..4 = na ścianie (podpora z -X, +X, -Z, +Z)
local function torchBounds(meta)
  local w = P * 1
  if meta == 1 then return 0, 3 * P, 0.5 - w, 3 * P, 13 * P, 0.5 + w end
  if meta == 2 then return 1 - 3 * P, 3 * P, 0.5 - w, 1, 13 * P, 0.5 + w end
  if meta == 3 then return 0.5 - w, 3 * P, 0, 0.5 + w, 13 * P, 3 * P end
  if meta == 4 then return 0.5 - w, 3 * P, 1 - 3 * P, 0.5 + w, 13 * P, 1 end
  return 0.5 - w, 0, 0.5 - w, 0.5 + w, 10 * P, 0.5 + w
end
B.torchBounds = torchBounds

-- Cienki panel przy jednej ze ścian bloku: side 0=-Z, 1=+X, 2=+Z, 3=-X
local function panel(side, t)
  if side == 0 then return 0, 0, 0, 1, 1, t end
  if side == 1 then return 1 - t, 0, 0, 1, 1, 1 end
  if side == 2 then return 0, 0, 1 - t, 1, 1, 1 end
  return 0, 0, 0, t, 1, 1
end

-- Drzwi: bity meta: 0-1 kierunek, 4 = otwarte, 8 = górna połowa
local function doorBounds(meta)
  local facing = meta % 4
  local open = math.floor(meta / 4) % 2 == 1
  local side = open and (facing + 1) % 4 or facing
  return panel(side, 3 * P)
end

-- Drabina: meta 1..4 jak przy pochodni (strona podpory)
local LADDER_SIDE = { [1] = 3, [2] = 1, [3] = 0, [4] = 2 }
local function ladderBounds(meta)
  return panel(LADDER_SIDE[meta] or 0, P)
end

-- Tekstura z "przodem" w kierunku meta (piec, skrzynia, dynia)
local function facingTex(front, side, top, bottom)
  local tFront, tSide = tiles.get(front), tiles.get(side)
  local tTop, tBottom = tiles.get(top), tiles.get(bottom or top)
  return function(face, meta)
    if face == 3 then return tTop end
    if face == 4 then return tBottom end
    if face == B.FACING_TO_FACE[meta % 4] then return tFront end
    return tSide
  end
end

-- Drop "zawsze ten przedmiot"
local function dropItem(id, minCount, maxCount, damage)
  return function(_, rng)
    local n = minCount
    if maxCount and maxCount > minCount then n = rng:int(minCount, maxCount) end
    if n <= 0 then return nil end
    return { { id = id, count = n, damage = damage or 0 } }
  end
end
local function dropNothing() return nil end

-- ---------------------------------------------------------------------------
-- Definicje bloków
-- ---------------------------------------------------------------------------
B.define { id = 0, name = "air", label = "Powietrze", solid = false, opaque = false,
  shape = "none", selectable = false, replaceable = true, hardness = 0, resistance = 0 }

B.define { id = 1, name = "stone", label = "Kamien", tex = "stone", hardness = 1.5,
  resistance = 6, tool = "pickaxe", tier = 0, drops = dropItem(4, 1) }

B.define { id = 2, name = "grass", label = "Trawa", hardness = 0.6, resistance = 0.6,
  tool = "shovel", drops = dropItem(3, 1),
  texFn = (function()
    local top, bottom = tiles.get("grass_top"), tiles.get("dirt")
    local side, snowSide = tiles.get("grass_side"), tiles.get("grass_side_snow")
    return function(face, meta)
      if face == 3 then return top end
      if face == 4 then return bottom end
      if meta == 1 then return snowSide end -- meta 1 = śnieg na wierzchu
      return side
    end
  end)() }

B.define { id = 3, name = "dirt", label = "Ziemia", tex = "dirt", hardness = 0.5,
  resistance = 0.5, tool = "shovel" }

B.define { id = 4, name = "cobblestone", label = "Bruk", tex = "cobblestone", hardness = 2,
  resistance = 6, tool = "pickaxe", tier = 0 }

B.define { id = 5, name = "planks", label = "Deski", tex = "planks", hardness = 2,
  resistance = 3, tool = "axe", flammable = true }

B.define { id = 6, name = "sapling", label = "Sadzonka", tex = "sapling", solid = false,
  opaque = false, shape = "cross", hardness = 0, resistance = 0, metaMask = 3,
  flammable = true }

B.define { id = 7, name = "bedrock", label = "Skala macierzysta", tex = "bedrock",
  hardness = -1, resistance = 3600000 }

B.define { id = 8, name = "water", label = "Woda", tex = "water", solid = false,
  opaque = false, shape = "liquid", layer = "translucent", opacity = 3, hardness = 100,
  resistance = 100, selectable = false, replaceable = true, liquid = "water",
  cullSame = true, drops = dropNothing }

B.define { id = 10, name = "lava", label = "Lawa", tex = "lava", solid = false,
  opaque = false, shape = "liquid", layer = "opaque", opacity = 15, light = 15,
  hardness = 100, resistance = 100, selectable = false, replaceable = true,
  liquid = "lava", cullSame = true, drops = dropNothing }

B.define { id = 12, name = "sand", label = "Piasek", tex = "sand", hardness = 0.5,
  resistance = 0.5, tool = "shovel", gravity = true }

B.define { id = 13, name = "gravel", label = "Zwir", tex = "gravel", hardness = 0.6,
  resistance = 0.6, tool = "shovel", gravity = true,
  drops = function(_, rng)
    if rng:chance(0.1) then return { { id = 318, count = 1, damage = 0 } } end
    return { { id = 13, count = 1, damage = 0 } }
  end }

B.define { id = 14, name = "gold_ore", label = "Ruda zlota", tex = "gold_ore",
  hardness = 3, resistance = 3, tool = "pickaxe", tier = 2 }
B.define { id = 15, name = "iron_ore", label = "Ruda zelaza", tex = "iron_ore",
  hardness = 3, resistance = 3, tool = "pickaxe", tier = 1 }
B.define { id = 16, name = "coal_ore", label = "Ruda wegla", tex = "coal_ore",
  hardness = 3, resistance = 3, tool = "pickaxe", tier = 0, drops = dropItem(263, 1),
  xp = { 0, 2 } }

-- Pień: meta 0 = dąb, 1 = świerk, 2 = brzoza
B.define { id = 17, name = "log", label = "Drewno", hardness = 2, resistance = 2,
  tool = "axe", metaMask = 3, flammable = true,
  texFn = (function()
    local top = tiles.get("log_top")
    local sides = { [0] = tiles.get("log_side"), tiles.get("log_pine_side"),
      tiles.get("log_birch_side") }
    return function(face, meta)
      if face == 3 or face == 4 then return top end
      return sides[meta % 4] or sides[0]
    end
  end)() }

-- Liście: bity 0-1 = gatunek, bit 4 = postawione przez gracza (nie opadają)
B.define { id = 18, name = "leaves", label = "Liscie", solid = true, opaque = false,
  opacity = 1, hardness = 0.2, resistance = 0.2, tool = "shears", metaMask = 3,
  flammable = true,
  texFn = (function()
    local t = { [0] = tiles.get("leaves"), tiles.get("leaves_pine"), tiles.get("leaves_birch") }
    return function(_, meta) return t[meta % 4] or t[0] end
  end)(),
  drops = function(meta, rng)
    local out = {}
    if rng:chance(1 / 20) then out[#out + 1] = { id = 6, count = 1, damage = meta % 4 } end
    if meta % 4 == 0 and rng:chance(1 / 200) then
      out[#out + 1] = { id = 260, count = 1, damage = 0 }
    end
    return out
  end }

B.define { id = 20, name = "glass", label = "Szklo", tex = "glass", opaque = false,
  hardness = 0.3, resistance = 0.3, cullSame = true, drops = dropNothing }

B.define { id = 21, name = "lapis_ore", label = "Ruda lapis", tex = "lapis_ore", hardness = 3,
  resistance = 3, tool = "pickaxe", tier = 1, drops = dropItem(351, 4, 8, 4), xp = { 2, 5 } }
B.define { id = 22, name = "lapis_block", label = "Blok lapis", tex = "lapis_block",
  hardness = 3, resistance = 3, tool = "pickaxe", tier = 1 }

B.define { id = 24, name = "sandstone", label = "Piaskowiec", hardness = 0.8,
  resistance = 0.8, tool = "pickaxe", tier = 0,
  tex = { top = "sandstone_top", side = "sandstone_side", bottom = "sandstone_bottom" } }

-- Łóżko: meta 0-3 = kierunek (od nóg do wezgłowia), bit 8 = wezgłowie
B.define { id = 26, name = "bed", label = "Lozko", opaque = false, shape = "box",
  bounds = box(0, 0, 0, 1, 9 * P, 1), hardness = 0.2, resistance = 0.2,
  drops = function(meta)
    if meta >= 8 then return nil end -- drop tylko z jednej połowy
    return { { id = 355, count = 1, damage = 0 } }
  end,
  texFn = (function()
    local topFoot, topHead = tiles.get("bed_top_foot"), tiles.get("bed_top_head")
    local sideFoot, sideHead = tiles.get("bed_side_foot"), tiles.get("bed_side_head")
    local bottom = tiles.get("planks")
    return function(face, meta)
      local head = meta >= 8
      if face == 3 then return head and topHead or topFoot end
      if face == 4 then return bottom end
      return head and sideHead or sideFoot
    end
  end)() }

B.define { id = 30, name = "cobweb", label = "Pajeczyna", tex = "cobweb", solid = false,
  opaque = false, shape = "cross", hardness = 4, resistance = 4, tool = "sword",
  drops = dropItem(287, 1) }

B.define { id = 31, name = "tall_grass", label = "Wysoka trawa", tex = "tall_grass",
  solid = false, opaque = false, shape = "cross", hardness = 0, resistance = 0,
  replaceable = true, flammable = true,
  drops = function(_, rng)
    if rng:chance(1 / 8) then return { { id = 295, count = 1, damage = 0 } } end
    return nil
  end }

B.define { id = 32, name = "dead_bush", label = "Martwy krzak", tex = "dead_bush",
  solid = false, opaque = false, shape = "cross", hardness = 0, resistance = 0,
  replaceable = true, drops = dropNothing }

-- Wełna: meta = kolor
B.define { id = 35, name = "wool", label = "Welna", hardness = 0.8, resistance = 0.8,
  metaMask = 7, flammable = true,
  texFn = (function()
    local t = { [0] = tiles.get("wool"), tiles.get("wool_red"), tiles.get("wool_yellow"),
      tiles.get("wool_green"), tiles.get("wool_blue"), tiles.get("wool_black") }
    return function(_, meta) return t[meta % 8] or t[0] end
  end)() }

B.define { id = 37, name = "dandelion", label = "Mniszek", tex = "dandelion", solid = false,
  opaque = false, shape = "cross", hardness = 0, resistance = 0 }
B.define { id = 38, name = "rose", label = "Roza", tex = "rose", solid = false,
  opaque = false, shape = "cross", hardness = 0, resistance = 0 }
B.define { id = 39, name = "brown_mushroom", label = "Brazowy grzyb", tex = "mushroom_brown",
  solid = false, opaque = false, shape = "cross", hardness = 0, resistance = 0, light = 1 }
B.define { id = 40, name = "red_mushroom", label = "Czerwony grzyb", tex = "mushroom_red",
  solid = false, opaque = false, shape = "cross", hardness = 0, resistance = 0 }

B.define { id = 41, name = "gold_block", label = "Blok zlota", tex = "gold_block",
  hardness = 3, resistance = 6, tool = "pickaxe", tier = 2 }
B.define { id = 42, name = "iron_block", label = "Blok zelaza", tex = "iron_block",
  hardness = 5, resistance = 6, tool = "pickaxe", tier = 1 }

B.define { id = 44, name = "slab", label = "Plyta kamienna", opaque = false, shape = "box",
  layer = "opaque", opacity = 15, bounds = box(0, 0, 0, 1, 0.5, 1), hardness = 2,
  resistance = 6, tool = "pickaxe", tier = 0, tex = { top = "slab_top", side = "slab_side" } }

B.define { id = 45, name = "bricks", label = "Cegly", tex = "bricks", hardness = 2,
  resistance = 6, tool = "pickaxe", tier = 0 }

B.define { id = 46, name = "tnt", label = "TNT", hardness = 0, resistance = 0,
  tex = { top = "tnt_top", side = "tnt_side", bottom = "tnt_bottom" }, flammable = true }

B.define { id = 47, name = "bookshelf", label = "Biblioteczka", hardness = 1.5,
  resistance = 1.5, tool = "axe", tex = { side = "bookshelf", top = "planks" },
  drops = dropItem(340, 3), flammable = true }

B.define { id = 48, name = "mossy_cobblestone", label = "Zamszony bruk",
  tex = "mossy_cobblestone", hardness = 2, resistance = 6, tool = "pickaxe", tier = 0 }

B.define { id = 49, name = "obsidian", label = "Obsydian", tex = "obsidian", hardness = 50,
  resistance = 1200, tool = "pickaxe", tier = 3 }

B.define { id = 50, name = "torch", label = "Pochodnia", tex = "torch", solid = false,
  opaque = false, shape = "box", bounds = torchBounds, light = 14, hardness = 0,
  resistance = 0, icon = "flat" }

B.define { id = 51, name = "fire", label = "Ogien", tex = "fire", solid = false,
  opaque = false, shape = "cross", light = 15, hardness = 0, resistance = 0,
  selectable = false, replaceable = true, drops = dropNothing }

B.define { id = 52, name = "spawner", label = "Spawner", tex = "spawner", opaque = false,
  hardness = 5, resistance = 25, tool = "pickaxe", tier = 0, drops = dropNothing }

B.define { id = 54, name = "chest", label = "Skrzynia", opaque = false, shape = "box",
  bounds = box(P, 0, P, 15 * P, 14 * P, 15 * P), hardness = 2.5, resistance = 2.5,
  tool = "axe", texFn = facingTex("chest_front", "chest_side", "chest_top"),
  tileEntity = "chest", flammable = true }

B.define { id = 56, name = "diamond_ore", label = "Ruda diamentu", tex = "diamond_ore",
  hardness = 3, resistance = 3, tool = "pickaxe", tier = 2, drops = dropItem(264, 1),
  xp = { 3, 7 } }
B.define { id = 57, name = "diamond_block", label = "Blok diamentu", tex = "diamond_block",
  hardness = 5, resistance = 6, tool = "pickaxe", tier = 2 }

B.define { id = 58, name = "crafting_table", label = "Stol rzemieslniczy", hardness = 2.5,
  resistance = 2.5, tool = "axe", flammable = true,
  texFn = (function()
    local top, side = tiles.get("crafting_table_top"), tiles.get("crafting_table_side")
    local front, bottom = tiles.get("crafting_table_front"), tiles.get("planks")
    return function(face)
      if face == 3 then return top end
      if face == 4 then return bottom end
      if face == 5 or face == 1 then return front end
      return side
    end
  end)() }

-- Pszenica: meta 0..7 = etap wzrostu
B.define { id = 59, name = "wheat", label = "Pszenica", solid = false, opaque = false,
  shape = "cross", hardness = 0, resistance = 0,
  texFn = (function()
    local t = {}
    for i = 0, 7 do t[i] = tiles.get("wheat_" .. i) end
    return function(_, meta) return t[meta % 8] end
  end)(),
  drops = function(meta, rng)
    local out = {}
    if meta >= 7 then out[#out + 1] = { id = 296, count = 1, damage = 0 } end
    local seeds = meta >= 7 and rng:int(1, 3) or 1
    out[#out + 1] = { id = 295, count = seeds, damage = 0 }
    return out
  end }

-- Pole uprawne: meta > 0 = nawodnione
B.define { id = 60, name = "farmland", label = "Pole uprawne", opaque = false,
  opacity = 15, layer = "opaque", shape = "box", bounds = box(0, 0, 0, 1, 15 * P, 1),
  hardness = 0.6, resistance = 0.6, tool = "shovel", drops = dropItem(3, 1),
  texFn = (function()
    local dry, wet, dirt = tiles.get("farmland_dry"), tiles.get("farmland_wet"), tiles.get("dirt")
    return function(face, meta)
      if face == 3 then return meta > 0 and wet or dry end
      return dirt
    end
  end)() }

B.define { id = 61, name = "furnace", label = "Piec", hardness = 3.5, resistance = 3.5,
  tool = "pickaxe", tier = 0, tileEntity = "furnace",
  texFn = facingTex("furnace_front", "furnace_side", "furnace_top") }
B.define { id = 62, name = "lit_furnace", label = "Piec (pali sie)", hardness = 3.5,
  resistance = 3.5, tool = "pickaxe", tier = 0, light = 13, tileEntity = "furnace",
  drops = dropItem(61, 1),
  texFn = facingTex("furnace_front_lit", "furnace_side", "furnace_top") }

B.define { id = 64, name = "door", label = "Drzwi", opaque = false, shape = "box",
  bounds = doorBounds, hardness = 3, resistance = 3, tool = "axe",
  drops = function(meta)
    if meta >= 8 then return nil end
    return { { id = 324, count = 1, damage = 0 } }
  end,
  texFn = (function()
    local bottom, top = tiles.get("door_bottom"), tiles.get("door_top")
    return function(_, meta) return meta >= 8 and top or bottom end
  end)() }
B.doorBounds = doorBounds

B.define { id = 65, name = "ladder", label = "Drabina", tex = "ladder", solid = false,
  opaque = false, shape = "box", bounds = ladderBounds, hardness = 0.4, resistance = 0.4,
  tool = "axe", climbable = true, icon = "flat" }

B.define { id = 73, name = "redstone_ore", label = "Ruda czerwonego kamienia",
  tex = "redstone_ore", hardness = 3, resistance = 3, tool = "pickaxe", tier = 2,
  drops = dropItem(331, 4, 5), xp = { 1, 5 } }

B.define { id = 78, name = "snow_layer", label = "Warstwa sniegu", tex = "snow",
  solid = false, opaque = false, shape = "box", bounds = box(0, 0, 0, 1, 2 * P, 1),
  hardness = 0.1, resistance = 0.1, tool = "shovel", replaceable = true,
  drops = dropItem(332, 1) }

B.define { id = 79, name = "ice", label = "Lod", tex = "ice", opaque = false,
  layer = "translucent", opacity = 3, hardness = 0.5, resistance = 0.5, cullSame = true,
  slippery = true, drops = dropNothing }

B.define { id = 80, name = "snow", label = "Snieg", tex = "snow", hardness = 0.2,
  resistance = 0.2, tool = "shovel", drops = dropItem(332, 4) }

B.define { id = 81, name = "cactus", label = "Kaktus", opaque = false, shape = "box",
  bounds = box(P, 0, P, 15 * P, 1, 15 * P), hardness = 0.4, resistance = 0.4,
  tex = { side = "cactus_side", top = "cactus_top", bottom = "cactus_bottom" } }

B.define { id = 82, name = "clay", label = "Glina", tex = "clay", hardness = 0.6,
  resistance = 0.6, tool = "shovel", drops = dropItem(337, 4) }

B.define { id = 83, name = "sugar_cane", label = "Trzcina cukrowa", tex = "sugar_cane",
  solid = false, opaque = false, shape = "cross", hardness = 0, resistance = 0,
  drops = dropItem(338, 1) }

B.define { id = 86, name = "pumpkin", label = "Dynia", hardness = 1, resistance = 1,
  tool = "axe", texFn = facingTex("pumpkin_face", "pumpkin_side", "pumpkin_top") }

B.define { id = 89, name = "glowstone", label = "Jasnoglaz", tex = "glowstone",
  hardness = 0.3, resistance = 0.3, light = 15, opaque = true, drops = dropItem(348, 2, 4) }

B.define { id = 91, name = "jack_o_lantern", label = "Lampion z dyni", hardness = 1,
  resistance = 1, tool = "axe", light = 15,
  texFn = facingTex("jack_o_lantern_face", "pumpkin_side", "pumpkin_top") }

B.define { id = 98, name = "stone_bricks", label = "Kamienne cegly", tex = "stone_bricks",
  hardness = 1.5, resistance = 6, tool = "pickaxe", tier = 0 }

B.define { id = 103, name = "melon", label = "Arbuz", hardness = 1, resistance = 1,
  tool = "axe", tex = { side = "melon_side", top = "melon_top" },
  drops = dropItem(360, 3, 7) }

-- ---------------------------------------------------------------------------
-- Redstone i tłoki
-- ---------------------------------------------------------------------------
-- Wektory "przodu" przekaźnika (0=S, 1=W, 2=N, 3=E) i tłoka (0=dół, 1=góra, 2=N, 3=S, 4=W, 5=E)
B.FACING4 = { [0] = { 0, 0, 1 }, [1] = { -1, 0, 0 }, [2] = { 0, 0, -1 }, [3] = { 1, 0, 0 } }
B.FACING6 = { [0] = { 0, -1, 0 }, [1] = { 0, 1, 0 }, [2] = { 0, 0, -1 }, [3] = { 0, 0, 1 },
  [4] = { -1, 0, 0 }, [5] = { 1, 0, 0 } }
local FACING6_TO_FACE = { [0] = 4, [1] = 3, [2] = 6, [3] = 5, [4] = 2, [5] = 1 }
local OPPOSITE_FACE = { 2, 1, 4, 3, 6, 5 }
-- strona podpory (jak pochodnia): 0 = podłoga, 1 = -X, 2 = +X, 3 = -Z, 4 = +Z
B.SUPPORT = { [0] = { 0, -1, 0 }, [1] = { -1, 0, 0 }, [2] = { 1, 0, 0 }, [3] = { 0, 0, -1 },
  [4] = { 0, 0, 1 } }

B.define { id = 55, name = "redstone_wire", label = "Czerwony pyl", solid = false, opaque = false,
  shape = "box", bounds = box(0, 0, 0, 1, P, 1), hardness = 0, resistance = 0,
  drops = dropItem(331, 1), redstone = "wire",
  texFn = (function()
    local off, on = tiles.get("redstone_dust"), tiles.get("redstone_dust_on")
    return function(_, meta) return meta > 0 and on or off end
  end)() }

B.define { id = 75, name = "redstone_torch_off", label = "Pochodnia z czerwonego pylu",
  tex = "redstone_torch_off", solid = false, opaque = false, shape = "box", bounds = torchBounds,
  hardness = 0, resistance = 0, drops = dropItem(76, 1), redstone = "torch", icon = "flat" }
B.define { id = 76, name = "redstone_torch", label = "Pochodnia z czerwonego pylu",
  tex = "redstone_torch", solid = false, opaque = false, shape = "box", bounds = torchBounds,
  light = 7, hardness = 0, resistance = 0, redstone = "torch", icon = "flat" }

-- Dźwignia: meta 0-4 = podpora (jak pochodnia), bit 8 = włączona
local function leverBoxes(meta)
  local side = meta % 8
  local on = meta >= 8
  local t = tiles.get("cobblestone")
  local h = tiles.get("lever")
  if side == 0 then
    return { { 5 * P, 0, 4 * P, 11 * P, 3 * P, 12 * P, tile = t },
      { 7 * P, 3 * P, (on and 4 or 9) * P, 9 * P, 10 * P, (on and 7 or 12) * P, tile = h } }
  end
  local v = B.SUPPORT[side]
  -- płytka przy ścianie + rączka do góry albo w dół
  local x0, x1 = 5 * P, 11 * P
  local z0, z1 = 5 * P, 11 * P
  if v[1] ~= 0 then x0, x1 = v[1] < 0 and 0 or 13 * P, v[1] < 0 and 3 * P or 1 end
  if v[3] ~= 0 then z0, z1 = v[3] < 0 and 0 or 13 * P, v[3] < 0 and 3 * P or 1 end
  local base = { x0, 4 * P, z0, x1, 12 * P, z1, tile = t }
  local hx0, hx1, hz0, hz1 = 7 * P, 9 * P, 7 * P, 9 * P
  if v[1] ~= 0 then hx0, hx1 = v[1] < 0 and 3 * P or 7 * P, v[1] < 0 and 9 * P or 13 * P end
  if v[3] ~= 0 then hz0, hz1 = v[3] < 0 and 3 * P or 7 * P, v[3] < 0 and 9 * P or 13 * P end
  local hy0, hy1 = on and 9 * P or 3 * P, on and 13 * P or 7 * P
  return { base, { hx0, hy0, hz0, hx1, hy1, hz1, tile = h } }
end
B.define { id = 69, name = "lever", label = "Dzwignia", tex = "lever", solid = false, opaque = false,
  shape = "box", boxes = leverBoxes, hardness = 0.5, resistance = 0.5, redstone = "lever",
  icon = "flat",
  bounds = function(meta)
    local list = leverBoxes(meta)
    local a, b = list[1], list[2]
    return math.min(a[1], b[1]), math.min(a[2], b[2]), math.min(a[3], b[3]),
      math.max(a[4], b[4]), math.max(a[5], b[5]), math.max(a[6], b[6])
  end,
  drops = function() return { { id = 69, count = 1, damage = 0 } } end }

-- Przycisk: meta 1-4 = podpora, bit 8 = wciśnięty
local function buttonBounds(meta)
  local v = B.SUPPORT[meta % 8] or B.SUPPORT[1]
  local d = (meta >= 8) and P or 2 * P
  local x0, x1, z0, z1 = 5 * P, 11 * P, 5 * P, 11 * P
  if v[1] ~= 0 then x0, x1 = v[1] < 0 and 0 or 1 - d, v[1] < 0 and d or 1 end
  if v[3] ~= 0 then z0, z1 = v[3] < 0 and 0 or 1 - d, v[3] < 0 and d or 1 end
  return x0, 6 * P, z0, x1, 10 * P, z1
end
B.define { id = 77, name = "stone_button", label = "Przycisk", tex = "stone_button", solid = false,
  opaque = false, shape = "box", bounds = buttonBounds, hardness = 0.5, resistance = 0.5,
  redstone = "button", drops = function() return { { id = 77, count = 1, damage = 0 } } end }

B.define { id = 70, name = "pressure_plate", label = "Plyta naciskowa", tex = "pressure_plate",
  solid = false, opaque = false, shape = "box", hardness = 0.5, resistance = 0.5,
  tool = "pickaxe", tier = 0, redstone = "plate",
  bounds = function(meta)
    return P, 0, P, 15 * P, (meta > 0) and P / 2 or P, 15 * P
  end,
  drops = function() return { { id = 70, count = 1, damage = 0 } } end }

-- Przekaźnik: meta 0-3 = kierunek wyjścia, bity 2-3 = opóźnienie (1..4)
local function repeaterBoxes(meta, on)
  local f = B.FACING4[meta % 4]
  local delay = math.floor(meta / 4) % 4
  local top = tiles.get(on and "repeater_on" or "repeater")
  local torch = tiles.get(on and "redstone_torch" or "redstone_torch_off")
  local list = { { 0, 0, 0, 1, 2 * P, 1, tile = nil } }
  -- pochodnia z przodu (stała) i z tyłu (zależna od opóźnienia)
  local function tb(offset)
    local cx, cz = 0.5 + f[1] * offset, 0.5 + f[3] * offset
    return { cx - P, 2 * P, cz - P, cx + P, 7 * P, cz + P, tile = torch }
  end
  list[2] = tb(5 * P)
  list[3] = tb(-1 * P - delay * 2 * P)
  local _ = top
  return list
end
for _, on in ipairs({ false, true }) do
  B.define { id = on and 94 or 93, name = on and "repeater_on" or "repeater",
    label = "Przekaznik", opaque = false, shape = "box", layer = "opaque",
    bounds = box(0, 0, 0, 1, 2 * P, 1), hardness = 0, resistance = 0, redstone = "repeater",
    light = on and 7 or 0,
    boxes = function(meta) return repeaterBoxes(meta, on) end,
    texFn = (function()
      local top = tiles.get(on and "repeater_on" or "repeater")
      local side = tiles.get("slab_side")
      return function(face) return face == 3 and top or side end
    end)(),
    drops = function() return { { id = 356, count = 1, damage = 0 } } end }
end

B.define { id = 123, name = "redstone_lamp", label = "Lampa", tex = "redstone_lamp", hardness = 0.3,
  resistance = 0.3, redstone = "lamp" }
B.define { id = 124, name = "redstone_lamp_on", label = "Lampa (wl.)", tex = "redstone_lamp_on",
  hardness = 0.3, resistance = 0.3, light = 15, redstone = "lamp",
  drops = function() return { { id = 123, count = 1, damage = 0 } } end }

-- Tłok: meta 0-5 = kierunek, bit 8 = wysunięty
local function pistonTex(sticky)
  local front = tiles.get(sticky and "piston_top_sticky" or "piston_top")
  local inner, back, side = tiles.get("piston_inner"), tiles.get("piston_bottom"), tiles.get("piston_side")
  return function(face, meta)
    local f = FACING6_TO_FACE[meta % 8] or 3
    if face == f then return meta >= 8 and inner or front end
    if face == OPPOSITE_FACE[f] then return back end
    return side
  end
end
local function pistonBounds(meta)
  if meta < 8 then return 0, 0, 0, 1, 1, 1 end
  local v = B.FACING6[meta % 8] or B.FACING6[1]
  local x0, y0, z0, x1, y1, z1 = 0, 0, 0, 1, 1, 1
  if v[1] > 0 then x1 = 12 * P elseif v[1] < 0 then x0 = 4 * P end
  if v[2] > 0 then y1 = 12 * P elseif v[2] < 0 then y0 = 4 * P end
  if v[3] > 0 then z1 = 12 * P elseif v[3] < 0 then z0 = 4 * P end
  return x0, y0, z0, x1, y1, z1
end
for _, sticky in ipairs({ false, true }) do
  B.define { id = sticky and 29 or 33, name = sticky and "sticky_piston" or "piston",
    label = sticky and "Lepki tlok" or "Tlok", opaque = false, opacity = 15, layer = "opaque",
    shape = "box", bounds = pistonBounds, hardness = 0.5, resistance = 0.5, redstone = "piston",
    sticky = sticky, texFn = pistonTex(sticky),
    drops = function() return { { id = sticky and 29 or 33, count = 1, damage = 0 } } end }
end
B.pistonBounds = pistonBounds

-- Głowica tłoka: meta 0-5 = kierunek, bit 8 = lepka
local function headBoxes(meta)
  local v = B.FACING6[meta % 8] or B.FACING6[1]
  local face = tiles.get(meta >= 8 and "piston_top_sticky" or "piston_top")
  local side = tiles.get("piston_side")
  local function span(c, lo, hi)
    if c > 0 then return lo, hi elseif c < 0 then return 1 - hi, 1 - lo end
    return nil
  end
  local px0, px1 = span(v[1], 12 * P, 1)
  local py0, py1 = span(v[2], 12 * P, 1)
  local pz0, pz1 = span(v[3], 12 * P, 1)
  local plate = { px0 or 0, py0 or 0, pz0 or 0, px1 or 1, py1 or 1, pz1 or 1, tile = face }
  local ax0, ax1 = span(v[1], -4 * P, 12 * P)
  local ay0, ay1 = span(v[2], -4 * P, 12 * P)
  local az0, az1 = span(v[3], -4 * P, 12 * P)
  local arm = { ax0 or 6 * P, ay0 or 6 * P, az0 or 6 * P, ax1 or 10 * P, ay1 or 10 * P, az1 or 10 * P,
    tile = side }
  -- ramię nie może wychodzić poza blok w rysowaniu - przycinamy do 0..1
  for i = 1, 6 do
    if arm[i] < 0 then arm[i] = 0 end
    if arm[i] > 1 then arm[i] = 1 end
  end
  return { plate, arm }
end
B.define { id = 34, name = "piston_head", label = "Glowica tloka", opaque = false, opacity = 0,
  layer = "opaque", shape = "box", boxes = headBoxes, hardness = 0.5, resistance = 0.5,
  tex = "piston_top", drops = function() return nil end, redstone = "head",
  bounds = function(meta)
    local list = headBoxes(meta)
    local a, b = list[1], list[2]
    return math.min(a[1], b[1]), math.min(a[2], b[2]), math.min(a[3], b[3]),
      math.max(a[4], b[4]), math.max(a[5], b[5]), math.max(a[6], b[6])
  end }

-- Płotek: bity meta = połączenia (1 = +X, 2 = -X, 4 = +Z, 8 = -Z)
local function fenceBoxes(meta)
  local list = { { 6 * P, 0, 6 * P, 10 * P, 1, 10 * P } }
  local function bar(x0, z0, x1, z1)
    list[#list + 1] = { x0, 12 * P, z0, x1, 15 * P, z1 }
    list[#list + 1] = { x0, 6 * P, z0, x1, 9 * P, z1 }
  end
  if meta % 2 == 1 then bar(10 * P, 7 * P, 1, 9 * P) end
  if math.floor(meta / 2) % 2 == 1 then bar(0, 7 * P, 6 * P, 9 * P) end
  if math.floor(meta / 4) % 2 == 1 then bar(7 * P, 10 * P, 9 * P, 1) end
  if math.floor(meta / 8) % 2 == 1 then bar(7 * P, 0, 9 * P, 6 * P) end
  return list
end
local function fenceBounds(meta)
  local x0, z0, x1, z1 = 6 * P, 6 * P, 10 * P, 10 * P
  if meta % 2 == 1 then x1 = 1 end
  if math.floor(meta / 2) % 2 == 1 then x0 = 0 end
  if math.floor(meta / 4) % 2 == 1 then z1 = 1 end
  if math.floor(meta / 8) % 2 == 1 then z0 = 0 end
  return x0, 0, z0, x1, 1, z1
end
B.define { id = 85, name = "fence", label = "Plotek", tex = "planks", opaque = false, shape = "box",
  layer = "opaque", boxes = fenceBoxes, bounds = fenceBounds, hardness = 2, resistance = 3,
  tool = "axe", flammable = true, fence = true,
  collisionBounds = function(meta)
    local x0, y0, z0, x1, _, z1 = fenceBounds(meta)
    return x0, y0, z0, x1, 1.5, z1
  end,
  drops = function() return { { id = 85, count = 1, damage = 0 } } end }

-- ---------------------------------------------------------------------------
-- Nether
-- ---------------------------------------------------------------------------
B.define { id = 87, name = "netherrack", label = "Skala Netheru", tex = "netherrack", hardness = 0.4,
  resistance = 0.4, tool = "pickaxe", tier = 0, eternalFire = true }
B.define { id = 88, name = "soul_sand", label = "Piasek dusz", tex = "soul_sand", hardness = 0.5,
  resistance = 0.5, tool = "shovel", opaque = false, opacity = 15, layer = "opaque", shape = "box",
  bounds = box(0, 0, 0, 1, 14 * P, 1), slowsEntities = true,
  texFn = (function() local t = tiles.get("soul_sand"); return function() return t end end)() }
-- Portal: meta 0 = płaszczyzna wzdłuż X, 1 = wzdłuż Z
B.define { id = 90, name = "portal", label = "Portal", tex = "nether_portal", solid = false,
  opaque = false, shape = "box", layer = "translucent", light = 11, hardness = -1,
  resistance = 0, selectable = false, drops = dropNothing,
  bounds = function(meta)
    if meta == 1 then return 6 * P, 0, 0, 10 * P, 1, 1 end
    return 0, 0, 6 * P, 1, 1, 10 * P
  end }

-- ---------------------------------------------------------------------------
-- Tory (kształt "rail": płaska płytka, wzniesienia i zakręty)
-- ---------------------------------------------------------------------------
local function railBounds(meta)
  local shape = meta % 8
  if meta < 16 and meta >= 10 then shape = meta end
  if shape >= 2 and shape <= 5 then return 0, 0, 0, 1, 0.5, 1 end
  return 0, 0, 0, 1, 2 * P, 1
end
B.define { id = 66, name = "rail", label = "Tory", tex = "rail", solid = false, opaque = false,
  shape = "rail", bounds = railBounds, hardness = 0.7, resistance = 0.7, tool = "pickaxe",
  icon = "flat", rail = true,
  texFn = (function()
    local straight, corner = tiles.get("rail"), tiles.get("rail_corner")
    return function(_, meta) return (meta >= 6 and meta <= 9) and corner or straight end
  end)(),
  drops = function() return { { id = 66, count = 1, damage = 0 } } end }
B.define { id = 27, name = "powered_rail", label = "Tory zasilane", solid = false, opaque = false,
  shape = "rail", bounds = railBounds, hardness = 0.7, resistance = 0.7, tool = "pickaxe",
  icon = "flat", rail = true, redstone = "poweredrail", tex = "powered_rail",
  texFn = (function()
    local off, on = tiles.get("powered_rail"), tiles.get("powered_rail_on")
    return function(_, meta) return meta >= 8 and on or off end
  end)(),
  drops = function() return { { id = 27, count = 1, damage = 0 } } end }
B.define { id = 28, name = "detector_rail", label = "Tory z czujnikiem", tex = "detector_rail",
  solid = false, opaque = false, shape = "rail", bounds = railBounds, hardness = 0.7,
  resistance = 0.7, tool = "pickaxe", icon = "flat", rail = true, redstone = "detector",
  drops = function() return { { id = 28, count = 1, damage = 0 } } end }

-- ---------------------------------------------------------------------------
-- Zaklinanie i alchemia
-- ---------------------------------------------------------------------------
B.define { id = 116, name = "enchanting_table", label = "Stol do zaklinania", opaque = false,
  opacity = 0, layer = "opaque", shape = "box", bounds = box(0, 0, 0, 1, 12 * P, 1), hardness = 5,
  resistance = 1200, tool = "pickaxe", tier = 0, light = 7,
  tex = { top = "enchanting_top", side = "enchanting_side", bottom = "enchanting_bottom" } }

-- Statyw alchemiczny: podstawa i pręt; zawartość w danych bloku (3 butelki + składnik)
B.define { id = 117, name = "brewing_stand", label = "Statyw alchemiczny", opaque = false,
  opacity = 0, layer = "cutout", shape = "box", hardness = 0.5, resistance = 0.5,
  tool = "pickaxe", tex = "brewing_stand", light = 1, tileEntity = "brewing",
  bounds = box(1 * P, 0, 1 * P, 15 * P, 14 * P, 15 * P),
  boxes = (function()
    local base, rod = tiles.get("brewing_base"), tiles.get("brewing_stand")
    local list = {
      { 1 * P, 0, 1 * P, 15 * P, 2 * P, 15 * P, tile = base },
      { 7 * P, 2 * P, 7 * P, 9 * P, 14 * P, 9 * P, tile = rod },
      { 2 * P, 2 * P, 3 * P, 5 * P, 9 * P, 6 * P, tile = rod },
      { 11 * P, 2 * P, 3 * P, 14 * P, 9 * P, 6 * P, tile = rod },
      { 6.5 * P, 2 * P, 11 * P, 9.5 * P, 9 * P, 14 * P, tile = rod },
    }
    return function() return list end
  end)(),
  drops = function() return { { id = 379, count = 1, damage = 0 } } end }

-- Kocioł: meta 0..3 = poziom wody
local function cauldronBoxes(meta)
  local side, inner = tiles.get("cauldron"), tiles.get("cauldron_inner")
  local list = {
    { 0, 3 * P, 0, 1, 5 * P, 1, tile = inner },
    { 0, 5 * P, 0, 2 * P, 1, 1, tile = side }, { 14 * P, 5 * P, 0, 1, 1, 1, tile = side },
    { 2 * P, 5 * P, 0, 14 * P, 1, 2 * P, tile = side }, { 2 * P, 5 * P, 14 * P, 14 * P, 1, 1, tile = side },
    { 0, 0, 0, 4 * P, 3 * P, 4 * P, tile = side }, { 12 * P, 0, 0, 1, 3 * P, 4 * P, tile = side },
    { 0, 0, 12 * P, 4 * P, 3 * P, 1, tile = side }, { 12 * P, 0, 12 * P, 1, 3 * P, 1, tile = side },
  }
  if meta > 0 then
    list[#list + 1] = { 2 * P, 5 * P, 2 * P, 14 * P, (6 + meta * 3) * P, 14 * P, tile = tiles.get("water") }
  end
  return list
end
B.define { id = 118, name = "cauldron", label = "Kociol", opaque = false, opacity = 0,
  layer = "opaque", shape = "box", boxes = cauldronBoxes, bounds = box(0, 0, 0, 1, 1, 1),
  hardness = 2, resistance = 2, tool = "pickaxe", tier = 0, tex = "cauldron",
  drops = function() return { { id = 380, count = 1, damage = 0 } } end }

-- Brodawka netherowa: rośnie na piasku dusz, meta 0..3
B.define { id = 115, name = "nether_wart", label = "Brodawka netherowa", solid = false, opaque = false,
  shape = "cross", hardness = 0, resistance = 0, tex = "nether_wart_0", silkDrop = false,
  bounds = box(0, 0, 0, 1, 4 * P, 1),
  texFn = (function()
    local t = { tiles.get("nether_wart_0"), tiles.get("nether_wart_1"), tiles.get("nether_wart_1"),
      tiles.get("nether_wart_2") }
    return function(_, meta) return t[(meta % 4) + 1] end
  end)(),
  drops = function(meta, rng)
    local n = meta >= 3 and rng:int(2, 4) or 1
    return { { id = 372, count = n, damage = 0 } }
  end }

-- ---------------------------------------------------------------------------
-- Twierdza i End
-- ---------------------------------------------------------------------------
B.define { id = 119, name = "end_portal", label = "Portal Endu", tex = "end_portal", solid = false,
  opaque = false, shape = "box", layer = "opaque", opacity = 0, light = 15, hardness = -1,
  resistance = 3600000, selectable = false, drops = dropNothing, bounds = box(0, 0, 0, 1, 12 * P, 1),
  boxes = (function()
    local t = tiles.get("end_portal")
    local list = { { 0, 11 * P, 0, 1, 12 * P, 1, tile = t } }
    return function() return list end
  end)() }

-- Rama portalu Endu: meta 0-3 = kierunek, +4 = z okiem Endu
local function frameBoxes(meta)
  local top, side, bottom = tiles.get("end_portal_frame"), tiles.get("end_portal_frame_side"),
    tiles.get("end_stone")
  local list = { { 0, 0, 0, 1, 13 * P, 1, tiles = { side, side, top, bottom, side, side } } }
  if meta >= 4 then
    local eye = tiles.get("ender_eye")
    list[2] = { 4 * P, 13 * P, 4 * P, 12 * P, 1, 12 * P, tile = eye }
  end
  return list
end
B.define { id = 120, name = "end_portal_frame", label = "Rama portalu Endu", opaque = false,
  opacity = 15, layer = "opaque", shape = "box", boxes = frameBoxes, hardness = -1,
  resistance = 3600000, tex = { top = "end_portal_frame", side = "end_portal_frame_side",
    bottom = "end_stone" }, light = 1, drops = dropNothing,
  bounds = function(meta) return 0, 0, 0, 1, meta >= 4 and 1 or 13 * P, 1 end }

B.define { id = 121, name = "end_stone", label = "Kamien Endu", tex = "end_stone", hardness = 3,
  resistance = 15, tool = "pickaxe", tier = 0 }

B.define { id = 122, name = "dragon_egg", label = "Jajo smoka", opaque = false, opacity = 0,
  layer = "opaque", shape = "box", tex = "dragon_egg", hardness = 3, resistance = 15, light = 1,
  bounds = box(P, 0, P, 15 * P, 1, 15 * P),
  boxes = (function()
    local t = tiles.get("dragon_egg")
    local list = {
      { 6 * P, 15 * P, 6 * P, 10 * P, 1, 10 * P, tile = t },
      { 5 * P, 14 * P, 5 * P, 11 * P, 15 * P, 11 * P, tile = t },
      { 4 * P, 13 * P, 4 * P, 12 * P, 14 * P, 12 * P, tile = t },
      { 3 * P, 11 * P, 3 * P, 13 * P, 13 * P, 13 * P, tile = t },
      { 2 * P, 8 * P, 2 * P, 14 * P, 11 * P, 14 * P, tile = t },
      { 1 * P, 3 * P, 1 * P, 15 * P, 8 * P, 15 * P, tile = t },
      { 2 * P, 1 * P, 2 * P, 14 * P, 3 * P, 14 * P, tile = t },
      { 3 * P, 0, 3 * P, 13 * P, 1 * P, 13 * P, tile = t },
    }
    return function() return list end
  end)() }

-- Warianty cegieł do twierdzy (zwykłe cegły to blok 98)
B.define { id = 97, name = "mossy_stone_bricks", label = "Omszale kamienne cegly",
  tex = "stone_bricks_mossy", hardness = 1.5, resistance = 6, tool = "pickaxe", tier = 0 }
B.define { id = 99, name = "cracked_stone_bricks", label = "Popekane kamienne cegly",
  tex = "stone_bricks_cracked", hardness = 1.5, resistance = 6, tool = "pickaxe", tier = 0 }
B.define { id = 101, name = "iron_bars", label = "Krata", opaque = false, opacity = 0,
  layer = "cutout", shape = "box", tex = "iron_bars", hardness = 5, resistance = 6,
  tool = "pickaxe", tier = 0, bounds = box(0, 0, 7 * P, 1, 1, 9 * P),
  boxes = (function()
    local t = tiles.get("iron_bars")
    local list = { { 0, 0, 7.5 * P, 1, 1, 8.5 * P, tile = t }, { 7.5 * P, 0, 0, 8.5 * P, 1, 1, tile = t } }
    return function() return list end
  end)(),
  collisionBounds = function() return 0, 0, 6 * P, 1, 1, 10 * P end }

-- ---------------------------------------------------------------------------
-- Szybkie tablice właściwości (indeks = id, 0..255) dla meshera i fizyki
-- ---------------------------------------------------------------------------
B.OPAQUE = {}   -- 1 = pełny nieprzezroczysty sześcian
B.OPACITY = {}  -- pochłanianie światła 0..15
B.LIGHT = {}    -- emisja światła
B.SOLID = {}    -- 1 = kolizja
for id = 0, 255 do
  local d = B.defs[id]
  B.OPAQUE[id] = (d and d.opaque and d.shape == "cube") and 1 or 0
  B.OPACITY[id] = d and d.opacity or 15
  B.LIGHT[id] = d and d.light or 0
  B.SOLID[id] = (d and d.solid) and 1 or 0
end

return B
