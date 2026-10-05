-- states/play.lua
-- Stan gry: łączy logikę (core/game.lua) z grafiką, dźwiękiem i sterowaniem.
--  * wejście: klawiatura i mysz -> game.input
--  * tick (20/s): game:tick(), cząsteczki, zdarzenia
--  * draw: niebo, chunki, byty, zaznaczenie, woda, cząsteczki, pogoda,
--    chmury, ręka, HUD, okna (ekwipunek, pauza, śmierć, czat)
--  * autozapis co minutę i zapis przy wyjściu

local config = require("core.config")
local mat4 = require("core.mat4")
local blocks = require("core.blocks")
local items = require("core.items")
local options = require("core.options")
local fs = require("core.fs")
local commands = require("core.commands")
local raycast = require("core.raycast")
local physics = require("core.physics")
local renderInit = require("render.init")
local atlas = require("render.atlas")
local shader = require("render.shader")
local Camera = require("render.camera")
local ChunkRenderer = require("render.chunkrenderer")
local models = require("render.models")
local sky = require("render.sky")
local particles = require("render.particles")
local weather = require("render.weather")
local hud = require("render.hud")
local gui = require("render.gui")
local sound = require("render.sound")
local tiles = require("core.tiles")
local ContainerScreen = require("ui.containerscreen")
local CreativeScreen = require("ui.creative")
local menus = require("ui.menus")

local Play = {}

local floor = math.floor
local P = 1 / 16

-- Krzywa jasności (jak w shaderze): l w 0..1
local function brightness(l)
  return 0.05 + 0.95 * (l / (4 - 3 * l))
end

-- params: { game = Game, folder = "nazwa" }
function Play:enter(params)
  renderInit.load()
  params = params or {}
  self.game = params.game
  self.folder = params.folder
  self.manager = params.manager
  local game = self.game
  game.renderDistance = options.values.renderDistance
  game.difficulty = options.values.difficulty
  self.renderer = ChunkRenderer.new(game.world, atlas.image)
  self.camera = Camera.new()
  self.screen = nil
  self.showHud = true
  self.showDebug = false
  self.thirdPerson = 0
  self.swing = 0
  self.prevSwing = 0
  self.equip = 1
  self.lastSelected = game.selected
  self.lastSpace, self.lastW = -10, -10
  self.ticks = 0
  self.autosaveTimer = 0
  self.hurtFlash = 0
  self.shake = 0
  self.lightningFlash = 0
  self.bob = 0
  self.prevWalk = game.player.walkDist
  self.fovMul = 1
  self.crackMeshes = {}
  particles.clear()
  hud.messages = {}
  love.mouse.setRelativeMode(true)
  love.mouse.setVisible(false)
  gui.userScale = options.values.guiScale
  gui.updateScale()
  sound.setVolume(options.values.volume)
  sound.setMusicVolume(options.values.music)
  if game.dead then self:openScreen(menus.death(game, function(a) self:deathAction(a) end)) end
  if game.netClient then
    local who = game.netClient.dedicated and "z serwerem" or ("z gra gracza " .. (game.netClient.hostName or "?"))
    hud.message("Polaczono " .. who .. ". /list - lista graczy", { 1, 1, 0.5 })
  else
    hud.message("Witaj w swiecie '" .. game.name .. "'! Wpisz /help w czacie (T)", { 1, 1, 0.5 })
  end
  if params.hostName then options.values.playerName = params.hostName end
  if params.openLan then self:openLan() end
end

function Play:leave()
  self:closeNet()
  love.mouse.setRelativeMode(false)
  love.mouse.setVisible(true)
  sound.stopAll()
  self.renderer:clear()
end

-- ---------------------------------------------------------------------------
-- Okna
-- ---------------------------------------------------------------------------
function Play:openScreen(screen)
  if self.screen and self.screen.close then self.screen:close() end
  if self.screen and self.screen.watchingTiles and self.game.netClient then
    self.game.netClient:unwatchTiles()
  end
  self.screen = screen
  love.mouse.setRelativeMode(screen == nil)
  love.mouse.setVisible(screen ~= nil)
  local inp = self.game.input
  inp.attack, inp.use = false, false
  if screen == nil then self.game.uiOpen = false end
end

function Play:closeScreen()
  self:openScreen(nil)
end

function Play:openPause()
  local game = self.game
  local kind, info
  if game.netServer then
    local srv = game.netServer
    kind = "host"
    info = "Siec LAN: " .. (self.lanAddress or "?") .. ":" .. srv.port .. "\nGraczy: " .. (srv:count() + 1)
  elseif game.netClient then
    kind = "client"
    info = game.netClient.dedicated and "Polaczono z serwerem"
      or ("Polaczono z gra gracza " .. (game.netClient.hostName or "?"))
  end
  self:openScreen(menus.pause(function(action)
    if action == "resume" then
      self:closeScreen()
    elseif action == "options" then
      self:openOptions()
    elseif action == "lan" then
      self:openLan()
    elseif action == "quit" then
      self:saveAndQuit()
    end
  end, kind, info))
end

-- ---------------------------------------------------------------------------
-- Gra wieloosobowa
-- ---------------------------------------------------------------------------
-- Adres IP komputera w sieci lokalnej (do podania znajomym)
local function localAddress()
  local ok, socket = pcall(require, "socket")
  if not ok or not socket then return "localhost" end
  local udp = socket.udp()
  if not udp then return "localhost" end
  -- nic nie jest wysyłane: setpeername tylko wybiera kartę sieciową
  udp:setpeername("192.168.255.255", 9)
  local ip = udp:getsockname()
  udp:close()
  if not ip or ip == "0.0.0.0" then return "localhost" end
  return ip
end

function Play:openLan()
  local game = self.game
  if game.dimension ~= "overworld" then
    hud.message("Siec LAN mozna otworzyc tylko w zwyklym swiecie", { 1, 0.5, 0.5 })
    self:closeScreen()
    return
  end
  local transport = require("core.net.transport")
  local protocol = require("core.net.protocol")
  local t, err = transport.enetServer(protocol.PORT, protocol.MAX_PLAYERS)
  if not t then
    hud.message("Nie udalo sie otworzyc gry w sieci: " .. tostring(err), { 1, 0.5, 0.5 })
    self:closeScreen()
    return
  end
  require("core.net.server").start(game, t, { name = options.values.playerName, port = protocol.PORT })
  self.lanAddress = localAddress()
  hud.message("Swiat otwarty w sieci LAN: " .. self.lanAddress .. " (port " .. protocol.PORT .. ")",
    { 0.6, 1, 0.6 })
  hud.message("Znajomi: Gra wieloosobowa -> wpisz ten adres", { 0.6, 1, 0.6 })
  self:closeScreen()
