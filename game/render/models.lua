-- render/models.lua
-- Modele 3D z prostopadłościanów (jak w Minecrafcie): moby, przedmioty
-- leżące na ziemi, strzały, spadające bloki, ręka gracza i ramka zaznaczenia.
-- Wymiary części w "pikselach" (1/16 bloku), model patrzy w stronę -Z.

local mat4 = require("core.mat4")
local blocks = require("core.blocks")
local tiles = require("core.tiles")
local items = require("core.items")
local shader = require("render.shader")
local atlas = require("render.atlas")
local icons = require("render.icons")
local meshbuffer = require("render.meshbuffer")

local M = {}

local P = 1 / 16
local FORMAT = meshbuffer.FORMAT
local whiteU, whiteV

-- ---------------------------------------------------------------------------
-- Budowanie siatek z prostopadłościanów
-- ---------------------------------------------------------------------------
local FACE_SHADE = { 0.6, 0.6, 1.0, 0.5, 0.8, 0.8 }
local FACES = {
  { { 1, 0, 1 }, { 1, 0, 0 }, { 1, 1, 0 }, { 1, 1, 1 } },
  { { 0, 0, 0 }, { 0, 0, 1 }, { 0, 1, 1 }, { 0, 1, 0 } },
  { { 0, 1, 1 }, { 1, 1, 1 }, { 1, 1, 0 }, { 0, 1, 0 } },
  { { 1, 0, 1 }, { 0, 0, 1 }, { 0, 0, 0 }, { 1, 0, 0 } },
  { { 0, 0, 1 }, { 1, 0, 1 }, { 1, 1, 1 }, { 0, 1, 1 } },
  { { 1, 0, 0 }, { 0, 0, 0 }, { 0, 1, 0 }, { 1, 1, 0 } },
}
local QUAD = { 1, 2, 3, 1, 3, 4 }
local UVS = { { 0, 1 }, { 1, 1 }, { 1, 0 }, { 0, 0 } }

