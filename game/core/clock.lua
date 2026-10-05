-- core/clock.lua
-- Stały krok czasowy (fixed timestep).
-- Logika gry (fizyka, moby, głód) liczy się w równych tickach (20 na sekundę),
-- niezależnie od FPS. Rysowanie odbywa się tak często, jak pozwala karta,
-- a "alpha" mówi, jak daleko jesteśmy między poprzednim a następnym tickiem,
-- żeby ruch na ekranie był płynny (interpolacja).

local M = {}

local Clock = {}
Clock.__index = Clock

-- Drobny zapas na błędy zaokrągleń liczb zmiennoprzecinkowych
local EPSILON = 1e-9

function M.new(ticksPerSecond, maxTicksPerFrame)
  local self = setmetatable({}, Clock)
  self.tickLength = 1 / ticksPerSecond
  self.maxTicks = maxTicksPerFrame or 10
  self.accumulator = 0
  self.totalTicks = 0
  self.droppedTime = 0 -- ile sekund "wyrzuciliśmy", bo gra nie nadążała
  return self
end

-- Dodaje czas klatki i zwraca, ile ticków trzeba teraz wykonać.
function Clock:advance(dt)
  if dt < 0 then dt = 0 end
  self.accumulator = self.accumulator + dt

  local n = math.floor(self.accumulator / self.tickLength + EPSILON)
  if n > self.maxTicks then
    -- Spirala śmierci: zamiast nadrabiać w nieskończoność, odpuszczamy zaległości
    -- (tak jak serwer MC z komunikatem "Can't keep up!")
    self.droppedTime = self.droppedTime
      + (n - self.maxTicks) * self.tickLength
    n = self.maxTicks
    self.accumulator = 0
  else
    self.accumulator = self.accumulator - n * self.tickLength
    if self.accumulator < 0 then self.accumulator = 0 end
  end

  self.totalTicks = self.totalTicks + n
  return n
end

-- Ułamek drogi do następnego ticka: 0..1
function Clock:alpha()
  local a = self.accumulator / self.tickLength
  if a > 1 then return 1 end
  if a < 0 then return 0 end
  return a
end

return M
