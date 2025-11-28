-- Action tracker using vim.on_key() with parser and mapping resolver

local parser_mod = require("track-action.parser")
local mappings = require("track-action.mappings")
local config = require("track-action.config")

local M = {}

--- Parser instance
---@type Parser|nil
local parser = nil

--- Action statistics
---@type table<string, number>
local actions = {}

--- Metadata about tracking session
---@type table
local metadata = {
  first_tracked = nil,
  last_updated = nil,
  total_actions = 0,
  session_start = nil,
}

--- Key buffer for potential mapping detection
local key_buffer = ""

--- Timeout for key buffer (milliseconds)
local KEY_BUFFER_TIMEOUT = 1000

--- Timer for key buffer timeout
local key_buffer_timer = nil

--- Namespace ID for vim.on_key()
local ns_id = nil

--- Track a semantic action
---@param action string Semantic action name
local function track_action(action)
  if not action or action == "" then
    return
  end

  -- Check if action should be excluded
  if config.should_exclude(action) then
    config.debug("Tracker: excluding action: %s", action)
    return
  end

  -- Update statistics
  actions[action] = (actions[action] or 0) + 1
  metadata.total_actions = metadata.total_actions + 1
  metadata.last_updated = os.time()

  config.debug("Tracker: tracked action: %s (count: %d)", action, actions[action])

  -- Notify main module to update stats window if visible
  -- Use vim.schedule to avoid issues during buffer modifications
  vim.schedule(function()
    local ok, main = pcall(require, "track-action")
    if ok and main.notify_action_tracked then
      pcall(main.notify_action_tracked)
    end
  end)
end

--- Clear the key buffer
local function clear_key_buffer()
  if key_buffer ~= "" then
    config.debug("Tracker: clearing key buffer: '%s'", key_buffer)
    key_buffer = ""
  end

  if key_buffer_timer then
    key_buffer_timer:stop()
    key_buffer_timer = nil
  end
end

--- Handle key buffer timeout
local function on_key_buffer_timeout()
  config.debug("Tracker: key buffer timeout, clearing")
  clear_key_buffer()

  -- Also reset parser in case it's stuck
  if parser then
    parser:reset()
  end
end

--- Check if key buffer matches a mapping
---@param mode string Current mode
---@return boolean True if mapping was found and handled
local function check_mapping(mode)
  if not config.get().resolve_mappings then
    return false
  end

  local mapping = mappings.get_mapping(key_buffer, mode)
  if mapping then
    config.debug("Tracker: found mapping for '%s': %s", key_buffer, vim.inspect(mapping))

    -- Resolve mapping to semantic action
    local semantic = mappings.resolve_rhs(mapping.rhs, mapping.desc, mapping.lhs)
    if semantic then
      track_action(semantic)
      clear_key_buffer()
      parser:reset()
      return true
    end
  end

  return false
end

--- Convert raw control character bytes to <C-x> format
---@param char string Single character
---@return string Formatted key
local function normalize_ctrl_key(char)
  local byte = string.byte(char)

  -- Control characters are bytes 1-26
  if byte >= 1 and byte <= 26 then
    -- Convert to <C-a> through <C-z> format
    local letter = string.char(byte + 96)  -- 1 -> 'a', 2 -> 'b', etc.
    return "<C-" .. letter .. ">"
  end

  -- Escape (byte 27)
  if byte == 27 then
    return "<Esc>"
  end

  -- Special cases
  if byte == 9 then
    return "<Tab>"  -- Also <C-i>
  end

  if byte == 13 then
    return "<CR>"  -- Also <C-m>
  end

  -- Return as-is
  return char
end

