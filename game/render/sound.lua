-- render/sound.lua
-- Dźwięki generowane w kodzie (bez plików audio): szum, tony i obwiednie.
-- Kopanie i kroki zależne od materiału, głosy mobów, wybuchy, łuk, jedzenie,
-- doświadczenie, deszcz. Dźwięk przestrzenny (głośność i panorama) przez
-- wbudowane audio pozycyjne LÖVE.

local blocks = require("core.blocks")
local Rng = require("core.rng")

local M = {}

local RATE = 22050
local cache = {}
local active = {}
local volume = 1
local enabled = true
local rng = Rng.new(31337)
local rainSource

local function noise() return rng:next() * 2 - 1 end

-- Tworzy SoundData z funkcji próbki fn(t, i, n) -> -1..1
local function synth(duration, fn)
  local n = math.floor(duration * RATE)
  local sd = love.sound.newSoundData(n, RATE, 16, 1)
  local prev = 0
  for i = 0, n - 1 do
    local t = i / RATE
    local v = fn(t, i, n, prev)
    prev = v
    if v > 1 then v = 1 elseif v < -1 then v = -1 end
    sd:setSample(i, v)
  end
  return sd
end

local function env(t, attack, decay)
  if t < attack then return t / attack end
  return math.exp(-(t - attack) / decay)
end

-- Szum przefiltrowany dolnoprzepustowo (k mały = ciemniejszy dźwięk)
local function filteredNoise(duration, k, attack, decay, gain)
  local lp = 0
  return synth(duration, function(t)
    lp = lp + (noise() - lp) * k
    return lp * env(t, attack, decay) * (gain or 1)
  end)
end

local function tone(duration, f0, f1, wave, attack, decay, gain)
  local phase = 0
  return synth(duration, function(t)
    local f = f0 + (f1 - f0) * (t / duration)
    phase = phase + f / RATE
    local s
    if wave == "square" then s = (phase % 1) < 0.5 and 0.6 or -0.6
    elseif wave == "saw" then s = ((phase % 1) * 2 - 1) * 0.7
    else s = math.sin(phase * math.pi * 2) end
    return s * env(t, attack, decay) * (gain or 1)
  end)
end

local GENERATORS = {
  dig_stone = function() return filteredNoise(0.15, 0.5, 0.002, 0.04, 0.9) end,
  dig_wood = function()
    local phase = 0
    return synth(0.15, function(t)
      phase = phase + 180 / RATE
      return (math.sin(phase * math.pi * 2) * 0.5 + noise() * 0.4) * env(t, 0.002, 0.03)
    end)
  end,
  dig_grass = function() return filteredNoise(0.18, 0.2, 0.005, 0.05, 1.0) end,
  dig_gravel = function() return filteredNoise(0.18, 0.35, 0.003, 0.05, 1.0) end,
  dig_sand = function() return filteredNoise(0.2, 0.12, 0.01, 0.06, 1.1) end,
  dig_snow = function() return filteredNoise(0.2, 0.08, 0.01, 0.06, 1.2) end,
  dig_cloth = function() return filteredNoise(0.15, 0.06, 0.005, 0.04, 1.2) end,
  dig_glass = function()
    return synth(0.35, function(t)
      return (math.sin(t * 2 * math.pi * 3100) * 0.3 + math.sin(t * 2 * math.pi * 4700) * 0.2
        + noise() * 0.3) * env(t, 0.001, 0.06)
    end)
  end,
  pop = function() return tone(0.08, 600, 1200, "sine", 0.002, 0.03, 0.5) end,
  click = function() return tone(0.04, 900, 700, "square", 0.001, 0.01, 0.4) end,
  hurt = function()
    return synth(0.25, function(t)
      return (math.sin(t * 2 * math.pi * (220 - t * 300)) * 0.6 + noise() * 0.2) * env(t, 0.005, 0.08)
    end)
  end,
  explosion = function()
    local lp = 0
    return synth(1.6, function(t)
      lp = lp + (noise() - lp) * 0.06
      return lp * 3 * env(t, 0.005, 0.45)
    end)
  end,
  fuse = function() return filteredNoise(1.2, 0.9, 0.05, 1.0, 0.35) end,
  fizz = function() return filteredNoise(0.5, 0.95, 0.01, 0.2, 0.4) end,
  bow = function() return tone(0.25, 400, 180, "sine", 0.002, 0.08, 0.6) end,
  arrow_hit = function() return filteredNoise(0.1, 0.3, 0.001, 0.02, 1.0) end,
  throw = function() return filteredNoise(0.15, 0.25, 0.03, 0.05, 0.6) end,
  eat = function() return filteredNoise(0.1, 0.4, 0.002, 0.03, 0.8) end,
  burp = function() return tone(0.3, 120, 90, "saw", 0.02, 0.1, 0.5) end,
  orb = function()
    return synth(0.15, function(t)
      return math.sin(t * 2 * math.pi * 1600) * env(t, 0.002, 0.05) * 0.4
        + math.sin(t * 2 * math.pi * 2400) * env(t, 0.002, 0.03) * 0.2
    end)
  end,
  levelup = function()
    return synth(0.6, function(t)
      local notes = { 523, 659, 784, 1047 }
      local idx = math.min(4, math.floor(t / 0.12) + 1)
      local lt = t - (idx - 1) * 0.12
      return math.sin(t * 2 * math.pi * notes[idx]) * env(lt, 0.005, 0.1) * 0.4
    end)
  end,
  door = function()
    return synth(0.25, function(t)
      return (math.sin(t * 2 * math.pi * (300 + math.sin(t * 60) * 40)) * 0.3 + noise() * 0.3)
        * env(t, 0.005, 0.07)
    end)
  end,
  bucket = function() return filteredNoise(0.3, 0.15, 0.02, 0.1, 1.0) end,
  splash = function() return filteredNoise(0.5, 0.4, 0.01, 0.15, 0.9) end,
  fall_small = function() return filteredNoise(0.12, 0.1, 0.002, 0.04, 1.2) end,
  fall_big = function() return filteredNoise(0.25, 0.08, 0.002, 0.08, 1.5) end,
  break_tool = function() return filteredNoise(0.2, 0.7, 0.001, 0.05, 1.0) end,
  shear = function() return filteredNoise(0.15, 0.8, 0.002, 0.04, 0.6) end,
  ignite = function() return filteredNoise(0.2, 0.9, 0.002, 0.06, 0.6) end,
  thunder = function()
    local lp = 0
    return synth(2.5, function(t)
      lp = lp + (noise() - lp) * 0.03
      return lp * 4 * env(t, 0.05, 0.9)
    end)
  end,
  piston = function()
    return synth(0.25, function(t)
      return (noise() * 0.5 + math.sin(t * 2 * math.pi * 90) * 0.4) * env(t, 0.003, 0.06)
    end)
  end,
  teleport = function() return tone(0.4, 200, 1400, "sine", 0.01, 0.15, 0.4) end,
  enderman_stare = function() return tone(0.8, 90, 60, "saw", 0.05, 0.4, 0.5) end,
  rain = function() return filteredNoise(2.0, 0.5, 0, 1000, 0.25) end,
  -- głosy mobów
  voice_pig = function() return tone(0.25, 300, 200, "square", 0.01, 0.08, 0.35) end,
  voice_cow = function() return tone(0.8, 140, 110, "saw", 0.08, 0.35, 0.4) end,
  voice_sheep = function()
    return synth(0.5, function(t)
      return math.sin(t * 2 * math.pi * (350 + math.sin(t * 40) * 30)) * 0.4 * env(t, 0.03, 0.2)
    end)
  end,
  voice_chicken = function() return tone(0.12, 900, 1300, "square", 0.005, 0.04, 0.25) end,
  voice_wolf = function() return tone(0.2, 500, 350, "saw", 0.01, 0.06, 0.35) end,
  voice_zombie = function()
    return synth(0.8, function(t)
      return (math.sin(t * 2 * math.pi * (90 + math.sin(t * 9) * 20)) * 0.5 + noise() * 0.1)
        * env(t, 0.1, 0.35)
    end)
  end,
  voice_skeleton = function()
    return synth(0.4, function(t)
      local click = (math.floor(t * 30) % 2 == 0) and 1 or 0
      return noise() * click * env(t, 0.005, 0.15) * 0.6
    end)
  end,
  voice_spider = function() return filteredNoise(0.4, 0.7, 0.02, 0.15, 0.6) end,
  voice_creeper = function() return filteredNoise(0.3, 0.8, 0.02, 0.1, 0.3) end,
  voice_ghast = function() return tone(0.6, 700, 300, "saw", 0.02, 0.25, 0.4) end,
  voice_pigman = function() return tone(0.5, 180, 120, "square", 0.03, 0.2, 0.35) end,
  voice_enderman = function() return tone(0.5, 600, 200, "sine", 0.01, 0.2, 0.4) end,
}

