-- core/player.lua
-- Gracz: pozycja, ruch (fizyka jak w Minecraft Beta 1.8) i stan.
-- Wszystkie wartości ruchu są "na tick" (1/20 s), tak jak w oryginale.
-- Zdrowie, głód i doświadczenie liczy core/survival.lua.

local physics = require("core.physics")
local blocks = require("core.blocks")

local M = {}

local Player = {}
Player.__index = Player

M.WIDTH = 0.6
M.HEIGHT = 1.8
M.EYE_HEIGHT = 1.62
M.SNEAK_EYE_DROP = 0.08

local GRAVITY = 0.08
local AIR_DRAG = 0.98
local JUMP_VELOCITY = 0.42
local BASE_FRICTION = 0.6 * 0.91

function M.new(x, y, z)
  local self = setmetatable({}, Player)
  self.x, self.y, self.z = x or 0, y or 80, z or 0
  self.prevX, self.prevY, self.prevZ = self.x, self.y, self.z
  self.vx, self.vy, self.vz = 0, 0, 0
  self.yaw, self.pitch = 0, 0
  self.width, self.height = M.WIDTH, M.HEIGHT
  self.stepHeight = 0.5
  self.onGround = false
  self.collidedH = false
  self.fallDistance = 0
  self.flying = false
  self.sprinting = false
  self.sneaking = false
  self.inWater = false
  self.inLava = false
  self.headInWater = false
  self.gameMode = "survival" -- survival | creative
  self.input = { forward = 0, strafe = 0, jump = false, sneak = false, sprint = false }
  self.walkDist = 0          -- do kołysania kamery i dźwięku kroków
  self.prevWalkDist = 0
  self.events = {}           -- zdarzenia dla survival (lądowanie, skok...)
  return self
end

function Player:eyeHeight()
  return M.EYE_HEIGHT - (self.sneaking and M.SNEAK_EYE_DROP or 0)
end

-- Pozycja oczu z interpolacją między tickami (do kamery)
function Player:eyePosition(alpha)
  alpha = alpha or 1
  local x = self.prevX + (self.x - self.prevX) * alpha
  local y = self.prevY + (self.y - self.prevY) * alpha
  local z = self.prevZ + (self.z - self.prevZ) * alpha
  return x, y + self:eyeHeight(), z
end

function Player:lookVector()
  local cp = math.cos(self.pitch)
  return -math.sin(self.yaw) * cp, math.sin(self.pitch), -math.cos(self.yaw) * cp
end

-- AABB gracza
function Player:bounds()
  local hw = self.width / 2
  return self.x - hw, self.y, self.z - hw, self.x + hw, self.y + self.height, self.z + hw
end

-- Dodaje przyspieszenie w kierunku patrzenia (jak moveFlying w MC)
function Player:moveRelative(strafe, forward, accel)
  local d = strafe * strafe + forward * forward
  if d < 1e-4 then return end
  d = math.sqrt(d)
  if d < 1 then d = 1 end
  d = accel / d
  strafe, forward = strafe * d, forward * d
  local s, c = math.sin(self.yaw), math.cos(self.yaw)
  -- przód = (-sin, -cos), prawo = (cos, -sin)
  self.vx = self.vx - forward * s + strafe * c
  self.vz = self.vz - forward * c - strafe * s
end

