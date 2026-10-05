-- core/maps.lua
-- Mapy (jak w Beta 1.6): pusta mapa użyta prawym przyciskiem staje się mapą
-- okolicy 128x128 bloków (wyrównaną do siatki). Gdy trzymasz mapę w ręce,
-- odkrywa się teren w promieniu 64 bloków. Piksel = indeks koloru:
--   0 = nieodkryte, inaczej kolor * 4 + cień (1 jasny, 2 średni, 3 ciemny)
-- Zapis: worlds/<folder>/maps/<id>.dat (RLE + kompresja).

local blocks = require("core.blocks")
local save = require("core.save")
local fs = require("core.fs")

local M = {}

local floor = math.floor
M.SIZE = 128

-- Paleta kolorów mapy (indeks od 1)
M.PALETTE = {
  { 127, 178, 56 },   -- 1 trawa
  { 247, 233, 163 },  -- 2 piasek
  { 112, 112, 112 },  -- 3 kamień
  { 151, 109, 77 },   -- 4 ziemia
  { 64, 64, 255 },    -- 5 woda
  { 255, 0, 0 },      -- 6 lawa
  { 0, 124, 0 },      -- 7 liście
  { 143, 119, 72 },   -- 8 drewno
  { 255, 255, 255 },  -- 9 śnieg
  { 160, 160, 255 },  -- 10 lód
  { 164, 168, 184 },  -- 11 glina
  { 112, 2, 0 },      -- 12 Nether
  { 199, 199, 199 },  -- 13 wełna / jasne
  { 60, 60, 60 },     -- 14 obsydian, ciemne
  { 255, 252, 245 },  -- 15 kwarc / kamień Endu (jasny)
  { 216, 127, 51 },   -- 16 pomarańczowy (dynia)
  { 0, 87, 0 },       -- 17 kaktus
}

local COLOR = {
  [2] = 1, [31] = 1, [37] = 1, [38] = 1, [6] = 1, [59] = 1, [83] = 1, [39] = 1, [40] = 1,
  [12] = 2, [24] = 2, [32] = 2, [121] = 15,
  [1] = 3, [4] = 3, [13] = 3, [14] = 3, [15] = 3, [16] = 3, [21] = 3, [56] = 3, [73] = 3, [7] = 3,
  [48] = 3, [98] = 3, [97] = 3, [99] = 3, [44] = 3, [61] = 3, [62] = 3, [67] = 3, [52] = 3,
  [3] = 4, [60] = 4, [88] = 4,
  [8] = 5, [9] = 5,
  [10] = 6, [11] = 6, [51] = 6,
  [18] = 7,
  [17] = 8, [5] = 8, [47] = 8, [54] = 8, [58] = 8, [85] = 8, [64] = 8, [53] = 8,
  [78] = 9, [80] = 9,
  [79] = 10,
  [82] = 11,
  [87] = 12, [89] = 16, [90] = 14, [45] = 12, [115] = 12,
  [35] = 13, [20] = 13, [42] = 13, [41] = 16,
  [49] = 14, [120] = 14, [116] = 14, [119] = 14,
  [86] = 16, [91] = 16, [81] = 17, [103] = 1,
}

local function colorOf(id)
  local c = COLOR[id]
  if c then return c end
  local d = blocks.defs[id]
  if d and d.liquid == "water" then return 5 end
  if d and d.liquid then return 6 end
  return 3
end

-- ---------------------------------------------------------------------------
-- Mapy w grze
-- ---------------------------------------------------------------------------
function M.init(game)
  game.maps = game.maps or {}
  game.nextMapId = game.nextMapId or 0
end

local function newMap(x0, z0, dim)
  local data = {}
  for i = 0, M.SIZE * M.SIZE - 1 do data[i] = 0 end
  return { x0 = x0, z0 = z0, dim = dim, data = data, version = 0 }
end

-- Tworzy nową mapę wokół gracza, zwraca jej numer
function M.create(game)
  M.init(game)
  local p = game.player
  local x0 = floor((p.x + 64) / 128) * 128 - 64
  local z0 = floor((p.z + 64) / 128) * 128 - 64
  local id = game.nextMapId
  game.nextMapId = id + 1
  local map = newMap(x0, z0, game.dimension)
  game.maps[id] = map
  M.update(game, map, true)
  return id
end

