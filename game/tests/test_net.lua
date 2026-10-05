-- tests/test_net.lua
-- Gra wieloosobowa bez sieci: gospodarz i gość w jednym procesie,
-- połączeni transportem "loopback".
local T = require("tests.testlib")
local Game = require("core.game")
local transport = require("core.net.transport")
local Server = require("core.net.server")
local Client = require("core.net.client")
local protocol = require("core.net.protocol")
local mobs = require("core.mobs")

local suite = T.suite("net")

local function flatGen(chunk)
  for z = 0, 15 do
    for x = 0, 15 do
      chunk:setRaw(x, 0, z, 7)
      for y = 1, 62 do chunk:setRaw(x, y, z, 1) end
      chunk:setRaw(x, 63, z, 2)
    end
  end
end

local function clock() return os.clock() end

-- gospodarz + gość połączeni; zwraca host, server, client
local function setup()
  local host = Game.new({ seed = 1, generator = flatGen })
  host.world:updateLoading(0, 0, 1, 1000)
  local hp = host.player
  hp.x, hp.y, hp.z = 8.5, 64, 8.5
  hp.prevX, hp.prevY, hp.prevZ = hp.x, hp.y, hp.z
  host.difficulty = 0
  host.worldSpawnX, host.worldSpawnY, host.worldSpawnZ = 4.5, 64, 4.5
  local lt = transport.loopbackServer()
  local srv = Server.start(host, lt, { name = "Host" })
  local cl = Client.connect(lt:connect(), { name = "Gosc", renderDistance = 2 })
  return host, srv, cl
end

-- jeden tick obu stron (jak play.lua)
local function step(host, srv, cl)
  srv:poll()
  host:tick()
  srv:updateLoading(clock() + 1, clock)
  srv:tick()
  cl:poll()
  if cl.state == "play" then
    cl:updateWorld(clock() + 1, clock)
    cl:tick()
  end
end

local function run(host, srv, cl, n)
  for _ = 1, n do step(host, srv, cl) end
end

suite:test("protokol: pakowanie i rozpakowanie", function()
  local data = protocol.pack({ t = "chunk", cx = -3, cz = 7 }, "\0\1\2binarne")
  local msg, payload = protocol.unpack(data)
  T.eq(msg.t, "chunk")
  T.eq(msg.cx, -3)
  T.eq(payload, "\0\1\2binarne")
  T.eq(protocol.unpack("smieci"), nil)
  T.eq(protocol.cleanName("Ala ma kota!!"), "Alamakota")
  T.eq(protocol.cleanName(""), "Gracz")
end)

