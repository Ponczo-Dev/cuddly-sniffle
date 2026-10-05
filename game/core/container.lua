-- core/container.lua
-- Logika okien z slotami (ekwipunek, stół, piec, skrzynia): klikanie myszą,
-- przenoszenie stosów, dzielenie, shift-click, crafting. Bez grafiki.
--
-- Slot: { inv = Inventory, i = indeks, group = "hotbar"|"main"|"armor"|"craft"|
--         "result"|"chest"|"input"|"fuel"|"output", armor = 1..4 (dla pancerza) }

local items = require("core.items")
local recipes = require("core.recipes")

local M = {}

local Container = {}
Container.__index = Container

-- opts.shift: grupa -> lista grup docelowych przy shift-click
-- opts.craftSize: 2 lub 3 (jeśli okno ma siatkę craftingu)
function M.new(slots, opts)
  local self = setmetatable({}, Container)
  self.slots = slots
  self.opts = opts or {}
  self.cursor = nil
  self.byGroup = {}
  for n, s in ipairs(slots) do
    s.n = n
    local g = self.byGroup[s.group]
    if not g then g = {}; self.byGroup[s.group] = g end
    g[#g + 1] = s
  end
  self:updateCrafting()
  return self
end

local function get(s) return s.inv.slots[s.i] end
local function put(s, stack)
  if stack and stack.count <= 0 then stack = nil end
  s.inv.slots[s.i] = stack
  s.inv.changed = true
end
M.getSlot, M.putSlot = get, put

-- Czy slot przyjmie dany stos
function Container:accepts(s, stack)
  if s.group == "result" or s.group == "output" then return false end
  if s.accept then return s.accept(stack) and true or false end
  if s.group == "armor" then
    local d = items.get(stack.id)
    return d and d.armor and d.armor.slot == s.armor or false
  end
  if s.group == "fuel" then
    return items.fuelTime(stack) > 0
  end
  return true
end

local function maxFor(s, stack)
  local m = items.maxStack(stack.id)
  if s.group == "armor" then m = 1 end
  if s.max and s.max < m then m = s.max end
  return m
end

-- ---------------------------------------------------------------------------
-- Crafting
-- ---------------------------------------------------------------------------
function Container:updateCrafting()
  local size = self.opts.craftSize
  if not size then return end
  local grid = {}
  local craft = self.byGroup.craft
  for k, s in ipairs(craft) do grid[k] = get(s) end
  local result = recipes.match(grid, size)
  put(self.byGroup.result[1], result)
end

-- Zużywa po jednym składniku z każdego pola siatki
function Container:consumeIngredients()
  for _, s in ipairs(self.byGroup.craft) do
    local st = get(s)
    if st then
      st.count = st.count - 1
      if st.count <= 0 then put(s, nil) else s.inv.changed = true end
    end
  end
end

-- Dodaje stos do grup docelowych (najpierw dokładanie, potem puste)
function Container:moveToGroups(stack, groups, reverse)
  local list = {}
  for _, gname in ipairs(groups) do
    local g = self.byGroup[gname]
    if g then
      if reverse then
        for k = #g, 1, -1 do list[#list + 1] = g[k] end
      else
        for k = 1, #g do list[#list + 1] = g[k] end
      end
    end
  end
  for _, s in ipairs(list) do
    if stack.count <= 0 then break end
    local cur = get(s)
    local max = maxFor(s, stack)
    if cur and items.canMerge(cur, stack) and cur.count < max and self:accepts(s, stack) then
      local n = math.min(max - cur.count, stack.count)
      cur.count = cur.count + n
      stack.count = stack.count - n
      s.inv.changed = true
    end
  end
  for _, s in ipairs(list) do
    if stack.count <= 0 then break end
    if not get(s) and self:accepts(s, stack) then
      local n = math.min(maxFor(s, stack), stack.count)
      put(s, { id = stack.id, count = n, damage = stack.damage or 0, ench = stack.ench })
      stack.count = stack.count - n
    end
  end
  return stack.count
end

-- Grupy docelowe dla shift-click
function Container:shiftTargets(s, stack)
  local custom = self.opts.shift and self.opts.shift[s.group]
  if s.group == "hotbar" or s.group == "main" then
    local d = items.get(stack.id)
    if d and d.armor and self.byGroup.armor then
      local slot = self.byGroup.armor[d.armor.slot]
      if slot and not get(slot) then return { "armor" } end
    end
  end
  if custom then return custom end
  if s.group == "hotbar" then return { "main" } end
  if s.group == "main" then return { "hotbar" } end
  return { "hotbar", "main" }
end

-- ---------------------------------------------------------------------------
-- Kliknięcie slotu. button: "left" | "right"
-- ---------------------------------------------------------------------------
function Container:click(n, button, shift)
  local s = self.slots[n]
  if not s then return end
  local stack = get(s)
  local cursor = self.cursor

  -- Wynik craftingu: zabranie gotowego przedmiotu
  if s.group == "result" then
    if not stack then return end
    if shift then
      -- crafting tyle razy, ile się da, prosto do ekwipunku
      local guard = 0
      while get(s) and guard < 64 do
        guard = guard + 1
        local r = get(s)
        local copy = { id = r.id, count = r.count, damage = r.damage, ench = r.ench }
        local left = self:moveToGroups(copy, { "hotbar", "main" }, true)
        if left > 0 then
          -- nie zmieściło się: cofamy częściowe dodanie nie jest potrzebne,
          -- bo moveToGroups dodaje tylko to, co się mieści - resztę wyrzucamy
          if self.opts.onOverflow then
            self.opts.onOverflow({ id = r.id, count = left, damage = r.damage, ench = r.ench })
          end
        end
        self:consumeIngredients()
        if self.opts.onCraft then self.opts.onCraft(copy) end
        self:updateCrafting()
        if left > 0 then break end
      end
      return
    end
    if not cursor then
      self.cursor = { id = stack.id, count = stack.count, damage = stack.damage, ench = stack.ench }
    elseif items.canMerge(cursor, stack) and cursor.count + stack.count <= items.maxStack(stack.id) then
      cursor.count = cursor.count + stack.count
    else
      return
    end
    self:consumeIngredients()
    if self.opts.onCraft then self.opts.onCraft(stack) end
    self:updateCrafting()
    return
  end

  -- Wyjście pieca: tylko zabieranie
  if s.group == "output" then
    if not stack then return end
    if shift then
      local left = self:moveToGroups({ id = stack.id, count = stack.count, damage = stack.damage, ench = stack.ench },
        { "hotbar", "main" }, true)
      if self.opts.onTake then self.opts.onTake(s, stack.count - left) end
      if left > 0 then stack.count = left; s.inv.changed = true else put(s, nil) end
      return
    end
    if not cursor then
      self.cursor = stack
      put(s, nil)
      if self.opts.onTake then self.opts.onTake(s, stack.count) end
    elseif items.canMerge(cursor, stack) then
      local max = items.maxStack(stack.id)
      local k = math.min(max - cursor.count, stack.count)
      cursor.count = cursor.count + k
      stack.count = stack.count - k
      if stack.count <= 0 then put(s, nil) else s.inv.changed = true end
      if self.opts.onTake then self.opts.onTake(s, k) end
    end
    return
  end

  -- Shift-click: przenieś cały stos do innej części okna
  if shift then
    if not stack then return end
    local left = self:moveToGroups(stack, self:shiftTargets(s, stack))
    if left <= 0 then put(s, nil) else s.inv.changed = true end
    if s.group == "craft" then self:updateCrafting() end
    return
  end

  if button == "left" then
    if not cursor then
      if stack then
        self.cursor = stack
        put(s, nil)
      end
    elseif not stack then
      if self:accepts(s, cursor) then
        local max = maxFor(s, cursor)
        if cursor.count <= max then
          put(s, cursor)
          self.cursor = nil
        else
          put(s, { id = cursor.id, count = max, damage = cursor.damage, ench = cursor.ench })
          cursor.count = cursor.count - max
        end
      end
    elseif items.canMerge(stack, cursor) then
      local max = maxFor(s, stack)
      local k = math.min(max - stack.count, cursor.count)
      stack.count = stack.count + k
      cursor.count = cursor.count - k
      if cursor.count <= 0 then self.cursor = nil end
      s.inv.changed = true
    elseif self:accepts(s, cursor) and cursor.count <= maxFor(s, cursor) then
      put(s, cursor)
      self.cursor = stack
    end
  else -- prawy przycisk
    if not cursor then
      if stack then
        local half = math.ceil(stack.count / 2)
        self.cursor = { id = stack.id, count = half, damage = stack.damage, ench = stack.ench }
        stack.count = stack.count - half
        if stack.count <= 0 then put(s, nil) else s.inv.changed = true end
      end
    elseif not stack then
      if self:accepts(s, cursor) then
        put(s, { id = cursor.id, count = 1, damage = cursor.damage, ench = cursor.ench })
        cursor.count = cursor.count - 1
        if cursor.count <= 0 then self.cursor = nil end
      end
    elseif items.canMerge(stack, cursor) then
      if stack.count < maxFor(s, stack) then
        stack.count = stack.count + 1
        cursor.count = cursor.count - 1
        if cursor.count <= 0 then self.cursor = nil end
        s.inv.changed = true
      end
    elseif self:accepts(s, cursor) and cursor.count <= maxFor(s, cursor) then
      put(s, cursor)
      self.cursor = stack
    end
  end

  if s.group == "craft" then self:updateCrafting() end
end

-- Rozkładanie stosu z kursora przeciąganiem po kilku slotach.
-- button "left": po równo, "right": po jednym do każdego.
function Container:distribute(list, button)
  local cursor = self.cursor
  if not cursor or #list == 0 then return end
  local targets = {}
  for _, n in ipairs(list) do
    local s = self.slots[n]
    local st = s and get(s)
    if s and s.group ~= "result" and s.group ~= "output" and self:accepts(s, cursor)
      and (not st or items.canMerge(st, cursor)) then
      targets[#targets + 1] = s
    end
  end
  if #targets == 0 then return end
  local per = button == "right" and 1 or math.max(1, math.floor(cursor.count / #targets))
  local craftChanged = false
  for _, s in ipairs(targets) do
    if cursor.count <= 0 then break end
    local st = get(s)
    local max = maxFor(s, cursor)
    local have = st and st.count or 0
    local k = math.min(per, max - have, cursor.count)
    if k > 0 then
      if st then st.count = st.count + k; s.inv.changed = true
      else put(s, { id = cursor.id, count = k, damage = cursor.damage, ench = cursor.ench }) end
      cursor.count = cursor.count - k
      if s.group == "craft" then craftChanged = true end
    end
  end
  if cursor.count <= 0 then self.cursor = nil end
  if craftChanged then self:updateCrafting() end
end

-- Zamknięcie okna: przedmioty z siatki craftingu i kursora wracają do gracza.
-- giveBack(stack) dodaje do ekwipunku albo wyrzuca na ziemię.
function Container:close(giveBack)
  local craft = self.byGroup.craft
  if craft and not self.opts.keepCraft then
    for _, s in ipairs(craft) do
      local st = get(s)
      if st then giveBack(st); put(s, nil) end
    end
    if self.byGroup.result then put(self.byGroup.result[1], nil) end
  end
  -- sloty tymczasowe (np. przedmiot na stole do zaklinania)
  for _, s in ipairs(self.slots) do
    if s.temp then
      local st = get(s)
      if st then giveBack(st); put(s, nil) end
    end
  end
  if self.cursor then
    giveBack(self.cursor)
    self.cursor = nil
  end
end

return M
