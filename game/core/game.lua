-- core/game.lua
-- Sesja gry: świat + gracz + ekwipunek + byty + czas.
-- Cała logika liczona w tickach (20/s) i całkowicie bez grafiki, więc da się
-- ją testować przez lua.exe. Stan play.lua tylko przekazuje wejście
-- (game.input) i rysuje to, co tu się dzieje. Zdarzenia dla grafiki/dźwięku
-- (cząsteczki, dźwięki, otwarcie okna) trafiają do listy game.events.

local World = require("core.world")
local Player = require("core.player")
local Inventory = require("core.inventory")
local blocks = require("core.blocks")
local items = require("core.items")
local raycast = require("core.raycast")
local physics = require("core.physics")
local blocklogic = require("core.blocklogic")
local entities = require("core.entities")
local Rng = require("core.rng")
local config = require("core.config")
local worldgen = require("core.worldgen")
local lighting = require("core.lighting")
local survival = require("core.survival")
local mobs = require("core.mobs")
local save = require("core.save")
local potions = require("core.potions")
local maps = require("core.maps")

local M = {}

local Game = {}
Game.__index = Game

local defs = blocks.defs
local floor = math.floor

M.REACH_SURVIVAL = 4.5
M.REACH_CREATIVE = 5
M.DAY_LENGTH = 24000

-- opts: seed, gameMode, difficulty, generator, lighting, loader, onUnload,
--       spawn {x,y,z} (opcjonalnie)
function M.new(opts)
  local self = setmetatable({}, Game)
  opts = opts or {}
  self.seed = opts.seed or 0
  self.name = opts.name or "Swiat"
  self.difficulty = opts.difficulty or 2 -- 0 spokojny, 1 łatwy, 2 normalny, 3 trudny
  self.hardcore = opts.hardcore or false
  self.opts = opts
  self.saveFolder = opts.saveFolder
  self.remote = opts.remote or false -- gość w grze sieciowej (świat u gospodarza)
  self.pendingAnimalChunks = {}
  self.animalRng = Rng.new(Rng.hash(self.seed, 555))
  self.dimension = "overworld"
  self.worlds = {}
  self.entitiesByDim = {}
  self.world = self:makeWorld("overworld")
  self.worlds.overworld = self.world
  self.world:addListener(self)
  self.rng = Rng.new(Rng.hash(self.seed, 99))
  self.player = Player.new(0.5, 100, 0.5)
  self.player.gameMode = opts.gameMode or "survival"
  self.spawnX, self.spawnY, self.spawnZ = nil, nil, nil
  self.inventory = Inventory.new(36)
  self.armor = Inventory.new(4)
  self.selected = 1
  self.entities = entities.new(self)
  self.entitiesByDim.overworld = self.entities
  self.time = 0              -- ticki od startu świata
  self.dayTime = 1000        -- 0..23999 (0 = wschód, 6000 = południe)
  self.events = {}
  self.input = {
    forward = 0, strafe = 0, jump = false, sneak = false, sprint = false,
    attack = false, use = false, attackPressed = false, usePressed = false,
  }
  self.mining = nil          -- { x, y, z, progress, id }
  self.breakCooldown = 0
  self.useCooldown = 0
  self.scheduled = {}        -- tick -> lista pozycji
  self.scheduledSet = {}
  self.weather = { raining = false, thunder = false, timer = 12000, strength = 0 }
  self.stats = {}
  self.dead = false
  self.renderDistance = config.RENDER_DISTANCE
  -- survival (zdrowie, głód, XP) i moby
  survival.init(self)
  self.survival = survival
  self.mobs = mobs
  mobs.init(self)
  maps.init(self)
  self.worldSpawnX, self.worldSpawnY, self.worldSpawnZ = 0.5, 80, 0.5
  return self
end

