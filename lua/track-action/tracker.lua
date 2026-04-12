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

--- Keys buffered in key_buffer but not yet fed to the parser.
--- When a mapping is being waited on, keys accumulate here.
--- If no mapping matches they are replayed to the parser all at once.
---@type string[]
local pending_keys = {}

--- Timeout for key buffer (milliseconds)
local KEY_BUFFER_TIMEOUT = 1000

--- Timer for key buffer timeout
local key_buffer_timer = nil

--- Namespace ID for vim.on_key()
local ns_id = nil

--- Registered callbacks
---@type fun(action: string, data: table)[]
local callbacks = {}

--- Register a callback to be called when an action is tracked.
--- The callback receives the action string and a data table with count info.
---@param fn fun(action: string, data: table)
function M.on_action(fn)
  callbacks[#callbacks + 1] = fn
end

--- Remove a previously registered callback.
---@param fn fun(action: string, data: table)
function M.off_action(fn)
  for i = #callbacks, 1, -1 do
    if callbacks[i] == fn then
      table.remove(callbacks, i)
      return
    end
  end
end

--- Track a semantic action
---@param action string Semantic action name
---@param native string|nil Native key equivalent (e.g. "<C-w>v")
---@param category string|nil "key" (keybinding) or "cmd" (typed ex command); defaults to "key"
local function track_action(action, native, category)
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

  config.debug("Tracker: tracked action: %s (count: %d, native: %s)", action, actions[action], native or "nil")

  local data = {
    action = action,
    count = actions[action],
    total = metadata.total_actions,
    native = native,
    category = category or "key",
  }

  -- Fire registered callbacks
  for _, fn in ipairs(callbacks) do
    local ok, err = pcall(fn, action, data)
    if not ok then
      config.debug("Tracker: callback error: %s", tostring(err))
    end
  end

  -- Fire User autocmd (deferred to avoid issues during vim.on_key)
  vim.schedule(function()
    vim.api.nvim_exec_autocmds("User", {
      pattern = "TrackAction",
      data = data,
    })
  end)
end

--- Track a typed ex command (e.g. from CmdlineLeave autocmd).
--- Resolves the command to a semantic action and fires callbacks with category "cmd".
---@param cmd string The command text (without leading colon)
function M.track_command(cmd)
  cmd = vim.trim(cmd or "")
  if cmd == "" then
    return
  end
  local action, native = mappings.resolve_rhs("<cmd>" .. cmd .. "<cr>", nil, nil)
  if not action then
    return
  end
  track_action(action, native, "cmd")
end

--- Clear the key buffer and pending key queue
local function clear_key_buffer()
  if key_buffer ~= "" then
    config.debug("Tracker: clearing key buffer: '%s'", key_buffer)
    key_buffer = ""
  end
  pending_keys = {}

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
    local semantic, native = mappings.resolve_rhs(mapping.rhs, mapping.desc, mapping.lhs)
    if semantic then
      track_action(semantic, native)
      clear_key_buffer()
      if parser then
        parser:reset()
      end
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

--- Process a normalized typed key against the mapping detector and parser.
--- Keys are buffered while waiting for a potential multi-key mapping; once
--- determined not to be a mapping, all buffered keys are replayed to the
--- parser in order (fixing g-prefix sequences like ge/gE when user has gd etc.)
---@param normalized_typed string Already-normalized key (e.g. "g", "e", "<C-w>")
---@param mode string Current vim mode
local function process_key(normalized_typed, mode)
  -- Add to key buffer and pending queue
  key_buffer = key_buffer .. normalized_typed
  table.insert(pending_keys, normalized_typed)

  -- Reset key buffer timeout
  if key_buffer_timer then
    key_buffer_timer:stop()
  end
  key_buffer_timer = vim.loop.new_timer()
  if not key_buffer_timer then
    return
  end
  key_buffer_timer:start(KEY_BUFFER_TIMEOUT, 0, vim.schedule_wrap(on_key_buffer_timeout))

  -- Check if key buffer matches a mapping (clear_key_buffer inside resets pending_keys)
  if check_mapping(mode) then
    return
  end

  -- Check if key buffer could be a mapping (partial match) — keep buffering
  if mappings.could_be_mapping(key_buffer, mode) then
    config.debug("Tracker: key buffer could be mapping, waiting: '%s'", key_buffer)
    return
  end

  -- Not a mapping. Replay all pending keys to the parser so that held prefix
  -- keys (e.g. the 'g' in 'ge' when 'gd' is mapped) are fed before the
  -- completion key. This fixes multi-key native sequences like ge/gE/gg.
  local local_pending = pending_keys
  clear_key_buffer()
  for _, k in ipairs(local_pending) do
    local a = parser:feed_key(k, mode)
    if a then
      track_action(a, a)
    end
  end
end

--- vim.on_key() callback
---@param key string Key after mappings
---@param typed string Typed keys before mappings
local function on_key(key, typed)
  if not parser then
    return
  end

  -- Ignore empty typed keys (feedkeys always passes empty typed)
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

  -- Ignore replace mode (R, Rv, Rx) - individual replacement chars are not actions
  if mode == "R" or mode == "Rv" or mode == "Rx" then
    config.debug("Tracker: ignoring replace mode")
    return
  end

  -- Ignore terminal mode
  if mode == "t" then
    config.debug("Tracker: ignoring terminal mode")
    return
  end

  process_key(normalized_typed, mode)
end

--- Augroup name for CmdlineLeave autocmd
local CMDLINE_AUGROUP = "TrackActionCmdline"

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

  -- Track typed ex commands via CmdlineLeave
  vim.api.nvim_create_augroup(CMDLINE_AUGROUP, { clear = true })
  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = CMDLINE_AUGROUP,
    callback = function()
      if vim.v.event.abort then return end
      if vim.fn.getcmdtype() ~= ":" then return end
      local cmd = vim.fn.getcmdline()
      M.track_command(cmd)
    end,
  })

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

  -- Unregister CmdlineLeave autocmd
  pcall(vim.api.nvim_del_augroup_by_name, CMDLINE_AUGROUP)

  -- Clear state
  parser = nil
  key_buffer = ""
  pending_keys = {}

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
---@param loaded_actions table|nil
---@param loaded_metadata table|nil
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

--- Process a pre-normalized key directly, bypassing vim.on_key and mode checks.
--- Intended for unit tests only — call tracker.start() first to initialize the parser.
---@param normalized_typed string Already-normalized key (e.g. "g", "e", "<C-w>")
---@param mode string|nil Vim mode to simulate (defaults to "n")
function M._process_key(normalized_typed, mode)
  if not parser then return end
  process_key(normalized_typed, mode or "n")
end

return M
