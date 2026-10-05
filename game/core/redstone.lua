-- core/redstone.lua
-- Redstone (jak w Beta 1.7-1.8, w uproszczeniu):
--  * przewód: moc 0..15, słabnie o 1 na blok, przechodzi po schodkach,
--  * źródła: dźwignia, przycisk, płyta naciskowa, pochodnia redstone,
--    przekaźnik (opóźnienie 1-4, dioda),
--  * pochodnia gaśnie, gdy blok, na którym wisi, jest zasilony (negacja),
--  * blok zasilony "mocno" (pochodnią pod spodem, przekaźnikiem, dźwignią)
--    przekazuje zasilanie przewodom i mechanizmom obok,
--  * mechanizmy: drzwi, TNT, lampa, tłok i lepki tłok (pcha do 12 bloków).

local blocks = require("core.blocks")

local R = {}

local defs = blocks.defs
local OPAQUE = blocks.OPAQUE
local FACING4, FACING6, SUPPORT = blocks.FACING4, blocks.FACING6, blocks.SUPPORT

local WIRE, TORCH_OFF, TORCH_ON = 55, 75, 76
local LEVER, BUTTON, PLATE = 69, 77, 70
local REP_OFF, REP_ON = 93, 94
local LAMP_OFF, LAMP_ON = 123, 124
local PISTON, STICKY, HEAD = 33, 29, 34
local DOOR, TNT = 64, 46

local DIRS = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }
local HORIZ = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function isWire(id) return id == WIRE end

-- Podpora pochodni/dźwigni/przycisku (pozycja bloku, na którym wisi)
local function supportOf(id, meta, x, y, z)
  local side = meta % 8
  if id == TORCH_ON or id == TORCH_OFF then side = meta end
  local v = SUPPORT[side]
  if not v then return nil end
  return x + v[1], y + v[2], z + v[3]
end
R.supportOf = supportOf

-- Moc, jaką element w (sx,sy,sz) daje do pozycji (tx,ty,tz). 0 albo 15.
function R.sourcePower(world, sx, sy, sz, tx, ty, tz)
  local id, meta = world:getBlockAndMeta(sx, sy, sz)
  if id == TORCH_ON then
    local ax, ay, az = supportOf(id, meta, sx, sy, sz)
    if ax == tx and ay == ty and az == tz then return 0 end
    return 15
  elseif id == LEVER or id == BUTTON then
    return meta >= 8 and 15 or 0
  elseif id == PLATE then
    return meta > 0 and 15 or 0
  elseif id == 28 then
    return meta >= 8 and 15 or 0
  elseif id == REP_ON then
    local f = FACING4[meta % 4]
    if sx + f[1] == tx and sy == ty and sz + f[3] == tz then return 15 end
  end
  return 0
end

-- Blok mocno zasilony: pochodnia pod nim, przekaźnik w niego skierowany,
-- dźwignia/przycisk na nim zawieszony, wciśnięta płyta na nim
function R.strongPowered(world, bx, by, bz)
  if OPAQUE[world:getBlock(bx, by, bz)] ~= 1 then return false end
  for _, d in ipairs(DIRS) do
    local nx, ny, nz = bx + d[1], by + d[2], bz + d[3]
    local id, meta = world:getBlockAndMeta(nx, ny, nz)
    if id == TORCH_ON and d[2] == -1 then
      return true
    elseif (id == LEVER or id == BUTTON) and meta >= 8 then
      local ax, ay, az = supportOf(id, meta, nx, ny, nz)
      if ax == bx and ay == by and az == bz then return true end
    elseif id == PLATE and meta > 0 and d[2] == 1 then
      return true
    elseif id == REP_ON then
      local f = FACING4[meta % 4]
      if nx + f[1] == bx and ny == by and nz + f[3] == bz then return true end
    end
  end
  return false
end

