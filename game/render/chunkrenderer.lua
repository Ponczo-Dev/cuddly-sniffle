-- render/chunkrenderer.lua
-- Zarządza meshami chunków: przebudowuje "brudne" chunki (z limitem czasu na
-- klatkę, żeby gra się nie przycinała) i rysuje widoczne chunki.

local mesher = require("core.mesher")
local meshbuffer = require("render.meshbuffer")
local shader = require("render.shader")
local frustum = require("core.frustum")
local world_mod = require("core.world")

local M = {}

local SIZE, HEIGHT = 16, 128

local Renderer = {}
Renderer.__index = Renderer

function M.new(world, texture)
  local self = setmetatable({}, Renderer)
  self.world = world
  self.texture = texture
  self.meshes = {}         -- klucz chunka -> { cx, cz, opaque, trans }
  self.opaqueBuf = meshbuffer.new(65536)
  self.transBuf = meshbuffer.new(16384)
  self.stats = { built = 0, drawn = 0, total = 0, vertices = 0, buildMs = 0 }
  self.candidates = {}
  return self
end

local function releaseEntry(e)
  if e.opaque then e.opaque:release() end
  if e.trans then e.trans:release() end
end

function Renderer:rebuild(chunk)
  local key = world_mod.key(chunk.cx, chunk.cz)
  mesher.gather(self.world, chunk.cx, chunk.cz)
  self.opaqueBuf:reset()
  self.transBuf:reset()
  mesher.build(chunk, self.opaqueBuf, self.transBuf)
  local old = self.meshes[key]
  if old then releaseEntry(old) end
  self.meshes[key] = {
    cx = chunk.cx, cz = chunk.cz,
    opaque = self.opaqueBuf:toMesh(self.texture),
    trans = self.transBuf:toMesh(self.texture),
    verts = self.opaqueBuf.n + self.transBuf.n,
  }
  chunk.dirty = false
end

-- Przebudowa brudnych chunków w zasięgu, od najbliższych, w limicie czasu
function Renderer:update(camX, camZ, radius, budgetSeconds)
  local world = self.world
  local ccx, ccz = math.floor(camX / SIZE), math.floor(camZ / SIZE)

  -- usuń meshe chunków spoza zasięgu albo zwolnionych
  for key, e in pairs(self.meshes) do
    local c = world:getChunk(e.cx, e.cz)
    if not c or math.abs(e.cx - ccx) > radius + 1 or math.abs(e.cz - ccz) > radius + 1 then
      releaseEntry(e)
      self.meshes[key] = nil
    end
  end

  -- kandydaci do przebudowy
  local list = self.candidates
  for i = #list, 1, -1 do list[i] = nil end
  for _, c in pairs(world.chunks) do
    if c.dirty and c.lit then
      local dx, dz = c.cx - ccx, c.cz - ccz
      if math.abs(dx) <= radius and math.abs(dz) <= radius
        and world:neighborsHave(c.cx, c.cz, "lit") then
        c._dist = dx * dx + dz * dz
        list[#list + 1] = c
      end
    end
  end
  table.sort(list, function(a, b) return a._dist < b._dist end)

  local start = love.timer.getTime()
  local built = 0
  for i = 1, #list do
    -- zawsze przynajmniej jeden chunk, potem pilnujemy limitu czasu
    if built > 0 and love.timer.getTime() - start > budgetSeconds then break end
    self:rebuild(list[i])
    built = built + 1
  end
  self.stats.built = built
  self.stats.pending = #list - built
  self.stats.buildMs = (love.timer.getTime() - start) * 1000
end

local sortList = {}

-- Rysuje bloki nieprzezroczyste; wodę zbiera do późniejszego drawTranslucent
function Renderer:draw(camera, daylight, fogColor, fogStart, fogEnd)
  self:drawOpaque(camera, daylight)
end

function Renderer:drawOpaque(camera, daylight)
  local g = love.graphics
  local f = camera.frustum
  local s = shader.chunk
  g.setShader(s)
  s:send("u_daylight", daylight)
  s:send("u_alphaCut", 0.5)
  g.setDepthMode("lequal", true)
  g.setMeshCullMode("back")
  g.setColor(1, 1, 1, 1)
  g.setBlendMode("replace")

  local drawn, total, verts = 0, 0, 0
  for i = #sortList, 1, -1 do sortList[i] = nil end
  for _, e in pairs(self.meshes) do
    total = total + 1
    local x0, z0 = e.cx * SIZE, e.cz * SIZE
    if (e.opaque or e.trans) and frustum.boxVisible(f, x0, 0, z0, x0 + SIZE, HEIGHT, z0 + SIZE) then
      if e.opaque then
        s:send("u_offset", { x0, 0, z0 })
        g.draw(e.opaque)
      end
      drawn = drawn + 1
      verts = verts + e.verts
      if e.trans then
        local dx, dz = x0 + 8 - camera.x, z0 + 8 - camera.z
        e._dist = dx * dx + dz * dz
        sortList[#sortList + 1] = e
      end
    end
  end

  g.setBlendMode("alpha")
  self.stats.drawn, self.stats.total, self.stats.vertices = drawn, total, verts
end

-- Woda i lód: od najdalszych, z mieszaniem, bez zapisu głębi
function Renderer:drawTranslucent(camera, daylight)
  local g = love.graphics
  local s = shader.chunk
  g.setShader(s)
  s:send("u_daylight", daylight)
  g.setColor(1, 1, 1, 1)
  if #sortList > 0 then
    table.sort(sortList, function(a, b) return a._dist > b._dist end)
    s:send("u_alphaCut", 0.01)
    g.setDepthMode("lequal", false)
    g.setMeshCullMode("none")
    for i = 1, #sortList do
      local e = sortList[i]
      s:send("u_offset", { e.cx * SIZE, 0, e.cz * SIZE })
      g.draw(e.trans)
    end
  end

  g.setDepthMode("lequal", true)
  g.setMeshCullMode("back")
end

function Renderer:clear()
  for key, e in pairs(self.meshes) do
    releaseEntry(e)
    self.meshes[key] = nil
  end
end

return M
