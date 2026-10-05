-- render/weather.lua
-- Deszcz i śnieg wokół gracza: pionowe pasy z przesuwaną teksturą,
-- tylko tam, gdzie nad głową jest niebo (jak w MC).

local mat4 = require("core.mat4")
local shader = require("render.shader")

local M = {}

local rainImg, snowImg, rainMesh, snowMesh
local ident = mat4.new()

local function makeImage(w, h, fn)
  local data = love.image.newImageData(w, h)
  data:mapPixel(fn)
  local img = love.graphics.newImage(data)
  img:setFilter("nearest", "nearest")
  img:setWrap("repeat", "repeat")
  return img
end

function M.load()
  local seed = 1
  local function rnd()
    seed = (seed * 16807) % 2147483647
    return seed / 2147483647
  end
  -- cienkie smugi: 64 kolumny tekstury na blok, tylko co kilka zapalona
  local rainCols = {}
  for x = 0, 63 do
    rainCols[x] = { start = math.floor(rnd() * 64), len = 5 + math.floor(rnd() * 8), on = rnd() < 0.18 }
  end
  rainImg = makeImage(64, 64, function(x, y)
    local c = rainCols[x]
    if c.on and ((y - c.start) % 64) < c.len then return 0.65, 0.75, 1, 0.7 end
    return 0, 0, 0, 0
  end)
  local flakes = {}
  for _ = 1, 40 do flakes[#flakes + 1] = { math.floor(rnd() * 16), math.floor(rnd() * 64) } end
  snowImg = makeImage(16, 64, function(x, y)
    for _, f in ipairs(flakes) do
      if f[1] == x and f[2] == y then return 1, 1, 1, 0.95 end
    end
    return 0, 0, 0, 0
  end)
  local format = {
    { "VertexPosition", "float", 3 }, { "VertexTexCoord", "float", 2 }, { "VertexColor", "byte", 4 },
  }
  rainMesh = love.graphics.newMesh(format, 6 * 600, "triangles", "stream")
  rainMesh:setTexture(rainImg)
  snowMesh = love.graphics.newMesh(format, 6 * 600, "triangles", "stream")
  snowMesh:setTexture(snowImg)
end

local rainVerts, snowVerts = {}, {}

-- Zwraca liczbę kolumn z deszczem w pobliżu (do dźwięku)
function M.draw(game, camera, alpha, light)
  local strength = game.weather.strength or 0
  if strength < 0.05 then return 0 end
  local world = game.world
  local cx, cy, cz = math.floor(camera.x), camera.y, math.floor(camera.z)
  local time = (game.time + alpha)
  local R = 9
  local nr, ns = 0, 0
  local near = 0
  for dz = -R, R do
    for dx = -R, R do
      if dx * dx + dz * dz <= R * R then
        local x, z = cx + dx, cz + dz
        local h = world:getHeight(x, z)
        local top = cy + 12
        if h < top then
          local bottom = math.max(h, cy - 10)
          local biome = game.biomeAt and game.biomeAt(x, z)
          if not (biome and biome.dry) then
            local snow = biome and biome.snowy
            -- płaszczyzna zwrócona do kamery (obrót wokół Y)
            local px, pz = x + 0.5, z + 0.5
            local ddx, ddz = px - camera.x, pz - camera.z
            local len = math.sqrt(ddx * ddx + ddz * ddz)
            if len < 0.01 then len = 0.01 end
            local rx, rz = -ddz / len * 0.5, ddx / len * 0.5
            local speed = snow and 0.02 or 0.12
            local off = ((x * 3121 + z * 7193) % 64) / 64
            local v0 = (bottom - time * speed) / 4 + off
            local v1 = (top - time * speed) / 4 + off
            local a = strength * (1 - len / (R + 1))
            local l = light
            local verts, n
            if snow then verts, n = snowVerts, ns else verts, n = rainVerts, nr end
            local b = n * 6
            verts[b + 1] = { px - rx, bottom, pz - rz, 0, -v0, l, l, l, a }
            verts[b + 2] = { px + rx, bottom, pz + rz, 1, -v0, l, l, l, a }
            verts[b + 3] = { px + rx, top, pz + rz, 1, -v1, l, l, l, a }
            verts[b + 4] = { px - rx, bottom, pz - rz, 0, -v0, l, l, l, a }
            verts[b + 5] = { px + rx, top, pz + rz, 1, -v1, l, l, l, a }
            verts[b + 6] = { px - rx, top, pz - rz, 0, -v1, l, l, l, a }
            if snow then ns = ns + 1 else nr = nr + 1 end
            if len < 5 and not snow then near = near + 1 end
            if nr >= 600 or ns >= 600 then break end
          end
        end
      end
    end
  end
  local s = shader.entity
  love.graphics.setShader(s)
  s:send("u_model", "row", mat4.identity(ident))
  s:send("u_light", 1)
  love.graphics.setMeshCullMode("none")
  love.graphics.setDepthMode("lequal", false)
  if nr > 0 then
    for i = nr * 6 + 1, #rainVerts do rainVerts[i] = nil end
    rainMesh:setVertices(rainVerts)
    rainMesh:setDrawRange(1, nr * 6)
    love.graphics.draw(rainMesh)
  end
  if ns > 0 then
    for i = ns * 6 + 1, #snowVerts do snowVerts[i] = nil end
    snowMesh:setVertices(snowVerts)
    snowMesh:setDrawRange(1, ns * 6)
    love.graphics.draw(snowMesh)
  end
  love.graphics.setDepthMode("lequal", true)
  return near
end

return M