end

function Play:closeNet()
  local game = self.game
  if not game then return end
  if game.netServer then game.netServer:stop() end
  if game.netClient then game.netClient:close() end
end

-- Utrata połączenia z gospodarzem: powrót do menu z komunikatem
function Play:netLost(message)
  if self.manager then
    self.manager:switch(require("states.menu"), { manager = self.manager,
      message = message or "Rozlaczono z serwerem" })
  else
    love.event.quit()
  end
end

function Play:openOptions()
  self:openScreen(menus.options(function(key, value) self:applyOption(key, value) end,
    function()
      options.save(fs)
      self:openPause()
    end))
end

function Play:applyOption(key, value)
  local game = self.game
  if key == "renderDistance" then game.renderDistance = value
  elseif key == "guiScale" then gui.userScale = value; gui.updateScale()
  elseif key == "difficulty" then game.difficulty = value
  elseif key == "volume" then sound.setVolume(value)
  elseif key == "music" then sound.setMusicVolume(value) end
end

function Play:deathAction(action)
  local game = self.game
  if action == "respawn" then
    game.survival.respawn(game)
    self:closeScreen()
  elseif action == "quit" then
    self:saveAndQuit()
  elseif action == "delete" then
    if self.folder then require("core.save").deleteWorld(self.folder) end
    self.folder = nil
    game.saveFolder = nil
    self:quitToMenu()
  end
end

function Play:save()
  if self.game.netServer then
    for _, ctx in pairs(self.game.netServer.peers) do self.game.netServer:savePlayer(ctx) end
  end
  if not self.folder then return end
  local n = self.game:saveAll()
  options.save(fs)
  return n
end

function Play:saveAndQuit()
  self:save()
  self:quitToMenu()
end

function Play:quitToMenu()
  if self.manager then
    self.manager:switch(require("states.menu"), { manager = self.manager })
  else
    love.event.quit()
  end
end

function Play:openContainer(kind, x, y, z)
  local game = self.game
  if kind == "inventory" then
    if game.player.gameMode == "creative" then
      self:openScreen(CreativeScreen.new(game))
    else
      self:openScreen(ContainerScreen.new(game, "inventory"))
    end
  else
    self:openScreen(ContainerScreen.new(game, kind, { x, y, z }))
    -- gość: zawartość skrzyni/pieca jest u gospodarza
    if game.netClient and (kind == "chest" or kind == "furnace" or kind == "brewing") then
      local list = { { x, y, z } }
      if kind == "chest" then
        for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
          if game.world:getBlock(x + d[1], y, z + d[2]) == 54 then list[2] = { x + d[1], y, z + d[2] } break end
        end
      end
      game.netClient:watchTiles(list)
      self.screen.watchingTiles = true
    end
  end
end

-- ---------------------------------------------------------------------------
-- Wejście
-- ---------------------------------------------------------------------------
function Play:readInput()
  local game = self.game
  local inp = game.input
  if self.screen then
    inp.forward, inp.strafe, inp.jump, inp.sneak = 0, 0, false, false
    inp.attack, inp.use = false, false
    return
  end
  local k = love.keyboard.isDown
  local f, s = 0, 0
  if k("w", "up") then f = f + 1 end
  if k("s", "down") then f = f - 1 end
  if k("d", "right") then s = s + 1 end
  if k("a", "left") then s = s - 1 end
  inp.forward, inp.strafe = f, s
  inp.jump = k("space")
  inp.sneak = k("lshift", "rshift")
  if k("lctrl", "rctrl") and f > 0 then inp.sprint = true end
  if f <= 0 then inp.sprint = false end
  inp.attack = love.mouse.isDown(1)
  inp.use = love.mouse.isDown(2)
end

function Play:mousemoved(x, y, dx, dy)
  if self.screen then
    if self.screen.mousemoved then self.screen:mousemoved(x, y, dx, dy) end
    return
  end
  local p = self.game.player
  if self.game.dead or self.game.sleeping then return end
  local sdeg = math.rad(options.mouseDegrees())
  local inv = options.values.invertMouse and -1 or 1
  p.yaw = p.yaw - dx * sdeg
  p.pitch = math.max(-math.pi / 2 + 0.001, math.min(math.pi / 2 - 0.001, p.pitch - dy * sdeg * inv))
end

function Play:mousepressed(x, y, button)
  if self.screen then
    if self.screen.mousepressed then self.screen:mousepressed(x, y, button) end
    return
  end
  local inp = self.game.input
  if button == 1 then
    inp.attackPressed = true
    self.swing = 1
  elseif button == 2 then
    inp.usePressed = true
  elseif button == 3 then
    self:pickBlock()
  end
end

function Play:mousereleased(x, y, button)
  if self.screen and self.screen.mousereleased then self.screen:mousereleased(x, y, button) end
end

function Play:wheelmoved(x, y)
  if self.screen then
    if self.screen.wheelmoved then self.screen:wheelmoved(x, y) end
    return
  end
  local game = self.game
  if y ~= 0 then
    game.selected = ((game.selected - 1 - (y > 0 and 1 or -1)) % 9) + 1
  end
end

-- Środkowy przycisk myszy: w trybie kreatywnym bierze wskazany blok
function Play:pickBlock()
  local game = self.game
  local hit = game.hit
  if not hit then return end
  local def = blocks.defs[hit.id]
  if not def then return end
  local id = hit.id
  if id == 64 then id = 324 elseif id == 26 then id = 355 elseif id == 62 then id = 61
  elseif id == 59 then id = 295 elseif id == 83 then id = 338 end
  local dmg = (def.metaMask and def.metaMask > 0) and (hit.meta % (def.metaMask + 1)) or 0
  -- jest już w pasku?
  for i = 1, 9 do
    local s = game.inventory.slots[i]
    if s and s.id == id and (s.damage or 0) == dmg then game.selected = i return end
  end
  if game.player.gameMode == "creative" then
    game.inventory:set(game.selected, { id = id, count = items.maxStack(id), damage = dmg })
  end
end

