-- render/texturegen.lua
-- Proceduralne tekstury bloków 16x16 (bez żadnych plików PNG).
-- Czysta logika: zwraca tablicę pikseli {r, g, b, a} (0..255), więc moduł
-- da się testować bez LÖVE. Pakowaniem do atlasu zajmuje się render/atlas.lua.
-- Chcesz własne tekstury? Podmień funkcję dla danej nazwy albo wczytaj PNG.

local Rng = require("core.rng")

local M = {}
local N = 16

local function clamp(v)
  if v < 0 then return 0 end
  if v > 255 then return 255 end
  return math.floor(v + 0.5)
end

-- Nowy kafelek wypełniony kolorem
local function new(r, g, b, a)
  local t = {}
  for i = 0, N * N - 1 do
    t[i] = { r or 0, g or 0, b or 0, a or 255 }
  end
  return t
end

local function get(t, x, y) return t[x + y * N] end
local function set(t, x, y, r, g, b, a)
  if x < 0 or y < 0 or x >= N or y >= N then return end
  local p = t[x + y * N]
  p[1], p[2], p[3], p[4] = clamp(r), clamp(g), clamp(b), clamp(a or 255)
end

local function copy(src)
  local t = {}
  for i = 0, N * N - 1 do
    local p = src[i]
    t[i] = { p[1], p[2], p[3], p[4] }
  end
  return t
end

-- Kolor bazowy z losową jasnością każdego piksela
local function noisy(rng, r, g, b, var, a)
  local t = new(r, g, b, a)
  for i = 0, N * N - 1 do
    local d = (rng:next() * 2 - 1) * var
    local p = t[i]
    p[1], p[2], p[3] = clamp(r + d), clamp(g + d), clamp(b + d)
  end
  return t
end

-- Przyciemnia/rozjaśnia piksel
local function shade(t, x, y, k)
  local p = get(t, x, y)
  if not p then return end
  p[1], p[2], p[3] = clamp(p[1] * k), clamp(p[2] * k), clamp(p[3] * k)
end

-- Skupiska kolorowych pikseli (rudy)
local function ore(rng, base, r, g, b, clusters)
  local t = copy(base)
  for _ = 1, clusters do
    local cx, cy = rng:int(2, 13), rng:int(2, 13)
    for _ = 1, rng:int(3, 6) do
      local x, y = cx + rng:int(-1, 1), cy + rng:int(-1, 1)
      local k = 0.8 + rng:next() * 0.4
      set(t, x, y, r * k, g * k, b * k)
    end
  end
  return t
end

-- Obramowanie (bloki metalu, skrzynie)
local function border(t, k)
  for i = 0, N - 1 do
    shade(t, i, 0, k); shade(t, i, N - 1, k)
    shade(t, 0, i, k); shade(t, N - 1, i, k)
  end
end

