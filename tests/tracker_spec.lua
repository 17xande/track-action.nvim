-- Tracker spec: category field and command tracking
-- Run: nvim --headless -u tests/minimal_init.lua -c "luafile tests/tracker_spec.lua"

package.path = "tests/?.lua;" .. package.path
local h = require("harness")
local describe, it, eq, is_nil = h.describe, h.it, h.eq, h.is_nil

require("track-action.config").setup({})
local tracker = require("track-action.tracker")

-- Helper: register a cmd callback, run fn, unregister, return received data
local function capture_cmd(fn)
  local received = nil
  local cb = function(action, data) received = data end
  tracker.on_cmd_action(cb)
  fn()
  tracker.off_cmd_action(cb)
  return received
end

-- Helper: register a key callback, run fn, unregister, return received data
local function capture_key(fn)
  local received = nil
  local cb = function(action, data) received = data end
  tracker.on_key_action(cb)
  fn()
  tracker.off_key_action(cb)
  return received
end

describe("tracker.track_command", function()

  describe("category field", function()
    it("fires callback with category 'cmd' for vsplit", function()
      local data = capture_cmd(function() tracker.track_command("vsplit") end)
      eq("cmd", data and data.category)
    end)

    it("fires callback with category 'cmd' for write", function()
      local data = capture_cmd(function() tracker.track_command("w") end)
      eq("cmd", data and data.category)
    end)

    it("fires callback with category 'cmd' for wincmd h", function()
      local data = capture_cmd(function() tracker.track_command("wincmd h") end)
      eq("cmd", data and data.category)
    end)

    it("fires callback with category 'cmd' for split", function()
      local data = capture_cmd(function() tracker.track_command("split") end)
      eq("cmd", data and data.category)
    end)

    it("fires callback with category 'cmd' for tabnext", function()
      local data = capture_cmd(function() tracker.track_command("tabnext") end)
      eq("cmd", data and data.category)
    end)
  end)

  describe("action and native fields", function()
    it("action is ex:vsplit for vsplit", function()
      local data = capture_cmd(function() tracker.track_command("vsplit") end)
      eq("ex:vsplit", data and data.action)
    end)

    it("native is <C-w>v for vsplit", function()
      local data = capture_cmd(function() tracker.track_command("vsplit") end)
      eq("<C-w>v", data and data.native)
    end)

    it("native is <C-w>v for vs", function()
      local data = capture_cmd(function() tracker.track_command("vs") end)
      eq("<C-w>v", data and data.native)
    end)

    it("native is <C-w>s for split", function()
      local data = capture_cmd(function() tracker.track_command("split") end)
      eq("<C-w>s", data and data.native)
    end)

    it("native is <C-w>h for wincmd h", function()
      local data = capture_cmd(function() tracker.track_command("wincmd h") end)
      eq("<C-w>h", data and data.native)
    end)

    it("native is <C-w>j for wincmd j", function()
      local data = capture_cmd(function() tracker.track_command("wincmd j") end)
      eq("<C-w>j", data and data.native)
    end)

    it("native is <C-w>k for wincmd k", function()
      local data = capture_cmd(function() tracker.track_command("wincmd k") end)
      eq("<C-w>k", data and data.native)
    end)

    it("native is <C-w>l for wincmd l", function()
      local data = capture_cmd(function() tracker.track_command("wincmd l") end)
      eq("<C-w>l", data and data.native)
    end)

    it("action is ex:write for w", function()
      local data = capture_cmd(function() tracker.track_command("w") end)
      eq("ex:write", data and data.action)
    end)

    it("action is ex:quit for q", function()
      local data = capture_cmd(function() tracker.track_command("q") end)
      eq("ex:quit", data and data.action)
    end)

    it("data has count and total fields", function()
      local data = capture_cmd(function() tracker.track_command("vsplit") end)
      eq(true, data ~= nil)
      eq(true, data.count ~= nil)
      eq(true, data.total ~= nil)
    end)
  end)

  describe("ignored inputs", function()
    it("does nothing for empty string", function()
      local data = capture_cmd(function() tracker.track_command("") end)
      is_nil(data)
    end)

    it("does nothing for whitespace only", function()
      local data = capture_cmd(function() tracker.track_command("   ") end)
      is_nil(data)
    end)

    it("does nothing for nil", function()
      local data = capture_cmd(function() tracker.track_command(nil) end)
      is_nil(data)
    end)
  end)

end)

