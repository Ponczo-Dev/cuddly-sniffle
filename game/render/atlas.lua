-- render/atlas.lua
-- Składa wszystkie kafelki z core/tiles.lua w jeden obraz (atlas tekstur).
-- Jeden atlas = jedna tekstura dla całego świata = mało przełączeń w GPU.

local tiles = require("core.tiles")
local texturegen = require("render.texturegen")

local M = {}

M.image = nil
M.imageData = nil
M.missing = {} -- nazwy kafelków bez generatora (do ekranu debug)

function M.load()
  local cols = tiles.COLUMNS
  local size = tiles.SIZE
  local px = cols * size
  local data = love.image.newImageData(px, px)
  for i, name in ipairs(tiles.names) do
    local idx = i - 1
    local ox = (idx % cols) * size
    local oy = math.floor(idx / cols) * size
    local pixels, ok = texturegen.generate(name)
    if not ok then M.missing[#M.missing + 1] = name end
    for y = 0, size - 1 do
      for x = 0, size - 1 do
        local p = pixels[x + y * size]
        data:setPixel(ox + x, oy + y, p[1] / 255, p[2] / 255, p[3] / 255, p[4] / 255)
      end
    end
  end
  M.imageData = data
  M.image = love.graphics.newImage(data)
  M.image:setFilter("nearest", "nearest")
  M.image:setWrap("clamp", "clamp")

  -- osobne obrazki pojedynczych kafelków (ikony, cząsteczki, napis pękania)
  M.quads = {}
  for i = 0, tiles.count - 1 do
    local ox = (i % cols) * size
    local oy = math.floor(i / cols) * size
    M.quads[i] = love.graphics.newQuad(ox, oy, size, size, px, px)
  end
  return M.image
end

-- Średni kolor kafelka (cząsteczki przy kopaniu, kolor na mapie)
local colorCache = {}
function M.averageColor(tile)
  if colorCache[tile] then return colorCache[tile] end
  local size = tiles.SIZE
  local ox = (tile % tiles.COLUMNS) * size
  local oy = math.floor(tile / tiles.COLUMNS) * size
  local r, g, b, n = 0, 0, 0, 0
  for y = 0, size - 1 do
    for x = 0, size - 1 do
      local pr, pg, pb, pa = M.imageData:getPixel(ox + x, oy + y)
      if pa > 0.5 then
        r, g, b, n = r + pr, g + pg, b + pb, n + 1
      end
    end
  end
  if n == 0 then n = 1 end
  local c = { r / n, g / n, b / n }
  colorCache[tile] = c
  return c
end

return M
