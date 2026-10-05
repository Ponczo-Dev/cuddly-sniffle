-- core/save.lua
-- Zapis i odczyt świata:
--   worlds/<folder>/level.lua           - dane świata i gracza (tekst Lua)
--   worlds/<folder>/chunks/<cx>.<cz>.dat - bloki (RLE + zlib), skrzynie, byty
-- Oświetlenia nie zapisujemy - liczy się na nowo po wczytaniu.

local Chunk = require("core.chunk")
local Inventory = require("core.inventory")
local serialize = require("core.serialize")
local fs = require("core.fs")

local M = {}

M.VERSION = 1
local VOLUME = Chunk.VOLUME
local unpack = rawget(_G, "unpack") or table.unpack

-- ---------------------------------------------------------------------------
-- RLE: pary (długość 1..255, wartość)
-- ---------------------------------------------------------------------------
local function rleEncode(arr, n)
  local parts = {}
  local buf = {}
  local bn = 0
  local i = 0
  while i < n do
    local v = arr[i]
    local run = 1
    while i + run < n and run < 255 and arr[i + run] == v do run = run + 1 end
    buf[bn + 1] = run
    buf[bn + 2] = v
    bn = bn + 2
    if bn >= 4000 then
      parts[#parts + 1] = string.char(unpack(buf, 1, bn))
      bn = 0
    end
    i = i + run
  end
  if bn > 0 then parts[#parts + 1] = string.char(unpack(buf, 1, bn)) end
  return table.concat(parts)
end
M.rleEncode = rleEncode

local function rleDecode(data, pos, arr, n)
  local i = 0
  local len = #data
  while i < n and pos < len do
    local stop = math.min(len, pos + 3999)
    local bytes = { data:byte(pos, stop) }
    for k = 1, #bytes - 1, 2 do
      local run, v = bytes[k], bytes[k + 1]
      for j = i, i + run - 1 do arr[j] = v end
      i = i + run
      if i >= n then
        return pos + k + 1
      end
    end
    pos = pos + #bytes - (#bytes % 2)
  end
  return pos
end
M.rleDecode = rleDecode

-- ---------------------------------------------------------------------------
-- Dane dodatkowe bloków i byty
-- ---------------------------------------------------------------------------
local function encodeTiles(chunk)
  local out = {}
  for idx, t in pairs(chunk.tiles) do
    local e = { idx = idx, kind = t.kind }
    if t.inventory then e.inv = t.inventory:serialize() end
    if t.pendingSlots then
      e.pending = {}
      for i, s in pairs(t.pendingSlots) do e.pending[#e.pending + 1] = { i, s.id, s.count, s.damage } end
    end
    e.burn, e.burnMax, e.cook, e.xp, e.brew = t.burn, t.burnMax, t.cook, t.xp, t.brew
    e.mob, e.delay = t.mob, t.delay
    out[#out + 1] = e
  end
  return out
end

local function decodeTiles(chunk, list)
  for _, e in ipairs(list or {}) do
    local t = { kind = e.kind }
    if e.inv then
      t.inventory = Inventory.new(e.kind == "furnace" and 3 or (e.kind == "brewing" and 4 or 27))
      t.inventory:deserialize(e.inv)
    end
    if e.pending then
      t.pendingSlots = {}
      for _, s in ipairs(e.pending) do t.pendingSlots[s[1]] = { id = s[2], count = s[3], damage = s[4] } end
    end
    t.burn, t.burnMax, t.cook, t.xp = e.burn or 0, e.burnMax or 0, e.cook or 0, e.xp or 0
    if e.kind == "brewing" then t.brew = e.brew or 0 end
    t.mob, t.delay = e.mob, e.delay
    chunk.tiles[e.idx] = t
  end
end

-- ---------------------------------------------------------------------------
-- Chunk <-> tekst
-- ---------------------------------------------------------------------------
function M.encodeChunk(chunk)
  local blocks = rleEncode(chunk.blocks, VOLUME)
  local meta = rleEncode(chunk.meta, VOLUME)
  local extra = serialize.encode({
    tiles = encodeTiles(chunk),
    entities = chunk.savedEntities,
  })
  local header = string.format("MCL%d %d %d %d\n", M.VERSION, #blocks, #meta, #extra)
  return header .. blocks .. meta .. extra
end

function M.decodeChunk(cx, cz, data)
  local v, nb, nm, ne = data:match("^MCL(%d+) (%d+) (%d+) (%d+)\n")
  if not v then return nil end
  local headerLen = #data:match("^[^\n]*\n")
  nb, nm, ne = tonumber(nb), tonumber(nm), tonumber(ne)
  local chunk = Chunk.new(cx, cz)
  local p = headerLen + 1
  rleDecode(data:sub(p, p + nb - 1), 1, chunk.blocks, VOLUME)
  p = p + nb
  rleDecode(data:sub(p, p + nm - 1), 1, chunk.meta, VOLUME)
  p = p + nm
  local extra = serialize.decode(data:sub(p, p + ne - 1)) or {}
  decodeTiles(chunk, extra.tiles)
  chunk.savedEntities = extra.entities
  chunk:recalcHeights()
  return chunk
end

local function chunkPath(folder, cx, cz, dim)
  local sub = (dim == "nether") and "/nether/chunks/" or (dim == "end" and "/end/chunks/" or "/chunks/")
  return "worlds/" .. folder .. sub .. cx .. "." .. cz .. ".dat"
end

function M.saveChunk(folder, chunk, dim)
  local data = M.encodeChunk(chunk)
  fs.write(chunkPath(folder, chunk.cx, chunk.cz, dim), fs.compress(data))
  chunk.modified = false
end

function M.loadChunk(folder, cx, cz, dim)
  local raw = fs.read(chunkPath(folder, cx, cz, dim))
  if not raw then return nil end
  local data = fs.decompress(raw)
  if not data then return nil end
  return M.decodeChunk(cx, cz, data)
end

-- ---------------------------------------------------------------------------
-- Lista światów
-- ---------------------------------------------------------------------------
function M.listWorlds()
  local out = {}
  for _, folder in ipairs(fs.list("worlds")) do
    local text = fs.read("worlds/" .. folder .. "/level.lua")
    local data = text and serialize.decode(text)
    if type(data) == "table" then
      out[#out + 1] = { folder = folder, name = data.name or folder, seed = data.seed,
        gameMode = data.gameMode, hardcore = data.hardcore, lastPlayed = data.lastPlayed or 0,
        dead = data.dead }
    end
  end
  table.sort(out, function(a, b) return a.lastPlayed > b.lastPlayed end)
  return out
end

-- Bezpieczna nazwa folderu z nazwy świata
function M.newFolderName(name)
  local base = name:gsub("[^%w%-_ ]", ""):gsub("%s+", "_")
  if base == "" then base = "Swiat" end
  local folder = base
  local n = 1
  while fs.exists("worlds/" .. folder) do
    n = n + 1
    folder = base .. "_" .. n
  end
  return folder
end

function M.deleteWorld(folder)
  fs.remove("worlds/" .. folder)
end

-- Seed z tekstu (jak w MC: liczba albo hash napisu)
function M.parseSeed(text)
  if not text or text == "" then
    return math.floor((os.time() * 7919 + math.floor((os.clock() * 1e6) % 1e6)) % 2147483646) + 1
  end
  local n = tonumber(text)
  if n then return math.floor(n) % 2147483646 end
  local h = 0
  for i = 1, #text do h = (h * 31 + text:byte(i)) % 2147483646 end
  return h
end

-- ---------------------------------------------------------------------------
-- Zapis i odczyt stanu gry
-- ---------------------------------------------------------------------------
local function serializeEntity(e)
  if e.type == "mob" and e.kind == "dragon" then return nil end
  if e.type == "mob" and not e.dead and e.health > 0 then
    return { t = "mob", kind = e.kind, x = e.x, y = e.y, z = e.z, yaw = e.yaw, health = e.health,
      tamed = e.tamed, sheared = e.sheared, color = e.color, growth = e.growth, sitting = e.sitting,
      charged = e.charged, persistent = e.persistent }
  elseif (e.type == "minecart" or e.type == "boat") and not e.dead then
    return { t = e.type, x = e.x, y = e.y, z = e.z, yaw = e.yaw }
  elseif e.type == "item" and not e.dead then
    return { t = "item", x = e.x, y = e.y, z = e.z, id = e.stack.id, count = e.stack.count,
      damage = e.stack.damage, ench = e.stack.ench, age = e.age }
  end
  return nil
end
M.serializeEntity = serializeEntity

-- Zbiera byty leżące w danym chunku (do zapisu z chunkiem)
function M.collectEntities(game, chunk, remove)
  local out = {}
  local x0, z0 = chunk.cx * 16, chunk.cz * 16
  for _, e in ipairs(game.entities.list) do
    if not e.dead and e.x >= x0 and e.x < x0 + 16 and e.z >= z0 and e.z < z0 + 16 then
      local s = serializeEntity(e)
      if s then
        out[#out + 1] = s
        if remove then e.dead = true; e.unloaded = true end
      end
    end
  end
  return out
end

-- Odtwarza byty zapisane w chunku
function M.restoreEntities(game, chunk)
  local list = chunk.savedEntities
  chunk.savedEntities = nil
  if not list then return end
  local mobs = require("core.mobs")
  local entities = require("core.entities")
  for _, s in ipairs(list) do
    if s.t == "mob" and mobs.DEFS[s.kind] then
      local e = mobs.spawn(game, s.kind, s.x, s.y, s.z)
      e.yaw, e.prevYaw = s.yaw or 0, s.yaw or 0
      e.health = s.health or e.health
      e.tamed, e.sheared, e.color, e.growth = s.tamed, s.sheared, s.color or e.color, s.growth
      e.sitting, e.charged = s.sitting, s.charged
      if s.persistent ~= nil then e.persistent = s.persistent end
      if e.tamed then e.owner = game.player; e.maxHealth = 20 end
    elseif s.t == "minecart" or s.t == "boat" then
      local vehicles = require("core.vehicles")
      if s.t == "minecart" then vehicles.spawnMinecart(game, s.x, s.y, s.z)
      else vehicles.spawnBoat(game, s.x, s.y, s.z, s.yaw) end
    elseif s.t == "item" then
      local e = entities.newItem(s.x, s.y, s.z, { id = s.id, count = s.count, damage = s.damage, ench = s.ench }, 0, 0, 0)
      e.age = s.age or 0
      e.pickupDelay = 0
      game.entities:add(e)
    end
  end
end

function M.levelData(game)
  local p = game.player
  return {
    version = M.VERSION, name = game.name, seed = game.seed, gameMode = p.gameMode,
    dimension = game.dimension,
    difficulty = game.difficulty, hardcore = game.hardcore, time = game.time,
    dayTime = game.dayTime, lastPlayed = os.time(), dead = game.dead,
    nextMapId = game.nextMapId, endState = game.endState,
    weather = { raining = game.weather.raining, thunder = game.weather.thunder,
      timer = game.weather.timer },
    worldSpawn = { game.worldSpawnX, game.worldSpawnY, game.worldSpawnZ },
    bedSpawn = game.spawnX and { game.spawnX, game.spawnY, game.spawnZ } or nil,
    player = {
      x = p.x, y = p.y, z = p.z, yaw = p.yaw, pitch = p.pitch, flying = p.flying,
      health = game.health, food = game.food, saturation = game.saturation,
      exhaustion = game.exhaustion, xpLevel = game.xpLevel, xpPoints = game.xpPoints,
      xpTotal = game.xpTotal, air = game.air, fireTicks = game.fireTicks,
      selected = game.selected, effects = game.effects,
    },
    inventory = game.inventory:serialize(),
    armor = game.armor:serialize(),
    stats = game.stats,
  }
end

function M.saveLevel(folder, game)
  fs.write("worlds/" .. folder .. "/level.lua", serialize.encode(M.levelData(game)))
end

function M.loadLevel(folder)
  local text = fs.read("worlds/" .. folder .. "/level.lua")
  return text and serialize.decode(text)
end

-- Przywraca stan gry z danych poziomu (po utworzeniu Game z tym samym seedem)
function M.applyLevel(game, data)
  game.name = data.name or game.name
  game.difficulty = data.difficulty or game.difficulty
  game.hardcore = data.hardcore or false
  game.time = data.time or 0
  game.dayTime = data.dayTime or 1000
  game.nextMapId = data.nextMapId or 0
  game.endState = data.endState
  if data.weather then
    game.weather.raining = data.weather.raining or false
    game.weather.thunder = data.weather.thunder or false
    game.weather.timer = data.weather.timer or 12000
    game.weather.strength = game.weather.raining and 1 or 0
  end
  local ws = data.worldSpawn
  if ws then game.worldSpawnX, game.worldSpawnY, game.worldSpawnZ = ws[1], ws[2], ws[3] end
  local bs = data.bedSpawn
  if bs then game.spawnX, game.spawnY, game.spawnZ = bs[1], bs[2], bs[3] end
  local p = game.player
  local d = data.player or {}
  p.gameMode = data.gameMode or p.gameMode
  p.x, p.y, p.z = d.x or p.x, d.y or p.y, d.z or p.z
  p.prevX, p.prevY, p.prevZ = p.x, p.y, p.z
  p.yaw, p.pitch = d.yaw or 0, d.pitch or 0
  p.flying = d.flying or false
  game.health = d.health or 20
  game.food = d.food or 20
  game.saturation = d.saturation or 5
  game.exhaustion = d.exhaustion or 0
  game.xpLevel = d.xpLevel or 0
  game.xpPoints = d.xpPoints or 0
  game.xpTotal = d.xpTotal or 0
  game.air = d.air or 300
  game.fireTicks = d.fireTicks or 0
  game.selected = d.selected or 1
  game.effects = d.effects or {}
  game.inventory:deserialize(data.inventory)
  game.armor:deserialize(data.armor)
  game.stats = data.stats or {}
  game.dead = data.dead or false
  game.savedDimension = data.dimension
end

return M
