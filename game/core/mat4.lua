-- core/mat4.lua
-- Macierze 4x4 do grafiki 3D. Płaska tablica 16 liczb w układzie
-- WIERSZOWYM (row-major): m[(wiersz-1)*4 + kolumna].
-- Do shadera wysyłamy przez shader:send(nazwa, "row", m).

local M = {}

function M.new()
  return { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }
end

function M.identity(out)
  out = out or {}
  for i = 1, 16 do out[i] = 0 end
  out[1], out[6], out[11], out[16] = 1, 1, 1, 1
  return out
end

-- out = a * b (out może być tą samą tablicą co a lub b)
local tmp = {}
function M.multiply(out, a, b)
  for r = 0, 3 do
    local a1, a2, a3, a4 = a[r * 4 + 1], a[r * 4 + 2], a[r * 4 + 3], a[r * 4 + 4]
    for c = 1, 4 do
      tmp[r * 4 + c] = a1 * b[c] + a2 * b[4 + c] + a3 * b[8 + c] + a4 * b[12 + c]
    end
  end
  for i = 1, 16 do out[i] = tmp[i] end
  return out
end

-- Rzut perspektywiczny (jak gluPerspective). fovy w radianach.
function M.perspective(out, fovy, aspect, near, far)
  out = M.identity(out)
  local f = 1 / math.tan(fovy / 2)
  out[1] = f / aspect
  out[6] = f
  out[11] = (far + near) / (near - far)
  out[12] = 2 * far * near / (near - far)
  out[15] = -1
  out[16] = 0
  return out
end

function M.translation(out, x, y, z)
  out = M.identity(out)
  out[4], out[8], out[12] = x, y, z
  return out
end

function M.scale(out, x, y, z)
  out = M.identity(out)
  out[1], out[6], out[11] = x, y, z
  return out
end

-- Obrót wokół osi X o kąt a (radiany)
function M.rotationX(out, a)
  out = M.identity(out)
  local c, s = math.cos(a), math.sin(a)
  out[6], out[7] = c, -s
  out[10], out[11] = s, c
  return out
end

-- Obrót wokół osi Y o kąt a (radiany)
function M.rotationY(out, a)
  out = M.identity(out)
  local c, s = math.cos(a), math.sin(a)
  out[1], out[3] = c, s
  out[9], out[11] = -s, c
  return out
end

function M.rotationZ(out, a)
  out = M.identity(out)
  local c, s = math.cos(a), math.sin(a)
  out[1], out[2] = c, -s
  out[5], out[6] = s, c
  return out
end

-- Macierz widoku kamery FPS: najpierw przesunięcie o -oko,
-- potem obrót o -yaw (oś Y) i -pitch (oś X).
local rx, ry, tr = {}, {}, {}
function M.fpsView(out, x, y, z, yaw, pitch)
  M.rotationX(rx, -pitch)
  M.rotationY(ry, -yaw)
  M.translation(tr, -x, -y, -z)
  M.multiply(out, ry, tr)
  M.multiply(out, rx, out)
  return out
end

-- Przekształca punkt (x, y, z, 1). Zwraca x, y, z, w.
function M.transform(m, x, y, z)
  return m[1] * x + m[2] * y + m[3] * z + m[4],
    m[5] * x + m[6] * y + m[7] * z + m[8],
    m[9] * x + m[10] * y + m[11] * z + m[12],
    m[13] * x + m[14] * y + m[15] * z + m[16]
end

return M
