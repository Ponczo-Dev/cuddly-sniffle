-- core/rails.lua
-- Tory: kształty (proste, zakręty, wzniesienia), automatyczne łączenie
-- z sąsiednimi torami i jazda wagonika po torach.
-- Meta toru (jak w MC): 0 = N-S, 1 = E-W, 2-5 = wzniesienia (E, W, N, S),
-- 6-9 = zakręty (SE, SW, NW, NE). Tor napędzany/detektor: 0-5 + bit 8 (aktywny).

local blocks = require("core.blocks")

local R = {}

R.RAIL, R.POWERED, R.DETECTOR = 66, 27, 28

-- wyjścia (dx, dz) i kierunek wznoszenia
R.SHAPES = {
  [0] = { exits = { { 0, -1 }, { 0, 1 } } },
  [1] = { exits = { { 1, 0 }, { -1, 0 } } },
  [2] = { exits = { { -1, 0 }, { 1, 0 } }, up = { 1, 0 } },
  [3] = { exits = { { -1, 0 }, { 1, 0 } }, up = { -1, 0 } },
  [4] = { exits = { { 0, 1 }, { 0, -1 } }, up = { 0, -1 } },
  [5] = { exits = { { 0, 1 }, { 0, -1 } }, up = { 0, 1 } },
  [6] = { exits = { { 0, 1 }, { 1, 0 } } },
  [7] = { exits = { { 0, 1 }, { -1, 0 } } },
  [8] = { exits = { { 0, -1 }, { -1, 0 } } },
  [9] = { exits = { { 0, -1 }, { 1, 0 } } },
}

function R.isRail(id)
  return id == R.RAIL or id == R.POWERED or id == R.DETECTOR
end
local isRail = R.isRail

function R.shapeOf(id, meta)
  if id == R.RAIL then return meta % 16 end
  return meta % 8
end

-- Czy tor w (x,y,z) ma wyjście w stronę (dx, dz)
local function hasExit(world, x, y, z, dx, dz)
  local id, meta = world:getBlockAndMeta(x, y, z)
  if not isRail(id) then return false end
  local sh = R.SHAPES[R.shapeOf(id, meta)]
  if not sh then return false end
  for _, e in ipairs(sh.exits) do
    if e[1] == dx and e[2] == dz then return true end
  end
  return false
end

-- Ile połączeń ma tor (sąsiednie tory wskazujące na niego)
local function connections(world, x, y, z, id, meta)
  local sh = R.SHAPES[R.shapeOf(id, meta)]
  local n = 0
  for _, e in ipairs(sh.exits) do
    for dy = -1, 1 do
      if hasExit(world, x + e[1], y + dy, z + e[2], -e[1], -e[2]) then n = n + 1 break end
    end
  end
  return n
end

local DIRS = { { 0, -1 }, { 0, 1 }, { 1, 0 }, { -1, 0 } }

