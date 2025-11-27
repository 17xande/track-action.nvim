-- track-action.nvim - Track and analyze your Vim actions
-- Main module and public API

local config = require("track-action.config")
local tracker = require("track-action.tracker")
local storage = require("track-action.storage")

local M = {}

--- Auto-save timer
local auto_save_timer = nil

--- Setup track-action.nvim with user configuration
---@param user_config table|nil User configuration
function M.setup(user_config)
  -- Setup configuration
  config.setup(user_config or {})
  local opts = config.get()

  -- Load existing stats
  local loaded_actions, loaded_metadata = storage.load()

  -- Set loaded stats in tracker
  tracker.set_stats(loaded_actions, loaded_metadata)

  -- Start tracking if enabled
  if opts.enabled then
    M.start()
  end

  -- Setup auto-save
  if opts.auto_save_interval > 0 then
    M.setup_auto_save()
  end

  -- Setup autocmd to save on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("TrackActionSave", { clear = true }),
    callback = function()
      M.save()
    end,
    desc = "Save track-action.nvim statistics on exit",
  })

  -- Create user commands
  M.create_commands()

  -- Setup keybind
  M.setup_keybind()

  config.debug("TrackAction: setup complete")
end

--- Start tracking
function M.start()
  config.debug("TrackAction: start()")
  tracker.start()
end

--- Stop tracking
function M.stop()
  config.debug("TrackAction: stop()")
  tracker.stop()
end

--- Save current statistics to file
---@return boolean Success
function M.save()
  config.debug("TrackAction: save()")

  local actions, metadata = tracker.get_stats()
  return storage.save(actions, metadata)
end

--- Reset statistics
function M.reset()
  config.debug("TrackAction: reset()")

  -- Confirm with user
  local confirm = vim.fn.confirm("Reset all track-action.nvim statistics?", "&Yes\n&No", 2)
  if confirm ~= 1 then
    return
  end

  tracker.reset()
  vim.notify("track-action.nvim: Statistics reset", vim.log.levels.INFO)
end

--- Get current statistics
---@return table, table Actions and metadata
function M.get_stats()
  return tracker.get_stats()
end

--- Get top N actions
---@param n number Number of actions to return (default 10)
---@return table Array of {action, count} pairs
function M.top(n)
  n = n or 10
  return tracker.get_top(n)
end

--- Persistent stats window and buffer
local stats_win = nil
local stats_buf = nil

