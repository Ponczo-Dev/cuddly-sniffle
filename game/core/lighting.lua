-- core/lighting.lua
-- Oświetlenie jak w Minecraft: dwa kanały 0..15
--  * światło nieba (sky): 15 pod gołym niebem, słabnie w cieniu i w wodzie,
--  * światło bloków (pochodnie, lawa, jasnogłaz).
-- Rozchodzenie się: BFS (przeszukiwanie wszerz), każdy krok -1 (lub więcej
-- przez liście/wodę). Światło nieba w dół przez powietrze nie słabnie.
-- Przy zmianie bloku: najpierw "gasimy" stare światło, potem rozpalamy nowe.

local blocks = require("core.blocks")

local M = {}

local OPACITY = blocks.OPACITY
local LIGHT = blocks.LIGHT
local floor = math.floor
local SIZE, HEIGHT = 16, 128

-- Kolejka BFS na płaskiej tablicy (x, y, z, poziom)
local qx, qy, qz, ql = {}, {}, {}, {}
local qHead, qTail = 1, 0
local function qreset() qHead, qTail = 1, 0 end
local function qpush(x, y, z, l)
  qTail = qTail + 1
  qx[qTail], qy[qTail], qz[qTail], ql[qTail] = x, y, z, l
end

local rx, ry, rz, rl = {}, {}, {}, {}  -- kolejka usuwania
local rHead, rTail = 1, 0

local DX = { 1, -1, 0, 0, 0, 0 }
local DY = { 0, 0, 1, -1, 0, 0 }
local DZ = { 0, 0, 0, 0, 1, -1 }

-- Szybki dostęp do chunków z pamięcią ostatniego
local lastKey, lastChunk = nil, nil
local function chunkAt(world, x, z)
  local cx, cz = floor(x / SIZE), floor(z / SIZE)
  local key = (cx + 32768) * 65536 + (cz + 32768)
  if key == lastKey then return lastChunk end
  local c = world.chunks[key]
  lastKey, lastChunk = key, c
  return c
end

local function getArr(c, sky)
  return sky and c.sky or c.blockLight
end

-- Rozchodzenie się światła z kolejki (kanał sky albo block)
local function propagate(world, sky)
  while qHead <= qTail do
    local x, y, z, l = qx[qHead], qy[qHead], qz[qHead], ql[qHead]
    qHead = qHead + 1
    if l > 1 then
      for d = 1, 6 do
        local nx, ny, nz = x + DX[d], y + DY[d], z + DZ[d]
        if ny >= 0 and ny < HEIGHT then
          local c = chunkAt(world, nx, nz)
          if c and c.generated then
            local i = (nx % SIZE) + (nz % SIZE) * SIZE + ny * 256
            local op = OPACITY[c.blocks[i]]
            if op < 15 then
              local nl
              if sky and d == 4 and l == 15 and op == 0 then
                nl = 15 -- pełne światło nieba schodzi w dół bez strat
              else
                nl = l - (op > 1 and op or 1)
              end
              local arr = sky and c.sky or c.blockLight
              if nl > arr[i] then
                arr[i] = nl
                if c.lit then c.dirty = true; world:markDirty(nx, ny, nz) end
                qpush(nx, ny, nz, nl)
              end
            end
          end
        end
      end
    end
  end
  qreset()
end

