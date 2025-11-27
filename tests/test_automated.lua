-- Automated test for track-action.nvim
-- Run with: nvim -u test_automated.lua --headless -c "lua run_tests()" -c "qa"

vim.opt.runtimepath:append(vim.fn.getcwd())

-- Setup the plugin
require("track-action").setup({
  enabled = true,
  debug = false,
  auto_save_interval = 0, -- Disable auto-save for testing
})

local track_action = require("track-action")

function run_tests()
  print("\n=== Starting Automated Tests ===\n")

  -- Create a buffer with content
  vim.cmd("enew")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "Line 1",
    "Line 2",
    "Line 3",
    "Line 4",
    "Line 5",
  })

  -- Simulate some keystrokes
  local function feed_keys(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
    -- Small delay to let the tracker process
    vim.wait(10)
  end

  print("Test 1: Testing basic movements...")
  feed_keys("j")  -- Move down
  feed_keys("j")  -- Move down
  feed_keys("k")  -- Move up
  feed_keys("l")  -- Move right
  feed_keys("h")  -- Move left

  print("Test 2: Testing word movements...")
  feed_keys("w")  -- Word forward
  feed_keys("w")
  feed_keys("b")  -- Word backward

  print("Test 3: Testing operators...")
  feed_keys("yy") -- Yank line
  feed_keys("dd") -- Delete line
  feed_keys("p")  -- Put

  print("Test 4: Testing with counts...")
  feed_keys("3j") -- Move 3 down
  feed_keys("2w") -- Move 2 words

  -- Wait a moment for all actions to be processed
  vim.wait(50)

  -- Get and display stats
  print("\n=== Test Results ===\n")
  local actions, metadata = track_action.get_stats()

  print("Total actions tracked: " .. (metadata.total_actions or 0))
  print("Unique actions: " .. vim.tbl_count(actions))
  print("")

  -- Show top actions
  local top = track_action.top(15)
  if #top > 0 then
    print("Top tracked actions:")
    for i, item in ipairs(top) do
      print(string.format("  %2d. %-20s %3d times", i, item.action, item.count))
    end
  else
    print("WARNING: No actions were tracked!")
    print("This might indicate an issue with the vim.on_key() integration")
  end

  print("\n=== Tests Complete ===\n")

  -- Verify expected actions
  local function check_action(action_name, min_count)
    local count = actions[action_name] or 0
    local status = count >= min_count and "✓" or "✗"
    print(string.format("%s Action '%s': expected >= %d, got %d", status, action_name, min_count, count))
    return count >= min_count
  end

  print("\nVerifying specific actions:")
  local all_passed = true
  all_passed = check_action("j", 2) and all_passed
  all_passed = check_action("w", 2) and all_passed
  all_passed = check_action("yy", 1) and all_passed
  all_passed = check_action("dd", 1) and all_passed

  if all_passed then
    print("\n✓ All tests PASSED!")
  else
    print("\n✗ Some tests FAILED")
  end
end
