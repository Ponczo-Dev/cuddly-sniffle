-- conf.lua
-- Konfiguracja LÖVE, wczytywana PRZED main.lua.

function love.conf(t)
  t.identity = "minecraft-lua"   -- folder zapisu: %APPDATA%\LOVE\minecraft-lua
  t.version = "11.5"             -- wersja LÖVE, pod którą piszemy
  t.console = true               -- okno konsoli z print() (tylko Windows)

  t.window.title = "Minecraft Lua (Beta)"
  t.window.width = 1280
  t.window.height = 720
  t.window.minwidth = 640
  t.window.minheight = 360
  t.window.resizable = true
  t.window.vsync = 1
  t.window.depth = 24            -- bufor głębi: niezbędny do grafiki 3D
  t.window.msaa = 0

  -- Wyłączamy moduły, których nie potrzebujemy (szybszy start)
  t.modules.joystick = false
  t.modules.physics = false
  t.modules.video = false

  -- Serwer dedykowany (--server): bez okna, grafiki i dźwięku,
  -- więc działa na serwerze bez monitora (np. Linux przez SSH)
  local args = rawget(_G, "arg") or {}
  for _, a in pairs(args) do
    if a == "--server" then
      t.window = false
      t.modules.window = false
      t.modules.graphics = false
      t.modules.audio = false
      t.modules.sound = false
      t.modules.font = false
      t.modules.image = false
      t.modules.keyboard = false
      t.modules.mouse = false
      t.modules.touch = false
    end
  end
end
