-- ui/containerscreen.lua
-- Okna z slotami: ekwipunek gracza (z craftingiem 2x2 i pancerzem),
-- stół rzemieślniczy (3x3), skrzynia (27 / 54 sloty), piec.
-- Obsługa myszy: klik lewy/prawy, shift-klik, przeciąganie (rozkładanie),
-- klawisz Q (wyrzuć), 1-9 (zamiana z paskiem szybkiego wyboru).

local Container = require("core.container")
local Inventory = require("core.inventory")
local items = require("core.items")
local furnace = require("core.furnace")
local gui = require("render.gui")
local sound = require("render.sound")

local M = {}

local Screen = {}
Screen.__index = Screen

-- Sloty ekwipunku gracza (plecak + pasek) na pozycji y0 (piksele GUI)
local function playerSlots(game, list, y0)
  for r = 0, 2 do
    for c = 0, 8 do
      list[#list + 1] = { inv = game.inventory, i = 10 + r * 9 + c, group = "main",
        gx = 8 + c * 18, gy = y0 + r * 18 }
    end
  end
  for c = 0, 8 do
    list[#list + 1] = { inv = game.inventory, i = 1 + c, group = "hotbar",
      gx = 8 + c * 18, gy = y0 + 58 }
  end
end

-- Otwiera okno danego rodzaju. pos = {x,y,z} bloku (stół, skrzynia, piec)
function M.new(game, kind, pos)
  local self = setmetatable({}, Screen)
  self.game = game
  self.kind = kind
  self.pos = pos
  self.w, self.h = 176, 166
  local slots = {}
  local opts = {}

  if kind == "inventory" then
    self.title = "Wytwarzanie"
    for a = 1, 4 do
      slots[#slots + 1] = { inv = game.armor, i = a, group = "armor", armor = a, gx = 8, gy = 8 + (a - 1) * 18 }
    end
    self.craftInv = Inventory.new(5)
    for r = 0, 1 do
      for c = 0, 1 do
        slots[#slots + 1] = { inv = self.craftInv, i = 1 + r * 2 + c, group = "craft",
          gx = 88 + c * 18, gy = 26 + r * 18 }
      end
    end
    slots[#slots + 1] = { inv = self.craftInv, i = 5, group = "result", gx = 144, gy = 36 }
    opts.craftSize = 2
    playerSlots(game, slots, 84)
  elseif kind == "crafting" then
    self.title = "Wytwarzanie"
    self.craftInv = Inventory.new(10)
    for r = 0, 2 do
      for c = 0, 2 do
        slots[#slots + 1] = { inv = self.craftInv, i = 1 + r * 3 + c, group = "craft",
          gx = 30 + c * 18, gy = 17 + r * 18 }
      end
    end
    slots[#slots + 1] = { inv = self.craftInv, i = 10, group = "result", gx = 124, gy = 35 }
    opts.craftSize = 3
    playerSlots(game, slots, 84)
  elseif kind == "chest" then
    local invs = {}
    local main = game:getOrCreateTile(pos[1], pos[2], pos[3])
    -- podwójna skrzynia: szukamy sąsiedniej skrzyni
    local other
    for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
      local nx, nz = pos[1] + d[1], pos[3] + d[2]
      if game.world:getBlock(nx, pos[2], nz) == 54 then
        other = { game:getOrCreateTile(nx, pos[2], nz), d[1] + d[2] }
        break
      end
    end
    if other and other[1] then
      if other[2] < 0 then invs = { other[1].inventory, main.inventory }
      else invs = { main.inventory, other[1].inventory } end
      self.title = "Duza skrzynia"
    else
      invs = { main.inventory }
      self.title = "Skrzynia"
    end
    local rows = #invs * 3
    for k, inv in ipairs(invs) do
      for r = 0, 2 do
        for c = 0, 8 do
          slots[#slots + 1] = { inv = inv, i = 1 + r * 9 + c, group = "chest",
            gx = 8 + c * 18, gy = 18 + ((k - 1) * 3 + r) * 18 }
        end
      end
    end
    self.h = 114 + rows * 18
    playerSlots(game, slots, 32 + rows * 18)
    opts.shift = { chest = { "hotbar", "main" }, hotbar = { "chest" }, main = { "chest" } }
    sound.play("door", pos[1] + 0.5, pos[2] + 0.5, pos[3] + 0.5, 0.6)
  elseif kind == "furnace" then
    self.title = "Piec"
    self.tile = game:getOrCreateTile(pos[1], pos[2], pos[3])
    local inv = self.tile.inventory
    slots[#slots + 1] = { inv = inv, i = 1, group = "input", gx = 56, gy = 17 }
    slots[#slots + 1] = { inv = inv, i = 2, group = "fuel", gx = 56, gy = 53 }
    slots[#slots + 1] = { inv = inv, i = 3, group = "output", gx = 116, gy = 35 }
    playerSlots(game, slots, 84)
    opts.shift = { output = { "hotbar", "main" }, input = { "hotbar", "main" }, fuel = { "hotbar", "main" },
      hotbar = { "input" }, main = { "input" } }
    local tile = self.tile
    opts.onTake = function(_, n)
      if n > 0 then
        local xp = furnace.takeXp(tile)
        if xp > 0 then game:addXp(xp) end
      end
    end
    -- paliwo shift-klikiem trafia do slotu paliwa
    self.fuelAware = true
  end

  opts.onOverflow = function(stack) game:giveItem(stack) end
  opts.onCraft = function(stack)
    game.stats.crafted = (game.stats.crafted or 0) + (stack.count or 1)
    sound.play("click", nil, nil, nil, 0.3)
  end
  self.container = Container.new(slots, opts)
  self.drag = nil
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

function Screen:slotAt(mx, my)
  local px, py, s = self:layout()
  for n, sl in ipairs(self.container.slots) do
    local x, y = px + sl.gx * s, py + sl.gy * s
    if mx >= x - s and mx < x + 17 * s and my >= y - s and my < y + 17 * s then return n, sl end
  end
  return nil
end

-- Steve w okienku ekwipunku (prosty rysunek)
local function drawPlayerFigure(x, y, s)
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", x, y, 52 * s, 72 * s)
  local cx = x + 26 * s
  local function R(px, py, pw, ph, c)
    g.setColor(c[1], c[2], c[3], 1)
    g.rectangle("fill", cx + px * s, y + py * s, pw * s, ph * s)
  end
  R(-6, 6, 12, 12, { 0.55, 0.38, 0.27 })     -- głowa
  R(-6, 6, 12, 4, { 0.25, 0.17, 0.1 })       -- włosy
  R(-4, 12, 2, 2, { 1, 1, 1 }); R(2, 12, 2, 2, { 1, 1, 1 })
  R(-3, 12, 1, 2, { 0.3, 0.2, 0.6 }); R(3, 12, 1, 2, { 0.3, 0.2, 0.6 })
  R(-6, 18, 12, 18, { 0.0, 0.65, 0.65 })     -- koszula
  R(-10, 18, 4, 18, { 0.0, 0.6, 0.6 }); R(6, 18, 4, 18, { 0.0, 0.6, 0.6 })
  R(-10, 32, 4, 4, { 0.55, 0.38, 0.27 }); R(6, 32, 4, 4, { 0.55, 0.38, 0.27 })
  R(-6, 36, 6, 18, { 0.25, 0.2, 0.6 }); R(0, 36, 6, 18, { 0.22, 0.18, 0.55 })
  R(-6, 54, 6, 4, { 0.35, 0.35, 0.35 }); R(0, 54, 6, 4, { 0.35, 0.35, 0.35 })
  g.setColor(1, 1, 1, 1)
end

function Screen:draw()
  local g = love.graphics
  local mx, my = love.mouse.getPosition()
  gui.setMouse(mx, my)
  local w, h = g.getDimensions()
  g.setColor(0, 0, 0, 0.55)
  g.rectangle("fill", 0, 0, w, h)
  local px, py, s = self:layout()
  gui.panel(px, py, self.w * s, self.h * s)
  local dark = { 0.25, 0.25, 0.25 }
  local function label(t, x, y)
    g.setFont(gui.font())
    g.setColor(dark)
    g.print(t, px + x * s, py + y * s)
    g.setColor(1, 1, 1)
  end
  if self.kind == "inventory" then
    drawPlayerFigure(px + 26 * s, py + 8 * s, s)
    label(self.title, 86, 14)
  elseif self.kind == "chest" then
    label(self.title, 8, 6)
    label("Ekwipunek", 8, self.h - 94)
  else
    label(self.title, self.kind == "furnace" and 66 or 28, 6)
    label("Ekwipunek", 8, 72)
  end

  -- strzałka craftingu
  if self.kind == "inventory" or self.kind == "crafting" then
    local ax = self.kind == "inventory" and 124 or 90
    local ay = self.kind == "inventory" and 36 or 35
    g.setColor(0.55, 0.55, 0.55, 1)
    g.rectangle("fill", px + (ax + 2) * s, py + (ay + 7) * s, 14 * s, 3 * s)
    g.polygon("fill", px + (ax + 15) * s, py + (ay + 4) * s, px + (ax + 21) * s, py + (ay + 8.5) * s,
      px + (ax + 15) * s, py + (ay + 13) * s)
    g.setColor(1, 1, 1)
  end

  -- piec: płomień i postęp
  if self.kind == "furnace" then
    local t = self.tile
    local fx, fy = px + 57 * s, py + 37 * s
    g.setColor(0.55, 0.55, 0.55, 1)
    g.rectangle("fill", fx, fy, 14 * s, 13 * s)
    if t.burn > 0 and t.burnMax > 0 then
      local f = t.burn / t.burnMax
      g.setColor(1, 0.55, 0.1, 1)
      g.rectangle("fill", fx, fy + (1 - f) * 13 * s, 14 * s, f * 13 * s)
    end
    local ax, ay = px + 79 * s, py + 35 * s
    g.setColor(0.55, 0.55, 0.55, 1)
    g.rectangle("fill", ax, ay + 6 * s, 22 * s, 5 * s)
    local prog = t.cook / furnace.COOK_TIME
    g.setColor(1, 1, 1, 1)
    g.rectangle("fill", ax, ay + 6 * s, 22 * s * prog, 5 * s)
    g.setColor(1, 1, 1)
  end

  -- sloty
  local hovered = self:slotAt(mx, my)
  for n, sl in ipairs(self.container.slots) do
    local x, y = px + sl.gx * s, py + sl.gy * s
    local size = sl.group == "result" or sl.group == "output"
    if size then
      gui.slot(x - 5 * s, y - 5 * s, 26 * s)
    else
      gui.slot(x - s, y - s)
    end
    local st = sl.inv.slots[sl.i]
    if st then
      gui.drawStack(st, x, y)
    elseif sl.group == "armor" then
      -- puste sloty pancerza: zarys
      g.setColor(0.4, 0.4, 0.4, 0.6)
      g.rectangle("line", x + 3 * s, y + 3 * s, 10 * s, 10 * s)
      g.setColor(1, 1, 1)
    end
    if n == hovered then
      g.setColor(1, 1, 1, 0.45)
      g.rectangle("fill", x, y, 16 * s, 16 * s)
      g.setColor(1, 1, 1)
    end
    if self.drag and self.drag.set[n] and #self.drag.list > 1 then
      g.setColor(1, 1, 1, 0.3)
      g.rectangle("fill", x, y, 16 * s, 16 * s)
      g.setColor(1, 1, 1)
    end
  end

  -- kursor
  local cur = self.container.cursor
  if cur then
    gui.drawStack(cur, mx - 8 * s, my - 8 * s)
  elseif hovered then
    local st = self.container.slots[hovered].inv.slots[self.container.slots[hovered].i]
    if st then
      local lines = { items.label(st) }
      local d = items.get(st.id)
      if d and d.maxDamage then
        lines[2] = string.format("Wytrzymalosc: %d / %d", d.maxDamage - (st.damage or 0), d.maxDamage)
      end
      if d and d.armor then lines[#lines + 1] = "Ochrona: +" .. d.armor.points end
      if d and d.food then lines[#lines + 1] = "Glod: +" .. d.food.hunger end
      gui.tooltip(lines, mx, my)
    end
  end
end

function Screen:mousepressed(x, y, button)
  local b = button == 1 and "left" or (button == 2 and "right" or nil)
  if not b then return end
  local n, sl = self:slotAt(x, y)
  local c = self.container
  local shift = love.keyboard.isDown("lshift", "rshift")
  if not n then
    -- kliknięcie poza oknem: wyrzucenie przedmiotu z kursora
    local px, py, s = self:layout()
    local outside = x < px or y < py or x > px + self.w * s or y > py + self.h * s
    if outside and c.cursor then
      if b == "left" then
        self.game:throwStack(c.cursor)
        c.cursor = nil
      else
        self.game:throwStack({ id = c.cursor.id, count = 1, damage = c.cursor.damage })
        c.cursor.count = c.cursor.count - 1
        if c.cursor.count <= 0 then c.cursor = nil end
      end
    end
    return
  end
  -- paliwo: shift-klik paliwa z ekwipunku do slotu paliwa
  if self.kind == "furnace" and shift and (sl.group == "main" or sl.group == "hotbar") then
    local st = sl.inv.slots[sl.i]
    if st and items.fuelTime(st) > 0 and not require("core.recipes").smeltResult(st) then
      local left = c:moveToGroups(st, { "fuel" })
      if left <= 0 then sl.inv.slots[sl.i] = nil end
      return
    end
  end
  if c.cursor and not shift and sl.group ~= "result" and sl.group ~= "output" then
    -- może to początek przeciągania - decyzja przy puszczeniu
    self.drag = { button = b, list = { n }, set = { [n] = true } }
    return
  end
  c:click(n, b, shift)
  sound.play("click", nil, nil, nil, 0.15)
end

function Screen:mousemoved(x, y)
  if self.drag then
    local n = self:slotAt(x, y)
    if n and not self.drag.set[n] then
      local sl = self.container.slots[n]
      if sl.group ~= "result" and sl.group ~= "output" then
        self.drag.set[n] = true
        self.drag.list[#self.drag.list + 1] = n
      end
    end
  end
end

function Screen:mousereleased(x, y, button)
  local d = self.drag
  if not d then return end
  self.drag = nil
  if #d.list == 1 then
    self.container:click(d.list[1], d.button, false)
  else
    self.container:distribute(d.list, d.button)
  end
  sound.play("click", nil, nil, nil, 0.15)
end

function Screen:keypressed(key)
  local mx, my = love.mouse.getPosition()
  local n, sl = self:slotAt(mx, my)
  if key == "q" and n and not self.container.cursor then
    local st = sl.inv.slots[sl.i]
    if st and sl.group ~= "result" then
      local all = love.keyboard.isDown("lctrl", "rctrl")
      local k = all and st.count or 1
      self.game:throwStack({ id = st.id, count = k, damage = st.damage })
      st.count = st.count - k
      if st.count <= 0 then sl.inv.slots[sl.i] = nil end
      if sl.group == "craft" then self.container:updateCrafting() end
    end
    return true
  end
  local num = tonumber(key)
  if num and num >= 1 and num <= 9 and n and sl.group ~= "result" and sl.group ~= "output" then
    local inv = self.game.inventory
    local a = sl.inv.slots[sl.i]
    local b = inv.slots[num]
    if sl.group == "armor" and b and not self.container:accepts(sl, b) then return true end
    sl.inv.slots[sl.i] = b
    inv.slots[num] = a
    sl.inv.changed, inv.changed = true, true
    if sl.group == "craft" then self.container:updateCrafting() end
    return true
  end
  return false
end

function Screen:close()
  local game = self.game
  self.container:close(function(stack) game:giveItem(stack) end)
  game.uiOpen = false
  if self.kind == "chest" and self.pos then
    sound.play("door", self.pos[1] + 0.5, self.pos[2] + 0.5, self.pos[3] + 0.5, 0.5)
  end
end

return M
