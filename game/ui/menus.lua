-- ui/menus.lua
-- Proste ekrany w trakcie gry: pauza, opcje, śmierć, czat.
-- Każdy ekran ma: draw(), mousepressed(), mousereleased(), keypressed(),
-- textinput(), close(). Akcje zgłasza przez callback onAction(nazwa).

local gui = require("render.gui")
local options = require("core.options")
local sound = require("render.sound")

local M = {}

local function centerButtons(count, bw, bh, gap, startY)
  local s = gui.scale
  local w, h = love.graphics.getDimensions()
  local list = {}
  local total = count * bh + (count - 1) * gap
  local y0 = startY or (h / 2 - total * s / 2)
  for i = 1, count do
    list[i] = { x = math.floor(w / 2 - bw * s / 2), y = math.floor(y0 + (i - 1) * (bh + gap) * s),
      w = bw * s, h = bh * s }
  end
  return list
end

local function hit(b, x, y) return x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h end

-- ---------------------------------------------------------------------------
-- Pauza
-- ---------------------------------------------------------------------------
local Pause = {}
Pause.__index = Pause

-- net: nil (gra jednoosobowa), "host" (serwer LAN działa), "client" (gość)
-- info: dodatkowa linia pod tytułem (np. adres serwera)
function M.pause(onAction, net, info)
  local labels = { "Wroc do gry", "Opcje..." }
  local actions = { "resume", "options" }
  if not net then
    labels[#labels + 1] = "Otworz w sieci LAN"
    actions[#actions + 1] = "lan"
  end
  labels[#labels + 1] = net == "client" and "Rozlacz" or "Zapisz i wyjdz do menu"
  actions[#actions + 1] = "quit"
  return setmetatable({ onAction = onAction, pausesGame = true, labels = labels, actions = actions,
    info = info }, Pause)
end

function Pause:draw()
  local g = love.graphics
  local w, h = g.getDimensions()
  gui.setMouse(love.mouse.getPosition())
  g.setColor(0, 0, 0, 0.55)
  g.rectangle("fill", 0, 0, w, h)
  local s = gui.scale
  gui.text("Menu gry", 0, h / 2 - 70 * s, nil, 1.3, "center", w)
  if self.info then
    local y = h / 2 - 56 * s
    for line in self.info:gmatch("[^\n]+") do
      gui.text(line, 0, y, { 0.6, 1, 0.6 }, 0.9, "center", w)
      y = y + 10 * s
    end
  end
  self.buttons = centerButtons(#self.labels, 200, 20, 4, h / 2 - 40 * s)
  for i, b in ipairs(self.buttons) do gui.button(self.labels[i], b.x, b.y, b.w, b.h) end
  gui.text("WSAD - ruch, spacja - skok, shift - kucanie, ctrl - sprint, E - ekwipunek",
    0, h - 40 * s, { 0.7, 0.7, 0.7 }, 0.8, "center", w)
  gui.text("Q - wyrzuc, T - czat, F1 - ukryj HUD, F2 - zrzut ekranu, F3 - debug, F5 - kamera",
    0, h - 28 * s, { 0.7, 0.7, 0.7 }, 0.8, "center", w)
end

function Pause:mousepressed(x, y, b)
  if b ~= 1 or not self.buttons then return end
  for i, btn in ipairs(self.buttons) do
    if hit(btn, x, y) then
      sound.play("click")
      self.onAction(self.actions[i])
      return
    end
  end
end

function Pause:keypressed(key)
  if key == "escape" then self.onAction("resume") end
  return true
end

-- ---------------------------------------------------------------------------
-- Opcje
-- ---------------------------------------------------------------------------
local Options = {}
Options.__index = Options

local DIFF = { [0] = "Spokojny", "Latwy", "Normalny", "Trudny" }

function M.options(onChange, onClose, background)
  local self = setmetatable({ onChange = onChange, onClose = onClose, background = background,
    pausesGame = true }, Options)
  self.items = {
    { kind = "slider", key = "renderDistance", min = 2, max = 16, step = 1,
      label = function(v) return "Zasieg widzenia: " .. v .. " chunkow" end },
    { kind = "slider", key = "fov", min = 50, max = 110, step = 1,
      label = function(v) return "Pole widzenia: " .. v end },
    { kind = "slider", key = "sensitivity", min = 0, max = 1, step = 0.01,
      label = function(v) return "Czulosc myszy: " .. math.floor(v * 200) .. "%" end },
    { kind = "slider", key = "volume", min = 0, max = 1, step = 0.01,
      label = function(v) return "Glosnosc: " .. math.floor(v * 100) .. "%" end },
    { kind = "cycle", key = "guiScale", values = { 0, 1, 2, 3, 4 },
      label = function(v) return "Skala GUI: " .. (v == 0 and "Auto" or v) end },
    { kind = "cycle", key = "difficulty", values = { 0, 1, 2, 3 },
      label = function(v) return "Poziom trudnosci: " .. DIFF[v] end },
    { kind = "toggle", key = "viewBobbing", label = function(v) return "Kolysanie kamery: " .. (v and "Wl" or "Wyl") end },
    { kind = "toggle", key = "clouds", label = function(v) return "Chmury: " .. (v and "Wl" or "Wyl") end },
    { kind = "toggle", key = "showFps", label = function(v) return "Licznik FPS: " .. (v and "Wl" or "Wyl") end },
    { kind = "toggle", key = "invertMouse", label = function(v) return "Odwroc mysz: " .. (v and "Wl" or "Wyl") end },
  }
  return self
end

function Options:layout()
  local s = gui.scale
  local w, h = love.graphics.getDimensions()
  local cols = 2
  local bw, bh = 150, 20
  local rows = math.ceil(#self.items / cols)
  local total = rows * (bh + 4)
  local y0 = math.max(30 * s, h / 2 - total * s / 2 - 10 * s)
  for i, it in ipairs(self.items) do
    local c = (i - 1) % cols
    local r = math.floor((i - 1) / cols)
    it.x = math.floor(w / 2 + (c == 0 and -(bw + 2) or 2) * s)
    it.y = math.floor(y0 + r * (bh + 4) * s)
    it.w, it.h = bw * s, bh * s
  end
  self.done = { x = math.floor(w / 2 - 100 * s), y = math.floor(y0 + (rows * (bh + 4) + 8) * s),
    w = 200 * s, h = 20 * s }
end

function Options:draw()
  local g = love.graphics
  local w = g.getWidth()
  gui.setMouse(love.mouse.getPosition())
  if self.background then self.background() else
    g.setColor(0, 0, 0, 0.6)
    g.rectangle("fill", 0, 0, w, g.getHeight())
  end
  self:layout()
  local s = gui.scale
  gui.text("Opcje", 0, 10 * s, nil, 1.3, "center", w)
  for _, it in ipairs(self.items) do
    local v = options.values[it.key]
    if it.kind == "slider" then
      gui.slider(it.label(v), (v - it.min) / (it.max - it.min), it.x, it.y, it.w, it.h)
    else
      gui.button(it.label(v), it.x, it.y, it.w, it.h)
    end
  end
  gui.button("Gotowe", self.done.x, self.done.y, self.done.w, self.done.h)
end

function Options:setSlider(it, mx)
  local f = gui.sliderValue(it.x, it.w, mx)
  local v = it.min + f * (it.max - it.min)
  v = math.floor(v / it.step + 0.5) * it.step
  if it.step >= 1 then v = math.floor(v + 0.5) end
  if options.values[it.key] ~= v then
    options.values[it.key] = v
    self.onChange(it.key, v)
  end
end

function Options:mousepressed(x, y, b)
  if b ~= 1 then return end
  self:layout()
  for _, it in ipairs(self.items) do
    if hit(it, x, y) then
      if it.kind == "slider" then
        self.dragging = it
        self:setSlider(it, x)
      elseif it.kind == "toggle" then
        options.values[it.key] = not options.values[it.key]
        self.onChange(it.key, options.values[it.key])
        sound.play("click")
      elseif it.kind == "cycle" then
        local cur = options.values[it.key]
        local idx = 1
        for k, v in ipairs(it.values) do if v == cur then idx = k end end
        idx = idx % #it.values + 1
        options.values[it.key] = it.values[idx]
        self.onChange(it.key, it.values[idx])
        sound.play("click")
      end
      return
    end
  end
  if hit(self.done, x, y) then
    sound.play("click")
    self.onClose()
  end
end

function Options:mousemoved(x)
  if self.dragging then self:setSlider(self.dragging, x) end
end

function Options:mousereleased()
  self.dragging = nil
end

function Options:keypressed(key)
  if key == "escape" then self.onClose() end
  return true
end

-- ---------------------------------------------------------------------------
-- Ekran śmierci
-- ---------------------------------------------------------------------------
local Death = {}
Death.__index = Death

function M.death(game, onAction)
  return setmetatable({ game = game, onAction = onAction, time = love.timer.getTime() }, Death)
end

function Death:draw()
  local g = love.graphics
  local w, h = g.getDimensions()
  local s = gui.scale
  gui.setMouse(love.mouse.getPosition())
  g.setColor(0.45, 0, 0, 0.55)
  g.rectangle("fill", 0, 0, w, h)
  gui.text(self.game.hardcore and "Koniec gry!" or "Zginales!", 0, h / 4, nil, 2, "center", w)
  gui.text(self.game.deathMessage or "", 0, h / 4 + 30 * s, nil, 1, "center", w)
  gui.text("Wynik: " .. (self.game.stats.lastScore or 0), 0, h / 4 + 45 * s, { 1, 1, 0.3 }, 1, "center", w)
  local labels = self.game.hardcore and { "Usun swiat i wyjdz" } or { "Odrodz sie", "Menu glowne" }
  self.actions = self.game.hardcore and { "delete" } or { "respawn", "quit" }
  self.buttons = centerButtons(#labels, 200, 20, 4, h / 2 + 10 * s)
  local ready = love.timer.getTime() - self.time > 1
  for i, b in ipairs(self.buttons) do gui.button(labels[i], b.x, b.y, b.w, b.h, not ready) end
end

function Death:mousepressed(x, y, b)
  if b ~= 1 or not self.buttons or love.timer.getTime() - self.time < 1 then return end
  for i, btn in ipairs(self.buttons) do
    if hit(btn, x, y) then
      sound.play("click")
      self.onAction(self.actions[i])
      return
    end
  end
end

function Death:keypressed() return true end

-- ---------------------------------------------------------------------------
-- Czat / komendy
-- ---------------------------------------------------------------------------
local Chat = {}
Chat.__index = Chat

M.chatHistory = {}

function M.chat(onSend, onClose, initial)
  love.keyboard.setKeyRepeat(true)
  return setmetatable({ text = initial or "", onSend = onSend, onClose = onClose,
    historyIndex = #M.chatHistory + 1, skipFirst = true }, Chat)
end

function Chat:draw()
  local g = love.graphics
  local w, h = g.getDimensions()
  local s = gui.scale
  local f = gui.font()
  g.setColor(0, 0, 0, 0.6)
  g.rectangle("fill", 2 * s, h - 14 * s, w - 4 * s, 12 * s)
  local caret = math.floor(love.timer.getTime() * 2) % 2 == 0 and "_" or ""
  gui.text(self.text .. caret, 4 * s, h - 14 * s + (12 * s - f:getHeight()) / 2)
end

function Chat:textinput(t)
  if self.skipFirst then
    self.skipFirst = false
    if t == "t" or t == "T" or t == "/" then return end
  end
  self.text = self.text .. t
end

function Chat:keypressed(key)
  if key == "escape" then
    love.keyboard.setKeyRepeat(false)
    self.onClose()
  elseif key == "return" or key == "kpenter" then
    love.keyboard.setKeyRepeat(false)
    if self.text ~= "" then
      M.chatHistory[#M.chatHistory + 1] = self.text
      self.onSend(self.text)
    end
    self.onClose()
  elseif key == "backspace" then
    self.text = self.text:sub(1, -2)
  elseif key == "up" then
    if self.historyIndex > 1 then
      self.historyIndex = self.historyIndex - 1
      self.text = M.chatHistory[self.historyIndex] or ""
    end
  elseif key == "down" then
    if self.historyIndex <= #M.chatHistory then
      self.historyIndex = self.historyIndex + 1
      self.text = M.chatHistory[self.historyIndex] or ""
    end
  end
  return true
end

return M