function M.get(game, id)
  M.init(game)
  local map = game.maps[id]
  if map == nil and game.saveFolder then
    map = M.load(game.saveFolder, id) or false
    game.maps[id] = map
  end
  return map or nil
end

-- Kolor kolumny świata (najwyższy widoczny blok, cień od wysokości północnego sąsiada)
local function columnTop(world, x, z)
  local y = world:getHeight(x, z) + 1
  if y > 127 then y = 127 end
  while y > 0 do
    local id = world:getBlock(x, y, z)
    if id ~= 0 then
      local d = blocks.defs[id]
      if d and (d.shape ~= "none") and id ~= 50 and id ~= 76 and id ~= 75 then return id, y end
    end
    y = y - 1
  end
  return 0, 0
end

-- Odkrywa teren w promieniu 64 bloków od gracza (full = cały obszar od razu)
function M.update(game, map, full)
  if map.dim ~= game.dimension then return end
  local world = game.world
  local p = game.player
  local px, pz = floor(p.x), floor(p.z)
  local R = 64
  local phase = game.time % 4
  local changed = false
  local data = map.data
  for mz = 0, M.SIZE - 1 do
    if full or mz % 4 == phase then
      local wz = map.z0 + mz
      local dz = wz - pz
      if dz * dz <= R * R then
        for mx = 0, M.SIZE - 1 do
          local wx = map.x0 + mx
          local dx = wx - px
          if dx * dx + dz * dz <= R * R and world:isLoadedAt(wx, wz) then
            local id, y = columnTop(world, wx, wz)
            local v = 0
            if id ~= 0 then
              local c = colorOf(id)
              local shade
              if c == 5 then
                -- głębokość wody
                local depth = 0
                local yy = y
                while yy > 0 and depth < 10 and blocks.defs[world:getBlock(wx, yy, wz)]
                  and blocks.defs[world:getBlock(wx, yy, wz)].liquid == "water" do
                  depth = depth + 1
                  yy = yy - 1
                end
                shade = depth < 3 and 1 or (depth < 6 and 2 or 3)
              else
                local _, ny = columnTop(world, wx, wz - 1)
                shade = y > ny and 1 or (y == ny and 2 or 3)
              end
              v = c * 4 + shade
            end
            local i = mx + mz * M.SIZE
            if data[i] ~= v then
              data[i] = v
              changed = true
            end
          end
        end
      end
    end
  end
  if changed then
    map.version = map.version + 1
    map.modified = true
  end
  return changed
end

-- Wywoływane co tick: aktualizuje mapę trzymaną w ręce
function M.tick(game)
  local held = game:heldStack()
  if held and held.id == 358 then
    local map = M.get(game, held.damage or 0)
    if map then M.update(game, map, false) end
  end
end

-- Kolor RGB piksela mapy (nil = nieodkryty)
local SHADE = { 1.0, 0.86, 0.71 }
function M.pixelColor(v)
  if v == 0 then return nil end
  local c = M.PALETTE[floor(v / 4)]
  if not c then return nil end
  local k = SHADE[v % 4] or 1
  return c[1] * k, c[2] * k, c[3] * k
end

-- ---------------------------------------------------------------------------
-- Zapis
-- ---------------------------------------------------------------------------
local function mapPath(folder, id) return "worlds/" .. folder .. "/maps/" .. id .. ".dat" end

function M.saveAll(game)
  local folder = game.saveFolder
  if not folder or not game.maps then return end
  for id, map in pairs(game.maps) do
    if map and map.modified then
      local header = string.format("MAP1 %d %d %s\n", map.x0, map.z0, map.dim or "overworld")
      fs.write(mapPath(folder, id), fs.compress(header .. save.rleEncode(map.data, M.SIZE * M.SIZE)))
      map.modified = false
    end
  end
end

function M.load(folder, id)
  local raw = fs.read(mapPath(folder, id))
  if not raw then return nil end
  local text = fs.decompress(raw)
  if not text then return nil end
  local x0, z0, dim = text:match("^MAP1 (%-?%d+) (%-?%d+) (%a+)\n")
  if not x0 then return nil end
  local map = newMap(tonumber(x0), tonumber(z0), dim)
  local start = #text:match("^[^\n]*\n") + 1
  save.rleDecode(text:sub(start), 1, map.data, M.SIZE * M.SIZE)
  return map
end

return M
