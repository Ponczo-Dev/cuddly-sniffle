-- states/boot.lua
-- Ekran startowy Fazy 0: sprawdza, czy LÖVE, okno, pętla gry i tick 20 TPS działają.
-- Kręcący się sześcian (rysowany liniami, matematyka "na piechotę") pokazuje,
-- że interpolacja między tickami daje płynny ruch nawet przy 20 TPS.
-- Teksty na ekranie BEZ polskich znaków: domyślna czcionka LÖVE 11 ich nie ma.

local config = require("core.config")
local bit = require("core.bit")
local util = require("core.util")

local Boot = {}

-- 8 wierzchołków sześcianu i 12 krawędzi (indeksy wierzchołków)
local CUBE_VERTS = {
  { -1, -1, -1 }, { 1, -1, -1 }, { 1, 1, -1 }, { -1, 1, -1 },
  { -1, -1, 1 }, { 1, -1, 1 }, { 1, 1, 1 }, { -1, 1, 1 },
}
local CUBE_EDGES = {
  { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 1 },
  { 5, 6 }, { 6, 7 }, { 7, 8 }, { 8, 5 },
  { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 },
}

-- Obrót o 4.5 stopnia na tick = 90 stopni na sekundę
local SPIN_PER_TICK = math.rad(4.5)

function Boot:enter()
  self.angle = 0
  self.prevAngle = 0
  self.ticks = 0
  self.projected = {} -- bufor na rzutowane punkty (bez alokacji co klatkę)
  for i = 1, #CUBE_VERTS do
    self.projected[i] = { 0, 0 }
  end

  -- Zbieramy informacje o środowisku do wyświetlenia
  local major, minor, revision, codename = love.getVersion()
  local rName, rVersion, rVendor, rDevice = love.graphics.getRendererInfo()
  local _, _, flags = love.window.getMode()
  local jit = rawget(_G, "jit")

  self.loveOk = major >= 11
  self.depthOk = (flags.depth or 0) >= 16
  self.info = {
    string.format("LOVE %d.%d.%d (%s)", major, minor, revision, codename),
    "Lua: " .. (jit and jit.version or _VERSION),
    "Operacje bitowe: " .. bit.impl,
    string.format("Grafika: %s %s", rName, rVersion),
    string.format("Karta: %s / %s", rVendor, rDevice),
    "Depth buffer: " .. tostring(flags.depth or 0) .. " bit",
    "Zapis gry w: " .. love.filesystem.getSaveDirectory(),
  }
end

-- Logika: wywoływana dokładnie 20 razy na sekundę
function Boot:tick()
  self.ticks = self.ticks + 1
  self.prevAngle = self.angle
  self.angle = self.angle + SPIN_PER_TICK
end

-- Rzut perspektywiczny wierzchołków sześcianu na ekran
function Boot:projectCube(angle, cx, cy, scale)
  local cosY, sinY = math.cos(angle), math.sin(angle)
  local ax = angle * 0.6
  local cosX, sinX = math.cos(ax), math.sin(ax)
  for i = 1, #CUBE_VERTS do
    local v = CUBE_VERTS[i]
    -- obrót wokół osi Y
    local x = v[1] * cosY - v[3] * sinY
    local z = v[1] * sinY + v[3] * cosY
    -- obrót wokół osi X
    local y = v[2] * cosX - z * sinX
    z = v[2] * sinX + z * cosX
    -- perspektywa: im dalej, tym mniejsze
    local depth = z + 4
    local p = self.projected[i]
    p[1] = cx + x / depth * scale
    p[2] = cy + y / depth * scale
  end
end

function Boot:draw(alpha)
  local w, h = love.graphics.getDimensions()
  love.graphics.clear(0.47, 0.65, 1.0) -- błękit nieba jak w MC

  -- Interpolowany kąt: płynny obrót niezależnie od FPS
  local angle = util.lerp(self.prevAngle, self.angle, alpha)
  self:projectCube(angle, w * 0.5, h * 0.5, math.min(w, h) * 0.6)

  love.graphics.setLineWidth(3)
  love.graphics.setColor(0.36, 0.25, 0.13) -- kolor "ziemi"
  for i = 1, #CUBE_EDGES do
    local a = self.projected[CUBE_EDGES[i][1]]
    local b = self.projected[CUBE_EDGES[i][2]]
    love.graphics.line(a[1], a[2], b[1], b[2])
  end

  -- Napisy
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("MINECRAFT LUA - Faza 0", 20, 20, 0, 2, 2)
  love.graphics.print("Jesli widzisz krecacy sie szescian, wszystko dziala!", 20, 60)

  local y = 100
  for i = 1, #self.info do
    love.graphics.print(self.info[i], 20, y)
    y = y + 18
  end

  y = y + 10
  love.graphics.print(string.format("Ticki: %d (%d TPS)  |  alpha: %.2f",
    self.ticks, config.TICKS_PER_SECOND, alpha), 20, y)

  -- Ostrzeżenia, gdy coś jest nie tak
  y = y + 28
  love.graphics.setColor(1, 0.3, 0.3)
  if not self.loveOk then
    love.graphics.print("UWAGA: potrzebny LOVE 11.x (najlepiej 11.5)!", 20, y)
    y = y + 18
  end
  if not self.depthOk then
    love.graphics.print("UWAGA: brak depth buffera - 3D w Fazie 1 nie zadziala!", 20, y)
  end

  love.graphics.setColor(1, 1, 1)
  love.graphics.print("ESC - wyjscie   F11 - pelny ekran   F3 - licznik FPS", 20, h - 30)
end

function Boot:keypressed(key)
  if key == "escape" then
    love.event.quit()
  end
end

return Boot