-- ---------------------------------------------------------------------------
-- Wymiary: zwykły świat i Nether (osobne chunki, byty i pliki zapisu)
-- ---------------------------------------------------------------------------
function Game:makeWorld(dim)
  local opts = self.opts
  local generator
  if dim == "nether" then
    local nethergen = require("core.nethergen")
    local gen = nethergen.new(self.seed)
    generator = function(chunk) gen:generate(chunk) end
  elseif dim == "end" then
    local gen = require("core.endgen").new(self.seed)
    self.endGen = gen
    generator = function(chunk) gen:generate(chunk) end
  else
    generator = opts.generator
    if opts.remote then
      -- gość w grze sieciowej: teren przychodzi od gospodarza, generator tylko do biomów
      local gen = worldgen.new(self.seed)
      self.gen = gen
      self.overworldBiome = function(x, z) return (gen:biome(x, z)) end
      self.biomeAt = self.overworldBiome
      generator = false
    elseif generator == nil then
      local gen = worldgen.new(self.seed)
      self.gen = gen
      self.overworldBiome = function(x, z) return (gen:biome(x, z)) end
      self.biomeAt = self.overworldBiome
      generator = function(chunk) gen:generate(chunk) end
    end
  end
  local loader, onUnload = opts.loader, opts.onUnload
  if self.saveFolder then
    local folder = self.saveFolder
    loader = function(cx, cz) return save.loadChunk(folder, cx, cz, dim) end
    onUnload = function(chunk)
      local list = save.collectEntities(self, chunk, true)
      if #list > 0 then chunk.savedEntities = list end
      if chunk.modified or #list > 0 then save.saveChunk(folder, chunk, dim) end
      chunk.savedEntities = nil
    end
  end
  local onCreate = function(chunk, fromDisk)
    if opts.remote then return end
    if fromDisk then
      save.restoreEntities(self, chunk)
    elseif dim == "overworld" and self.gen and self.animalRng:chance(0.12) then
      self.pendingAnimalChunks[#self.pendingAnimalChunks + 1] = { chunk.cx, chunk.cz }
    end
  end
  local light = opts.lighting
  if light == nil then light = lighting end
  local w = World.new({
    seed = self.seed, generator = generator or nil, lighting = light or nil,
    loader = loader, onUnload = onUnload, onCreate = onCreate,
  })
  w.dimension = dim
  if dim == "nether" or dim == "end" then w.noSky = true end
  return w
end

-- Ustawia wymiar bez teleportu (np. po wczytaniu zapisu)
function Game:setDimension(dim)
  if dim == self.dimension then return end
  self.entitiesByDim[self.dimension] = self.entities
  self.dimension = dim
  self.world = self.worlds[dim]
  if not self.world then
    self.world = self:makeWorld(dim)
    self.worlds[dim] = self.world
    self.world:addListener(self)
  end
  self.entities = self.entitiesByDim[dim] or entities.new(self)
  self.entitiesByDim[dim] = self.entities
  if dim == "nether" then
    local nb = require("core.nethergen").BIOME
    self.biomeAt = function() return nb end
  elseif dim == "end" then
    local eb = require("core.endgen").BIOME
    self.biomeAt = function() return eb end
  else
    self.biomeAt = self.overworldBiome
  end
end

-- Przejście do innego wymiaru: zapis i zwolnienie starego, przygotowanie nowego
function Game:changeDimension(dim, x, y, z)
  local old = self.world
  -- zapis stanu i zwolnienie wszystkich chunków poprzedniego wymiaru
  old:unloadFar(0, 0, -1)
  for _, e in ipairs(self.entities.list) do e.dead = true end
  self.entities.list = {}
  self.endDragon, self.endCrystals = nil, nil
  self.scheduled, self.scheduledSet = {}, {}
  self.mining = nil
  self:setDimension(dim)
  local p = self.player
  p.x, p.y, p.z = x, y, z
  p.prevX, p.prevY, p.prevZ = x, y, z
  self.world:updateLoading(floor(x / 16), floor(z / 16), 1, 1000)
  self:emit("dimension", dim)
end

-- ---------------------------------------------------------------------------
-- Zdarzenia dla warstwy grafiki/dźwięku
-- ---------------------------------------------------------------------------
function Game:emit(kind, a, b, c, d, e)
  self.events[#self.events + 1] = { kind, a, b, c, d, e }
end

function Game:popEvents()
  local ev = self.events
  self.events = {}
  return ev
end

-- Słuchacz zmian bloków w świecie (rejestrowany w World)
function Game:onBlockChanged(world, x, y, z, oldId, newId)
  -- nic: sąsiadów powiadamiamy jawnie w notifyNeighbors
end

-- ---------------------------------------------------------------------------
-- Planowane aktualizacje bloków
-- ---------------------------------------------------------------------------
local function posKey(x, y, z)
  return ((x + 1048576) * 256 + y) * 2097152 + (z + 1048576)
end

function Game:scheduleTick(x, y, z, delay)
  local k = posKey(x, y, z)
  if self.scheduledSet[k] then return end
  local due = self.time + (delay or 1)
  local list = self.scheduled[due]
  if not list then list = {}; self.scheduled[due] = list end
  list[#list + 1] = { x, y, z }
  self.scheduledSet[k] = true
end

function Game:processScheduled()
  local list = self.scheduled[self.time]
  if not list then return end
  self.scheduled[self.time] = nil
  local n = 0
  for _, p in ipairs(list) do
    self.scheduledSet[posKey(p[1], p[2], p[3])] = nil
    if self.world:isLoadedAt(p[1], p[3]) then
      blocklogic.scheduledTick(self, p[1], p[2], p[3])
      n = n + 1
    end
  end
end

-- Powiadamia 6 sąsiadów (i sam blok) o zmianie
function Game:notifyNeighbors(x, y, z)
  blocklogic.onNeighborChanged(self, x, y, z)
  for _, d in ipairs(blocklogic.NEIGHBORS) do
    blocklogic.onNeighborChanged(self, x + d[1], y + d[2], z + d[3])
  end
end

-- Ustawia blok i powiadamia sąsiadów
function Game:setBlock(x, y, z, id, meta)
  if self.world:setBlock(x, y, z, id, meta or 0) then
    self:notifyNeighbors(x, y, z)
    return true
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Przedmioty
-- ---------------------------------------------------------------------------
function Game:heldStack()
  return self.inventory.slots[self.selected]
end

-- Dodaje do ekwipunku (hotbar najpierw). Zwraca liczbę, która się nie zmieściła.
function Game:addToInventory(stack)
  local copy = { id = stack.id, count = stack.count, damage = stack.damage or 0, ench = stack.ench }
  -- serwer: przedmiot podnosi gość (podmieniony kontekst gracza)
  if self.remoteCtx then return self.remoteCtx.server:giveTo(self.remoteCtx, copy) end
  return self.inventory:add(copy)
end

-- Daje przedmiot graczowi albo wyrzuca go obok, gdy brak miejsca
function Game:giveItem(stack)
  local left = self:addToInventory(stack)
  if left > 0 then
    local p = self.player
    self:dropStack(p.x, p.y + 1.2, p.z, { id = stack.id, count = left, damage = stack.damage, ench = stack.ench })
  end
end

-- Wyrzuca stos w świecie z lekkim losowym rozrzutem
function Game:dropStack(x, y, z, stack)
  if self.suppressDrops then return nil end
  local rng = self.rng
  local e = entities.newItem(x, y, z, stack,
    (rng:next() - 0.5) * 0.2, 0.2, (rng:next() - 0.5) * 0.2)
  return self.entities:add(e)
end

-- Gracz wyrzuca przedmiot przed siebie (klawisz Q)
function Game:throwFromHand(all)
  local s = self:heldStack()
  if not s then return end
  local n = all and s.count or 1
  local p = self.player
  local lx, ly, lz = p:lookVector()
  local ex, ey, ez = p:eyePosition()
  local e = entities.newItem(ex, ey - 0.3, ez, { id = s.id, count = n, damage = s.damage, ench = s.ench },
    lx * 0.3, ly * 0.3 + 0.1, lz * 0.3)
  e.pickupDelay = 40
  self.entities:add(e)
  self.inventory:decrement(self.selected, n)
end

function Game:throwStack(stack)
  local p = self.player
  local lx, ly, lz = p:lookVector()
  local ex, ey, ez = p:eyePosition()
  local e = entities.newItem(ex, ey - 0.3, ez, stack, lx * 0.3, ly * 0.3 + 0.1, lz * 0.3)
  e.pickupDelay = 40
  self.entities:add(e)
end

function Game:spawnXp(x, y, z, value)
  if self.suppressDrops then return end
  for _, v in ipairs(entities.splitXp(value)) do
    self.entities:add(entities.newXp(x, y, z, v))
  end
end

function Game:addXp(n)
  survival.addXp(self, n)
end

function Game:explode(x, y, z, power, source)
  mobs.explode(self, x, y, z, power, source)
end

function Game:spawnFallingBlock(x, y, z, id, meta)
  self.entities:add(entities.newFalling(x, y, z, id, meta))
end

function Game:primeTnt(x, y, z, fuse)
  self.world:setBlock(x, y, z, 0, 0)
  self:notifyNeighbors(x, y, z)
  self.entities:add(entities.newTnt(x, y, z, fuse))
  self:emit("sound", "fuse", x + 0.5, y + 0.5, z + 0.5)
end

-- ---------------------------------------------------------------------------
-- Celowanie
-- ---------------------------------------------------------------------------
function Game:reach()
  return self.player.gameMode == "creative" and M.REACH_CREATIVE or M.REACH_SURVIVAL
end

function Game:target()
  local p = self.player
  local ex, ey, ez = p:eyePosition()
  local lx, ly, lz = p:lookVector()
  return raycast.cast(self.world, ex, ey, ez, lx, ly, lz, self:reach())
end

-- ---------------------------------------------------------------------------
-- Niszczenie bloków
-- ---------------------------------------------------------------------------
-- Usuwa blok, daje drop (jeśli byPlayer: zależnie od narzędzia)
function Game:breakBlock(x, y, z, byPlayer)
  local world = self.world
  local id, meta = world:getBlockAndMeta(x, y, z)
  if id == 0 then return false end
  local def = defs[id]
  local creative = self.player.gameMode == "creative"

  -- zawartość skrzyni/pieca wypada
  local tile = self:resolveTile(world:getTile(x, y, z))
  if tile and tile.inventory then
    for i = 1, tile.inventory.size do
      local s = tile.inventory.slots[i]
      if s then self:dropStack(x + 0.5, y + 0.5, z + 0.5, s) end
    end
  end

  -- druga połowa drzwi/łóżka znika razem
  local ox, oy, oz = blocklogic.otherHalf(world, x, y, z, id, meta)

  world:setBlock(x, y, z, 0, 0)
  self:emit("break", x, y, z, id, meta)

  if ox and world:getBlock(ox, oy, oz) == id then
    world:setBlock(ox, oy, oz, 0, 0)
    self:notifyNeighbors(ox, oy, oz)
  end

  -- drop
  local held = byPlayer and self:heldStack() or nil
  local drop = not creative
  if byPlayer and drop and not items.canHarvest(held, def) then drop = false end
  if drop then
    local list
    local heldDef = held and items.get(held.id)
    local enchant = require("core.enchant")
    local silk = enchant.level(held, "silk_touch") > 0
    if silk and def.silkDrop ~= false and not def.tileEntity and id ~= 26 and id ~= 64
      and id ~= 59 and def.shape ~= "liquid" then
      -- Jedwabny dotyk: sam blok (ruda, szkło, trawa, lód...)
      local dmg = 0
      if def.metaMask and def.metaMask > 0 then dmg = meta % (def.metaMask + 1) end
      local bid = id
      if id == 74 then bid = 73 end -- świecąca ruda redstone
      list = { { id = bid, count = 1, damage = dmg } }
    elseif id == 18 and heldDef and heldDef.toolType == "shears" then
      list = { { id = 18, count = 1, damage = meta % 4 } }
    elseif id == 31 and heldDef and heldDef.toolType == "shears" then
      list = { { id = 31, count = 1, damage = 0 } }
    elseif def.drops then
      list = def.drops(meta, self.rng)
    else
      local dmg = 0
      if def.metaMask and def.metaMask > 0 then dmg = meta % (def.metaMask + 1) end
      list = { { id = id, count = 1, damage = dmg } }
    end
    -- Szczęście: więcej surowców z rud (węgiel, diament, lapis, redstone)
    if not silk and def.xp and enchant.level(held, "fortune") > 0 then
      for _, s in ipairs(list or {}) do s.count = enchant.fortuneCount(held, s.count, self.rng) end
    end
    for _, s in ipairs(list or {}) do
      if s.count > 0 then self:dropStack(x + 0.5, y + 0.3, z + 0.5, s) end
    end
    if byPlayer and def.xp and not silk then
      local v = self.rng:int(def.xp[1], def.xp[2])
      if v > 0 then self:spawnXp(x + 0.5, y + 0.5, z + 0.5, v) end
    end
  end

  -- lód zamienia się w wodę
  if id == 79 and not creative and world:getBlock(x, y - 1, z) ~= 0 then
    world:setBlock(x, y, z, 8, 0)
    self:scheduleTick(x, y, z, 5)
  end

  self:notifyNeighbors(x, y, z)
  if def.redstone then require("core.redstone").notifyAround(self, x, y, z) end
  return true
end

-- Ciecz zmywa rośliny, pochodnie itp.
function Game:destroyByLiquid(x, y, z)
  local id = self.world:getBlock(x, y, z)
  if id ~= 0 and not (defs[id] and defs[id].liquid) then
    self:breakBlock(x, y, z, false)
  end
end

-- ---------------------------------------------------------------------------
-- Stawianie bloków
-- ---------------------------------------------------------------------------
-- Czy AABB bloku nachodzi na gracza lub moba
function Game:blockedByEntity(x, y, z, blockId, meta)
  local def = defs[blockId]
  if not def or not def.solid then return false end
  local x0, y0, z0, x1, y1, z1 = blocks.bounds(def, meta)
  x0, y0, z0, x1, y1, z1 = x + x0, y + y0, z + z0, x + x1, y + y1, z + z1
  local function hits(e)
    local hw = e.width / 2
    return e.x + hw > x0 and e.x - hw < x1 and e.y + e.height > y0 and e.y < y1
      and e.z + hw > z0 and e.z - hw < z1
  end
  if hits(self.player) then return true end
  for _, e in ipairs(self.entities.list) do
    if e.isMob and not e.dead and hits(e) then return true end
  end
  return false
end

-- Próbuje postawić blok przedmiotem z ręki. Zwraca true przy sukcesie.
function Game:placeFromHand(hit)
  local stack = self:heldStack()
  if not stack then return false end
  local itemDef = items.get(stack.id)
  local blockId = stack.id < 256 and stack.id or (itemDef and (itemDef.placeBlock or itemDef.plant))
  if not blockId then return false end
  local bdef = defs[blockId]
  if not bdef then return false end
  local world = self.world

  -- miejsce: sam trafiony blok, jeśli da się go zastąpić (trawa, śnieg)
  local x, y, z = hit.x + hit.nx, hit.y + hit.ny, hit.z + hit.nz
  local hitDef = defs[hit.id]
  if hitDef and hitDef.replaceable and hit.id ~= blockId then
    x, y, z = hit.x, hit.y, hit.z
  end
  if y < 0 or y >= 128 then return false end
  local cur = world:getBlock(x, y, z)
  local curDef = defs[cur]
  if cur ~= 0 and not (curDef and curDef.replaceable) then return false end
  if not world:isLoadedAt(x, z) then return false end

  local p = self.player
  local lx, ly, lz = p:lookVector()

  -- bloki wielokomórkowe
  local multi = blocklogic.multiPlacement(world, blockId, x, y, z, lx, lz)
  if blockId == 64 or blockId == 26 then
    if not multi then return false end
    for _, b in ipairs(multi) do
      if self:blockedByEntity(b[1], b[2], b[3], b[4], b[5]) then return false end
    end
    for _, b in ipairs(multi) do world:setBlock(b[1], b[2], b[3], b[4], b[5]) end
    for _, b in ipairs(multi) do self:notifyNeighbors(b[1], b[2], b[3]) end
    self:consumeHeld(1)
    self:emit("place", x, y, z, blockId)
    return true
  end

  local meta = blocklogic.placementMeta(world, blockId, x, y, z, hit, lx, lz, stack.damage, ly)
  if meta == nil then return false end
  if not blocklogic.canStay(world, blockId, x, y, z, meta) then return false end
  if self:blockedByEntity(x, y, z, blockId, meta) then return false end

  world:setBlock(x, y, z, blockId, meta)
  if bdef.tileEntity then self:createTile(x, y, z, bdef.tileEntity) end
  if bdef.rail then
    require("core.rails").onPlaced(self, x, y, z, math.abs(lx) > math.abs(lz) and "x" or "z")
  end
  self:notifyNeighbors(x, y, z)
  if bdef.redstone then require("core.redstone").notifyAround(self, x, y, z) end
  if bdef.liquid then self:scheduleTick(x, y, z, 5) end
  if bdef.gravity then self:scheduleTick(x, y, z, 2) end
  self:consumeHeld(1)
  self:emit("place", x, y, z, blockId)
  return true
end

-- Zużywa n sztuk z ręki (nie w trybie kreatywnym)
function Game:consumeHeld(n)
  if self.player.gameMode == "creative" then return end
  self.inventory:decrement(self.selected, n)
end

-- Zużywa wytrzymałość narzędzia w ręku
function Game:damageHeld(amount)
  if self.player.gameMode == "creative" then return end
  local s = self:heldStack()
  if not s then return end
  local d = items.get(s.id)
  if d and d.maxDamage then
    if self.inventory:damageItem(self.selected, amount) then
      self:emit("sound", "break_tool", self.player.x, self.player.y + 1, self.player.z)
    end
  end
end

-- Dane dodatkowe bloku (skrzynia 27 slotów, piec 3 sloty)
function Game:createTile(x, y, z, kind)
  local tile
  if kind == "chest" then
    tile = { kind = "chest", inventory = Inventory.new(27) }
  elseif kind == "furnace" then
    tile = { kind = "furnace", inventory = Inventory.new(3), burn = 0, burnMax = 0, cook = 0,
      xp = 0 }
  elseif kind == "brewing" then
    tile = { kind = "brewing", inventory = Inventory.new(4), brew = 0 }
  end
  if tile then self.world:setTile(x, y, z, tile) end
  return tile
end

-- Skrzynie z lochów mają zawartość zapisaną jako lista - zamieniamy na ekwipunek
function Game:resolveTile(tile)
  if tile and tile.pendingSlots then
    tile.inventory = Inventory.new(27)
    for i, st in pairs(tile.pendingSlots) do tile.inventory.slots[i] = st end
    tile.pendingSlots = nil
  end
  return tile
end

function Game:getOrCreateTile(x, y, z)
  local tile = self.world:getTile(x, y, z)
  if tile then return self:resolveTile(tile) end
  local def = defs[self.world:getBlock(x, y, z)]
  if def and def.tileEntity then return self:createTile(x, y, z, def.tileEntity) end
  return nil
end

-- ---------------------------------------------------------------------------
-- Używanie przedmiotów (prawy przycisk)
-- ---------------------------------------------------------------------------
function Game:useItem(hit)
  local stack = self:heldStack()
  local p = self.player
  local world = self.world

  -- 1) kliknięcie bloku z akcją (drzwi, stół, skrzynia...) - chyba że kucamy
  if hit and not p.sneaking then
    if blocklogic.onUse(self, hit.x, hit.y, hit.z, hit.id, hit.meta) then return true end
  end
  if not stack then return false end
  local d = items.get(stack.id)
  if not d then return false end

  -- 2) jedzenie (zaczyna się trzymaniem przycisku - obsługuje survival)
  if d.food then
    return self.survival.startEating(self)
  end

  -- 3) przedmioty specjalne
  if d.use == "bucket" then return self:useBucket(stack, d) end
  if d.use == "milk" then
    self.survival.clearEffects(self)
    if p.gameMode ~= "creative" then self.inventory:set(self.selected, items.newStack(325)) end
    return true
  end
  if d.use == "bow" then return self.survival.startBow(self) end
  if d.use == "vehicle" then
    local vehicles = require("core.vehicles")
    local vh = stack.id == 333 and vehicles.waterHit(self) or hit
    return vehicles.placeFromItem(self, vh, stack.id)
  end
  if d.toolType == "sword" then return self.survival.startBlocking(self) end
  if d.use == "potion" then
    local _, _, splash = potions.decode(stack.damage)
    if splash then
      potions.throw(self, stack.damage)
      self:consumeHeld(1)
      return true
    end
    return self.survival.startDrinking(self)
  end
  if d.use == "bottle" then return self:fillBottle() end
  if d.use == "eye" then
    if hit and hit.id == 120 then return false end
    return require("core.endportal").throwEye(self)
  end
  if d.use == "map" then
    local id = require("core.maps").create(self)
    if not id then return false end
    if p.gameMode ~= "creative" then self.inventory:decrement(self.selected, 1) end
    self:giveItem({ id = 358, count = 1, damage = id })
    self:emit("sound", "paper", p.x, p.y + 1, p.z)
    return true
  end
  if d.use == "throw" then
    if self.mobs then self.mobs.throwItem(self, stack.id) end
    self:consumeHeld(1)
    return true
  end

  if not hit then return false end

  if d.use == "flint_and_steel" then
    if hit.id == 46 then
      self:primeTnt(hit.x, hit.y, hit.z)
    else
      local fx, fy, fz = hit.x + hit.nx, hit.y + hit.ny, hit.z + hit.nz
      if world:getBlock(fx, fy, fz) == 0 then
        if not require("core.portal").tryLight(self, fx, fy, fz) then
          world:setBlock(fx, fy, fz, 51, 0)
        end
        self:emit("sound", "ignite", fx + 0.5, fy + 0.5, fz + 0.5)
      end
    end
    self:damageHeld(1)
    return true
  end

  if d.toolType == "hoe" then
    if (hit.id == 2 or hit.id == 3) and hit.face ~= 4 and world:getBlock(hit.x, hit.y + 1, hit.z) == 0 then
      world:setBlock(hit.x, hit.y, hit.z, 60, 0)
      self:notifyNeighbors(hit.x, hit.y, hit.z)
      self:emit("sound", "step_grass", hit.x + 0.5, hit.y + 1, hit.z + 0.5)
      if hit.id == 2 and self.rng:chance(0.1) then
        self:dropStack(hit.x + 0.5, hit.y + 1.2, hit.z + 0.5, items.newStack(295))
      end
      self:damageHeld(1)
      return true
    end
    return false
  end

  if d.use == "dye" and stack.damage == 15 then
    if self:applyBoneMeal(hit.x, hit.y, hit.z) then
      self:consumeHeld(1)
      return true
    end
    return false
  end

  -- 4) stawianie bloku
  return self:placeFromHand(hit)