-- Komórki Woronoja (bruk, żwir)
local function cells(rng, count, palette, edge)
  local cs = {}
  for i = 1, count do
    cs[i] = { rng:next() * N, rng:next() * N, palette[rng:int(1, #palette)] }
  end
  local t = new()
  for y = 0, N - 1 do
    for x = 0, N - 1 do
      local best, second, bc = 1e9, 1e9, nil
      for i = 1, count do
        local c = cs[i]
        -- odległość z zawijaniem (tekstura bez szwów)
        local dx = math.abs(x + 0.5 - c[1]); if dx > N / 2 then dx = N - dx end
        local dy = math.abs(y + 0.5 - c[2]); if dy > N / 2 then dy = N - dy end
        local d = dx * dx + dy * dy
        if d < best then second = best; best = d; bc = c[3]
        elseif d < second then second = d end
      end
      local k = 0.9 + rng:next() * 0.2
      if edge and math.sqrt(second) - math.sqrt(best) < 0.9 then k = k * edge end
      set(t, x, y, bc[1] * k, bc[2] * k, bc[3] * k)
    end
  end
  return t
end

-- Rysowanie z "pixel artu": wiersze tekstu + paleta znak -> kolor
local function art(rows, palette, base)
  local t = base and copy(base) or new(0, 0, 0, 0)
  for y = 1, #rows do
    local row = rows[y]
    for x = 1, #row do
      local ch = row:sub(x, x)
      local c = palette[ch]
      if c then set(t, x - 1, y - 1, c[1], c[2], c[3], c[4] or 255) end
    end
  end
  return t
end
M.art = art

-- ---------------------------------------------------------------------------
-- Generatory poszczególnych tekstur
-- ---------------------------------------------------------------------------
local G = {}

local function stone(rng)
  local t = noisy(rng, 125, 125, 125, 14)
  for _ = 1, 10 do
    local x, y = rng:int(0, 15), rng:int(0, 15)
    shade(t, x, y, 0.8); shade(t, x + 1, y, 0.85)
  end
  return t
end
G.stone = stone

local function dirt(rng)
  local t = noisy(rng, 134, 96, 67, 12)
  for _ = 1, 14 do shade(t, rng:int(0, 15), rng:int(0, 15), 0.75) end
  for _ = 1, 6 do shade(t, rng:int(0, 15), rng:int(0, 15), 1.2) end
  return t
end
G.dirt = dirt

local function grassTop(rng)
  local t = new()
  for y = 0, N - 1 do
    for x = 0, N - 1 do
      local k = 0.82 + rng:next() * 0.3
      set(t, x, y, 92 * k, 156 * k, 52 * k)
    end
  end
  return t
end
G.grass_top = grassTop

local function grassSideWith(rng, r, g, b, depth)
  local t = dirt(rng)
  for x = 0, N - 1 do
    local h = depth + rng:int(0, 2)
    for y = 0, h - 1 do
      local k = 0.82 + rng:next() * 0.3
      set(t, x, y, r * k, g * k, b * k)
    end
  end
  return t
end
G.grass_side = function(rng) return grassSideWith(rng, 92, 156, 52, 3) end
G.grass_side_snow = function(rng) return grassSideWith(rng, 240, 245, 250, 3) end

G.cobblestone = function(rng)
  return cells(rng, 11, { { 130, 130, 130 }, { 110, 110, 110 }, { 150, 150, 150 },
    { 95, 95, 95 } }, 0.55)
end

G.mossy_cobblestone = function(rng)
  local t = G.cobblestone(rng)
  for _ = 1, 40 do
    local x, y = rng:int(0, 15), rng:int(0, 15)
    set(t, x, y, 70 + rng:int(0, 20), 110 + rng:int(0, 30), 50)
  end
  return t
end

local function planks(rng, r, g, b)
  local t = new()
  for y = 0, N - 1 do
    local board = math.floor(y / 4)
    local seam = rng:int(0, 15)
    for x = 0, N - 1 do
      local k = 0.88 + rng:next() * 0.18
      if (x + board * 5) % 16 == 0 then k = k * 0.95 end
      set(t, x, y, r * k, g * k, b * k)
    end
    if y % 4 == 3 then
      for x = 0, N - 1 do shade(t, x, y, 0.68) end
    end
    if y % 4 == 1 then shade(t, (seam + board * 7) % 16, y, 0.7) end
  end
  return t
end
G.planks = function(rng) return planks(rng, 162, 130, 78) end
G.planks_dark = function(rng) return planks(rng, 104, 78, 47) end

local function bark(rng, r, g, b, stripes)
  local t = new()
  for x = 0, N - 1 do
    local kx = 0.85 + rng:next() * 0.2
    for y = 0, N - 1 do
      local k = kx * (0.9 + rng:next() * 0.15)
      if stripes and rng:next() < 0.1 then k = k * 0.5 end
      set(t, x, y, r * k, g * k, b * k)
    end
  end
  return t
end
G.log_side = function(rng) return bark(rng, 102, 81, 50) end
G.log_pine_side = function(rng) return bark(rng, 60, 42, 25) end
G.log_birch_side = function(rng)
  local t = new()
  for y = 0, N - 1 do
    for x = 0, N - 1 do
      local k = 0.92 + rng:next() * 0.1
      set(t, x, y, 215 * k, 215 * k, 205 * k)
    end
  end
  for _ = 1, 9 do
    local x, y = rng:int(0, 13), rng:int(0, 15)
    for i = 0, rng:int(1, 3) do set(t, x + i, y, 40, 40, 35) end
  end
  return t
end

G.log_top = function(rng)
  local t = new()
  for y = 0, N - 1 do
    for x = 0, N - 1 do
      local d = math.sqrt((x - 7.5) ^ 2 + (y - 7.5) ^ 2)
      local ring = math.floor(d) % 2 == 0 and 1 or 0.88
      local k = ring * (0.92 + rng:next() * 0.1)
      if d > 6.8 then
        set(t, x, y, 102 * k, 81 * k, 50 * k)
      else
        set(t, x, y, 176 * k, 144 * k, 90 * k)
      end
    end
  end
  return t
end

local function leaves(rng, r, g, b)
  local t = new(0, 0, 0, 0)
  for y = 0, N - 1 do
    for x = 0, N - 1 do
      if rng:next() > 0.22 then
        local k = 0.7 + rng:next() * 0.45
        set(t, x, y, r * k, g * k, b * k)
      end
    end
  end
  return t
end
G.leaves = function(rng) return leaves(rng, 58, 128, 36) end
G.leaves_pine = function(rng) return leaves(rng, 48, 96, 60) end
G.leaves_birch = function(rng) return leaves(rng, 96, 150, 64) end

G.sand = function(rng) return noisy(rng, 219, 207, 160, 10) end
G.gravel = function(rng)
  return cells(rng, 18, { { 140, 132, 128 }, { 110, 100, 98 }, { 165, 158, 150 },
    { 90, 86, 84 } }, 0.8)
end
G.clay = function(rng) return noisy(rng, 160, 166, 179, 8) end
G.snow = function(rng) return noisy(rng, 242, 248, 252, 5) end
G.ice = function(rng) return noisy(rng, 160, 190, 250, 10, 170) end

G.bedrock = function(rng)
  local t = new()
  for i = 0, N * N - 1 do
    local v = rng:next() < 0.5 and 50 + rng:int(0, 30) or 100 + rng:int(0, 50)
    local p = t[i]
    p[1], p[2], p[3] = v, v, v
  end
  return t
end

G.coal_ore = function(rng) return ore(rng, stone(rng), 35, 35, 35, 5) end
G.iron_ore = function(rng) return ore(rng, stone(rng), 216, 175, 147, 5) end
G.gold_ore = function(rng) return ore(rng, stone(rng), 252, 238, 75, 5) end
G.diamond_ore = function(rng) return ore(rng, stone(rng), 93, 236, 245, 4) end
G.redstone_ore = function(rng) return ore(rng, stone(rng), 230, 10, 10, 5) end
G.lapis_ore = function(rng) return ore(rng, stone(rng), 30, 70, 190, 5) end

local function metalBlock(rng, r, g, b)
  local t = noisy(rng, r, g, b, 6)
  border(t, 0.75)
  for i = 1, N - 2 do shade(t, i, 1, 1.15); shade(t, 1, i, 1.15) end
  return t
end
G.iron_block = function(rng) return metalBlock(rng, 220, 220, 220) end
G.gold_block = function(rng) return metalBlock(rng, 250, 215, 60) end
G.diamond_block = function(rng) return metalBlock(rng, 100, 225, 220) end
G.lapis_block = function(rng) return metalBlock(rng, 35, 70, 170) end

G.water = function(rng)
  local t = new()
  for y = 0, N - 1 do
    for x = 0, N - 1 do
      local k = 0.85 + 0.15 * math.sin((x + y * 0.5) * 0.8) + rng:next() * 0.08
      set(t, x, y, 45 * k, 80 * k, 230 * k, 175)
    end
  end
  return t
end

G.lava = function(rng)
  local t = new()
  for y = 0, N - 1 do
    for x = 0, N - 1 do
      local v = math.sin(x * 0.9 + rng:next()) + math.cos(y * 0.7 + rng:next())
      if v > 0.6 then
        set(t, x, y, 255, 220, 80)
      elseif v > -0.4 then
        set(t, x, y, 230, 110 + rng:int(0, 30), 20)
      else
        set(t, x, y, 190, 60, 10)
      end
    end
  end
  return t
end

G.glass = function()
  local t = new(0, 0, 0, 0)
  for i = 0, N - 1 do
    set(t, i, 0, 220, 240, 245); set(t, i, N - 1, 200, 225, 235)
    set(t, 0, i, 220, 240, 245); set(t, N - 1, i, 200, 225, 235)
  end
  for i = 0, 3 do set(t, 3 + i, 6 - i, 235, 250, 255) end
  for i = 0, 2 do set(t, 9 + i, 12 - i, 235, 250, 255) end
  return t
end

local function wool(rng, r, g, b)
  local t = noisy(rng, r, g, b, 10)
  for y = 0, N - 1, 2 do
    for x = (y / 2) % 2, N - 1, 3 do shade(t, x, y, 0.9) end
  end
  return t
end
G.wool = function(rng) return wool(rng, 234, 234, 234) end
G.wool_red = function(rng) return wool(rng, 175, 45, 40) end
G.wool_yellow = function(rng) return wool(rng, 220, 200, 50) end
G.wool_green = function(rng) return wool(rng, 60, 110, 30) end
G.wool_blue = function(rng) return wool(rng, 45, 60, 160) end
G.wool_black = function(rng) return wool(rng, 30, 28, 28) end

G.bricks = function(rng)
  local t = new()
  for y = 0, N - 1 do
    for x = 0, N - 1 do
      local row = math.floor(y / 4)
      local off = (row % 2) * 4
      local mortar = (y % 4 == 3) or ((x + off) % 8 == 7)
      if mortar then
        local v = 160 + rng:int(0, 20)
        set(t, x, y, v, v * 0.95, v * 0.9)
      else
        local k = 0.85 + rng:next() * 0.25
        set(t, x, y, 150 * k, 74 * k, 58 * k)
      end
    end
  end
  return t
end

G.stone_bricks = function(rng)
  local t = noisy(rng, 122, 122, 122, 8)
  for y = 0, N - 1 do
    for x = 0, N - 1 do
      local row = math.floor(y / 8)
      local off = (row % 2) * 8
      if y % 8 == 7 or (x + off) % 16 == 15 then shade(t, x, y, 0.6)
      elseif y % 8 == 0 or (x + off) % 16 == 0 then shade(t, x, y, 1.1) end
    end
  end
  return t
end

G.slab_top = function(rng)
  local t = noisy(rng, 168, 168, 168, 6)
  border(t, 0.8)
  return t
end
G.slab_side = function(rng)
  local t = noisy(rng, 160, 160, 160, 6)
  for x = 0, N - 1 do shade(t, x, 7, 0.7); shade(t, x, 15, 0.7); shade(t, x, 8, 1.1) end
  return t
end

G.sandstone_side = function(rng)
  local t = noisy(rng, 216, 203, 155, 6)
  for x = 0, N - 1 do
    shade(t, x, 3, 0.9); shade(t, x, 11, 0.92)
    for y = 13, 15 do shade(t, x, y, 0.9) end
  end
  return t
end
G.sandstone_top = function(rng) return noisy(rng, 222, 210, 162, 5) end
G.sandstone_bottom = function(rng)
  local t = noisy(rng, 210, 196, 148, 9)
  for _ = 1, 12 do shade(t, rng:int(0, 15), rng:int(0, 15), 0.85) end
  return t
end

G.obsidian = function(rng)
  local t = noisy(rng, 20, 16, 30, 6)
  for _ = 1, 18 do
    local x, y = rng:int(0, 15), rng:int(0, 15)
    set(t, x, y, 60, 40, 90)
  end
  return t
end

G.tnt_side = function(rng)
  local t = new()
  for y = 0, N - 1 do
    for x = 0, N - 1 do
      local k = 0.9 + rng:next() * 0.15
      if y >= 5 and y <= 10 then
        set(t, x, y, 230 * k, 230 * k, 230 * k)
      else
        set(t, x, y, 200 * k, 40 * k, 30 * k)
      end
    end
    if y < 5 or y > 10 then
      for x = 1, N - 1, 4 do shade(t, x, y, 0.75) end
    end
  end
  local letters = {
    "###.#..#.###",
    ".#..##.#..#.",
    ".#..#.##..#.",
    ".#..#..#..#.",
  }
  for yy, row in ipairs(letters) do
    for xx = 1, #row do
      if row:sub(xx, xx) == "#" then set(t, xx + 1, yy + 5, 30, 30, 30) end
    end
  end
  return t
end
G.tnt_top = function(rng)
  local t = noisy(rng, 200, 50, 40, 10)
  for y = 6, 9 do for x = 6, 9 do set(t, x, y, 90, 90, 90) end end
  set(t, 7, 7, 40, 40, 40); set(t, 8, 8, 40, 40, 40)
  return t
end
G.tnt_bottom = function(rng) return noisy(rng, 190, 45, 35, 10) end

G.bookshelf = function(rng)
  local t = G.planks(rng)
  local colors = { { 140, 30, 30 }, { 40, 70, 140 }, { 50, 110, 40 }, { 150, 120, 40 },
    { 100, 50, 110 } }
  for shelf = 0, 1 do
    local y0 = 1 + shelf * 8
    local x = 1
    while x < 15 do
      local w = rng:int(1, 2)
      local c = colors[rng:int(1, #colors)]
      local h = rng:int(4, 6)
      for xx = x, math.min(14, x + w - 1) do
        for yy = y0 + (6 - h), y0 + 5 do
          local k = 0.85 + rng:next() * 0.2
          set(t, xx, yy, c[1] * k, c[2] * k, c[3] * k)
        end
      end
      x = x + w
    end
  end
  return t
end

G.torch = function()
  local t = new(0, 0, 0, 0)
  for y = 8, 15 do
    set(t, 7, y, 110, 85, 50); set(t, 8, y, 90, 68, 40)
  end
  set(t, 7, 6, 255, 230, 120); set(t, 8, 6, 255, 210, 90)
  set(t, 7, 7, 255, 160, 40); set(t, 8, 7, 250, 130, 30)
  set(t, 7, 5, 255, 250, 200); set(t, 8, 5, 255, 240, 160)
  return t
end

G.fire = function(rng)
  local t = new(0, 0, 0, 0)
  for x = 0, N - 1 do
    local h = rng:int(6, 14)
    for y = N - h, N - 1 do
      local f = (y - (N - h)) / h
      set(t, x, y, 255, 120 + 120 * (1 - f), 30 * (1 - f), 230)
    end
  end
  return t
end

G.spawner = function(rng)
  local t = new(0, 0, 0, 0)
  for i = 0, N - 1 do
    for j = 0, N - 1 do
      if i % 4 == 0 or j % 4 == 0 then
        local v = 40 + rng:int(0, 30)
        set(t, i, j, v, v, v + 10)
      end
    end
  end
  return t
end
G.mob_spawner_cage = G.spawner

local function chestBase(rng)
  local t = planks(rng, 170, 120, 50)
  border(t, 0.55)
  return t
end
G.chest_side = function(rng)
  local t = chestBase(rng)
  for x = 0, N - 1 do shade(t, x, 5, 0.6) end
  return t
end
G.chest_front = function(rng)
  local t = G.chest_side(rng)
  for y = 4, 7 do for x = 7, 8 do set(t, x, y, 190, 190, 190) end end
  set(t, 7, 6, 60, 60, 60)
  return t
end
G.chest_top = function(rng) return chestBase(rng) end

G.crafting_table_top = function(rng)
  local t = planks(rng, 150, 105, 60)
  border(t, 0.6)
  for i = 1, N - 2 do shade(t, i, 5, 0.65); shade(t, i, 10, 0.65)
    shade(t, 5, i, 0.65); shade(t, 10, i, 0.65) end
  return t
end
G.crafting_table_side = function(rng)
  local t = G.planks(rng)
  for x = 0, N - 1 do for y = 0, 2 do set(t, x, y, 110, 75, 45) end end
  -- piła
  for x = 3, 7 do set(t, x, 6, 180, 180, 180) end
  for x = 3, 7, 2 do set(t, x, 7, 180, 180, 180) end
  set(t, 8, 6, 100, 70, 40); set(t, 9, 6, 100, 70, 40)
  return t
end
G.crafting_table_front = function(rng)
  local t = G.crafting_table_side(rng)
  -- młotek
  for y = 5, 12 do set(t, 11, y, 100, 70, 40) end
  for x = 9, 13 do set(t, x, 5, 120, 120, 120); set(t, x, 6, 120, 120, 120) end
  return t
end

local WHEAT_STAGES = {}
for i = 0, 7 do
  G["wheat_" .. i] = function(rng)
    local t = new(0, 0, 0, 0)
    local h = 2 + i * 2
    local ripe = i / 7
    for x = 1, N - 2, 2 do
      local hh = h + rng:int(-1, 0)
      for y = N - hh, N - 1 do
        local r = 50 + ripe * 160
        local g = 140 + ripe * 50
        set(t, x + (y % 3 == 0 and 1 or 0), y, r, g, 30)
      end
      if i == 7 then set(t, x, N - hh, 220, 190, 70) end
    end
    return t
  end
end
M.WHEAT_STAGES = WHEAT_STAGES

local function farmland(rng, wet)
  local k = wet and 0.6 or 1
  local t = noisy(rng, 120 * k, 82 * k, 56 * k, 8)
  for y = 0, N - 1, 4 do
    for x = 0, N - 1 do shade(t, x, y, 0.7) end
  end
  return t
end
G.farmland_dry = function(rng) return farmland(rng, false) end
G.farmland_wet = function(rng) return farmland(rng, true) end

local function furnaceFace(rng, lit)
  local t = stone(rng)
  border(t, 0.7)
  for y = 7, 13 do
    for x = 4, 11 do
      if lit and y >= 10 then
        set(t, x, y, 255, 120 + rng:int(0, 100), 20)
      else
        set(t, x, y, 25, 25, 25)
      end
    end
  end
  for x = 3, 12 do shade(t, x, 6, 0.6) end
  return t
end
G.furnace_front = function(rng) return furnaceFace(rng, false) end
G.furnace_front_lit = function(rng) return furnaceFace(rng, true) end
G.furnace_side = function(rng)
  local t = stone(rng)
  border(t, 0.75)
  return t
end
G.furnace_top = function(rng)
  local t = noisy(rng, 110, 110, 110, 8)
  border(t, 0.7)
  return t
end

local function door(rng, top)
  local t = planks(rng, 150, 110, 60)
  border(t, 0.6)
  for y = 0, N - 1 do shade(t, 7, y, 0.75) end
  if top then
    for y = 3, 9 do for x = 3, 12 do
      if x ~= 7 and x ~= 8 and y ~= 6 then set(t, x, y, 180, 210, 220, 255) end
    end end
  else
    set(t, 12, 5, 60, 60, 60); set(t, 12, 4, 60, 60, 60)
  end
  return t
end
G.door_bottom = function(rng) return door(rng, false) end
G.door_top = function(rng) return door(rng, true) end

G.ladder = function()
  local t = new(0, 0, 0, 0)
  for y = 0, N - 1 do
    set(t, 2, y, 130, 100, 60); set(t, 3, y, 110, 82, 48)
    set(t, 12, y, 130, 100, 60); set(t, 13, y, 110, 82, 48)
  end
  for y = 2, N - 1, 4 do
    for x = 4, 11 do set(t, x, y, 140, 108, 66); set(t, x, y + 1, 105, 78, 45) end
  end
  return t
end

G.cactus_side = function(rng)
  local t = noisy(rng, 20, 120, 30, 10)
  for y = 0, N - 1 do
    shade(t, 0, y, 0.7); shade(t, 15, y, 0.7)
    shade(t, 4, y, 0.8); shade(t, 11, y, 0.8)
  end
  for _ = 1, 8 do set(t, rng:int(1, 14), rng:int(0, 15), 30, 30, 20) end
  return t
end
G.cactus_top = function(rng)
  local t = noisy(rng, 30, 130, 40, 8)
  border(t, 0.7)
  return t
end
G.cactus_bottom = function(rng) return noisy(rng, 160, 190, 110, 8) end

G.sugar_cane = function(rng)
  local t = new(0, 0, 0, 0)
  for _, x in ipairs({ 3, 8, 12 }) do
    for y = 0, N - 1 do
      local k = (y % 5 == 0) and 0.7 or (0.9 + rng:next() * 0.2)
      set(t, x, y, 140 * k, 200 * k, 100 * k)
      set(t, x + 1, y, 110 * k, 170 * k, 80 * k)
    end
  end
  return t
end

local function pumpkinBase(rng)
  local t = noisy(rng, 220, 130, 30, 10)
  for y = 0, N - 1 do
    for _, x in ipairs({ 0, 4, 8, 12 }) do shade(t, x, y, 0.8) end
  end
  return t
end
G.pumpkin_side = pumpkinBase
G.pumpkin_top = function(rng)
  local t = noisy(rng, 210, 125, 30, 10)
  for y = 6, 9 do for x = 7, 8 do set(t, x, y, 100, 80, 30) end end
  return t
end
local FACE_ROWS = {
  "................",
  "................",
  "................",
  "...##......##...",
  "..####....####..",
  "................",
  "................",
  "....#.####.#....",
  "....########....",
  ".....######.....",
}
G.pumpkin_face = function(rng)
  return art(FACE_ROWS, { ["#"] = { 40, 25, 10 } }, pumpkinBase(rng))
end
G.jack_o_lantern_face = function(rng)
  return art(FACE_ROWS, { ["#"] = { 255, 230, 90 } }, pumpkinBase(rng))
end

G.glowstone = function(rng)
  local t = cells(rng, 10, { { 250, 220, 120 }, { 200, 150, 70 }, { 255, 240, 170 },
    { 170, 120, 60 } }, 0.7)
  return t
end

G.melon_side = function(rng)
  local t = noisy(rng, 110, 150, 30, 8)
  for y = 0, N - 1 do
    for x = 0, N - 1, 3 do shade(t, x, y, 0.7) end
  end
  return t
end
G.melon_top = function(rng)
  local t = noisy(rng, 120, 160, 40, 8)
  border(t, 0.75)
  return t
end

local function plant(rows, palette)
  return function() return art(rows, palette) end
end

G.tall_grass = function(rng)
  local t = new(0, 0, 0, 0)
  for x = 1, N - 2 do
    if rng:next() < 0.6 then
      local h = rng:int(5, 13)
      for y = N - h, N - 1 do
        local k = 0.75 + rng:next() * 0.35
        set(t, x, y, 80 * k, 150 * k, 50 * k)
      end
    end
  end
  return t
end

G.dead_bush = plant({
  "................", "................", "....#......#....", ".....#....#.....",
  "..#...#..#...#..", "...#...##...#...", "....#..##..#....", ".....#.##.#.....",
  "......####......", ".......##.......", ".......##.......", ".......##.......",
  ".......##.......", ".......##.......", ".......##.......", ".......##.......",
}, { ["#"] = { 130, 95, 50 } })

local STEM = { 60, 130, 40 }
G.dandelion = plant({
  "................", "................", "................", "................",
  "................", "......yyy.......", ".....yYYYy......", ".....yYYYy......",
  "......yyy.......", ".......g........", ".......g...gg...", "...gg..g..g.....",
  ".....g.g.g......", "......ggg.......", ".......g........", ".......g........",
}, { y = { 240, 220, 30 }, Y = { 255, 245, 90 }, g = STEM })
G.rose = plant({
  "................", "................", "................", "................",
  "......rrr.......", ".....rRRRr......", ".....rRrRr......", ".....rRRRr......",
  "......rrr.......", ".......g........", "...gg..g..gg....", ".....g.g.g......",
  "......ggg.......", ".......g........", ".......g........", ".......g........",
}, { r = { 180, 20, 20 }, R = { 230, 40, 40 }, g = STEM })
G.mushroom_brown = plant({
  "................", "................", "................", "................",
  "................", "................", "................", "................",
  ".....bbbbbb.....", "....bBBBBBBb....", "....bbbbbbbb....", ".......ww.......",
  ".......ww.......", ".......ww.......", ".......ww.......", "................",
}, { b = { 130, 95, 70 }, B = { 160, 120, 90 }, w = { 220, 210, 190 } })
G.mushroom_red = plant({
  "................", "................", "................", "................",
  "................", "................", "................", "......rrrr......",
  ".....rwrrwr.....", "....rrrrrrrr....", "....rrwrrwrr....", ".......ww.......",
  ".......ww.......", ".......ww.......", ".......ww.......", "................",
}, { r = { 200, 30, 30 }, w = { 240, 240, 240 } })
G.sapling = plant({
  "................", "................", "......gg........", ".....gGGg.......",
  "....gGGGGg......", "...gGGgGGGg.....", "....gGGGGg......", "...gGgGGgGg.....",
  "....gGGGGg......", ".....gGGg.......", ".......b........", ".......b........",
  ".......b........", ".......b........", ".......b........", ".......b........",
}, { g = { 40, 100, 30 }, G = { 70, 150, 40 }, b = { 100, 75, 40 } })

G.cobweb = function()
  local t = new(0, 0, 0, 0)
  for i = 0, N - 1 do
    set(t, i, i, 230, 230, 230, 200); set(t, N - 1 - i, i, 230, 230, 230, 200)
    set(t, 7, i, 230, 230, 230, 200); set(t, i, 7, 230, 230, 230, 200)
  end
  for r = 3, 7, 2 do
    for a = 0, 15 do
      local ang = a / 16 * math.pi * 2
      set(t, math.floor(7.5 + math.cos(ang) * r), math.floor(7.5 + math.sin(ang) * r),
        220, 220, 220, 180)
    end
  end
  return t
end

local function bedTop(head)
  return function(rng)
    local t = noisy(rng, 170, 30, 30, 8)
    if head then
      for y = 1, 6 do for x = 2, 13 do set(t, x, y, 235, 235, 235) end end
    end
    border(t, 0.75)
    return t
  end
end
G.bed_top_foot = bedTop(false)
G.bed_top_head = bedTop(true)
local function bedSide(head)
  return function(rng)
    local t = new(0, 0, 0, 0)
    for y = 7, 15 do
      for x = 0, N - 1 do
        if y <= 9 then
          local w = head and x < 6
          if w then set(t, x, y, 230, 230, 230) else set(t, x, y, 170, 30, 30) end
        else
          local k = 0.9 + rng:next() * 0.15
          set(t, x, y, 150 * k, 110 * k, 60 * k)
        end
      end
    end
    return t
  end
end
G.bed_side_foot = bedSide(false)
G.bed_side_head = bedSide(true)
G.bed_end_foot = bedSide(false)
G.bed_end_head = bedSide(true)

G.white = function() return new(255, 255, 255) end

for i = 0, 9 do
  G["cracks_" .. i] = function()
    local rng = Rng.new(777)
    local t = new(0, 0, 0, 0)
    local lines = 2 + i * 2
    for _ = 1, lines do
      local x, y = rng:int(4, 11), rng:int(4, 11)
      local dx, dy = rng:int(-1, 1), rng:int(-1, 1)
      if dx == 0 and dy == 0 then dx = 1 end
      for _ = 1, 3 + i do
        set(t, x, y, 0, 0, 0, 200)
        x, y = x + dx, y + dy
        if rng:next() < 0.4 then dx = rng:int(-1, 1) end
        if rng:next() < 0.4 then dy = rng:int(-1, 1) end
      end
    end
    return t
  end
end

G.netherrack = function(rng) return noisy(rng, 110, 50, 50, 15) end
G.soul_sand = function(rng) return noisy(rng, 85, 64, 50, 12) end
G.nether_portal = function(rng) return noisy(rng, 120, 40, 200, 30, 190) end

-- ---------------------------------------------------------------------------
-- Redstone, tłoki, tory
-- ---------------------------------------------------------------------------
local function dust(r, g, b)
  return function(rng)
    local t = new(0, 0, 0, 0)
    for i = 0, N - 1 do
      for w = -1, 1 do
        local k = 0.75 + rng:next() * 0.3
        set(t, i, 7 + w, r * k, g * k, b * k)
        set(t, 7 + w, i, r * k, g * k, b * k)
      end
    end
    for y = 5, 10 do for x = 5, 10 do
      local k = 0.8 + rng:next() * 0.25
      set(t, x, y, r * k, g * k, b * k)
    end end
    return t
  end
end
G.redstone_dust = dust(110, 10, 10)
G.redstone_dust_on = dust(250, 40, 30)

local function rtorch(on)
  return function()
    local t = new(0, 0, 0, 0)
    for y = 8, 15 do set(t, 7, y, 110, 85, 50); set(t, 8, y, 90, 68, 40) end
    local c = on and { 255, 60, 40 } or { 90, 20, 20 }
    local c2 = on and { 255, 160, 140 } or { 60, 15, 15 }
    for y = 5, 7 do set(t, 7, y, c[1], c[2], c[3]); set(t, 8, y, c[1], c[2], c[3]) end
    set(t, 7, 5, c2[1], c2[2], c2[3])
    return t
  end
end
G.redstone_torch = rtorch(true)
G.redstone_torch_off = rtorch(false)

G.lever = function()
  local t = new(0, 0, 0, 0)
  for y = 2, 13 do set(t, 7, y, 120, 90, 50); set(t, 8, y, 100, 75, 40) end
  return t
end

local function repeater(on)
  return function(rng)
    local t = noisy(rng, 160, 160, 160, 6)
    border(t, 0.8)
    local c = on and { 240, 40, 30 } or { 110, 20, 20 }
    for y = 2, 13 do set(t, 7, y, c[1], c[2], c[3]); set(t, 8, y, c[1], c[2], c[3]) end
    for i = 0, 3 do
      set(t, 7 - i, 2 + i, c[1], c[2], c[3]); set(t, 8 + i, 2 + i, c[1], c[2], c[3])
    end
    return t
  end
end
G.repeater = repeater(false)
G.repeater_on = repeater(true)
G.stone_button = function(rng) return noisy(rng, 140, 140, 140, 8) end
G.pressure_plate = function(rng)
  local t = noisy(rng, 135, 135, 135, 6)
  border(t, 0.75)
  return t
end
local function lamp(on)
  return function(rng)
    local t = cells(rng, 9, on and { { 250, 210, 120 }, { 230, 170, 80 }, { 255, 240, 180 } }
      or { { 110, 70, 40 }, { 90, 55, 30 }, { 130, 90, 55 } }, 0.6)
    border(t, 0.55)
    return t
  end
end
G.redstone_lamp = lamp(false)
G.redstone_lamp_on = lamp(true)

G.piston_side = function(rng)
  local t = noisy(rng, 120, 120, 120, 8)
  for y = 0, 3 do
    for x = 0, N - 1 do
      local k = 0.9 + rng:next() * 0.15
      set(t, x, y, 160 * k, 125 * k, 75 * k)
    end
  end
  for x = 0, N - 1 do shade(t, x, 4, 0.6) end
  border(t, 0.8)
  return t
end
G.piston_top = function(rng)
  local t = planks(rng, 165, 130, 80)
  border(t, 0.7)
  return t
end
G.piston_top_sticky = function(rng)
  local t = G.piston_top(rng)
  for y = 3, 12 do for x = 3, 12 do
    if rng:next() < 0.85 then set(t, x, y, 100 + rng:int(0, 30), 180 + rng:int(0, 40), 80) end
  end end
  return t
end
G.piston_bottom = function(rng)
  local t = noisy(rng, 110, 110, 110, 8)
  border(t, 0.7)
  for y = 6, 9 do for x = 6, 9 do set(t, x, y, 60, 60, 60) end end
  return t
end
G.piston_inner = function(rng)
  local t = noisy(rng, 100, 100, 100, 8)
  for y = 6, 9 do for x = 6, 9 do set(t, x, y, 160, 125, 75) end end
  return t
end

local function rail(r, g, b)
  return function(rng)
    local t = new(0, 0, 0, 0)
    for y = 1, N - 2, 3 do
      for x = 1, N - 2 do
        local k = 0.85 + rng:next() * 0.2
        set(t, x, y, 110 * k, 80 * k, 45 * k)
        set(t, x, y + 1, 95 * k, 70 * k, 40 * k)
      end
    end
    for y = 0, N - 1 do
      set(t, 3, y, r, g, b); set(t, 4, y, r * 0.8, g * 0.8, b * 0.8)
      set(t, 11, y, r, g, b); set(t, 12, y, r * 0.8, g * 0.8, b * 0.8)
    end
    return t
  end
end
G.rail = rail(170, 170, 170)
G.powered_rail = function(rng)
  local t = rail(230, 200, 60)(rng)
  for y = 0, N - 1, 4 do set(t, 7, y, 120, 20, 20); set(t, 8, y, 120, 20, 20) end
  return t
end
G.powered_rail_on = function(rng)
  local t = rail(240, 210, 70)(rng)
  for y = 0, N - 1 do set(t, 7, y, 240, 40, 30); set(t, 8, y, 240, 40, 30) end
  return t
end
G.detector_rail = function(rng)
  local t = rail(150, 150, 150)(rng)
  for y = 6, 9 do for x = 6, 9 do set(t, x, y, 160, 30, 30) end end
  return t
end
G.rail_corner = function(rng)
  local t = new(0, 0, 0, 0)
  for y = 1, N - 2, 3 do
    for x = 1, N - 2 do
      local k = 0.85 + rng:next() * 0.2
      set(t, x, y, 110 * k, 80 * k, 45 * k)
    end
  end
  for a = 0, 40 do
    local ang = a / 40 * math.pi / 2
    for _, rad in ipairs({ 4.5, 12 }) do
      set(t, math.floor(15.5 - math.cos(ang) * rad), math.floor(15.5 - math.sin(ang) * rad), 170, 170, 170)
    end
  end
  return t
end
G.fence = G.planks
G.trapdoor = function(rng)
  local t = planks(rng, 150, 110, 60)
  border(t, 0.6)
  for y = 3, 12, 3 do for x = 3, 12 do shade(t, x, y, 0.7) end end
  return t
end

-- Brakująca tekstura: magenta-czarna szachownica (od razu widać błąd)
local function missing()
  local t = new()
  for y = 0, N - 1 do
    for x = 0, N - 1 do
      if (math.floor(x / 4) + math.floor(y / 4)) % 2 == 0 then
        set(t, x, y, 255, 0, 255)
      else
        set(t, x, y, 0, 0, 0)
      end
    end
  end
  return t
end

-- Generuje kafelek o danej nazwie (deterministycznie: ten sam wynik za każdym razem)
function M.generate(name)
  local gen = G[name]
  if not gen then return missing(), false end
  local seed = 0
  for i = 1, #name do seed = seed * 31 + name:byte(i) end
  return gen(Rng.new(seed)), true
end

M.N = N
return M