-- Liczba poziomych połączeń przewodu (do ustalenia, w co "celuje")
local function wireLinks(world, x, y, z)
  local links = {}
  local aboveOpaque = OPAQUE[world:getBlock(x, y + 1, z)] == 1
  for _, h in ipairs(HORIZ) do
    local nx, nz = x + h[1], z + h[2]
    local nid = world:getBlock(nx, y, nz)
    local d = defs[nid]
    local connects = nid == WIRE or (d and d.redstone and d.redstone ~= "wire" and d.redstone ~= "head"
      and d.redstone ~= "piston" and d.redstone ~= "lamp")
    if not connects and OPAQUE[nid] ~= 1 and isWire(world:getBlock(nx, y - 1, nz)) then connects = true end
    if not connects and not aboveOpaque and isWire(world:getBlock(nx, y + 1, nz)) then connects = true end
    if connects then links[#links + 1] = h end
  end
  return links
end
R.wireLinks = wireLinks

-- Blok słabo zasilony: przewód na nim albo przewód skierowany w niego
function R.weakPowered(world, bx, by, bz)
  if OPAQUE[world:getBlock(bx, by, bz)] ~= 1 then return false end
  local aid, ameta = world:getBlockAndMeta(bx, by + 1, bz)
  if aid == WIRE and ameta > 0 then return true end
  for _, h in ipairs(HORIZ) do
    local wx, wz = bx - h[1], bz - h[2]
    local id, meta = world:getBlockAndMeta(wx, by, wz)
    if id == WIRE and meta > 0 then
      local links = wireLinks(world, wx, by, wz)
      -- przewód kończący się na bloku albo prosty przewód skierowany w niego
      if #links == 0 then return true end
      if #links == 1 and links[1][1] == -h[1] and links[1][2] == -h[2] then return true end
    end
  end
  return false
end

function R.blockPowered(world, x, y, z)
  return R.strongPowered(world, x, y, z) or R.weakPowered(world, x, y, z)
end

-- Czy mechanizm w (x,y,z) jest zasilany. except = pomiń ten kierunek (np. przód tłoka)
function R.isPowered(world, x, y, z, exceptDir)
  for i, d in ipairs(DIRS) do
    if i ~= exceptDir then
      local nx, ny, nz = x + d[1], y + d[2], z + d[3]
      if R.sourcePower(world, nx, ny, nz, x, y, z) > 0 then return true end
      local id, meta = world:getBlockAndMeta(nx, ny, nz)
      if id == WIRE and meta > 0 and d[2] >= 0 then return true end
      if OPAQUE[id] == 1 and R.blockPowered(world, nx, ny, nz) then return true end
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Powiadamianie okolicy o zmianie stanu źródła
-- ---------------------------------------------------------------------------
function R.notifyAround(game, x, y, z, skipWires)
  local logic = require("core.blocklogic")
  local world = game.world
  for dx = -2, 2 do
    for dy = -2, 2 do
      for dz = -2, 2 do
        if math.abs(dx) + math.abs(dy) + math.abs(dz) <= 2 and not (dx == 0 and dy == 0 and dz == 0) then
          local px, py, pz = x + dx, y + dy, z + dz
          local id = world:getBlock(px, py, pz)
          local d = defs[id]
          if d and (d.redstone or id == DOOR or id == TNT) then
            if not (skipWires and id == WIRE) then
              logic.onNeighborChanged(game, px, py, pz)
            end
          end
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Sieć przewodów: przeliczenie mocy całej połączonej sieci
-- ---------------------------------------------------------------------------
local function key(x, y, z) return x .. "," .. y .. "," .. z end

local function wireNeighbors(world, x, y, z)
  local out = {}
  local aboveOpaque = OPAQUE[world:getBlock(x, y + 1, z)] == 1
  for _, h in ipairs(HORIZ) do
    local nx, nz = x + h[1], z + h[2]
    local nid = world:getBlock(nx, y, nz)
    if nid == WIRE then
      out[#out + 1] = { nx, y, nz }
    else
      if OPAQUE[nid] ~= 1 and isWire(world:getBlock(nx, y - 1, nz)) then
        out[#out + 1] = { nx, y - 1, nz }
      end
      if not aboveOpaque and isWire(world:getBlock(nx, y + 1, nz)) then
        out[#out + 1] = { nx, y + 1, nz }
      end
    end
  end
  return out
end

-- Moc wpływająca do przewodu bezpośrednio ze źródeł
local function directPower(world, x, y, z)
  for _, d in ipairs(DIRS) do
    local nx, ny, nz = x + d[1], y + d[2], z + d[3]
    if R.sourcePower(world, nx, ny, nz, x, y, z) > 0 then return 15 end
    if OPAQUE[world:getBlock(nx, ny, nz)] == 1 and R.strongPowered(world, nx, ny, nz) then return 15 end
  end
  return 0
end

function R.updateWire(game, x, y, z)
  local world = game.world
  if world:getBlock(x, y, z) ~= WIRE then return end
  -- 1) zbierz sieć
  local nodes, index = {}, {}
  local queue = { { x, y, z } }
  index[key(x, y, z)] = 1
  nodes[1] = { x, y, z }
  local head = 1
  while head <= #queue and #nodes < 2000 do
    local q = queue[head]
    head = head + 1
    for _, n in ipairs(wireNeighbors(world, q[1], q[2], q[3])) do
      local k = key(n[1], n[2], n[3])
      if not index[k] then
        nodes[#nodes + 1] = n
        index[k] = #nodes
        queue[#queue + 1] = n
      end
    end
  end
  -- 2) moc: źródła 15, dalej -1 na krok (kolejka kubełkowa)
  local power = {}
  local buckets = {}
  for l = 0, 15 do buckets[l] = {} end
  for i, n in ipairs(nodes) do
    local p = directPower(world, n[1], n[2], n[3])
    power[i] = p
    if p > 0 then table.insert(buckets[p], i) end
  end
  for l = 15, 2, -1 do
    local b = buckets[l]
    local j = 1
    while j <= #b do
      local i = b[j]
      j = j + 1
      if power[i] == l then
        local n = nodes[i]
        for _, m in ipairs(wireNeighbors(world, n[1], n[2], n[3])) do
          local mi = index[key(m[1], m[2], m[3])]
          if mi and power[mi] < l - 1 then
            power[mi] = l - 1
            table.insert(buckets[l - 1], mi)
          end
        end
      end
    end
  end
  -- 3) zapis zmian i powiadomienie mechanizmów
  local changed = {}
  for i, n in ipairs(nodes) do
    if world:getMeta(n[1], n[2], n[3]) ~= power[i] then
      world:setBlock(n[1], n[2], n[3], WIRE, power[i])
      changed[#changed + 1] = n
    end
  end
  for _, n in ipairs(changed) do R.notifyAround(game, n[1], n[2], n[3], true) end
end

-- ---------------------------------------------------------------------------
-- Elementy z opóźnieniem: pochodnia i przekaźnik
-- ---------------------------------------------------------------------------
local function repeaterInput(world, x, y, z, meta)
  local f = FACING4[meta % 4]
  local bx, bz = x - f[1], z - f[3]
  local id, bmeta = world:getBlockAndMeta(bx, y, bz)
  if id == WIRE then return bmeta > 0 end
  if R.sourcePower(world, bx, y, bz, x, y, z) > 0 then return true end
  if OPAQUE[id] == 1 and R.blockPowered(world, bx, y, bz) then return true end
  return false
end

local function repeaterDelay(meta)
  return (math.floor(meta / 4) % 4 + 1) * 2
end

function R.onNeighborChanged(game, x, y, z, id, meta)
  local world = game.world
  local kind = defs[id] and defs[id].redstone
  if kind == "wire" then
    R.updateWire(game, x, y, z)
  elseif kind == "torch" then
    game:scheduleTick(x, y, z, 2)
  elseif kind == "repeater" then
    local input = repeaterInput(world, x, y, z, meta)
    if input ~= (id == REP_ON) then game:scheduleTick(x, y, z, repeaterDelay(meta)) end
  elseif kind == "lamp" then
    local p = R.isPowered(world, x, y, z)
    if p and id == LAMP_OFF then
      world:setBlock(x, y, z, LAMP_ON, 0)
    elseif not p and id == LAMP_ON then
      game:scheduleTick(x, y, z, 4)
    end
  elseif kind == "piston" then
    R.updatePiston(game, x, y, z, id, meta)
  elseif kind == "poweredrail" then
    local powered = R.railChainPowered(world, x, y, z, meta % 8)
    local want = (meta % 8) + (powered and 8 or 0)
    if want ~= meta then
      world:setBlock(x, y, z, id, want)
      -- sąsiednie tory zasilane w łańcuchu też się aktualizują
      for _, d in ipairs(DIRS) do
        local nx, ny, nz = x + d[1], y + d[2], z + d[3]
        if world:getBlock(nx, ny, nz) == 27 then
          require("core.blocklogic").onNeighborChanged(game, nx, ny, nz)
        end
      end
    end
  elseif id == TNT then
    if R.isPowered(world, x, y, z) then game:primeTnt(x, y, z) end
  elseif id == DOOR then
    R.updateDoor(game, x, y, z, meta)
  end
end

function R.scheduledTick(game, x, y, z, id, meta)
  local world = game.world
  local kind = defs[id] and defs[id].redstone
  if kind == "torch" then
    local ax, ay, az = supportOf(id, meta, x, y, z)
    local shouldBeOn = not R.blockPowered(world, ax, ay, az)
    if shouldBeOn and id == TORCH_OFF then
      world:setBlock(x, y, z, TORCH_ON, meta)
      R.notifyAround(game, x, y, z)
    elseif not shouldBeOn and id == TORCH_ON then
      world:setBlock(x, y, z, TORCH_OFF, meta)
      R.notifyAround(game, x, y, z)
    end
  elseif kind == "repeater" then
    local input = repeaterInput(world, x, y, z, meta)
    if input and id == REP_OFF then
      world:setBlock(x, y, z, REP_ON, meta)
      R.notifyAround(game, x, y, z)
    elseif not input and id == REP_ON then
      world:setBlock(x, y, z, REP_OFF, meta)
      R.notifyAround(game, x, y, z)
    end
  elseif kind == "lamp" then
    if id == LAMP_ON and not R.isPowered(world, x, y, z) then
      world:setBlock(x, y, z, LAMP_OFF, 0)
    end
  elseif kind == "button" then
    if meta >= 8 then
      world:setBlock(x, y, z, BUTTON, meta - 8)
      game:emit("sound", "click", x + 0.5, y + 0.5, z + 0.5)
      R.notifyAround(game, x, y, z)
    end
  elseif kind == "detector" then
    if meta >= 8 then
      local occupied = false
      for _, e in ipairs(game.entities.list) do
        if e.type == "minecart" and not e.dead and math.floor(e.x) == x and math.floor(e.z) == z
          and math.abs(e.y - y) < 1 then occupied = true end
      end
      if occupied then
        game:scheduleTick(x, y, z, 20)
      else
        world:setBlock(x, y, z, id, meta - 8)
        R.notifyAround(game, x, y, z)
      end
    end
  elseif kind == "plate" then
    if meta > 0 then
      if R.plateOccupied(game, x, y, z) then
        game:scheduleTick(x, y, z, 20)
      else
        world:setBlock(x, y, z, PLATE, 0)
        game:emit("sound", "click", x + 0.5, y + 0.5, z + 0.5)
        R.notifyAround(game, x, y, z)
      end
    end
  end
end

-- Tor zasilany: zasilony bezpośrednio albo przez łańcuch do 8 torów zasilanych
function R.railChainPowered(world, x, y, z, shape)
  if R.isPowered(world, x, y, z) then return true end
  local axis = (shape == 1 or shape == 2 or shape == 3) and { 1, 0 } or { 0, 1 }
  for _, sign in ipairs({ 1, -1 }) do
    for i = 1, 8 do
      local nx, nz = x + axis[1] * sign * i, z + axis[2] * sign * i
      local found = false
      for dy = -1, 1 do
        if world:getBlock(nx, y + dy, nz) == 27 then
          found = true
          if R.isPowered(world, nx, y + dy, nz) then return true end
          break
        end
      end
      if not found then break end
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Kliknięcia: dźwignia, przycisk, przekaźnik (zmiana opóźnienia)
-- ---------------------------------------------------------------------------
function R.onUse(game, x, y, z, id, meta)
  local world = game.world
  if id == LEVER then
    local newMeta = meta >= 8 and meta - 8 or meta + 8
    world:setBlock(x, y, z, LEVER, newMeta)
    game:emit("sound", "click", x + 0.5, y + 0.5, z + 0.5)
    R.notifyAround(game, x, y, z)
    local ax, ay, az = supportOf(id, newMeta, x, y, z)
    if ax then R.notifyAround(game, ax, ay, az) end
    return true
  elseif id == BUTTON then
    if meta < 8 then
      world:setBlock(x, y, z, BUTTON, meta + 8)
      game:emit("sound", "click", x + 0.5, y + 0.5, z + 0.5)
      game:scheduleTick(x, y, z, 20)
      R.notifyAround(game, x, y, z)
      local ax, ay, az = supportOf(id, meta, x, y, z)
      if ax then R.notifyAround(game, ax, ay, az) end
    end
    return true
  elseif id == REP_OFF or id == REP_ON then
    local delay = (math.floor(meta / 4) + 1) % 4
    world:setBlock(x, y, z, id, meta % 4 + delay * 4)
    game:emit("sound", "click", x + 0.5, y + 0.5, z + 0.5)
    return true
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Płyta naciskowa
-- ---------------------------------------------------------------------------
function R.plateOccupied(game, x, y, z)
  local function on(e)
    local hw = (e.width or 0.5) / 2
    return e.x + hw > x and e.x - hw < x + 1 and e.z + hw > z and e.z - hw < z + 1
      and e.y >= y - 0.01 and e.y < y + 0.5
  end
  if not game.dead and on(game.player) then return true end
  for _, e in ipairs(game.entities.list) do
    if not e.dead and (e.isMob or e.type == "item") and on(e) then return true end
  end
  return false
end

-- Wywoływane w ticku gry dla bytów: naciśnięcie płyty
function R.checkPlate(game, e)
  local x, y, z = math.floor(e.x), math.floor(e.y + 0.05), math.floor(e.z)
  local world = game.world
  local id, meta = world:getBlockAndMeta(x, y, z)
  if id == PLATE and meta == 0 then
    world:setBlock(x, y, z, PLATE, 1)
    game:emit("sound", "click", x + 0.5, y + 0.5, z + 0.5)
    game:scheduleTick(x, y, z, 20)
    R.notifyAround(game, x, y, z)
  end
end

-- ---------------------------------------------------------------------------
-- Drzwi sterowane prądem
-- ---------------------------------------------------------------------------
function R.updateDoor(game, x, y, z, meta)
  local world = game.world
  local lx, ly, lz = x, y, z
  local lowerMeta = meta
  if meta >= 8 then ly = y - 1; lowerMeta = world:getMeta(lx, ly, lz) end
  if world:getBlock(lx, ly, lz) ~= DOOR then return end
  local powered = R.isPowered(world, lx, ly, lz) or R.isPowered(world, lx, ly + 1, lz)
  local key_ = lx .. "," .. ly .. "," .. lz
  game.doorPower = game.doorPower or {}
  if game.doorPower[key_] == powered then return end
  game.doorPower[key_] = powered
  local open = math.floor(lowerMeta / 4) % 2 == 1
  if powered ~= open then
    local newMeta = (lowerMeta % 4) + (powered and 4 or 0)
    world:setBlock(lx, ly, lz, DOOR, newMeta)
    if world:getBlock(lx, ly + 1, lz) == DOOR then world:setBlock(lx, ly + 1, lz, DOOR, newMeta + 8) end
    game:emit("sound", "door", lx + 0.5, ly + 0.5, lz + 0.5)
  end
end

-- ---------------------------------------------------------------------------
-- Tłoki
-- ---------------------------------------------------------------------------
local FACE_INDEX = { [0] = 4, [1] = 3, [2] = 6, [3] = 5, [4] = 2, [5] = 1 } -- facing -> DIRS index

local function pushable(id)
  if id == 0 then return true end
  local d = defs[id]
  if not d then return false end
  if d.hardness < 0 or id == 49 then return false end -- skała macierzysta, obsydian
  if d.tileEntity then return false end
  if id == HEAD or ((id == PISTON or id == STICKY)) then return nil end -- sprawdzane osobno
  return true
end

-- Blok "kruchy": tłok go niszczy zamiast pchać (rośliny, pochodnie, przewód)
local function fragile(id)
  local d = defs[id]
  if not d then return false end
  if d.liquid then return true end
  return d.solid == false or d.replaceable or d.shape == "cross"
end

function R.updatePiston(game, x, y, z, id, meta)
  local facing = meta % 8
  local extended = meta >= 8
  local powered = R.isPowered(game.world, x, y, z, FACE_INDEX[facing])
  if powered and not extended then
    R.extend(game, x, y, z, id, facing)
  elseif not powered and extended then
    R.retract(game, x, y, z, id, facing)
  end
end

function R.extend(game, x, y, z, id, facing)
  local world = game.world
  local v = FACING6[facing]
  local list = {}
  local cx, cy, cz = x + v[1], y + v[2], z + v[3]
  for i = 1, 13 do
    if cy < 0 or cy >= 128 then return false end
    local bid, bmeta = world:getBlockAndMeta(cx, cy, cz)
    if bid == 0 or fragile(bid) then break end
    if i == 13 then return false end
    local ok = pushable(bid)
    if ok == nil then
      -- wsunięty tłok można pchać, wysunięty i głowicy nie
      if bid == HEAD or bmeta >= 8 then return false end
    elseif not ok then
      return false
    end
    list[#list + 1] = { cx, cy, cz, bid, bmeta }
    cx, cy, cz = cx + v[1], cy + v[2], cz + v[3]
  end
  -- ostatnie (puste lub kruche) pole: zniszcz kruchy blok
  local endId = world:getBlock(cx, cy, cz)
  if endId ~= 0 and fragile(endId) and not (defs[endId] and defs[endId].liquid) then
    game:breakBlock(cx, cy, cz, false)
  elseif endId ~= 0 and defs[endId] and defs[endId].liquid then
    world:setBlock(cx, cy, cz, 0, 0)
  end
  -- pole bezpośrednio przed tłokiem mogło być kruche
  local hx, hy, hz = x + v[1], y + v[2], z + v[3]
  if #list == 0 then
    local fid = world:getBlock(hx, hy, hz)
    if fid ~= 0 then
      if defs[fid] and defs[fid].liquid then world:setBlock(hx, hy, hz, 0, 0)
      else game:breakBlock(hx, hy, hz, false) end
    end
  end
  for i = #list, 1, -1 do
    local b = list[i]
    world:setBlock(b[1] + v[1], b[2] + v[2], b[3] + v[3], b[4], b[5])
  end
  local sticky = id == STICKY
  world:setBlock(hx, hy, hz, HEAD, facing + (sticky and 8 or 0))
  world:setBlock(x, y, z, id, facing + 8)
  -- przesuwanie bytów stojących na drodze
  local physics = require("core.physics")
  local function pushEntity(e)
    local hw = (e.width or 0.5) / 2
    for _, b in ipairs(list) do
      local bx, by, bz = b[1] + v[1], b[2] + v[2], b[3] + v[3]
      if e.x + hw > bx and e.x - hw < bx + 1 and e.y + (e.height or 1) > by and e.y < by + 1
        and e.z + hw > bz and e.z - hw < bz + 1 then
        physics.move(world, e, v[1] * 1.01, v[2] * 1.01, v[3] * 1.01, false)
        return
      end
    end
    if e.x + hw > hx and e.x - hw < hx + 1 and e.y + (e.height or 1) > hy and e.y < hy + 1
      and e.z + hw > hz and e.z - hw < hz + 1 then
      physics.move(world, e, v[1] * 1.01, v[2] * 1.01, v[3] * 1.01, false)
    end
  end
  pushEntity(game.player)
  for _, e in ipairs(game.entities.list) do if not e.dead then pushEntity(e) end end
  game:emit("sound", "piston", x + 0.5, y + 0.5, z + 0.5)
  game:notifyNeighbors(hx, hy, hz)
  for _, b in ipairs(list) do game:notifyNeighbors(b[1] + v[1], b[2] + v[2], b[3] + v[3]) end
  game:notifyNeighbors(cx, cy, cz)
  return true
end

function R.retract(game, x, y, z, id, facing)
  local world = game.world
  local v = FACING6[facing]
  local hx, hy, hz = x + v[1], y + v[2], z + v[3]
  if world:getBlock(hx, hy, hz) == HEAD then world:setBlock(hx, hy, hz, 0, 0) end
  world:setBlock(x, y, z, id, facing)
  if id == STICKY then
    local px, py, pz = hx + v[1], hy + v[2], hz + v[3]
    local bid, bmeta = world:getBlockAndMeta(px, py, pz)
    local ok = pushable(bid)
    if bid ~= 0 and ok and not fragile(bid) then
      world:setBlock(px, py, pz, 0, 0)
      world:setBlock(hx, hy, hz, bid, bmeta)
      game:notifyNeighbors(px, py, pz)
    end
  end
  game:emit("sound", "piston", x + 0.5, y + 0.5, z + 0.5)
  game:notifyNeighbors(hx, hy, hz)
end

-- Kierunek tłoka przy stawianiu: przodem do gracza (także w pionie)
function R.pistonFacing(lookX, lookY, lookZ)
  if lookY < -0.8 then return 1 end   -- patrzymy w dół: tłok w górę
  if lookY > 0.8 then return 0 end
  if math.abs(lookX) > math.abs(lookZ) then
    return lookX > 0 and 4 or 5
  end
  return lookZ > 0 and 2 or 3
end

return R