function Play:keypressed(key, scancode, isrepeat)
  local game = self.game
  if self.screen then
    if self.screen.keypressed and self.screen:keypressed(key) then return end
    if key == "escape" or key == "e" then
      if not (self.screen.isDeath or game.dead) then self:closeScreen() end
    end
    return
  end
  local now = self.ticks
  if key == "escape" then
    self:openPause()
  elseif key == "e" then
    self:openContainer("inventory")
  elseif key == "t" or key == "/" then
    self:openScreen(menus.chat(function(text) self:chat(text) end, function() self:closeScreen() end,
      key == "/" and "/" or ""))
  elseif key == "q" then
    game:throwFromHand(love.keyboard.isDown("lctrl", "rctrl"))
    self.swing = 1
  elseif key == "f1" then
    self.showHud = not self.showHud
  elseif key == "f2" then
    local name = os.date("zrzut_%Y-%m-%d_%H-%M-%S.png")
    love.graphics.captureScreenshot(function(img)
      img:encode("png", name)
    end)
    hud.message("Zapisano zrzut ekranu: " .. name)
  elseif key == "f3" then
    self.showDebug = not self.showDebug
  elseif key == "f5" then
    self.thirdPerson = (self.thirdPerson + 1) % 3
  elseif key == "space" and not isrepeat then
    if game.player.gameMode == "creative" and now - self.lastSpace < 7 then
      game.player.flying = not game.player.flying
      game.player.vy = 0
      self.lastSpace = -10
    else
      self.lastSpace = now
    end
  elseif key == "w" and not isrepeat then
    if now - self.lastW < 7 then game.input.sprint = true end
    self.lastW = now
  else
    local n = tonumber(key)
    if n and n >= 1 and n <= 9 then game.selected = n end
  end
end

function Play:textinput(t)
  if self.screen and self.screen.textinput then self.screen:textinput(t) end
end

function Play:chat(text)
  local game = self.game
  if text:sub(1, 1) == "/" then
    local reply = commands.run(game, text)
    for line in reply:gmatch("[^\n]+") do hud.message(line, { 0.75, 0.75, 0.75 }) end
  elseif game.netClient then
    game.netClient:chat(text)
  elseif game.netServer then
    game.netServer:announce("<" .. game.netServer.hostName .. "> " .. text)
  else
    hud.message("<Gracz> " .. text)
  end
end

function Play:focus(focused)
  if not focused and not self.screen then self:openPause() end
end

function Play:resize()
  gui.updateScale()
end

-- ---------------------------------------------------------------------------
-- Logika
-- ---------------------------------------------------------------------------
function Play:tick()
  local game = self.game
  self.ticks = self.ticks + 1
  self:readInput()
  local server, client = game.netServer, game.netClient
  if server then server:poll() end
  if client then
    client:poll()
    if client.state == "closed" then
      self:netLost(client.error)
      return
    end
  end
  -- pauza zatrzymuje świat tylko w grze jednoosobowej
  local paused = self.screen and self.screen.pausesGame and not client
    and not (server and server:count() > 0)
  if paused then return end

  if client then client:tick() else game:tick() end
  if server then server:tick() end
  particles.update(game.world)
  self:handleEvents()

  -- zmiana slotu: nazwa przedmiotu
  if game.selected ~= self.lastSelected then
    self.lastSelected = game.selected
    hud.showItemName(game:heldStack())
    self.equip = 0
  end
  if self.equip < 1 then self.equip = math.min(1, self.equip + 0.25) end
  self.prevSwing = self.swing
  if self.swing > 0 then self.swing = math.max(0, self.swing - 1 / 6) end
  if game.input.attack and not self.screen and self.swing == 0 and game.mining then self.swing = 1 end

  -- kroki
  local p = game.player
  if floor(p.walkDist) ~= floor(self.prevWalk) and p.onGround and not p.sneaking then
    local below = game.world:getBlock(floor(p.x), floor(p.y - 0.2), floor(p.z))
    if below ~= 0 then sound.dig(below, p.x, p.y, p.z, 0.25) end
  end
  self.prevWalk = p.walkDist
  if p.inWater and not self.wasInWater and p.vy < -0.2 then
    sound.play("splash", p.x, p.y, p.z, 0.6)
    particles.burst("splash", p.x, p.y + 0.5, p.z, 10)
  end
  self.wasInWater = p.inWater

  -- przyjazne dźwięki mobów
  if self.ticks % 40 == 0 then
    for _, e in ipairs(game.entities:near(p.x, p.y, p.z, 16, "mob")) do
      if game.rng:chance(0.1) and e.health > 0 then
        sound.voice(e.kind, e.x, e.y + e.height * 0.8, e.z, (e.growth and e.growth < 0) and 1.5 or 1)
      end
    end
  end
  -- ogień i dym z pochodni oraz pieców w pobliżu
  if self.ticks % 6 == 0 then self:ambientParticles() end

  -- spanie: zasypianie / budzenie
  if self.hurtFlash > 0 then self.hurtFlash = self.hurtFlash - 1 end
  if self.lightningFlash > 0 then self.lightningFlash = self.lightningFlash - 1 end
  if self.shake > 0 then self.shake = self.shake * 0.85 end

  -- autozapis co 60 s
  self.autosaveTimer = self.autosaveTimer + 1
  if self.autosaveTimer >= 1200 then
    self.autosaveTimer = 0
    self:save()
  end
end

function Play:ambientParticles()
  local game = self.game
  local p = game.player
  local world = game.world
  for _ = 1, 30 do
    local x = floor(p.x) + math.random(-12, 12)
    local y = floor(p.y) + math.random(-6, 6)
    local z = floor(p.z) + math.random(-12, 12)
    local id = world:getBlock(x, y, z)
    if id == 50 then
      local meta = world:getMeta(x, y, z)
      local x0, _, z0, x1, y1, z1 = blocks.torchBounds(meta)
      particles.burst("flame", x + (x0 + x1) / 2, y + y1 + 0.05, z + (z0 + z1) / 2, 1)
    elseif id == 62 then
      particles.burst("flame", x + 0.5, y + 0.3, z + 0.5, 1)
    elseif id == 116 then
      particles.burst("enchant", x + 0.5, y + 1.2, z + 0.5, 2)
    elseif id == 119 or id == 120 then
      if math.random() < 0.3 then particles.burst("portal", x + 0.5, y + 0.9, z + 0.5, 1) end
    elseif id == 10 and world:getBlock(x, y + 1, z) == 0 and math.random() < 0.1 then
      particles.burst("fire_small", x + 0.5, y + 1, z + 0.5, 1)
    end
  end
end

-- Efekty, które dzieją się w konkretnym miejscu świata. Gospodarz gry
-- sieciowej liczy też wymiary gości - ich efektów nie pokazujemy.
local LOCAL_FX = { ["break"] = true, hit = true, place = true, sound = true, particles = true,
  explosion = true, lightning = true }

