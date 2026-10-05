-- render/hud.lua
-- Interfejs w trakcie gry: celownik, pasek szybkiego wyboru, serca, głód,
-- pancerz, bąbelki powietrza, pasek doświadczenia, nazwa przedmiotu,
-- komunikaty i ekran debugowania (F3).

local gui = require("render.gui")
local items = require("core.items")
local texturegen = require("render.texturegen")
local survival = require("core.survival")

local M = {}

local sprites = {}

local function img(rows, pal)
  local px = texturegen.art(rows, pal)
  local w, h = #rows[1], #rows
  local data = love.image.newImageData(w, h)
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local p = px[x + y * 16]
      data:setPixel(x, y, p[1] / 255, p[2] / 255, p[3] / 255, p[4] / 255)
    end
  end
  local i = love.graphics.newImage(data)
  i:setFilter("nearest", "nearest")
  return i
end

local HEART = { ".oo.oo...", "oRRoRRo..", "oRwRRRo..", "oRRRRRo..", ".oRRRo...", "..oRo....",
  "...o.....", ".........", "........." }
local HEART_HALF = { ".oo.oo...", "oRRo..o..", "oRwo..o..", "oRRo..o..", ".oRo.o...", "..oRo....",
  "...o.....", ".........", "........." }
local FOOD = { "......oo.", ".....oBo.", "...ooBo..", "..oMMoo..", ".oMMMMo..", ".oMMMMo..",
  ".oMMMo...", "..ooo....", "........." }
local FOOD_HALF = { "......oo.", ".....oBo.", "...ooBo..", "..o..oo..", ".o...Mo..", ".o..MMo..",
  ".o.MMo...", "..ooo....", "........." }
local ARMOR = { ".ooo.ooo.", ".oWWoWWo.", ".oWWWWWo.", ".oWWWWWo.", ".oWWWWWo.", "..oWWWo..",
  "...ooo...", ".........", "........." }
local ARMOR_HALF = { ".ooo.ooo.", ".oWWo..o.", ".oWWo..o.", ".oWWo..o.", ".oWWo..o.", "..oWo.o..",
  "...ooo...", ".........", "........." }
local BUBBLE = { "..ooo....", ".oWwwo...", "oWwwwwo..", "owwwwwo..", "owwwwwo..", ".owwwo...",
  "..ooo....", ".........", "........." }

function M.load()
  sprites.heart = img(HEART, { o = { 20, 0, 0 }, R = { 220, 20, 20 }, w = { 255, 200, 200 } })
  sprites.heartHalf = img(HEART_HALF, { o = { 20, 0, 0 }, R = { 220, 20, 20 }, w = { 255, 200, 200 } })
  sprites.heartEmpty = img(HEART, { o = { 20, 0, 0 }, R = { 50, 20, 20 }, w = { 60, 25, 25 } })
  sprites.heartPoison = img(HEART, { o = { 20, 20, 0 }, R = { 140, 150, 30 }, w = { 200, 210, 120 } })
  sprites.heartFlash = img(HEART, { o = { 255, 255, 255 }, R = { 220, 20, 20 }, w = { 255, 200, 200 } })
  sprites.food = img(FOOD, { o = { 40, 20, 0 }, M = { 190, 110, 50 }, B = { 230, 220, 200 } })
  sprites.foodHalf = img(FOOD_HALF, { o = { 40, 20, 0 }, M = { 190, 110, 50 }, B = { 230, 220, 200 } })
  sprites.foodEmpty = img(FOOD, { o = { 40, 20, 0 }, M = { 55, 35, 20 }, B = { 70, 60, 50 } })
  sprites.foodHunger = img(FOOD, { o = { 20, 40, 0 }, M = { 110, 140, 40 }, B = { 180, 200, 150 } })
  sprites.armor = img(ARMOR, { o = { 30, 30, 30 }, W = { 220, 220, 220 } })
  sprites.armorHalf = img(ARMOR_HALF, { o = { 30, 30, 30 }, W = { 220, 220, 220 } })
  sprites.armorEmpty = img(ARMOR, { o = { 30, 30, 30 }, W = { 60, 60, 60 } })
  sprites.bubble = img(BUBBLE, { o = { 20, 40, 90 }, W = { 255, 255, 255 }, w = { 120, 170, 255 } })
