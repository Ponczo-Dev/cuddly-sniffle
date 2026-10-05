-- states/loading.lua
-- Ekran ładowania: tworzy (albo wczytuje) świat i generuje teren wokół
-- gracza po kawałku, pokazując postęp - okno nie "zamarza".

local Game = require("core.game")
local save = require("core.save")
local options = require("core.options")
local gui = require("render.gui")
local atlas = require("render.atlas")
local tiles = require("core.tiles")
local renderInit = require("render.init")

local Loading = {}

local RADIUS = 2 -- tyle chunków wokół startu przygotowujemy przed wejściem

-- params: { folder = "..." } (wczytanie) albo { create = { name, seed, gameMode, hardcore } }
function Loading:enter(params)
  renderInit.load()
  self.params = params or {}
  self.manager = self.params.manager
  self.stage = "init"
  self.progress = 0
  self.message = "Przygotowywanie swiata..."
  love.mouse.setRelativeMode(false)
end

function Loading:start()
  local p = self.params
  if p.create then
    local c = p.create
    local folder = p.temporary and nil or save.newFolderName(c.name)
    self.folder = folder
    self.game = Game.new({ seed = c.seed, name = c.name, gameMode = c.gameMode,
      difficulty = c.hardcore and 3 or options.values.difficulty, hardcore = c.hardcore,
      saveFolder = folder })
    self.isNew = true
    local x, z = self.game:chooseSpawnColumn()
    self.spawnX, self.spawnZ = x, z
    local pl = self.game.player
    pl.x, pl.z = x + 0.5, z + 0.5
    self.message = "Generowanie terenu..."
    if c.gameMode == "creative" then
      -- startowy zestaw bloków w pasku
      local start = { 1, 4, 3, 5, 17, 20, 45, 50, 58 }
      for i, id in ipairs(start) do self.game.inventory:set(i, { id = id, count = 64, damage = 0 }) end
    end
  else
    local data = save.loadLevel(p.folder)
    if not data then
      self.message = "Nie mozna wczytac swiata!"
      self.stage = "error"
      return
    end
    self.folder = p.folder
    self.game = Game.new({ seed = data.seed, name = data.name, gameMode = data.gameMode,
      difficulty = data.difficulty, hardcore = data.hardcore, saveFolder = p.folder })
    save.applyLevel(self.game, data)
    local dim = self.game.savedDimension
    if dim == "nether" or dim == "end" then self.game:setDimension(dim) end
    self.isNew = false
    self.spawnX, self.spawnZ = math.floor(self.game.player.x), math.floor(self.game.player.z)
    self.message = "Wczytywanie swiata..."
  end
  self.game.renderDistance = options.values.renderDistance
  self.stage = "generate"
end

function Loading:update()
  if self.stage == "init" then
    self:start()
    return
  end
  if self.stage ~= "generate" then return end
  local game = self.game
  local cx, cz = math.floor(self.spawnX / 16), math.floor(self.spawnZ / 16)
  local start = love.timer.getTime()
  repeat
    local g, l = game.world:updateLoading(cx, cz, RADIUS, 1)
  until (g == 0 and l == 0) or love.timer.getTime() - start > 0.05
  -- postęp: oświetlone chunki w promieniu
  local total, done = 0, 0
  for dz = -RADIUS - 1, RADIUS + 1 do
    for dx = -RADIUS - 1, RADIUS + 1 do
      total = total + 1
      local c = game.world:getChunk(cx + dx, cz + dz)
      if c and c.lit then done = done + 1 end
    end
  end
  self.progress = done / total
  if done >= total then self:finish() end
end

function Loading:finish()
  local game = self.game
  if self.isNew then
    local y = game:surfaceY(self.spawnX, self.spawnZ)
    game.worldSpawnX, game.worldSpawnY, game.worldSpawnZ = self.spawnX + 0.5, y, self.spawnZ + 0.5
    local p = game.player
    p.x, p.y, p.z = self.spawnX + 0.5, y, self.spawnZ + 0.5
    p.prevX, p.prevY, p.prevZ = p.x, p.y, p.z
    if self.folder then save.saveLevel(self.folder, game) end
  end
  self.stage = "done"
  self.manager:switch(require("states.play"), { game = game, folder = self.folder, manager = self.manager,
    openLan = self.params.openLan, hostName = self.params.hostName })
end

function Loading:draw()
  local g = love.graphics
  local w, h = g.getDimensions()
  local s = gui.scale
  gui.dirtBackground(atlas.image, atlas.quads[tiles.get("dirt")])
  gui.text(self.message, 0, h / 2 - 20 * s, nil, 1.2, "center", w)
  if self.stage == "generate" then
    local bw = 100 * s
    g.setColor(0.5, 0.5, 0.5)
    g.rectangle("fill", w / 2 - bw / 2, h / 2 + 4 * s, bw, 2 * s)
    g.setColor(0.5, 1, 0.5)
    g.rectangle("fill", w / 2 - bw / 2, h / 2 + 4 * s, bw * self.progress, 2 * s)
    g.setColor(1, 1, 1)
  elseif self.stage == "error" then
    gui.text("Nacisnij ESC", 0, h / 2 + 10 * s, { 0.7, 0.7, 0.7 }, 1, "center", w)
  end
end

function Loading:keypressed(key)
  if key == "escape" and self.stage == "error" then
    self.manager:switch(require("states.menu"), { manager = self.manager })
  end
end

return Loading
