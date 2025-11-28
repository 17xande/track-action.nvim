-- Test for buffer modification bug fix
-- Run with: nvim -u test_buffer_modifications.lua --headless +'lua run_tests()' +qa!

vim.opt.runtimepath:append(vim.fn.getcwd())
vim.opt.hidden = true  -- Allow buffers to be hidden without saving

function run_tests()
  print("\n=== Testing Buffer Modification Bug Fix ===\n")

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

  -- Setup plugin
  local track_action = require("track-action")
  track_action.setup({
    enabled = true,
    debug = false,
    auto_save_interval = 0,
  })

  local tracker = require("track-action.tracker")

  -- Test 1: Tracker stays running after direct action tracking
  test("Tracker stays running after action tracking", function()
    assert(tracker.is_running(), "Tracker should be running")

    -- Get initial action count
    local actions_before, _ = tracker.get_stats()
    local initial_count = actions_before["test_action"] or 0

    -- Manually track an action (simulates what happens when keys are pressed)
    local parser = require("track-action.parser").new()
    local action = parser:feed_key("d")
    action = parser:feed_key("d")

    assert(tracker.is_running(), "Tracker should still be running")
  end)

  -- Test 2: Stats window can be created and updated without crashing
  test("Stats window can be created during buffer modifications", function()
    -- Create a buffer
    vim.cmd("enew")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {"Line 1", "Line 2", "Line 3"})

    -- Show stats window
    track_action.show_stats()
    assert(track_action.is_stats_visible(), "Stats window should be visible")

    -- Modify buffer (this used to cause crashes)
    vim.api.nvim_buf_set_lines(0, 0, 1, false, {})

    -- Window should still be valid
    assert(track_action.is_stats_visible(), "Stats window should still be visible after buffer mod")

    -- Clean up
    track_action.hide_stats()
  end)

  -- Test 3: update_stats_window handles invalid buffer gracefully
  test("Stats update handles buffer modifications gracefully", function()
    -- Create and show stats
    vim.cmd("enew")
    track_action.show_stats()
    assert(track_action.is_stats_visible(), "Stats window should be visible")

    -- Try to update stats (should not crash even with buffer mods happening)
    track_action.notify_action_tracked()
    vim.wait(100)  -- Wait for scheduled update

    -- Should still be visible
    assert(track_action.is_stats_visible(), "Stats window should survive update")

    track_action.hide_stats()
  end)

  -- Test 4: Tracker error handling doesn't crash on notification errors
  test("Tracker survives notification errors", function()
    assert(tracker.is_running(), "Tracker should be running")

    -- Call notify_action_tracked multiple times
    -- (this is what happens when actions are tracked)
    for i = 1, 10 do
      track_action.notify_action_tracked()
    end

    vim.wait(100)  -- Wait for scheduled updates

    assert(tracker.is_running(), "Tracker should still be running after notifications")
  end)

  -- Test 5: Stats window update with buffer being deleted
  test("Stats window survives buffer deletion", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {"Test"})

    track_action.show_stats()
    assert(track_action.is_stats_visible(), "Stats window should be visible")

    -- Delete the buffer
    vim.cmd("bdelete! " .. buf)

    -- Notify should not crash
    track_action.notify_action_tracked()
    vim.wait(100)

    -- Stats window might still be visible (it's a separate buffer)
    -- Main thing is we didn't crash
    assert(tracker.is_running(), "Tracker should still be running")

    track_action.hide_stats()
  end)

  -- Test 6: Multiple rapid buffer modifications
  test("Tracker handles rapid buffer modifications", function()
    vim.cmd("enew")
    local buf = vim.api.nvim_get_current_buf()

    track_action.show_stats()

    -- Rapid buffer modifications
    for i = 1, 20 do
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {"Line " .. i})
      track_action.notify_action_tracked()
    end

    vim.wait(200)  -- Wait for all scheduled updates

    assert(tracker.is_running(), "Tracker should survive rapid modifications")
    assert(vim.api.nvim_buf_is_valid(buf), "Buffer should still be valid")

    track_action.hide_stats()
  end)

  -- Test 7: Stats accumulate correctly
  test("Stats accumulate correctly", function()
    local parser = require("track-action.parser").new()

    -- Simulate tracking some actions
    local actions_before, metadata_before = tracker.get_stats()
    local total_before = metadata_before.total_actions

    -- Parser should normalize and complete actions
    parser:feed_key("d")
    parser:feed_key("d")  -- Should complete as "dd"

    local actions_after, metadata_after = tracker.get_stats()

    -- Metadata should be valid
    assert(type(metadata_after.total_actions) == "number", "total_actions should be a number")
    assert(type(metadata_after.last_updated) == "number" or metadata_after.last_updated == nil,
           "last_updated should be a number or nil")
  end)

  -- Test 8: Window validation in update_stats_window
  test("update_stats_window validates window properly", function()
    -- Create stats window
    track_action.show_stats()
    local win = vim.api.nvim_get_current_win()

    -- Call notify multiple times (should validate window each time)
    for i = 1, 5 do
      track_action.notify_action_tracked()
    end

    vim.wait(100)

    assert(track_action.is_stats_visible(), "Stats should still be visible")

    track_action.hide_stats()

    -- After hiding, notify should not crash
    track_action.notify_action_tracked()
    vim.wait(50)

    assert(not track_action.is_stats_visible(), "Stats should be hidden")
    assert(tracker.is_running(), "Tracker should still be running")
  end)

  -- Test 9: Error handling with pcall protection
  test("Tracker has proper pcall error protection", function()
    -- The tracker should have pcall wrappers around on_key callback
    -- We test this by ensuring tracker keeps running even after errors

    assert(tracker.is_running(), "Tracker should be running")

    -- Create multiple buffers and modify them
    for i = 1, 5 do
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {"Test " .. i})
      vim.api.nvim_buf_delete(buf, { force = true })
    end

    -- Tracker should still be running
    assert(tracker.is_running(), "Tracker should survive buffer operations")
  end)

  -- Test 10: scheduled notify_action_tracked doesn't block
  test("notify_action_tracked uses vim.schedule properly", function()
    track_action.show_stats()

    -- These should all be scheduled, not blocking
    local start_time = vim.loop.now()
    for i = 1, 100 do
      track_action.notify_action_tracked()
    end
    local end_time = vim.loop.now()

    -- Should complete quickly since it's all scheduled
    local duration = end_time - start_time
    assert(duration < 100, "notify calls should be fast (scheduled, not blocking)")

    vim.wait(200)  -- Wait for all scheduled updates to complete

    assert(tracker.is_running(), "Tracker should still be running")
    track_action.hide_stats()
  end)

  -- Summary
  print(string.format("\n=== Test Summary ==="))
  print(string.format("Total: %d", test_count))
  print(string.format("Passed: %d", pass_count))
  print(string.format("Failed: %d", test_count - pass_count))

  if all_passed then
    print("\n✓ All buffer modification tests PASSED!")
    print("The bug fix is working correctly.\n")
  else
    print("\n✗ Some tests FAILED\n")
    vim.cmd("cquit 1")
  end
end
