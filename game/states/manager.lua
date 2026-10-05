-- states/manager.lua
-- Prosty menedżer stanów gry (menu, ładowanie, gra, pauza...).
-- Stan to zwykła tabela z opcjonalnymi metodami:
--   enter(...), leave(), tick(), update(dt, alpha), draw(alpha),
--   keypressed(key, scancode, isrepeat), resize(w, h) itd.
-- Bez love.*, więc da się go testować przez lua.exe.

local M = {}

local Manager = {}
Manager.__index = Manager

function M.new()
  return setmetatable({ current = nil }, Manager)
end

-- Przełącza na nowy stan. Dodatkowe argumenty trafiają do state:enter(...)
function Manager:switch(state, ...)
  local old = self.current
  if old and old.leave then
    old:leave()
  end
  self.current = state
  if state.enter then
    state:enter(...)
  end
end

-- Wywołuje metodę obecnego stanu, jeśli ją ma.
function Manager:call(name, ...)
  local state = self.current
  if state then
    local fn = state[name]
    if fn then
      return fn(state, ...)
    end
  end
end

return M
