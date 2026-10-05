-- core/bytearray.lua
-- Tablica bajtów (0..255) indeksowana od 0.
-- W LuaJIT (LÖVE) to natywna tablica FFI uint8_t: szybka i oszczędna (1 bajt
-- na element). W zwykłym Lua (testy przez lua.exe) to zwykła tabela.
-- W obu przypadkach używa się jej tak samo: a[i] = v, v = a[i].

local M = {}

local ok, ffi = pcall(require, "ffi")
M.hasFFI = ok and type(ffi) == "table" and ffi.new ~= nil

if M.hasFFI then
  function M.new(n, fill)
    local a = ffi.new("uint8_t[?]", n)
    if fill and fill ~= 0 then
      ffi.fill(a, n, fill)
    end
    return a
  end

  function M.fill(a, n, value)
    ffi.fill(a, n, value)
  end

  function M.copy(dst, src, n)
    ffi.copy(dst, src, n)
  end
else
  function M.new(n, fill)
    fill = fill or 0
    local a = {}
    for i = 0, n - 1 do
      a[i] = fill
    end
    return a
  end

  function M.fill(a, n, value)
    for i = 0, n - 1 do
      a[i] = value
    end
  end

  function M.copy(dst, src, n)
    for i = 0, n - 1 do
      dst[i] = src[i]
    end
  end
end

return M