function Play:handleEvents()
  local game = self.game
  for _, ev in ipairs(game:popEvents()) do
    local kind = ev[1]
    if ev.dim and ev.dim ~= game.dimension and LOCAL_FX[kind] then
      kind = nil
    end
    if kind == "break" then
      particles.blockBreak(ev[2], ev[3], ev[4], ev[5], ev[6])
      sound.dig(ev[5], ev[2] + 0.5, ev[3] + 0.5, ev[4] + 0.5, 1)
    elseif kind == "hit" then
      particles.blockHit(ev[2], ev[3], ev[4], ev[5], ev[6])
      sound.dig(ev[5], ev[2] + 0.5, ev[3] + 0.5, ev[4] + 0.5, 0.35)
    elseif kind == "place" then
      sound.dig(ev[5], ev[2] + 0.5, ev[3] + 0.5, ev[4] + 0.5, 0.9)
      self.swing = 1
    elseif kind == "sound" then
      local name = ev[2]
      if name == "mob_hurt" or name == "mob_death" then
        sound.mob(ev[6], name == "mob_death" and "death" or "hurt", ev[3], ev[4], ev[5])
      elseif name == "step_grass" then
        sound.dig(2, ev[3], ev[4], ev[5])
      elseif name == "fuse" then
        sound.play("fuse", ev[3], ev[4], ev[5], 0.8)
      else
        sound.play(name, ev[3], ev[4], ev[5])
      end
    elseif kind == "particles" then
      if ev[2] == "eat" then
        local p = game.player
        local ex, ey, ez = p:eyePosition()
        local lx, ly, lz = p:lookVector()
        particles.burst("smoke", ex + lx * 0.4, ey - 0.2 + ly * 0.4, ez + lz * 0.4, 2)
      else
        particles.burst(ev[2], ev[3], ev[4], ev[5], ev[2] == "potion" and 30 or 8, ev[6])
      end
    elseif kind == "explosion" then
      particles.burst("explosion", ev[2], ev[3], ev[4], 40)
      sound.play("explosion", ev[2], ev[3], ev[4], 1.2)
      local p = game.player
      local d = math.sqrt((p.x - ev[2]) ^ 2 + (p.y - ev[3]) ^ 2 + (p.z - ev[4]) ^ 2)
      self.shake = math.max(self.shake, math.max(0, 1 - d / 20))
    elseif kind == "lightning" then
      self.lightningFlash = 6
      sound.play("thunder", ev[2], ev[3], ev[4], 1.5)
    elseif kind == "open" then
      self:openContainer(ev[2], ev[3], ev[4], ev[5])
    elseif kind == "message" then
      hud.message(ev[2], { 1, 1, 0.6 })
    elseif kind == "chat" then
      hud.message(ev[2])
    elseif kind == "death" then
      game.stats.lastScore = game.xpTotal
      self:openScreen(menus.death(game, function(a) self:deathAction(a) end))
      self.screen.isDeath = true
    elseif kind == "hurt" then
      self.hurtFlash = 10
    elseif kind == "swing" then
      self.swing = 1
    elseif kind == "wake" then
      hud.message("Dzien dobry!", { 1, 1, 0.6 })
    elseif kind == "dimension" then
      self.renderer:clear()
      self.renderer = ChunkRenderer.new(game.world, atlas.image)
      particles.clear()
      sound.setRain(0)
      local msg = ({ nether = "Wszedles do Netheru", ["end"] = "Wszedles do Endu" })[ev[2]]
      hud.message(msg or "Wrociles do zwyklego swiata", { 1, 0.6, 0.6 })
    end
  end
end

function Play:update(dt, alpha)
  local game = self.game
  -- muzyka Minecrafta (jeśli jest zainstalowany)
  local ctx = game.dimension == "nether" and "nether" or (game.dimension == "end" and "end"
    or (game.player.gameMode == "creative" and "creative" or "game"))
  sound.updateMusic(dt, ctx)
  gui.updateScale()
  -- ładowanie świata z limitem czasu na klatkę
  local start = love.timer.getTime()
  local budget = 0.006
  local pcx, pcz = floor(game.player.x / 16), floor(game.player.z / 16)
  local p = game.player
  if game.netClient then
    -- gość: teren przychodzi z sieci, tu tylko światło i zwalnianie
    game.netClient:updateWorld(start + budget, love.timer.getTime)
  else
    repeat
      -- najpierw oświetlanie gotowych chunków, potem generowanie nowych
      local _, lit = game.world:updateLoading(pcx, pcz, game.renderDistance, 0, 1)
      local gen = 0
      if love.timer.getTime() - start < budget then
        gen = game.world:updateLoading(pcx, pcz, game.renderDistance, 1, 0)
      end
    until (gen == 0 and lit == 0) or love.timer.getTime() - start > budget
    local keep
    if game.netServer then
      -- teren wokół gości generuje i trzyma gospodarz
      game.netServer:updateLoading(love.timer.getTime() + budget, love.timer.getTime)
      keep = game.netServer:keepAreas()
    end
    local removed = game.world:unloadFar(floor(p.x / 16), floor(p.z / 16), game.renderDistance + 4, keep)
    if removed > 0 then game.entities:removeOutside(game.world) end
  end
  self.renderer:update(p.x, p.z, game.renderDistance, 0.008)

  -- gracz utknął w niezaładowanym terenie (po odrodzeniu): przenieś na powierzchnię
  if game.needsSpawnFix and game.world:isLoadedAt(floor(p.x), floor(p.z)) then
    local c = game.world:getChunkAt(floor(p.x), floor(p.z))
    if c and c.lit then
      p.y = game:surfaceY(floor(p.x), floor(p.z))
      p.prevY = p.y
      game.needsSpawnFix = false
    end
  end

  -- FOV: sprint go poszerza
  local target = p.sprinting and 1.15 or 1
  if p.flying and p.sprinting then target = 1.2 end
  self.fovMul = self.fovMul + (target - self.fovMul) * math.min(1, dt * 10)

  sound.setRain(game.weather.raining and (self.rainNear or 0) > 0 and game.weather.strength or 0)
end

-- ---------------------------------------------------------------------------
-- Rysowanie
-- ---------------------------------------------------------------------------
local tmpM, tmpM2, handView = mat4.new(), mat4.new(), mat4.new()

