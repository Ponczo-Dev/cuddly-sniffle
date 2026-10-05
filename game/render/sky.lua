-- render/sky.lua
-- Niebo: kolor zależny od pory dnia i pogody, wschody/zachody, słońce,
-- księżyc, gwiazdy i chmury (jak w Beta). Kolor mgły pasuje do nieba.

local mat4 = require("core.mat4")
local shader = require("render.shader")
local Rng = require("core.rng")

local M = {}

local sunMesh, moonMesh, starsMesh, cloudMesh, cloudImage
local rot, tmp, viewRot = mat4.new(), mat4.new(), mat4.new()

local function lerp(a, b, t) return a + (b - a) * t end

local function quad(size, r, g, b, a)
  local s = size
  return {
    { -s, 100, -s, 0, 0, r, g, b, a }, { s, 100, -s, 1, 0, r, g, b, a }, { s, 100, s, 1, 1, r, g, b, a },
    { -s, 100, -s, 0, 0, r, g, b, a }, { s, 100, s, 1, 1, r, g, b, a }, { -s, 100, s, 0, 1, r, g, b, a },
  }
end

local function makeImage(size, fn)
  local data = love.image.newImageData(size, size)
  data:mapPixel(function(x, y) return fn(x, y) end)
  local img = love.graphics.newImage(data)
  img:setFilter("nearest", "nearest")
  return img
end

