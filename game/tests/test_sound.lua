-- tests/test_sound.lua
-- Szukanie dźwięków Minecrafta (indeks zasobów + pliki po skrócie).
local T = require("tests.testlib")
local soundpack = require("core.soundpack")

local suite = T.suite("dzwieki")

suite:test("grupy wariantow i indeks zasobow", function()
  T.eq(soundpack.groupOf("dig/grass3.ogg"), "dig/grass")
  T.eq(soundpack.groupOf("random/door_open.ogg"), "random/door_open")
  T.eq(soundpack.groupOf("mob/zombiepig/zpighurt2.ogg"), "mob/zombiepig/zpighurt")
  local text = [[{"objects": {"minecraft/sounds/dig/grass1.ogg": {"hash": "ab12cd", "size": 10},
    "minecraft/sounds/dig/grass2.ogg": {"hash": "ef34ab", "size": 11},
    "minecraft/lang/pl_pl.json": {"hash": "999999", "size": 5},
    "minecraft/sounds/music/game/calm1.ogg": {"hash": "cc11dd", "size": 99}}}]]
  local list = soundpack.parseIndex(text)
  T.eq(#list, 3, "tylko dzwieki .ogg")
  local lib = soundpack.library(list)
  T.eq(#lib["dig/grass"], 2, "dwa warianty trawy")
  T.truthy(soundpack.pick(lib, { "dig/nic", "dig/grass" }), "pierwsza istniejaca grupa")
  T.eq(#soundpack.musicTracks(lib, "game"), 1, "muzyka w grze")
  T.eq(#soundpack.musicTracks(lib, "menu"), 0, "brak muzyki menu")
end)

suite:test("odczyt z folderu .minecraft (sztuczny)", function()
  local files = {
    ["/dom/.minecraft/assets/indexes/17.json"] = [[{"objects":{"minecraft/sounds/random/pop.ogg":{"hash":"aabbcc","size":3}}}]],
    ["/dom/.minecraft/assets/indexes/1.12.json"] = [[{}]],
  }
  local function open(path)
    local data = files[path]
    if not data then return nil end
    local pos = 0
    return {
      seek = function(_, whence) if whence == "end" then return #data end return pos end,
      read = function() return data end,
      close = function() end,
    }
  end
  local getenv = function(k) if k == "HOME" then return "/dom" end end
  local assets, list = soundpack.scanMinecraft(open, getenv)
  T.eq(assets, "/dom/.minecraft/assets")
  T.eq(#list, 1)
  T.eq(list[1].path, "/dom/.minecraft/assets/objects/aa/aabbcc", "plik po skrocie")
  T.eq(soundpack.scanMinecraft(function() return nil end, getenv), nil, "brak Minecrafta")
end)


-- Wbudowana darmowa paczka: lista plików z freesounds/FILES.md
suite:test("darmowe dzwieki: kazde zdarzenie, mob i muzyka maja plik", function()
  local f = io.open("freesounds/FILES.md", "rb")
  T.truthy(f, "freesounds/FILES.md")
  local list = {}
  for rel in f:read("*a"):gmatch("%- `([^`]+%.ogg)`") do
    list[#list + 1] = { rel = rel }
    local g = io.open("freesounds/" .. rel, "rb")
    T.truthy(g, "plik " .. rel)
    g:close()
  end
  f:close()
  local lib = soundpack.library(list)
  -- zdarzenia bez darmowego odpowiednika (gra po prostu milczy)
  local missing = { burp = true, enderman_stare = true, dragon_wings = true, lava = true, water = true }
  for name, cands in pairs(soundpack.EVENTS) do
    if not missing[name] then T.truthy(soundpack.pick(lib, cands), "zdarzenie " .. name) end
  end
  for kind, m in pairs(soundpack.MOBS) do
    for _, what in ipairs({ "say", "hurt", "death" }) do
      T.truthy(soundpack.pick(lib, m[what]), kind .. " " .. what)
    end
  end
  for _, mat in ipairs({ "stone", "wood", "grass", "gravel", "sand", "snow", "cloth" }) do
    T.truthy(lib["dig/" .. mat] and lib["step/" .. mat] and lib["hit/" .. mat], "material " .. mat)
  end
  for _, ctx in ipairs({ "menu", "game", "creative", "nether", "end" }) do
    T.truthy(#soundpack.musicTracks(lib, ctx) > 0, "muzyka " .. ctx)
  end
end)

return suite
