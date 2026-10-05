-- render/icons.lua
-- Ikony przedmiotów do ekwipunku i HUD. Bloki pokazujemy jako małe
-- sześciany w rzucie izometrycznym (jak w Minecraft Beta), przedmioty jako
-- pixel art. Wszystko rysowane raz do jednego atlasu (Canvas) i keszowane.

local blocks = require("core.blocks")
local items = require("core.items")
local tiles = require("core.tiles")
local atlas = require("render.atlas")
local itemart = require("render.itemart")

local M = {}

local CELL = 32
local COLS = 32
local canvas
local slots = {}    -- klucz "id:damage" -> quad
local nextSlot = 0
local isoMesh

local function key(id, damage) return id * 65536 + (damage or 0) end

function M.load()
  canvas = love.graphics.newCanvas(CELL * COLS, CELL * COLS)
  canvas:setFilter("nearest", "nearest")
  isoMesh = love.graphics.newMesh({
    { "VertexPosition", "float", 2 },
    { "VertexTexCoord", "float", 2 },
    { "VertexColor", "byte", 4 },
  }, 4, "fan", "dynamic")
  isoMesh:setTexture(atlas.image)
end

-- Wariant tekstury bloku dla ikony (np. kolor wełny z damage)
local function blockMeta(def, damage)
  if def.metaMask and def.metaMask > 0 then return (damage or 0) % (def.metaMask + 1) end
  if def.name == "furnace" or def.name == "chest" or def.name == "pumpkin"
    or def.name == "jack_o_lantern" then
    return 0
  end
  return 0
end

local function drawFace(tile, p1, p2, p3, p4, shade, v0frac, v1frac)
  local u0, v0, size = tiles.uv(tile)
  local e = 0.0005
  local tv0 = v0 + size * (v0frac or 0) + e
  local tv1 = v0 + size * (v1frac or 1) - e
  isoMesh:setVertices({
    { p1[1], p1[2], u0 + e, tv0, shade, shade, shade, 1 },
    { p2[1], p2[2], u0 + size - e, tv0, shade, shade, shade, 1 },
    { p3[1], p3[2], u0 + size - e, tv1, shade, shade, shade, 1 },
    { p4[1], p4[2], u0 + e, tv1, shade, shade, shade, 1 },
  })
  love.graphics.draw(isoMesh)
end

-- Sześcian izometryczny w komórce (ox, oy); heightFrac: 1 = pełny blok
local function drawIsoBlock(def, meta, ox, oy, heightFrac)
  local s = CELL / 32
  local h = (heightFrac or 1)
  local top = blocks.faceTile(def, 3, meta)
  local left = blocks.faceTile(def, 5, meta)   -- południe (przód)
  local right = blocks.faceTile(def, 1, meta)  -- wschód
  if def.texFn and (def.name == "furnace" or def.name == "lit_furnace" or def.name == "pumpkin"
    or def.name == "jack_o_lantern" or def.name == "chest") then
    left = blocks.faceTile(def, 5, 0)
  end
  local yoff = (1 - h) * 14 * s
  local function P(x, y) return { ox + x * s, oy + y * s } end
  -- górna ściana (romb)
  drawFace(top, P(16, 2 + yoff / s), P(30, 9 + yoff / s), P(16, 16 + yoff / s), P(2, 9 + yoff / s), 1)
  -- lewa (przód)
  drawFace(left, P(2, 9 + yoff / s), P(16, 16 + yoff / s), P(16, 30), P(2, 23), 0.8, 1 - h, 1)
  -- prawa
  drawFace(right, P(16, 16 + yoff / s), P(30, 9 + yoff / s), P(30, 23), P(16, 30), 0.6, 1 - h, 1)
end

local imageCache = {}
local function pixelsToImage(pixels)
  local data = love.image.newImageData(16, 16)
  for y = 0, 15 do
    for x = 0, 15 do
      local p = pixels[x + y * 16]
      data:setPixel(x, y, p[1] / 255, p[2] / 255, p[3] / 255, p[4] / 255)
    end
  end
  local img = love.graphics.newImage(data)
  img:setFilter("nearest", "nearest")
  return img
end

-- Rysuje ikonę do atlasu i zwraca quad
local function build(id, damage)
  local slot = nextSlot
  nextSlot = nextSlot + 1
  local ox = (slot % COLS) * CELL
  local oy = math.floor(slot / COLS) * CELL
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.setShader()
  love.graphics.setBlendMode("alpha")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.origin()
  love.graphics.setScissor(ox, oy, CELL, CELL)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setScissor()

  local def = items.get(id)
  if id < 256 and def then
    local flat = def.icon == "flat" or def.shape == "cross" or def.shape == "none"
      or def.name == "door" or def.name == "ladder" or def.name == "torch"
    if flat then
      local tile = blocks.faceTile(def, 3, blockMeta(def, damage))
      love.graphics.draw(atlas.image, atlas.quads[tile], ox, oy, 0, CELL / 16, CELL / 16)
    else
      local hf = 1
      if def.name == "slab" then hf = 0.5 elseif def.name == "snow_layer" then hf = 0.125
      elseif def.name == "bed" then hf = 0.56 elseif def.name == "farmland" then hf = 0.94 end
      drawIsoBlock(def, blockMeta(def, damage), ox, oy, hf)
    end
  elseif def then
    local img = imageCache[key(id, damage)]
    if not img then
      img = pixelsToImage(itemart.generate(def, damage))
      imageCache[key(id, damage)] = img
    end
    love.graphics.draw(img, ox, oy, 0, CELL / 16, CELL / 16)
  end
  love.graphics.pop()
  local q = love.graphics.newQuad(ox, oy, CELL, CELL, canvas:getDimensions())
  return q
end

-- Damage ma znaczenie tylko dla przedmiotów z wariantami (barwnik, wełna...)
local function iconDamage(id, damage)
  local d = items.get(id)
  if not d then return 0 end
  if d.maxDamage then return 0 end
  if id < 256 and not (d.metaMask and d.metaMask > 0) then return 0 end
  return damage or 0
end

function M.quad(id, damage)
  local dmg = iconDamage(id, damage)
  local k = key(id, dmg)
  local q = slots[k]
  if not q then
    q = build(id, dmg)
    slots[k] = q
  end
  return q
end

-- Rysuje ikonę stosu w (x, y) o boku size pikseli
function M.draw(id, damage, x, y, size)
  if not items.get(id) then return end
  local q = M.quad(id, damage)
  love.graphics.draw(canvas, q, x, y, 0, size / CELL, size / CELL)
end

-- Obrazek ikony przedmiotu (pixel art) - do sprite'ów przedmiotów w świecie
function M.itemImage(id, damage)
  local dmg = iconDamage(id, damage)
  local k = key(id, dmg)
  local img = imageCache[k]
  if not img then
    local def = items.get(id)
    if not def then return nil end
    if id < 256 then
      local tile = blocks.faceTile(def, 3, blockMeta(def, dmg))
      local size = tiles.SIZE
      local data = love.image.newImageData(size, size)
      data:paste(atlas.imageData, 0, 0, (tile % tiles.COLUMNS) * size,
        math.floor(tile / tiles.COLUMNS) * size, size, size)
      img = love.graphics.newImage(data)
      img:setFilter("nearest", "nearest")
    else
      img = pixelsToImage(itemart.generate(def, dmg))
    end
    imageCache[k] = img
  end
  return img
end

function M.canvas() return canvas end

return M