function M.load()
  local format = {
    { "VertexPosition", "float", 3 }, { "VertexTexCoord", "float", 2 }, { "VertexColor", "byte", 4 },
  }
  local sunImg = makeImage(16, function(x, y)
    local d = math.max(math.abs(x - 7.5), math.abs(y - 7.5))
    if d < 4 then return 1, 1, 0.85, 1 end
    if d < 6 then return 1, 0.95, 0.6, 0.6 end
    return 1, 0.9, 0.5, 0.15
  end)
  local rng = Rng.new(5)
  local moonImg = makeImage(16, function(x, y)
    local d = math.max(math.abs(x - 7.5), math.abs(y - 7.5))
    if d < 5 then
      local v = 0.85 + rng:next() * 0.1
      if (x == 6 and y == 6) or (x == 9 and y == 9) or (x == 9 and y == 5) then v = 0.6 end
      return v, v, v * 1.05, 1
    end
    return 0.8, 0.8, 0.9, 0.1
  end)
  sunMesh = love.graphics.newMesh(format, quad(30, 1, 1, 1, 1), "triangles", "static")
  sunMesh:setTexture(sunImg)
  moonMesh = love.graphics.newMesh(format, quad(20, 1, 1, 1, 1), "triangles", "static")
  moonMesh:setTexture(moonImg)

  -- gwiazdy: małe kwadraty rozrzucone po sferze
  local verts = {}
  local srng = Rng.new(10842)
  local white = makeImage(1, function() return 1, 1, 1, 1 end)
  for _ = 1, 900 do
    local x, y, z = srng:next() * 2 - 1, srng:next() * 2 - 1, srng:next() * 2 - 1
    local len = math.sqrt(x * x + y * y + z * z)
    if len > 0.01 and len < 1 then
      x, y, z = x / len * 100, y / len * 100, z / len * 100
      local s = 0.15 + srng:next() * 0.25
      -- dwa wektory styczne
      local ax, ay, az = -z, 0, x
      local al = math.sqrt(ax * ax + az * az)
      if al < 0.01 then ax, ay, az, al = 1, 0, 0, 1 end
      ax, az = ax / al * s, az / al * s
      local bx, by, bz = y * az - z * ay, z * ax - x * az, x * ay - y * ax
      local bl = math.sqrt(bx * bx + by * by + bz * bz)
      bx, by, bz = bx / bl * s, by / bl * s, bz / bl * s
      local b = 0.7 + srng:next() * 0.3
      local p1 = { x - ax - bx, y - ay - by, z - az - bz }
      local p2 = { x + ax - bx, y + ay - by, z + az - bz }
      local p3 = { x + ax + bx, y + ay + by, z + az + bz }
      local p4 = { x - ax + bx, y - ay + by, z - az + bz }
      for _, p in ipairs({ p1, p2, p3, p1, p3, p4 }) do
        verts[#verts + 1] = { p[1], p[2], p[3], 0.5, 0.5, b, b, b, 1 }
      end
    end
  end
  starsMesh = love.graphics.newMesh(format, verts, "triangles", "static")
  starsMesh:setTexture(white)

  -- chmury: tekstura z szumu, kafelkowana
  local nrng = Rng.new(777)
  local grid = {}
  for i = 0, 63 * 64 + 63 do grid[i] = nrng:next() end
  cloudImage = makeImage(64, function(x, y)
    -- rozmycie dla zbitych chmur
    local s = 0
    for dy = -1, 1 do
      for dx = -1, 1 do
        s = s + grid[((x + dx) % 64) + ((y + dy) % 64) * 64]
      end
    end
    s = s / 9
    if s > 0.53 then return 1, 1, 1, 0.8 end
    return 1, 1, 1, 0
  end)
  cloudImage:setWrap("repeat", "repeat")
  cloudMesh = love.graphics.newMesh(format, 6, "triangles", "stream")
  cloudMesh:setTexture(cloudImage)
end

-- Kolory nieba i mgły. Zwraca skyColor, fogColor, sunsetColor|nil
function M.colors(game, camY)
  local d = game:daylight()
  local t = game:celestialAngle()
  local b = (d - 0.2) / 0.8
  local base = { 0.47, 0.65, 1.0 }
  if game.biomeAt then
    local p = game.player
    local bio = game.biomeAt(math.floor(p.x), math.floor(p.z))
    if bio and bio.fog then base = { bio.fog[1] * 0.8 + 0.1, bio.fog[2] * 0.8 + 0.1, bio.fog[3] } end
  end
  local sky = { base[1] * b, base[2] * b, base[3] * b }
  local rain = game.weather.strength or 0
  if rain > 0 then
    local g = (sky[1] * 0.3 + sky[2] * 0.59 + sky[3] * 0.11) * 0.6
    for i = 1, 3 do sky[i] = lerp(sky[i], g, rain * 0.75) end
  end
  local fog = { lerp(sky[1], 0.75 * b + 0.05, 0.4), lerp(sky[2], 0.82 * b + 0.05, 0.4),
    lerp(sky[3], 1.0 * b + 0.07, 0.3) }
  if rain > 0 then
    for i = 1, 3 do fog[i] = fog[i] * (1 - rain * 0.4) end
  end
  -- czerwień zachodu/wschodu
  local sunset
  local c = math.cos(t * math.pi * 2)
  if c > -0.4 and c < 0.4 then
    local f = (1 - math.abs(c) / 0.4)
    sunset = { 1, 0.45 + f * 0.25, 0.25, f * f * 0.6 }
    for i = 1, 3 do fog[i] = lerp(fog[i], sunset[i], sunset[4] * 0.5) end
  end
  -- pod ziemią w ciemności niebo czernieje
  if camY < 40 then
    local f = math.max(0, (camY - 10) / 30)
    for i = 1, 3 do sky[i], fog[i] = sky[i] * f, fog[i] * f end
  end
  return sky, fog, sunset
end

-- Rysuje słońce, księżyc i gwiazdy (przed terenem, bez bufora głębi)
function M.drawCelestial(game, camera, alpha)
  local g = love.graphics
  local s = shader.entity
  local angle = game:celestialAngle(alpha)
  local rain = game.weather.strength or 0
  mat4.fpsView(viewRot, 0, 0, 0, camera.yaw, camera.pitch)
  s:send("u_view", "row", viewRot)
  s:send("u_fogStart", 10000)
  s:send("u_fogEnd", 20000)
  g.setShader(s)
  g.setDepthMode("always", false)
  g.setMeshCullMode("none")
  g.setBlendMode("add")
  s:send("u_light", 1)
  s:send("u_tint", { 0, 0, 0, 0 })
  -- obrót nieba: słońce wschodzi na wschodzie (+X)
  mat4.rotationZ(rot, -angle * math.pi * 2 + math.pi / 2)
  local vis = 1 - rain
  g.setColor(1, 1, 1, vis)
  s:send("u_model", "row", rot)
  g.draw(sunMesh)
  mat4.rotationZ(tmp, math.pi)
  mat4.multiply(tmp, rot, tmp)
  s:send("u_model", "row", tmp)
  g.draw(moonMesh)
  local night = 1 - (game:daylight() - 0.2) / 0.8
  local starA = math.max(0, night * 1.4 - 0.4) * vis
  if starA > 0 then
    g.setColor(1, 1, 1, starA)
    s:send("u_model", "row", rot)
    g.draw(starsMesh)
  end
  g.setColor(1, 1, 1, 1)
  g.setBlendMode("alpha")
  g.setDepthMode("lequal", true)
  s:send("u_view", "row", camera.view)
end

-- Chmury: płaska warstwa na wysokości 108, dryfuje powoli
function M.drawClouds(game, camera, alpha, fogColor, fogEnd)
  local g = love.graphics
  local s = shader.entity
  local time = game.time + alpha
  local scale = 12 -- jeden piksel tekstury = 12 bloków
  local cx, cz = camera.x, camera.z
  local drift = time * 0.03
  local R = 220
  local y = 108.33
  local b = game:daylight()
  local c = { 1, 1, 1 }
  if game.weather.strength > 0 then
    local k = 1 - game.weather.strength * 0.5
    c = { k, k, k }
  end
  local x0, x1, z0, z1 = cx - R, cx + R, cz - R, cz + R
  local function uv(x, z) return (x + drift) / scale / 64, z / scale / 64 end
  local u0, v0 = uv(x0, z0)
  local u1, v1 = uv(x1, z1)
  local r, gg, bb = c[1] * b, c[2] * b, c[3] * b
  cloudMesh:setVertices({
    { x0, y, z0, u0, v0, r, gg, bb, 1 }, { x1, y, z0, u1, v0, r, gg, bb, 1 },
    { x1, y, z1, u1, v1, r, gg, bb, 1 },
    { x0, y, z0, u0, v0, r, gg, bb, 1 }, { x1, y, z1, u1, v1, r, gg, bb, 1 },
    { x0, y, z1, u0, v1, r, gg, bb, 1 },
  })
  g.setShader(s)
  s:send("u_model", "row", mat4.identity(tmp))
  s:send("u_light", 1)
  s:send("u_fogStart", fogEnd * 0.8)
  s:send("u_fogEnd", R)
  g.setMeshCullMode("none")
  g.setDepthMode("lequal", false)
  g.draw(cloudMesh)
  g.setDepthMode("lequal", true)
  local _ = fogColor
end

return M
