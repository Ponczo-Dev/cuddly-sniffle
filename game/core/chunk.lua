-- core/chunk.lua
-- Chunk: kolumna 16 x 128 x 16 bloków.
-- Dane trzymamy w płaskich tablicach bajtów, indeks = x + z*16 + y*256
-- (x, z: 0..15, y: 0..127). Dzięki temu jedna tablica zamiast tysięcy tabel.

local bytearray = require("core.bytearray")
local blocks = require("core.blocks")

local M = {}

local SIZE = 16
local HEIGHT = 128
local VOLUME = SIZE * SIZE * HEIGHT
M.SIZE, M.HEIGHT, M.VOLUME = SIZE, HEIGHT, VOLUME

local OPACITY = blocks.OPACITY

local Chunk = {}
Chunk.__index = Chunk

function M.new(cx, cz)
  local self = setmetatable({}, Chunk)
  self.cx, self.cz = cx, cz
  self.blocks = bytearray.new(VOLUME)
  self.meta = bytearray.new(VOLUME)
  self.sky = bytearray.new(VOLUME)        -- światło nieba 0..15
  self.blockLight = bytearray.new(VOLUME) -- światło bloków 0..15
  self.heightMap = {}  -- dla każdej kolumny: y pierwszego bloku nad najwyższym nieprzezroczystym
  for i = 0, SIZE * SIZE - 1 do self.heightMap[i] = 0 end
  self.maxY = 0        -- najwyższy niepusty blok (mesher nie musi sprawdzać wyżej)
  self.tiles = {}      -- dane dodatkowe bloków (skrzynie, piece): indeks -> tabela
  self.generated = false
  self.lit = false
  self.dirty = true    -- trzeba przebudować mesh
  self.modified = false -- trzeba zapisać na dysk
  return self
end

function M.index(x, y, z)
  return x + z * SIZE + y * 256
end
local index = M.index

function Chunk:get(x, y, z)
  return self.blocks[x + z * SIZE + y * 256]
end

function Chunk:getMeta(x, y, z)
  return self.meta[x + z * SIZE + y * 256]
end

-- Ustawia blok bez żadnych aktualizacji (szybka ścieżka dla generatora)
function Chunk:setRaw(x, y, z, id, meta)
  local i = x + z * SIZE + y * 256
  self.blocks[i] = id
  self.meta[i] = meta or 0
end

-- Przelicza mapę wysokości i maxY (po generowaniu albo wczytaniu)
function Chunk:recalcHeights()
  local maxY = 0
  local b = self.blocks
  for z = 0, SIZE - 1 do
    for x = 0, SIZE - 1 do
      local h = 0
      for y = HEIGHT - 1, 0, -1 do
        local id = b[x + z * SIZE + y * 256]
        if id ~= 0 then
          if y > maxY then maxY = y end
          if OPACITY[id] > 0 then
            h = y + 1
            break
          end
        end
      end
      self.heightMap[x + z * SIZE] = h
    end
  end
  self.maxY = maxY
end

-- Aktualizuje mapę wysokości jednej kolumny po zmianie bloku
function Chunk:updateColumn(x, y, z, id)
  if id ~= 0 and y > self.maxY then self.maxY = y end
  local col = x + z * SIZE
  local h = self.heightMap[col]
  if OPACITY[id] > 0 then
    if y + 1 > h then self.heightMap[col] = y + 1 end
  elseif y + 1 == h then
    -- usunięto najwyższy blok: szukamy w dół nowego szczytu
    local b = self.blocks
    local nh = 0
    for yy = y - 1, 0, -1 do
      if OPACITY[b[col + yy * 256]] > 0 then
        nh = yy + 1
        break
      end
    end
    self.heightMap[col] = nh
  end
end

function Chunk:height(x, z)
  return self.heightMap[x + z * SIZE]
end

function Chunk:getTile(x, y, z)
  return self.tiles[index(x, y, z)]
end

function Chunk:setTile(x, y, z, tile)
  self.tiles[index(x, y, z)] = tile
  self.modified = true
end

return M
