-- core/net/transport.lua
-- Warstwa przesyłania pakietów. Dwie wersje o tym samym interfejsie:
--   * enet     - prawdziwa sieć (biblioteka enet wbudowana w LÖVE)
--   * loopback - w pamięci, do testów logiki bez sieci (lua.exe)
--
-- Serwer:  t:service() -> lista { type = "connect"|"receive"|"disconnect", peer = id, data }
--          t:send(peerId, data), t:kick(peerId), t:close()
-- Klient:  t:service() -> lista { type = ..., data }, t:send(data), t:close()

local M = {}

-- ---------------------------------------------------------------------------
-- enet
-- ---------------------------------------------------------------------------
local function loadEnet()
  local ok, enet = pcall(require, "enet")
  if ok then return enet end
  return nil
end

function M.enetServer(port, maxPeers)
  local enet = loadEnet()
  if not enet then return nil, "Brak biblioteki enet" end
  local host = enet.host_create("*:" .. port, maxPeers or 8, 2)
  if not host then return nil, "Port " .. port .. " jest zajety" end
  local peers, ids = {}, {}
  local t = {}
  function t:service()
    local out = {}
    local ok, ev = pcall(host.service, host, 0)
    while ok and ev do
      local id = ids[ev.peer]
      if not id then
        id = ev.peer:index()
        ids[ev.peer] = id
        peers[id] = ev.peer
      end
      out[#out + 1] = { type = ev.type, peer = id, data = ev.data }
      if ev.type == "disconnect" then peers[id] = nil; ids[ev.peer] = nil end
      ok, ev = pcall(host.service, host, 0)
    end
    return out
  end
  function t:send(id, data)
    local p = peers[id]
    if p then p:send(data, 0, "reliable") end
  end
  function t:kick(id)
    local p = peers[id]
    if p then p:disconnect_later() end
  end
  function t:close()
    for _, p in pairs(peers) do p:disconnect_now() end
    host:flush()
    peers, ids = {}, {}
    pcall(host.destroy, host)
  end
  function t:flush() host:flush() end
  return t
end

function M.enetClient(address, port)
  local enet = loadEnet()
  if not enet then return nil, "Brak biblioteki enet" end
  local host = enet.host_create(nil, 1, 2)
  if not host then return nil, "Nie mozna utworzyc polaczenia" end
  local ok, peer = pcall(host.connect, host, address .. ":" .. port, 2)
  if not ok or not peer then return nil, "Zly adres: " .. tostring(address) end
  local t = {}
  function t:service()
    local out = {}
    local ok2, ev = pcall(host.service, host, 0)
    while ok2 and ev do
      out[#out + 1] = { type = ev.type, data = ev.data }
      ok2, ev = pcall(host.service, host, 0)
    end
    return out
  end
  function t:send(data) peer:send(data, 0, "reliable") end
  function t:close()
    pcall(peer.disconnect_now, peer)
    pcall(host.flush, host)
    pcall(host.destroy, host)
  end
  function t:flush() host:flush() end
  return t
end

-- ---------------------------------------------------------------------------
-- loopback (testy): serwer i dowolna liczba klientów w jednym procesie
-- ---------------------------------------------------------------------------
function M.loopbackServer()
  local srv = { queue = {}, clients = {}, nextId = 1 }
  function srv:service()
    local q = self.queue
    self.queue = {}
    return q
  end
  function srv:send(id, data)
    local c = self.clients[id]
    if c then c.queue[#c.queue + 1] = { type = "receive", data = data } end
  end
  function srv:kick(id)
    local c = self.clients[id]
    if c then
      c.queue[#c.queue + 1] = { type = "disconnect" }
      self.clients[id] = nil
    end
  end
  function srv:close()
    for id in pairs(self.clients) do self:kick(id) end
  end
  function srv:flush() end
  -- tworzy klienta połączonego z tym serwerem
  function srv:connect()
    local id = self.nextId
    self.nextId = id + 1
    local server = self
    local c = { queue = { { type = "connect" } }, id = id }
    self.clients[id] = c
    server.queue[#server.queue + 1] = { type = "connect", peer = id }
    function c:service()
      local q = self.queue
      self.queue = {}
      return q
    end
    function c:send(data)
      if server.clients[id] then
        server.queue[#server.queue + 1] = { type = "receive", peer = id, data = data }
      end
    end
    function c:close()
      if server.clients[id] then
        server.clients[id] = nil
        server.queue[#server.queue + 1] = { type = "disconnect", peer = id }
      end
    end
    function c:flush() end
    return c
  end
  return srv
end

return M
