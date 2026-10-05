-- render/camera.lua
-- Kamera FPS: pozycja oka, obrót (yaw/pitch), macierze i frustum.
-- yaw = 0 patrzy w stronę -Z (północ), dodatni pitch = w górę.

local mat4 = require("core.mat4")
local frustum = require("core.frustum")

local M = {}

local Camera = {}
Camera.__index = Camera

function M.new()
  local self = setmetatable({}, Camera)
  self.x, self.y, self.z = 0, 80, 0
  self.yaw, self.pitch = 0, 0
  self.fov = math.rad(70)
  self.near, self.far = 0.05, 512
  self.proj = mat4.new()
  self.view = mat4.new()
  self.viewProj = mat4.new()
  self.frustum = frustum.new()
  return self
end

-- Wektor kierunku patrzenia
function Camera:forward()
  local cp = math.cos(self.pitch)
  return -math.sin(self.yaw) * cp, math.sin(self.pitch), -math.cos(self.yaw) * cp
end

function Camera:update(width, height)
  mat4.perspective(self.proj, self.fov, width / height, self.near, self.far)
  mat4.fpsView(self.view, self.x, self.y, self.z, self.yaw, self.pitch)
  mat4.multiply(self.viewProj, self.proj, self.view)
  frustum.update(self.frustum, self.viewProj)
end

-- Rzut punktu świata na ekran (do napisów nad głowami itp.)
function Camera:project(x, y, z, width, height)
  local cx, cy, _, cw = mat4.transform(self.viewProj, x, y, z)
  if cw <= 0.01 then return nil end
  return (cx / cw * 0.5 + 0.5) * width, (1 - (cy / cw * 0.5 + 0.5)) * height
end

return M
