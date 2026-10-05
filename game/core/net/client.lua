-- core/net/client.lua
-- Klient gry wieloosobowej (gość). Tworzy własną sesję Game bez generatora:
-- teren przychodzi od gospodarza chunk po chunku, światło liczymy lokalnie.
-- Gość sam porusza postacią, kopie i stawia (zmiany wysyła gospodarzowi),
-- ma swój ekwipunek, głód i zdrowie. Moby i przedmioty to "duchy" -
-- kopie stanu od gospodarza, które tylko płynnie się przesuwają.

local protocol = require("core.net.protocol")
local save = require("core.save")
local fs = require("core.fs")
local items = require("core.items")
local blocks = require("core.blocks")
local World = require("core.world")

local M = {}

local Client = {}
Client.__index = Client

local floor, sqrt, abs = math.floor, math.sqrt, math.abs
local pack, unpack_ = protocol.pack, protocol.unpack
local q, dq = protocol.q, protocol.dq

-- transport: z core.net.transport; opts: name, renderDistance
function M.connect(transport, opts)
  opts = opts or {}
  local self = setmetatable({}, Client)
  self.transport = transport
  self.name = protocol.cleanName(opts.name)
  self.rd = opts.renderDistance or 6
  self.state = "connecting"   -- connecting -> login -> play -> closed
  self.ticks = 0
  self.recorded = {}
  self.recording = false
  self.timeout = 0
  return self
end

function Client:send(msg, payload)
  if self.state == "closed" then return end
  self.transport:send(pack(msg, payload))
end

function Client:close(reason)
  if self.state == "closed" then return end
  if self.state == "play" then
    self:send({ t = "bye", d = self:playerData() })
    if self.transport.flush then self.transport:flush() end
  end
  self.transport:close()
  self.state = "closed"
  self.error = self.error or reason
end

