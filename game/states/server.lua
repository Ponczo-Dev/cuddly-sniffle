-- states/server.lua
-- Serwer dedykowany: gra działa bez okna (np. na serwerze z publicznym IP),
-- gracze łączą się z menu "Gra wieloosobowa". Uruchomienie:
--   love game --server [--world=serwer] [--port=25565] [--seed=12345]
--                      [--mode=survival|creative] [--difficulty=0-3] [--max=8]
-- Konsola (wpisuj w terminalu): help, list, say <tekst>, kick <nick>, save, stop,
-- time set day|night, weather clear|rain|thunder, difficulty 0-3, seed.

local Game = require("core.game")
local save = require("core.save")
local fs = require("core.fs")
local commands = require("core.commands")
local transport = require("core.net.transport")
local protocol = require("core.net.protocol")
local NetServer = require("core.net.server")

local Server = {}

local floor = math.floor
local AUTOSAVE_TICKS = 20 * 60

local function log(fmt, ...)
  local text = select("#", ...) > 0 and string.format(fmt, ...) or fmt
  print(os.date("[%H:%M:%S] ") .. text)
end

local function argValue(args, name)
  for _, a in ipairs(args or {}) do
    local v = a:match("^%-%-" .. name .. "=(.*)$")
    if v then return v end
  end
  return nil
end

function Server:enter(params)
  pcall(function() io.stdout:setvbuf("line") end)
  params = params or {}
  self.manager = params.manager
  local args = params.args or {}
  local worldName = argValue(args, "world") or "serwer"
  local folder = worldName:gsub("[^%w%-_]", "_")
  local port = tonumber(argValue(args, "port")) or protocol.PORT
  local maxPlayers = tonumber(argValue(args, "max")) or protocol.MAX_PLAYERS
  self.folder = folder
  self.ticks = 0

  local data = save.loadLevel(folder)
  local game
  if data then
    game = Game.new({ seed = data.seed, name = data.name, gameMode = data.gameMode,
      difficulty = data.difficulty, saveFolder = folder })
    save.applyLevel(game, data)
    if game.savedDimension and game.savedDimension ~= "overworld" then game:setDimension("overworld") end
    game.defaultGameMode = data.gameMode or "survival"
    log("Wczytano swiat '%s' (seed %s)", folder, tostring(game.seed))
  else
    local seed = save.parseSeed(argValue(args, "seed"))
    local mode = argValue(args, "mode") == "creative" and "creative" or "survival"
    game = Game.new({ seed = seed, name = worldName, gameMode = mode,
      difficulty = tonumber(argValue(args, "difficulty")) or 2, saveFolder = folder })
    game.defaultGameMode = mode
    log("Tworzenie nowego swiata '%s' (seed %d, tryb %s)...", folder, seed, mode)
    local x, z = game:chooseSpawnColumn()
    local cx, cz = floor(x / 16), floor(z / 16)
    repeat
      local g, l = game.world:updateLoading(cx, cz, 2, 4)
    until g == 0 and l == 0
    local y = game:surfaceY(x, z)
    game.worldSpawnX, game.worldSpawnY, game.worldSpawnZ = x + 0.5, y, z + 0.5
  end
  local diff = tonumber(argValue(args, "difficulty"))
  if diff then game.difficulty = math.max(0, math.min(3, diff)) end
  game.dedicated = true
  -- "gospodarz" to niewidoczny obserwator wysoko nad punktem startu
  local p = game.player
  p.gameMode = "creative"
  p.flying = true
  p.x, p.y, p.z = game.worldSpawnX, 120, game.worldSpawnZ
  p.prevX, p.prevY, p.prevZ = p.x, p.y, p.z
  game.renderDistance = 3
  self.game = game

  local t, err = transport.enetServer(port, maxPlayers)
  if not t then
    log("BLAD: nie mozna otworzyc portu %d: %s", port, tostring(err))
    love.event.quit(1)
    return
  end
  self.net = NetServer.start(game, t, { name = "Serwer", port = port, dedicated = true,
    maxPlayers = maxPlayers })
  self:saveWorld()
  log("Serwer dziala na porcie %d (UDP), maks. %d graczy. Tryb: %s, trudnosc: %d", port, maxPlayers,
    game.defaultGameMode, game.difficulty)
  log("Gracze: menu 'Gra wieloosobowa' -> adres tego serwera (np. 1.2.3.4 albo 1.2.3.4:%d)", port)
  log("Wpisz 'help', aby zobaczyc komendy konsoli.")

  -- konsola: osobny wątek czyta linie z terminala
  self.console = love.thread.getChannel("serwer_konsola")
  local ok, thread = pcall(love.thread.newThread, [[
    require("love.thread")
    local ch = love.thread.getChannel("serwer_konsola")
    while true do
      local line = io.read("*l")
      if not line then break end
      ch:push(line)
    end
  ]])
  if ok and thread then thread:start() end
