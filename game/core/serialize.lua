-- core/serialize.lua
-- Zapis tabel Lua do tekstu i odczyt (bez wykonywania obcego kodu:
-- tekst wczytujemy w pustym środowisku). Obsługuje liczby, napisy,
-- wartości logiczne i zagnieżdżone tabele.

local M = {}

local function encodeValue(v, out, indent)
  local t = type(v)
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then
      out[#out + 1] = "0"
    elseif v == math.floor(v) and math.abs(v) < 2 ^ 53 then
      out[#out + 1] = string.format("%d", v)
    else
      out[#out + 1] = string.format("%.17g", v)
    end
  elseif t == "string" then
    out[#out + 1] = string.format("%q", v)
  elseif t == "boolean" then
    out[#out + 1] = v and "true" or "false"
  elseif t == "table" then
    out[#out + 1] = "{"
    local n = #v
    for i = 1, n do
      encodeValue(v[i], out, indent)
      out[#out + 1] = ","
    end
    -- pozostałe klucze w stałej kolejności
    local keys = {}
    for k in pairs(v) do
      if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then
        keys[#keys + 1] = k
      end
    end
    table.sort(keys, function(a, b)
      if type(a) == type(b) then return a < b end
      return type(a) == "number"
    end)
    for _, k in ipairs(keys) do
      local kv = v[k]
      local kt = type(kv)
      if kt == "number" or kt == "string" or kt == "boolean" or kt == "table" then
        if type(k) == "string" and k:match("^[%a_][%w_]*$") then
          out[#out + 1] = k .. "="
        else
          out[#out + 1] = "["
          encodeValue(k, out, indent)
          out[#out + 1] = "]="
        end
        encodeValue(kv, out, indent)
        out[#out + 1] = ","
      end
    end
    out[#out + 1] = "}"
  else
    out[#out + 1] = "nil"
  end
end

function M.encode(v)
  local out = { "return " }
  encodeValue(v, out, "")
  return table.concat(out)
end

function M.decode(text)
  if type(text) ~= "string" then return nil end
  local fn
  local setfenv = rawget(_G, "setfenv")
  local loadstring = rawget(_G, "loadstring")
  if setfenv and loadstring then
    fn = loadstring(text, "=dane")
    if fn then setfenv(fn, {}) end
  else
    fn = load(text, "=dane", "t", {})
  end
  if not fn then return nil end
  local ok, result = pcall(fn)
  if ok then return result end
  return nil
end

return M