end

function Game:useBucket(stack, d)
  local p = self.player
  local world = self.world
  local ex, ey, ez = p:eyePosition()
  local lx, ly, lz = p:lookVector()
  if stack.id == 325 then
    -- napełnianie: celujemy w źródło cieczy
    local hit = raycast.cast(world, ex, ey, ez, lx, ly, lz, self:reach(), function(def, _, meta)
      return def.liquid ~= nil and meta == 0 or def.selectable
    end)
    if hit and defs[hit.id] and defs[hit.id].liquid and hit.meta == 0 then
      world:setBlock(hit.x, hit.y, hit.z, 0, 0)
      self:notifyNeighbors(hit.x, hit.y, hit.z)
      local filled = hit.id == 8 and 326 or 327
      if p.gameMode ~= "creative" then
        self.inventory:decrement(self.selected, 1)
        self:giveItem(items.newStack(filled))
      end
      self:emit("sound", "bucket", hit.x + 0.5, hit.y + 0.5, hit.z + 0.5)
      return true
    end
    return false
  end
  -- wylewanie
  local hit = self:target()
  if not hit then return false end
  local x, y, z = hit.x + hit.nx, hit.y + hit.ny, hit.z + hit.nz
  local hd = defs[hit.id]
  if hd and hd.replaceable then x, y, z = hit.x, hit.y, hit.z end
  local cur = world:getBlock(x, y, z)
  local cd = defs[cur]
  if cur ~= 0 and not (cd and cd.replaceable) then return false end
  if self.dimension == "nether" and d.fluid == 8 then
    self:emit("sound", "fizz", x + 0.5, y + 0.5, z + 0.5)
    self:emit("particles", "smoke", x + 0.5, y + 0.5, z + 0.5)
    if p.gameMode ~= "creative" then self.inventory:set(self.selected, items.newStack(325)) end
    return true
  end
  self:destroyByLiquid(x, y, z)
  world:setBlock(x, y, z, d.fluid, 0)
  self:scheduleTick(x, y, z, 1)
  self:notifyNeighbors(x, y, z)
  if p.gameMode ~= "creative" then
    self.inventory:set(self.selected, items.newStack(325))
  end
  self:emit("sound", "bucket", x + 0.5, y + 0.5, z + 0.5)
  return true
