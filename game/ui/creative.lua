-- ui/creative.lua
-- Ekwipunek trybu kreatywnego: siatka wszystkich bloków i przedmiotów
-- (przewijana kółkiem) + pasek szybkiego wyboru. Kliknięcie bierze pełny stos.

local Container = require("core.container")
local blocks = require("core.blocks")
local items = require("core.items")
local gui = require("render.gui")

local M = {}

local Screen = {}
Screen.__index = Screen

local COLS, ROWS = 9, 5

-- Lista wszystkich przedmiotów do wyboru (z wariantami)
local catalog
local function buildCatalog()
  catalog = {}
  local skip = { [0] = true, [8] = true, [10] = true, [26] = true, [51] = true, [59] = true,
    [62] = true, [64] = true }
  for id = 1, 255 do
    local d = blocks.defs[id]
    if d and not skip[id] then
      if d.metaMask and d.metaMask > 0 then
        local variants = (d.name == "wool") and 6 or 3
        for m = 0, variants - 1 do catalog[#catalog + 1] = { id = id, damage = m } end
      else
        catalog[#catalog + 1] = { id = id, damage = 0 }
      end
    end
  end
  local ids = {}
  for id in pairs(items.defs) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    if id == 351 then
      for _, dmg in ipairs({ 15, 4, 1, 2, 3, 11 }) do catalog[#catalog + 1] = { id = id, damage = dmg } end
    elseif id == 263 then
      catalog[#catalog + 1] = { id = id, damage = 0 }
      catalog[#catalog + 1] = { id = id, damage = 1 }
    else
      catalog[#catalog + 1] = { id = id, damage = 0 }
    end
  end
end

function M.new(game)
  if not catalog then buildCatalog() end
  local self = setmetatable({}, Screen)
  self.game = game
  self.scroll = 0
  self.w, self.h = 176, 150
  local slots = {}
  for c = 0, 8 do
    slots[#slots + 1] = { inv = game.inventory, i = 1 + c, group = "hotbar", gx = 8 + c * 18, gy = 126 }
  end
  self.container = Container.new(slots, {})
  game.uiOpen = true
  return self
end

function Screen:layout()
  local s = gui.scale
  local w, h = love.graphics.getDimensions()
  self.px = math.floor((w - self.w * s) / 2)
  self.py = math.floor((h - self.h * s) / 2)
  return self.px, self.py, s
end

local function maxScroll()
  return math.max(0, math.ceil(#catalog / COLS) - ROWS)
end

function Screen:gridAt(mx, my)
  local px, py, s = self:layout()
  for r = 0, ROWS - 1 do
    for c = 0, COLS - 1 do
      local x, y = px + (8 + c * 18) * s, py + (18 + r * 18) * s
      if mx >= x - s and mx < x + 17 * s and my >= y - s and my < y + 17 * s then
        return catalog[(self.scroll + r) * COLS + c + 1]
      end
    end
  end
  return nil
end

function Screen:slotAt(mx, my)
  local px, py, s = self:layout()
  for n, sl in ipairs(self.container.slots) do
    local x, y = px + sl.gx * s, py + sl.gy * s
    if mx >= x - s and mx < x + 17 * s and my >= y - s and my < y + 17 * s then return n, sl end
  end
end

function Screen:draw()
  local g = love.graphics
  local mx, my = love.mouse.getPosition()
  local w, h = g.getDimensions()
  g.setColor(0, 0, 0, 0.55)
  g.rectangle("fill", 0, 0, w, h)
  local px, py, s = self:layout()
  gui.panel(px, py, self.w * s, self.h * s)
  g.setFont(gui.font())
  g.setColor(0.25, 0.25, 0.25)
  g.print("Tryb kreatywny  (kolko myszy: przewijanie)", px + 8 * s, py + 6 * s)
  g.setColor(1, 1, 1)
  local hoverItem = self:gridAt(mx, my)
  for r = 0, ROWS - 1 do
    for c = 0, COLS - 1 do
      local x, y = px + (8 + c * 18) * s, py + (18 + r * 18) * s
      gui.slot(x - s, y - s)
      local it = catalog[(self.scroll + r) * COLS + c + 1]
      if it then
        gui.drawStack({ id = it.id, count = 1, damage = it.damage }, x, y)
        if it == hoverItem then
          g.setColor(1, 1, 1, 0.45)
          g.rectangle("fill", x, y, 16 * s, 16 * s)
          g.setColor(1, 1, 1)
        end
      end
    end
  end
  -- pasek przewijania
  local ms = maxScroll()
  local bx, by = px + 172 * s - 6 * s, py + 18 * s
  g.setColor(0.4, 0.4, 0.4)
  g.rectangle("fill", bx, by, 4 * s, ROWS * 18 * s)
  local kh = ROWS * 18 * s * (ROWS / (ms + ROWS))
  local ky = by + (ROWS * 18 * s - kh) * (ms > 0 and self.scroll / ms or 0)
  g.setColor(0.85, 0.85, 0.85)
  g.rectangle("fill", bx, ky, 4 * s, kh)
  g.setColor(1, 1, 1)

  local hs = self:slotAt(mx, my)
  for n, sl in ipairs(self.container.slots) do
    local x, y = px + sl.gx * s, py + sl.gy * s
    gui.slot(x - s, y - s)
    local st = sl.inv.slots[sl.i]
    if st then gui.drawStack(st, x, y) end
    if n == hs then
      g.setColor(1, 1, 1, 0.45)
      g.rectangle("fill", x, y, 16 * s, 16 * s)
      g.setColor(1, 1, 1)
    end
  end
  local cur = self.container.cursor
  if cur then
    gui.drawStack(cur, mx - 8 * s, my - 8 * s)
  elseif hoverItem then
    gui.tooltip(items.label({ id = hoverItem.id, count = 1, damage = hoverItem.damage }), mx, my)
  elseif hs then
    local st = self.container.slots[hs].inv.slots[self.container.slots[hs].i]
    if st then gui.tooltip(items.label(st), mx, my) end
  end
end

function Screen:mousepressed(x, y, button)
  local c = self.container
  local it = self:gridAt(x, y)
  if it then
    if c.cursor then
      c.cursor = nil -- odłożenie do katalogu = usunięcie
    else
      local shift = love.keyboard.isDown("lshift", "rshift")
      local n = button == 2 and 1 or items.maxStack(it.id)
      local stack = { id = it.id, count = n, damage = it.damage }
      if shift then
        self.game.inventory:add(stack)
      else
        c.cursor = stack
      end
    end
    return
  end
  local n = self:slotAt(x, y)
  if n then
    c:click(n, button == 2 and "right" or "left", love.keyboard.isDown("lshift", "rshift"))
    return
  end
  local px, py, s = self:layout()
  if (x < px or y < py or x > px + self.w * s or y > py + self.h * s) and c.cursor then
    self.game:throwStack(c.cursor)
    c.cursor = nil
  end
end

function Screen:wheelmoved(_, dy)
  self.scroll = math.max(0, math.min(maxScroll(), self.scroll - dy))
end

function Screen:keypressed(key)
  local mx, my = love.mouse.getPosition()
  local num = tonumber(key)
  local it = self:gridAt(mx, my)
  if num and num >= 1 and num <= 9 and it then
    self.game.inventory:set(num, { id = it.id, count = items.maxStack(it.id), damage = it.damage })
    return true
  end
  return false
end

function Screen:close()
  self.container.cursor = nil
  self.game.uiOpen = false
end

return M
