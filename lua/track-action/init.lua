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

--- Display statistics in a floating window
function M.show_stats()
  local actions, metadata = M.get_stats()

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)

  -- Prepare content
  local lines = {
    "=== TrackAction.nvim Statistics ===",
    "",
    string.format("Total actions: %d", metadata.total_actions or 0),
    string.format("Unique actions: %d", vim.tbl_count(actions)),
    "",
  }

  if metadata.first_tracked then
    table.insert(lines, string.format("First tracked: %s", os.date("%Y-%m-%d %H:%M:%S", metadata.first_tracked)))
  end

  if metadata.last_updated then
    table.insert(lines, string.format("Last updated: %s", os.date("%Y-%m-%d %H:%M:%S", metadata.last_updated)))
  end

  table.insert(lines, "")
  table.insert(lines, "=== All Actions (sorted by count) ===")
  table.insert(lines, "")

  -- Get all actions sorted by count
  local sorted_actions = {}
  for action, count in pairs(actions) do
    table.insert(sorted_actions, { action = action, count = count })
  end

  table.sort(sorted_actions, function(a, b)
    return a.count > b.count
  end)

  -- Display all actions
  for i, item in ipairs(sorted_actions) do
    table.insert(lines, string.format("%3d. %-40s %7d", i, item.action, item.count))
  end

  if #sorted_actions == 0 then
    table.insert(lines, "  (no actions tracked yet)")
  end

  -- Set buffer content
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")

  -- Calculate window size (make it wider to accommodate action names)
  local width = 70
  local height = math.min(#lines + 2, vim.o.lines - 4)

  -- Create floating window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = " TrackAction.nvim ",
    title_pos = "center",
  })

  -- Set keymaps to close window
  vim.api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>close<cr>", { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", "<cmd>close<cr>", { noremap = true, silent = true })

  return win
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
    M.show_stats()
  end, { desc = "Show statistics in floating window" })

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

--- Setup keybind for showing stats
function M.setup_keybind()
  local opts = config.get()

  -- Don't set up keybind if it's disabled
  if not opts.keybind or opts.keybind == false then
    config.debug("TrackAction: keybind disabled")
    return
  end

  -- Set up the keybind
  vim.keymap.set("n", opts.keybind, function()
    M.show_stats()
  end, {
    noremap = true,
    silent = true,
    desc = "Show TrackAction statistics",
  })

  config.debug("TrackAction: keybind set to %s", opts.keybind)
end

return M