end

-- Szklana butelka: nabieranie wody ze źródła
function Game:fillBottle()
  local p = self.player
  local ex, ey, ez = p:eyePosition()
  local lx, ly, lz = p:lookVector()
  local hit = raycast.cast(self.world, ex, ey, ez, lx, ly, lz, self:reach(), function(def, _, meta)
    return def.liquid ~= nil or def.selectable
  end)
  if hit and hit.id == 8 or (hit and hit.id == 9) then
    if p.gameMode ~= "creative" then self.inventory:decrement(self.selected, 1) end
    self:giveItem({ id = 373, count = 1, damage = 0 })
    self:emit("sound", "bucket", hit.x + 0.5, hit.y + 0.5, hit.z + 0.5)
    return true
  end
  return false
end

-- Mączka kostna: natychmiastowy wzrost
function Game:applyBoneMeal(x, y, z)
  local world = self.world
  local id = world:getBlock(x, y, z)
  if id == 59 then
    world:setBlock(x, y, z, 59, 7)
    self:emit("particles", "happy", x + 0.5, y + 0.5, z + 0.5)
    return true
  end
  if id == 6 then
    self:growTree(x, y, z, world:getMeta(x, y, z) % 4)
    return true
  end
  if id == 2 then
    -- trawa i kwiaty wokół
    for _ = 1, 32 do
      local tx = x + self.rng:int(-3, 3)
      local tz = z + self.rng:int(-3, 3)
      local ty = y + 1
      if world:getBlock(tx, ty - 1, tz) == 2 and world:getBlock(tx, ty, tz) == 0 then
        local r = self.rng:next()
        local plant = r < 0.8 and 31 or (r < 0.9 and 37 or 38)
        world:setBlock(tx, ty, tz, plant, 0)
      end
    end
    self:emit("particles", "happy", x + 0.5, y + 1, z + 0.5)
    return true
  end
  return false
