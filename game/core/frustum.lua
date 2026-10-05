-- core/frustum.lua
-- Frustum culling: nie rysujemy chunków, których kamera nie widzi.
-- Płaszczyzny wyciągamy z macierzy projekcja*widok (metoda Gribba-Hartmanna).

local M = {}

-- planes: tablica 6 płaszczyzn {a, b, c, d}
function M.new()
  local f = {}
  for i = 1, 6 do f[i] = { 0, 0, 0, 0 } end
  return f
end

local function setPlane(p, a, b, c, d)
  local len = math.sqrt(a * a + b * b + c * c)
  if len == 0 then len = 1 end
  p[1], p[2], p[3], p[4] = a / len, b / len, c / len, d / len
end

-- m: macierz projekcja*widok (row-major)
function M.update(f, m)
  local r4a, r4b, r4c, r4d = m[13], m[14], m[15], m[16]
  setPlane(f[1], r4a + m[1], r4b + m[2], r4c + m[3], r4d + m[4])     -- lewa
  setPlane(f[2], r4a - m[1], r4b - m[2], r4c - m[3], r4d - m[4])     -- prawa
  setPlane(f[3], r4a + m[5], r4b + m[6], r4c + m[7], r4d + m[8])     -- dół
  setPlane(f[4], r4a - m[5], r4b - m[6], r4c - m[7], r4d - m[8])     -- góra
  setPlane(f[5], r4a + m[9], r4b + m[10], r4c + m[11], r4d + m[12])  -- bliska
  setPlane(f[6], r4a - m[9], r4b - m[10], r4c - m[11], r4d - m[12])  -- daleka
end

-- Czy prostopadłościan (AABB) jest choć częściowo widoczny?
function M.boxVisible(f, x0, y0, z0, x1, y1, z1)
  for i = 1, 6 do
    local p = f[i]
    local a, b, c = p[1], p[2], p[3]
    -- wierzchołek najdalej w kierunku normalnej płaszczyzny
    local x = a >= 0 and x1 or x0
    local y = b >= 0 and y1 or y0
    local z = c >= 0 and z1 or z0
    if a * x + b * y + c * z + p[4] < 0 then
      return false
    end
  end
  return true
end

return M
