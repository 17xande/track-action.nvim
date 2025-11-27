-- Interactive test for track-action.nvim
-- Run with: nvim -u test_interactive.lua test_file.txt

-- Minimal setup
vim.opt.runtimepath:append(vim.fn.getcwd())

-- Setup the plugin
require("track-action").setup({
  enabled = true,
  debug = false,  -- Turn off debug for cleaner output
  keybind = "<leader>ta",
  auto_save_interval = 10000,
})

-- Create a test buffer with some content
vim.cmd([[
  enew
  setlocal buftype=nofile
  call setline(1, ['Line 1 - Hello World', 'Line 2 - Testing track-action.nvim', 'Line 3 - Move around with hjkl', 'Line 4 - Try dd to delete', 'Line 5 - Try w to move by word'])
]])

-- Show instructions
vim.defer_fn(function()
  print([[

=== track-action.nvim Interactive Test ===

The plugin is now tracking your actions!

Try these commands:
  • hjkl    - Move around
  • w/b     - Word movements
  • dd      - Delete a line
  • yy      - Yank a line
  • p       - Put (paste)
  • u       - Undo
  • <leader>ta - Show stats window (press \ then t then a)
  • :TrackActionStats - Alternative way to show stats

When done testing:
  • :TrackActionTop 10 - See your top 10 actions
  • :q - Quit

Press any key to start...
]])
end, 100)
