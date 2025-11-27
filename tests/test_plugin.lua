-- Test script for track-action.nvim
-- Run with: nvim -u test_plugin.lua

-- Minimal setup
vim.opt.runtimepath:append(vim.fn.getcwd())

-- Setup the plugin with debug enabled
local ok, track_action = pcall(require, "track-action")

if not ok then
  print("ERROR: Failed to load track-action module")
  print(track_action)
  return
end

print("✓ Successfully loaded track-action module")

-- Setup with debug mode
local setup_ok, err = pcall(function()
  track_action.setup({
    enabled = true,
    debug = true,
    keybind = "<leader>ta",
    auto_save_interval = 5000, -- 5 seconds for testing
  })
end)

if not setup_ok then
  print("ERROR: Failed to setup track-action")
  print(err)
  return
end

print("✓ Successfully setup track-action")
print("")
print("=== Testing Instructions ===")
print("1. Press some keys in normal mode (w, j, k, dd, etc.)")
print("2. Press <leader>ta to see stats (default leader is \\)")
print("3. Or use :TrackActionStats command")
print("4. Use :TrackActionTop 10 to see top 10 actions")
print("5. Press :q to quit")
print("")
print("Commands available:")
print("  :TrackActionStats - Show stats window")
print("  :TrackActionTop [N] - Show top N actions")
print("  :TrackActionSave - Save stats")
print("  :TrackActionReset - Reset stats")
print("")

-- Wait a moment then show initial status
vim.defer_fn(function()
  print("Plugin is now tracking your actions!")
  print("Press <leader>ta to view stats")
end, 100)