function Client:playerNames()
  local list = {}
  for _, e in ipairs(self.game and self.game.entities.list or {}) do
    if e.type == "player" and e.name then list[#list + 1] = e.name end
  end
  list[#list + 1] = self.name
  return list
end

-- ---------------------------------------------------------------------------
-- Duchy bytów (kopie od gospodarza)
-- ---------------------------------------------------------------------------
local Ghosts = {}
Ghosts.__index = Ghosts

local function newGhosts(client, game)
  return setmetatable({ client = client, game = game, list = {}, byId = {} }, Ghosts)
end

-- Byt stworzony lokalnie (wyrzucony przedmiot, strzała...) idzie do gospodarza
function Ghosts:add(e)
  if e.ghost then
    self.list[#self.list + 1] = e
    self.byId[e.id] = e
    return e
  end
  local s = protocol.entitySpawn(e)
  if s then self.client:send({ t = "spawn", e = s }) end
  e.dead = true
  return e
end

function Ghosts:count(kind)
  local n = 0
  for _, e in ipairs(self.list) do
    if not e.dead and (not kind or e.type == kind) then n = n + 1 end
  end
  return n
end

function Ghosts:near(x, y, z, r, kind)
  local out = {}
  local r2 = r * r
  for _, e in ipairs(self.list) do
    if not e.dead and (not kind or e.type == kind) then
      local dx, dy, dz = e.x - x, e.y - y, e.z - z
      if dx * dx + dy * dy + dz * dz <= r2 then out[#out + 1] = e end
    end
  end
  return out
end

function Ghosts:removeOutside() end

-- Płynny ruch w stronę ostatniej pozycji od gospodarza
function Ghosts:tick()
  for _, e in ipairs(self.list) do
    e.prevX, e.prevY, e.prevZ, e.prevYaw = e.x, e.y, e.z, e.yaw
    e.age = e.age + 1
    e.x = e.x + (e.tx - e.x) * 0.5
    e.y = e.y + (e.ty - e.y) * 0.5
    e.z = e.z + (e.tz - e.z) * 0.5
    local dy = ((e.tyaw - e.yaw + math.pi) % (2 * math.pi)) - math.pi
    e.yaw = e.yaw + dy * 0.5
    if e.type == "mob" or e.type == "player" then
      local sp = sqrt((e.x - e.prevX) ^ 2 + (e.z - e.prevZ) ^ 2)
      e.limbSpeed = e.limbSpeed + (math.min(1, sp * 4) - e.limbSpeed) * 0.4
      e.limb = e.limb + sp * 3
    end
    if (e.localHurt or 0) > 0 then e.localHurt = e.localHurt - 1 end
  end
end

local function applyState(e, s, x, fresh)
  e.tx, e.ty, e.tz, e.tyaw = dq(s[3]), dq(s[4]), dq(s[5]), dq(s[6])
  if fresh then
    e.x, e.y, e.z, e.yaw = e.tx, e.ty, e.tz, e.tyaw
    e.prevX, e.prevY, e.prevZ, e.prevYaw = e.x, e.y, e.z, e.yaw
  end
  local t = e.type
  if t == "mob" then
    e.health = x.h or e.health
    e.hurtTime = x.ht or ((e.localHurt or 0) > 0 and e.localHurt or 0)
    e.deathTime = x.dt or 0
    e.growth = x.g
    e.color, e.sheared, e.tamed = x.c or 0, x.s, x.tm
    e.fuse = x.f or 0
    e.headPitch = x.hp and dq(x.hp) or nil
  elseif t == "item" then
    if x.st then e.stack = { id = x.st[1], count = x.st[2], damage = x.st[3] } end
  elseif t == "xp" then
    e.value = x.v or 1
  elseif t == "falling" then
    e.block, e.meta = x.b, x.m
  elseif t == "tnt" then
    e.fuse = x.f or 80
  elseif t == "arrow" then
    e.vx, e.vy, e.vz = dq(x.vx), dq(x.vy), dq(x.vz)
    e.stuck = x.sk
  elseif t == "minecart" or t == "boat" then
    e.hurtTime = x.ht or 0
  elseif t == "player" then
    e.name = x.n or e.name
    e.headPitch = dq(x.hp)
    e.sneaking = x.sn
    e.hurtTime = x.ht or 0
    e.deathTime = x.dt and 10 or 0
  end
end

function Ghosts:sync(list)
  local mobs = require("core.mobs")
  local seen = {}
  for _, s in ipairs(list) do
    if type(s) == "table" and type(s[1]) == "number" and type(s[2]) == "string" then
      local id, t = s[1], s[2]
      local x = s[7] or {}
      seen[id] = true
      local e = self.byId[id]
      local fresh = false
      if not e or e.type ~= t then
        if e then e.dead = true end
        e = { id = id, type = t, ghost = true, x = 0, y = 0, z = 0, yaw = 0, prevYaw = 0,
          vx = 0, vy = 0, vz = 0, age = 0, width = 0.25, height = 0.25, limb = 0, limbSpeed = 0,
          dead = false, spin = math.random() * math.pi * 2 }
        if t == "mob" then
          local d = mobs.DEFS[x.k]
          if not d then e = nil end
          if e then
            e.kind, e.def, e.label, e.isMob = x.k, d, d.label, true
            e.width, e.height, e.health = d.w, d.h, x.h or d.health
          end
        elseif t == "player" then
          e.kind, e.width, e.height = "player", 0.6, 1.8
        elseif t == "minecart" then
          e.isVehicle, e.width, e.height = true, 0.98, 0.7
        elseif t == "boat" then
          e.isVehicle, e.width, e.height = true, 1.5, 0.6
        elseif t == "falling" or t == "tnt" then
          e.width, e.height = 0.98, 0.98
        elseif t == "item" and not x.st then
          e = nil
        end
        if e then
          self.list[#self.list + 1] = e
          self.byId[id] = e
          fresh = true
        end
      end
      if e then applyState(e, s, x, fresh) end
    end
  end
  -- znikają byty, których gospodarz już nie przysłał
  local j = 1
  local l = self.list
  for i = 1, #l do
    local e = l[i]
    if seen[e.id] and not e.dead then
      l[j] = e
      j = j + 1
    else
      e.dead = true
      if self.byId[e.id] == e then self.byId[e.id] = nil end
    end
  end
  for i = j, #l do l[i] = nil end
end

-- ---------------------------------------------------------------------------
-- Sesja gry gościa
-- ---------------------------------------------------------------------------
-- Atak i interakcja z duchami idą do gospodarza
local function makeMobsProxy(client)
  local mobs = require("core.mobs")
  local proxy = setmetatable({}, { __index = mobs })
  proxy.tick = function() end
  proxy.lightningStrike = function() end
  proxy.interact = function() return false end
  proxy.playerAttack = function(game, e)
    local p = game.player
    if e.isVehicle then
      client:send({ t = "attack", id = e.id })
      return
    end
    local held = game:heldStack()
    local dmg = items.attackDamage(held)
    local crit = p.vy < 0 and not p.onGround and not p.inWater and p.fallDistance > 0
    if crit then
      dmg = dmg + game.rng:int(0, floor(dmg / 2) + 1)
      game:emit("particles", "crit", e.x, e.y + e.height * 0.7, e.z)
    end
    dmg = client.modifyDamage and client.modifyDamage(game, e, dmg) or dmg
    client:send({ t = "attack", id = e.id, dmg = dmg, kb = p.sprinting and 2 or 1 })
    e.localHurt = 10
    local hd = held and items.get(held.id)
    if hd and hd.maxDamage then game:damageHeld(hd.toolType == "sword" and 1 or 2) end
    game.survival.addExhaustion(game, 0.3)
    if p.sprinting then p.sprinting = false end
  end
  return proxy
end

function Client:startGame(w)
  local Game = require("core.game")
  local game = Game.new({ seed = w.seed, name = w.world or "Serwer", gameMode = w.gm,
    difficulty = w.diff, remote = true })
  game.dayTime, game.time = w.day or 1000, w.time or 0
  game.weather.raining, game.weather.thunder = w.r or false, w.th or false
  game.weather.strength = w.ws or 0
  if w.spawn then game.worldSpawnX, game.worldSpawnY, game.worldSpawnZ = w.spawn[1], w.spawn[2], w.spawn[3] end
  local p = game.player
  local pos = w.pos or w.spawn or { 0.5, 80, 0.5 }
  p.x, p.y, p.z = pos[1], pos[2], pos[3]
  p.prevX, p.prevY, p.prevZ = p.x, p.y, p.z
  if type(w.pdata) == "table" then
    self:applyPlayerData(game, w.pdata)
  elseif w.gm == "creative" then
    -- pierwsza wizyta w trybie kreatywnym: startowy zestaw bloków
    local start = { 1, 4, 3, 5, 17, 20, 45, 50, 58 }
    for i, id in ipairs(start) do game.inventory:set(i, { id = id, count = 64, damage = 0 }) end
  end
  game.renderDistance = self.rd
  local ghosts = newGhosts(self, game)
  game.entities = ghosts
  game.entitiesByDim.overworld = ghosts
  game.mobs = makeMobsProxy(self)
  game.netClient = self
  game.net = self
  game.world:addListener(self)
  self.game = game
  self.hostName = w.host
  self.playerName = w.name
  self.state = "play"
end

-- Stan gracza zapisywany u gospodarza (żeby po powrocie mieć swój ekwipunek)
function Client:playerData()
  local game = self.game
  if not game then return nil end
  local d = save.levelData(game)
  return { player = d.player, inventory = d.inventory, armor = d.armor, gameMode = d.gameMode,
    bedSpawn = d.bedSpawn }
end

function Client:applyPlayerData(game, d)
  local p = game.player
  local pd = d.player or {}
  p.yaw, p.pitch = pd.yaw or 0, pd.pitch or 0
  p.flying = pd.flying or false
  game.health = pd.health or 20
  game.food = pd.food or 20
  game.saturation = pd.saturation or 5
  game.xpLevel, game.xpPoints, game.xpTotal = pd.xpLevel or 0, pd.xpPoints or 0, pd.xpTotal or 0
  game.selected = pd.selected or 1
  game.inventory:deserialize(d.inventory)
  game.armor:deserialize(d.armor)
  if d.bedSpawn then game.spawnX, game.spawnY, game.spawnZ = d.bedSpawn[1], d.bedSpawn[2], d.bedSpawn[3] end
end

-- Słuchacz świata gościa: zapamiętuje zmiany zrobione przez gracza
function Client:onBlockChanged(world, x, y, z, oldId, newId, oldMeta, newMeta)
  if not self.recording then return end
  local r = self.recorded
  local n = #r
  r[n + 1], r[n + 2], r[n + 3], r[n + 4], r[n + 5] = x, y, z, newId, newMeta or 0
end

-- Chunk od gospodarza
function Client:receiveChunk(msg, payload)
  local game = self.game
  local data = payload and fs.decompress(payload)
  if not data then return end
  local chunk = save.decodeChunk(msg.cx, msg.cz, data)
  if not chunk then return end
  chunk.savedEntities = nil
  local world = game.world
  if world:getChunk(msg.cx, msg.cz) then
    world.chunks[World.key(msg.cx, msg.cz)] = nil
    world.chunkCount = world.chunkCount - 1
    -- sąsiedzi muszą przeliczyć siatki (ściany na granicy)
    for dz = -1, 1 do
      for dx = -1, 1 do
        local n = world:getChunk(msg.cx + dx, msg.cz + dz)
        if n then n.dirty = true end
      end
    end
  end
  chunk.generated = true
  chunk.dirty = true
  world:addChunk(chunk)
  self.chunksReceived = (self.chunksReceived or 0) + 1
end

-- Zmiany bloków od gospodarza: bez reakcji sąsiadów (te liczy gospodarz)
function Client:receiveBlocks(list)
  local game = self.game
  local world = game.world
  for i = 1, #list - 4, 5 do
    local x, y, z, id, meta = list[i], list[i + 1], list[i + 2], list[i + 3], list[i + 4]
    if type(x) == "number" and (id == 0 or blocks.defs[id]) then
      world:setBlock(x, y, z, id, meta)
      local def = blocks.defs[id]
      if def and def.tileEntity and not world:getTile(x, y, z) then game:createTile(x, y, z, def.tileEntity) end
    end
  end
end

function Client:receiveTile(msg)
  local game = self.game
  local tile = game:getOrCreateTile(msg.x, msg.y, msg.z)
  if not tile or not tile.inventory then return end
  local inv = tile.inventory
  local fresh = {}
  for _, e in ipairs(msg.inv or {}) do
    if type(e) == "table" and items.get(e[2]) then fresh[e[1]] = { id = e[2], count = e[3], damage = e[4] or 0 } end
  end
  for i = 1, inv.size do inv.slots[i] = fresh[i] end
  inv.changed = true
  tile.burn, tile.burnMax, tile.cook = msg.burn or tile.burn, msg.burnMax or tile.burnMax, msg.cook or tile.cook
  -- nie odsyłamy z powrotem tego, co właśnie przyszło
  if self.watch then
    for _, w in ipairs(self.watch) do
      if w[1] == msg.x and w[2] == msg.y and w[3] == msg.z then w.sig = self:tileSig(w) end
    end
  end
end

function Client:handle(msg, payload)
  local t = msg.t
  if t == "welcome" then
    if self.state == "login" then self:startGame(msg) end
    return
  elseif t == "kick" then
    self.error = msg.reason or "Rozlaczono"
    self:close()
    return
  end
  local game = self.game
  if not game then return end
  if t == "chunk" then
    self:receiveChunk(msg, payload)
  elseif t == "b" then
    if type(msg.l) == "table" then self:receiveBlocks(msg.l) end
  elseif t == "e" then
    if type(msg.l) == "table" then game.entities:sync(msg.l) end
  elseif t == "hurt" then
    local attacker
    if msg.ax then attacker = { x = dq(msg.ax), z = dq(msg.az), label = msg.l } end
    if msg.l and not attacker then attacker = { label = msg.l } end
    self.applyingHurt = true
    game.survival.damage(game, tonumber(msg.a) or 0, msg.s or "mob", attacker)
    self.applyingHurt = false
  elseif t == "push" then
    local p = game.player
    p.vx, p.vy, p.vz = p.vx + dq(msg.vx), p.vy + dq(msg.vy), p.vz + dq(msg.vz)
  elseif t == "give" then
    if items.get(msg.id) then
      game:giveItem({ id = msg.id, count = msg.count or 1, damage = msg.damage or 0 })
      local p = game.player
      game:emit("sound", "pop", p.x, p.y + 1, p.z)
      game.stats.collected = (game.stats.collected or 0) + (msg.count or 1)
    end
  elseif t == "xp" then
    game:addXp(tonumber(msg.n) or 0)
    local p = game.player
    game:emit("sound", "orb", p.x, p.y + 1, p.z)
  elseif t == "time" then
    game.dayTime, game.time = msg.day or game.dayTime, msg.time or game.time
    game.weather.raining, game.weather.thunder = msg.r or false, msg.th or false
  elseif t == "chat" then
    game:emit("chat", protocol.cleanChat(msg.text))
  elseif t == "fx" then
    for _, f in ipairs(msg.l or {}) do
      if type(f) == "table" then game:emit(f[1], f[2], f[3], f[4], f[5], f[6]) end
    end
  elseif t == "tile" then
    self:receiveTile(msg)
  end
end

-- Odbiór pakietów (co tick, także w czasie ładowania)
function Client:poll()
  if self.state == "closed" then return end
  for _, ev in ipairs(self.transport:service()) do
    if ev.type == "connect" then
      self.state = "login"
      self:send({ t = "hello", v = protocol.VERSION, name = self.name, rd = self.rd })
    elseif ev.type == "disconnect" then
      self.error = self.error or "Utracono polaczenie z gospodarzem"
      self.state = "closed"
      return
    elseif ev.type == "receive" then
      local msg, payload = unpack_(ev.data)
      if msg then
        local ok, err = pcall(self.handle, self, msg, payload)
        if not ok then print("Blad pakietu: " .. tostring(err)) end
        if self.state == "closed" then return end
      end
    end
  end
  if self.state == "connecting" then
    self.timeout = self.timeout + 1
    if self.timeout > 20 * 10 then
      self.error = "Nie mozna polaczyc sie z serwerem"
      self:close()
    end
  end
end

-- Oświetlanie i zwalnianie chunków u gościa (bez generowania)
function Client:updateWorld(deadline, now)
  local game = self.game
  local p = game.player
  local cx, cz = floor(p.x / 16), floor(p.z / 16)
  repeat
    local _, lit = game.world:updateLoading(cx, cz, self.rd, 0, 1)
  until lit == 0 or now() > deadline
  game.world:unloadFar(cx, cz, self.rd + 4)
end

-- Sygnatura zawartości obserwowanego pojemnika (do wykrywania zmian)
function Client:tileSig(w)
  local tile = self.game.world:getTile(w[1], w[2], w[3])
  if not tile or not tile.inventory then return "" end
  local parts = {}
  for i = 1, tile.inventory.size do
    local s = tile.inventory.slots[i]
    parts[i] = s and (s.id .. ":" .. s.count .. ":" .. (s.damage or 0)) or "-"
  end
  return table.concat(parts, ",")
end

-- Otwarto skrzynię/piec: pobierz aktualną zawartość od gospodarza
function Client:watchTiles(list)
  self.watch = list
  local l = {}
  for _, w in ipairs(list) do
    w.sig = self:tileSig(w)
    l[#l + 1] = { w[1], w[2], w[3] }
  end
  self:send({ t = "tileget", l = l })
end

function Client:unwatchTiles()
  if not self.watch then return end
  self:checkTiles()
  self.watch = nil
  self:send({ t = "tileclose" })
end

function Client:checkTiles()
  for _, w in ipairs(self.watch or {}) do
    local sig = self:tileSig(w)
    if sig ~= w.sig then
      w.sig = sig
      local tile = self.game.world:getTile(w[1], w[2], w[3])
      if tile and tile.inventory then
        self:send({ t = "tileset", x = w[1], y = w[2], z = w[3], inv = tile.inventory:serialize() })
      end
    end
  end
end

-- Tick gry gościa: logika gracza + wysyłka zmian
function Client:tick()
  local game = self.game
  self.ticks = self.ticks + 1
  self.recording = true
  local ok, err = pcall(game.tick, game)
  self.recording = false
  if not ok then error(err, 0) end
  if #self.recorded > 0 then
    self:send({ t = "b", l = self.recorded })
    self.recorded = {}
  end
  if self.watch then self:checkTiles() end
  if self.ticks % 2 == 0 then
    local p = game.player
    self:send({ t = "pos", x = q(p.x), y = q(p.y), z = q(p.z), yaw = q(p.yaw), pitch = q(p.pitch),
      og = p.onGround or nil, sn = p.sneaking or nil, fl = p.flying or nil, gm = p.gameMode,
      dead = game.dead or nil, ht = (game.hurtTime or 0) > 0 or nil })
  end
  if self.ticks % 600 == 0 then self:send({ t = "psave", d = self:playerData() }) end
end

function Client:chat(text)
  self:send({ t = "chat", text = protocol.cleanChat(text) })
end

return M
