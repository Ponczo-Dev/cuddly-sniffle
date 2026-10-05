-- states/menu.lua
-- Menu główne: tytuł, lista światów, tworzenie nowego świata
-- (nazwa, ziarno, tryb gry), usuwanie, opcje.

local renderInit = require("render.init")
local gui = require("render.gui")
local atlas = require("render.atlas")
local tiles = require("core.tiles")
local save = require("core.save")
local options = require("core.options")
local fs = require("core.fs")
local sound = require("render.sound")
local menus = require("ui.menus")

local Menu = {}

local SPLASHES = {
  "Teraz w Lua!", "Bez admina!", "100% proceduralne!", "Beta 1.8!", "Tez sprobuj Terraria!",
  "Kop i buduj!", "Uwaga na creepery!", "Pikselowe!", "Zrobione w LOVE!", "Nieskonczony swiat!",
}

local function hit(b, x, y) return b and x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h end

function Menu:enter(params)
  renderInit.load()
  params = params or {}
  self.manager = params.manager
  self.page = "title"
  self.splash = SPLASHES[math.random(1, #SPLASHES)]
  self.worlds = save.listWorlds()
  self.selected = nil
  self.newName = "Nowy swiat"
  self.newSeed = ""
  self.newMode = 1
  self.focus = "name"
  self.lastClick = 0
  self.time = 0
  love.mouse.setRelativeMode(false)
  love.mouse.setVisible(true)
  love.keyboard.setKeyRepeat(true)
  gui.userScale = options.values.guiScale
  gui.updateScale()
end

function Menu:leave()
  love.keyboard.setKeyRepeat(false)
end

local MODES = {
  { label = "Przetrwanie", mode = "survival", hardcore = false,
    info = "Zbieraj surowce, jedz, uwazaj na potwory" },
  { label = "Kreatywny", mode = "creative", hardcore = false,
    info = "Nieskonczone bloki, latanie, brak obrazen" },
  { label = "Hardcore", mode = "survival", hardcore = true,
    info = "Jedno zycie, trudny poziom - smierc usuwa swiat" },
}

function Menu:background()
  gui.dirtBackground(atlas.image, atlas.quads[tiles.get("dirt")])
end

function Menu:update(dt)
  self.time = self.time + dt
  gui.updateScale()
end

-- ---------------------------------------------------------------------------
-- Rysowanie stron
-- ---------------------------------------------------------------------------
function Menu:drawTitle()
  local g = love.graphics
  local w, h = g.getDimensions()
  local s = gui.scale
  -- tytuł z "bloków"
  local title = "MINECRAFT LUA"
  gui.text(title, 0, h * 0.18, { 0.85, 0.85, 0.85 }, 3.2, "center", w)
  gui.text("edycja Beta", 0, h * 0.18 + 42 * s, { 0.6, 0.6, 0.6 }, 1.2, "center", w)
  -- żółty napis ukośny
  g.push()
  local tx = w / 2 + gui.textWidth(title, 3.2) / 2 - 10 * s
  g.translate(tx, h * 0.18 + 38 * s)
  g.rotate(-0.35)
  local pulse = 1 + math.abs(math.sin(self.time * 6)) * 0.08
  g.scale(pulse, pulse)
  local sw = gui.textWidth(self.splash)
  gui.text(self.splash, -sw / 2, 0, { 1, 1, 0 })
  g.pop()
  self.buttons = {}
  local labels = { "Jeden gracz", "Opcje...", "Wyjdz z gry" }
  for i, l in ipairs(labels) do
    local b = { x = math.floor(w / 2 - 100 * s), y = math.floor(h * 0.45 + (i - 1) * 24 * s),
      w = 200 * s, h = 20 * s, action = i }
    self.buttons[i] = b
    gui.button(l, b.x, b.y, b.w, b.h)
  end
  gui.text("Minecraft Lua - klon ery Beta, napisany w Lua i LOVE", 4 * s, h - 12 * s,
    { 0.8, 0.8, 0.8 }, 0.9)
  gui.text("Nie jest powiazany z Mojang", 0, h - 12 * s, { 0.8, 0.8, 0.8 }, 0.9, "right", w - 4 * s)
end

function Menu:drawWorlds()
  local g = love.graphics
  local w, h = g.getDimensions()
  local s = gui.scale
  gui.text("Wybierz swiat", 0, 12 * s, nil, 1.2, "center", w)
  local lx, lw = math.floor(w / 2 - 110 * s), 220 * s
  local ly = 32 * s
  local rowH = 30 * s
  local maxRows = math.max(1, math.floor((h - 100 * s) / rowH))
  g.setColor(0, 0, 0, 0.5)
  g.rectangle("fill", 0, ly - 4 * s, w, maxRows * rowH + 8 * s)
  g.setColor(1, 1, 1)
  self.rows = {}
  if #self.worlds == 0 then
    gui.text("Brak swiatow - utworz nowy!", 0, ly + 20 * s, { 0.7, 0.7, 0.7 }, 1, "center", w)
  end
  for i, wd in ipairs(self.worlds) do
    if i > maxRows then break end
    local y = ly + (i - 1) * rowH
    local r = { x = lx, y = y, w = lw, h = rowH - 2 * s, index = i }
    self.rows[i] = r
    if self.selected == i then
      g.setColor(0.6, 0.6, 0.6, 1)
      g.setLineWidth(s)
      g.rectangle("line", r.x, r.y, r.w, r.h)
      g.setColor(0, 0, 0, 0.6)
      g.rectangle("fill", r.x + s, r.y + s, r.w - 2 * s, r.h - 2 * s)
      g.setColor(1, 1, 1)
    end
    gui.text(wd.name, r.x + 4 * s, r.y + 2 * s)
    local mode = wd.hardcore and "Hardcore" or (wd.gameMode == "creative" and "Kreatywny" or "Przetrwanie")
    local date = wd.lastPlayed > 0 and os.date("%Y-%m-%d %H:%M", wd.lastPlayed) or ""
    gui.text(wd.folder .. "  (" .. date .. ")", r.x + 4 * s, r.y + 11 * s, { 0.55, 0.55, 0.55 }, 0.85)
    gui.text(mode .. (wd.dead and " - koniec gry" or ""), r.x + 4 * s, r.y + 19 * s, { 0.55, 0.55, 0.55 }, 0.85)
  end
  local by = h - 52 * s
  local hasSel = self.selected ~= nil
  self.buttons = {
    { x = math.floor(w / 2 - 154 * s), y = by, w = 150 * s, h = 20 * s, action = "play", label = "Graj", dis = not hasSel },
    { x = math.floor(w / 2 + 4 * s), y = by, w = 150 * s, h = 20 * s, action = "new", label = "Nowy swiat" },
    { x = math.floor(w / 2 - 154 * s), y = by + 24 * s, w = 150 * s, h = 20 * s, action = "delete", label = "Usun", dis = not hasSel },
    { x = math.floor(w / 2 + 4 * s), y = by + 24 * s, w = 150 * s, h = 20 * s, action = "back", label = "Anuluj" },
  }
  for _, b in ipairs(self.buttons) do gui.button(b.label, b.x, b.y, b.w, b.h, b.dis) end
end

function Menu:drawCreate()
  local g = love.graphics
  local w, h = g.getDimensions()
  local s = gui.scale
  gui.text("Utworz nowy swiat", 0, 16 * s, nil, 1.2, "center", w)
  local fx, fw = math.floor(w / 2 - 100 * s), 200 * s
  gui.text("Nazwa swiata", fx, 44 * s, { 0.65, 0.65, 0.65 })
  self.nameField = { x = fx, y = 54 * s, w = fw, h = 20 * s }
  gui.textField(self.newName, fx, 54 * s, fw, 20 * s, self.focus == "name")
  gui.text("Ziarno (seed) - puste = losowe", fx, 82 * s, { 0.65, 0.65, 0.65 })
  self.seedField = { x = fx, y = 92 * s, w = fw, h = 20 * s }
  gui.textField(self.newSeed, fx, 92 * s, fw, 20 * s, self.focus == "seed", "np. 12345 albo slowo")
  local mode = MODES[self.newMode]
  self.buttons = {
    { x = fx, y = 124 * s, w = fw, h = 20 * s, action = "mode", label = "Tryb gry: " .. mode.label },
    { x = math.floor(w / 2 - 154 * s), y = h - 30 * s, w = 150 * s, h = 20 * s, action = "create",
      label = "Utworz swiat", dis = self.newName:gsub("%s", "") == "" },
    { x = math.floor(w / 2 + 4 * s), y = h - 30 * s, w = 150 * s, h = 20 * s, action = "back", label = "Anuluj" },
  }
  gui.text(mode.info, 0, 148 * s, { 0.65, 0.65, 0.65 }, 0.9, "center", w)
  for _, b in ipairs(self.buttons) do gui.button(b.label, b.x, b.y, b.w, b.h, b.dis) end
end

function Menu:drawConfirm()
  local g = love.graphics
  local w, h = g.getDimensions()
  local s = gui.scale
  local wd = self.worlds[self.selected]
  gui.text("Czy na pewno usunac ten swiat?", 0, h / 3, nil, 1.2, "center", w)
  gui.text("'" .. (wd and wd.name or "") .. "' zniknie na zawsze! (dlugo!)", 0, h / 3 + 20 * s,
    { 0.7, 0.7, 0.7 }, 1, "center", w)
  self.buttons = {
    { x = math.floor(w / 2 - 154 * s), y = h / 2 + 10 * s, w = 150 * s, h = 20 * s, action = "confirmDelete", label = "Usun" },
    { x = math.floor(w / 2 + 4 * s), y = h / 2 + 10 * s, w = 150 * s, h = 20 * s, action = "back", label = "Anuluj" },
  }
  for _, b in ipairs(self.buttons) do gui.button(b.label, b.x, b.y, b.w, b.h) end
end

function Menu:draw()
  gui.setMouse(love.mouse.getPosition())
  if self.page == "options" then
    self.optionsScreen:draw()
    return
  end
  self:background()
  if self.page == "title" then self:drawTitle()
  elseif self.page == "worlds" then self:drawWorlds()
  elseif self.page == "create" then self:drawCreate()
  elseif self.page == "confirm" then self:drawConfirm() end
end

-- ---------------------------------------------------------------------------
-- Akcje
-- ---------------------------------------------------------------------------
function Menu:startWorld(params)
  params.manager = self.manager
  self.manager:switch(require("states.loading"), params)
end

function Menu:action(a)
  sound.play("click")
  if self.page == "title" then
    if a == 1 then
      self.worlds = save.listWorlds()
      self.selected = #self.worlds > 0 and 1 or nil
      self.page = "worlds"
    elseif a == 2 then
      self.optionsScreen = menus.options(function(key, value)
        if key == "guiScale" then gui.userScale = value; gui.updateScale() end
        if key == "volume" then sound.setVolume(value) end
      end, function()
        options.save(fs)
        self.page = "title"
      end, function() self:background() end)
      self.page = "options"
    elseif a == 3 then
      love.event.quit()
    end
  elseif self.page == "worlds" then
    if a == "play" and self.selected then
      self:startWorld({ folder = self.worlds[self.selected].folder })
    elseif a == "new" then
      self.newName = "Nowy swiat"
      self.newSeed = ""
      self.focus = "name"
      self.page = "create"
    elseif a == "delete" and self.selected then
      self.page = "confirm"
    elseif a == "back" then
      self.page = "title"
    end
  elseif self.page == "create" then
    if a == "mode" then
      self.newMode = self.newMode % #MODES + 1
    elseif a == "create" then
      local m = MODES[self.newMode]
      self:startWorld({ create = { name = self.newName, seed = save.parseSeed(self.newSeed),
        gameMode = m.mode, hardcore = m.hardcore } })
    elseif a == "back" then
      self.page = "worlds"
    end
  elseif self.page == "confirm" then
    if a == "confirmDelete" then
      save.deleteWorld(self.worlds[self.selected].folder)
      self.worlds = save.listWorlds()
      self.selected = #self.worlds > 0 and 1 or nil
    end
    self.page = "worlds"
  end
end

function Menu:mousepressed(x, y, button)
  if self.page == "options" then
    self.optionsScreen:mousepressed(x, y, button)
    return
  end
  if button ~= 1 then return end
  if self.page == "create" then
    if hit(self.nameField, x, y) then self.focus = "name" end
    if hit(self.seedField, x, y) then self.focus = "seed" end
  end
  if self.page == "worlds" and self.rows then
    for i, r in ipairs(self.rows) do
      if hit(r, x, y) then
        local now = love.timer.getTime()
        if self.selected == i and now - self.lastClick < 0.4 then
          self:action("play")
          return
        end
        self.selected = i
        self.lastClick = now
        return
      end
    end
  end
  for _, b in ipairs(self.buttons or {}) do
    if hit(b, x, y) and not b.dis then
      self:action(b.action)
      return
    end
  end
end

function Menu:mousemoved(x, y)
  if self.page == "options" then self.optionsScreen:mousemoved(x, y) end
end

function Menu:mousereleased(x, y, b)
  if self.page == "options" then self.optionsScreen:mousereleased(x, y, b) end
end

function Menu:textinput(t)
  if self.page ~= "create" then return end
  if self.focus == "name" and #self.newName < 32 then self.newName = self.newName .. t
  elseif self.focus == "seed" and #self.newSeed < 32 then self.newSeed = self.newSeed .. t end
end

function Menu:keypressed(key)
  if self.page == "options" then
    self.optionsScreen:keypressed(key)
    return
  end
  if self.page == "create" then
    if key == "backspace" then
      if self.focus == "name" then self.newName = self.newName:sub(1, -2)
      else self.newSeed = self.newSeed:sub(1, -2) end
    elseif key == "tab" then
      self.focus = self.focus == "name" and "seed" or "name"
    elseif key == "return" then
      self:action("create")
    elseif key == "escape" then
      self.page = "worlds"
    end
    return
  end
  if key == "escape" then
    if self.page == "title" then love.event.quit() else self.page = "title" end
  elseif key == "return" and self.page == "worlds" and self.selected then
    self:action("play")
  end
end

return Menu
