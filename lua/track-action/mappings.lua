-- Mapping resolver for hybrid approach
-- Detects and resolves custom user mappings to semantic actions

local commands = require("track-action.commands")
local config = require("track-action.config")

local M = {}

--- Mapping cache
---@type table<string, table>
local mapping_cache = {
  n = {},  -- normal mode
  v = {},  -- visual mode
  _last_refresh = 0,
}

--- Refresh interval in milliseconds
local CACHE_REFRESH_INTERVAL = 5000  -- 5 seconds

--- Refresh mapping cache for a given mode
---@param mode string Mode to refresh ('n', 'v', etc.)
local function refresh_mappings(mode)
  config.debug("Mappings: refreshing cache for mode: %s", mode)

  local mappings = {}

  -- Get global mappings
  local global_maps = vim.api.nvim_get_keymap(mode)
  for _, map in ipairs(global_maps) do
    mappings[map.lhs] = {
      lhs = map.lhs,
      rhs = map.rhs or "",
      desc = map.desc,
      expr = map.expr == 1,
      lua = map.callback ~= nil,
      noremap = map.noremap == 1,
      silent = map.silent == 1,
    }
  end

  -- Get buffer-local mappings (for current buffer)
  local buf_maps = vim.api.nvim_buf_get_keymap(0, mode)
  for _, map in ipairs(buf_maps) do
    -- Buffer-local mappings override global
    mappings[map.lhs] = {
      lhs = map.lhs,
      rhs = map.rhs or "",
      desc = map.desc,
      expr = map.expr == 1,
      lua = map.callback ~= nil,
      noremap = map.noremap == 1,
      silent = map.silent == 1,
      buffer_local = true,
    }
  end

  mapping_cache[mode] = mappings
  mapping_cache._last_refresh = vim.loop.now()

  config.debug("Mappings: cached %d mappings for mode %s", vim.tbl_count(mappings), mode)
end

--- Get mapping for a key sequence in a given mode
---@param sequence string Key sequence to look up
---@param mode string Mode ('n', 'v', etc.)
---@return table|nil Mapping info or nil if not found
function M.get_mapping(sequence, mode)
  mode = mode or "n"

  -- Refresh cache if needed or if mode cache doesn't exist
  if not config.get().cache_mappings or
     not mapping_cache[mode] or
     vim.loop.now() - mapping_cache._last_refresh > CACHE_REFRESH_INTERVAL then
    refresh_mappings(mode)
  end

  -- Double-check cache exists (safety)
  if not mapping_cache[mode] then
    return nil
  end

  return mapping_cache[mode][sequence]
end

--- Check if a key sequence has a mapping
---@param sequence string Key sequence to check
---@param mode string Mode ('n', 'v', etc.)
---@return boolean
function M.has_mapping(sequence, mode)
  return M.get_mapping(sequence, mode) ~= nil
end

--- Resolve a mapping RHS to a semantic action
---@param rhs string Right-hand side of mapping
---@param desc string|nil Optional description
---@param lhs string|nil Left-hand side of mapping
---@return string|nil Semantic action or nil
function M.resolve_rhs(rhs, desc, lhs)
  config.debug("Mappings: resolving RHS: %s (desc: %s, lhs: %s)", rhs or "nil", desc or "none", lhs or "none")

  -- If RHS is empty and LHS is a single character, treat as native command with description
  -- This handles lua/expr mappings that just add descriptions to native keys
  if lhs and rhs == "" and #lhs == 1 then
    config.debug("Mappings: empty RHS for single-char LHS, treating as native command")
    return nil
  end

  -- If RHS is empty, we can't resolve it
  if not rhs or rhs == "" then
    return nil
  end

  -- If RHS equals LHS, this is just a native command with a description (e.g., for which-key)
  -- Return nil to let the parser handle it as a native command
  if lhs and rhs == lhs then
    config.debug("Mappings: RHS equals LHS, treating as native command")
    return nil
  end

  -- Detect common expr mapping pattern: v:count == 0 ? 'g<key>' : '<key>'
  -- This is used in LazyVim to make j/k work better with wrapped lines
  -- Treat as native command since it's just an enhanced version
  if lhs and #lhs == 1 then
    local pattern = "v:count%s*==%s*0%s*%?%s*'g" .. lhs .. "'%s*:%s*'" .. lhs .. "'"
    if rhs:match(pattern) then
      config.debug("Mappings: detected count-based expr mapping, treating as native command")
      return nil
    end
  end

  -- If description is available and descriptive, use it
  if desc and #desc > 0 and #desc < 50 then
    -- Convert description to semantic name
    local semantic = desc:lower():gsub("%s+", "_"):gsub("[^%w_]", "")
    config.debug("Mappings: using description as semantic: %s", semantic)
    return "custom:" .. semantic
  end

  -- Try to parse RHS as a command
  -- Handle <cmd>...<cr> format
  local cmd_match = rhs:match("<[Cc][Mm][Dd]>(.+)<[Cc][Rr]>")
  if cmd_match then
    config.debug("Mappings: found <cmd> format: %s", cmd_match)
    return M.classify_ex_command(cmd_match)
  end

  -- Handle :...<CR> format
  local ex_match = rhs:match("^:(.+)<[Cc][Rr]>")
  if ex_match then
    config.debug("Mappings: found ex command: %s", ex_match)
    return M.classify_ex_command(ex_match)
  end

  -- Check if RHS is a simple vim command sequence we recognize
  if #rhs <= 4 then  -- Short sequences like "dd", "yy", "w", etc.
    -- Strip any leading/trailing special chars
    local clean_rhs = rhs:gsub("^<[^>]+>", ""):gsub("<[^>]+>$", "")

    -- Check if it's a recognized standalone command
    if commands.is_standalone(clean_rhs) then
      config.debug("Mappings: RHS is standalone command: %s", clean_rhs)
      return clean_rhs
    end

    -- Check if it's an operator + motion
    if #clean_rhs == 2 then
      local op = clean_rhs:sub(1, 1)
      local motion = clean_rhs:sub(2, 2)
      if commands.is_operator(op) and commands.is_motion(motion) then
        config.debug("Mappings: RHS is operator+motion: %s", clean_rhs)
        return clean_rhs
      end
    end
  end

  -- Fallback: track as custom mapping with LHS or RHS
  config.debug("Mappings: fallback to custom:rhs")
  return "custom:" .. rhs:sub(1, 20):gsub("[^%w_]", "_")