function Play:setupCamera(alpha)
  local game = self.game
  local p = game.player
  local cam = self.camera
  local ex, ey, ez = p:eyePosition(alpha)
  -- kołysanie kamery przy chodzeniu
  if options.values.viewBobbing and p.onGround and self.thirdPerson == 0 then
    local walk = p.prevWalkDist + (p.walkDist - p.prevWalkDist) * alpha
    local speed = math.min(1, math.sqrt((p.x - p.prevX) ^ 2 + (p.z - p.prevZ) ^ 2) * 5)
    self.bob = self.bob + (speed - self.bob) * 0.1
    local bx = math.sin(walk * math.pi) * 0.04 * self.bob
    local by = -math.abs(math.cos(walk * math.pi)) * 0.06 * self.bob
    ex = ex + math.cos(p.yaw) * bx
    ez = ez - math.sin(p.yaw) * bx
    ey = ey + by
  end
  if game.sleeping then ey = p.y + 0.3 end
  if game.dead then ey = p.y + 0.3 end
  cam.yaw, cam.pitch = p.yaw, p.pitch
  if self.shake > 0.01 then
    cam.yaw = cam.yaw + (math.random() - 0.5) * self.shake * 0.05
    cam.pitch = cam.pitch + (math.random() - 0.5) * self.shake * 0.05
  end
  -- widok z trzeciej osoby
  if self.thirdPerson > 0 then
    local lx, ly, lz = p:lookVector()
    local dir = self.thirdPerson == 1 and -1 or 1
    local hit = raycast.cast(game.world, ex, ey, ez, lx * dir, ly * dir, lz * dir, 4, function(def)
      return def.solid
    end)
    local d = hit and math.max(0.5, hit.dist - 0.3) or 4
    ex, ey, ez = ex + lx * dir * d, ey + ly * dir * d, ez + lz * dir * d
    if self.thirdPerson == 2 then
      cam.yaw = cam.yaw + math.pi
      cam.pitch = -cam.pitch
    end
  end
  cam.x, cam.y, cam.z = ex, ey, ez
  cam.fov = math.rad(options.values.fov * self.fovMul)
  if game.player.headInWater then cam.fov = cam.fov * 0.9 end
  local w, h = love.graphics.getDimensions()
  cam.far = math.max(256, game.renderDistance * 16 + 64)
  cam:update(w, h)
end

function Play:entityLight(x, y, z)
  local game = self.game
  local bx, by, bz = floor(x), floor(y), floor(z)
  local sl = game.world:getSkyLight(bx, by, bz)
  local bl = game.world:getBlockLight(bx, by, bz)
  local l = math.max(sl * game:daylight(), bl) / 15
  local b = brightness(l)
  if game.dimension == "nether" and b < 0.32 then b = 0.32 end
  if game.dimension == "end" and b < 0.5 then b = 0.5 end
  return b
end

-- Nakładka pękania bloku
function Play:crackMesh(stage)
  local m = self.crackMeshes[stage]
  if m then return m end
  local t = tiles.get("cracks_" .. stage)
  local tt = { t, t, t, t, t, t }
  m = models.meshFromBoxes({ { -0.02, -0.02, -0.02, 16.02, 16.02, 16.02, color = { 1, 1, 1 }, tiles = tt } })
  self.crackMeshes[stage] = m
  return m
end

function Play:drawEntities(alpha)
  local game = self.game
  local g = love.graphics
  local s = shader.entity
  local cam = self.camera
  g.setShader(s)
  g.setDepthMode("lequal", true)
  g.setMeshCullMode("none")
  g.setBlendMode("alpha")
  local time = love.timer.getTime()
  for _, e in ipairs(game.entities.list) do
    if not e.dead then
      local x = e.prevX + (e.x - e.prevX) * alpha
      local y = e.prevY + (e.y - e.prevY) * alpha
      local z = e.prevZ + (e.z - e.prevZ) * alpha
      local dx, dz = x - cam.x, z - cam.z
      if dx * dx + dz * dz < (game.renderDistance * 16) ^ 2 then
        local hw = (e.width or 0.5) / 2 + 0.5
        if require("core.frustum").boxVisible(cam.frustum, x - hw, y - 0.5, z - hw, x + hw,
          y + (e.height or 1) + 0.5, z + hw) then
          local light = self:entityLight(x, y + (e.height or 0.5) * 0.5, z)
          if e.type == "mob" or e.type == "player" then
            models.drawMob(e, alpha, e.kind == "dragon" and math.max(light, 0.8) or light, time)
          elseif e.type == "crystal" then
            models.drawMob(e, alpha, 1, time)
          elseif e.type == "item" then
            if e.stack.ench then s:send("u_glint", 0.6); s:send("u_time", time) end
            models.drawItem(e, alpha, light, time, cam.yaw)
            if e.stack.ench then s:send("u_glint", 0) end
          elseif e.type == "falling" or e.type == "tnt" then
            s:send("u_light", light)
            if e.type == "tnt" and math.floor(e.fuse / 5) % 2 == 0 then
              s:send("u_tint", { 1, 1, 1, 0.5 })
            end
            local scale = 1
            if e.type == "tnt" and e.fuse < 10 then scale = 1 + (10 - e.fuse) / 10 * 0.25 end
            models.baseMatrix(tmpM, x, y + 0.49, z, 0, scale)
            models.drawMesh(models.blockMesh(e.block or 46, e.meta or 0), tmpM)
            s:send("u_tint", { 0, 0, 0, 0 })
          elseif e.type == "arrow" then
            s:send("u_light", light)
            local pitch = math.atan2 and math.atan2(e.vy, math.sqrt(e.vx * e.vx + e.vz * e.vz)) or 0
            models.baseMatrix(tmpM, x, y, z, e.yaw or 0)
            if not e.stuck then
              mat4.rotationX(tmpM2, pitch)
              mat4.multiply(tmpM, tmpM, tmpM2)
            else
              mat4.rotationX(tmpM2, e.stuckPitch or pitch)
              e.stuckPitch = e.stuckPitch or pitch
              mat4.multiply(tmpM, tmpM, tmpM2)
            end
            models.drawMesh(models.arrow, tmpM)
          elseif e.type == "minecart" or e.type == "boat" then
            s:send("u_light", light)
            if e.hurtTime and e.hurtTime > 0 then s:send("u_tint", { 1, 0, 0, 0.3 }) end
            models.baseMatrix(tmpM, x, y, z, e.yaw or 0)
            models.drawMesh(e.type == "boat" and models.boat or models.minecart, tmpM)
            s:send("u_tint", { 0, 0, 0, 0 })
          elseif e.type == "xp" then
            s:send("u_light", 1)
            local pulse = 0.8 + math.sin((e.age + alpha) * 0.4) * 0.2
            models.baseMatrix(tmpM, x, y + 0.15, z, (e.age + alpha) * 0.1, pulse)
            models.drawMesh(models.xp, tmpM)
          elseif e.type == "fireball" or e.type == "smallfireball" then
            s:send("u_light", 1)
            g.setColor(1, 0.55, 0.15, 1)
            models.baseMatrix(tmpM, x, y, z, (e.age + alpha) * 0.3, e.type == "fireball" and 3 or 1.2)
            models.drawMesh(models.ball, tmpM)
            g.setColor(1, 1, 1, 1)
          elseif e.type == "potion" or e.type == "eye" then
            s:send("u_light", e.type == "eye" and 1 or light)
            local mesh = models.spriteMesh(e.type == "eye" and 381 or 373, e.potion or 0)
            if mesh then
              models.baseMatrix(tmpM, x, y, z, cam.yaw, 0.35)
              models.drawMesh(mesh, tmpM)
            end
          elseif e.type == "snowball" or e.type == "egg" or e.type == "pearl" then
            s:send("u_light", light)
            local c = e.type == "egg" and { 0.95, 0.9, 0.75 } or (e.type == "pearl" and { 0.1, 0.4, 0.35 } or { 1, 1, 1 })
            g.setColor(c[1], c[2], c[3], 1)
            models.baseMatrix(tmpM, x, y, z, 0)
            models.drawMesh(models.ball, tmpM)
            g.setColor(1, 1, 1, 1)
          end
        end
      end
    end
  end
  -- gracz w widoku z trzeciej osoby
  if self.thirdPerson > 0 and models.MODELS.player then
    local p = game.player
    local fake = { kind = "player", x = p.x, y = p.y, z = p.z, prevX = p.prevX, prevY = p.prevY,
      prevZ = p.prevZ, yaw = p.yaw, prevYaw = p.yaw, limb = p.walkDist * 1.5,
      limbSpeed = math.min(1, math.sqrt((p.x - p.prevX) ^ 2 + (p.z - p.prevZ) ^ 2) * 5),
      hurtTime = game.hurtTime, headPitch = -p.pitch * 0.5 }
    models.drawMob(fake, alpha, self:entityLight(p.x, p.y + 1, p.z), time)
  end