end

-- Wyrośnięcie drzewa z sadzonki
function Game:growTree(x, y, z, kind)
  local trees = require("core.trees")
  self.world:setBlock(x, y, z, 0, 0)
  local ok = trees.grow(self.world, x, y, z, kind or 0, self.rng, true)
  if not ok then
    self.world:setBlock(x, y, z, 6, kind or 0)
  end
  return ok
end

-- ---------------------------------------------------------------------------
-- Interakcja gracza w ticku: kopanie i używanie
-- ---------------------------------------------------------------------------
function Game:tickInteraction()
  local inp = self.input
  local p = self.player
  if self.dead or self.uiOpen then
    self.mining = nil
    return
  end
  if self.breakCooldown > 0 then self.breakCooldown = self.breakCooldown - 1 end
  if self.useCooldown > 0 then self.useCooldown = self.useCooldown - 1 end

  local hit = self:target()
  self.hit = hit

  -- atak bytu ma pierwszeństwo przed kopaniem
  local entityHit = self.mobs and self.mobs.pickEntity(self, hit and hit.dist or self:reach())
  self.entityHit = entityHit
  if inp.attackPressed then
    self:emit("swing")
    if entityHit then
      self.mobs.playerAttack(self, entityHit)
      self.mining = nil
      inp.attackPressed = false
    end
  end

  -- kopanie
  if inp.attack and hit and not entityHit then
    local creative = p.gameMode == "creative"
    if creative then
      if self.breakCooldown == 0 then
        self:breakBlock(hit.x, hit.y, hit.z, true)
        self.breakCooldown = 5
      end
      self.mining = nil
    else
      local m = self.mining
      if not m or m.x ~= hit.x or m.y ~= hit.y or m.z ~= hit.z or m.id ~= hit.id then
        m = { x = hit.x, y = hit.y, z = hit.z, id = hit.id, progress = 0, ticks = 0 }
        self.mining = m
      end
      if self.breakCooldown == 0 then
        local def = defs[hit.id]
        local aqua = require("core.enchant").level(self.armor.slots[1], "aqua_affinity") > 0
        local s = items.breakStrength(self:heldStack(), def, p.onGround, p.headInWater and not aqua)
        m.progress = m.progress + s
        m.ticks = m.ticks + 1
        if m.ticks % 4 == 1 then self:emit("hit", hit.x, hit.y, hit.z, hit.id, hit.face) end
        if m.progress >= 1 then
          local held = self:heldStack()
          local hd = held and items.get(held.id)
          self:breakBlock(hit.x, hit.y, hit.z, true)
          if def.hardness > 0 and hd and hd.maxDamage then
            self:damageHeld(hd.toolType == "sword" and 2 or 1)
          end
          self.survival.addExhaustion(self, 0.025)
          self.mining = nil
          self.breakCooldown = 5
        end
      end
    end
  else
    self.mining = nil
  end

  -- prawy przycisk
  if inp.use and self.useCooldown == 0 then
    local eating = self.survival.isUsingItem(self)
    if not eating then
      local did = false
      if entityHit and self.mobs and inp.usePressed then
        did = self.mobs.interact(self, entityHit)
      end
      if not did then did = self:useItem(hit) end
      if did then
        self.useCooldown = 4
        self:emit("swing")
      end
    end
  end
  if not inp.use then self.survival.stopUsing(self) end
  inp.attackPressed = false
  inp.usePressed = false
