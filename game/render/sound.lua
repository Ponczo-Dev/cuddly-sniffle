-- render/sound.lua
-- Dźwięki i muzyka z ORYGINALNEGO Minecrafta zainstalowanego na komputerze
-- gracza (folder .minecraft) albo z folderu "sounds" (np. paczka zasobów).
-- Projekt nie zawiera plików Mojang: gdy ich nie ma, gra jest po prostu cicha.
-- Dźwięk przestrzenny (głośność i panorama) przez audio pozycyjne LÖVE.

local blocks = require("core.blocks")
local soundpack = require("core.soundpack")

local M = {}

local lib = {}        -- grupa -> lista plików
local cache = {}      -- plik -> Source (static)
local active = {}
local volume = 1
local musicVolume = 0.5
local enabled = true
local loaded = false
local rainSource
local music = { source = nil, timer = 10, context = nil }

-- Skąd są dźwięki (do wyświetlenia w menu)
M.info = { count = 0, source = nil }

-- Materiał bloku do dźwięku kopania/kroków (nazwy jak foldery dig/ i step/ w MC)
function M.material(id)
  local d = blocks.defs[id]
  if not d then return "stone" end
  local n = d.name
  if n == "glass" or n == "ice" or n == "glowstone" then return "glass" end
  if n == "wool" then return "cloth" end
  if n == "sand" or n == "soul_sand" then return "sand" end
  if n == "gravel" or n == "dirt" or n == "farmland" or n == "clay" then return "gravel" end
  if n == "snow" or n == "snow_layer" then return "snow" end
  if d.tool == "axe" or n == "ladder" then return "wood" end
  if d.tool == "pickaxe" or n == "bedrock" or n == "obsidian" then return "stone" end
  return "grass"
end

