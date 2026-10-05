-- core/commands.lua
-- Komendy czatu (klawisz T albo /): /help, /time, /gamemode, /give, /tp,
-- /weather, /seed, /kill, /summon, /difficulty, /xp, /spawnpoint, /clear,
-- /heal, /fly. Zwraca tekst odpowiedzi.

local items = require("core.items")
local blocks = require("core.blocks")
local mobs = require("core.mobs")

local M = {}

local function findItem(name)
  local n = tonumber(name)
  if n then return items.get(n) and n or nil end
  name = name:lower()
  local id = items.ids[name] or blocks.ids[name]
  if id then return id end
  -- szukanie po polskiej nazwie (bez spacji, małe litery)
  local key = name:gsub("_", " ")
  for i, d in pairs(blocks.defs) do
    if d.label:lower() == key then return i end
  end
  for i, d in pairs(items.defs) do
    if d.label:lower() == key then return i end
  end
  return nil
end

local HELP = {
  "/time set day|night|noon|midnight|<liczba>, /time add <n>",
  "/gamemode survival|creative (0|1)",
  "/give <nazwa|id> [ilosc] [damage]",
  "/tp <x> <y> <z>, /spawnpoint, /seed, /kill, /heal, /clear",
  "/weather clear|rain|thunder, /difficulty 0-3",
  "/summon <pig|cow|sheep|chicken|wolf|zombie|skeleton|spider|creeper|enderman>",
  "/xp <ilosc>",
}

function M.run(game, text)
  local args = {}
  for w in text:gmatch("%S+") do args[#args + 1] = w end
  local cmd = (args[1] or ""):lower():gsub("^/", "")
  local p = game.player

  if cmd == "help" or cmd == "?" then
    return table.concat(HELP, "\n")
  elseif cmd == "time" then
    local sub, val = args[2], args[3]
    local named = { day = 1000, noon = 6000, night = 13000, midnight = 18000, sunrise = 23000 }
    if sub == "set" and val then
      local t = named[val] or tonumber(val)
      if not t then return "Nieznany czas: " .. val end
      game.dayTime = math.floor(game.dayTime / 24000) * 24000 + t
      return "Ustawiono czas na " .. t
    elseif sub == "add" and tonumber(val) then
      game.dayTime = game.dayTime + tonumber(val)
      return "Dodano " .. val .. " tickow"
    end
    return "Uzycie: /time set <day|night|liczba>"
  elseif cmd == "gamemode" or cmd == "gm" then
    local m = args[2]
    if m == "1" or m == "creative" or m == "c" then
      p.gameMode = "creative"
      return "Tryb gry: kreatywny"
    elseif m == "0" or m == "survival" or m == "s" then
      p.gameMode = "survival"
      p.flying = false
      return "Tryb gry: przetrwanie"
    end
    return "Uzycie: /gamemode survival|creative"
  elseif cmd == "give" then
    if not args[2] then return "Uzycie: /give <nazwa|id> [ilosc]" end
    local id = findItem(args[2])
    if not id then return "Nie ma takiego przedmiotu: " .. args[2] end
    local count = tonumber(args[3]) or 1
    local dmg = tonumber(args[4]) or 0
    game:giveItem({ id = id, count = count, damage = dmg })
    return "Dano " .. count .. " x " .. items.label({ id = id, count = count, damage = dmg })
  elseif cmd == "tp" then
    local x, y, z = tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if not (x and y and z) then return "Uzycie: /tp <x> <y> <z>" end
    p.x, p.y, p.z = x, y, z
    p.prevX, p.prevY, p.prevZ = x, y, z
    p.vx, p.vy, p.vz = 0, 0, 0
    p.fallDistance = 0
    return string.format("Teleportowano do %.1f %.1f %.1f", x, y, z)
  elseif cmd == "seed" then
    return "Seed: " .. tostring(game.seed)
  elseif cmd == "weather" then
    local w = args[2]
    if w == "clear" then game.weather.raining, game.weather.thunder = false, false
    elseif w == "rain" then game.weather.raining, game.weather.thunder = true, false
    elseif w == "thunder" then game.weather.raining, game.weather.thunder = true, true
    else return "Uzycie: /weather clear|rain|thunder" end
    game.weather.timer = 12000
    return "Pogoda: " .. w
  elseif cmd == "kill" then
    game.survival.damage(game, 1000, "void")
    return "Auc!"
  elseif cmd == "heal" then
    game.health, game.food, game.saturation = 20, 20, 5
    return "Uleczono"
  elseif cmd == "clear" then
    game.inventory:clear()
    return "Wyczyszczono ekwipunek"
  elseif cmd == "difficulty" then
    local d = tonumber(args[2])
    if not d or d < 0 or d > 3 then return "Uzycie: /difficulty 0-3" end
    game.difficulty = d
    return "Poziom trudnosci: " .. ({ [0] = "spokojny", "latwy", "normalny", "trudny" })[d]
  elseif cmd == "summon" then
    local kind = args[2]
    if not kind or not mobs.DEFS[kind] then return "Nieznany mob" end
    local lx, _, lz = p:lookVector()
    mobs.spawn(game, kind, p.x + lx * 3, p.y + 0.5, p.z + lz * 3)
    return "Przywolano: " .. mobs.DEFS[kind].label
  elseif cmd == "xp" then
    local n = tonumber(args[2])
    if not n then return "Uzycie: /xp <ilosc>" end
    game:addXp(n)
    return "Dodano " .. n .. " punktow doswiadczenia"
  elseif cmd == "spawnpoint" then
    game.spawnX, game.spawnY, game.spawnZ = p.x, p.y, p.z
    game.worldSpawnX, game.worldSpawnY, game.worldSpawnZ = p.x, p.y, p.z
    return "Ustawiono punkt odrodzenia"
  end
  return "Nieznana komenda. Wpisz /help"
end

return M
