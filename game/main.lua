-- main.lua
-- Punkt wejścia gry. Spina całość: zegar ticków (20/s), menedżer stanów
-- (menu -> ładowanie -> gra), ustawienia i globalne skróty klawiszowe.

-- Najpierw strict: od tej chwili literówka w nazwie zmiennej = błąd
require("core.strict").enable()

local config = require("core.config")
local Clock = require("core.clock")
local StateManager = require("states.manager")
local options = require("core.options")
local fs = require("core.fs")

local clock
local states

function love.load(args)
  -- Piksele bez rozmywania (tekstury 16x16 jak w Minecrafcie)
  if love.graphics then love.graphics.setDefaultFilter("nearest", "nearest") end
  math.randomseed(os.time())
  options.load(fs)
  -- zbieranie śmieci małymi krokami (bez długich przycięć)
  collectgarbage("setpause", 120)
  collectgarbage("setstepmul", 200)

  clock = Clock.new(config.TICKS_PER_SECOND, config.MAX_TICKS_PER_FRAME)
  states = StateManager.new()

  -- Parametry startowe (przydatne przy testowaniu):
  --   --play            od razu nowy, tymczasowy świat (bez zapisu)
  --   --creative        to samo w trybie kreatywnym
  --   --boot            ekran testowy z Fazy 0
  --   --seed=12345      ziarno dla --play
  --   --lan             z --play/--creative: od razu otwiera świat w sieci LAN
  --   --join=adres      dołącza do gry w sieci (np. --join=localhost)
  --   --name=Nick       nick w grze wieloosobowej
  local mode, seed = "menu", 12345
  local lan, join, name = false, nil, nil
  for _, a in ipairs(args or {}) do
    if a == "--play" then mode = "play"
    elseif a == "--creative" then mode = "creative"
    elseif a == "--boot" then mode = "boot"
    elseif a == "--lan" then lan = true
    elseif a:match("^%-%-join=") then join = a:match("=(.+)$")
    elseif a:match("^%-%-name=") then name = a:match("=(.+)$")
    elseif a:match("^%-%-seed=") then seed = tonumber(a:match("=(%-?%d+)")) or seed end
  end
  -- serwer dedykowany: --server [--world=Nazwa] [--port=25565] [--seed=N] ...
  local server = false
  for _, a in ipairs(args or {}) do if a == "--server" then server = true end end
  if server then
    states:switch(require("states.server"), { manager = states, args = args })
    return
  end
  if join then
    states:switch(require("states.connect"), { manager = states, address = join,
      name = name or require("core.options").values.playerName })
  elseif mode == "boot" then
    states:switch(require("states.boot"))
  elseif mode == "play" or mode == "creative" then
    states:switch(require("states.loading"), { manager = states, temporary = true, openLan = lan,
      hostName = name,
      create = { name = "Test", seed = seed, gameMode = mode == "creative" and "creative" or "survival" } })
  else
    states:switch(require("states.menu"), { manager = states })
  end
end

function love.update(dt)
  -- Logika w równych tickach (20/s), niezależnie od FPS
  local ticks = clock:advance(dt)
  for _ = 1, ticks do
    states:call("tick")
  end
  states:call("update", dt, clock:alpha())
  collectgarbage("step", 2)
end

function love.draw()
  states:call("draw", clock:alpha())
end

function love.keypressed(key, scancode, isrepeat)
  -- Pełny ekran działa w każdym stanie gry
  if key == "f11" then
    love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
    return
  end
  states:call("keypressed", key, scancode, isrepeat)
end

function love.keyreleased(key, scancode)
  states:call("keyreleased", key, scancode)
end

function love.textinput(t)
  states:call("textinput", t)
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

-- Zamknięcie okna: zapis świata
function love.quit()
  states:call("save")
  states:call("closeNet")
  options.save(fs)
  return false
end
