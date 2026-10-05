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

return suite