-- ---------------------------------------------------------------------------
-- Pierwsze oświetlenie chunka (po wygenerowaniu)
-- ---------------------------------------------------------------------------
function M.lightChunk(world, chunk)
  lastKey = nil
  local bx, bz = chunk.cx * SIZE, chunk.cz * SIZE
  local b, sky, bl = chunk.blocks, chunk.sky, chunk.blockLight
  qreset()

  -- 1) kolumny: światło nieba z góry w dół (w Netherze nieba nie ma)
  local noSky = world.noSky
  local maxH = 0
  for lz = 0, SIZE - 1 do
    for lx = 0, SIZE - 1 do
      local l = noSky and 0 or 15
      for y = HEIGHT - 1, 0, -1 do
        local i = lx + lz * SIZE + y * 256
        if l > 0 then
          local op = OPACITY[b[i]]
          if not (op == 0 and l == 15) then
            l = l - (op > 1 and op or 1)
            if op >= 15 then l = 0 end
            if l < 0 then l = 0 end
          end
        end
        sky[i] = l
        bl[i] = 0
      end
      local h = chunk.heightMap[lx + lz * SIZE]
      if h > maxH then maxH = h end
    end
  end

  -- 2) rozchodzenie w bok: komórki poniżej najwyższego terenu w okolicy
  for lz = 0, (noSky and -1 or SIZE - 1) do
    for lx = 0, SIZE - 1 do
      local top = chunk.heightMap[lx + lz * SIZE]
      -- najwyższy sąsiad (światło wpada z boku pod nawisy)
      for d = 1, 4 do
        local nx, nz = bx + lx + DX[d == 3 and 5 or (d == 4 and 6 or d)],
          bz + lz + DZ[d == 3 and 5 or (d == 4 and 6 or d)]
        local nh = world:getHeight(nx, nz)
        if nh > top then top = nh end
      end
      for y = 0, math.min(top, HEIGHT - 1) do
        local i = lx + lz * SIZE + y * 256
        local l = sky[i]
        if l > 1 then qpush(bx + lx, y, bz + lz, l) end
      end
    end
  end
  -- światło z oświetlonych już sąsiadów
  if not noSky then
    M.pullFromNeighbors(world, chunk, true)
    propagate(world, true)
  end

  -- 3) światło bloków (pochodnie, lawa...)
  for i = 0, SIZE * SIZE * HEIGHT - 1 do
    local e = LIGHT[b[i]]
    if e > 0 then
      bl[i] = e
      local lx, lz, y = i % SIZE, floor(i / SIZE) % SIZE, floor(i / 256)
      qpush(bx + lx, y, bz + lz, e)
    end
  end
  M.pullFromNeighbors(world, chunk, false)
  propagate(world, false)
end

-- Dodaje do kolejki brzegowe komórki sąsiednich (oświetlonych) chunków
function M.pullFromNeighbors(world, chunk, sky)
  local bx, bz = chunk.cx * SIZE, chunk.cz * SIZE
  local sides = {
    { -1, 0, SIZE - 1, nil }, { 1, 0, 0, nil }, { 0, -1, nil, SIZE - 1 }, { 0, 1, nil, 0 },
  }
  for _, s in ipairs(sides) do
    local n = world:getChunk(chunk.cx + s[1], chunk.cz + s[2])
    if n and n.lit then
      local arr = getArr(n, sky)
      for k = 0, SIZE - 1 do
        local lx = s[3] or k
        local lz = s[4] or k
        -- nad terenem wszędzie jest pełne światło nieba: nie ma czego rozchodzić
        local top = HEIGHT - 1
        if sky then
          local ox = s[3] and (s[1] < 0 and 0 or SIZE - 1) or k
          local oz = s[4] and (s[2] < 0 and 0 or SIZE - 1) or k
          top = math.max(n.heightMap[lx + lz * SIZE], chunk.heightMap[ox + oz * SIZE]) + 1
          if top > HEIGHT - 1 then top = HEIGHT - 1 end
        end
        for y = 0, top do
          local l = arr[lx + lz * SIZE + y * 256]
          if l > 1 then
            qpush(n.cx * SIZE + lx, y, n.cz * SIZE + lz, l)
          end
        end
      end
    end
  end
  local _ = bx + bz
end

-- ---------------------------------------------------------------------------
-- Aktualizacja po zmianie bloku
-- ---------------------------------------------------------------------------
local function getLight(world, x, y, z, sky)
  if y < 0 then return 0 end
  if y >= HEIGHT then return sky and 15 or 0 end
  local c = chunkAt(world, x, z)
  if not c or not c.generated then return 0 end
  local arr = sky and c.sky or c.blockLight
  return arr[(x % SIZE) + (z % SIZE) * SIZE + y * 256]
end

