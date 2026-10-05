-- core/blocklogic.lua
-- Zachowania bloków: gdzie można je postawić, co robią po kliknięciu,
-- reakcje na zmiany obok (pochodnia bez podpory odpada), losowe ticki
-- (rośnięcie, rozrastanie trawy, opadanie liści) i ticki planowane
-- (płynięcie wody i lawy, spadanie piasku).
-- Funkcje dostają obiekt gry (game), żeby mieć dostęp do świata i bytów.

local blocks = require("core.blocks")

local L = {}

local redstoneMod
local function redstone()
  if not redstoneMod then redstoneMod = require("core.redstone") end
  return redstoneMod
end

local defs = blocks.defs
local OPAQUE = blocks.OPAQUE
local SOLID = blocks.SOLID
local id = blocks.id

local AIR = 0
local STONE, GRASS, DIRT, COBBLE = 1, 2, 3, 4
local SAPLING, WATER, LAVA, SAND, GRAVEL = 6, 8, 10, 12, 13
local LOG, LEAVES = 17, 18
local TALL_GRASS, DEAD_BUSH = 31, 32
local DANDELION, ROSE, BROWN_MUSH, RED_MUSH = 37, 38, 39, 40
local TORCH, FIRE = 50, 51
local WHEAT, FARMLAND = 59, 60
local DOOR, LADDER, BED = 64, 65, 26
local SNOW_LAYER, ICE, SNOW = 78, 79, 80
local CACTUS, SUGAR_CANE = 81, 83
local OBSIDIAN = 49
local TNT = 46

L.NEIGHBORS = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }
local NEIGHBORS = L.NEIGHBORS
local HORIZONTAL = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

-- Czy blok w tym miejscu jest pełnym, litym podparciem
local function solidAt(world, x, y, z)
  return OPAQUE[world:getBlock(x, y, z)] == 1
end
L.solidAt = solidAt

local function isLiquid(id_) local d = defs[id_]; return d and d.liquid end

-- ---------------------------------------------------------------------------
-- Gdzie można postawić blok
-- ---------------------------------------------------------------------------
local function plantSoil(below)
  return below == GRASS or below == DIRT or below == FARMLAND
end

