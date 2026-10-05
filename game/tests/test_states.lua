-- tests/test_states.lua
local T = require("tests.testlib")
local StateManager = require("states.manager")

local suite = T.suite("states")

suite:test("switch wywoluje leave i enter", function()
  local log = {}
  local a = {
    enter = function() log[#log + 1] = "a.enter" end,
    leave = function() log[#log + 1] = "a.leave" end,
  }
  local b = {
    enter = function(_, arg) log[#log + 1] = "b.enter:" .. arg end,
  }
  local m = StateManager.new()
  m:switch(a)
  m:switch(b, "x")
  T.eq(table.concat(log, ","), "a.enter,a.leave,b.enter:x")
  T.eq(m.current, b)
end)

suite:test("call przekazuje argumenty i zwraca wynik", function()
  local s = { add = function(self, x, y) return x + y end }
  local m = StateManager.new()
  m:switch(s)
  T.eq(m:call("add", 2, 3), 5)
end)

suite:test("brak metody albo stanu nie jest bledem", function()
  local m = StateManager.new()
  T.eq(m:call("draw"), nil)
  m:switch({})
  T.eq(m:call("draw"), nil)
end)

return suite