--- vim.on_key() callback
---@param key string Key after mappings
---@param typed string Typed keys before mappings
local function on_key(key, typed)
  if not parser then
    return
  end

  -- Ignore empty typed keys
  if typed == "" then
    config.debug("Tracker: ignoring empty typed key")
    return
  end

  -- Get current mode
  local mode = vim.api.nvim_get_mode().mode

  -- Normalize control characters
  local normalized_typed = normalize_ctrl_key(typed)

  config.debug("Tracker: on_key key='%s' typed='%s' normalized='%s' mode='%s'",
    key, typed, normalized_typed, mode)

  -- Only track in enabled modes
  local opts = config.get()
  if mode == "i" and not opts.track_insert_mode then
    config.debug("Tracker: ignoring insert mode")
    return
  end

  if (mode == "v" or mode == "V" or mode == "\22") and not opts.track_visual_mode then
    config.debug("Tracker: ignoring visual mode")
    return
  end

  -- Always ignore command-line mode (typing after :, /, ?)
  if mode == "c" then
    config.debug("Tracker: ignoring command-line mode")
    return
  end

  -- Add to key buffer (use normalized version)
  key_buffer = key_buffer .. normalized_typed

  -- Reset key buffer timeout
  if key_buffer_timer then
    key_buffer_timer:stop()
  end
  key_buffer_timer = vim.loop.new_timer()
  key_buffer_timer:start(KEY_BUFFER_TIMEOUT, 0, vim.schedule_wrap(on_key_buffer_timeout))

  -- Check if key buffer matches a mapping
  if check_mapping(mode) then
    return
  end

  -- Check if key buffer could be a mapping (partial match)
  if mappings.could_be_mapping(key_buffer, mode) then
    config.debug("Tracker: key buffer could be mapping, waiting: '%s'", key_buffer)
    return
  end

  -- Not a mapping, feed to parser
  -- Feed the normalized key to parser with mode information
  local action = parser:feed_key(normalized_typed, mode)

  if action then
    track_action(action)
    clear_key_buffer()
  end
end

--- Start tracking
function M.start()
  if parser then
    config.debug("Tracker: already started")
    return
  end

  config.debug("Tracker: starting")

  -- Initialize parser
  parser = parser_mod.new()

  -- Initialize mappings
  mappings.init()

  -- Initialize metadata
  if not metadata.first_tracked then
    metadata.first_tracked = os.time()
  end
  metadata.session_start = os.time()

  -- Register vim.on_key() callback with error handling wrapper
  ns_id = vim.api.nvim_create_namespace("track_action_tracker")
  vim.on_key(function(key, typed)
    local ok, err = pcall(on_key, key, typed)
    if not ok then
      -- Log error but don't break tracking
      vim.schedule(function()
        vim.notify("track-action: Error in tracker: " .. tostring(err), vim.log.levels.ERROR)
        config.debug("Tracker error: %s", tostring(err))
      end)
    end
  end, ns_id)

  config.debug("Tracker: started with namespace: %d", ns_id)
end

--- Stop tracking
function M.stop()
  if not parser then
    config.debug("Tracker: not running")
    return
  end

  config.debug("Tracker: stopping")

  -- Unregister vim.on_key() callback
  if ns_id then
    vim.on_key(nil, ns_id)
    ns_id = nil
  end

  -- Clear timers
  if key_buffer_timer then
    key_buffer_timer:stop()
    key_buffer_timer = nil
  end

  -- Clear state
  parser = nil
  key_buffer = ""

  config.debug("Tracker: stopped")
end

--- Reset tracking statistics
function M.reset()
  config.debug("Tracker: resetting statistics")

  actions = {}
  metadata = {
    first_tracked = os.time(),
    last_updated = os.time(),
    total_actions = 0,
    session_start = os.time(),
  }
end

--- Get current statistics
---@return table, table Actions table and metadata table
function M.get_stats()
  return actions, metadata
end

--- Get top N actions
---@param n number Number of top actions to return
---@return table Array of {action, count} pairs
function M.get_top(n)
  local sorted = {}

  for action, count in pairs(actions) do
    table.insert(sorted, { action = action, count = count })
  end

  table.sort(sorted, function(a, b)
    return a.count > b.count
  end)

  -- Return top N
  local result = {}
  for i = 1, math.min(n, #sorted) do
    table.insert(result, sorted[i])
  end

  return result
end

--- Set statistics (used when loading from file)
---@param loaded_actions table
---@param loaded_metadata table
function M.set_stats(loaded_actions, loaded_metadata)
  actions = loaded_actions or {}
  metadata = vim.tbl_extend("force", metadata, loaded_metadata or {})
  config.debug("Tracker: loaded %d actions", vim.tbl_count(actions))
end

--- Check if tracking is active
---@return boolean
function M.is_running()
  return parser ~= nil
end

return M