local PLACE_RULES = {
  [SAPLING] = function(w, x, y, z) return plantSoil(w:getBlock(x, y - 1, z)) end,
  [TALL_GRASS] = function(w, x, y, z) return plantSoil(w:getBlock(x, y - 1, z)) end,
  [DANDELION] = function(w, x, y, z) return plantSoil(w:getBlock(x, y - 1, z)) end,
  [ROSE] = function(w, x, y, z) return plantSoil(w:getBlock(x, y - 1, z)) end,
  [DEAD_BUSH] = function(w, x, y, z) return w:getBlock(x, y - 1, z) == SAND end,
  [BROWN_MUSH] = function(w, x, y, z)
    return solidAt(w, x, y - 1, z) and w:getSkyLight(x, y, z) < 13
  end,
  [RED_MUSH] = function(w, x, y, z)
    return solidAt(w, x, y - 1, z) and w:getSkyLight(x, y, z) < 13
  end,
  [WHEAT] = function(w, x, y, z) return w:getBlock(x, y - 1, z) == FARMLAND end,
  [CACTUS] = function(w, x, y, z)
    local below = w:getBlock(x, y - 1, z)
    if below ~= SAND and below ~= CACTUS then return false end
    for _, d in ipairs(HORIZONTAL) do
      if SOLID[w:getBlock(x + d[1], y, z + d[2])] == 1 then return false end
    end
    return true
  end,
  [SUGAR_CANE] = function(w, x, y, z)
    local below = w:getBlock(x, y - 1, z)
    if below == SUGAR_CANE then return true end
    if below ~= GRASS and below ~= DIRT and below ~= SAND then return false end
    for _, d in ipairs(HORIZONTAL) do
      if w:getBlock(x + d[1], y - 1, z + d[2]) == WATER then return true end
    end
    return false
  end,
  [SNOW_LAYER] = function(w, x, y, z) return solidAt(w, x, y - 1, z) end,
  [55] = function(w, x, y, z) return solidAt(w, x, y - 1, z) end,
  [66] = function(w, x, y, z) return solidAt(w, x, y - 1, z) end,
  [27] = function(w, x, y, z) return solidAt(w, x, y - 1, z) end,
  [28] = function(w, x, y, z) return solidAt(w, x, y - 1, z) end,
  [70] = function(w, x, y, z) return solidAt(w, x, y - 1, z) end,
  [93] = function(w, x, y, z) return solidAt(w, x, y - 1, z) end,
  [94] = function(w, x, y, z) return solidAt(w, x, y - 1, z) end,
  [77] = function(w, x, y, z, meta)
    local v = blocks.SUPPORT[(meta or 0) % 8]
    if not v or (meta or 0) % 8 == 0 then return false end
    return solidAt(w, x + v[1], y + v[2], z + v[3])
  end,
  [69] = function(w, x, y, z, meta)
    local v = blocks.SUPPORT[(meta or 0) % 8]
    if not v then return false end
    return solidAt(w, x + v[1], y + v[2], z + v[3])
  end,
  [TORCH] = function(w, x, y, z, meta)
    if meta == 0 then return solidAt(w, x, y - 1, z) end
    if meta == 1 then return solidAt(w, x - 1, y, z) end
    if meta == 2 then return solidAt(w, x + 1, y, z) end
    if meta == 3 then return solidAt(w, x, y, z - 1) end
    if meta == 4 then return solidAt(w, x, y, z + 1) end
    return false
  end,
  [75] = function(w, x, y, z, meta) return L.PLACE_RULES[TORCH](w, x, y, z, meta) end,
  [76] = function(w, x, y, z, meta) return L.PLACE_RULES[TORCH](w, x, y, z, meta) end,
  [LADDER] = function(w, x, y, z, meta)
    if meta == 1 then return solidAt(w, x - 1, y, z) end
    if meta == 2 then return solidAt(w, x + 1, y, z) end
    if meta == 3 then return solidAt(w, x, y, z - 1) end
    if meta == 4 then return solidAt(w, x, y, z + 1) end
    return false
  end,
}
L.PLACE_RULES = PLACE_RULES

function L.canStay(world, blockId, x, y, z, meta)
  local rule = PLACE_RULES[blockId]
  if rule then return rule(world, x, y, z, meta) end
  return true
end

-- Kierunek "przodu" (0=S,1=W,2=N,3=E) zwrócony do gracza
function L.facingTowardPlayer(lookX, lookZ)
  if math.abs(lookX) > math.abs(lookZ) then
    return lookX > 0 and 1 or 3
  end
  return lookZ > 0 and 2 or 0
end

-- Wektor (dx, dz) kierunku patrzenia gracza w poziomie, jako 0..3 (S,W,N,E)
local DIR_VEC = { [0] = { 0, 1 }, [1] = { -1, 0 }, [2] = { 0, -1 }, [3] = { 1, 0 } }
L.DIR_VEC = DIR_VEC
local function lookDir(lookX, lookZ)
  if math.abs(lookX) > math.abs(lookZ) then return lookX > 0 and 3 or 1 end
  return lookZ > 0 and 0 or 2
end
L.lookDir = lookDir

-- Meta pochodni/drabiny z klikniętej ściany (strona podpory)
local FACE_TO_SUPPORT = { [1] = 1, [2] = 2, [5] = 3, [6] = 4, [3] = 0 }

