-- core/inventory.lua
-- Ekwipunek: tablica slotów, w każdym stos { id, count, damage } albo nil.
-- Ekwipunek gracza (jak w Beta/1.8): sloty 1..9 = hotbar, 10..36 = plecak,
-- osobno 4 sloty pancerza (1 hełm .. 4 buty).

local items = require("core.items")

local M = {}

local Inventory = {}
Inventory.__index = Inventory

function M.new(size)
  return setmetatable({ size = size, slots = {}, changed = true }, Inventory)
end

function Inventory:get(i)
  return self.slots[i]
end

function Inventory:set(i, stack)
  if stack and stack.count <= 0 then stack = nil end
  self.slots[i] = stack
  self.changed = true
end

function Inventory:clear()
  self.slots = {}
  self.changed = true
end

-- Dodaje stos: najpierw dokłada do istniejących, potem do pustych slotów.
-- order: opcjonalna lista indeksów (np. najpierw hotbar). Zwraca resztę (0 = wszystko).
function Inventory:add(stack, order)
  local count = stack.count
  local max = items.maxStack(stack.id)
  local list = order
  if not list then
    list = {}
    for i = 1, self.size do list[i] = i end
  end
  -- 1) dokładanie do pasujących stosów
  for _, i in ipairs(list) do
    if count <= 0 then break end
    local s = self.slots[i]
    if s and items.canMerge(s, stack) and s.count < max then
      local n = math.min(max - s.count, count)
      s.count = s.count + n
      count = count - n
    end
  end
  -- 2) puste sloty
  for _, i in ipairs(list) do
    if count <= 0 then break end
    if not self.slots[i] then
      local n = math.min(max, count)
      self.slots[i] = { id = stack.id, count = n, damage = stack.damage or 0 }
      count = count - n
    end
  end
  self.changed = true
  return count
end

-- Ile sztuk danego przedmiotu jest w ekwipunku
function Inventory:count(id, damage)
  local n = 0
  for i = 1, self.size do
    local s = self.slots[i]
    if s and s.id == id and (damage == nil or s.damage == damage) then n = n + s.count end
  end
  return n
end

-- Zabiera n sztuk przedmiotu (zwraca ile udało się zabrać)
function Inventory:removeItem(id, n, damage)
  local taken = 0
  for i = 1, self.size do
    if taken >= n then break end
    local s = self.slots[i]
    if s and s.id == id and (damage == nil or s.damage == damage) then
      local k = math.min(n - taken, s.count)
      s.count = s.count - k
      taken = taken + k
      if s.count <= 0 then self.slots[i] = nil end
    end
  end
  self.changed = true
  return taken
end

-- Zmniejsza stos w slocie o n
function Inventory:decrement(i, n)
  local s = self.slots[i]
  if not s then return end
  s.count = s.count - (n or 1)
  if s.count <= 0 then self.slots[i] = nil end
  self.changed = true
end

-- Zużywa narzędzie w slocie. Zwraca true, jeśli się zepsuło.
function Inventory:damageItem(i, amount)
  local s = self.slots[i]
  if not s then return false end
  local d = items.get(s.id)
  if not d or not d.maxDamage then return false end
  s.damage = (s.damage or 0) + (amount or 1)
  self.changed = true
  if s.damage >= d.maxDamage then
    self.slots[i] = nil
    return true
  end
  return false
end

function Inventory:isEmpty()
  for i = 1, self.size do
    if self.slots[i] then return false end
  end
  return true
end

-- Zapis do prostej tabeli (do pliku) i odczyt
function Inventory:serialize()
  local out = {}
  for i = 1, self.size do
    local s = self.slots[i]
    if s then out[#out + 1] = { i, s.id, s.count, s.damage or 0 } end
  end
  return out
end

function Inventory:deserialize(data)
  self.slots = {}
  for _, e in ipairs(data or {}) do
    if items.get(e[2]) then
      self.slots[e[1]] = { id = e[2], count = e[3], damage = e[4] or 0 }
    end
  end
  self.changed = true
end

-- Kolejność dodawania do ekwipunku gracza: najpierw hotbar, potem plecak
M.PLAYER_ORDER = {}
for i = 1, 36 do M.PLAYER_ORDER[i] = i end

return M
