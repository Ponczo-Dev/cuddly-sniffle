-- render/meshbuffer.lua
-- Szybki bufor wierzchołków na FFI (LuaJIT). Mesher wpisuje wierzchołki
-- przez buf:vertex(...), a toMesh() kopiuje je jednym ruchem do GPU.
-- Bez FFI (inne środowisko) używa wolniejszej ścieżki przez tabele.

local M = {}

M.FORMAT = {
  { "VertexPosition", "float", 3 },
  { "VertexTexCoord", "float", 2 },
  { "VertexColor", "byte", 4 },
}

local ok, ffi = pcall(require, "ffi")
local hasFFI = ok and type(ffi) == "table" and ffi.new ~= nil

if hasFFI then
  pcall(ffi.cdef, [[
    typedef struct { float x, y, z, u, v; uint8_t r, g, b, a; } mc_vertex;
  ]])
end
local VERTEX_SIZE = 24

local Buffer = {}
Buffer.__index = Buffer

function M.new(capacity)
  local self = setmetatable({}, Buffer)
  self.n = 0
  self.capacity = capacity or 4096
  if hasFFI then
    self.data = ffi.new("mc_vertex[?]", self.capacity)
  else
    self.list = {}
  end
  return self
end

function Buffer:reset()
  self.n = 0
end

local floor = math.floor

if hasFFI then
  function Buffer:vertex(x, y, z, u, v, r, g, b)
    local n = self.n
    if n >= self.capacity then
      local newCap = self.capacity * 2
      local newData = ffi.new("mc_vertex[?]", newCap)
      ffi.copy(newData, self.data, n * VERTEX_SIZE)
      self.data, self.capacity = newData, newCap
    end
    local p = self.data[n]
    p.x, p.y, p.z, p.u, p.v = x, y, z, u, v
    p.r, p.g, p.b, p.a = r, g, b, 255
    self.n = n + 1
  end
else
  function Buffer:vertex(x, y, z, u, v, r, g, b)
    self.n = self.n + 1
    self.list[self.n] = { x, y, z, u, v, floor(r) / 255, floor(g) / 255, floor(b) / 255, 1 }
  end
end

-- Tworzy (lub nadpisuje) mesh LÖVE. Zwraca nil, gdy bufor pusty.
function Buffer:toMesh(texture)
  local n = self.n
  if n == 0 then return nil end
  local mesh
  if hasFFI then
    local bytes = love.data.newByteData(n * VERTEX_SIZE)
    ffi.copy(bytes:getFFIPointer(), self.data, n * VERTEX_SIZE)
    mesh = love.graphics.newMesh(M.FORMAT, n, "triangles", "static")
    mesh:setVertices(bytes)
    bytes:release()
  else
    local list = {}
    for i = 1, n do list[i] = self.list[i] end
    mesh = love.graphics.newMesh(M.FORMAT, list, "triangles", "static")
  end
  if texture then mesh:setTexture(texture) end
  return mesh
end

M.hasFFI = hasFFI
return M
