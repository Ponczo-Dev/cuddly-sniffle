-- core/config.lua
-- Wszystkie stałe i wartości balansu w jednym miejscu.
-- Zmieniaj tutaj, a nie w kodzie poszczególnych modułów.

local config = {
  -- Czas gry: 20 ticków na sekundę, jak w Minecrafcie
  TICKS_PER_SECOND = 20,
  -- Maksymalnie tyle ticków nadrabiamy w jednej klatce (gdy gra się przytnie)
  MAX_TICKS_PER_FRAME = 10,

  -- Świat (wartości z ery Beta)
  CHUNK_SIZE = 16,      -- szerokość i długość chunka w blokach
  WORLD_HEIGHT = 128,   -- wysokość świata (Beta: 128, od 1.2: 256)
  SEA_LEVEL = 64,       -- poziom morza

  -- Grafika i sterowanie (później trafią do menu ustawień)
  RENDER_DISTANCE = 6,  -- zasięg w chunkach
  FOV = 70,             -- kąt widzenia w stopniach
  MOUSE_SENSITIVITY = 0.15,
}

return config