-- Oblicza meta stawianego bloku. Zwraca meta albo nil (nie można postawić).
-- hit: wynik raycastu (face), look: wektor patrzenia gracza
function L.placementMeta(world, blockId, x, y, z, hit, lookX, lookZ, itemDamage, lookY)
  local def = defs[blockId]
  if blockId == TORCH or blockId == 76 or blockId == 75 or blockId == 69 then
    local meta = FACE_TO_SUPPORT[hit.face]
    if meta == nil then return nil end
    local rule = PLACE_RULES[blockId]
    if not rule(world, x, y, z, meta) then
      -- spróbuj innych podpór
      for m = 0, 4 do
        if rule(world, x, y, z, m) then return m end
      end
      return nil
    end
    return meta
  end
  if blockId == 77 then
    local meta = FACE_TO_SUPPORT[hit.face]
    if not meta or meta == 0 then return nil end
    return meta
  end
  if blockId == 93 then
    return lookDir(lookX, lookZ)
  end
  if blockId == 33 or blockId == 29 then
    return redstone().pistonFacing(lookX, lookY or 0, lookZ)
  end
  if blockId == 85 then
    return L.fenceMeta(world, x, y, z)
  end
  if blockId == LADDER then
    local meta = FACE_TO_SUPPORT[hit.face]
    if not meta or meta == 0 then return nil end
    if not PLACE_RULES[LADDER](world, x, y, z, meta) then return nil end
    return meta
  end
  if def and (def.name == "furnace" or def.name == "chest" or def.name == "pumpkin"
    or def.name == "jack_o_lantern") then
    return L.facingTowardPlayer(lookX, lookZ)
  end
  if blockId == LEAVES then
    return (itemDamage or 0) % 4 + 4 -- bit 4: postawione przez gracza
  end
  if def and def.metaMask and def.metaMask > 0 then
    return (itemDamage or 0) % (def.metaMask + 1)
  end
  return 0
end

-- Połączenia płotka z sąsiadami (płotki i pełne bloki)
function L.fenceMeta(world, x, y, z)
  local meta = 0
  local function conn(nx, nz)
    local id = world:getBlock(nx, y, nz)
    return id == 85 or OPAQUE[id] == 1
  end
  if conn(x + 1, z) then meta = meta + 1 end
  if conn(x - 1, z) then meta = meta + 2 end
  if conn(x, z + 1) then meta = meta + 4 end
  if conn(x, z - 1) then meta = meta + 8 end
  return meta
end

-- ---------------------------------------------------------------------------
-- Bloki wielokomórkowe: drzwi (2 wysokie) i łóżko (2 długie)
-- ---------------------------------------------------------------------------
-- Zwraca listę {x, y, z, id, meta} do postawienia albo nil
function L.multiPlacement(world, blockId, x, y, z, lookX, lookZ)
  if blockId == DOOR then
    if not solidAt(world, x, y - 1, z) then return nil end
    local above = world:getBlock(x, y + 1, z)
    if above ~= AIR and not (defs[above] and defs[above].replaceable) then return nil end
    -- panel po dalszej stronie bloku względem gracza
    local dir = lookDir(lookX, lookZ)
    local facing = ({ [2] = 0, [3] = 1, [0] = 2, [1] = 3 })[dir]
    return { { x, y, z, DOOR, facing }, { x, y + 1, z, DOOR, facing + 8 } }
  end
  if blockId == BED then
    local dir = lookDir(lookX, lookZ)
    local v = DIR_VEC[dir]
    local hx, hz = x + v[1], z + v[2]
    local headBlock = world:getBlock(hx, y, hz)
    if headBlock ~= AIR and not (defs[headBlock] and defs[headBlock].replaceable) then
      return nil
    end
    if not solidAt(world, x, y - 1, z) or not solidAt(world, hx, y - 1, hz) then return nil end
    return { { x, y, z, BED, dir }, { hx, y, hz, BED, dir + 8 } }
  end
  return nil
end