-- box: { x0, y0, z0, x1, y1, z1 (piksele), color = {r,g,b}, tiles = {6 kafelków}|nil }
local function addBox(verts, b, scale)
  scale = scale or P
  local c = b.color or { 1, 1, 1 }
  for f = 1, 6 do
    local shade = FACE_SHADE[f]
    local tile = b.tiles and b.tiles[f]
    local u0, v0, size
    if tile then u0, v0, size = tiles.uv(tile) end
    for _, k in ipairs(QUAD) do
      local cc = FACES[f][k]
      local x = (b[1] + (b[4] - b[1]) * cc[1]) * scale
      local y = (b[2] + (b[5] - b[2]) * cc[2]) * scale
      local z = (b[3] + (b[6] - b[3]) * cc[3]) * scale
      local u, v
      if tile then
        local e = 0.0005
        u = u0 + e + UVS[k][1] * (size - 2 * e)
        v = v0 + e + UVS[k][2] * (size - 2 * e)
      else
        u, v = whiteU, whiteV
      end
      local fx = b.faceColors and b.faceColors[f] or c
      verts[#verts + 1] = { x, y, z, u, v, fx[1] * shade, fx[2] * shade, fx[3] * shade, 1 }
    end
  end
end

local function meshFromBoxes(boxes, scale)
  local verts = {}
  for _, b in ipairs(boxes) do addBox(verts, b, scale) end
  local mesh = love.graphics.newMesh(FORMAT, verts, "triangles", "static")
  mesh:setTexture(atlas.image)
  return mesh
end
M.meshFromBoxes = meshFromBoxes

local function B(x0, y0, z0, x1, y1, z1, color, extra)
  local b = { x0, y0, z0, x1, y1, z1, color = color }
  if extra then for k, v in pairs(extra) do b[k] = v end end
  return b
end

-- Część modelu: siatka + punkt obrotu (piksele) + rodzaj animacji
local function part(boxes, pivot, anim, phase)
  return { mesh = meshFromBoxes(boxes), pivot = pivot or { 0, 0, 0 }, anim = anim, phase = phase or 0 }
end

-- ---------------------------------------------------------------------------
-- Modele mobów
-- ---------------------------------------------------------------------------
local function eyes(z, y, colorEye, colorPupil, spread)
  spread = spread or 2
  return {
    B(-spread - 1, y, z - 0.1, -spread + 1, y + 1, z, colorEye),
    B(spread - 1, y, z - 0.1, spread + 1, y + 1, z, colorEye),
    colorPupil and B(-spread, y, z - 0.15, -spread + 1, y + 1, z - 0.05, colorPupil) or nil,
    colorPupil and B(spread - 1, y, z - 0.15, spread, y + 1, z - 0.05, colorPupil) or nil,
  }
end

local function quadruped(spec)
  local parts = {}
  local lw, lh = spec.legW, spec.legH
  local bx, bz = spec.bodyW / 2, spec.bodyL / 2
  local legX = bx - lw / 2 - (spec.legInset or 0)
  local legZ = bz - lw / 2 - (spec.legInsetZ or 1)
  local legColor = spec.legColor or spec.color
  local positions = {
    { -legX, -legZ, 0 }, { legX, -legZ, math.pi }, { -legX, legZ, math.pi }, { legX, legZ, 0 },
  }
  for _, p in ipairs(positions) do
    parts[#parts + 1] = part({ B(p[1] - lw / 2, 0, p[2] - lw / 2, p[1] + lw / 2, lh, p[2] + lw / 2,
      legColor) }, { p[1], lh, p[2] }, "leg", p[3])
  end
  local body = { B(-bx, lh, -bz, bx, lh + spec.bodyH, bz, spec.bodyColor or spec.color) }
  for _, extra in ipairs(spec.bodyExtra or {}) do body[#body + 1] = extra end
  parts[#parts + 1] = part(body, { 0, 0, 0 }, "body")
  local head = spec.head
  parts[#parts + 1] = part(head.boxes, head.pivot, "head")
  return parts
end

local MODELS = {}

local function buildModels()
  local pink, pinkD = { 0.95, 0.65, 0.65 }, { 0.85, 0.5, 0.5 }
  local black, white = { 0.08, 0.08, 0.08 }, { 0.95, 0.95, 0.95 }

  -- świnia
  local pigHead = { B(-4, 8, -14, 4, 16, -6, pink), B(-2, 9, -15, 2, 12, -14, pinkD) }
  for _, e in ipairs(eyes(-14, 13, white, black, 2.5)) do pigHead[#pigHead + 1] = e end
  MODELS.pig = quadruped { color = pink, legW = 4, legH = 6, bodyW = 10, bodyH = 8, bodyL = 16,
    head = { boxes = pigHead, pivot = { 0, 12, -6 } } }

  -- krowa
  local brown = { 0.35, 0.24, 0.17 }
  local cowHead = { B(-4, 12, -15, 4, 20, -9, brown), B(-3, 12, -16, 3, 15, -15, { 0.75, 0.65, 0.6 }),
    B(-5, 19, -12, -4, 21, -11, white), B(4, 19, -12, 5, 21, -11, white) }
  for _, e in ipairs(eyes(-15, 17, white, black, 2.5)) do cowHead[#cowHead + 1] = e end
  MODELS.cow = quadruped { color = brown, legW = 4, legH = 10, bodyW = 12, bodyH = 10, bodyL = 18,
    bodyExtra = { B(-6.1, 13, -4, 6.1, 18, 3, white), B(-4, 19.9, 2, 3, 20.1, 7, white) },
    head = { boxes = cowHead, pivot = { 0, 16, -9 } } }

  -- owca (kolor wełny ustawiany przy rysowaniu przez osobną część)
  local face = { 0.75, 0.7, 0.65 }
  local sheepHead = { B(-3, 11, -14, 3, 18, -7, face), B(-4, 15, -11, 4, 19, -7, white) }
  for _, e in ipairs(eyes(-14, 15, white, black, 1.5)) do sheepHead[#sheepHead + 1] = e end
  MODELS.sheep = quadruped { color = face, legW = 4, legH = 8, bodyW = 8, bodyH = 8, bodyL = 14,
    bodyColor = { 0.85, 0.75, 0.72 },
    head = { boxes = sheepHead, pivot = { 0, 14, -7 } } }
  MODELS.sheepWool = meshFromBoxes({ B(-5, 7, -8, 5, 18, 8, white) })

  -- kurczak
  local yellow, red = { 0.95, 0.75, 0.2 }, { 0.85, 0.1, 0.1 }
  local chHead = { B(-2, 9, -6, 2, 15, -3, white), B(-2, 11, -8, 2, 13, -6, yellow),
    B(-1, 9, -7, 1, 11, -6, red) }
  for _, e in ipairs(eyes(-6, 13, black, nil, 1.5)) do chHead[#chHead + 1] = e end
  MODELS.chicken = {
    part({ B(-1.5, 0, -0.5, -0.5, 5, 0.5, yellow) }, { -1, 5, 0 }, "leg", 0),
    part({ B(0.5, 0, -0.5, 1.5, 5, 0.5, yellow) }, { 1, 5, 0 }, "leg", math.pi),
    part({ B(-3, 5, -4, 3, 11, 4, white), B(-4, 6, -3, -3, 10, 3, white), B(3, 6, -3, 4, 10, 3, white) },
      { 0, 0, 0 }, "body"),
    part(chHead, { 0, 10, -3 }, "head"),
  }

  -- wilk
  local gray = { 0.75, 0.73, 0.7 }
  local wolfHead = { B(-3, 9, -10, 3, 15, -5, gray), B(-1.5, 9, -13, 1.5, 12, -10, { 0.65, 0.63, 0.6 }),
    B(-3, 15, -7, -1, 17, -6, gray), B(1, 15, -7, 3, 17, -6, gray) }
  for _, e in ipairs(eyes(-10, 12, black, nil, 1.5)) do wolfHead[#wolfHead + 1] = e end
  MODELS.wolf = quadruped { color = gray, legW = 2, legH = 8, bodyW = 6, bodyH = 6, bodyL = 12,
    bodyExtra = { B(-1, 11, 6, 1, 13, 11, gray) },
    head = { boxes = wolfHead, pivot = { 0, 12, -5 } } }
  MODELS.wolfCollar = meshFromBoxes({ B(-3.2, 9.5, -6, 3.2, 10.5, -5, red) })

  -- postacie dwunożne
  local function biped(spec)
    local parts = {}
    local lw = spec.limb or 4
    local lh = spec.legH or 12
    local bh = spec.bodyH or 12
    parts[#parts + 1] = part({ B(-lw, 0, -lw / 2, 0, lh, lw / 2, spec.legs) }, { -lw / 2, lh, 0 }, "leg", 0)
    parts[#parts + 1] = part({ B(0, 0, -lw / 2, lw, lh, lw / 2, spec.legs) }, { lw / 2, lh, 0 }, "leg", math.pi)
    parts[#parts + 1] = part({ B(-4, lh, -2, 4, lh + bh, 2, spec.body) }, { 0, 0, 0 }, "body")
    local top = lh + bh
    parts[#parts + 1] = part({ B(-4 - lw, top - (spec.armH or 12), -lw / 2, -4, top, lw / 2, spec.arms) },
      { -4 - lw / 2, top - 2, 0 }, spec.armAnim or "arm", math.pi)
    parts[#parts + 1] = part({ B(4, top - (spec.armH or 12), -lw / 2, 4 + lw, top, lw / 2, spec.arms) },
      { 4 + lw / 2, top - 2, 0 }, spec.armAnim or "arm", 0)
    local head = { B(-4, top, -4, 4, top + 8, 4, spec.head) }
    for _, e in ipairs(spec.face or {}) do head[#head + 1] = e end
    parts[#parts + 1] = part(head, { 0, top, 0 }, "head")
    return parts
  end

  local zskin = { 0.33, 0.55, 0.3 }
  MODELS.zombie = biped { legs = { 0.2, 0.22, 0.5 }, body = { 0.1, 0.6, 0.62 }, arms = zskin,
    head = zskin, armAnim = "zombieArm",
    face = { B(-3, 27, -4.1, -1, 28, -4, black), B(1, 27, -4.1, 3, 28, -4, black),
      B(-2, 25, -4.1, 2, 26, -4, { 0.2, 0.35, 0.18 }) } }
  local bone = { 0.8, 0.8, 0.78 }
  MODELS.skeleton = biped { legs = bone, body = { 0.6, 0.6, 0.58 }, arms = bone, head = bone,
    limb = 2, armAnim = "skeletonArm",
    face = { B(-3, 27, -4.1, -1, 29, -4, black), B(1, 27, -4.1, 3, 29, -4, black),
      B(-2, 25, -4.1, 2, 26, -4, { 0.3, 0.3, 0.3 }) } }
  local ender = { 0.06, 0.05, 0.08 }
  local purple = { 0.85, 0.4, 1.0 }
  MODELS.enderman = biped { legs = ender, body = ender, arms = ender, head = ender, limb = 2,
    legH = 30, bodyH = 12, armH = 30,
    face = { B(-3.5, 45, -4.1, -1, 46, -4, purple), B(1, 45, -4.1, 3.5, 46, -4, purple) } }

  -- zombie pigman: różowa skóra, poszarpane ubranie
  local pskin = { 0.92, 0.6, 0.6 }
  MODELS.pigman = biped { legs = { 0.55, 0.45, 0.3 }, body = { 0.6, 0.5, 0.35 }, arms = pskin,
    head = pskin, armAnim = "zombieArm",
    face = { B(-3, 27, -4.1, -1, 28, -4, black), B(1, 27, -4.1, 3, 28, -4, black),
      B(-2, 24.5, -4.3, 2, 26.5, -4, { 0.85, 0.5, 0.5 }), B(-4, 28, -4.05, 4, 32, -4, { 0.5, 0.75, 0.45 }) } }

  -- ghast: wielki biały sześcian z mackami
  local gw = { 0.94, 0.94, 0.94 }
  local ghastBody = { B(-32, 16, -32, 32, 80, 32, gw),
    B(-20, 48, -32.2, -8, 56, -32, black), B(8, 48, -32.2, 20, 56, -32, black),
    B(-8, 28, -32.2, 8, 34, -32, { 0.5, 0.5, 0.5 }) }
  local tentacles = {}
  for i = 0, 2 do
    for j = 0, 2 do
      local tx, tz = -20 + i * 20, -20 + j * 20
      tentacles[#tentacles + 1] = B(tx - 2, -16 + (i + j) % 3 * 4, tz - 2, tx + 2, 16, tz + 2, gw)
    end
  end
  MODELS.ghast = { part(ghastBody, { 0, 0, 0 }, "body"), part(tentacles, { 0, 16, 0 }, "tentacles") }

  -- gracz (widok z trzeciej osoby)
  local skin = { 0.85, 0.62, 0.48 }
  MODELS.player = biped { legs = { 0.25, 0.2, 0.6 }, body = { 0.0, 0.65, 0.65 }, arms = skin,
    head = skin,
    face = { B(-4, 30, -4.1, 4, 32, -4, { 0.3, 0.2, 0.1 }), B(-4, 32, -4, 4, 32.2, 4, { 0.3, 0.2, 0.1 }),
      B(-3, 27, -4.1, -1, 28, -4, white), B(1, 27, -4.1, 3, 28, -4, white),
      B(-2, 27, -4.15, -1, 28, -4.05, { 0.3, 0.2, 0.6 }), B(1, 27, -4.15, 2, 28, -4.05, { 0.3, 0.2, 0.6 }) } }

  -- creeper
  local cg, cgd = { 0.35, 0.72, 0.3 }, { 0.25, 0.55, 0.22 }
  local creeperHead = { B(-4, 18, -4, 4, 26, 4, cg),
    B(-3, 22, -4.1, -1, 24, -4, black), B(1, 22, -4.1, 3, 24, -4, black),
    B(-1, 19, -4.1, 1, 22, -4, black), B(-2, 18.5, -4.1, -1, 21, -4, black),
    B(1, 18.5, -4.1, 2, 21, -4, black) }
  MODELS.creeper = {
    part({ B(-4, 0, -6, 0, 6, -2, cgd) }, { -2, 6, -4 }, "leg", 0),
    part({ B(0, 0, -6, 4, 6, -2, cgd) }, { 2, 6, -4 }, "leg", math.pi),
    part({ B(-4, 0, 2, 0, 6, 6, cgd) }, { -2, 6, 4 }, "leg", math.pi),
    part({ B(0, 0, 2, 4, 6, 6, cgd) }, { 2, 6, 4 }, "leg", 0),
    part({ B(-4, 6, -2, 4, 18, 2, cg) }, { 0, 0, 0 }, "body"),
    part(creeperHead, { 0, 18, 0 }, "head"),
  }

  -- pająk
  local sp, spd = { 0.2, 0.17, 0.15 }, { 0.13, 0.11, 0.1 }
  local red2 = { 0.9, 0.1, 0.1 }
  local spParts = {
    part({ B(-5, 5, 3, 5, 13, 15, sp) }, { 0, 0, 0 }, "body"),
    part({ B(-3, 6, -3, 3, 12, 3, spd) }, { 0, 0, 0 }, "body"),
    part({ B(-4, 5, -11, 4, 13, -3, sp), B(-3, 10, -11.1, -1, 11, -11, red2),
      B(1, 10, -11.1, 3, 11, -11, red2), B(-2, 8, -11.1, -1, 9, -11, red2),
      B(1, 8, -11.1, 2, 9, -11, red2) }, { 0, 9, -3 }, "head"),
  }
  for i = 0, 3 do
    local z = -1.5 + i * 1
    spParts[#spParts + 1] = part({ B(-17, 8, z - 1, -2, 10, z + 1, spd) }, { -2, 9, z }, "spiderLeftLeg", i)
    spParts[#spParts + 1] = part({ B(2, 8, z - 1, 17, 10, z + 1, spd) }, { 2, 9, z }, "spiderRightLeg", i)
  end
  MODELS.spider = spParts

  -- ramka zaznaczenia bloku (12 cienkich krawędzi)
  local t = 0.4
  local edges = {}
  local k = { 0.05, 0.05, 0.05 }
  local function E(x0, y0, z0, x1, y1, z1) edges[#edges + 1] = B(x0, y0, z0, x1, y1, z1, k) end
  for _, y in ipairs({ 0, 16 }) do
    for _, z in ipairs({ 0, 16 }) do E(-t / 2, y - t / 2, z - t / 2, 16 + t / 2, y + t / 2, z + t / 2) end
    for _, x in ipairs({ 0, 16 }) do E(x - t / 2, y - t / 2, -t / 2, x + t / 2, y + t / 2, 16 + t / 2) end
  end
  for _, x in ipairs({ 0, 16 }) do
    for _, z in ipairs({ 0, 16 }) do E(x - t / 2, -t / 2, z - t / 2, x + t / 2, 16 + t / 2, z + t / 2) end
  end
  M.outline = meshFromBoxes(edges)

  -- wagonik i łódka
  local iron, ironD = { 0.6, 0.6, 0.62 }, { 0.3, 0.3, 0.32 }
  M.minecart = meshFromBoxes({
    B(-8, 1, -10, 8, 3, 10, ironD), B(-8, 3, -10, -6, 10, 10, iron), B(6, 3, -10, 8, 10, 10, iron),
    B(-6, 3, -10, 6, 10, -8, iron), B(-6, 3, 8, 6, 10, 10, iron),
    B(-7, 0, -7, -5, 2, -5, black), B(5, 0, -7, 7, 2, -5, black),
    B(-7, 0, 5, -5, 2, 7, black), B(5, 0, 5, 7, 2, 7, black),
  })
  local wood, woodD = { 0.62, 0.47, 0.28 }, { 0.45, 0.33, 0.18 }
  M.boat = meshFromBoxes({
    B(-12, 0, -8, 12, 2, 8, woodD), B(-12, 2, -8, 12, 7, -6, wood), B(-12, 2, 6, 12, 7, 8, wood),
    B(-12, 2, -6, -10, 7, 6, wood), B(10, 2, -6, 12, 7, 6, wood),
  })

  -- strzała
  M.arrow = meshFromBoxes({ B(-0.5, -0.5, -7, 0.5, 0.5, 7, { 0.5, 0.35, 0.2 }),
    B(-1, -1, -8, 1, 1, -6, { 0.6, 0.6, 0.6 }), B(-0.2, -1.5, 5, 0.2, 1.5, 8, white) })
  -- kulka XP
  M.xp = meshFromBoxes({ B(-2, -2, -2, 2, 2, 2, { 0.6, 1.0, 0.2 }) })
  -- śnieżka/jajko/perła
  M.ball = meshFromBoxes({ B(-1.5, -1.5, -1.5, 1.5, 1.5, 1.5, white) })
  -- ręka gracza
  M.arm = meshFromBoxes({ B(-2, -12, -2, 2, 0, 2, { 0.9, 0.7, 0.55 }) })
end

-- Sześcian bloku z teksturami (przedmioty na ziemi, spadający piasek, TNT, ręka)
local blockMeshes = {}
function M.blockMesh(id, meta)
  local k = id * 256 + (meta or 0)
  if blockMeshes[k] then return blockMeshes[k] end
  local def = blocks.defs[id]
  if not def then return nil end
  local t = {}
  for f = 1, 6 do t[f] = blocks.faceTile(def, f, meta or 0) end
  local x0, y0, z0, x1, y1, z1 = 0, 0, 0, 1, 1, 1
  if def.shape == "box" and def.name ~= "torch" then x0, y0, z0, x1, y1, z1 = blocks.bounds(def, meta or 0) end
  local m = meshFromBoxes({ B(x0 * 16 - 8, y0 * 16 - 8, z0 * 16 - 8, x1 * 16 - 8, y1 * 16 - 8,
    z1 * 16 - 8, { 1, 1, 1 }, { tiles = t }) })
  blockMeshes[k] = m
  return m
end

-- Płaski sprite przedmiotu (kwadrat z ikoną, widoczny z obu stron)
local spriteMeshes = {}
function M.spriteMesh(id, damage)
  local d = items.get(id)
  local k = id * 65536 + ((d and d.maxDamage) and 0 or (damage or 0))
  if spriteMeshes[k] then return spriteMeshes[k] end
  local img = icons.itemImage(id, damage)
  if not img then return nil end
  local s = 0.5
  local v = {
    { -s, -s, 0, 0, 1, 1, 1, 1, 1 }, { s, -s, 0, 1, 1, 1, 1, 1, 1 }, { s, s, 0, 1, 0, 1, 1, 1, 1 },
    { -s, -s, 0, 0, 1, 1, 1, 1, 1 }, { s, s, 0, 1, 0, 1, 1, 1, 1 }, { -s, s, 0, 0, 0, 1, 1, 1, 1 },
    { s, -s, 0, 1, 1, 0.8, 0.8, 0.8, 1 }, { -s, -s, 0, 0, 1, 0.8, 0.8, 0.8, 1 },
    { -s, s, 0, 0, 0, 0.8, 0.8, 0.8, 1 }, { s, -s, 0, 1, 1, 0.8, 0.8, 0.8, 1 },
    { -s, s, 0, 0, 0, 0.8, 0.8, 0.8, 1 }, { s, s, 0, 1, 0, 0.8, 0.8, 0.8, 1 },
  }
  local m = love.graphics.newMesh(FORMAT, v, "triangles", "static")
  m:setTexture(img)
  spriteMeshes[k] = m
  return m
end

-- Czy przedmiot rysować jako sześcian (bloki pełne)
function M.isCubeItem(id)
  if id >= 256 then return false end
  local d = blocks.defs[id]
  return d and (d.shape == "cube" or (d.shape == "box" and d.name ~= "torch" and d.name ~= "door"
    and d.name ~= "ladder"))
end

function M.load()
  local u0, v0, size = tiles.uv(tiles.get("white"))
  whiteU, whiteV = u0 + size / 2, v0 + size / 2
  buildModels()
end

-- ---------------------------------------------------------------------------
-- Rysowanie
-- ---------------------------------------------------------------------------
local base, tmp, tmp2, tmp3, model = mat4.new(), mat4.new(), mat4.new(), mat4.new(), mat4.new()

local function drawMesh(mesh, m)
  shader.entity:send("u_model", "row", m)
  love.graphics.draw(mesh)
end
M.drawMesh = drawMesh

-- Macierz bazowa: pozycja, obrót wokół Y, skala
function M.baseMatrix(out, x, y, z, yaw, scale, rollZ)
  mat4.translation(out, x, y, z)
  mat4.rotationY(tmp, yaw)
  mat4.multiply(out, out, tmp)
  if rollZ and rollZ ~= 0 then
    mat4.rotationZ(tmp, rollZ)
    mat4.multiply(out, out, tmp)
  end
  if scale and scale ~= 1 then
    mat4.scale(tmp, scale, scale, scale)
    mat4.multiply(out, out, tmp)
  end
  return out
end

local function partAngle(p, e, t)
  local swing = math.cos((e.limb or 0) * 0.6662 + p.phase) * 1.2 * (e.limbSpeed or 0)
  if p.anim == "leg" then return swing, 0 end
  if p.anim == "arm" then return swing * 0.8, 0 end
  if p.anim == "zombieArm" then
    return -math.pi / 2 + math.sin(t * 2 + p.phase) * 0.05 + swing * 0.1 - (e.swing or 0) * 0.08, 0
  end
  if p.anim == "skeletonArm" then return -math.pi / 2 * (e.target and 1 or 0) + swing * 0.5, 0 end
  if p.anim == "head" then return (e.headPitch or 0), 0 end
  if p.anim == "tentacles" then return math.sin(t * 2 + (e.id or 0)) * 0.1, 0 end
  if p.anim == "spiderLeftLeg" or p.anim == "spiderRightLeg" then
    local side = p.anim == "spiderLeftLeg" and 1 or -1
    local spread = (p.phase - 1.5) * 0.35
    local walk = math.sin((e.limb or 0) * 0.6662 * 2 + p.phase * 1.6) * 0.4 * (e.limbSpeed or 0)
    return 0, spread * side + walk * side, side * 0.6
  end
  return 0, 0
end

-- Rysuje moba
function M.drawMob(e, alpha, light, time)
  local model_ = MODELS[e.kind]
  if not model_ then return end
  local x = e.prevX + (e.x - e.prevX) * alpha
  local y = e.prevY + (e.y - e.prevY) * alpha
  local z = e.prevZ + (e.z - e.prevZ) * alpha
  local yaw = e.prevYaw + (((e.yaw - e.prevYaw + math.pi) % (2 * math.pi)) - math.pi) * alpha
  local scale = (e.growth and e.growth < 0) and 0.5 or 1
  local roll = 0
  if e.deathTime and e.deathTime > 0 then
    roll = math.min(1, (e.deathTime + alpha) / 20) * math.pi / 2
  end
  if e.kind == "creeper" and e.fuse and e.fuse > 0 then
    scale = scale * (1 + (e.fuse / 30) * 0.15)
  end
  M.baseMatrix(base, x, y, z, yaw, scale, roll)
  local s = shader.entity
  s:send("u_light", light)
  local tint = { 0, 0, 0, 0 }
  if (e.hurtTime and e.hurtTime > 0) or (e.deathTime and e.deathTime > 0) then
    tint = { 1, 0, 0, 0.45 }
  elseif e.kind == "creeper" and e.fuse and e.fuse > 0 and math.floor(e.fuse / 4) % 2 == 0 then
    tint = { 1, 1, 1, 0.5 }
  end
  s:send("u_tint", tint)
  for _, p in ipairs(model_) do
    local ax, ay, az = partAngle(p, e, time)
    local pv = p.pivot
    mat4.translation(tmp, pv[1] * P, pv[2] * P, pv[3] * P)
    mat4.multiply(model, base, tmp)
    if ay and ay ~= 0 then mat4.rotationY(tmp2, ay); mat4.multiply(model, model, tmp2) end
    if az and az ~= 0 then mat4.rotationZ(tmp2, az); mat4.multiply(model, model, tmp2) end
    if ax ~= 0 then mat4.rotationX(tmp2, ax); mat4.multiply(model, model, tmp2) end
    mat4.translation(tmp3, -pv[1] * P, -pv[2] * P, -pv[3] * P)
    mat4.multiply(model, model, tmp3)
    drawMesh(p.mesh, model)
  end
  -- wełna owcy w kolorze
  if e.kind == "sheep" and not e.sheared then
    local WOOL = { [0] = { 1, 1, 1 }, [1] = { 0.75, 0.2, 0.2 }, [2] = { 0.9, 0.8, 0.2 },
      [3] = { 0.3, 0.5, 0.15 }, [4] = { 0.2, 0.25, 0.65 }, [5] = { 0.15, 0.15, 0.15 } }
    local c = WOOL[e.color or 0] or WOOL[0]
    love.graphics.setColor(c[1], c[2], c[3], 1)
    drawMesh(MODELS.sheepWool, base)
    love.graphics.setColor(1, 1, 1, 1)
  end
  if e.kind == "wolf" and e.tamed then
    -- obroża na głowie
    local head = model_[#model_]
    local pv = head.pivot
    mat4.translation(tmp, 0, 0, 0)
    mat4.multiply(model, base, tmp)
    drawMesh(MODELS.wolfCollar, model)
    local _ = pv
  end
  s:send("u_tint", { 0, 0, 0, 0 })
end

-- Przedmiot leżący na ziemi (obracający się i podskakujący)
function M.drawItem(e, alpha, light, time, camYaw)
  local x = e.prevX + (e.x - e.prevX) * alpha
  local y = e.prevY + (e.y - e.prevY) * alpha
  local z = e.prevZ + (e.z - e.prevZ) * alpha
  local st = e.stack
  local bob = math.sin((e.age + alpha) / 10 + (e.spin or 0)) * 0.1 + 0.1
  shader.entity:send("u_light", light)
  local count = st.count > 16 and 3 or (st.count > 1 and 2 or 1)
  for i = 1, count do
    local ox = (i - 1) * 0.06
    if M.isCubeItem(st.id) then
      local mesh = M.blockMesh(st.id, (blocks.defs[st.id] and blocks.defs[st.id].metaMask or 0) > 0
        and st.damage or 0)
      M.baseMatrix(base, x + ox, y + bob + 0.15 + ox, z, (e.age + alpha) / 20 + (e.spin or 0), 0.25)
      drawMesh(mesh, base)
    else
      local mesh = M.spriteMesh(st.id, st.damage)
      if mesh then
        M.baseMatrix(base, x + ox, y + bob + 0.2, z + ox * 0.5, camYaw, 0.45)
        drawMesh(mesh, base)
      end
    end
  end
end

function M.drawOutline(x0, y0, z0, x1, y1, z1)
  mat4.translation(base, x0, y0, z0)
  mat4.scale(tmp, x1 - x0, y1 - y0, z1 - z0)
  mat4.multiply(base, base, tmp)
  shader.entity:send("u_light", 1)
  drawMesh(M.outline, base)
end

M.MODELS = MODELS
M.tmp = { base = base, tmp = tmp, model = model }
return M
