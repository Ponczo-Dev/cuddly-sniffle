-- core/world.lua
-- Świat: zbiór chunków + dostęp do bloków we współrzędnych świata.
-- Ładuje chunki wokół gracza (generuje albo wczytuje z dysku), oświetla je
-- i zwalnia te, które są za daleko. Bez love.*, testowalny przez lua.exe.

local Chunk = require("core.chunk")
local blocks = require("core.blocks")

local M = {}

local SIZE, HEIGHT = Chunk.SIZE, Chunk.HEIGHT
local floor = math.floor

local World = {}
World.__index = World

-- Klucz chunka w tablicy (liczba, bez tworzenia stringów)
local function key(cx, cz)
  return (cx + 32768) * 65536 + (cz + 32768)
end
M.key = key

-- Kolejność ładowania: od najbliższych chunków (spirala po odległości)
local spiralCache = {}
local function spiral(radius)
  if spiralCache[radius] then return spiralCache[radius] end
  local list = {}
  for dz = -radius, radius do
    for dx = -radius, radius do
      list[#list + 1] = { dx, dz, dx * dx + dz * dz }
    end
  end
  table.sort(list, function(a, b) return a[3] < b[3] end)
  spiralCache[radius] = list
  return list
end
M.spiral = spiral

-- opts: seed, generator(chunk, world), loader(cx, cz) -> chunk|nil,
--       lighting (moduł oświetlenia), onUnload(chunk)
function M.new(opts)
  opts = opts or {}
  local self = setmetatable({}, World)
  self.seed = opts.seed or 0
  self.generator = opts.generator
  self.loader = opts.loader
  self.lighting = opts.lighting
  self.onUnload = opts.onUnload
  self.onCreate = opts.onCreate
  self.chunks = {}
  self.chunkCount = 0
  self.listeners = {}   -- obiekty z metodą onBlockChanged(world, x, y, z, oldId, newId)
  return self
end

-- ---------------------------------------------------------------------------
-- Chunki
-- ---------------------------------------------------------------------------
function World:getChunk(cx, cz)
  return self.chunks[key(cx, cz)]
end

function World:getChunkAt(x, z)
  return self.chunks[key(floor(x / SIZE), floor(z / SIZE))]
end

function World:isLoadedAt(x, z)
  local c = self:getChunkAt(x, z)
  return c ~= nil and c.generated
end

-- Wstawia gotowy chunk (np. w testach)
function World:addChunk(chunk)
  local k = key(chunk.cx, chunk.cz)
  if not self.chunks[k] then self.chunkCount = self.chunkCount + 1 end
  self.chunks[k] = chunk
  return chunk
end

-- Tworzy chunk: wczytuje z dysku albo generuje
function World:createChunk(cx, cz)
  local chunk = self.loader and self.loader(cx, cz)
  local fromDisk = chunk ~= nil
  if not chunk then
    chunk = Chunk.new(cx, cz)
    if self.generator then
      self.generator(chunk, self)
    end
    chunk:recalcHeights()
  end
  chunk.generated = true
  chunk.dirty = true
  self:addChunk(chunk)
  if self.onCreate then self.onCreate(chunk, fromDisk) end
  return chunk
end

function World:removeChunk(cx, cz)
  local k = key(cx, cz)
  local chunk = self.chunks[k]
  if chunk then
    if self.onUnload then self.onUnload(chunk) end
    self.chunks[k] = nil
    self.chunkCount = self.chunkCount - 1
  end
  return chunk
end

-- Czy wszystkie 8 sąsiadów chunka spełnia warunek pola field (np. "generated")
function World:neighborsHave(cx, cz, field)
  for dz = -1, 1 do
    for dx = -1, 1 do
      if dx ~= 0 or dz ~= 0 then
        local n = self.chunks[key(cx + dx, cz + dz)]
        if not n or not n[field] then return false end
      end
    end
  end
  return true
end

-- Ładowanie świata wokół gracza.
--   radius: zasięg renderowania (w chunkach)
--   budget: ile chunków maks. wygenerować w tym wywołaniu
-- Generujemy o 2 chunki dalej, oświetlamy o 1 dalej niż rysujemy,
-- żeby brzegi miały poprawne światło i ściany.
function World:updateLoading(centerCx, centerCz, radius, budget, lightBudget)
  local generated = 0
  local genList = spiral(radius + 2)
  for i = 1, #genList do
    if generated >= budget then break end
    local o = genList[i]
    local cx, cz = centerCx + o[1], centerCz + o[2]
    if not self.chunks[key(cx, cz)] then
      self:createChunk(cx, cz)
      generated = generated + 1
    end
  end

  -- oświetlenie chunków, które mają wszystkich sąsiadów
  local litList = spiral(radius + 1)
  local lit = 0
  lightBudget = lightBudget or budget
  for i = 1, #litList do
    if lit >= lightBudget then break end
    local o = litList[i]
    local cx, cz = centerCx + o[1], centerCz + o[2]
    local c = self.chunks[key(cx, cz)]
    if c and c.generated and not c.lit and self:neighborsHave(cx, cz, "generated") then
      self:lightChunk(c)
      lit = lit + 1
    end
  end
  return generated, lit
end

function World:lightChunk(chunk)
  if self.lighting then
    self.lighting.lightChunk(self, chunk)
  else
    -- bez modułu oświetlenia: pełne światło nieba nad terenem
    local sky = chunk.sky
    for z = 0, SIZE - 1 do
      for x = 0, SIZE - 1 do
        local h = chunk.heightMap[x + z * SIZE]
        for y = h, HEIGHT - 1 do
          sky[x + z * SIZE + y * 256] = 15
        end
      end
    end
  end
  chunk.lit = true
  chunk.dirty = true
end

-- Zwalnia chunki dalej niż radius od środka.
-- keep: opcjonalna lista { cx, cz, r } obszarów, których nie zwalniamy (goście w sieci)
function World:unloadFar(centerCx, centerCz, radius, keep)
  local toRemove = {}
  for _, c in pairs(self.chunks) do
    if math.abs(c.cx - centerCx) > radius or math.abs(c.cz - centerCz) > radius then
      local kept = false
      for _, k in ipairs(keep or {}) do
        if math.abs(c.cx - k[1]) <= k[3] and math.abs(c.cz - k[2]) <= k[3] then kept = true break end
      end
      if not kept then toRemove[#toRemove + 1] = c end
    end
  end
  for _, c in ipairs(toRemove) do
    self:removeChunk(c.cx, c.cz)
  end
  return #toRemove
end

-- ---------------------------------------------------------------------------
-- Bloki we współrzędnych świata
-- ---------------------------------------------------------------------------
function World:getBlock(x, y, z)
  if y < 0 or y >= HEIGHT then return 0 end
  local c = self.chunks[key(floor(x / SIZE), floor(z / SIZE))]
  if not c then return 0 end
  return c.blocks[(x % SIZE) + (z % SIZE) * SIZE + y * 256]
end

function World:getMeta(x, y, z)
  if y < 0 or y >= HEIGHT then return 0 end
  local c = self.chunks[key(floor(x / SIZE), floor(z / SIZE))]
  if not c then return 0 end
  return c.meta[(x % SIZE) + (z % SIZE) * SIZE + y * 256]
end

function World:getBlockAndMeta(x, y, z)
  if y < 0 or y >= HEIGHT then return 0, 0 end
  local c = self.chunks[key(floor(x / SIZE), floor(z / SIZE))]
  if not c then return 0, 0 end
  local i = (x % SIZE) + (z % SIZE) * SIZE + y * 256
  return c.blocks[i], c.meta[i]
end

function World:getSkyLight(x, y, z)
  if self.noSky then return 0 end
  if y >= HEIGHT then return 15 end
  if y < 0 then return 0 end
  local c = self.chunks[key(floor(x / SIZE), floor(z / SIZE))]
  if not c then return 15 end
  return c.sky[(x % SIZE) + (z % SIZE) * SIZE + y * 256]
end

function World:getBlockLight(x, y, z)
  if y < 0 or y >= HEIGHT then return 0 end
  local c = self.chunks[key(floor(x / SIZE), floor(z / SIZE))]
  if not c then return 0 end
  return c.blockLight[(x % SIZE) + (z % SIZE) * SIZE + y * 256]
end

-- Najwyższy blok nieprzepuszczający światła w kolumnie (+1)
function World:getHeight(x, z)
  local c = self.chunks[key(floor(x / SIZE), floor(z / SIZE))]
  if not c then return 0 end
  return c.heightMap[(x % SIZE) + (z % SIZE) * SIZE]
end

-- Oznacza chunk (i sąsiadów, jeśli blok leży na krawędzi) do przebudowy mesha
function World:markDirty(x, y, z)
  local cx, cz = floor(x / SIZE), floor(z / SIZE)
  local lx, lz = x % SIZE, z % SIZE
  local x0 = lx == 0 and -1 or 0
  local x1 = lx == SIZE - 1 and 1 or 0
  local z0 = lz == 0 and -1 or 0
  local z1 = lz == SIZE - 1 and 1 or 0
  for dz = z0, z1 do
    for dx = x0, x1 do
      local c = self.chunks[key(cx + dx, cz + dz)]
      if c then c.dirty = true end
    end
  end
end

-- Ustawia blok z pełnymi aktualizacjami (światło, mesh, słuchacze).
-- Zwraca true, jeśli się udało (chunk istnieje).
function World:setBlock(x, y, z, id, meta)
  if y < 0 or y >= HEIGHT then return false end
  local c = self.chunks[key(floor(x / SIZE), floor(z / SIZE))]
  if not c then return false end
  local lx, lz = x % SIZE, z % SIZE
  local i = lx + lz * SIZE + y * 256
  local oldId = c.blocks[i]
  local oldMeta = c.meta[i]
  meta = meta or 0
  if oldId == id and oldMeta == meta then return true end

  c.blocks[i] = id
  c.meta[i] = meta
  c.modified = true
  if oldId ~= id then
    c:updateColumn(lx, y, lz, id)
    -- usunięty blok traci swoje dane dodatkowe (zawartość skrzyni itd.)
    if c.tiles[i] and not (blocks.defs[id] and blocks.defs[id].tileEntity) then
      c.tiles[i] = nil
    end
  end
  self:markDirty(x, y, z)

  if oldId ~= id and self.lighting and c.lit then
    self.lighting.onBlockChanged(self, x, y, z, oldId, id)
  end
  for _, l in ipairs(self.listeners) do
    l:onBlockChanged(self, x, y, z, oldId, id, oldMeta, meta)
  end
  return true
end

-- Zmienia tylko meta (np. stan drzwi), z odświeżeniem mesha
function World:setMeta(x, y, z, meta)
  local id = self:getBlock(x, y, z)
  return self:setBlock(x, y, z, id, meta)
end

function World:getTile(x, y, z)
  if y < 0 or y >= HEIGHT then return nil end
  local c = self:getChunkAt(x, z)
  if not c then return nil end
  return c.tiles[(x % SIZE) + (z % SIZE) * SIZE + y * 256]
end

function World:setTile(x, y, z, tile)
  local c = self:getChunkAt(x, z)
  if not c then return end
  c.tiles[(x % SIZE) + (z % SIZE) * SIZE + y * 256] = tile
  c.modified = true
end

function World:addListener(l)
  self.listeners[#self.listeners + 1] = l
end

return M