end

function Play:drawSelection()
  local game = self.game
  local hit = game.hit
  if not hit or self.screen or game.dead or not self.showHud then return end
  local def = blocks.defs[hit.id]
  if not def then return end
  local x0, y0, z0, x1, y1, z1 = blocks.bounds(def, hit.meta)
  local g = love.graphics
  g.setShader(shader.entity)
  g.setMeshCullMode("none")
  g.setColor(1, 1, 1, 0.6)
  models.drawOutline(hit.x + x0 - 0.002, hit.y + y0 - 0.002, hit.z + z0 - 0.002,
    hit.x + x1 + 0.002, hit.y + y1 + 0.002, hit.z + z1 + 0.002)
  g.setColor(1, 1, 1, 1)
  -- pękanie
  local m = game.mining
  if m and m.progress > 0 then
    local stage = math.min(9, floor(m.progress * 10))
    local mesh = self:crackMesh(stage)
    shader.entity:send("u_light", 1)
    mat4.translation(tmpM, m.x, m.y, m.z)
    models.drawMesh(mesh, tmpM)
  end
end

-- Ręka i przedmiot w pierwszej osobie
function Play:drawHand(alpha)
  local game = self.game
  if self.thirdPerson > 0 or game.dead or not self.showHud then return end
  local g = love.graphics
  local s = shader.entity
  g.clear(false, false, true)
  g.setShader(s)
  s:send("u_view", "row", mat4.identity(handView))
  s:send("u_fogStart", 1000)
  s:send("u_fogEnd", 2000)
  local p = game.player
  local light = self:entityLight(p.x, p.y + 1.6, p.z)
  s:send("u_light", light)
  local swing = self.prevSwing + (self.swing - self.prevSwing) * alpha
  local sw = math.sin((1 - swing) * math.pi)
  local sw2 = math.sin(math.sqrt(1 - swing) * math.pi)
  if swing <= 0 then sw, sw2 = 0, 0 end
  local equip = 1 - self.equip
  local walk = p.prevWalkDist + (p.walkDist - p.prevWalkDist) * alpha
  local bobX = options.values.viewBobbing and math.sin(walk * math.pi) * 0.03 * self.bob or 0
  local bobY = options.values.viewBobbing and -math.abs(math.cos(walk * math.pi)) * 0.04 * self.bob or 0
  local using = game.using
  local eatBob = 0
  if using and (using.kind == "eat" or using.kind == "drink") then
    eatBob = math.abs(math.sin(using.ticks * 0.8)) * 0.05
  end

  local held = game:heldStack()
  g.setMeshCullMode("none")
  if held and held.ench then
    s:send("u_glint", 0.55)
    s:send("u_time", love.timer.getTime())
  end
  if held then
    if models.isCubeItem(held.id) then
      local mesh = models.blockMesh(held.id, (blocks.defs[held.id].metaMask or 0) > 0 and held.damage or 0)
      mat4.translation(tmpM, 0.56 + bobX - sw2 * 0.4, -0.55 + bobY - equip * 0.6 + sw * 0.2 + eatBob,
        -0.75 - sw2 * 0.2)
      mat4.rotationY(tmpM2, math.rad(45) - sw2 * 0.6)
      mat4.multiply(tmpM, tmpM, tmpM2)
      mat4.rotationX(tmpM2, -sw * 0.6)
      mat4.multiply(tmpM, tmpM, tmpM2)
      mat4.scale(tmpM2, 0.4, 0.4, 0.4)
      mat4.multiply(tmpM, tmpM, tmpM2)
      models.drawMesh(mesh, tmpM)
    else
      local mesh = models.spriteMesh(held.id, held.damage)
      if mesh then
        local bowPull = (using and using.kind == "bow") and math.min(1, using.ticks / 20) or 0
        local blocking = using and using.kind == "block"
        if blocking then sw, sw2 = 0, 0 end
        mat4.translation(tmpM, 0.6 + bobX - sw2 * 0.4 - bowPull * 0.3,
          -0.45 + bobY - equip * 0.6 + sw * 0.2 + eatBob, -0.9 - sw2 * 0.2 + bowPull * 0.2)
        mat4.rotationY(tmpM2, math.rad(-80) + bowPull * 1.2)
        mat4.multiply(tmpM, tmpM, tmpM2)
        mat4.rotationZ(tmpM2, math.rad(blocking and 70 or 25) - sw * 1.0)
        mat4.multiply(tmpM, tmpM, tmpM2)
        if blocking then
          mat4.rotationX(tmpM2, math.rad(-30))
          mat4.multiply(tmpM, tmpM, tmpM2)
        end
        mat4.scale(tmpM2, 0.75, 0.75, 0.75)
        mat4.multiply(tmpM, tmpM, tmpM2)
        models.drawMesh(mesh, tmpM)
      end
    end
  else
    mat4.translation(tmpM, 0.55 + bobX - sw2 * 0.3, -0.5 + bobY - equip * 0.6 + sw * 0.15,
      -0.55 - sw2 * 0.3)
    mat4.rotationX(tmpM2, math.rad(-70) - sw * 0.8)
    mat4.multiply(tmpM, tmpM, tmpM2)
    mat4.rotationZ(tmpM2, math.rad(12))
    mat4.multiply(tmpM, tmpM, tmpM2)
    models.drawMesh(models.arm, tmpM)
  end
  s:send("u_glint", 0)
  s:send("u_view", "row", self.camera.view)
