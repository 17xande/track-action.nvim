-- Tracker spec: category field and command tracking
-- Run: nvim --headless -u tests/minimal_init.lua -c "luafile tests/tracker_spec.lua"

package.path = "tests/?.lua;" .. package.path
local h = require("harness")
local describe, it, eq, is_nil = h.describe, h.it, h.eq, h.is_nil

require("track-action.config").setup({})
local tracker = require("track-action.tracker")

-- Helper: register a callback, run fn, unregister, return received data
local function capture(fn)
  local received = nil
  local cb = function(action, data) received = data end
  tracker.on_action(cb)
  fn()
  tracker.off_action(cb)
  return received
end

describe("tracker.track_command", function()

  describe("category field", function()
    it("fires callback with category 'cmd' for vsplit", function()
      local data = capture(function() tracker.track_command("vsplit") end)
      eq("cmd", data and data.category)
    end)

    it("fires callback with category 'cmd' for write", function()
      local data = capture(function() tracker.track_command("w") end)
      eq("cmd", data and data.category)
    end)

    it("fires callback with category 'cmd' for wincmd h", function()
      local data = capture(function() tracker.track_command("wincmd h") end)
      eq("cmd", data and data.category)
    end)

    it("fires callback with category 'cmd' for split", function()
      local data = capture(function() tracker.track_command("split") end)
      eq("cmd", data and data.category)
    end)

    it("fires callback with category 'cmd' for tabnext", function()
      local data = capture(function() tracker.track_command("tabnext") end)
      eq("cmd", data and data.category)
    end)
  end)

  describe("action and native fields", function()
    it("action is ex:vsplit for vsplit", function()
      local data = capture(function() tracker.track_command("vsplit") end)
      eq("ex:vsplit", data and data.action)
    end)

    it("native is <C-w>v for vsplit", function()
      local data = capture(function() tracker.track_command("vsplit") end)
      eq("<C-w>v", data and data.native)
    end)

    it("native is <C-w>v for vs", function()
      local data = capture(function() tracker.track_command("vs") end)
      eq("<C-w>v", data and data.native)
    end)

    it("native is <C-w>s for split", function()
      local data = capture(function() tracker.track_command("split") end)
      eq("<C-w>s", data and data.native)
    end)

    it("native is <C-w>h for wincmd h", function()
      local data = capture(function() tracker.track_command("wincmd h") end)
      eq("<C-w>h", data and data.native)
    end)

    it("native is <C-w>j for wincmd j", function()
      local data = capture(function() tracker.track_command("wincmd j") end)
      eq("<C-w>j", data and data.native)
    end)

    it("native is <C-w>k for wincmd k", function()
      local data = capture(function() tracker.track_command("wincmd k") end)
      eq("<C-w>k", data and data.native)
    end)

    it("native is <C-w>l for wincmd l", function()
      local data = capture(function() tracker.track_command("wincmd l") end)
      eq("<C-w>l", data and data.native)
    end)

    it("action is ex:write for w", function()
      local data = capture(function() tracker.track_command("w") end)
      eq("ex:write", data and data.action)
    end)

    it("action is ex:quit for q", function()
      local data = capture(function() tracker.track_command("q") end)
      eq("ex:quit", data and data.action)
    end)

    it("data has count and total fields", function()
      local data = capture(function() tracker.track_command("vsplit") end)
      eq(true, data ~= nil)
      eq(true, data.count ~= nil)
      eq(true, data.total ~= nil)
    end)
  end)

  describe("ignored inputs", function()
    it("does nothing for empty string", function()
      local data = capture(function() tracker.track_command("") end)
      is_nil(data)
    end)

    it("does nothing for whitespace only", function()
      local data = capture(function() tracker.track_command("   ") end)
      is_nil(data)
    end)

    it("does nothing for nil", function()
      local data = capture(function() tracker.track_command(nil) end)
      is_nil(data)
    end)
  end)

end)

describe("tracker.on_action / off_action", function()
  it("registers callback", function()
    local called = false
    local cb = function() called = true end
    tracker.on_action(cb)
    tracker.track_command("vsplit")
    tracker.off_action(cb)
    eq(true, called)
  end)

  it("off_action stops further firing", function()
    local count = 0
    local cb = function() count = count + 1 end
    tracker.on_action(cb)
    tracker.track_command("vsplit")
    tracker.off_action(cb)
    tracker.track_command("vsplit")
    eq(1, count)
  end)

  it("multiple callbacks all fire", function()
    local count = 0
    local cb1 = function() count = count + 1 end
    local cb2 = function() count = count + 1 end
    tracker.on_action(cb1)
    tracker.on_action(cb2)
    tracker.track_command("vsplit")
    tracker.off_action(cb1)
    tracker.off_action(cb2)
    eq(2, count)
  end)
end)

h.summary()