-- Dobór kształtu toru do sąsiadów. canCurve = false dla torów specjalnych.
function R.autoShape(world, x, y, z, canCurve, preferAxis)
  local found = {}
  for _, d in ipairs(DIRS) do
    local nx, nz = x + d[1], z + d[2]
    for dy = 1, -1, -1 do
      local nid = world:getBlock(nx, y + dy, nz)
      if isRail(nid) then
        -- sąsiad z wolnym końcem albo już wskazujący na nas
        local nmeta = world:getMeta(nx, y + dy, nz)
        if hasExit(world, nx, y + dy, nz, -d[1], -d[2]) or connections(world, nx, y + dy, nz, nid, nmeta) < 2 then
          found[#found + 1] = { d[1], d[2], dy }
          break
        end
      end
    end
  end
  local function straight(d, up)
    if d[1] ~= 0 then
      if up then return d[1] > 0 and 2 or 3 end
      return 1
    end
    if up then return d[2] < 0 and 4 or 5 end
    return 0
  end
  if #found == 0 then
    return preferAxis == "x" and 1 or 0
  end
  if #found == 1 then
    local f = found[1]
    return straight(f, f[3] == 1)
  end
  local a, b = found[1], found[2]
  if a[1] == -b[1] and a[2] == -b[2] then
    if a[3] == 1 then return straight(a, true) end
    if b[3] == 1 then return straight(b, true) end
    return straight(a, false)
  end
  if not canCurve then return straight(a, a[3] == 1) end
  -- zakręt: znajdź kształt z wyjściami a i b
  for shape = 6, 9 do
    local ex = R.SHAPES[shape].exits
    local ok1 = (ex[1][1] == a[1] and ex[1][2] == a[2]) or (ex[2][1] == a[1] and ex[2][2] == a[2])
    local ok2 = (ex[1][1] == b[1] and ex[1][2] == b[2]) or (ex[2][1] == b[1] and ex[2][2] == b[2])
    if ok1 and ok2 then return shape end
  end
  return straight(a, false)
end

-- Po postawieniu toru: dopasuj kształt jego i sąsiadów z wolnymi końcami
function R.onPlaced(game, x, y, z, preferAxis)
  local world = game.world
  local id, meta = world:getBlockAndMeta(x, y, z)
  local special = id ~= R.RAIL
  local shape = R.autoShape(world, x, y, z, not special, preferAxis)
  world:setBlock(x, y, z, id, special and (shape + (meta >= 8 and 8 or 0)) or shape)
  for _, d in ipairs(DIRS) do
    for dy = -1, 1 do
      local nx, ny, nz = x + d[1], y + dy, z + d[2]
      local nid, nmeta = world:getBlockAndMeta(nx, ny, nz)
      if isRail(nid) and connections(world, nx, ny, nz, nid, nmeta) < 2 then
        local ns = R.autoShape(world, nx, ny, nz, nid == R.RAIL)
        local newMeta = nid == R.RAIL and ns or (ns + (nmeta >= 8 and 8 or 0))
        if newMeta ~= nmeta then world:setBlock(nx, ny, nz, nid, newMeta) end
      end
    end
  end
end

-- Wysokość toru w punkcie (dla wagonika), względem y bloku
function R.heightAt(shape, fx, fz)
  local sh = R.SHAPES[shape]
  if not sh or not sh.up then return 0 end
  local u = sh.up
  if u[1] > 0 then return fx elseif u[1] < 0 then return 1 - fx end
  if u[2] > 0 then return fz end
  return 1 - fz
end

-- ---------------------------------------------------------------------------
-- Jazda wagonika po torze
-- ---------------------------------------------------------------------------
-- Zwraca tor pod wagonikiem: x, y, z, id, meta (albo nil)
function R.railUnder(world, e)
  local bx, by, bz = math.floor(e.x), math.floor(e.y + 0.1), math.floor(e.z)
  local id, meta = world:getBlockAndMeta(bx, by, bz)
  if isRail(id) then return bx, by, bz, id, meta end
  id, meta = world:getBlockAndMeta(bx, by - 1, bz)
  if isRail(id) then return bx, by - 1, bz, id, meta end
  return nil
end

-- Jeden tick ruchu wagonika po torze. Zwraca true, jeśli był na torze.
function R.moveCart(game, e)
  local world = game.world
  local bx, by, bz, id, meta = R.railUnder(world, e)
  if not bx then return false end
  local shape = R.shapeOf(id, meta)
  local sh = R.SHAPES[shape]
  if not sh then return false end
  local e1, e2 = sh.exits[1], sh.exits[2]

  local speed = math.sqrt(e.vx * e.vx + e.vz * e.vz)
  -- w którą stronę jedziemy: do wyjścia bardziej zgodnego z prędkością
  local d1 = e.vx * e1[1] + e.vz * e1[2]
  local d2 = e.vx * e2[1] + e.vz * e2[2]
  local exit = d2 >= d1 and e2 or e1
  local entry = exit == e2 and e1 or e2

  -- wzniesienie: grawitacja ciągnie w dół toru
  if sh.up then
    local downhill = -1
    if exit[1] == sh.up[1] and exit[2] == sh.up[2] then downhill = 1 end
    speed = speed - 0.0078125 * 2 * downhill
    if speed < 0 then
      speed = -speed
      exit, entry = entry, exit
    end
  end

  -- tory napędzane: przyspieszenie albo hamowanie
  if id == R.POWERED then
    if meta >= 8 then
      if speed > 0.01 then
        speed = speed + 0.06
      else
        -- start od ściany: odpychamy w stronę wolnego wyjścia
        for _, ex in ipairs({ e1, e2 }) do
          if blocks.OPAQUE[world:getBlock(bx - ex[1], by, bz - ex[2])] == 1 then
            exit, entry = ex, ex == e1 and e2 or e1
            speed = 0.1
          end
        end
      end
    else
      speed = speed * 0.5
      if speed < 0.03 then speed = 0 end
    end
  end

  -- jadący gracz może popychać wagonik (W)
  if e.rider and e.pushX then
    local push = e.pushX * exit[1] + e.pushZ * exit[2]
    if speed < 0.01 then
      local pe = e.pushX * entry[1] + e.pushZ * entry[2]
      if pe > push then exit, entry = entry, exit; push = pe end
    end
    if push > 0 then speed = speed + push * 0.01 end
  end

  speed = speed * 0.997
  if speed > 0.4 then speed = 0.4 end

  -- cel: środek krawędzi wyjściowej; sterujemy w jego stronę
  local tx = bx + 0.5 + exit[1] * 0.5
  local tz = bz + 0.5 + exit[2] * 0.5
  -- na prostych torach trzymaj się środka
  if exit[1] == 0 then e.x = e.x + (bx + 0.5 - e.x) * 0.5 end
  if exit[2] == 0 then e.z = e.z + (bz + 0.5 - e.z) * 0.5 end
  local dx, dz = tx - e.x, tz - e.z
  local len = math.sqrt(dx * dx + dz * dz)
  if len < 0.001 then dx, dz, len = exit[1], exit[2], 1 end
  e.vx, e.vz = dx / len * speed, dz / len * speed
  -- przesuń (z wyjściem poza blok, jeśli prędkość większa niż dystans)
  local step = math.min(speed, len + 0.01)
  e.x = e.x + dx / len * step
  e.z = e.z + dz / len * step
  if speed > len then
    local rest = speed - len
    e.x = e.x + exit[1] * rest
    e.z = e.z + exit[2] * rest
  end
  -- wysokość toru
  local nbx, nby, nbz, nid, nmeta = R.railUnder(world, { x = e.x, y = by + 0.5, z = e.z })
  if not nbx then
    -- koniec toru w górę albo w dół
    local upId, upMeta = world:getBlockAndMeta(math.floor(e.x), by + 1, math.floor(e.z))
    if isRail(upId) then nbx, nby, nbz, nid, nmeta = math.floor(e.x), by + 1, math.floor(e.z), upId, upMeta end
  end
  if nbx then
    local ns = R.shapeOf(nid, nmeta)
    e.y = nby + R.heightAt(ns, e.x - nbx, e.z - nbz) + 0.0625
  else
    e.y = by + 0.0625
  end
  e.vy = 0
  e.onRail = true

  -- detektor
  if id == R.DETECTOR and meta < 8 then
    world:setBlock(bx, by, bz, id, meta + 8)
    game:scheduleTick(bx, by, bz, 20)
    require("core.redstone").notifyAround(game, bx, by, bz)
  end
  return true
end

return R
