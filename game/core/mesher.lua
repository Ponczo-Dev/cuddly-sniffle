-- core/mesher.lua
-- Zamienia bloki chunka na trójkąty do narysowania (mesh).
--  * rysuje tylko ściany widoczne (sąsiad to powietrze/blok przezroczysty),
--  * ambient occlusion (przyciemnione narożniki jak w MC),
--  * płynne światło (średnia z 4 komórek przy wierzchołku).
--
-- Wierzchołek = x, y, z, u, v, r, g, b gdzie:
--   r = światło nieba (0..255), g = światło bloków (0..255),
--   b = cieniowanie ściany * AO (0..255).
-- Pora dnia jest liczona w shaderze, więc zmiana dnia nie wymaga przebudowy.
--
-- Wyjście trafia do "bufora" z metodą buf:vertex(x, y, z, u, v, r, g, b).
-- W grze to szybki bufor FFI (render/meshbuffer.lua), w testach zwykła tabela.

local blocks = require("core.blocks")
local tiles = require("core.tiles")
local bytearray = require("core.bytearray")

local M = {}

local SIZE, HEIGHT = 16, 128
-- Kopia chunka z obwódką 1 bloku: 18 x 130 x 18
local PW = SIZE + 2
local PSZ = PW            -- krok indeksu dla z
local PSY = PW * PW       -- krok indeksu dla y
local PN = PW * PW * (HEIGHT + 2)

local pb = bytearray.new(PN) -- id bloków
local pm = bytearray.new(PN) -- meta
local ps = bytearray.new(PN) -- światło nieba
local pl = bytearray.new(PN) -- światło bloków

local OPQ = blocks.OPAQUE
local defs = blocks.defs
local floor = math.floor

local TILE = 1 / tiles.COLUMNS
local EPS = 1 / 4096 -- mały margines UV, żeby nie łapać pikseli sąsiednich kafelków
local TILE_IN = TILE - 2 * EPS
local AO_CURVE = { [0] = 0.42, 0.62, 0.81, 1.0 }

local function pidx(x, y, z) -- x, z: -1..16, y: -1..128
  return (x + 1) + (z + 1) * PSZ + (y + 1) * PSY
end

-- ---------------------------------------------------------------------------
-- Ściany sześcianu. Narożniki w kolejności przeciwnej do ruchu wskazówek
-- zegara, patrząc z zewnątrz (BL, BR, TR, TL) - to "przód" trójkąta.
-- ---------------------------------------------------------------------------
local FACES = {
  { n = { 1, 0, 0 }, c = { { 1, 0, 1 }, { 1, 0, 0 }, { 1, 1, 0 }, { 1, 1, 1 } }, shade = 0.6 },
  { n = { -1, 0, 0 }, c = { { 0, 0, 0 }, { 0, 0, 1 }, { 0, 1, 1 }, { 0, 1, 0 } }, shade = 0.6 },
  { n = { 0, 1, 0 }, c = { { 0, 1, 1 }, { 1, 1, 1 }, { 1, 1, 0 }, { 0, 1, 0 } }, shade = 1.0 },
  { n = { 0, -1, 0 }, c = { { 1, 0, 1 }, { 0, 0, 1 }, { 0, 0, 0 }, { 1, 0, 0 } }, shade = 0.5 },
  { n = { 0, 0, 1 }, c = { { 0, 0, 1 }, { 1, 0, 1 }, { 1, 1, 1 }, { 0, 1, 1 } }, shade = 0.8 },
  { n = { 0, 0, -1 }, c = { { 1, 0, 0 }, { 0, 0, 0 }, { 0, 1, 0 }, { 1, 1, 0 } }, shade = 0.8 },
}
M.FACES = FACES

-- UV wierzchołka z jego pozycji w bloku (działa też dla "box")
local function faceUV(face, x, y, z)
  if face == 1 then return 1 - z, 1 - y end
  if face == 2 then return z, 1 - y end
  if face == 3 then return x, z end
  if face == 4 then return x, 1 - z end
  if face == 5 then return x, 1 - y end
  return 1 - x, 1 - y
end