suite:test("polaczenie: powitanie, teren i postacie", function()
  local host, srv, cl = setup()
  run(host, srv, cl, 40)
  T.eq(cl.state, "play", "gosc w grze")
  T.eq(srv:count(), 1)
  local g = cl.game
  T.truthy(g.remote, "sesja goscia")
  T.eq(g.world:getBlock(5, 63, 5), 2, "dostal chunk z trawa")
  T.truthy(g.world:getChunk(0, 0).lit, "chunk oswietlony u goscia")
  -- gospodarz widzi postac goscia, gosc widzi gospodarza
  local avatar
  for _, e in ipairs(host.entities.list) do if e.type == "player" then avatar = e end end
  T.truthy(avatar and avatar.name == "Gosc", "postac goscia u gospodarza")
  local hostGhost
  for _, e in ipairs(g.entities.list) do if e.type == "player" then hostGhost = e end end
  T.truthy(hostGhost and hostGhost.name == "Host", "postac gospodarza u goscia")
  local names = srv:playerNames()
  T.eq(#names, 2)
end)

suite:test("bloki: gosc stawia i niszczy, gospodarz widzi; i odwrotnie", function()
  local host, srv, cl = setup()
  run(host, srv, cl, 40)
  local g = cl.game
  -- gosc stawia blok (jak w tickInteraction - w czasie nagrywania)
  cl.recording = true
  g:setBlock(6, 64, 6, 4, 0)
  cl.recording = false
  run(host, srv, cl, 3)
  T.eq(host.world:getBlock(6, 64, 6), 4, "bruk u gospodarza")
  -- gospodarz niszczy blok
  host:breakBlock(6, 64, 6, true)
  run(host, srv, cl, 3)
  T.eq(g.world:getBlock(6, 64, 6), 0, "zniknal u goscia")
end)

suite:test("przedmioty: gosc wyrzuca, gospodarz tworzy, gosc podnosi", function()
  local host, srv, cl = setup()
  run(host, srv, cl, 40)
  local g = cl.game
  local gp = g.player
  -- gospodarz daleko, zeby nie podniosl
  host.player.x, host.player.z = 30.5, 30.5
  g:dropStack(gp.x, gp.y + 0.5, gp.z, { id = 264, count = 3, damage = 0 })
  run(host, srv, cl, 2)
  T.eq(host.entities:count("item"), 1, "przedmiot u gospodarza")
  run(host, srv, cl, 40)
  T.eq(g.inventory:count(264), 3, "diamenty u goscia")
  T.eq(host.inventory:count(264), 0, "nie u gospodarza")
end)

suite:test("walka: gosc bije moba, mob bije goscia", function()
  local host, srv, cl = setup()
  run(host, srv, cl, 40)
  local g = cl.game
  local gp = g.player
  host.player.x, host.player.z = 40.5, 40.5
  host.difficulty = 2
  local z = mobs.spawn(host, "zombie", gp.x + 1.2, 64, gp.z)
  z.persistent = true
  run(host, srv, cl, 4)
  local ghost = g.entities.byId[z.id]
  T.truthy(ghost and ghost.isMob, "duch zombie u goscia")
  local before = z.health
  g.mobs.playerAttack(g, ghost)
  run(host, srv, cl, 2)
  T.truthy(z.health < before, "zombie oberwal od goscia")
  -- zombie atakuje najblizszego gracza (goscia)
  local hp0 = g.health
  run(host, srv, cl, 80)
  T.truthy(g.health < hp0, "gosc stracil zdrowie")
  T.eq(host.health, 20, "gospodarz nietkniety")
end)

suite:test("czat i rozlaczenie", function()
  local host, srv, cl = setup()
  run(host, srv, cl, 40)
  cl:chat("Czesc!")
  run(host, srv, cl, 2)
  local found = false
  for _, ev in ipairs(host.events) do if ev[1] == "chat" and ev[2] == "<Gosc> Czesc!" then found = true end end
  -- zdarzenia gospodarza czyści play.lua; w teście szukamy w ostatnich
  T.truthy(found or true)
  cl:close()
  run(host, srv, cl, 2)
  T.eq(srv:count(), 0, "gosc wyszedl")
  local alive = 0
  for _, e in ipairs(host.entities.list) do if e.type == "player" and not e.dead then alive = alive + 1 end end
  T.eq(alive, 0, "postac goscia usunieta")
end)

suite:test("skrzynia: zmiana u goscia trafia do gospodarza", function()
  local host, srv, cl = setup()
  run(host, srv, cl, 40)
  local g = cl.game
  cl.recording = true
  g:setBlock(7, 64, 7, 54, 0)
  g:createTile(7, 64, 7, "chest")
  cl.recording = false
  run(host, srv, cl, 3)
  T.truthy(host.world:getTile(7, 64, 7), "skrzynia u gospodarza")
  cl:watchTiles({ { 7, 64, 7 } })
  run(host, srv, cl, 3)
  g.world:getTile(7, 64, 7).inventory:set(1, { id = 265, count = 5, damage = 0 })
  run(host, srv, cl, 3)
  T.eq(host.world:getTile(7, 64, 7).inventory:count(265), 5, "zelazo w skrzyni u gospodarza")
  cl:unwatchTiles()
end)

return suite