-- Druga połowa bloku wielokomórkowego (do usuwania obu naraz)
function L.otherHalf(world, x, y, z, blockId, meta)
  if (blockId == 33 or blockId == 29) and meta >= 8 then
    local v = blocks.FACING6[meta % 8]
    if world:getBlock(x + v[1], y + v[2], z + v[3]) == 34 then return x + v[1], y + v[2], z + v[3] end
    return nil
  end
  if blockId == 34 then
    local v = blocks.FACING6[meta % 8]
    return x - v[1], y - v[2], z - v[3]
  end
  if blockId == DOOR then
    if meta >= 8 then return x, y - 1, z end
    return x, y + 1, z
  end
  if blockId == BED then
    local v = DIR_VEC[meta % 4]
    if meta >= 8 then return x - v[1], y, z - v[2] end
    return x + v[1], y, z + v[2]
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Kliknięcie prawym przyciskiem na blok. Zwraca true, jeśli coś się stało.
-- ---------------------------------------------------------------------------
function L.onUse(game, x, y, z, blockId, meta)
  local world = game.world
  if blockId == 69 or blockId == 77 or blockId == 93 or blockId == 94 then
    return redstone().onUse(game, x, y, z, blockId, meta)
  end
  if blockId == DOOR then
    local lx, ly, lz = x, y, z
    local lowerMeta = meta
    if meta >= 8 then ly = y - 1; lowerMeta = world:getMeta(lx, ly, lz) end
    local open = math.floor(lowerMeta / 4) % 2 == 1
    local newMeta = (lowerMeta % 4) + (open and 0 or 4)
    world:setBlock(lx, ly, lz, DOOR, newMeta)
    if world:getBlock(lx, ly + 1, lz) == DOOR then
      world:setBlock(lx, ly + 1, lz, DOOR, newMeta + 8)
    end
    game:emit("sound", "door", x + 0.5, y + 0.5, z + 0.5)
    return true
  end
  local def = defs[blockId]
  if def and def.name == "crafting_table" then
    game:emit("open", "crafting", x, y, z)
    return true
  end
  if def and def.tileEntity == "chest" then
    if solidAt(world, x, y + 1, z) then return true end -- zablokowana skrzynia
    game:emit("open", "chest", x, y, z)
    return true
  end
  if def and def.tileEntity == "furnace" then
    game:emit("open", "furnace", x, y, z)
    return true
  end
  if blockId == BED then
    game:trySleep(x, y, z, meta)
    return true
  end
  if blockId == TNT then
    return false
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Zmiana sąsiada: sprawdzanie podpory, start płynięcia, spadanie
-- ---------------------------------------------------------------------------
function L.onNeighborChanged(game, x, y, z)
  local world = game.world
  local blockId, meta = world:getBlockAndMeta(x, y, z)
  if blockId == AIR then return end
  local def = defs[blockId]
  if not def then return end

  if def.liquid then
    game:scheduleTick(x, y, z, def.liquid == "water" and 5 or 30)
    return
  end
  if def.gravity then
    game:scheduleTick(x, y, z, 2)
    return
  end
  if blockId == DOOR then
    local ox, oy, oz = L.otherHalf(world, x, y, z, blockId, meta)
    if world:getBlock(ox, oy, oz) ~= DOOR or (meta < 8 and not solidAt(world, x, y - 1, z)) then
      game:breakBlock(x, y, z, false)
      return
    end
    redstone().onNeighborChanged(game, x, y, z, blockId, meta)
    return
  end
  if blockId == BED then
    local ox, oy, oz = L.otherHalf(world, x, y, z, blockId, meta)
    if world:getBlock(ox, oy, oz) ~= BED then game:breakBlock(x, y, z, false) end
    return
  end
  if blockId == FIRE then
    if not solidAt(world, x, y - 1, z) and not L.nearFlammable(world, x, y, z) then
      world:setBlock(x, y, z, AIR, 0)
    end
    return
  end
  if blockId == 90 then
    require("core.portal").validate(game, x, y, z)
    return
  end
  if blockId == FARMLAND then
    if OPAQUE[world:getBlock(x, y + 1, z)] == 1 then world:setBlock(x, y, z, DIRT, 0) end
    return
  end
  if blockId == GRASS or blockId == DIRT then
    -- śnieg na wierzchu zmienia boki trawy
    if blockId == GRASS then
      local above = world:getBlock(x, y + 1, z)
      local snowy = (above == SNOW_LAYER or above == SNOW) and 1 or 0
      if meta ~= snowy then world:setBlock(x, y, z, GRASS, snowy) end
    end
    return
  end
  if PLACE_RULES[blockId] and not PLACE_RULES[blockId](world, x, y, z, meta) then
    game:breakBlock(x, y, z, false)
    return
  end
  if blockId == 85 then
    local m = L.fenceMeta(world, x, y, z)
    if m ~= meta then world:setBlock(x, y, z, 85, m) end
    return
  end
  if blockId == 34 then
    -- głowica bez tłoka znika
    local v = blocks.FACING6[meta % 8]
    local bid = world:getBlock(x - v[1], y - v[2], z - v[3])
    if bid ~= 33 and bid ~= 29 then world:setBlock(x, y, z, AIR, 0) end
    return
  end
  if def.redstone or blockId == TNT then
    redstone().onNeighborChanged(game, x, y, z, blockId, meta)
  end