end

-- ---------------------------------------------------------------------------
-- Losowe ticki bloków w chunkach wokół gracza
-- ---------------------------------------------------------------------------
function Game:randomTicks()
  if self.remote then return end
  local world = self.world
  local rng = self.rng
  local p = self.player
  local pcx, pcz = floor(p.x / 16), floor(p.z / 16)
  local r = math.min(self.renderDistance, 8)
  for _, c in pairs(world.chunks) do
    if c.lit and math.abs(c.cx - pcx) <= r and math.abs(c.cz - pcz) <= r then
      local top = c.maxY
      local count = 3 * (floor(top / 16) + 1)
      for _ = 1, count do
        local lx, lz = rng:int(0, 15), rng:int(0, 15)
        local y = rng:int(0, top)
        local i = lx + lz * 16 + y * 256
        local id = c.blocks[i]
        if id ~= 0 and id ~= 1 and id ~= 3 then
          blocklogic.randomTick(self, c.cx * 16 + lx, y, c.cz * 16 + lz, id, c.meta[i])
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Pora dnia
-- ---------------------------------------------------------------------------
-- Jasność nieba 0..1 (jak w MC: najciemniej w nocy 0.2 * 15 = ~4)
function Game:daylight()
  if self.dimension == "nether" or self.dimension == "end" then return 0.2 end
  local t = (self.dayTime % M.DAY_LENGTH) / M.DAY_LENGTH -- 0 = wschód (6:00)
  -- kąt słońca: 0 w południe
  local angle = t - 0.25
  local brightness = math.cos(angle * math.pi * 2) * 2 + 0.5
  if brightness < 0 then brightness = 0 elseif brightness > 1 then brightness = 1 end
  local rain = self.weather.strength or 0
  brightness = brightness * (1 - rain * 0.3)
  return 0.2 + brightness * 0.8
