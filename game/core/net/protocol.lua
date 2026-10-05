-- core/net/protocol.lua
-- Format wiadomości sieciowych gry wieloosobowej (LAN).
-- Pakiet = "<długość nagłówka>\n" + nagłówek (tabela Lua z core.serialize)
--          + opcjonalne dane binarne (np. skompresowany chunk).
-- Nagłówek wczytujemy w pustym środowisku, więc obcy kod się nie wykona.

local serialize = require("core.serialize")

local M = {}

M.PORT = 25565
M.VERSION = 1
M.MAX_PLAYERS = 8

function M.pack(msg, payload)
  local head = serialize.encode(msg)
  return #head .. "\n" .. head .. (payload or "")
end

-- Zwraca msg, payload (albo nil przy uszkodzonym pakiecie)
function M.unpack(data)
  if type(data) ~= "string" then return nil end
  local len, rest = data:match("^(%d+)\n()")
  if not len then return nil end
  len = tonumber(len)
  local head = data:sub(rest, rest + len - 1)
  local msg = serialize.decode(head)
  if type(msg) ~= "table" or type(msg.t) ~= "string" then return nil end
  local payload = data:sub(rest + len)
  if payload == "" then payload = nil end
  return msg, payload
end

-- Liczby zmiennoprzecinkowe jako całkowite (setne części), żeby pakiety były krótkie
local floor = math.floor
function M.q(v) return floor((v or 0) * 100 + 0.5) end
function M.dq(v) return (v or 0) / 100 end

-- Bezpieczny nick: litery, cyfry, _ i -, maks. 16 znaków
function M.cleanName(name)
  name = tostring(name or ""):gsub("[^%w_%-]", "")
  if name == "" then name = "Gracz" end
  return name:sub(1, 16)
end

-- Czat: bez znaków sterujących, maks. 100 znaków
function M.cleanChat(text)
  return tostring(text or ""):gsub("[%c]", ""):sub(1, 100)
end

-- ---------------------------------------------------------------------------
-- Byty: migawka (serwer -> klient)
-- ---------------------------------------------------------------------------
local q = M.q

-- Kompaktowy opis bytu do wysłania klientom
function M.entityState(e)
  local s = { e.id, e.type, q(e.x), q(e.y), q(e.z), q(e.yaw or 0) }
  local x = {}
  local t = e.type
  if t == "mob" then
    x.k = e.kind
    x.h = e.health
    if (e.hurtTime or 0) > 0 then x.ht = e.hurtTime end
    if (e.deathTime or 0) > 0 then x.dt = e.deathTime end
    if e.growth and e.growth < 0 then x.g = -1 end
    if e.color and e.color ~= 0 then x.c = e.color end
    if e.sheared then x.s = true end
    if e.tamed then x.tm = true end
    if e.fuse and e.fuse > 0 then x.f = e.fuse end
    if e.headPitch then x.hp = q(e.headPitch) end
  elseif t == "item" then
    x.st = { e.stack.id, e.stack.count, e.stack.damage or 0 }
  elseif t == "xp" then
    x.v = e.value
  elseif t == "falling" then
    x.b, x.m = e.block, e.meta
  elseif t == "tnt" then
    x.f = e.fuse
  elseif t == "arrow" then
    x.vx, x.vy, x.vz = q(e.vx), q(e.vy), q(e.vz)
    if e.stuck then x.sk = true end
  elseif t == "minecart" or t == "boat" then
    if (e.hurtTime or 0) > 0 then x.ht = e.hurtTime end
  elseif t == "player" then
    x.n = e.name
    x.hp = q(e.headPitch or 0)
    if e.sneaking then x.sn = true end
    if (e.hurtTime or 0) > 0 then x.ht = e.hurtTime end
    if e.deadPlayer then x.dt = 1 end
  end
  if next(x) then s[7] = x end
  return s
end

-- ---------------------------------------------------------------------------
-- Byt utworzony u klienta (wyrzucony przedmiot, strzała, TNT...) -> serwer
-- Kopiujemy proste pola; referencje (np. strzelec) uzupełnia serwer.
-- ---------------------------------------------------------------------------
local SPAWNABLE = { item = true, xp = true, tnt = true, arrow = true, snowball = true,
  egg = true, pearl = true, minecart = true, boat = true, falling = true }
M.SPAWNABLE = SPAWNABLE

function M.entitySpawn(e)
  if not SPAWNABLE[e.type] then return nil end
  local out = {}
  for k, v in pairs(e) do
    local tv = type(v)
    if (tv == "number" or tv == "string" or tv == "boolean") and k ~= "id" then out[k] = v end
  end
  if e.stack then out.stack = { id = e.stack.id, count = e.stack.count, damage = e.stack.damage or 0 } end
  return out
end

return M
