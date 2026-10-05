-- render/gui.lua
-- Wspólne elementy interfejsu w stylu Minecrafta: skala GUI, panele,
-- sloty, przyciski, suwaki, pola tekstowe, napisy z cieniem, ikony stosów.

local items = require("core.items")
local icons = require("render.icons")

local M = {}

M.scale = 2
M.userScale = 0 -- 0 = automatycznie
local fonts = {}
local hover = { x = -1, y = -1 }

function M.updateScale()
  local w, h = love.graphics.getDimensions()
  local auto = math.max(1, math.min(math.floor(w / 320), math.floor(h / 240)))
  if M.userScale > 0 then
    M.scale = math.min(M.userScale, auto)
  else
    M.scale = math.min(auto, 4)
  end
  return M.scale
end

function M.font(mult)
  mult = mult or 1
  local size = math.max(8, math.floor(7 * M.scale * mult + 0.5))
  local f = fonts[size]
  if not f then
    f = love.graphics.newFont(size)
    f:setFilter("nearest", "nearest")
    fonts[size] = f
  end
  return f
end

-- Napis z cieniem (jak w MC)
function M.text(str, x, y, color, mult, align, width)
  local g = love.graphics
  local f = M.font(mult)
  g.setFont(f)
  local s = math.max(1, math.floor(M.scale * (mult or 1) / 2 + 0.5))
  color = color or { 1, 1, 1 }
  local shadow = { color[1] * 0.25, color[2] * 0.25, color[3] * 0.25, color[4] or 1 }
  if align then
    g.setColor(shadow)
    g.printf(str, x + s, y + s, width, align)
    g.setColor(color)
    g.printf(str, x, y, width, align)
  else
    g.setColor(shadow)
    g.print(str, x + s, y + s)
    g.setColor(color)
    g.print(str, x, y)
  end
  g.setColor(1, 1, 1, 1)
end

function M.textWidth(str, mult)
  return M.font(mult):getWidth(str)
end

-- Panel okna (szary z jasną i ciemną krawędzią)
function M.panel(x, y, w, h)
  local g = love.graphics
  local s = M.scale
  g.setColor(0.0, 0.0, 0.0, 1)
  g.rectangle("fill", x + s, y, w - 2 * s, h)
  g.rectangle("fill", x, y + s, w, h - 2 * s)
  g.setColor(0.776, 0.776, 0.776, 1)
  g.rectangle("fill", x + s, y + s, w - 2 * s, h - 2 * s)
  g.setColor(1, 1, 1, 1)
  g.rectangle("fill", x + s, y + s, w - 3 * s, 2 * s)
  g.rectangle("fill", x + s, y + s, 2 * s, h - 3 * s)
  g.setColor(0.33, 0.33, 0.33, 1)
  g.rectangle("fill", x + 2 * s, y + h - 3 * s, w - 3 * s, 2 * s)
  g.rectangle("fill", x + w - 3 * s, y + 2 * s, 2 * s, h - 3 * s)
  g.setColor(1, 1, 1, 1)
end

-- Slot 18x18 (wklęsły)
function M.slot(x, y, size)
  local g = love.graphics
  local s = M.scale
  size = size or 18 * s
  g.setColor(0.216, 0.216, 0.216, 1)
  g.rectangle("fill", x, y, size - s, size - s)
  g.setColor(1, 1, 1, 1)
  g.rectangle("fill", x + s, y + s, size - s, size - s)
  g.setColor(0.545, 0.545, 0.545, 1)
  g.rectangle("fill", x + s, y + s, size - 2 * s, size - 2 * s)
  g.setColor(1, 1, 1, 1)
end

-- Stos: ikona + liczba + pasek wytrzymałości
function M.drawStack(stack, x, y, size)
  if not stack then return end
  local g = love.graphics
  size = size or 16 * M.scale
  g.setColor(1, 1, 1, 1)
  icons.draw(stack.id, stack.damage, x, y, size)
  local d = items.get(stack.id)
  if d and d.maxDamage and (stack.damage or 0) > 0 then
    local f = 1 - stack.damage / d.maxDamage
    local s = M.scale
    g.setColor(0, 0, 0, 1)
    g.rectangle("fill", x + 2 * s, y + 13 * s, 13 * s, 2 * s)
    g.setColor(1 - f, f, 0, 1)
    g.rectangle("fill", x + 2 * s, y + 13 * s, math.floor(13 * f) * s, s)
    g.setColor(1, 1, 1, 1)
  end
  if stack.count > 1 then
    local str = tostring(stack.count)
    local w = M.textWidth(str)
    local f = M.font()
    M.text(str, x + size - w + M.scale, y + size - f:getHeight() + M.scale * 2)
  end
end