end

function Play:draw(alpha)
  local game = self.game
  local g = love.graphics
  local w, h = g.getDimensions()
  alpha = alpha or 1
  if self.screen and self.screen.pausesGame and not game.net then alpha = 1 end
  self:setupCamera(alpha)
  local cam = self.camera
  local p = game.player
  sound.setListener(cam.x, cam.y, cam.z, cam:forward())

  local skyColor, fogColor = sky.colors(game, cam.y)
  local fogEnd = game.renderDistance * 16 * 0.92
  local fogStart = fogEnd * 0.45
  if game.weather.strength > 0 then
    fogEnd = fogEnd * (1 - game.weather.strength * 0.25)
  end
  local nether = game.dimension == "nether"
  local theEnd = game.dimension == "end"
  if nether then
    skyColor = { 0.22, 0.03, 0.02 }
    fogColor = skyColor
    fogEnd = math.min(fogEnd, 80)
    fogStart = fogEnd * 0.2
  elseif theEnd then
    skyColor = { 0.05, 0.035, 0.08 }
    fogColor = { 0.09, 0.07, 0.12 }
    fogEnd = math.min(fogEnd, 170)
    fogStart = fogEnd * 0.45
  end
  shader.chunk:send("u_ambient", theEnd and 0.5 or (nether and 0.32 or 0))
  -- w Netherze i Endzie nie ma słońca, chmur ani pogody
  nether = nether or theEnd
  local underwater = physics.pointInLiquid(game.world, cam.x, cam.y, cam.z, "water")
  local inLava = physics.pointInLiquid(game.world, cam.x, cam.y, cam.z, "lava")
  if underwater then
    fogColor = { 0.05 * game:daylight(), 0.1 * game:daylight(), 0.4 * game:daylight() + 0.05 }
    skyColor = fogColor
    fogStart, fogEnd = 0, 14
  elseif inLava then
    fogColor = { 0.6, 0.1, 0 }
    skyColor = fogColor
    fogStart, fogEnd = 0, 2
  end
  if self.lightningFlash > 0 then
    skyColor = { 0.9, 0.9, 1 }
  end

  g.clear(skyColor[1], skyColor[2], skyColor[3], 1)
  shader.setCamera(cam.proj, cam.view, fogColor, fogStart, fogEnd)
  if not underwater and not inLava and cam.y > 30 and not nether then sky.drawCelestial(game, cam, alpha) end
  shader.setCamera(cam.proj, cam.view, fogColor, fogStart, fogEnd)

  local daylight = game:daylight()
  if self.lightningFlash > 0 then daylight = 1 end
  self.renderer:drawOpaque(cam, daylight)
  self:drawEntities(alpha)
  self:drawSelection()
  self.renderer:drawTranslucent(cam, daylight)
  shader.entity:send("u_fogStart", fogStart)
  shader.entity:send("u_fogEnd", fogEnd)
  particles.draw(cam, alpha, function(x, y, z) return self:entityLight(x, y, z) end)
  self.rainNear = nether and 0 or weather.draw(game, cam, alpha, brightness(daylight))
  if options.values.clouds and not underwater and not nether then
    sky.drawClouds(game, cam, alpha, fogColor, fogEnd)
  end
  self:drawHand(alpha)

  g.setShader()
  g.setDepthMode()
  g.setMeshCullMode("none")
  g.setBlendMode("alpha")
  g.setColor(1, 1, 1, 1)

  -- nakładki: pod wodą, w lawie, w ogniu, obrażenia, sen
  if underwater then
    g.setColor(0.1, 0.2, 0.8, 0.25)
    g.rectangle("fill", 0, 0, w, h)
  elseif inLava then
    g.setColor(1, 0.3, 0, 0.6)
    g.rectangle("fill", 0, 0, w, h)
  end
  if game.fireTicks > 0 and p.gameMode ~= "creative" and not self.screen then
    g.setColor(1, 0.5, 0.1, 0.15 + math.sin(love.timer.getTime() * 20) * 0.05)
    g.rectangle("fill", 0, h * 0.6, w, h * 0.4)
  end
  if (game.portalTimer or 0) > 0 then
    local f = math.min(1, game.portalTimer / 80)
    g.setColor(0.5, 0.1, 0.9, f * 0.65)
    g.rectangle("fill", 0, 0, w, h)
  end
  if self.hurtFlash > 0 then
    g.setColor(0.8, 0, 0, self.hurtFlash / 10 * 0.3)
    g.rectangle("fill", 0, 0, w, h)
  end
  if game.sleeping then
    g.setColor(0, 0, 0.05, math.min(0.9, game.sleeping.timer / 100))
    g.rectangle("fill", 0, 0, w, h)
  end
  g.setColor(1, 1, 1, 1)

  self:drawNameTags(alpha)
  if self.showHud and not game.dead and not self.screen then self:drawHeldMap() end
  if self.showHud and not game.dead then
    hud.draw(game, alpha, { hideCrosshair = self.screen ~= nil or self.thirdPerson > 0,
      chatOpen = self.screen and self.screen.text ~= nil })
  end
  if self.showDebug then hud.drawDebug(game, self:debugInfo()) end
  if options.values.showFps and not self.showDebug then
    gui.text("FPS: " .. love.timer.getFPS(), 4, 4, { 1, 1, 0.4 })
  end
  if self.screen then self.screen:draw() end
end

