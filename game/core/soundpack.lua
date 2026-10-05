-- core/soundpack.lua
-- Szukanie oryginalnych dźwięków Minecrafta na komputerze gracza.
-- Projekt NIE zawiera dźwięków Mojang (bez Minecrafta gra używa wbudowanych
-- darmowych dźwięków z folderu "freesounds"): gra czyta je z Twojej instalacji
-- Minecrafta (folder .minecraft/assets: indeks JSON + pliki .ogg nazwane
-- skrótem SHA1) albo z folderu "sounds" (np. rozpakowana paczka zasobów).
--
-- Dźwięki grupujemy po nazwie bez numeru wariantu:
--   "dig/grass1.ogg", "dig/grass2.ogg" -> grupa "dig/grass" (losowy wariant).
-- Bez love.*, więc da się testować przez lua.exe.

local M = {}

-- Grupa z względnej ścieżki dźwięku ("mob/zombie/say3.ogg" -> "mob/zombie/say")
function M.groupOf(rel)
  local g = rel:gsub("%.%w+$", ""):gsub("%d+$", "")
  return g
end

-- Indeks zasobów MC: "minecraft/sounds/dig/grass1.ogg": {"hash": "...", "size": 123}
-- Zwraca listę { rel = "dig/grass1.ogg", hash = "..." }
function M.parseIndex(text)
  local out = {}
  for key, body in text:gmatch('"([^"]+%.ogg)"%s*:%s*(%b{})') do
    local rel = key:match("^minecraft/sounds/(.+)$") or key:match("^sounds/(.+)$")
    local hash = body:match('"hash"%s*:%s*"(%x+)"')
    if rel and hash then out[#out + 1] = { rel = rel, hash = hash } end
  end
  return out
end

-- Możliwe foldery .minecraft (Windows, Linux, macOS)
function M.minecraftDirs(getenv)
  getenv = getenv or os.getenv
  local list = {}
  local appdata = getenv("APPDATA")
  if appdata then list[#list + 1] = appdata .. "\\.minecraft" end
  local home = getenv("HOME")
  if home then
    list[#list + 1] = home .. "/.minecraft"
    list[#list + 1] = home .. "/Library/Application Support/minecraft"
    list[#list + 1] = home .. "/.var/app/com.mojang.Minecraft/.minecraft"
  end
  return list
end

local function sep(dir) return dir:find("\\", 1, true) and "\\" or "/" end

local function fileSize(path, open)
  local f = open(path, "rb")
  if not f then return nil end
  local size = f:seek("end")
  f:close()
  return size
end

-- Nazwy plików indeksu do sprawdzenia (nowe wersje: numery, starsze: "1.12" itd.)
function M.indexNames()
  local names = {}
  for i = 40, 1, -1 do names[#names + 1] = tostring(i) end
  for minor = 21, 7, -1 do
    names[#names + 1] = "1." .. minor
    for patch = 1, 6 do names[#names + 1] = "1." .. minor .. "." .. patch end
  end
  names[#names + 1] = "legacy"
  names[#names + 1] = "pre-1.6"
  return names
end

-- Szuka największego indeksu w <mc>/assets/indexes. Zwraca ścieżkę folderu
-- assets i listę dźwięków { rel, path } albo nil.
function M.scanMinecraft(open, getenv)
  open = open or io.open
  for _, mc in ipairs(M.minecraftDirs(getenv)) do
    local s = sep(mc)
    local assets = mc .. s .. "assets"
    local best, bestSize
    for _, name in ipairs(M.indexNames()) do
      local p = assets .. s .. "indexes" .. s .. name .. ".json"
      local size = fileSize(p, open)
      if size and (not bestSize or size > bestSize) then best, bestSize = p, size end
    end
    if best then
      local f = open(best, "rb")
      local text = f and f:read("*a") or ""
      if f then f:close() end
      local list = {}
      for _, e in ipairs(M.parseIndex(text)) do
        local path = assets .. s .. "objects" .. s .. e.hash:sub(1, 2) .. s .. e.hash
        list[#list + 1] = { rel = e.rel, path = path }
      end
      if #list > 0 then return assets, list, best end
    end
  end
  return nil
end

-- Buduje bibliotekę: grupa -> lista plików (każdy { rel, path | lovePath })
function M.library(entries, lib)
  lib = lib or {}
  for _, e in ipairs(entries) do
    local g = M.groupOf(e.rel)
    local list = lib[g]
    if not list then list = {}; lib[g] = list end
    list[#list + 1] = e
  end
  return lib
end

-- ---------------------------------------------------------------------------
-- Które pliki Minecrafta grają dla zdarzeń gry (pierwsza istniejąca grupa)
-- ---------------------------------------------------------------------------
M.EVENTS = {
  pop = { "random/pop" }, click = { "random/click" }, hurt = { "damage/hit", "entity/player/hurt" },
  explosion = { "random/explode" }, fuse = { "random/fuse" }, fizz = { "random/fizz" },
  bow = { "random/bow" }, arrow_hit = { "random/bowhit" }, throw = { "random/throw", "random/bow" },
  eat = { "random/eat" }, burp = { "random/burp" }, orb = { "random/orb" },
  levelup = { "random/levelup" }, door = { "random/door_open", "block/wooden_door/open" },
  chest_open = { "random/chestopen", "block/chest/open" },
  chest_close = { "random/chestclosed", "block/chest/close" },
  bucket = { "item/bucket/fill", "random/splash" }, splash = { "random/splash", "entity/generic/splash" },
  fall_small = { "damage/fallsmall" }, fall_big = { "damage/fallbig" }, break_tool = { "random/break" },
  shear = { "mob/sheep/shear" }, ignite = { "fire/ignition" }, thunder = { "ambient/weather/thunder" },
  piston = { "tile/piston/out", "block/piston/extend" }, teleport = { "mob/endermen/portal" },
  enderman_stare = { "mob/endermen/stare" }, rain = { "ambient/weather/rain" },
  drink = { "random/drink" }, glass = { "random/glass", "block/glass/break" },
  brew = { "block/brewing_stand/brew" }, paper = { "item/book/page", "random/click" },
  enchant = { "block/enchantment_table/enchant", "random/levelup" },
  dragon_growl = { "mob/enderdragon/growl" }, dragon_wings = { "mob/enderdragon/wings" },
  portal_end = { "block/end_portal/endportal", "portal/travel" },
  fire = { "fire/fire" }, lava = { "liquid/lava" }, water = { "liquid/water" },
}

-- Głosy mobów: say / hurt / death
M.MOBS = {
  pig = { say = { "mob/pig/say" }, hurt = { "mob/pig/say" }, death = { "mob/pig/death" } },
  cow = { say = { "mob/cow/say" }, hurt = { "mob/cow/hurt" }, death = { "mob/cow/hurt" } },
  sheep = { say = { "mob/sheep/say" }, hurt = { "mob/sheep/hurt", "mob/sheep/say" },
    death = { "mob/sheep/hurt", "mob/sheep/say" } },
  chicken = { say = { "mob/chicken/say" }, hurt = { "mob/chicken/hurt" }, death = { "mob/chicken/hurt" } },
  wolf = { say = { "mob/wolf/bark" }, hurt = { "mob/wolf/hurt" }, death = { "mob/wolf/death" } },
  zombie = { say = { "mob/zombie/say" }, hurt = { "mob/zombie/hurt" }, death = { "mob/zombie/death" } },
  skeleton = { say = { "mob/skeleton/say" }, hurt = { "mob/skeleton/hurt" }, death = { "mob/skeleton/death" } },
  spider = { say = { "mob/spider/say" }, hurt = { "mob/spider/hurt", "mob/spider/say" },
    death = { "mob/spider/death" } },
  creeper = { say = { "mob/creeper/say" }, hurt = { "mob/creeper/say" }, death = { "mob/creeper/death" } },
  ghast = { say = { "mob/ghast/moan" }, hurt = { "mob/ghast/scream", "mob/ghast/moan" },
    death = { "mob/ghast/death", "mob/ghast/moan" },
    shoot = { "mob/ghast/fireball" }, charge = { "mob/ghast/charge" } },
  pigman = { say = { "mob/zombiepig/zpig" }, hurt = { "mob/zombiepig/zpighurt" },
    death = { "mob/zombiepig/zpigdeath" } },
  enderman = { say = { "mob/endermen/idle" }, hurt = { "mob/endermen/hit" }, death = { "mob/endermen/death" } },
  blaze = { say = { "mob/blaze/breathe" }, hurt = { "mob/blaze/hit" }, death = { "mob/blaze/death" } },
  dragon = { say = { "mob/enderdragon/growl" }, hurt = { "mob/enderdragon/hit" },
    death = { "mob/enderdragon/end", "mob/enderdragon/growl" } },
}

-- Kopanie (dig) i kroki (step) zależne od materiału bloku
M.DIG = { glass = { "random/glass", "dig/stone" } }
M.STEP = { glass = { "step/stone" } }

-- Muzyka (C418): utwory według miejsca
function M.musicTracks(lib, context)
  local prefixes
  if context == "menu" then prefixes = { "music/menu/" }
  elseif context == "nether" then prefixes = { "music/game/nether/" }
  elseif context == "end" then prefixes = { "music/game/end/" }
  elseif context == "creative" then prefixes = { "music/game/creative/", "music/game/" }
  else prefixes = { "music/game/" } end
  local out = {}
  for _, prefix in ipairs(prefixes) do
    for g, list in pairs(lib) do
      if g:sub(1, #prefix) == prefix then
        local rest = g:sub(#prefix + 1)
        -- "music/game/" bez podfolderów (nether, end, creative, water...)
        if prefix ~= "music/game/" or not rest:find("/", 1, true) then
          for _, e in ipairs(list) do out[#out + 1] = e end
        end
      end
    end
    if #out > 0 then break end
  end
  table.sort(out, function(a, b) return a.rel < b.rel end)
  return out
end

-- Pierwsza grupa z listy kandydatów, która istnieje w bibliotece
function M.pick(lib, candidates)
  for _, g in ipairs(candidates or {}) do
    if lib[g] and #lib[g] > 0 then return lib[g] end
  end
  return nil
end

return M
