-- core/tiles.lua
-- Lista kafelków (tekstur 16x16) w atlasie bloków.
-- Kolejność = pozycja w atlasie (16 kafelków w wierszu, numeracja od 0).
-- Obrazki generuje render/textures.lua na podstawie NAZW z tej listy,
-- a mesher (czysta logika) potrzebuje tylko numerów.

local M = {}

local NAMES = {
  "stone", "dirt", "grass_top", "grass_side", "cobblestone", "planks", "sapling", "bedrock",
  "water", "lava", "sand", "gravel", "gold_ore", "iron_ore", "coal_ore", "log_side",
  "log_top", "leaves", "glass", "lapis_ore", "lapis_block", "sandstone_side", "sandstone_top",
  "sandstone_bottom", "wool", "dandelion", "rose", "mushroom_brown", "mushroom_red",
  "gold_block", "iron_block", "bricks",
  "tnt_side", "tnt_top", "tnt_bottom", "bookshelf", "mossy_cobblestone", "obsidian", "torch",
  "fire", "spawner", "chest_front", "chest_side", "chest_top", "diamond_ore", "diamond_block",
  "crafting_table_top", "crafting_table_side", "crafting_table_front",
  "wheat_0", "wheat_1", "wheat_2", "wheat_3", "wheat_4", "wheat_5", "wheat_6", "wheat_7",
  "farmland_dry", "farmland_wet", "furnace_front", "furnace_front_lit", "furnace_side",
  "furnace_top", "door_bottom", "door_top", "ladder", "redstone_ore", "snow", "grass_side_snow",
  "ice", "cactus_side", "cactus_top", "cactus_bottom", "clay", "sugar_cane", "pumpkin_side",
  "pumpkin_top", "pumpkin_face", "jack_o_lantern_face", "glowstone", "melon_side", "melon_top",
  "tall_grass", "dead_bush", "bed_top_foot", "bed_top_head", "bed_side_foot", "bed_side_head",
  "bed_end_foot", "bed_end_head", "slab_side", "slab_top", "white",
  "cracks_0", "cracks_1", "cracks_2", "cracks_3", "cracks_4",
  "cracks_5", "cracks_6", "cracks_7", "cracks_8", "cracks_9",
  "wool_red", "wool_yellow", "wool_green", "wool_blue", "wool_black",
  "netherrack", "soul_sand", "nether_portal", "stone_bricks", "rail", "rail_corner",
  "mob_spawner_cage", "planks_dark", "log_birch_side", "log_pine_side", "leaves_pine",
  "leaves_birch", "cobweb", "fence", "trapdoor", "piston_side", "piston_top", "piston_top_sticky",
  "piston_bottom", "piston_inner", "redstone_dust", "redstone_dust_on", "redstone_torch",
  "redstone_torch_off", "lever", "repeater", "repeater_on", "stone_button", "pressure_plate",
  "redstone_lamp", "redstone_lamp_on", "powered_rail", "powered_rail_on", "detector_rail",
  "dispenser_front", "note_block", "jukebox_top", "jukebox_side", "sponge", "end_stone",
  "end_portal_frame", "enchanting_top", "enchanting_side", "brewing_stand", "cauldron",
}

M.names = NAMES
M.index = {}      -- nazwa -> numer (od 0)
M.COLUMNS = 16    -- kafelków w wierszu atlasu
M.SIZE = 16       -- rozmiar kafelka w pikselach

for i, name in ipairs(NAMES) do
  M.index[name] = i - 1
end
M.count = #NAMES

-- Numer kafelka po nazwie (błąd przy literówce)
function M.get(name)
  local i = M.index[name]
  if not i then
    error("Nieznany kafelek tekstury: " .. tostring(name), 2)
  end
  return i
end

-- Współrzędne UV (0..1) lewego górnego rogu i rozmiar kafelka w atlasie
function M.uv(index)
  local col = index % M.COLUMNS
  local row = math.floor(index / M.COLUMNS)
  local size = 1 / M.COLUMNS
  return col * size, row * size, size
end

return M
