-- Unit tests for track-action.nvim
-- Run with: nvim -u test_unit.lua --headless +'lua run_tests()' +qa

vim.opt.runtimepath:append(vim.fn.getcwd())

function run_tests()
  print("\n=== track-action.nvim Unit Tests ===\n")

  local all_passed = true
  local test_count = 0
  local pass_count = 0

  local function test(name, fn)
    test_count = test_count + 1
    io.write(string.format("Test %d: %s ... ", test_count, name))
    io.flush()

    local ok, err = pcall(fn)
    if ok then
      print("✓ PASS")
      pass_count = pass_count + 1
    else
      print("✗ FAIL")
      print("  Error: " .. tostring(err))
      all_passed = false
    end
  end

  -- Test 1: Module loading
  test("Load track-action module", function()
    local track_action = require("track-action")
    assert(track_action ~= nil, "Module should load")
    assert(type(track_action.setup) == "function", "Should have setup function")
  end)

  -- Test 2: Parser module
  test("Load parser module", function()
    local parser_mod = require("track-action.parser")
    assert(parser_mod ~= nil, "Parser module should load")
    assert(type(parser_mod.new) == "function", "Should have new function")
  end)

  -- Test 3: Parser basic functionality
  test("Parser can parse simple motion", function()
    local parser_mod = require("track-action.parser")
    local parser = parser_mod.new()
    local action = parser:feed_key("w")
    assert(action == "w", "Should parse 'w' motion, got: " .. tostring(action))
  end)

  -- Test 4: Parser with count
  test("Parser strips counts", function()
    local parser_mod = require("track-action.parser")
    local parser = parser_mod.new()

    parser:feed_key("3")  -- Count
    local action = parser:feed_key("w")  -- Motion
    assert(action == "w", "Should parse '3w' as 'w', got: " .. tostring(action))
  end)

  -- Test 5: Parser double operator
  test("Parser handles doubled operators", function()
    local parser_mod = require("track-action.parser")
    local parser = parser_mod.new()

    local action = parser:feed_key("d")  -- First d
    assert(action == nil, "First 'd' should not complete")

    action = parser:feed_key("d")  -- Second d
    assert(action == "dd", "Should parse 'dd' as 'dd', got: " .. tostring(action))
  end)

  -- Test 6: Commands module
  test("Load commands module", function()
    local commands = require("track-action.commands")
    assert(commands ~= nil, "Commands module should load")
    assert(commands.is_operator("d") == true, "Should recognize 'd' as operator")
    assert(commands.is_motion("w") ~= false, "Should recognize 'w' as motion")
  end)

  -- Test 7: Config module
  test("Load and setup config", function()
    local config = require("track-action.config")
    assert(config ~= nil, "Config module should load")

    config.setup({ enabled = false })
    local opts = config.get()
    assert(opts.enabled == false, "Should apply user config")
  end)

  -- Test 8: Storage module
  test("Load storage module", function()
    local storage = require("track-action.storage")
    assert(storage ~= nil, "Storage module should load")
    assert(type(storage.save) == "function", "Should have save function")
    assert(type(storage.load) == "function", "Should have load function")
  end)

  -- Test 9: Mappings module
  test("Load mappings module", function()
    local mappings = require("track-action.mappings")
    assert(mappings ~= nil, "Mappings module should load")
    assert(type(mappings.resolve_rhs) == "function", "Should have resolve_rhs function")
  end)

  -- Test 10: Integration test
  test("Full plugin setup", function()
    local track_action = require("track-action")
    track_action.setup({
      enabled = true,
      debug = false,
      auto_save_interval = 0,
    })

    -- Check that it's running
    local tracker = require("track-action.tracker")
    assert(tracker.is_running(), "Tracker should be running after setup")
  end)

  -- Summary
  print(string.format("\n=== Test Summary ==="))
  print(string.format("Total: %d", test_count))
  print(string.format("Passed: %d", pass_count))
  print(string.format("Failed: %d", test_count - pass_count))

  if all_passed then
    print("\n✓ All tests PASSED!\n")
  else
    print("\n✗ Some tests FAILED\n")
    vim.cmd("cquit 1")  -- Exit with error code
  end
end