-- Materiał bloku do dźwięku kopania/kroków
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

local function get(name)
  local s = cache[name]
  if s == false then return nil end
  if not s then
    local gen = GENERATORS[name]
    if not gen then cache[name] = false return nil end
    local ok, sd = pcall(gen)
    if not ok then cache[name] = false return nil end
    s = love.audio.newSource(sd, "static")
    cache[name] = s
  end
  return s
end

function M.load()
  if not love.audio then enabled = false return end
  love.audio.setDistanceModel("linearclamped")
  -- wygeneruj najczęstsze z góry (żeby nie było przycięcia przy pierwszym użyciu)
  for _, n in ipairs({ "dig_stone", "dig_grass", "dig_wood", "dig_gravel", "pop", "hurt", "click" }) do
    get(n)
  end
end

function M.setVolume(v)
  volume = v
  if love.audio then love.audio.setVolume(v) end
end

function M.setListener(x, y, z, fx, fy, fz)
  if not enabled then return end
  love.audio.setPosition(x, y, z)
  love.audio.setOrientation(fx, fy, fz, 0, 1, 0)
end

-- Odtwarza dźwięk; x,y,z = nil -> bez pozycji (np. kliknięcie w menu)
function M.play(name, x, y, z, vol, pitch)
  if not enabled or volume <= 0 then return end
  local s = get(name)
  if not s then return end
  -- limit jednoczesnych dźwięków
  for i = #active, 1, -1 do
    if not active[i]:isPlaying() then table.remove(active, i) end
  end
  if #active > 24 then return end
  local c = s:clone()
  c:setVolume(vol or 1)
  c:setPitch((pitch or 1) * (0.9 + rng:next() * 0.2))
  if x then
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

function M.dig(id, x, y, z, vol)
  M.play("dig_" .. M.material(id), x, y, z, vol or 1)
end

function M.voice(kind, x, y, z, pitch)
  M.play("voice_" .. kind, x, y, z, 0.8, pitch)
end

-- Szum deszczu w tle
function M.setRain(strength)
  if not enabled then return end
  if strength > 0.05 then
    if not rainSource then
      local s = get("rain")
      if not s then return end
      rainSource = s:clone()
      rainSource:setLooping(true)
      rainSource:setRelative(true)
      rainSource:play()
    end
    rainSource:setVolume(strength * 0.6)
  elseif rainSource then
    rainSource:stop()
    rainSource = nil
  end
end

function M.stopAll()
  for _, s in ipairs(active) do s:stop() end
  active = {}
  if rainSource then rainSource:stop(); rainSource = nil end
end

return M