-- ---------------------------------------------------------------------------
-- Wczytywanie
-- ---------------------------------------------------------------------------
-- Pliki z folderu "sounds" (w folderze zapisu albo w folderze gry), np.
-- sounds/dig/grass1.ogg, sounds/mob/zombie/say1.ogg, sounds/music/game/calm1.ogg
local function scanFolder(dir, rel, out)
  for _, name in ipairs(love.filesystem.getDirectoryItems(dir)) do
    local path = dir .. "/" .. name
    local r = rel == "" and name or (rel .. "/" .. name)
    local info = love.filesystem.getInfo(path)
    if info and info.type == "directory" then
      scanFolder(path, r, out)
    elseif name:match("%.ogg$") or name:match("%.wav$") or name:match("%.mp3$") then
      out[#out + 1] = { rel = r, lovePath = path }
    end
  end
  return out
end

function M.load()
  if loaded then return end
  loaded = true
  if not love.audio then enabled = false return end
  love.audio.setDistanceModel("linearclamped")
  lib = {}
  local ok, assets, list = pcall(soundpack.scanMinecraft, io.open, os.getenv)
  if ok and assets then
    soundpack.library(list, lib)
    M.info.source = "Minecraft"
    M.info.count = #list
  end
  -- własne pliki zastępują te z Minecrafta (całe grupy)
  local own = scanFolder("sounds", "", {})
  if #own > 0 then
    local ownLib = soundpack.library(own)
    for g, l in pairs(ownLib) do lib[g] = l end
    M.info.source = M.info.source and (M.info.source .. " + folder sounds") or "folder sounds"
    M.info.count = M.info.count + #own
  end
end

local function fileData(e)
  if e.lovePath then return love.filesystem.newFileData(e.lovePath) end
  local f = io.open(e.path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return love.filesystem.newFileData(data, e.rel:match("[^/]+$") or "dzwiek.ogg")
end

local function sourceFor(e)
  local s = cache[e]
  if s == false then return nil end
  if not s then
    local ok, src = pcall(function()
      local fd = fileData(e)
      if not fd then return nil end
      return love.audio.newSource(love.sound.newSoundData(fd), "static")
    end)
    s = ok and src or false
    cache[e] = s
    if not s then return nil end
  end
  return s
end

local function randomEntry(list)
  if not list or #list == 0 then return nil end
  return list[math.random(1, #list)]
end

-- ---------------------------------------------------------------------------
-- Odtwarzanie
-- ---------------------------------------------------------------------------
function M.setVolume(v)
  volume = v
  if love.audio then love.audio.setVolume(v) end
end

function M.setMusicVolume(v)
  musicVolume = v
  if music.source then
    if v <= 0 then music.source:stop(); music.source = nil else music.source:setVolume(v) end
  end
end

function M.setListener(x, y, z, fx, fy, fz)
  if not enabled then return end
  love.audio.setPosition(x, y, z)
  love.audio.setOrientation(fx, fy, fz, 0, 1, 0)
end

local function playList(list, x, y, z, vol, pitch)
  if not enabled or volume <= 0 then return end
  local e = randomEntry(list)
  local s = e and sourceFor(e)
  if not s then return end
  for i = #active, 1, -1 do
    if not active[i]:isPlaying() then table.remove(active, i) end
  end
  if #active > 24 then return end
  local c = s:clone()
  c:setVolume(vol or 1)
  c:setPitch((pitch or 1) * (0.92 + math.random() * 0.16))
  if x and c:getChannelCount() == 1 then
    c:setRelative(false)
    c:setPosition(x, y, z)
    c:setAttenuationDistances(2, 24)
  else
    c:setRelative(true)
    c:setPosition(0, 0, 0)
  end
  c:play()
  active[#active + 1] = c
end

-- Zdarzenie gry po nazwie (np. "explosion", "pop", "voice_zombie")
function M.play(name, x, y, z, vol, pitch)
  if not enabled then return end
  local cands
  local kind = name:match("^voice_(.+)$")
  if kind then
    local m = soundpack.MOBS[kind]
    cands = m and m.say
  else
    cands = soundpack.EVENTS[name]
    if not cands then
      local mat = name:match("^dig_(.+)$")
      if mat then cands = soundpack.DIG[mat] or { "dig/" .. mat } end
    end
  end
  playList(soundpack.pick(lib, cands), x, y, z, vol, pitch)
end

-- Kopanie/stawianie (głośno: dig/) albo kroki i uderzenia (cicho: step/)
function M.dig(id, x, y, z, vol)
  vol = vol or 1
  local mat = M.material(id)
  local cands
  if vol >= 0.5 then cands = soundpack.DIG[mat] or { "dig/" .. mat }
  else cands = soundpack.STEP[mat] or { "step/" .. mat } end
  playList(soundpack.pick(lib, cands), x, y, z, vol)
end

-- Głosy mobów: what = "say" | "hurt" | "death"
function M.mob(kind, what, x, y, z, pitch)
  local m = soundpack.MOBS[kind]
  if not m then return end
  playList(soundpack.pick(lib, m[what] or m.say), x, y, z, what == "say" and 0.8 or 1, pitch)
end

function M.voice(kind, x, y, z, pitch)
  M.mob(kind, "say", x, y, z, pitch)
end

-- Deszcz w tle (zapętlony)
function M.setRain(strength)
  if not enabled then return end
  if strength > 0.05 then
    if not rainSource then
      local e = randomEntry(soundpack.pick(lib, soundpack.EVENTS.rain))
      local s = e and sourceFor(e)
      if not s then return end
      rainSource = s:clone()
      rainSource:setLooping(true)
      rainSource:setRelative(true)
      rainSource:play()
    end
    rainSource:setVolume(strength * 0.5)
  elseif rainSource then
    rainSource:stop()
    rainSource = nil
  end
end

-- ---------------------------------------------------------------------------
-- Muzyka (C418) jak w Minecrafcie: utwór, potem kilka minut ciszy
-- context: "menu" | "game" | "creative" | "nether" | "end"
-- ---------------------------------------------------------------------------
function M.updateMusic(dt, context)
  if not enabled or musicVolume <= 0 then return end
  if music.context ~= context then
    -- menu -> gra (i odwrotnie): zmiana nastroju, krótka przerwa
    local wasMenu = music.context == "menu" or context == "menu"
    music.context = context
    if wasMenu and music.source then music.source:stop(); music.source = nil end
    music.timer = math.min(music.timer, context == "menu" and 1 or 15)
  end
  if music.source then
    if music.source:isPlaying() then return end
    music.source = nil
    music.timer = 120 + math.random() * 240
  end
  music.timer = music.timer - dt
  if music.timer > 0 then return end
  local tracks = soundpack.musicTracks(lib, context)
  local e = randomEntry(tracks)
  music.timer = 60
  if not e then return end
  local ok, src = pcall(function()
    local fd = fileData(e)
    return fd and love.audio.newSource(love.sound.newDecoder(fd), "stream")
  end)
  if ok and src then
    src:setRelative(true)
    src:setVolume(musicVolume)
    src:play()
    music.source = src
  end
end

function M.isMusicPlaying()
  return music.source ~= nil and music.source:isPlaying()
end

function M.stopMusic()
  if music.source then music.source:stop(); music.source = nil end
end

function M.stopAll()
  for _, s in ipairs(active) do s:stop() end
  active = {}
  if rainSource then rainSource:stop(); rainSource = nil end
end

return M