function M.tooltip(lines, mx, my)
  local g = love.graphics
  if type(lines) == "string" then lines = { lines } end
  local f = M.font()
  local w = 0
  for _, l in ipairs(lines) do w = math.max(w, f:getWidth(l)) end
  local s = M.scale
  local h = #lines * (f:getHeight() + s)
  local x, y = mx + 12 * s, my - 12 * s
  local sw = g.getWidth()
  if x + w + 8 * s > sw then x = mx - w - 16 * s end
  if y < 0 then y = 0 end
  g.setColor(0.06, 0, 0.12, 0.94)
  g.rectangle("fill", x - 3 * s, y - 3 * s, w + 6 * s, h + 5 * s)
  g.setColor(0.25, 0.0, 0.5, 1)
  g.setLineWidth(s)
  g.rectangle("line", x - 2 * s, y - 2 * s, w + 4 * s, h + 3 * s)
  for i, l in ipairs(lines) do
    M.text(l, x, y + (i - 1) * (f:getHeight() + s), i == 1 and { 1, 1, 1 } or { 0.65, 0.65, 0.65 })
  end
end

-- ---------------------------------------------------------------------------
-- Przyciski i widżety
-- ---------------------------------------------------------------------------
function M.setMouse(x, y) hover.x, hover.y = x, y end

local function inside(x, y, w, h)
  return hover.x >= x and hover.x < x + w and hover.y >= y and hover.y < y + h
end
M.inside = inside

function M.button(label, x, y, w, h, disabled)
  local g = love.graphics
  local s = M.scale
  local hov = inside(x, y, w, h) and not disabled
  if disabled then g.setColor(0.25, 0.25, 0.25, 1)
  elseif hov then g.setColor(0.45, 0.5, 0.75, 1)
  else g.setColor(0.45, 0.45, 0.45, 1) end
  g.rectangle("fill", x, y, w, h)
  g.setColor(0, 0, 0, 1)
  g.setLineWidth(s)
  g.rectangle("line", x + s / 2, y + s / 2, w - s, h - s)
  g.setColor(1, 1, 1, disabled and 0.1 or 0.35)
  g.rectangle("fill", x + s, y + s, w - 2 * s, s)
  g.setColor(0, 0, 0, 0.35)
  g.rectangle("fill", x + s, y + h - 2 * s, w - 2 * s, s)
  local f = M.font()
  local color = disabled and { 0.6, 0.6, 0.6 } or (hov and { 1, 1, 0.63 } or { 0.88, 0.88, 0.88 })
  M.text(label, x, y + (h - f:getHeight()) / 2, color, 1, "center", w)
  return hov
end

-- Suwak: value 0..1, zwraca nową wartość podczas przeciągania
function M.slider(label, value, x, y, w, h)
  local g = love.graphics
  local s = M.scale
  g.setColor(0.2, 0.2, 0.2, 1)
  g.rectangle("fill", x, y, w, h)
  g.setColor(0, 0, 0, 1)
  g.setLineWidth(s)
  g.rectangle("line", x + s / 2, y + s / 2, w - s, h - s)
  local kx = x + value * (w - 8 * s)
  local hov = inside(x, y, w, h)
  g.setColor(hov and 0.6 or 0.5, hov and 0.65 or 0.5, hov and 0.85 or 0.5, 1)
  g.rectangle("fill", kx, y, 8 * s, h)
  local f = M.font()
  M.text(label, x, y + (h - f:getHeight()) / 2, { 0.9, 0.9, 0.9 }, 1, "center", w)
  return hov
end

function M.sliderValue(x, w, mx)
  local s = M.scale
  local v = (mx - x - 4 * s) / (w - 8 * s)
  if v < 0 then v = 0 elseif v > 1 then v = 1 end
  return v
end

-- Pole tekstowe
function M.textField(text, x, y, w, h, focused, placeholder)
  local g = love.graphics
  local s = M.scale
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", x, y, w, h)
  g.setColor(focused and 1 or 0.63, focused and 1 or 0.63, focused and 1 or 0.63, 1)
  g.setLineWidth(s)
  g.rectangle("line", x + s / 2, y + s / 2, w - s, h - s)
  local f = M.font()
  local shown = text
  if shown == "" and placeholder and not focused then
    M.text(placeholder, x + 4 * s, y + (h - f:getHeight()) / 2, { 0.5, 0.5, 0.5 })
  else
    local caret = (focused and math.floor(love.timer.getTime() * 2) % 2 == 0) and "_" or ""
    M.text(shown .. caret, x + 4 * s, y + (h - f:getHeight()) / 2, { 0.9, 0.9, 0.9 })
  end
  return inside(x, y, w, h)
end

-- Tło menu: przyciemnione kafelki ziemi (jak ekrany opcji w MC)
local dirtImg
function M.dirtBackground(atlasImage, quad)
  local g = love.graphics
  local w, h = g.getDimensions()
  local size = 32 * M.scale / 2 * 2
  if quad then
    g.setColor(0.25, 0.25, 0.25, 1)
    for y = 0, h, size do
      for x = 0, w, size do
        g.draw(atlasImage, quad, x, y, 0, size / 16, size / 16)
      end
    end
    g.setColor(1, 1, 1, 1)
  else
    g.clear(0.15, 0.12, 0.1)
  end
  local _ = dirtImg
end

return M
