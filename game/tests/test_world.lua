-- tests/test_world.lua
local T = require("tests.testlib")
local World = require("core.world")
local Chunk = require("core.chunk")
local mesher = require("core.mesher")
local mat4 = require("core.mat4")
local frustum = require("core.frustum")
local Rng = require("core.rng")

local suite = T.suite("world")

-- Świat z pustymi (wygenerowanymi) chunkami w kwadracie -r..r
local function emptyWorld(r)
  local w = World.new()
  for cz = -r, r do
    for cx = -r, r do
      local c = Chunk.new(cx, cz)
      c.generated = true
      w:addChunk(c)
    end
  end
  return w
end

suite:test("set/get bloku, takze ujemne wspolrzedne", function()
  local w = emptyWorld(1)
  T.truthy(w:setBlock(-1, 10, -17 + 16, 4))
  T.eq(w:getBlock(-1, 10, -1), 4)
  w:setBlock(5, 20, 7, 1, 3)
  T.eq(w:getBlock(5, 20, 7), 1)
  T.eq(w:getMeta(5, 20, 7), 3)
  T.eq(w:getBlock(5, 200, 7), 0, "powyzej swiata = powietrze")
  T.eq(w:setBlock(100, 5, 100, 1), false, "niezaladowany chunk")
end)

suite:test("mapa wysokosci po zmianach", function()
  local w = emptyWorld(0)
  w:setBlock(3, 10, 3, 1)
  T.eq(w:getHeight(3, 3), 11)
  w:setBlock(3, 20, 3, 1)
  T.eq(w:getHeight(3, 3), 21)
  w:setBlock(3, 20, 3, 0)
  T.eq(w:getHeight(3, 3), 11, "po usunieciu szczytu")
  w:setBlock(3, 30, 3, 20) -- szkło przepuszcza światło
  T.eq(w:getHeight(3, 3), 11)
end)

suite:test("blok na krawedzi oznacza sasiada jako brudny", function()
  local w = emptyWorld(1)
  for _, c in pairs(w.chunks) do c.dirty = false end
  w:setBlock(0, 5, 5, 1)
  T.truthy(w:getChunk(-1, 0).dirty, "lewy sasiad")
  T.truthy(w:getChunk(0, 0).dirty)
  T.eq(w:getChunk(1, 0).dirty, false)
end)

suite:test("ladowanie swiata wokol gracza", function()
  local gen = function(chunk) chunk:setRaw(0, 0, 0, 7) end
  local w = World.new({ generator = gen })
  w:updateLoading(0, 0, 1, 1000)
  T.eq(w.chunkCount, 49, "promien 1 + 2 zapasu = 7x7")
  T.truthy(w:getChunk(0, 0).lit, "srodek oswietlony")
  T.eq(w:getChunk(4, 4), nil)
  local removed = w:unloadFar(10, 10, 2)
  T.eq(removed, 49)
end)

suite:test("mesher: pojedynczy blok = 6 scian", function()
  local w = emptyWorld(1)
  w:setBlock(5, 5, 5, 1)
  for _, c in pairs(w.chunks) do w:lightChunk(c) end
  local buf, tbuf = mesher.newTableBuffer(), mesher.newTableBuffer()
  mesher.gather(w, 0, 0)
  mesher.build(w:getChunk(0, 0), buf, tbuf)
  T.eq(buf.n, 36, "6 scian x 6 wierzcholkow")
  T.eq(tbuf.n, 0)
end)

suite:test("mesher: ukrywa sciany miedzy blokami", function()
  local w = emptyWorld(1)
  w:setBlock(5, 5, 5, 1)
  w:setBlock(6, 5, 5, 1)
  local buf, tbuf = mesher.newTableBuffer(), mesher.newTableBuffer()
  mesher.gather(w, 0, 0)
  mesher.build(w:getChunk(0, 0), buf, tbuf)
  T.eq(buf.n, 60, "10 scian")
end)

suite:test("mesher: woda trafia do warstwy przezroczystej", function()
  local w = emptyWorld(1)
  w:setBlock(5, 5, 5, 8)
  local buf, tbuf = mesher.newTableBuffer(), mesher.newTableBuffer()
  mesher.gather(w, 0, 0)
  mesher.build(w:getChunk(0, 0), buf, tbuf)
  T.eq(buf.n, 0)
  T.truthy(tbuf.n > 0)
end)

suite:test("mesher: blok na granicy chunkow", function()
  local w = emptyWorld(1)
  w:setBlock(15, 5, 5, 1)
  w:setBlock(16, 5, 5, 1) -- sąsiedni chunk
  local buf, tbuf = mesher.newTableBuffer(), mesher.newTableBuffer()
  mesher.gather(w, 0, 0)
  mesher.build(w:getChunk(0, 0), buf, tbuf)
  T.eq(buf.n, 30, "5 scian - wspolna ukryta")
end)

suite:test("mat4: kamera patrzy w -Z", function()
  local view = mat4.fpsView({}, 0, 0, 0, 0, 0)
  local _, _, z = mat4.transform(view, 0, 0, -5)
  T.near(z, -5, 1e-9, "punkt przed kamera ma z<0 w ukladzie kamery")
  local proj = mat4.perspective({}, math.rad(70), 1, 0.1, 100)
  local vp = mat4.multiply({}, proj, view)
  local f = frustum.new()
  frustum.update(f, vp)
  T.truthy(frustum.boxVisible(f, -1, -1, -10, 1, 1, -8), "przed kamera")
  T.eq(frustum.boxVisible(f, -1, -1, 8, 1, 1, 10), false, "za kamera")
end)

suite:test("rng: deterministyczny", function()
  local a, b = Rng.new(42), Rng.new(42)
  for _ = 1, 100 do T.eq(a:next(), b:next()) end
  local c = Rng.new(43)
  T.truthy(Rng.new(42):next() ~= c:next())
  for _ = 1, 1000 do
    local v = a:int(3, 7)
    T.truthy(v >= 3 and v <= 7)
  end
  T.truthy(Rng.hash(1, 2) ~= Rng.hash(2, 1))
end)

return suite
