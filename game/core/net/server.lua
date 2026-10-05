-- core/net/server.lua
-- Serwer gry wieloosobowej działający w grze gospodarza ("Otwórz w sieci LAN").
-- Gospodarz ma jedyną prawdziwą kopię świata: generuje teren, symuluje
-- ciecze, redstone, moby i przedmioty. Goście dostają chunki i zmiany bloków,
-- a sami liczą tylko ruch swojej postaci, ekwipunek, głód i zdrowie.
--
-- Moby i przedmioty obsługują wielu graczy przez "podmianę kontekstu":
-- na czas ticku bytu game.player wskazuje najbliższego gracza (gospodarza
-- albo gościa). Obrażenia, podniesione przedmioty i XP dla gościa trafiają
-- wtedy do niego przez sieć (patrz game.remoteCtx w game.lua i survival.lua).
--
-- Gracze mogą być w różnych wymiarach (świat, Nether, End). Gospodarz trzyma
-- wtedy kilka światów naraz, a na czas obsługi gościa podmienia też wymiar
-- (game:withDimension). Wymiar gospodarza tickuje sam game:tick, pozostałe
-- (te, w których są goście) - Server:tick.

local protocol = require("core.net.protocol")
local Player = require("core.player")
local entities = require("core.entities")
local blocks = require("core.blocks")
local items = require("core.items")
local save = require("core.save")
local serialize = require("core.serialize")
local World = require("core.world")
local fs = require("core.fs")

local M = {}

local Server = {}
Server.__index = Server

local floor, sqrt, abs = math.floor, math.sqrt, math.abs
local pack = protocol.pack
local q = protocol.q

M.CHUNKS_PER_TICK = 3
M.ENTITY_RANGE = 80

-- game: sesja gospodarza; transport: z core.net.transport
function M.start(game, transport, opts)
  opts = opts or {}
  local self = setmetatable({}, Server)
  self.game = game
  self.transport = transport
  self.port = opts.port or protocol.PORT
  self.hostName = protocol.cleanName(opts.name or "Gospodarz")
  -- serwer dedykowany: gospodarz nie gra (nie ma postaci, moby go nie widzą)
  self.dedicated = opts.dedicated or false
  self.maxPlayers = opts.maxPlayers or protocol.MAX_PLAYERS
  self.log = opts.log
  self.peers = {}          -- id -> kontekst gracza
  self.pendingBlocks = {}  -- wymiar -> zmiany bloków do rozesłania w tym ticku
  self.hooked = {}         -- wymiary, których słuchamy
  self.ticks = 0
  game.netServer = self
  game.net = self
  -- nowe wymiary podłącza game:setDimension (przez hookDimension)
  for dim in pairs(game.worlds) do self:hookDimension(dim) end
  return self
end

-- Słuchanie zmian bloków i tick bytów (z podmianą kontekstu gracza) w wymiarze
function Server:hookDimension(dim)
  local game = self.game
  local world, mgr = game.worlds[dim], game.entitiesByDim[dim]
  if not world then return end
  if self.hooked[dim] ~= world then
    self.hooked[dim] = world
    world:addListener(self)
  end
  if dim == game.dimension then mgr = game.entities end
  if mgr and not mgr.netHooked then
    mgr.netHooked = true
    mgr.tick = function(m) self:tickEntities(m, dim) end
  end
end

-- Świat wymiaru (tworzy go, jeśli jeszcze nie istnieje)
function Server:worldOf(dim)
  local game = self.game
  if not game.worlds[dim] then game:withDimension(dim, function() end) end
  self:hookDimension(dim)
  return game.worlds[dim]
end

function Server:entitiesOf(dim)
  self:worldOf(dim)
  local game = self.game
  return dim == game.dimension and game.entities or game.entitiesByDim[dim]
end

function Server:stop(reason)
  for id in pairs(self.peers) do
    self.transport:send(id, pack({ t = "kick", reason = reason or "Gospodarz zamknal swiat" }))
  end
  if self.transport.flush then self.transport:flush() end
  for _, ctx in pairs(self.peers) do self:savePlayer(ctx) end
  self.transport:close()
  for _, ctx in pairs(self.peers) do if ctx.avatar then ctx.avatar.dead = true end end
  self.peers = {}
  local game = self.game
  for _, world in pairs(self.hooked) do
    local l = world.listeners
    for i = #l, 1, -1 do if l[i] == self then table.remove(l, i) end end
  end
  self.hooked = {}
  for _, mgr in pairs(game.entitiesByDim) do
    if mgr.netHooked then mgr.tick, mgr.netHooked = nil, nil end
  end
  self.game.netServer = nil
  self.game.net = nil