-- Prekomputacja przesunięć indeksów dla AO:
-- dla każdej ściany i narożnika: sąsiad boczny 1, boczny 2, narożny
for f = 1, 6 do
  local F = FACES[f]
  local nx, ny, nz = F.n[1], F.n[2], F.n[3]
  F.dn = nx + nz * PSZ + ny * PSY
  F.ao = {}
  F.uv = {}
  for k = 1, 4 do
    local c = F.c[k]
    local d = {}
    -- dwie osie styczne do ściany
    local axes = {}
    if nx == 0 then axes[#axes + 1] = 1 end
    if ny == 0 then axes[#axes + 1] = 2 end
    if nz == 0 then axes[#axes + 1] = 3 end
    local o1 = { 0, 0, 0 }
    local o2 = { 0, 0, 0 }
    o1[axes[1]] = c[axes[1]] == 1 and 1 or -1
    o2[axes[2]] = c[axes[2]] == 1 and 1 or -1
    d[1] = o1[1] + o1[3] * PSZ + o1[2] * PSY
    d[2] = o2[1] + o2[3] * PSZ + o2[2] * PSY
    d[3] = d[1] + d[2]
    F.ao[k] = d
    local u, v = faceUV(f, c[1], c[2], c[3])
    F.uv[k] = { u, v }
  end
end

-- ---------------------------------------------------------------------------
-- Kopiowanie chunka i sąsiadów do bufora z obwódką
-- ---------------------------------------------------------------------------
local STONE = 1

function M.gather(world, cx, cz)
  -- wiersz y = -1: lity blok (żeby nie rysować spodu świata)
  local topSky = world.noSky and 0 or 15
  for z = -1, SIZE do
    for x = -1, SIZE do
      local i = pidx(x, -1, z)
      pb[i], pm[i], ps[i], pl[i] = STONE, 0, 0, 0
      local j = pidx(x, HEIGHT, z)
      pb[j], pm[j], ps[j], pl[j] = 0, 0, topSky, 0
    end
  end

  for dz = -1, 1 do
    for dx = -1, 1 do
      local c = world:getChunk(cx + dx, cz + dz)
      local x0, x1 = 0, SIZE - 1
      if dx == -1 then x0 = SIZE - 1 elseif dx == 1 then x1 = 0 end
      local z0, z1 = 0, SIZE - 1
      if dz == -1 then z0 = SIZE - 1 elseif dz == 1 then z1 = 0 end
      local offX, offZ = dx * SIZE, dz * SIZE
      if c then
        local cb, cm, cs, cl = c.blocks, c.meta, c.sky, c.blockLight
        for z = z0, z1 do
          for x = x0, x1 do
            local src = x + z * SIZE
            local dst = pidx(x + offX, 0, z + offZ)
            for y = 0, HEIGHT - 1 do
              pb[dst], pm[dst], ps[dst], pl[dst] = cb[src], cm[src], cs[src], cl[src]
              src = src + 256
              dst = dst + PSY
            end
          end
        end
      else
        -- brak sąsiada: traktujemy jak lity kamień (brzeg świata)
        for z = z0, z1 do
          for x = x0, x1 do
            local dst = pidx(x + offX, 0, z + offZ)
            for _ = 0, HEIGHT - 1 do
              pb[dst], pm[dst], ps[dst], pl[dst] = STONE, 0, 0, 0
              dst = dst + PSY
            end
          end
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Widoczność ściany
-- ---------------------------------------------------------------------------
local function faceVisible(def, id, nid)
  if OPQ[nid] == 1 then return false end
  if nid == id and def.cullSame then return false end
  if def.liquid then
    local nd = defs[nid]
    if nd and nd.liquid == def.liquid then return false end
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Sześcian z AO i płynnym światłem
-- ---------------------------------------------------------------------------
local cs, cb, ca = {}, {}, {} -- światło nieba / bloków / AO dla 4 narożników

local ORDER_A = { 1, 2, 3, 1, 3, 4 }
local ORDER_B = { 2, 3, 4, 2, 4, 1 }
local BACK = { 1, 3, 2, 1, 4, 3 }

local function emitQuad(buf, F, bx, by, bz, u0, v0, shade)
  -- kolejność trójkątów zależna od AO (unika "zygzaków" w cieniu)
  local ord = (ca[1] + ca[3] < ca[2] + ca[4]) and ORDER_B or ORDER_A
  local corners, uvs = F.c, F.uv
  for j = 1, 6 do
    local k = ord[j]
    local c = corners[k]
    local uv = uvs[k]
    buf:vertex(bx + c[1], by + c[2], bz + c[3],
      u0 + uv[1] * TILE_IN, v0 + uv[2] * TILE_IN,
      cs[k], cb[k], shade * AO_CURVE[ca[k]] * 255)
  end
end

local function meshCube(buf, def, id, meta, p, x, y, z)
  for f = 1, 6 do
    local F = FACES[f]
    local np = p + F.dn
    local nid = pb[np]
    if faceVisible(def, id, nid) then
      local baseS, baseB = ps[np], pl[np]
      for k = 1, 4 do
        local d = F.ao[k]
        local s1 = OPQ[pb[np + d[1]]]
        local s2 = OPQ[pb[np + d[2]]]
        local sc = OPQ[pb[np + d[3]]]
        local ao
        if s1 == 1 and s2 == 1 then ao = 0 else ao = 3 - s1 - s2 - sc end
        ca[k] = ao
        -- płynne światło: średnia z przezroczystych komórek wokół narożnika
        local sumS, sumB, cnt = baseS, baseB, 1
        if s1 == 0 then sumS = sumS + ps[np + d[1]]; sumB = sumB + pl[np + d[1]]; cnt = cnt + 1 end
        if s2 == 0 then sumS = sumS + ps[np + d[2]]; sumB = sumB + pl[np + d[2]]; cnt = cnt + 1 end
        if sc == 0 and (s1 == 0 or s2 == 0) then
          sumS = sumS + ps[np + d[3]]; sumB = sumB + pl[np + d[3]]; cnt = cnt + 1
        end
        cs[k] = sumS * 17 / cnt
        cb[k] = sumB * 17 / cnt
      end
      local t = blocks.faceTile(def, f, meta)
      local u0 = (t % 16) * TILE + EPS
      local v0 = floor(t / 16) * TILE + EPS
      emitQuad(buf, F, x, y, z, u0, v0, F.shade)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Prostopadłościan (płyta, pochodnia, drzwi, kaktus...) - bez AO
-- ---------------------------------------------------------------------------
local function meshOneBox(buf, def, meta, p, x, y, z, x0, y0, z0, x1, y1, z1, tileOverride)
  local sx, sy, sz = x1 - x0, y1 - y0, z1 - z0
  for f = 1, 6 do
    local F = FACES[f]
    local n = F.n
    -- czy ściana leży na granicy bloku?
    local onEdge = (n[1] == 1 and x1 >= 1) or (n[1] == -1 and x0 <= 0)
      or (n[2] == 1 and y1 >= 1) or (n[2] == -1 and y0 <= 0)
      or (n[3] == 1 and z1 >= 1) or (n[3] == -1 and z0 <= 0)
    local np = p + F.dn
    local visible = true
    if onEdge and OPQ[pb[np]] == 1 then visible = false end
    if visible then
      local lp = onEdge and np or p
      local s, b = ps[lp] * 17, pl[lp] * 17
      -- komórka samego bloku bywa ciemna (np. płyta pochłania światło)
      if not onEdge and OPQ[pb[np]] == 0 then
        local s2, b2 = ps[np] * 17, pl[np] * 17
        if s2 > s then s = s2 end
        if b2 > b then b = b2 end
      end
      for k = 1, 4 do cs[k], cb[k], ca[k] = s, b, 3 end
      local t = tileOverride or blocks.faceTile(def, f, meta)
      local tu = (t % 16) * TILE
      local tv = floor(t / 16) * TILE
      -- UV z faktycznej pozycji narożnika (fragment tekstury jak w MC)
      for j = 1, 6 do
        local k = ORDER_A[j]
        local c = F.c[k]
        local px = x0 + c[1] * sx
        local py = y0 + c[2] * sy
        local pz = z0 + c[3] * sz
        local u, v = faceUV(f, px, py, pz)
        if u < 0 then u = 0 elseif u > 1 then u = 1 end
        if v < 0 then v = 0 elseif v > 1 then v = 1 end
        buf:vertex(x + px, y + py, z + pz,
          tu + EPS + u * (TILE - 2 * EPS), tv + EPS + v * (TILE - 2 * EPS),
          s, b, F.shade * 255)
      end
    end
  end
end

-- Blok z jednego albo kilku prostopadłościanów (def.boxes: tłok, płotek, dźwignia)
local function meshBox(buf, def, id, meta, p, x, y, z)
  if def.boxes then
    local list = def.boxes(meta)
    for i = 1, #list do
      local bx = list[i]
      meshOneBox(buf, def, meta, p, x, y, z, bx[1], bx[2], bx[3], bx[4], bx[5], bx[6], bx.tile)
    end
    return
  end
  local x0, y0, z0, x1, y1, z1 = blocks.bounds(def, meta)
  meshOneBox(buf, def, meta, p, x, y, z, x0, y0, z0, x1, y1, z1)
end

-- ---------------------------------------------------------------------------
-- Roślina "X" (dwie skrzyżowane płaszczyzny, widoczne z obu stron)
-- ---------------------------------------------------------------------------
local CROSS = {
  { 0.1, 0.1, 0.9, 0.9 },
  { 0.1, 0.9, 0.9, 0.1 },
}
local function meshCross(buf, def, id, meta, p, x, y, z)
  local s, b = ps[p] * 17, pl[p] * 17
  local t = blocks.faceTile(def, 3, meta)
  local u0 = (t % 16) * TILE + EPS
  local v0 = floor(t / 16) * TILE + EPS
  local u1, v1 = u0 + TILE_IN, v0 + TILE_IN
  local h = 1
  local shade = 0.9 * 255
  for i = 1, 2 do
    local q = CROSS[i]
    local ax, az, bx, bz = x + q[1], z + q[2], x + q[3], z + q[4]
    -- przód
    buf:vertex(ax, y, az, u0, v1, s, b, shade)
    buf:vertex(bx, y, bz, u1, v1, s, b, shade)
    buf:vertex(bx, y + h, bz, u1, v0, s, b, shade)
    buf:vertex(ax, y, az, u0, v1, s, b, shade)
    buf:vertex(bx, y + h, bz, u1, v0, s, b, shade)
    buf:vertex(ax, y + h, az, u0, v0, s, b, shade)
    -- tył
    buf:vertex(bx, y, bz, u1, v1, s, b, shade)
    buf:vertex(ax, y, az, u0, v1, s, b, shade)
    buf:vertex(ax, y + h, az, u0, v0, s, b, shade)
    buf:vertex(bx, y, bz, u1, v1, s, b, shade)
    buf:vertex(ax, y + h, az, u0, v0, s, b, shade)
    buf:vertex(bx, y + h, bz, u1, v0, s, b, shade)
  end
end

-- ---------------------------------------------------------------------------
-- Ciecz: obniżona powierzchnia zależna od poziomu (meta)
-- ---------------------------------------------------------------------------
local function liquidHeight(meta, above)
  if above then return 1 end
  if meta == 0 or meta >= 8 then return 14 / 16 end
  return (8 - meta) / 9
end
M.liquidHeight = liquidHeight

local function meshLiquid(buf, def, id, meta, p, x, y, z)
  local aboveDef = defs[pb[p + PSY]]
  local above = aboveDef and aboveDef.liquid == def.liquid
  local h = liquidHeight(meta, above)
  local t = blocks.faceTile(def, 3, meta)
  local tu = (t % 16) * TILE
  local tv = floor(t / 16) * TILE
  for f = 1, 6 do
    local F = FACES[f]
    local np = p + F.dn
    local nid = pb[np]
    local visible = faceVisible(def, id, nid)
    if f == 3 and not above then visible = true end -- powierzchnia zawsze widoczna
    if visible then
      local s, b = ps[np] * 17, pl[np] * 17
      if OPQ[nid] == 1 or f == 3 then
        s, b = math.max(ps[p], ps[np]) * 17, math.max(pl[p], pl[np]) * 17
      end
      for j = 1, 6 do
        local k = ORDER_A[j]
        local c = F.c[k]
        local py = c[2] * h
        local u, v = faceUV(f, c[1], py, c[3])
        buf:vertex(x + c[1], y + py, z + c[3],
          tu + EPS + u * (TILE - 2 * EPS), tv + EPS + v * (TILE - 2 * EPS),
          s, b, F.shade * 255)
      end
      -- powierzchnię wody widać też od spodu (gdy nurkujemy)
      if f == 3 and def.layer == "translucent" then
        for j = 1, 6 do
          local k = BACK[j]
          local c = F.c[k]
          local py = c[2] * h
          local u, v = faceUV(f, c[1], py, c[3])
          buf:vertex(x + c[1], y + py, z + c[3],
            tu + EPS + u * (TILE - 2 * EPS), tv + EPS + v * (TILE - 2 * EPS),
            s, b, 0.5 * 255)
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Tory: płytka nad ziemią, obrót tekstury i wzniesienia
-- ---------------------------------------------------------------------------
local RAIL_ROT = { [0] = 0, [1] = 1, [2] = 1, [3] = 1, [4] = 0, [5] = 0, [6] = 0, [7] = 1, [8] = 2, [9] = 3 }
local RAIL_UP = { [2] = { 1, 0 }, [3] = { -1, 0 }, [4] = { 0, -1 }, [5] = { 0, 1 } }
local railCorners = { { 0, 1 }, { 1, 1 }, { 1, 0 }, { 0, 0 } } -- (x, z) BL, BR, TR, TL od góry

local function meshRail(buf, def, id, meta, p, x, y, z)
  local shape = id == 66 and meta % 16 or meta % 8
  local s, b = ps[p] * 17, pl[p] * 17
  local t = blocks.faceTile(def, 3, meta)
  local tu = (t % 16) * TILE + EPS
  local tv = floor(t / 16) * TILE + EPS
  local rot = RAIL_ROT[shape] or 0
  local up = RAIL_UP[shape]
  local h = 1 / 16
  local verts = {}
  for k = 1, 4 do
    local c = railCorners[k]
    local cy = h
    if up then
      if (up[1] > 0 and c[1] == 1) or (up[1] < 0 and c[1] == 0)
        or (up[2] > 0 and c[2] == 1) or (up[2] < 0 and c[2] == 0) then
        cy = cy + 1
      end
    end
    -- UV z obrotem o rot * 90 stopni
    local u, v = c[1], c[2]
    for _ = 1, rot do u, v = 1 - v, u end
    verts[k] = { x + c[1], y + cy, z + c[2], tu + u * TILE_IN, tv + v * TILE_IN }
  end
  local order = { 1, 2, 3, 1, 3, 4, 1, 3, 2, 1, 4, 3 }
  for j = 1, 12 do
    local v = verts[order[j]]
    buf:vertex(v[1], v[2], v[3], v[4], v[5], s, b, j <= 6 and 255 or 160)
  end
end

-- ---------------------------------------------------------------------------
-- Budowa mesha chunka.
--   opaqueBuf: bloki nieprzezroczyste i "wycinane" (liście, rośliny)
--   transBuf:  bloki półprzezroczyste (woda, lód)
-- Przed wywołaniem: M.gather(world, cx, cz)
-- ---------------------------------------------------------------------------
function M.build(chunk, opaqueBuf, transBuf)
  local maxY = chunk.maxY
  if maxY >= HEIGHT then maxY = HEIGHT - 1 end
  for y = 0, maxY do
    for z = 0, SIZE - 1 do
      local p = pidx(0, y, z)
      for x = 0, SIZE - 1 do
        local id = pb[p]
        if id ~= 0 then
          local def = defs[id]
          if def then
            local buf = def.layer == "translucent" and transBuf or opaqueBuf
            local shape = def.shape
            local meta = pm[p]
            if shape == "cube" then
              meshCube(buf, def, id, meta, p, x, y, z)
            elseif shape == "box" then
              meshBox(buf, def, id, meta, p, x, y, z)
            elseif shape == "cross" then
              meshCross(buf, def, id, meta, p, x, y, z)
            elseif shape == "liquid" then
              meshLiquid(buf, def, id, meta, p, x, y, z)
            elseif shape == "rail" then
              meshRail(buf, def, id, meta, p, x, y, z)
            end
          end
        end
        p = p + 1
      end
    end
  end
end

-- Prosty bufor na zwykłej tabeli (testy, fallback bez FFI)
local TableBuffer = {}
TableBuffer.__index = TableBuffer

function M.newTableBuffer()
  return setmetatable({ n = 0, data = {} }, TableBuffer)
end

function TableBuffer:vertex(x, y, z, u, v, r, g, b)
  local d = self.data
  local i = self.n * 8
  d[i + 1], d[i + 2], d[i + 3], d[i + 4] = x, y, z, u
  d[i + 5], d[i + 6], d[i + 7], d[i + 8] = v, r, g, b
  self.n = self.n + 1
end

function TableBuffer:reset()
  self.n = 0
end

return M
