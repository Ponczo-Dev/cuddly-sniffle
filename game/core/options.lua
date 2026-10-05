-- core/options.lua
-- Ustawienia gracza (zasięg widzenia, FOV, czułość myszy, głośność...).
-- Zapisywane do pliku options.lua w folderze zapisu gry.

local serialize = require("core.serialize")

local M = {}

M.defaults = {
  renderDistance = 6,
  fov = 70,
  sensitivity = 0.5,   -- 0..1
  volume = 0.7,
  music = 0.5,          -- głośność muzyki (z Minecrafta, jeśli zainstalowany)
  guiScale = 0,        -- 0 = auto
  difficulty = 2,
  viewBobbing = true,
  showFps = false,
  clouds = true,
  invertMouse = false,
  playerName = "Gracz",     -- nick w grze wieloosobowej
  lastServer = "localhost", -- ostatni adres serwera
}

M.values = {}
for k, v in pairs(M.defaults) do M.values[k] = v end

function M.load(fs)
  local text = fs.read("options.lua")
  if text then
    local data = serialize.decode(text)
    if type(data) == "table" then
      for k, v in pairs(data) do
        if M.defaults[k] ~= nil and type(v) == type(M.defaults[k]) then M.values[k] = v end
      end
    end
  end
  return M.values
end

function M.save(fs)
  fs.write("options.lua", serialize.encode(M.values))
end

-- Czułość myszy w stopniach na piksel
function M.mouseDegrees()
  return 0.05 + M.values.sensitivity * 0.35
end

return M