function Player:addEvent(name, value)
  self.events[#self.events + 1] = { name, value }
end

-- Śliskość bloku pod nogami (lód)
local function slipperiness(world, p)
  local id = world:getBlock(math.floor(p.x), math.floor(p.y - 0.5), math.floor(p.z))
  local def = blocks.defs[id]
  if def and def.slippery then return 0.98 end
  return 0.6
end

-- Jeden tick ruchu. canSprint: survival sprawdza głód.
function Player:tick(world, canSprint)
  self.prevX, self.prevY, self.prevZ = self.x, self.y, self.z
  self.prevWalkDist = self.walkDist
  local inp = self.input

  self.inWater = physics.inLiquid(world, self, "water")
  self.inLava = physics.inLiquid(world, self, "lava")
  local ex, ey, ez = self.x, self.y + self:eyeHeight(), self.z
  self.headInWater = physics.pointInLiquid(world, ex, ey, ez, "water")
  self.headInLava = physics.pointInLiquid(world, ex, ey, ez, "lava")

  local forward, strafe = inp.forward, inp.strafe
  self.sneaking = inp.sneak and not self.flying

  -- sprint: tylko do przodu, nie kucając, gdy głód pozwala
  if inp.sprint and forward > 0 and not self.sneaking and canSprint ~= false then
    if not self.sprinting then self.sprinting = true end
  end
  if self.sprinting and (forward <= 0 or self.collidedH or self.sneaking or canSprint == false) then
    self.sprinting = false
  end

  if self.sneaking then
    forward, strafe = forward * 0.3, strafe * 0.3
  end

  if self.gameMode ~= "creative" then self.flying = false end

  if self.flying then
    self:tickFlying(world, forward, strafe)
  elseif self.inWater or self.inLava then
    self:tickSwimming(world, forward, strafe)
  else
    self:tickWalking(world, forward, strafe)
  end

  local dx, dz = self.x - self.prevX, self.z - self.prevZ
  if self.onGround then
    self.walkDist = self.walkDist + math.sqrt(dx * dx + dz * dz) * 0.6
  end
end

function Player:tickWalking(world, forward, strafe)
  local inp = self.input
  local friction = 0.91
  if self.onGround then friction = slipperiness(world, self) * 0.91 end

  if inp.jump and self.onGround then
    self.vy = JUMP_VELOCITY
    if self.sprinting then
      -- skok w biegu daje dodatkowy wyrzut do przodu
      self.vx = self.vx - math.sin(self.yaw) * 0.2
      self.vz = self.vz - math.cos(self.yaw) * 0.2
    end
    self:addEvent("jump", self.sprinting)
  end

  local accel
  if self.onGround then
    accel = 0.1 * (0.16277136 / (friction * friction * friction))
  else
    accel = 0.02
  end
  if self.sprinting then accel = accel * 1.3 end
  self:moveRelative(strafe, forward, accel)

  local climbing = physics.onClimbable(world, self)
  if climbing then
    local lim = 0.15
    if self.vx < -lim then self.vx = -lim elseif self.vx > lim then self.vx = lim end
    if self.vz < -lim then self.vz = -lim elseif self.vz > lim then self.vz = lim end
    if self.vy < -lim then self.vy = -lim end
    if self.sneaking and self.vy < 0 then self.vy = 0 end
    self.fallDistance = 0
  end

  local wasOnGround = self.onGround
  local mx, my, mz, wx, wy, wz = physics.move(world, self, self.vx, self.vy, self.vz, self.sneaking)
  self:updateFall(my, wasOnGround)

  -- uderzenie w przeszkodę zatrzymuje ruch w tej osi
  if mx ~= wx then self.vx = 0 end
  if mz ~= wz then self.vz = 0 end
  if my ~= wy then self.vy = 0 end
  if self.collidedH and climbing then self.vy = 0.2 end

  self.vy = (self.vy - GRAVITY) * AIR_DRAG
  self.vx = self.vx * friction
  self.vz = self.vz * friction
end

function Player:tickSwimming(world, forward, strafe)
  local inp = self.input
  local lava = self.inLava and not self.inWater
  self:moveRelative(strafe, forward, 0.02)
  local wasOnGround = self.onGround
  local _, my = physics.move(world, self, self.vx, self.vy, self.vz, false)
  self:updateFall(my, wasOnGround)
  local drag = lava and 0.5 or 0.8
  self.vx, self.vy, self.vz = self.vx * drag, self.vy * drag, self.vz * drag
  self.vy = self.vy - 0.02
  if inp.jump then self.vy = self.vy + 0.04 end
  -- wyskakiwanie z wody na brzeg
  if self.collidedH then
    local hw = self.width / 2
    local free = not physics.intersects(world, self.x - hw + self.vx, self.y + 0.6,
      self.z - hw + self.vz, self.x + hw + self.vx, self.y + self.height + 0.6, self.z + hw + self.vz)
    if free then self.vy = 0.3 end
  end
  self.fallDistance = 0
end

function Player:tickFlying(world, forward, strafe)
  local inp = self.input
  local accel = self.sprinting and 0.1 or 0.05
  self:moveRelative(strafe, forward, accel)
  if inp.jump then self.vy = self.vy + 0.15 end
  if inp.sneak then self.vy = self.vy - 0.15 end
  physics.move(world, self, self.vx, self.vy, self.vz, false)
  self.vx, self.vz = self.vx * 0.91, self.vz * 0.91
  self.vy = self.vy * 0.6
  self.fallDistance = 0
  if self.onGround then self.flying = false end
end

-- Liczenie wysokości upadku (obrażenia liczy survival przy lądowaniu)
function Player:updateFall(dy, wasOnGround)
  if self.onGround then
    if self.fallDistance > 0 then
      self:addEvent("land", self.fallDistance)
    end
    self.fallDistance = 0
  elseif dy < 0 then
    self.fallDistance = self.fallDistance - dy
  end
end

return M