describe("g-prefix key buffer with user g-mappings", function()
  -- Regression: when user has g* mappings (e.g. gd for LSP), the tracker holds
  -- 'g' waiting to see if it's a mapping prefix. When 'e' follows and 'ge' is not
  -- a mapping, the old code fed only 'e' to the parser (emitting "e"), not "ge".
  -- Fix: pending_keys replays all held keys to the parser when no mapping matches.
  local function setup()
    vim.keymap.set("n", "gd", function() end, { buffer = 0 })
    tracker.start()
    require("track-action.mappings").refresh_cache()
  end

  local function teardown()
    tracker.stop()
    pcall(vim.keymap.del, "n", "gd", { buffer = 0 })
  end

  it("ge emits 'ge' not 'e' when gd mapping exists", function()
    setup()
    local received = nil
    tracker.on_key_action(function(action) received = action end)
    tracker._process_key("g", "n")
    tracker._process_key("e", "n")
    teardown()
    eq("ge", received)
  end)

  it("gE emits 'gE' not 'E' when gd mapping exists", function()
    setup()
    local received = nil
    tracker.on_key_action(function(action) received = action end)
    tracker._process_key("g", "n")
    tracker._process_key("E", "n")
    teardown()
    eq("gE", received)
  end)

  it("gg emits 'gg' when gd mapping exists", function()
    setup()
    local received = nil
    tracker.on_key_action(function(action) received = action end)
    tracker._process_key("g", "n")
    tracker._process_key("g", "n")
    teardown()
    eq("gg", received)
  end)
end)

describe("tracker.on_cmd_action / off_cmd_action", function()
  it("registers callback", function()
    local called = false
    local cb = function() called = true end
    tracker.on_cmd_action(cb)
    tracker.track_command("vsplit")
    tracker.off_cmd_action(cb)
    eq(true, called)
  end)

  it("off_cmd_action stops further firing", function()
    local count = 0
    local cb = function() count = count + 1 end
    tracker.on_cmd_action(cb)
    tracker.track_command("vsplit")
    tracker.off_cmd_action(cb)
    tracker.track_command("vsplit")
    eq(1, count)
  end)

  it("multiple callbacks all fire", function()
    local count = 0
    local cb1 = function() count = count + 1 end
    local cb2 = function() count = count + 1 end
    tracker.on_cmd_action(cb1)
    tracker.on_cmd_action(cb2)
    tracker.track_command("vsplit")
    tracker.off_cmd_action(cb1)
    tracker.off_cmd_action(cb2)
    eq(2, count)
  end)
end)

-- =========================================================================
-- Separate event system: on_key_action / on_cmd_action
-- =========================================================================

describe("tracker.on_key_action / on_cmd_action", function()

  describe("on_cmd_action only fires for commands", function()
    it("fires for track_command", function()
      local received = nil
      local cb = function(action, data) received = data end
      tracker.on_cmd_action(cb)
      tracker.track_command("vsplit")
      tracker.off_cmd_action(cb)
      eq("cmd", received and received.category)
    end)

    it("does not fire for keybind actions", function()
      tracker.start()
      local received = nil
      local cb = function(action, data) received = data end
      tracker.on_cmd_action(cb)
      tracker._process_key("j", "n")
      tracker.off_cmd_action(cb)
      tracker.stop()
      is_nil(received)
    end)
  end)

  describe("on_key_action only fires for keybinds", function()
    it("fires for keybind action", function()
      tracker.start()
      local received = nil
      local cb = function(action, data) received = data end
      tracker.on_key_action(cb)
      tracker._process_key("j", "n")
      tracker.off_key_action(cb)
      tracker.stop()
      eq("key", received and received.category)
    end)

    it("does not fire for command actions", function()
      local received = nil
      local cb = function(action, data) received = data end
      tracker.on_key_action(cb)
      tracker.track_command("vsplit")
      tracker.off_key_action(cb)
      is_nil(received)
    end)
  end)

end)

-- =========================================================================
-- track_command tracks all ex commands
-- =========================================================================

describe("track_command tracks all ex commands", function()
  it("tracks unknown commands via ex: prefix", function()
    local data = capture_cmd(function() tracker.track_command("SomeRandomPlugin") end)
    eq("ex:SomeRandomPlugin", data and data.action)
  end)

  it("tracks Lua commands", function()
    local data = capture_cmd(function() tracker.track_command("lua print('hi')") end)
    eq("ex:lua", data and data.action)
  end)

  it("tracks help commands", function()
    local data = capture_cmd(function() tracker.track_command("help api") end)
    eq("ex:help", data and data.action)
  end)
end)

h.summary()