end

function Server:count()
  local n = 0
  for _, ctx in pairs(self.peers) do if ctx.state == "play" then n = n + 1 end end
  return n
end

function Server:playerNames()
  local list = {}
  if not self.dedicated then list[1] = self.hostName end
  for _, ctx in pairs(self.peers) do
    if ctx.state == "play" then list[#list + 1] = ctx.name end
  end
  return list
end

function Server:send(ctx, msg, payload)
  self.transport:send(ctx.id, pack(msg, payload))
end

function Server:broadcast(msg, except)
  local data = pack(msg)
  for id, ctx in pairs(self.peers) do
    if ctx.state == "play" and ctx ~= except then self.transport:send(id, data) end
  end
end

-- Wiadomość na czacie u wszystkich (i u gospodarza)
function Server:announce(text, except)
  self:broadcast({ t = "chat", text = text }, except)
  self.game:emit("chat", text)
end

-- ---------------------------------------------------------------------------
-- Podmiana kontekstu gracza
-- ---------------------------------------------------------------------------
function Server:withCtx(ctx, fn, ...)
  local g = self.game
  local p, dead, rc = g.player, g.dead, g.remoteCtx
  g.player, g.dead, g.remoteCtx = ctx.player, ctx.dead, ctx
  local ok, err = pcall(fn, ...)
  g.player, g.dead, g.remoteCtx = p, dead, rc
  if not ok then error(err, 0) end
end

-- Najbliższy gość w wymiarze dim, jeśli jest bliżej niż gospodarz (inaczej nil)
function Server:nearestRemote(e, dim)
  local g = self.game
  dim = dim or g.dimension
  local best, bestD = nil, math.huge
  -- wymiar, w którym naprawdę jest gospodarz (game:withDimension go podmienia)
  if not self.dedicated and not g.dead and (g.realDimension or g.dimension) == dim then
    local p = g.player
    bestD = (p.x - e.x) ^ 2 + (p.y - e.y) ^ 2 + (p.z - e.z) ^ 2
  end
  for _, ctx in pairs(self.peers) do
    if ctx.state == "play" and not ctx.dead and ctx.dim == dim then
      local p = ctx.player
      local d = (p.x - e.x) ^ 2 + (p.y - e.y) ^ 2 + (p.z - e.z) ^ 2
      if d < bestD then best, bestD = ctx, d end
    end
  end
  return best
end

-- Zastępuje Manager:tick w każdym wymiarze
function Server:tickEntities(mgr, dim)
  local game = self.game
  local list = mgr.list
  local hasRemote = self:count() > 0
  for i = 1, #list do
    local e = list[i]
    if not e.dead then
      e.prevX, e.prevY, e.prevZ, e.prevYaw = e.x, e.y, e.z, e.yaw
      e.age = e.age + 1
      local fn = entities.TICK[e.type]
      if fn then
        local ctx = hasRemote and self:nearestRemote(e, dim)
        if ctx then self:withCtx(ctx, fn, game, e) else fn(game, e) end
      end
      if e.y < -64 then e.dead = true end
    end
  end
  local j = 1
  for i = 1, #list do
    local e = list[i]
    if not e.dead then
      list[j] = e
      j = j + 1
    elseif e.onRemove then
      e.onRemove(game, e)
    end
  end
  for i = j, #list do list[i] = nil end
end

-- Wywoływane z game.lua / survival.lua, gdy game.remoteCtx jest ustawiony
function Server:giveTo(ctx, stack)
  self:send(ctx, { t = "give", id = stack.id, count = stack.count, damage = stack.damage or 0,
    ench = stack.ench })
  return 0
end

function Server:xpTo(ctx, n)
  self:send(ctx, { t = "xp", n = n })
end

function Server:hurt(ctx, amount, source, attacker)
  if ctx.dead or ctx.player.gameMode == "creative" and source ~= "void" then return false end
  local msg = { t = "hurt", a = amount, s = source }
  if attacker and attacker.x then msg.ax, msg.az = q(attacker.x), q(attacker.z) end
  if attacker and attacker.label then msg.l = attacker.label end
  self:send(ctx, msg)
  return true
end

-- Wybuch blisko gościa: obrażenia jak w mobs.explode (dla gospodarza liczy je sam wybuch)
function Server:explosionDamage(x, y, z, power, dim)
  local radius = power * 2
  for _, ctx in pairs(self.peers) do
    if ctx.state == "play" and not ctx.dead and ctx.dim == (dim or "overworld") then
      local p = ctx.player
      local dx, dy, dz = p.x - x, p.y + 0.9 - y, p.z - z
      local dist = sqrt(dx * dx + dy * dy + dz * dz)
      if dist < radius and dist > 0.001 then
        local impact = 1 - dist / radius
        local dmg = floor((impact * impact + impact) / 2 * 8 * power + 1)
        self:hurt(ctx, dmg, "explosion")
        self:send(ctx, { t = "push", vx = q(dx / dist * impact), vy = q(dy / dist * impact),
          vz = q(dz / dist * impact) })
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Zmiany bloków (słuchacz świata)
-- ---------------------------------------------------------------------------
function Server:onBlockChanged(world, x, y, z, oldId, newId, oldMeta, newMeta)
  local dim = world.dimension or "overworld"
  if self.hooked[dim] ~= world then return end
  local pb = self.pendingBlocks[dim]
  if not pb then pb = {}; self.pendingBlocks[dim] = pb end
  local n = #pb
  pb[n + 1], pb[n + 2], pb[n + 3], pb[n + 4], pb[n + 5] = x, y, z, newId, newMeta or 0
end

-- Zmiany od gościa: stawiamy bloki z powiadomieniem sąsiadów, ale bez dropów
-- (gość sam je stworzył i przysłał jako byty)
function Server:applyBlocks(ctx, list)
  self.game:withDimension(ctx.dim, self.applyBlocksHere, self, list)
end

function Server:applyBlocksHere(list)
  local game = self.game
  local world = game.world
  local redstone = require("core.redstone")
  game.suppressDrops = true
  local ok, err = pcall(function()
    -- najpierw wszystkie bloki, potem sąsiedzi: łóżko i drzwi przychodzą
    -- jako dwie połówki i pierwsza nie może się zniszczyć przed drugą
    local changed = {}
    for i = 1, #list - 4, 5 do
      local x, y, z, id, meta = list[i], list[i + 1], list[i + 2], list[i + 3], list[i + 4]
      local def = blocks.defs[id]
      if type(x) == "number" and (id == 0 or def) and world:isLoadedAt(x, z) then
        local old = world:getBlock(x, y, z)
        local oldDef = blocks.defs[old]
        if world:setBlock(x, y, z, id, meta) then
          if old ~= id then
            if def and def.tileEntity and not world:getTile(x, y, z) then
              game:createTile(x, y, z, def.tileEntity)
            end
            if def and def.liquid then game:scheduleTick(x, y, z, 5) end
            if def and def.gravity then game:scheduleTick(x, y, z, 2) end
          end
          changed[#changed + 1] = { x, y, z, (def and def.redstone) or (oldDef and oldDef.redstone) }
        end
      end
    end
    for _, c in ipairs(changed) do
      game:notifyNeighbors(c[1], c[2], c[3])
      if c[4] then redstone.notifyAround(game, c[1], c[2], c[3]) end
    end
  end)
  game.suppressDrops = false
  if not ok then error(err, 0) end
end

-- ---------------------------------------------------------------------------
-- Gracze
-- ---------------------------------------------------------------------------
local function uniqueName(self, name)
  local base, n = name, 1
  local function taken(nm)
    if nm == self.hostName and not self.dedicated then return true end
    for _, c in pairs(self.peers) do if c.name == nm and c.state == "play" then return true end end
    return false
  end
  while taken(name) do
    n = n + 1
    name = base:sub(1, 13) .. n
  end
  return name
end

function Server:playerFile(name)
  if not self.game.saveFolder then return nil end
  return "worlds/" .. self.game.saveFolder .. "/players/" .. name .. ".lua"
end

function Server:savePlayer(ctx)
  local path = ctx.state == "play" and ctx.pdata and self:playerFile(ctx.name)
  if path then
    ctx.pdata.dim = ctx.dim ~= "overworld" and ctx.dim or nil
    fs.write(path, serialize.encode(ctx.pdata))
  end
end

function Server:handleHello(ctx, msg)
  if msg.v ~= protocol.VERSION then
    self:send(ctx, { t = "kick", reason = "Inna wersja gry" })
    self.transport:kick(ctx.id)
    return
  end
  if self:count() >= self.maxPlayers then
    self:send(ctx, { t = "kick", reason = "Serwer jest pelny" })
    self.transport:kick(ctx.id)
    return
  end
  local game = self.game
  ctx.name = uniqueName(self, protocol.cleanName(msg.name))
  ctx.rd = math.max(2, math.min(8, tonumber(msg.rd) or 6))
  local sx, sy, sz = game.worldSpawnX, game.worldSpawnY, game.worldSpawnZ
  local dim = "overworld"
  -- zapisany stan gracza z poprzedniej wizyty
  local path = self:playerFile(ctx.name)
  local text = path and fs.read(path)
  local pdata = text and serialize.decode(text)
  if type(pdata) ~= "table" then pdata = nil end
  if pdata and pdata.player and pdata.player.x then
    sx, sy, sz = pdata.player.x, pdata.player.y, pdata.player.z
    if pdata.dim == "nether" or pdata.dim == "end" then dim = pdata.dim end
  end
  ctx.dim = dim
  ctx.pdata = pdata
  local p = Player.new(sx, sy, sz)
  p.gameMode = game.defaultGameMode or game.player.gameMode
  ctx.player = p
  ctx.cx, ctx.cz = floor(sx / 16), floor(sz / 16)
  ctx.sent = {}
  ctx.dead = false
  self:makeAvatar(ctx)
  ctx.state = "play"
  local w = game.weather
  self:send(ctx, {
    t = "welcome", id = ctx.id, name = ctx.name, world = game.name, seed = game.seed,
    gm = game.defaultGameMode or game.player.gameMode, diff = game.difficulty, day = game.dayTime,
    time = game.time, dedicated = self.dedicated or nil,
    spawn = { game.worldSpawnX, game.worldSpawnY, game.worldSpawnZ },
    pos = { sx, sy, sz }, r = w.raining, th = w.thunder, ws = w.strength,
    pdata = pdata, host = self.hostName, dim = dim ~= "overworld" and dim or nil,
  })
  self:announce(ctx.name .. " dolaczyl do gry")
end

-- Postać gościa widoczna dla innych (byt w wymiarze, w którym jest gość)
function Server:makeAvatar(ctx)
  if ctx.avatar then ctx.avatar.dead = true end
  local p = ctx.player
  local av = entities.base("player", p.x, p.y, p.z, 0.6, 1.8)
  av.kind, av.name = "player", ctx.name
  av.limb, av.limbSpeed, av.headPitch = 0, 0, 0
  av.tx, av.ty, av.tz, av.tyaw = p.x, p.y, p.z, p.yaw or 0
  av.yaw = p.yaw or 0
  ctx.avatar = av
  self:entitiesOf(ctx.dim):add(av)
end

-- Podróż gościa między wymiarami (portal, odrodzenie po śmierci w Netherze).
-- Cel liczy gospodarz: znajduje albo buduje portal po drugiej stronie.
function Server:travelPeer(ctx, msg)
  local game = self.game
  local kind = msg.kind
  local from = ctx.dim
  local p = ctx.player
  local target, x, y, z, fix
  local function spawnPoint()
    local sx, sy, sz = tonumber(msg.x), tonumber(msg.y), tonumber(msg.z)
    if sx and sy and sz then return sx, sy, sz end
    return game.worldSpawnX, game.worldSpawnY, game.worldSpawnZ
  end
  if kind == "nether" then
    if from == "end" then return end
    local tx, tz
    target, tx, tz = require("core.portal").target(from, p.x, p.z)
    self:worldOf(target)
    x, y, z = game:withDimension(target, require("core.portal").arrive, game, tx, tz)
  elseif kind == "end" then
    if from == "end" then
      target = "overworld"
      x, y, z = spawnPoint()
      fix = true
    elseif from == "overworld" then
      target = "end"
      self:worldOf(target)
      x, y, z = game:withDimension(target, require("core.endportal").arrive, game)
    else
      return
    end
  elseif kind == "respawn" then
    if from == "overworld" then return end
    target = "overworld"
    x, y, z = spawnPoint()
    fix = true
  else
    return
  end
  self:movePeer(ctx, target, x, y, z, fix)
end

function Server:movePeer(ctx, dim, x, y, z, fix)
  self:worldOf(dim)
  ctx.dim = dim
  local p = ctx.player
  p.x, p.y, p.z = x, y, z
  ctx.cx, ctx.cz = floor(x / 16), floor(z / 16)
  ctx.sent = {}
  ctx.watch = nil
  self:makeAvatar(ctx)
  self:send(ctx, { t = "dim", dim = dim, x = x, y = y, z = z, fix = fix or nil })
end

-- Wyrzucenie gracza po nicku (konsola serwera)
function Server:kickName(name, reason)
  for id, ctx in pairs(self.peers) do
    if ctx.state == "play" and ctx.name:lower() == tostring(name):lower() then
      self:send(ctx, { t = "kick", reason = reason or "Wyrzucony przez serwer" })
      if self.transport.flush then self.transport:flush() end
      self:removePeer(id, "wyrzucony")
      self.transport:kick(id)
      return true
    end
  end
  return false
end

function Server:removePeer(id, reason)
  local ctx = self.peers[id]
  if not ctx then return end
  self.peers[id] = nil
  if ctx.state == "play" then
    self:savePlayer(ctx)
    ctx.avatar.dead = true
    self:announce(ctx.name .. " opuscil gre" .. (reason and (" (" .. reason .. ")") or ""))
  end
end

local function findEntity(mgr, id)
  for _, e in ipairs(mgr.list) do
    if e.id == id and not e.dead then return e end
  end
  return nil
end

function Server:handle(ctx, msg, payload)
  local t = msg.t
  if ctx.state ~= "play" then
    if t == "hello" then self:handleHello(ctx, msg) end
    return
  end
  local game = self.game
  -- pakiety wysłane jeszcze przed przejściem do innego wymiaru
  if msg.d and msg.d ~= ctx.dim and (t == "pos" or t == "b" or t == "spawn" or t == "attack"
    or t == "tileset" or t == "tileget") then
    return
  end
  if t == "pos" then
    local p = ctx.player
    p.x, p.y, p.z = protocol.dq(msg.x), protocol.dq(msg.y), protocol.dq(msg.z)
    p.yaw, p.pitch = protocol.dq(msg.yaw), protocol.dq(msg.pitch)
    p.onGround, p.sneaking, p.flying = msg.og or false, msg.sn or false, msg.fl or false
    p.gameMode = msg.gm == "creative" and "creative" or "survival"
    ctx.dead = msg.dead or false
    ctx.cx, ctx.cz = floor(p.x / 16), floor(p.z / 16)
    local av = ctx.avatar
    av.tx, av.ty, av.tz, av.tyaw = p.x, p.y, p.z, p.yaw
    av.headPitch = -p.pitch * 0.5
    av.sneaking = p.sneaking
    av.deadPlayer = ctx.dead
    if msg.ht then av.hurtTime = 10 end
  elseif t == "b" then
    if type(msg.l) == "table" then self:applyBlocks(ctx, msg.l) end
  elseif t == "spawn" then
    game:withDimension(ctx.dim, self.spawnFromClient, self, ctx, msg.e)
  elseif t == "attack" then
    local e = findEntity(self:entitiesOf(ctx.dim), msg.id)
    if e then game:withDimension(ctx.dim, self.withCtx, self, ctx, self.attackEntity, self, ctx, e, msg) end
  elseif t == "portal" then
    self:travelPeer(ctx, msg)
  elseif t == "chat" then
    local text = protocol.cleanChat(msg.text)
    if text ~= "" then self:announce("<" .. ctx.name .. "> " .. text) end
  elseif t == "tileget" then
    ctx.watch = {}
    for _, pos in ipairs(msg.l or {}) do
      if type(pos) == "table" then
        ctx.watch[#ctx.watch + 1] = { pos[1], pos[2], pos[3] }
        self:sendTile(ctx, pos[1], pos[2], pos[3])
      end
    end
  elseif t == "tileset" then
    game:withDimension(ctx.dim, function()
      local tile = game:getOrCreateTile(msg.x, msg.y, msg.z)
      if tile and tile.inventory and type(msg.inv) == "table" then
        tile.inventory:deserialize(msg.inv)
        game.world:getChunkAt(msg.x, msg.z).modified = true
      end
    end)
    for _, other in pairs(self.peers) do
      if other ~= ctx and other.watch and other.dim == ctx.dim then
        for _, w in ipairs(other.watch) do
          if w[1] == msg.x and w[2] == msg.y and w[3] == msg.z then self:sendTile(other, w[1], w[2], w[3]) end
        end
      end
    end
  elseif t == "tileclose" then
    ctx.watch = nil
  elseif t == "psave" then
    if type(msg.d) == "table" then ctx.pdata = msg.d end
  elseif t == "bye" then
    if type(msg.d) == "table" then ctx.pdata = msg.d end
    self:removePeer(ctx.id)
    self.transport:kick(ctx.id)
  end
end

function Server.attackEntity(self, ctx, e, msg)
  local game = self.game
  local mobs = require("core.mobs")
  if e.isVehicle then
    require("core.vehicles").attack(game, e)
    return
  end
  if e.isCrystal then
    require("core.dragon").destroyCrystal(game, e)
    return
  end
  if not e.isMob then return end
  local dmg = math.max(0, math.min(30, tonumber(msg.dmg) or 1))
  local p = ctx.player
  local kb = math.max(1, math.min(4, tonumber(msg.kb) or 1))
  if mobs.damageMob(game, e, dmg, "player", { x = p.x, z = p.z, knockback = kb }) then
    e.lastHitByPlayer = 100
    e.looting = math.max(0, math.min(3, tonumber(msg.loot) or 0))
    local fire = math.max(0, math.min(2, tonumber(msg.fire) or 0))
    if fire > 0 then e.fireTicks = math.max(e.fireTicks or 0, 80 * fire) end
    if e.def.neutral then e.angry = p; e.target = p end
    if e.kind == "wolf" and not e.tamed then e.angry = p end
    if e.kind == "pigman" then
      for _, o in ipairs(game.entities:near(e.x, e.y, e.z, 32, "mob")) do
        if o.kind == "pigman" then o.angry = p end
      end
    end
  end
end

-- Byt utworzony przez gościa (wyrzucony przedmiot, strzała, TNT, wagonik...)
function Server:spawnFromClient(ctx, s)
  if type(s) ~= "table" or not protocol.SPAWNABLE[s.type] then return end
  local game = self.game
  local x, y, z = tonumber(s.x), tonumber(s.y), tonumber(s.z)
  if not (x and y and z) then return end
  if s.type == "minecart" then
    require("core.vehicles").spawnMinecart(game, x, y, z)
    return
  elseif s.type == "boat" then
    require("core.vehicles").spawnBoat(game, x, y, z, s.yaw)
    return
  end
  local e = entities.base(s.type, x, y, z, s.width, s.height)
  for k, v in pairs(s) do
    if k ~= "id" and k ~= "dead" then e[k] = v end
  end
  e.prevX, e.prevY, e.prevZ = x, y, z
  if s.type == "item" then
    if type(s.stack) ~= "table" or not items.get(s.stack.id) then return end
    e.stack = { id = s.stack.id, count = math.max(1, math.min(64, s.stack.count or 1)),
      damage = s.stack.damage or 0, ench = type(s.stack.ench) == "table" and s.stack.ench or nil }
    e.pickupDelay = math.max(e.pickupDelay or 10, 10)
  elseif s.type == "arrow" or s.type == "snowball" or s.type == "egg" or s.type == "pearl"
    or s.type == "potion" then
    e.shooter = ctx.player
  elseif s.type == "falling" and not blocks.defs[s.block or -1] then
    return
  end
  e.age = 0
  game.entities:add(e)
end

function Server:sendTile(ctx, x, y, z)
  local game = self.game
  local tile = game:withDimension(ctx.dim, game.getOrCreateTile, game, x, y, z)
  if not tile or not tile.inventory then return end
  self:send(ctx, { t = "tile", x = x, y = y, z = z, kind = tile.kind, inv = tile.inventory:serialize(),
    burn = tile.burn, burnMax = tile.burnMax, cook = tile.cook, brew = tile.brew })
end

-- ---------------------------------------------------------------------------
-- Pętla
-- ---------------------------------------------------------------------------
-- Odbiór pakietów (wywoływane co tick, także w czasie pauzy)
function Server:poll()
  for _, ev in ipairs(self.transport:service()) do
    if ev.type == "connect" then
      self.peers[ev.peer] = { id = ev.peer, state = "login", name = "?", server = self }
    elseif ev.type == "disconnect" then
      self:removePeer(ev.peer, "rozlaczono")
    elseif ev.type == "receive" then
      local ctx = self.peers[ev.peer]
      if ctx then
        local msg, payload = protocol.unpack(ev.data)
        if msg then
          local ok, err = pcall(self.handle, self, ctx, msg, payload)
          if not ok then print("Blad pakietu od " .. tostring(ctx.name) .. ": " .. tostring(err)) end
        end
      end
    end
  end
end

-- Chunki wokół gości: generowanie po stronie gospodarza (z limitem czasu)
function Server:updateLoading(deadline, now)
  local game = self.game
  for _, ctx in pairs(self.peers) do
    if ctx.state == "play" then
      self:worldOf(ctx.dim)
      game:withDimension(ctx.dim, function()
        repeat
          local g, l = game.world:updateLoading(ctx.cx, ctx.cz, ctx.rd + 1, 1, 1)
        until (g == 0 and l == 0) or now() > deadline
      end)
    end
  end
  self.unloadTimer = (self.unloadTimer or 0) + 1
  if self.unloadTimer >= 20 then
    self.unloadTimer = 0
    self:unloadOtherDimensions()
  end
end

-- Wymiary bez gospodarza: chunki daleko od gości są zwalniane (zapis na
-- dysk), a wymiar bez nikogo - cały
function Server:unloadOtherDimensions()
  local game = self.game
  for dim, world in pairs(game.worlds) do
    if dim ~= game.dimension then
      local keep = self:keepAreas(dim)
      game:withDimension(dim, function()
        local removed
        if #keep == 0 then
          removed = world:unloadFar(0, 0, -1)
          -- nikt tu nie gra: zaplanowane aktualizacje i tak by przepadły
          game.scheduled, game.scheduledSet = {}, {}
        else
          removed = world:unloadFar(keep[1][1], keep[1][2], keep[1][3], keep)
        end
        if removed > 0 then game.entities:removeOutside(world) end
      end)
    end
  end
end

-- Środki obszarów, których nie wolno zwolnić (dla World:unloadFar)
function Server:keepAreas(dim)
  dim = dim or self.game.dimension
  local list = {}
  for _, ctx in pairs(self.peers) do
    if ctx.state == "play" and ctx.dim == dim then list[#list + 1] = { ctx.cx, ctx.cz, ctx.rd + 4 } end
  end
  return list
end

-- Najbliższe brakujące chunki dla gościa
local function sendChunks(self, ctx)
  local world = self:worldOf(ctx.dim)
  local r = ctx.rd + 1
  local sent = 0
  local spiral = World.spiral(r)
  for i = 1, #spiral do
    if sent >= M.CHUNKS_PER_TICK then break end
    local o = spiral[i]
    local cx, cz = ctx.cx + o[1], ctx.cz + o[2]
    local k = World.key(cx, cz)
    if not ctx.sent[k] then
      local c = world:getChunk(cx, cz)
      if c and c.generated then
        local data = fs.compress(save.encodeChunk(c))
        self:send(ctx, { t = "chunk", cx = cx, cz = cz }, data)
        ctx.sent[k] = true
        sent = sent + 1
      end
    end
  end
  -- zapominamy chunki daleko od gościa (on zwalnia je jeszcze dalej)
  if self.ticks % 20 == 0 then
    for k in pairs(ctx.sent) do
      local cx = floor(k / 65536) - 32768
      local cz = k % 65536 - 32768
      if abs(cx - ctx.cx) > ctx.rd + 3 or abs(cz - ctx.cz) > ctx.rd + 3 then ctx.sent[k] = nil end
    end
  end
end

local function sendBlocks(self, ctx)
  local pb = self.pendingBlocks[ctx.dim]
  if not pb or #pb == 0 then return end
  local out = {}
  local sentSet = ctx.sent
  for i = 1, #pb, 5 do
    local x, z = pb[i], pb[i + 2]
    if sentSet[World.key(floor(x / 16), floor(z / 16))] then
      local n = #out
      out[n + 1], out[n + 2], out[n + 3], out[n + 4], out[n + 5] = x, pb[i + 1], z, pb[i + 3], pb[i + 4]
    end
  end
  if #out > 0 then self:send(ctx, { t = "b", l = out }) end
end

local function sendEntities(self, ctx)
  local game = self.game
  local p = ctx.player
  local r2 = M.ENTITY_RANGE * M.ENTITY_RANGE
  local list = {}
  for _, e in ipairs(self:entitiesOf(ctx.dim).list) do
    if not e.dead and e ~= ctx.avatar then
      local dx, dz = e.x - p.x, e.z - p.z
      if dx * dx + dz * dz < r2 then list[#list + 1] = protocol.entityState(e) end
    end
  end
  -- gospodarz jako postać
  if game.dimension == ctx.dim and not self.dedicated then
    local hp = game.player
    list[#list + 1] = { -1, "player", q(hp.x), q(hp.y), q(hp.z), q(hp.yaw),
      { n = self.hostName, hp = q(-hp.pitch * 0.5), sn = hp.sneaking or nil,
        ht = (game.hurtTime or 0) > 0 and game.hurtTime or nil, dt = game.dead and 1 or nil } }
  end
  self:send(ctx, { t = "e", l = list })
end

-- Zdarzenia efektowne (wybuchy, pioruny, niszczenie bloków przez gospodarza)
local FX = { explosion = true, lightning = true, ["break"] = true }

-- Tick wymiaru, w którym nie ma gospodarza (ten liczy game:tick)
function Server:tickDimension(dim)
  local game = self.game
  game.entities:tick()
  if dim == "end" then
    -- smok goni najbliższego gościa
    for _, ctx in pairs(self.peers) do
      if ctx.state == "play" and ctx.dim == "end" then
        self:withCtx(ctx, require("core.dragon").tick, game)
        break
      end
    end
  end
  game:processScheduled()
  game:tickTiles()
end

function Server:tick()
  self.ticks = self.ticks + 1
  local game = self.game
  -- wygładzanie ruchu postaci gości
  for _, ctx in pairs(self.peers) do
    if ctx.state == "play" then
      local av = ctx.avatar
      av.x = av.x + (av.tx - av.x) * 0.5
      av.y = av.y + (av.ty - av.y) * 0.5
      av.z = av.z + (av.tz - av.z) * 0.5
      local dy = ((av.tyaw - av.yaw + math.pi) % (2 * math.pi)) - math.pi
      av.yaw = av.yaw + dy * 0.5
      local sp = sqrt((av.x - av.prevX) ^ 2 + (av.z - av.prevZ) ^ 2)
      av.limbSpeed = av.limbSpeed + (math.min(1, sp * 4) - av.limbSpeed) * 0.4
      av.limb = av.limb + sp * 3
      if (av.hurtTime or 0) > 0 then av.hurtTime = av.hurtTime - 1 end
    end
  end
  -- wymiary z gośćmi, ale bez gospodarza
  local others = {}
  for _, ctx in pairs(self.peers) do
    if ctx.state == "play" and ctx.dim ~= game.dimension then others[ctx.dim] = true end
  end
  for dim in pairs(others) do
    self:worldOf(dim)
    game:withDimension(dim, self.tickDimension, self, dim)
  end
  -- świat wokół gości żyje tak jak wokół gospodarza
  if self:count() > 0 then
    local mobs = require("core.mobs")
    local redstone = require("core.redstone")
    for _, ctx in pairs(self.peers) do
      if ctx.state == "play" then
        game:withDimension(ctx.dim, self.withCtx, self, ctx, function()
          if game.mobs then mobs.tick(game) end
          game:randomTicks()
          if ctx.player.onGround and not ctx.dead then redstone.checkPlate(game, ctx.player) end
        end)
      end
    end
  end
  -- efekty z tego ticku (każdy gość dostaje te ze swojego wymiaru)
  local fx = {}
  for _, ev in ipairs(game.events) do
    local dim = ev.dim or "overworld"
    if FX[ev[1]] then
      fx[dim] = fx[dim] or {}
      local l = fx[dim]
      l[#l + 1] = { ev[1], ev[2], ev[3], ev[4], ev[5], ev[6] }
    end
    if ev[1] == "explosion" then self:explosionDamage(ev[2], ev[3], ev[4], ev[5], dim) end
  end
  local w = game.weather
  for _, ctx in pairs(self.peers) do
    if ctx.state == "play" then
      sendChunks(self, ctx)
      sendBlocks(self, ctx)
      if fx[ctx.dim] then self:send(ctx, { t = "fx", l = fx[ctx.dim] }) end
      if self.ticks % 2 == 0 then sendEntities(self, ctx) end
      if self.ticks % 20 == 0 then
        self:send(ctx, { t = "time", day = game.dayTime, time = game.time, r = w.raining, th = w.thunder })
      end
      if ctx.watch and self.ticks % 10 == 0 then
        for _, pos in ipairs(ctx.watch) do
          local tile = self:worldOf(ctx.dim):getTile(pos[1], pos[2], pos[3])
          if tile and (tile.kind == "furnace" or tile.kind == "brewing") then
            self:sendTile(ctx, pos[1], pos[2], pos[3])
          end
        end
      end
    end
  end
  self.pendingBlocks = {}
end

return M