end

-- Kąt słońca dla nieba (0 = wschód, 0.25 = południe)
function Game:celestialAngle(alpha)
  return ((self.dayTime + (alpha or 0)) % M.DAY_LENGTH) / M.DAY_LENGTH
end

function Game:isNight()
  local t = self.dayTime % M.DAY_LENGTH
  return t > 12500 and t < 23500
end

-- Skylight po uwzględnieniu pory dnia (do spawnu mobów, palenia zombie)
function Game:effectiveSkyLight(x, y, z)
  local s = self.world:getSkyLight(x, y, z)
  local d = self:daylight()
  return floor(s * d + 0.5)
end

function Game:lightAt(x, y, z)
  local w = self.world
  local s = w:getSkyLight(x, y, z)
  local b = w:getBlockLight(x, y, z)
  local sk = floor(s * self:daylight() + 0.5)
  return math.max(sk, b)
end

-- ---------------------------------------------------------------------------
-- Spanie w łóżku
-- ---------------------------------------------------------------------------
function Game:trySleep(x, y, z, meta)
  if self.remote then
    self:emit("message", "Spac moze tylko gospodarz gry")
    return
  end
  if self.dimension == "nether" then
    self.world:setBlock(x, y, z, 0, 0)
    self:explode(x + 0.5, y + 0.5, z + 0.5, 5)
    return
  end
  if not self:isNight() then
    self:emit("message", "Mozesz spac tylko w nocy")
    self.spawnX, self.spawnY, self.spawnZ = x + 0.5, y + 1, z + 0.5
    return
  end
  if self.mobs and self.mobs.hostileNear(self, x, y, z, 8) then
    self:emit("message", "Nie mozesz teraz spac - w poblizu sa potwory")
    return
  end
  self.sleeping = { x = x, y = y, z = z, timer = 0 }
  self.spawnX, self.spawnY, self.spawnZ = x + 0.5, y + 1, z + 0.5
  self:emit("message", "Ustawiono punkt odrodzenia")
end

function Game:tickSleep()
  local s = self.sleeping
  if not s then return end
  s.timer = s.timer + 1
  local p = self.player
  p.vx, p.vy, p.vz = 0, 0, 0
  if s.timer >= 100 then
    -- poranek
    self.dayTime = (floor(self.dayTime / M.DAY_LENGTH) + 1) * M.DAY_LENGTH
    self.weather.raining = false
    self.weather.thunder = false
    self.sleeping = nil
    self:emit("wake")
  end
end

-- ---------------------------------------------------------------------------
-- Pogoda
-- ---------------------------------------------------------------------------
function Game:tickWeather()
  local w = self.weather
  w.timer = w.timer - 1
  if w.timer <= 0 then
    if w.raining then
      w.raining = false
      w.thunder = false
      w.timer = self.rng:int(12000, 180000)
    else
      w.raining = true
      w.thunder = self.rng:chance(0.3)
      w.timer = self.rng:int(12000, 24000)
    end
  end
  local target = w.raining and 1 or 0
  if w.strength < target then w.strength = math.min(target, w.strength + 0.01)
  elseif w.strength > target then w.strength = math.max(target, w.strength - 0.01) end

  -- piorun podczas burzy
  if w.thunder and w.strength > 0.9 and self.dimension == "overworld" and self.rng:chance(1 / 2000) then
    local p = self.player
    local lx = floor(p.x) + self.rng:int(-48, 48)
    local lz = floor(p.z) + self.rng:int(-48, 48)
    if self.world:isLoadedAt(lx, lz) then
      local ly = self.world:getHeight(lx, lz)
      self:emit("lightning", lx + 0.5, ly, lz + 0.5)
      if self.mobs then self.mobs.lightningStrike(self, lx + 0.5, ly, lz + 0.5) end
    end
  end

  -- śnieg i lód w zimnych biomach podczas opadów
  if w.raining and self.biomeAt and self.rng:chance(1 / 4) then
    local p = self.player
    local x = floor(p.x) + self.rng:int(-32, 32)
    local z = floor(p.z) + self.rng:int(-32, 32)
    if self.world:isLoadedAt(x, z) then
      local biome = self.biomeAt(x, z)
      if biome and biome.snowy then
        local y = self.world:getHeight(x, z)
        local below = self.world:getBlock(x, y - 1, z)
        if below == 8 and self.world:getMeta(x, y - 1, z) == 0 then
          self.world:setBlock(x, y - 1, z, 79, 0)
        elseif self.world:getBlock(x, y, z) == 0 and blocks.OPAQUE[below] == 1 then
          self:setBlock(x, y, z, 78, 0)
        end
      end
    end
  end
end

