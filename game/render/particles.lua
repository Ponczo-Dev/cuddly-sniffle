-- render/particles.lua
-- Cząsteczki: odłamki niszczonego bloku, dym, płomienie, serduszka, krople
-- deszczu i płatki śniegu. Wszystkie rysowane jako kwadraty zwrócone do
-- kamery, z jednej dynamicznej siatki (jedno wywołanie rysowania).

local tiles = require("core.tiles")
local blocks = require("core.blocks")
local shader = require("render.shader")
local atlas = require("render.atlas")
local mat4 = require("core.mat4")

local M = {}

local list = {}
local MAX = 1200
local mesh
local verts = {}
local ident = mat4.new()
local whiteU, whiteV

function M.load()
  mesh = love.graphics.newMesh({
    { "VertexPosition", "float", 3 }, { "VertexTexCoord", "float", 2 }, { "VertexColor", "byte", 4 },
  }, MAX * 6, "triangles", "stream")
  mesh:setTexture(atlas.image)
  local u0, v0, s = tiles.uv(tiles.get("white"))
  whiteU, whiteV = u0 + s / 2, v0 + s / 2
end

function M.clear() list = {} end
function M.count() return #list end

-- Dodaje cząsteczkę: opts = { x,y,z, vx,vy,vz, life, size, r,g,b,a, gravity, tile, drag }
function M.add(p)
  if #list >= MAX then table.remove(list, 1) end
  p.age = 0
  p.life = p.life or 20
  p.size = p.size or 0.1
  p.gravity = p.gravity or 0.04
  p.drag = p.drag or 0.98
  p.r, p.g, p.b, p.a = p.r or 1, p.g or 1, p.b or 1, p.a or 1
  p.px, p.py, p.pz = p.x, p.y, p.z
  if p.tile then
    -- losowy fragment 4x4 piksele z tekstury bloku
    local u0, v0, s = tiles.uv(p.tile)
    local fx, fy = math.random(0, 12) / 16, math.random(0, 12) / 16
    p.u0, p.v0 = u0 + fx * s, v0 + fy * s
    p.u1, p.v1 = p.u0 + s / 4, p.v0 + s / 4
  else
    p.u0, p.v0, p.u1, p.v1 = whiteU, whiteV, whiteU, whiteV
  end
  list[#list + 1] = p
end

-- Odłamki niszczonego bloku
function M.blockBreak(x, y, z, id, meta)
  local def = blocks.defs[id]
  if not def or def.shape == "none" then return end
  local tile = blocks.faceTile(def, 1, meta or 0)
  for i = 0, 3 do
    for j = 0, 3 do
      for k = 0, 3 do
        local px, py, pz = x + (i + 0.5) / 4, y + (j + 0.5) / 4, z + (k + 0.5) / 4
        M.add({ x = px, y = py, z = pz,
          vx = (px - x - 0.5) * 0.15 + (math.random() - 0.5) * 0.05,
          vy = (py - y - 0.5) * 0.15 + math.random() * 0.1,
          vz = (pz - z - 0.5) * 0.15 + (math.random() - 0.5) * 0.05,
          life = math.random(10, 30), size = 0.06 + math.random() * 0.05, tile = tile,
          collide = true })
      end
    end
  end
end

-- Pojedyncze odpryski przy uderzaniu w blok
function M.blockHit(x, y, z, id, face)
  local def = blocks.defs[id]
  if not def then return end
  local tile = blocks.faceTile(def, face or 1, 0)
  local nx, ny, nz = 0, 0, 0
  if face == 1 then nx = 1 elseif face == 2 then nx = -1 elseif face == 3 then ny = 1
  elseif face == 4 then ny = -1 elseif face == 5 then nz = 1 elseif face == 6 then nz = -1 end
  for _ = 1, 2 do
    local px = x + 0.5 + nx * 0.52 + (nx == 0 and (math.random() - 0.5) or 0)
    local py = y + 0.5 + ny * 0.52 + (ny == 0 and (math.random() - 0.5) or 0)
    local pz = z + 0.5 + nz * 0.52 + (nz == 0 and (math.random() - 0.5) or 0)
    M.add({ x = px, y = py, z = pz, vx = nx * 0.05, vy = 0.05, vz = nz * 0.05,
      life = 15, size = 0.05, tile = tile, collide = true })
  end
end

function M.burst(kind, x, y, z, n)
  n = n or 8
  for _ = 1, n do
    local p = { x = x + (math.random() - 0.5) * 0.6, y = y + (math.random() - 0.5) * 0.6,
      z = z + (math.random() - 0.5) * 0.6,
      vx = (math.random() - 0.5) * 0.1, vy = math.random() * 0.1, vz = (math.random() - 0.5) * 0.1 }
    if kind == "smoke" or kind == "poof" or kind == "explosion" then
      local v = 0.3 + math.random() * 0.5
      p.r, p.g, p.b, p.gravity, p.size, p.life = v, v, v, -0.004, 0.15, math.random(20, 40)
      if kind == "explosion" then
        p.size = 0.4 + math.random() * 0.4
        p.vx, p.vy, p.vz = p.vx * 4, p.vy * 3, p.vz * 4
        p.r, p.g, p.b = 0.9, 0.9, 0.85
      end
    elseif kind == "flame" then
      p.r, p.g, p.b, p.gravity, p.size, p.life = 1, 0.6, 0.1, -0.003, 0.08, 15
      p.vx, p.vy, p.vz = p.vx * 0.2, 0.01, p.vz * 0.2
    elseif kind == "heart" then
      p.r, p.g, p.b, p.gravity, p.size, p.life = 1, 0.2, 0.3, -0.005, 0.15, 30
    elseif kind == "happy" then
      p.r, p.g, p.b, p.gravity, p.size, p.life = 0.3, 1, 0.3, -0.002, 0.08, 30
    elseif kind == "crit" then
      p.r, p.g, p.b, p.gravity, p.size, p.life = 1, 1, 0.8, 0.02, 0.07, 15
      p.vx, p.vy, p.vz = p.vx * 4, p.vy * 3, p.vz * 4
    elseif kind == "portal" then
      p.r, p.g, p.b, p.gravity, p.size, p.life = 0.7, 0.2, 1, -0.01, 0.08, 30
    elseif kind == "splash" or kind == "bubble" then
      p.r, p.g, p.b, p.gravity, p.size, p.life = 0.5, 0.6, 1, 0.04, 0.06, 15
      p.vy = 0.15
    elseif kind == "snow" or kind == "egg" then
      p.r, p.g, p.b, p.gravity, p.size, p.life = 1, 1, 1, 0.04, 0.07, 15
    elseif kind == "fire_small" then
      p.r, p.g, p.b, p.gravity, p.size, p.life = 1, 0.5, 0.1, -0.006, 0.1, 12
    end
    M.add(p)
  end
end

function M.update(world)
  local j = 1
  for i = 1, #list do
    local p = list[i]
    p.age = p.age + 1
    p.px, p.py, p.pz = p.x, p.y, p.z
    p.vy = p.vy - p.gravity
    p.vx, p.vy, p.vz = p.vx * p.drag, p.vy * p.drag, p.vz * p.drag
    local nx, ny, nz = p.x + p.vx, p.y + p.vy, p.z + p.vz
    if p.collide and world and blocks.SOLID[world:getBlock(math.floor(nx), math.floor(ny), math.floor(nz))] == 1 then
      p.vx, p.vy, p.vz = p.vx * 0.5, 0, p.vz * 0.5
      nx, ny, nz = p.x + p.vx, p.y, p.z + p.vz
    end
    p.x, p.y, p.z = nx, ny, nz
    if p.age < p.life then
      list[j] = p
      j = j + 1
    end
  end
  for i = j, #list do list[i] = nil end
end

-- Rysowanie: kamera daje wektory "w prawo" i "w górę"
function M.draw(camera, alpha, lightFn)
  if #list == 0 then return end
  local v = camera.view
  local rx, ry, rz = v[1], v[2], v[3]
  local ux, uy, uz = v[5], v[6], v[7]
  local n = 0
  for i = 1, #list do
    local p = list[i]
    local x = p.px + (p.x - p.px) * alpha
    local y = p.py + (p.y - p.py) * alpha
    local z = p.pz + (p.z - p.pz) * alpha
    local s = p.size
    local l = lightFn and lightFn(x, y, z) or 1
    if p.gravity < 0 or p.tile == nil and (p.r == 1 and p.g == 0.6) then l = 1 end
    local r, g, b, a = p.r * l, p.g * l, p.b * l, p.a * (1 - math.max(0, (p.age - p.life + 5) / 5))
    local ax, ay, az = (rx + ux) * s, (ry + uy) * s, (rz + uz) * s
    local bx, by, bz = (rx - ux) * s, (ry - uy) * s, (rz - uz) * s
    local base = n * 6
    verts[base + 1] = { x - ax, y - ay, z - az, p.u0, p.v1, r, g, b, a }
    verts[base + 2] = { x + bx, y + by, z + bz, p.u1, p.v1, r, g, b, a }
    verts[base + 3] = { x + ax, y + ay, z + az, p.u1, p.v0, r, g, b, a }
    verts[base + 4] = { x - ax, y - ay, z - az, p.u0, p.v1, r, g, b, a }
    verts[base + 5] = { x + ax, y + ay, z + az, p.u1, p.v0, r, g, b, a }
    verts[base + 6] = { x - bx, y - by, z - bz, p.u0, p.v0, r, g, b, a }
    n = n + 1
  end
  for i = n * 6 + 1, #verts do verts[i] = nil end
  mesh:setVertices(verts)
  mesh:setDrawRange(1, n * 6)
  local s = shader.entity
  love.graphics.setShader(s)
  s:send("u_model", "row", mat4.identity(ident))
  s:send("u_light", 1)
  love.graphics.setMeshCullMode("none")
  love.graphics.draw(mesh)
end

return M
