-- Configuration management for track-action.nvim

local M = {}

--- Default configuration
M.defaults = {
  -- Enable/disable tracking
  enabled = true,

  -- Auto-save interval in milliseconds (60 seconds)
  auto_save_interval = 60000,

  -- Stats file location
  stats_file = vim.fn.stdpath("data") .. "/track_action_stats.json",

  -- Track actions in insert mode
  track_insert_mode = false,

  -- Track actions in visual mode
  track_visual_mode = true,

  -- Actions to exclude from tracking
  exclude_actions = {
    "<Esc>",
    "<C-c>",
  },

  -- Resolve custom mappings (hybrid approach)
  resolve_mappings = true,

  -- Cache mapping resolution for performance
  cache_mappings = true,

  -- Debug mode (print verbose logs)
  debug = false,

  -- Log file path for debug output (e.g. "/tmp/track-action.log").
  -- When set, debug messages go to this file instead of vim.notify.
  log_file = nil,

  -- Keybind to show stats window (set to false to disable)
  keybind = "<leader>ta",
}

--- Current configuration (merged with user config)
M.options = {}

--- Setup configuration
---@param user_config table|nil User configuration to merge with defaults
function M.setup(user_config)
  M.options = vim.tbl_deep_extend("force", M.defaults, user_config or {})

  -- Validate configuration
  if type(M.options.auto_save_interval) ~= "number" then
    vim.notify("track-action.nvim: auto_save_interval must be a number", vim.log.levels.ERROR)
    M.options.auto_save_interval = M.defaults.auto_save_interval
  end

  if M.options.auto_save_interval < 1000 then
    vim.notify("track-action.nvim: auto_save_interval should be at least 1000ms", vim.log.levels.WARN)
  end

  return M.options
end

--- Get current configuration
---@return table
function M.get()
  return M.options
end

--- Check if an action should be excluded
---@param action string
---@return boolean
function M.should_exclude(action)
  for _, excluded in ipairs(M.options.exclude_actions or {}) do
    if action == excluded then
      return true
    end
  end
  return false
end

--- Log file handle (opened lazily on first debug write)
---@type file*|nil
local _log_file = nil

--- Log debug message if debug mode is enabled.
--- Writes to log_file when configured, otherwise falls back to vim.notify.
---@param msg string
---@param ... any Additional arguments to format
function M.debug(msg, ...)
  if not M.options.debug then
    return
  end
  local formatted = string.format(msg, ...)
  if M.options.log_file then
    if not _log_file then
      _log_file = io.open(M.options.log_file, "a")
    end
    if _log_file then
      _log_file:write(os.date("%H:%M:%S") .. " [track-action] " .. formatted .. "\n")
      _log_file:flush()
      return
    end
  end
  vim.notify("[track-action.nvim] " .. formatted, vim.log.levels.DEBUG)
end

return M