end

function L.nearFlammable(world, x, y, z)
  for _, d in ipairs(NEIGHBORS) do
    local nd = defs[world:getBlock(x + d[1], y + d[2], z + d[3])]
    if nd and nd.flammable then return true end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Losowe ticki (wywoływane dla losowych bloków w załadowanych chunkach)
-- ---------------------------------------------------------------------------
local function hasLogNearby(world, x, y, z)
  -- liście żyją, jeśli w promieniu 4 (po liściach) jest pień
  local visited = {}
  local queue = { { x, y, z, 0 } }
  local head = 1
  while head <= #queue do
    local q = queue[head]
    head = head + 1
    for _, d in ipairs(NEIGHBORS) do
      local nx, ny, nz = q[1] + d[1], q[2] + d[2], q[3] + d[3]
      local k = (nx - x + 8) + (ny - y + 8) * 17 + (nz - z + 8) * 289
      if not visited[k] then
        visited[k] = true
        local b = world:getBlock(nx, ny, nz)
        if b == LOG then return true end
        if b == LEAVES and q[4] < 3 then queue[#queue + 1] = { nx, ny, nz, q[4] + 1 } end
      end
    end
  end
  return false
end

function L.randomTick(game, x, y, z, blockId, meta)
  local world = game.world
  local rng = game.rng

  if blockId == GRASS then
    local above = world:getBlock(x, y + 1, z)
    if blocks.OPACITY[above] >= 2 then
      world:setBlock(x, y, z, DIRT, 0)
      return
    end
    if world:getSkyLight(x, y + 1, z) >= 9 or world:getBlockLight(x, y + 1, z) >= 9 then
      for _ = 1, 4 do
        local tx = x + rng:int(-1, 1)
        local ty = y + rng:int(-3, 1)
        local tz = z + rng:int(-1, 1)
        if world:getBlock(tx, ty, tz) == DIRT and blocks.OPACITY[world:getBlock(tx, ty + 1, tz)] < 2
          and world:getSkyLight(tx, ty + 1, tz) >= 4 then
          world:setBlock(tx, ty, tz, GRASS, 0)
        end
      end
    end
    return
  end

  if blockId == LEAVES then
    if meta >= 4 then return end -- postawione przez gracza
    if not hasLogNearby(world, x, y, z) then
      game:breakBlock(x, y, z, false)
    end
    return
  end

  if blockId == WHEAT then
    if meta < 7 and (world:getSkyLight(x, y + 1, z) >= 9 or world:getBlockLight(x, y, z) >= 9) then
      local wet = world:getMeta(x, y - 1, z) > 0
      local chance = wet and 0.35 or 0.15
      if rng:chance(chance) then world:setBlock(x, y, z, WHEAT, meta + 1) end
    end
    return
  end

  if blockId == FARMLAND then
    local wet = L.waterNear(world, x, y, z, 4)
    if wet then
      if meta == 0 then world:setBlock(x, y, z, FARMLAND, 7) end
    elseif meta > 0 then
      world:setBlock(x, y, z, FARMLAND, meta - 1)
    elseif world:getBlock(x, y + 1, z) ~= WHEAT then
      world:setBlock(x, y, z, DIRT, 0)
    end
    return
  end

  if blockId == SAPLING then
    if world:getSkyLight(x, y + 1, z) >= 9 and rng:chance(1 / 7) then
      game:growTree(x, y, z, meta % 4)
    end
    return
  end

  if blockId == CACTUS or blockId == SUGAR_CANE then
    if world:getBlock(x, y + 1, z) == AIR then
      local h = 1
      while world:getBlock(x, y - h, z) == blockId do h = h + 1 end
      if h < 3 and rng:chance(1 / 4) then
        if L.canStay(world, blockId, x, y + 1, z) then
          world:setBlock(x, y + 1, z, blockId, 0)
        end
      end
    end
    return
  end

  if blockId == SNOW_LAYER or blockId == ICE then
    if world:getBlockLight(x, y, z) > 11 or world:getBlockLight(x, y + 1, z) > 11 then
      world:setBlock(x, y, z, blockId == ICE and WATER or AIR, 0)
    end
    return
  end

  if blockId == FIRE then
    -- ogień gaśnie albo rozprzestrzenia się na palne bloki
    if game.weather and game.weather.raining and world:getHeight(x, z) <= y then
      world:setBlock(x, y, z, AIR, 0)
      return
    end
    if rng:chance(0.3) then
      for _, d in ipairs(NEIGHBORS) do
        local nx, ny, nz = x + d[1], y + d[2], z + d[3]
        local nd = defs[world:getBlock(nx, ny, nz)]
        if nd and nd.flammable and rng:chance(0.25) then
          if nd.name == "tnt" then
            game:primeTnt(nx, ny, nz)
          else
            world:setBlock(nx, ny, nz, FIRE, 0)
          end
        end
      end
      local below = defs[world:getBlock(x, y - 1, z)]
      if not (below and below.eternalFire) and (not L.nearFlammable(world, x, y, z) or rng:chance(0.3)) then
        world:setBlock(x, y, z, AIR, 0)
      end
    end
    return
  end
end

function L.waterNear(world, x, y, z, r)
  for dx = -r, r do
    for dz = -r, r do
      for dy = 0, 1 do
        if world:getBlock(x + dx, y + dy, z + dz) == WATER then return true end
      end
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Planowane ticki: płynięcie cieczy i spadające bloki
-- Meta cieczy: 0 = źródło, 1..7 = odległość od źródła, 8 = spadająca
-- ---------------------------------------------------------------------------
local function liquidLevel(world, x, y, z, liquidId)
  local b, m = world:getBlockAndMeta(x, y, z)
  if b ~= liquidId then return -1 end
  if m >= 8 then return 0 end
  return m
end

local function canFlowInto(world, x, y, z, liquidId)
  local b = world:getBlock(x, y, z)
  if b == AIR then return true end
  if b == liquidId then return false end
  local d = defs[b]
  if not d then return false end
  if d.liquid then return false end
  if d.replaceable then return true end
  return d.solid == false and d.shape ~= "box" -- rośliny są zmywane
end

-- Woda + lawa: kamień, bruk albo obsydian
local function reactLava(game, x, y, z, liquidId)
  local world = game.world
  if liquidId ~= LAVA then return false end
  for _, d in ipairs(NEIGHBORS) do
    if d[2] ~= -1 and world:getBlock(x + d[1], y + d[2], z + d[3]) == WATER then
      local meta = world:getMeta(x, y, z)
      world:setBlock(x, y, z, meta == 0 and OBSIDIAN or COBBLE, 0)
      game:emit("sound", "fizz", x + 0.5, y + 0.5, z + 0.5)
      return true
    end
  end
  return false
end

function L.liquidTick(game, x, y, z, liquidId)
  local world = game.world
  local meta = world:getMeta(x, y, z)
  if world:getBlock(x, y, z) ~= liquidId then return end
  if reactLava(game, x, y, z, liquidId) then return end
  local isWater = liquidId == WATER
  local decay = isWater and 1 or 2
  local delay = isWater and 5 or 30

  -- 1) Płynąca ciecz: sprawdź, czy wciąż ma zasilanie
  if meta ~= 0 then
    local best = 99
    local sources = 0
    for _, d in ipairs(HORIZONTAL) do
      local l = liquidLevel(world, x + d[1], y, z + d[2], liquidId)
      if l >= 0 then
        local bm = world:getMeta(x + d[1], y, z + d[2])
        if bm == 0 then sources = sources + 1 end
        if l < best then best = l end
      end
    end
    local newMeta
    if liquidLevel(world, x, y + 1, z, liquidId) >= 0 then
      newMeta = 8 -- spada z góry
    else
      newMeta = best + decay
      if newMeta > 7 then newMeta = -1 end
    end
    -- nieskończone źródło wody: dwa źródła obok i grunt pod spodem
    if isWater and sources >= 2 then
      local below = world:getBlock(x, y - 1, z)
      if SOLID[below] == 1 or (below == WATER and world:getMeta(x, y - 1, z) == 0) then
        newMeta = 0
      end
    end
    if newMeta ~= meta then
      if newMeta < 0 then
        game:setBlock(x, y, z, AIR, 0)
        return
      end
      game:setBlock(x, y, z, liquidId, newMeta)
      meta = newMeta
    end
  end

  -- 2) Spływanie w dół
  if y > 0 and canFlowInto(world, x, y - 1, z, liquidId) then
    if liquidId == LAVA and world:getBlock(x, y - 1, z) == WATER then return end
    game:destroyByLiquid(x, y - 1, z)
    game:setBlock(x, y - 1, z, liquidId, 8)
    game:scheduleTick(x, y - 1, z, delay)
    return
  end
  local below = world:getBlock(x, y - 1, z)
  if below == liquidId and meta ~= 0 then return end -- nad cieczą nie rozlewa się

  -- 3) Rozlewanie na boki
  local level = meta >= 8 and 0 or meta
  local spread = level + decay
  if spread > 7 then return end
  for _, d in ipairs(HORIZONTAL) do
    local nx, nz = x + d[1], z + d[2]
    if canFlowInto(world, nx, y, nz, liquidId) then
      game:destroyByLiquid(nx, y, nz)
      game:setBlock(nx, y, nz, liquidId, spread)
      game:scheduleTick(nx, y, nz, delay)
    elseif world:getBlock(nx, y, nz) == liquidId then
      local nm = world:getMeta(nx, y, nz)
      if nm ~= 0 and nm < 8 and nm > spread then
        game:setBlock(nx, y, nz, liquidId, spread)
        game:scheduleTick(nx, y, nz, delay)
      end
    elseif liquidId == WATER and world:getBlock(nx, y, nz) == LAVA then
      local lm = world:getMeta(nx, y, nz)
      game:setBlock(nx, y, nz, lm == 0 and OBSIDIAN or COBBLE, 0)
    end
  end
end

function L.scheduledTick(game, x, y, z)
  local world = game.world
  local blockId, meta = world:getBlockAndMeta(x, y, z)
  local def = defs[blockId]
  if not def then return end
  if def.redstone then
    redstone().scheduledTick(game, x, y, z, blockId, meta)
    return
  end
  if def.liquid then
    L.liquidTick(game, x, y, z, blockId)
  elseif def.gravity then
    local below = world:getBlock(x, y - 1, z)
    local bd = defs[below]
    if y > 0 and (below == AIR or (bd and (bd.liquid or bd.replaceable))) then
      local meta = world:getMeta(x, y, z)
      world:setBlock(x, y, z, AIR, 0)
      game:spawnFallingBlock(x, y, z, blockId, meta)
    end
  end
end

return L