end

M.messages = {}
M.itemName = nil
M.itemNameTime = 0

function M.message(text, color)
  table.insert(M.messages, { text = text, time = love.timer.getTime(), color = color })
  if #M.messages > 8 then table.remove(M.messages, 1) end
end

function M.showItemName(stack)
  if stack then
    M.itemName = items.label(stack)
    M.itemNameTime = love.timer.getTime()
  end
end

local function drawIcons(sprite, half, empty, value, maxv, x, y, rightToLeft, jitter)
  local g = love.graphics
  local s = gui.scale
  for i = 0, maxv / 2 - 1 do
    local ix = rightToLeft and (x - i * 8 * s - 9 * s) or (x + i * 8 * s)
    local iy = y + (jitter and jitter(i) or 0) * s
    g.draw(empty, ix, iy, 0, s, s)
    local v = value - i * 2
    if v >= 2 then g.draw(sprite, ix, iy, 0, s, s)
    elseif v == 1 then g.draw(half, ix, iy, 0, s, s) end
  end
end

function M.draw(game, alpha, opts)
  local g = love.graphics
  local w, h = g.getDimensions()
  local s = gui.scale
  opts = opts or {}

  -- celownik
  if not opts.hideCrosshair then
    g.setBlendMode("subtract")
    g.setColor(1, 1, 1, 0.75)
    g.rectangle("fill", w / 2 - 4.5 * s, h / 2 - 0.5 * s, 9 * s, s)
    g.rectangle("fill", w / 2 - 0.5 * s, h / 2 - 4.5 * s, s, 9 * s)
    g.setBlendMode("alpha")
    g.setColor(1, 1, 1, 0.9)
    g.rectangle("fill", w / 2 - 4.5 * s, h / 2 - 0.5 * s, 9 * s, s)
    g.rectangle("fill", w / 2 - 0.5 * s, h / 2 - 4.5 * s, s, 9 * s)
    g.setColor(1, 1, 1, 1)
  end

  -- aktywne efekty mikstur (prawy górny róg)
  local fx = game.effects
  if fx and next(fx) then
    local potions = require("core.potions")
    local names = {}
    for name in pairs(fx) do names[#names + 1] = name end
    table.sort(names)
    local y = 4 * s
    for _, name in ipairs(names) do
      local e = fx[name]
      local secs = math.floor(e.ticks / 20)
      local label = (potions.EFFECT_LABEL[name] or name) .. ((e.amp or 0) > 0 and " II" or "")
        .. string.format("  %d:%02d", math.floor(secs / 60), secs % 60)
      local tw = gui.textWidth(label)
      g.setColor(0, 0, 0, 0.45)
      g.rectangle("fill", w - tw - 10 * s, y - s, tw + 8 * s, 11 * s)
      gui.text(label, w - tw - 6 * s, y, { 1, 1, 1 })
      y = y + 12 * s
    end
    g.setColor(1, 1, 1, 1)
  end

  -- pasek szybkiego wyboru (182 x 22)
  local hx = math.floor(w / 2 - 91 * s)
  local hy = h - 22 * s
  g.setColor(0, 0, 0, 0.55)
  g.rectangle("fill", hx, hy, 182 * s, 22 * s)
  g.setColor(0.55, 0.55, 0.55, 0.9)
  g.setLineWidth(s)
  g.rectangle("line", hx + s / 2, hy + s / 2, 182 * s - s, 22 * s - s)
  for i = 1, 9 do
    local sx = hx + (i - 1) * 20 * s + s
    g.setColor(0.4, 0.4, 0.4, 0.6)
    g.rectangle("line", sx + s / 2, hy + s + s / 2, 20 * s - s, 20 * s - s)
    local st = game.inventory.slots[i]
    if st then gui.drawStack(st, sx + 2 * s, hy + 3 * s) end
  end
  -- zaznaczony slot
  local sel = hx + (game.selected - 1) * 20 * s - s
  g.setColor(1, 1, 1, 1)
  g.setLineWidth(2 * s)
  g.rectangle("line", sel + s, hy - s + s, 24 * s - 2 * s, 24 * s - 2 * s)
  g.setLineWidth(1)

  local survivalMode = game.player.gameMode ~= "creative"
  if survivalMode then
    -- doświadczenie
    local xy = hy - 7 * s
    g.setColor(0, 0, 0, 0.7)
    g.rectangle("fill", hx, xy, 182 * s, 5 * s)
    g.setColor(0.5, 1, 0.2, 1)
    g.rectangle("fill", hx + s, xy + s, (180 * survival.xpProgress(game)) * s, 3 * s)
    if game.xpLevel > 0 then
      local str = tostring(game.xpLevel)
      local tw = gui.textWidth(str)
      gui.text(str, w / 2 - tw / 2, xy - 9 * s, { 0.5, 1, 0.2 })
    end

    -- serca i głód
    g.setColor(1, 1, 1, 1)
    local iy = hy - 17 * s
    local flash = game.hurtTime > 0 and game.hurtTime % 4 < 2
    local heart = game.effects.poison and sprites.heartPoison or sprites.heart
    local lowHealth = game.health <= 4
    local t = love.timer.getTime()
    drawIcons(heart, sprites.heartHalf, flash and sprites.heartFlash or sprites.heartEmpty,
      game.health, 20, hx, iy, false,
      lowHealth and function(i) return math.floor(math.sin(t * 20 + i * 3) + 0.5) end or nil)
    local foodSprite = game.effects.hunger and sprites.foodHunger or sprites.food
    drawIcons(foodSprite, sprites.foodHalf, sprites.foodEmpty, game.food, 20, hx + 182 * s, iy, true,
      (game.saturation <= 0 and game.time % (game.food * 3 + 1) == 0)
        and function(i) return (i % 2) end or nil)
    -- pancerz
    local armor = survival.armorPoints(game)
    if armor > 0 then
      drawIcons(sprites.armor, sprites.armorHalf, sprites.armorEmpty, armor, 20, hx, iy - 10 * s, false)
    end
    -- powietrze pod wodą
    if game.player.headInWater and game.air < 300 then
      local bubbles = math.ceil(math.max(0, game.air) / 30)
      for i = 0, bubbles - 1 do
        g.draw(sprites.bubble, hx + 182 * s - (i + 1) * 8 * s - s, iy - 10 * s, 0, s, s)
      end
    end
  end

  -- nazwa przedmiotu po zmianie slotu
  local now = love.timer.getTime()
  if M.itemName and now - M.itemNameTime < 2 then
    local a = math.min(1, 2 - (now - M.itemNameTime))
    local tw = gui.textWidth(M.itemName)
    gui.text(M.itemName, w / 2 - tw / 2, hy - (survivalMode and 38 or 14) * s, { 1, 1, 1, a })
  end

  -- komunikaty (czat)
  local my = h - 50 * s
  local f = gui.font()
  for i = #M.messages, 1, -1 do
    local m = M.messages[i]
    local age = now - m.time
    if age < 10 or opts.chatOpen then
      local a = opts.chatOpen and 1 or math.min(1, 10 - age)
      local tw = f:getWidth(m.text)
      g.setColor(0, 0, 0, 0.45 * a)
      g.rectangle("fill", 2 * s, my - s, tw + 4 * s, f:getHeight() + 2 * s)
      local c = m.color or { 1, 1, 1 }
      gui.text(m.text, 4 * s, my, { c[1], c[2], c[3], a })
      my = my - f:getHeight() - 2 * s
    end
  end
  g.setColor(1, 1, 1, 1)
end

-- Ekran debugowania F3
function M.drawDebug(game, info)
  local s = gui.scale
  local f = gui.font()
  local y = 2 * s
  local function line(str, right)
    local g = love.graphics
    local tw = f:getWidth(str)
    local x = right and (g.getWidth() - tw - 4 * s) or 2 * s
    g.setColor(0, 0, 0, 0.45)
    g.rectangle("fill", x - s, y, tw + 2 * s, f:getHeight())
    gui.text(str, x, y)
    y = y + f:getHeight()
  end
  for _, l in ipairs(info.left) do line(l) end
  y = 2 * s
  for _, l in ipairs(info.right) do line(l, true) end
end

M.sprites = sprites
return M
