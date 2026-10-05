-- states/connect.lua
-- Łączenie z grą w sieci LAN: połączenie, powitanie od gospodarza
-- i pobranie terenu wokół gracza. Potem przejście do stanu gry.

local gui = require("render.gui")
local atlas = require("render.atlas")
local tiles = require("core.tiles")
local options = require("core.options")
local renderInit = require("render.init")
local transport = require("core.net.transport")
local protocol = require("core.net.protocol")
local Client = require("core.net.client")

local Connect = {}

local RADIUS = 1 -- tyle chunków wokół gracza musi być gotowe przed wejściem

-- params: { address = "192.168.1.10" lub "adres:port", name = "Nick" }
function Connect:enter(params)
  renderInit.load()
  self.params = params or {}
  self.manager = self.params.manager
  self.message = "Laczenie z " .. tostring(self.params.address) .. "..."
  self.progress = 0
  love.mouse.setRelativeMode(false)
  love.mouse.setVisible(true)
  local addr = tostring(self.params.address or "localhost")
  local host, port = addr:match("^(.-):(%d+)$")
  host = host or addr
  port = tonumber(port) or protocol.PORT
  local t, err = transport.enetClient(host, port)
  if not t then
    self:fail(err)
    return
  end
  self.client = Client.connect(t, { name = self.params.name,
    renderDistance = math.min(8, options.values.renderDistance) })
end

function Connect:fail(msg)
  self.failed = true
  self.message = msg or "Nie mozna polaczyc"
  if self.client then self.client:close() end
end

function Connect:tick()
  local c = self.client
  if self.failed or not c then return end
  c:poll()
  if c.state == "closed" then
    self:fail(c.error or "Rozlaczono")
    return
  end
  if c.state == "login" then self.message = "Logowanie..." end
  if c.state ~= "play" then return end
  self.message = "Pobieranie terenu..."
  local game = c.game
  c:updateWorld(love.timer.getTime() + 0.02, love.timer.getTime)
  local p = game.player
  local cx, cz = math.floor(p.x / 16), math.floor(p.z / 16)
  local total, done = 0, 0
  for dz = -RADIUS, RADIUS do
    for dx = -RADIUS, RADIUS do
      total = total + 1
      local ch = game.world:getChunk(cx + dx, cz + dz)
      if ch and ch.lit then done = done + 1 end
    end
  end
  self.progress = done / total
  if done >= total then
    -- gracz stoi na powierzchni, jeśli zapisana pozycja jest w ziemi
    local blocks = require("core.blocks")
    local bx, by, bz = math.floor(p.x), math.floor(p.y), math.floor(p.z)
    if blocks.SOLID[game.world:getBlock(bx, by, bz)] == 1 or blocks.SOLID[game.world:getBlock(bx, by + 1, bz)] == 1 then
      p.y = game:surfaceY(bx, bz)
      p.prevY = p.y
    end
    self.done = true
    self.manager:switch(require("states.play"), { game = game, manager = self.manager })
  end
end

function Connect:leave()
  if not self.done and self.client then self.client:close() end
end

function Connect:draw()
  local g = love.graphics
  local w, h = g.getDimensions()
  local s = gui.scale
  gui.dirtBackground(atlas.image, atlas.quads[tiles.get("dirt")])
  gui.text(self.message, 0, h / 2 - 20 * s, nil, 1.2, "center", w)
  if self.failed then
    gui.text("Nacisnij ESC, aby wrocic", 0, h / 2 + 10 * s, { 0.7, 0.7, 0.7 }, 1, "center", w)
  elseif self.client and self.client.state == "play" then
    local bw = 100 * s
    g.setColor(0.5, 0.5, 0.5)
    g.rectangle("fill", w / 2 - bw / 2, h / 2 + 4 * s, bw, 2 * s)
    g.setColor(0.5, 1, 0.5)
    g.rectangle("fill", w / 2 - bw / 2, h / 2 + 4 * s, bw * self.progress, 2 * s)
    g.setColor(1, 1, 1)
  else
    gui.text("Esc - anuluj", 0, h / 2 + 10 * s, { 0.7, 0.7, 0.7 }, 1, "center", w)
  end
end

function Connect:keypressed(key)
  if key == "escape" then
    self.manager:switch(require("states.menu"), { manager = self.manager })
  end
end

return Connect
