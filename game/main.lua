-- main.lua
-- Punkt wejścia gry. Tylko spina całość: zegar ticków, menedżer stanów,
-- globalne skróty klawiszowe. Właściwa logika siedzi w states/ i core/.

-- Najpierw strict: od tej chwili literówka w nazwie zmiennej = błąd
require("core.strict").enable()

local config = require("core.config")
local Clock = require("core.clock")
local StateManager = require("states.manager")

local clock
local states
local showFps = true

function love.load(args)
  -- Piksele bez rozmywania (tekstury 16x16 jak w Minecrafcie)
  love.graphics.setDefaultFilter("nearest", "nearest")

  clock = Clock.new(config.TICKS_PER_SECOND, config.MAX_TICKS_PER_FRAME)
  states = StateManager.new()

  -- Parametr "--play" pomija menu (przydatne przy testowaniu)
  local first = "states.boot"
  for _, a in ipairs(args or {}) do
    if a == "--play" then first = "states.play" end
  end
  states:switch(require(first))
end

function love.update(dt)
  -- Logika w równych tickach (20/s), niezależnie od FPS
  local ticks = clock:advance(dt)
  for _ = 1, ticks do
    states:call("tick")
  end
  states:call("update", dt, clock:alpha())
end

function love.draw()
  states:call("draw", clock:alpha())

  if showFps then
    local w = love.graphics.getWidth()
    love.graphics.setColor(1, 1, 0)
    love.graphics.print("FPS: " .. love.timer.getFPS(), w - 90, 10)
    love.graphics.setColor(1, 1, 1)
  end
end

function love.keypressed(key, scancode, isrepeat)
  -- Skróty działające w każdym stanie gry
  if key == "f11" then
    love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
    return
  elseif key == "f3" then
    showFps = not showFps
    return
  end
  states:call("keypressed", key, scancode, isrepeat)
end

function love.keyreleased(key, scancode)
  states:call("keyreleased", key, scancode)
end

function love.mousepressed(x, y, button)
  states:call("mousepressed", x, y, button)
end

function love.mousereleased(x, y, button)
  states:call("mousereleased", x, y, button)
end

function love.mousemoved(x, y, dx, dy)
  states:call("mousemoved", x, y, dx, dy)
end

function love.wheelmoved(x, y)
  states:call("wheelmoved", x, y)
end

function love.resize(w, h)
  states:call("resize", w, h)
end

function love.focus(focused)
  states:call("focus", focused)
end
