-- render/init.lua
-- Jednorazowe ładowanie wszystkich zasobów graficznych i dźwiękowych.

local M = {}

local loaded = false

function M.load()
  if loaded then return end
  loaded = true
  require("render.atlas").load()
  require("render.shader").load()
  require("render.icons").load()
  require("render.models").load()
  require("render.sky").load()
  require("render.particles").load()
  require("render.weather").load()
  require("render.hud").load()
  require("render.sound").load()
end

return M