-- Mapa trzymana w ręce: duży podgląd na dole ekranu
function Play:drawHeldMap()
  local game = self.game
  local held = game:heldStack()
  if not held or held.id ~= 358 then return end
  local maps = require("core.maps")
  local map = maps.get(game, held.damage or 0)
  if not map then return end
  local N = maps.SIZE
  self.mapImages = self.mapImages or {}
  local entry = self.mapImages[held.damage or 0]
  if not entry then
    entry = { data = love.image.newImageData(N, N), version = -1 }
    self.mapImages[held.damage or 0] = entry
  end
  if entry.version ~= map.version then
    local d = entry.data
    for z = 0, N - 1 do
      for x = 0, N - 1 do
        local r, gg, b = maps.pixelColor(map.data[x + z * N])
        if r then d:setPixel(x, z, r / 255, gg / 255, b / 255, 1)
        else d:setPixel(x, z, 0.85, 0.78, 0.62, 1) end
      end
    end
    if entry.image then entry.image:replacePixels(d) else
      entry.image = love.graphics.newImage(d)
      entry.image:setFilter("nearest", "nearest")
    end
    entry.version = map.version
  end
  local g = love.graphics
  local w, h = g.getDimensions()
  local size = math.floor(math.min(w * 0.45, h * 0.62))
  local x0, y0 = math.floor(w / 2 - size / 2), math.floor(h - size - 50 * gui.scale)
  -- pergamin
  g.setColor(0.55, 0.43, 0.27, 1)
  g.rectangle("fill", x0 - 10, y0 - 10, size + 20, size + 20)
  g.setColor(0.86, 0.79, 0.62, 1)
  g.rectangle("fill", x0 - 6, y0 - 6, size + 12, size + 12)
  g.setColor(1, 1, 1, 1)
  g.draw(entry.image, x0, y0, 0, size / N, size / N)
  -- znacznik gracza (strzałka)
  local p = game.player
  if map.dim == game.dimension then
    local mx, mz = (p.x - map.x0) / N, (p.z - map.z0) / N
    if mx >= 0 and mx <= 1 and mz >= 0 and mz <= 1 then
      local cx, cy = x0 + mx * size, y0 + mz * size
      local fx, fz = -math.sin(p.yaw), -math.cos(p.yaw)
      local k = size / 40
      g.setColor(1, 1, 1, 1)
      g.polygon("fill", cx + fx * k * 1.6, cy + fz * k * 1.6, cx - fz * k - fx * k, cy + fx * k - fz * k,
        cx + fz * k - fx * k, cy - fx * k - fz * k)
      g.setColor(0.2, 0.2, 0.2, 1)
      g.setLineWidth(1)
      g.polygon("line", cx + fx * k * 1.6, cy + fz * k * 1.6, cx - fz * k - fx * k, cy + fx * k - fz * k,
        cx + fz * k - fx * k, cy - fx * k - fz * k)
    end
  end
  gui.text("Mapa #" .. (held.damage or 0), x0, y0 - 22 * gui.scale, { 1, 1, 1 })
  g.setColor(1, 1, 1, 1)
end

-- Nicki nad głowami innych graczy (gra wieloosobowa)
function Play:drawNameTags(alpha)
  local game = self.game
  if not game.net or not self.showHud then return end
  local g = love.graphics
  local w, h = g.getDimensions()
  local cam = self.camera
  for _, e in ipairs(game.entities.list) do
    if e.type == "player" and e.name and not e.dead then
      local x = e.prevX + (e.x - e.prevX) * alpha
      local y = e.prevY + (e.y - e.prevY) * alpha + 2.1
      local z = e.prevZ + (e.z - e.prevZ) * alpha
      local d = math.sqrt((x - cam.x) ^ 2 + (y - cam.y) ^ 2 + (z - cam.z) ^ 2)
      local sx, sy = cam:project(x, y, z, w, h)
      if sx and d < 64 then
        local mult = math.max(0.7, math.min(1.4, 8 / math.max(d, 1)))
        local tw = gui.textWidth(e.name, mult)
        g.setColor(0, 0, 0, 0.4)
        g.rectangle("fill", sx - tw / 2 - 2, sy - 2, tw + 4, 10 * gui.scale * mult + 2)
        gui.text(e.name, sx - tw / 2, sy, e.sneaking and { 0.7, 0.7, 0.7 } or { 1, 1, 1 }, mult)
      end
    end
  end
  g.setColor(1, 1, 1, 1)
end

function Play:debugInfo()
  local game = self.game
  local p = game.player
  local st = self.renderer.stats
  local bx, by, bz = floor(p.x), floor(p.y), floor(p.z)
  local biome = game.biomeAt and game.biomeAt(bx, bz)
  local facing = ({ "Poludnie (+Z)", "Zachod (-X)", "Polnoc (-Z)", "Wschod (+X)" })
  local dir = floor(((-p.yaw / (math.pi * 2)) * 4 + 2.5) % 4) + 1
  local hit = game.hit
  local stats = love.graphics.getStats()
  local left = {
    "Minecraft Lua (Beta) - " .. love.timer.getFPS() .. " fps",
    string.format("Chunki: %d widoczne / %d meshe / %d w pamieci, kolejka: %d",
      st.drawn or 0, st.total or 0, game.world.chunkCount, st.pending or 0),
    string.format("Byty: %d   Czasteczki: %d   Rysowania: %d", #game.entities.list,
      particles.count(), stats.drawcalls),
    "",
    string.format("XYZ: %.3f / %.3f / %.3f", p.x, p.y, p.z),
    string.format("Blok: %d %d %d   Chunk: %d %d", bx, by, bz, floor(bx / 16), floor(bz / 16)),
    "Kierunek: " .. facing[dir],
    "Biom: " .. (biome and biome.name or "?"),
    string.format("Swiatlo: niebo %d, bloki %d", game.world:getSkyLight(bx, by + 1, bz),
      game.world:getBlockLight(bx, by + 1, bz)),
    string.format("Czas: dzien %d, %d tickow", floor(game.dayTime / 24000) + 1, game.dayTime % 24000),
    "Seed: " .. tostring(game.seed),
  }
  local right = {
    string.format("Pamiec Lua: %.1f MB", collectgarbage("count") / 1024),
    string.format("Tekstury: %.1f MB", stats.texturememory / 1048576),
    "Wierzcholki: " .. (st.vertices or 0),
    string.format("Budowa meshy: %.1f ms", st.buildMs or 0),
  }
  if hit then
    local d = blocks.defs[hit.id]
    right[#right + 1] = ""
    right[#right + 1] = string.format("Cel: %s (%d:%d)", d and d.name or "?", hit.id, hit.meta)
    right[#right + 1] = string.format("na %d %d %d", hit.x, hit.y, hit.z)
  end
  return { left = left, right = right }
end

return Play
