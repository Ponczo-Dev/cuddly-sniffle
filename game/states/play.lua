-- states/play.lua (wersja Fazy 1-2: wolna kamera nad płaskim światem)

local config = require("core.config")
local World = require("core.world")
local blocks = require("core.blocks")
local atlas = require("render.atlas")
local shader = require("render.shader")
local Camera = require("render.camera")
local ChunkRenderer = require("render.chunkrenderer")

local Play = {}

-- Tymczasowy generator: płaski teren + rząd wszystkich bloków do podglądu
local function flatGenerator(chunk)
  for z = 0, 15 do
    for x = 0, 15 do
      chunk:setRaw(x, 0, z, 7)
      for y = 1, 59 do chunk:setRaw(x, y, z, 1) end
      for y = 60, 62 do chunk:setRaw(x, y, z, 3) end
      chunk:setRaw(x, 63, z, 2)
    end
  end
  if chunk.cz == 0 and chunk.cx >= 0 and chunk.cx < 4 then
    local i = 0
    for id = 1, 255 do
      local d = blocks.defs[id]
      if d and id ~= 2 then
        local x = (i % 8) * 2
        local cxIndex = math.floor(i / 8)
        if cxIndex == chunk.cx then
          chunk:setRaw(x, 64, 4, id, 0)
        end
        i = i + 1
      end
    end
  end
end

function Play:enter()
  atlas.load()
  shader.load()
  self.world = World.new({ seed = 1, generator = flatGenerator })
  self.renderer = ChunkRenderer.new(self.world, atlas.image)
  self.camera = Camera.new()
  self.camera.x, self.camera.y, self.camera.z = 8, 68, 16
  self.camera.pitch = -0.3
  self.radius = config.RENDER_DISTANCE
  love.mouse.setRelativeMode(true)
end

function Play:leave()
  love.mouse.setRelativeMode(false)
  self.renderer:clear()
end

function Play:mousemoved(_, _, dx, dy)
  local cam = self.camera
  local s = math.rad(config.MOUSE_SENSITIVITY)
  cam.yaw = cam.yaw - dx * s
  cam.pitch = math.max(-1.55, math.min(1.55, cam.pitch - dy * s))
end

function Play:update(dt)
  local cam = self.camera
  local k = love.keyboard.isDown
  local speed = (k("lctrl") and 40 or 12) * dt
  local fx, fz = -math.sin(cam.yaw), -math.cos(cam.yaw)
  local rx, rz = -fz, fx
  if k("w") then cam.x, cam.z = cam.x + fx * speed, cam.z + fz * speed end
  if k("s") then cam.x, cam.z = cam.x - fx * speed, cam.z - fz * speed end
  if k("d") then cam.x, cam.z = cam.x + rx * speed, cam.z + rz * speed end
  if k("a") then cam.x, cam.z = cam.x - rx * speed, cam.z - rz * speed end
  if k("space") then cam.y = cam.y + speed end
  if k("lshift") then cam.y = cam.y - speed end

  local ccx, ccz = math.floor(cam.x / 16), math.floor(cam.z / 16)
  self.world:updateLoading(ccx, ccz, self.radius, 4)
  self.world:unloadFar(ccx, ccz, self.radius + 4)
  self.renderer:update(cam.x, cam.z, self.radius, 0.008)
end

function Play:draw()
  local g = love.graphics
  local w, h = g.getDimensions()
  local sky = { 0.47, 0.65, 1.0 }
  g.clear(sky[1], sky[2], sky[3], 1)
  local cam = self.camera
  cam:update(w, h)
  local fogEnd = self.radius * 16
  shader.setCamera(cam.proj, cam.view, sky, fogEnd * 0.6, fogEnd)
  self.renderer:draw(cam, 1.0, sky, fogEnd * 0.6, fogEnd)
  g.setShader()
  g.setDepthMode()
  g.setMeshCullMode("none")
  g.setColor(1, 1, 1)
  local st = self.renderer.stats
  g.print(string.format("XYZ: %.1f %.1f %.1f  chunki: %d/%d  wierzch.: %d  kolejka: %d",
    cam.x, cam.y, cam.z, st.drawn, st.total, st.vertices, st.pending or 0), 10, 10)
end

function Play:keypressed(key)
  if key == "escape" then love.event.quit() end
end

return Play