--- Update the stats window content
local function update_stats_window()
  if not stats_buf or not vim.api.nvim_buf_is_valid(stats_buf) then
    return
  end

  local actions, metadata = M.get_stats()

  -- Get all actions sorted by count
  local sorted_actions = {}
  for action, count in pairs(actions) do
    table.insert(sorted_actions, { action = action, count = count })
  end

  table.sort(sorted_actions, function(a, b)
    return a.count > b.count
  end)

  -- Prepare minimal content - just the action list
  local lines = {}

  -- Limit to top 20 for display
  local display_count = math.min(20, #sorted_actions)
  for i = 1, display_count do
    local item = sorted_actions[i]
    table.insert(lines, string.format("%-20s %4d", item.action, item.count))
  end

  if #sorted_actions == 0 then
    table.insert(lines, "no actions yet")
  end

  -- Update buffer content
  vim.api.nvim_buf_set_option(stats_buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(stats_buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(stats_buf, "modifiable", false)
end

--- Display statistics in a floating window on the right side
function M.show_stats()
  -- If window already exists and is valid, just update it
  if stats_win and vim.api.nvim_win_is_valid(stats_win) then
    update_stats_window()
    return stats_win
  end

  -- Create buffer if needed
  if not stats_buf or not vim.api.nvim_buf_is_valid(stats_buf) then
    stats_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(stats_buf, "buftype", "nofile")
    vim.api.nvim_buf_set_option(stats_buf, "bufhidden", "hide")
    vim.api.nvim_buf_set_option(stats_buf, "swapfile", false)

    -- Set keymaps to close window
    vim.api.nvim_buf_set_keymap(stats_buf, "n", "q", "<cmd>lua require('track-action').hide_stats()<cr>", { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(stats_buf, "n", "<Esc>", "<cmd>lua require('track-action').hide_stats()<cr>", { noremap = true, silent = true })
  end

  -- Window dimensions - narrow width on the right
  local width = 28
  local height = math.min(22, vim.o.lines - 2)

  -- Position on right side
  local col = vim.o.columns - width - 2
  local row = 1

  -- Create floating window on the right, not stealing focus
  stats_win = vim.api.nvim_open_win(stats_buf, false, {  -- false = don't focus
    relative = "editor",
    width = width,
    height = height,
    col = col,
    row = row,
    style = "minimal",
    border = "rounded",
    focusable = false,  -- Can't be focused
    zindex = 40,  -- Lower z-index to not be too intrusive
  })

  -- Set window options
  vim.api.nvim_win_set_option(stats_win, "winblend", 10)  -- Slight transparency

  -- Update content
  update_stats_window()

  return stats_win
end

--- Hide the stats window
function M.hide_stats()
  if stats_win and vim.api.nvim_win_is_valid(stats_win) then
    vim.api.nvim_win_close(stats_win, true)
    stats_win = nil
  end
end

--- Toggle stats window visibility
function M.toggle_stats()
  if stats_win and vim.api.nvim_win_is_valid(stats_win) then
    M.hide_stats()
  else
    M.show_stats()
  end
end

--- Check if stats window is visible
function M.is_stats_visible()
  return stats_win and vim.api.nvim_win_is_valid(stats_win)
end

--- Setup auto-save timer
function M.setup_auto_save()
  if auto_save_timer then
    auto_save_timer:stop()
    auto_save_timer = nil
  end

  local opts = config.get()
  if opts.auto_save_interval <= 0 then
    config.debug("TrackAction: auto-save disabled")
    return
  end

  config.debug("TrackAction: setting up auto-save every %dms", opts.auto_save_interval)

  auto_save_timer = vim.loop.new_timer()
  auto_save_timer:start(
    opts.auto_save_interval,
    opts.auto_save_interval,
    vim.schedule_wrap(function()
      if tracker.is_running() then
        config.debug("TrackAction: auto-saving")
        M.save()
      end
    end)
  )
end

--- Stop auto-save timer
function M.stop_auto_save()
  if auto_save_timer then
    auto_save_timer:stop()
    auto_save_timer = nil
    config.debug("TrackAction: auto-save stopped")
  end
end

--- Create user commands
function M.create_commands()
  vim.api.nvim_create_user_command("TrackActionStart", function()
    M.start()
    vim.notify("track-action.nvim: Tracking started", vim.log.levels.INFO)
  end, { desc = "Start tracking actions" })

  vim.api.nvim_create_user_command("TrackActionStop", function()
    M.stop()
    vim.notify("track-action.nvim: Tracking stopped", vim.log.levels.INFO)
  end, { desc = "Stop tracking actions" })

  vim.api.nvim_create_user_command("TrackActionSave", function()
    if M.save() then
      vim.notify("track-action.nvim: Statistics saved", vim.log.levels.INFO)
    end
  end, { desc = "Save statistics to file" })

  vim.api.nvim_create_user_command("TrackActionStats", function()
    M.toggle_stats()
  end, { desc = "Toggle statistics floating window" })

  vim.api.nvim_create_user_command("TrackActionReset", function()
    M.reset()
  end, { desc = "Reset all statistics" })

  vim.api.nvim_create_user_command("TrackActionTop", function(opts)
    local n = tonumber(opts.args) or 10
    local top = M.top(n)

    print(string.format("=== Top %d Actions ===", n))
    for i, item in ipairs(top) do
      print(string.format("%2d. %-30s %6d", i, item.action, item.count))
    end
  end, { nargs = "?", desc = "Show top N actions" })

  config.debug("TrackAction: commands created")
end

--- Setup keybind for toggling stats
function M.setup_keybind()
  local opts = config.get()

  -- Don't set up keybind if it's disabled
  if not opts.keybind or opts.keybind == false then
    config.debug("TrackAction: keybind disabled")
    return
  end

  -- Set up the keybind to toggle
  vim.keymap.set("n", opts.keybind, function()
    M.toggle_stats()
  end, {
    noremap = true,
    silent = true,
    desc = "Toggle TrackAction statistics",
  })

  config.debug("TrackAction: keybind set to %s", opts.keybind)
end

--- Notify that stats should be updated (called by tracker)
function M.notify_action_tracked()
  -- If stats window is visible, update it
  if M.is_stats_visible() then
    vim.schedule(function()
      update_stats_window()
    end)
  end
end

return M