end

--- Classify an ex command into semantic action
---@param cmd string Ex command without leading ':'
---@return string Semantic action
function M.classify_ex_command(cmd)
  -- Trim whitespace
  cmd = vim.trim(cmd)

  -- Common commands
  local patterns = {
    ["^w%s*$"] = "ex:write",
    ["^w%s+"] = "ex:write",
    ["^write"] = "ex:write",
    ["^q%s*$"] = "ex:quit",
    ["^q!"] = "ex:quit_force",
    ["^quit"] = "ex:quit",
    ["^wq"] = "ex:write_quit",
    ["^x%s*$"] = "ex:write_quit",
    ["^bd"] = "ex:buffer_delete",
    ["^bdelete"] = "ex:buffer_delete",
    ["^bn"] = "ex:buffer_next",
    ["^bp"] = "ex:buffer_previous",
    ["^e%s+"] = "ex:edit",
    ["^edit"] = "ex:edit",
    ["^tabnew"] = "ex:tab_new",
    ["^vs"] = "ex:vsplit",
    ["^sp"] = "ex:split",
    ["^%d+"] = "ex:goto_line",
  }

  for pattern, semantic in pairs(patterns) do
    if cmd:match(pattern) then
      config.debug("Mappings: classified ex command: %s -> %s", cmd, semantic)
      return semantic
    end
  end

  -- Fallback: use command name
  local cmd_name = cmd:match("^(%w+)")
  if cmd_name then
    config.debug("Mappings: ex command fallback: %s", cmd_name)
    return "ex:" .. cmd_name
  end

  return "ex:unknown"
end

--- Check if a partial key sequence could complete to a mapping
---@param partial string Partial key sequence
---@param mode string Mode ('n', 'v', etc.)
---@return boolean True if partial could complete to a mapping
function M.could_be_mapping(partial, mode)
  mode = mode or "n"

  -- Refresh cache if needed or if mode cache doesn't exist
  if not config.get().cache_mappings or
     not mapping_cache[mode] or
     vim.loop.now() - mapping_cache._last_refresh > CACHE_REFRESH_INTERVAL then
    refresh_mappings(mode)
  end

  -- Safety check
  if not mapping_cache[mode] then
    return false
  end

  -- Check if any mapping starts with this partial sequence
  for lhs, map_info in pairs(mapping_cache[mode]) do
    if vim.startswith(lhs, partial) then
      -- Skip mappings that map to themselves (native commands with descriptions)
      -- This includes: rhs == lhs, or empty rhs (lua/expr mappings) with single-char lhs
      local is_self_mapping = (map_info.rhs == lhs) or
                             (map_info.rhs == "" and #lhs == 1)

      -- Also skip count-based expr mappings (v:count == 0 ? 'g<key>' : '<key>')
      if not is_self_mapping and #lhs == 1 then
        local pattern = "v:count%s*==%s*0%s*%?%s*'g" .. lhs .. "'%s*:%s*'" .. lhs .. "'"
        if map_info.rhs:match(pattern) then
          is_self_mapping = true
        end
      end

      if is_self_mapping then
        config.debug("Mappings: skipping self-mapping: %s (rhs='%s')", lhs, map_info.rhs)
      else
        config.debug("Mappings: partial '%s' could complete to: %s", partial, lhs)
        return true
      end
    end
  end

  return false
end

--- Force refresh of mapping cache
function M.refresh_cache()
  for mode in string.gmatch("nv", ".") do
    refresh_mappings(mode)
  end
end

--- Initialize mapping cache
function M.init()
  config.debug("Mappings: initializing")
  M.refresh_cache()

  -- Refresh cache when new mappings might be added
  vim.api.nvim_create_autocmd({ "VimEnter", "BufEnter" }, {
    group = vim.api.nvim_create_augroup("TrackActionMappings", { clear = true }),
    callback = function()
      if config.get().cache_mappings then
        M.refresh_cache()
      end
    end,
  })
end

return M