end

-- Zapis świata (stan gracza-obserwatora nie zmienia trybu gry świata)
function Server:saveWorld()
  local game = self.game
  if not game then return 0 end
  local p = game.player
  local mode = p.gameMode
  p.gameMode = game.defaultGameMode
  local n = game:saveAll()
  p.gameMode = mode
  if self.net then
    for _, ctx in pairs(self.net.peers) do self.net:savePlayer(ctx) end
  end
  return n
end

function Server:save()
  self:saveWorld()
end

-- Wywoływane przy wyłączaniu (komenda stop, Ctrl+C, systemd stop).
-- Kończymy proces od razu: wątek konsoli czeka na klawiaturę i LÖVE
-- czekałby na niego w nieskończoność.
function Server:closeNet()
  if self.net then
    self.net:stop("Serwer zostal zatrzymany")
    self.net = nil
  end
  log("Serwer zatrzymany.")
  io.stdout:flush()
  -- _exit pomija sprzątanie LÖVE, które czekałoby na wątek konsoli
  -- (świat jest już zapisany, połączenia zamknięte)
  local ok, ffi = pcall(require, "ffi")
  if ok then
    pcall(ffi.cdef, "void _exit(int status);")
    pcall(function() ffi.C._exit(0) end)
  end
  os.exit(0)
end

-- ---------------------------------------------------------------------------
-- Komendy konsoli
-- ---------------------------------------------------------------------------
local HELP = {
  "list                      - gracze na serwerze",
  "say <tekst>               - wiadomosc do wszystkich",
  "kick <nick>               - wyrzucenie gracza",
  "save                      - zapis swiata",
  "stop                      - zapis i wylaczenie serwera",
  "time set day|night|<n>    - pora dnia",
  "weather clear|rain|thunder, difficulty 0-3, seed",
}

function Server:command(line)
  line = line:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^/", "")
  if line == "" then return end
  local cmd, rest = line:match("^(%S+)%s*(.*)$")
  cmd = cmd:lower()
  local net, game = self.net, self.game
  if cmd == "help" or cmd == "?" then
    for _, l in ipairs(HELP) do print("  " .. l) end
  elseif cmd == "list" then
    local names = net and net:playerNames() or {}
    log("Gracze (%d): %s", #names, #names > 0 and table.concat(names, ", ") or "-")
  elseif cmd == "say" then
    if net and rest ~= "" then net:announce("[Serwer] " .. protocol.cleanChat(rest)) end
  elseif cmd == "kick" then
    if net and net:kickName(rest) then log("Wyrzucono %s", rest) else log("Nie ma gracza %s", rest) end
  elseif cmd == "save" then
    local n = self:saveWorld()
    log("Zapisano swiat (%d chunkow)", n)
  elseif cmd == "stop" then
    log("Zatrzymywanie serwera...")
    self:saveWorld()
    self:closeNet()
  elseif cmd == "time" or cmd == "weather" or cmd == "difficulty" or cmd == "seed" then
    local reply = commands.run(game, "/" .. line)
    for l in reply:gmatch("[^\n]+") do log(l) end
    if net and cmd ~= "seed" then net:announce("[Serwer] " .. reply:gsub("\n", " ")) end
  else
    log("Nieznana komenda. Wpisz 'help'.")
  end
end

-- ---------------------------------------------------------------------------
-- Pętla
-- ---------------------------------------------------------------------------
function Server:tick()
  local game, net = self.game, self.net
  if not game or not net then return end
  self.ticks = self.ticks + 1
  while self.console do
    local line = self.console:pop()
    if not line then break end
    local ok, err = pcall(self.command, self, line)
    if not ok then log("Blad komendy: %s", tostring(err)) end
  end
  if not self.net then return end
  net:poll()
  game:tick()
  net:tick()
  -- zdarzenia: czat do konsoli, reszta (dźwięki, cząsteczki) nie jest potrzebna
  for _, ev in ipairs(game:popEvents()) do
    if ev[1] == "chat" then log("%s", ev[2]) end
  end
  if self.ticks % AUTOSAVE_TICKS == 0 then self:saveWorld() end
end

function Server:update()
  local game, net = self.game, self.net
  if not game or not net then return end
  local now = love.timer.getTime
  local deadline = now() + 0.02
  -- okolica startu zostaje wczytana (jak spawn chunks w MC)
  local p = game.player
  local cx, cz = floor(p.x / 16), floor(p.z / 16)
  game.world:updateLoading(cx, cz, game.renderDistance, 1, 1)
  net:updateLoading(deadline, now)
  local removed = game.world:unloadFar(cx, cz, game.renderDistance + 2, net:keepAreas())
  if removed > 0 then game.entities:removeOutside(game.world) end
end

local _ = fs
return Server