-- Czy w tym miejscu pada deszcz (nie śnieg) i jest niebo nad głową
function Game:isRainingAt(x, y, z)
  if not self.weather.raining then return false end
  if self.world:getHeight(floor(x), floor(z)) > floor(y) then return false end
  if self.biomeAt then
    local b = self.biomeAt(floor(x), floor(z))
    if b and (b.snowy or b.dry) then return false end
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Główny tick gry
-- ---------------------------------------------------------------------------
function Game:tick()
  self.time = self.time + 1
  self.dayTime = self.dayTime + 1
  local p = self.player
  local inp = self.input

  local remote = self.remote
  if not self.dead then
    if remote and not self.world:isLoadedAt(floor(p.x), floor(p.z)) then
      -- gość czeka na teren od gospodarza
      p.vx, p.vy, p.vz = 0, 0, 0
      p.prevX, p.prevY, p.prevZ = p.x, p.y, p.z
    elseif self.sleeping then
      self:tickSleep()
    elseif p.riding then
      require("core.vehicles").tickRider(self)
    else
      p.input.forward = inp.forward
      p.input.strafe = inp.strafe
      p.input.jump = inp.jump
      p.input.sneak = inp.sneak
      p.input.sprint = inp.sprint
      if self.uiOpen then
        p.input.forward, p.input.strafe, p.input.jump = 0, 0, false
      end
      if self.survival.isUsingItem(self) then
        p.input.forward = p.input.forward * 0.2
        p.input.strafe = p.input.strafe * 0.2
        p.input.sprint = false
      end
      p:tick(self.world, self.survival.canSprint(self))
    end
    self:tickInteraction()
    if not remote then
      require("core.portal").tick(self)
      require("core.endportal").tick(self)
    end
    maps.tick(self)
  end

  self.survival.tick(self)
  self.entities:tick()
  if remote then
    -- świat symuluje gospodarz; tu tylko płynna zmiana siły deszczu
    local w = self.weather
    local target = w.raining and 1 or 0
    if w.strength < target then w.strength = math.min(target, w.strength + 0.01)
    elseif w.strength > target then w.strength = math.max(target, w.strength - 0.01) end
    return
  end
  require("core.vehicles").followVehicle(self)
  -- płyty naciskowe pod graczem i bytami
  local redstone = require("core.redstone")
  if p.onGround and not self.dead then redstone.checkPlate(self, p) end
  for _, e in ipairs(self.entities.list) do
    if e.onGround and not e.dead and (e.isMob or e.type == "item") then redstone.checkPlate(self, e) end
  end
  -- na serwerze dedykowanym moby pojawiają się tylko wokół graczy (robi to serwer)
  if self.mobs and not self.dedicated then self.mobs.tick(self) end
  if self.dimension == "end" then require("core.dragon").tick(self) end
  self:processScheduled()
  self:randomTicks()
  self:tickWeather()
  self:tickTiles()
end

-- Piece przetapiają w tle
function Game:tickTiles()
  local furnaces = require("core.furnace")
  for _, c in pairs(self.world.chunks) do
    for idx, tile in pairs(c.tiles) do
      if tile.kind == "furnace" then
        local lx, lz = idx % 16, floor(idx / 16) % 16
        local y = floor(idx / 256)
        furnaces.tick(self, tile, c.cx * 16 + lx, y, c.cz * 16 + lz)
      elseif tile.kind == "brewing" then
        local lx, lz = idx % 16, floor(idx / 16) % 16
        potions.tickStand(self, tile, c.cx * 16 + lx, floor(idx / 256), c.cz * 16 + lz)
      end
    end
  end
end

-- Ładuje świat wokół gracza (wywoływane co klatkę z play.lua)
function Game:updateWorld(budget)
  local p = self.player
  local cx, cz = floor(p.x / 16), floor(p.z / 16)
  self.world:updateLoading(cx, cz, self.renderDistance, budget or 2)
  local removed = self.world:unloadFar(cx, cz, self.renderDistance + 4)
  if removed > 0 then self.entities:removeOutside(self.world) end
end

-- Zapisuje wszystkie zmienione chunki, byty i stan gracza
function Game:saveAll()
  local folder = self.saveFolder
  if not folder then return 0 end
  local n = 0
  for _, chunk in pairs(self.world.chunks) do
    local list = save.collectEntities(self, chunk, false)
    if #list > 0 then chunk.savedEntities = list end
    if chunk.modified or #list > 0 then
      save.saveChunk(folder, chunk, self.dimension)
      n = n + 1
    end
    chunk.savedEntities = nil
  end
  save.saveLevel(folder, self)
  maps.saveAll(self)
  return n
end

-- Wybiera miejsce startu: najbliższy ląd (nie ocean) wokół (0, 0)
function Game:chooseSpawnColumn()
  if not self.gen then return 0, 0 end
  for r = 0, 2000, 16 do
    for i = 0, 7 do
      local a = i / 8 * math.pi * 2
      local x, z = floor(math.cos(a) * r), floor(math.sin(a) * r)
      local biome, h = self.gen:biome(x, z)
      if h >= worldgen.SEA + 1 and biome ~= worldgen.BIOMES.ocean
        and biome ~= worldgen.BIOMES.beach then
        return x, z
      end
      if r == 0 then break end
    end
  end
  return 0, 0
end

-- Generuje okolicę startu od razu i stawia gracza na powierzchni
function Game:prepareSpawn(radius)
  local x, z = self:chooseSpawnColumn()
  local cx, cz = floor(x / 16), floor(z / 16)
  self.world:updateLoading(cx, cz, radius or 1, 1000)
  local y = self:surfaceY(x, z)
  self.worldSpawnX, self.worldSpawnY, self.worldSpawnZ = x + 0.5, y, z + 0.5
  local p = self.player
  p.x, p.y, p.z = x + 0.5, y, z + 0.5
  p.prevX, p.prevY, p.prevZ = p.x, p.y, p.z
end

-- Najniższe bezpieczne y nad ziemią w kolumnie (stopy gracza)
function Game:surfaceY(x, z)
  local world = self.world
  local y = world:getHeight(x, z)
  while y < 126 and (blocks.SOLID[world:getBlock(x, y, z)] == 1
    or blocks.SOLID[world:getBlock(x, y + 1, z)] == 1) do
    y = y + 1
  end
  return y
end

return M
