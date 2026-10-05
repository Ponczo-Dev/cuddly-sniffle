-- core/fs.lua
-- Warstwa plików: w grze love.filesystem (zapis w %APPDATA%\LOVE\minecraft-lua,
-- bez admina), w testach zwykłe io.open w podanym folderze.

local M = {}

local useLove = rawget(_G, "love") and love.filesystem and love.filesystem.write
local root = "."

function M.setRoot(path)
  root = path
  useLove = false
end

if useLove then
  function M.read(path)
    if not love.filesystem.getInfo(path) then return nil end
    return love.filesystem.read(path)
  end
  function M.write(path, data)
    local dir = path:match("^(.*)/[^/]+$")
    if dir then love.filesystem.createDirectory(dir) end
    return love.filesystem.write(path, data)
  end
  function M.exists(path) return love.filesystem.getInfo(path) ~= nil end
  function M.mkdir(path) return love.filesystem.createDirectory(path) end
  function M.list(path)
    if not love.filesystem.getInfo(path) then return {} end
    return love.filesystem.getDirectoryItems(path)
  end
  function M.isDir(path)
    local info = love.filesystem.getInfo(path)
    return info and info.type == "directory"
  end
  local function removeRec(path)
    local info = love.filesystem.getInfo(path)
    if not info then return end
    if info.type == "directory" then
      for _, f in ipairs(love.filesystem.getDirectoryItems(path)) do removeRec(path .. "/" .. f) end
    end
    love.filesystem.remove(path)
  end
  M.remove = removeRec
else
  -- Wersja testowa: pliki w folderze root (bez podfolderów systemowych)
  local function full(p) return root .. "/" .. p end
  local files = {} -- pamięć podręczna nazw (listowanie bez lfs)
  function M.read(path)
    local f = io.open(full(path), "rb")
    if not f then return nil end
    local d = f:read("*a")
    f:close()
    return d
  end
  function M.write(path, data)
    local dir = path:match("^(.*)/[^/]+$")
    if dir then os.execute('mkdir -p "' .. full(dir) .. '" 2>/dev/null') end
    local f = io.open(full(path), "wb")
    if not f then return false end
    f:write(data)
    f:close()
    files[path] = true
    return true
  end
  function M.exists(path)
    local f = io.open(full(path), "rb")
    if f then f:close() return true end
    return files[path] or false
  end
  function M.mkdir(path) os.execute('mkdir -p "' .. full(path) .. '" 2>/dev/null') return true end
  function M.list(path)
    local out = {}
    local p = io.popen('ls "' .. full(path) .. '" 2>/dev/null')
    if p then
      for line in p:lines() do out[#out + 1] = line end
      p:close()
    end
    return out
  end
  function M.isDir(path)
    local p = io.popen('test -d "' .. full(path) .. '" && echo yes')
    local r = p and p:read("*l")
    if p then p:close() end
    return r == "yes"
  end
  function M.remove(path) os.execute('rm -rf "' .. full(path) .. '"') end
end

-- Kompresja (tylko w LÖVE; w testach bez kompresji)
function M.compress(data)
  if useLove and love.data and love.data.compress then
    return "Z" .. love.data.compress("string", "zlib", data, 6)
  end
  return "R" .. data
end

function M.decompress(data)
  local tag = data:sub(1, 1)
  local body = data:sub(2)
  if tag == "Z" then
    if not (love and love.data) then return nil end
    return love.data.decompress("string", "zlib", body)
  end
  return body
end

return M