local function setLight(world, x, y, z, sky, v)
  local c = chunkAt(world, x, z)
  if not c then return end
  local arr = sky and c.sky or c.blockLight
  local i = (x % SIZE) + (z % SIZE) * SIZE + y * 256
  if arr[i] ~= v then
    arr[i] = v
    world:markDirty(x, y, z)
  end
end

local function relight(world, x, y, z, sky, newId)
  local old = getLight(world, x, y, z, sky)

  -- 1) usuwanie starego światła
  rHead, rTail = 1, 0
  qreset()
  setLight(world, x, y, z, sky, 0)
  rTail = 1
  rx[1], ry[1], rz[1], rl[1] = x, y, z, old
  while rHead <= rTail do
    local cx, cy, cz, cl = rx[rHead], ry[rHead], rz[rHead], rl[rHead]
    rHead = rHead + 1
    for d = 1, 6 do
      local nx, ny, nz = cx + DX[d], cy + DY[d], cz + DZ[d]
      if ny >= 0 and ny < HEIGHT then
        local c = chunkAt(world, nx, nz)
        if c and c.generated then
          local i = (nx % SIZE) + (nz % SIZE) * SIZE + ny * 256
          local arr = sky and c.sky or c.blockLight
          local nl = arr[i]
          if nl > 0 then
            local fromAbove = sky and d == 4 and cl == 15 and nl == 15
            if nl < cl or fromAbove then
              arr[i] = 0
              world:markDirty(nx, ny, nz)
              rTail = rTail + 1
              rx[rTail], ry[rTail], rz[rTail], rl[rTail] = nx, ny, nz, nl
              -- inne źródło światła (np. druga pochodnia) świeci dalej
              local e = (not sky) and LIGHT[c.blocks[i]] or 0
              if e > 0 then
                arr[i] = e
                qpush(nx, ny, nz, e)
              end
            else
              qpush(nx, ny, nz, nl) -- jaśniejszy sąsiad: rozpali na nowo
            end
          end
        end
      end
    end
  end

  -- 2) nowe źródło w tym miejscu
  local base = 0
  if sky then
    if y >= HEIGHT - 1 or (getLight(world, x, y + 1, z, true) == 15 and OPACITY[newId] == 0) then
      base = 15
    end
  else
    base = LIGHT[newId]
  end
  if base > 0 then
    setLight(world, x, y, z, sky, base)
    qpush(x, y, z, base)
  end
  -- sąsiedzi mogą rozświetlić to miejsce
  for d = 1, 6 do
    local nx, ny, nz = x + DX[d], y + DY[d], z + DZ[d]
    local nl = getLight(world, nx, ny, nz, sky)
    if nl > 1 then qpush(nx, ny, nz, nl) end
  end
  -- światło nieba nad usuniętym blokiem schodzi w dół całą kolumną
  if sky and base == 15 then
    local yy = y - 1
    while yy >= 0 do
      local c = chunkAt(world, x, z)
      if not c then break end
      local i = (x % SIZE) + (z % SIZE) * SIZE + yy * 256
      if OPACITY[c.blocks[i]] ~= 0 then break end
      if c.sky[i] < 15 then
        c.sky[i] = 15
        world:markDirty(x, yy, z)
      end
      qpush(x, yy, z, 15)
      yy = yy - 1
    end
  end
  propagate(world, sky)
end

function M.onBlockChanged(world, x, y, z, oldId, newId)
  lastKey = nil
  if OPACITY[oldId] ~= OPACITY[newId] and not world.noSky then
    relight(world, x, y, z, true, newId)
    -- przy postawieniu bloku światło nieba pod nim musi zgasnąć całą kolumną
    if OPACITY[newId] > 0 then
      local yy = y - 1
      while yy >= 0 and getLight(world, x, yy, z, true) == 15 do
        relight(world, x, yy, z, true, world:getBlock(x, yy, z))
        yy = yy - 1
      end
    end
  end
  if OPACITY[oldId] ~= OPACITY[newId] or LIGHT[oldId] ~= LIGHT[newId] then
    relight(world, x, y, z, false, newId)
  end
end

return M
