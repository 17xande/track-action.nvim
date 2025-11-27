-- Storage and persistence for action statistics

local config = require("track-action.config")

local M = {}

--- Save statistics to file
---@param actions table Actions table
---@param metadata table Metadata table
---@return boolean Success
function M.save(actions, metadata)
  local opts = config.get()
  local file_path = opts.stats_file

  config.debug("Storage: saving to: %s", file_path)

  -- Ensure directory exists
  local dir = vim.fn.fnamemodify(file_path, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    config.debug("Storage: creating directory: %s", dir)
    vim.fn.mkdir(dir, "p")
  end

  -- Prepare data
  local data = {
    version = 1,
    actions = actions,
    metadata = metadata,
  }

  -- Encode as JSON
  local ok, json = pcall(vim.json.encode, data)
  if not ok then
    vim.notify("track-action.nvim: Failed to encode stats: " .. tostring(json), vim.log.levels.ERROR)
    return false
  end

  -- Write to temporary file first (atomic write)
  local temp_file = file_path .. ".tmp"
  local file, err = io.open(temp_file, "w")
  if not file then
    vim.notify("track-action.nvim: Failed to open file for writing: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end

  file:write(json)
  file:close()

  -- Rename temporary file to actual file (atomic on POSIX systems)
  local rename_ok, rename_err = os.rename(temp_file, file_path)
  if not rename_ok then
    vim.notify("track-action.nvim: Failed to save stats file: " .. tostring(rename_err), vim.log.levels.ERROR)
    -- Clean up temp file
    os.remove(temp_file)
    return false
  end

  config.debug("Storage: saved %d actions", vim.tbl_count(actions))
  return true
end

--- Load statistics from file
---@return table|nil, table|nil Actions table and metadata table, or nil on error
function M.load()
  local opts = config.get()
  local file_path = opts.stats_file

  config.debug("Storage: loading from: %s", file_path)

  -- Check if file exists
  if vim.fn.filereadable(file_path) == 0 then
    config.debug("Storage: file does not exist, starting fresh")
    return {}, {}
  end

  -- Read file
  local file, err = io.open(file_path, "r")
  if not file then
    vim.notify("track-action.nvim: Failed to open stats file: " .. tostring(err), vim.log.levels.WARN)
    return {}, {}
  end

  local content = file:read("*all")
  file:close()

  -- Parse JSON
  local ok, data = pcall(vim.json.decode, content)
  if not ok then
    vim.notify("track-action.nvim: Failed to parse stats file (corrupted?): " .. tostring(data), vim.log.levels.WARN)
    -- Backup corrupted file
    local backup = file_path .. ".backup." .. os.time()
    os.rename(file_path, backup)
    vim.notify("track-action.nvim: Corrupted file backed up to: " .. backup, vim.log.levels.INFO)
    return {}, {}
  end

  -- Validate data structure
  if type(data) ~= "table" then
    vim.notify("track-action.nvim: Invalid stats file format", vim.log.levels.WARN)
    return {}, {}
  end

  local actions = data.actions or {}
  local metadata = data.metadata or {}

  config.debug("Storage: loaded %d actions", vim.tbl_count(actions))
  return actions, metadata
end

--- Merge loaded statistics with current session
---@param current_actions table Current actions
---@param current_metadata table Current metadata
---@param loaded_actions table Loaded actions
---@param loaded_metadata table Loaded metadata
---@return table, table Merged actions and metadata
function M.merge(current_actions, current_metadata, loaded_actions, loaded_metadata)
  config.debug("Storage: merging stats")

  -- Merge actions (additive)
  local merged_actions = vim.deepcopy(loaded_actions)
  for action, count in pairs(current_actions) do
    merged_actions[action] = (merged_actions[action] or 0) + count
  end

  -- Merge metadata
  local merged_metadata = vim.tbl_extend("force", loaded_metadata, {
    last_updated = current_metadata.last_updated or os.time(),
    session_start = current_metadata.session_start,
  })

  -- Use earliest first_tracked
  if current_metadata.first_tracked then
    if not merged_metadata.first_tracked or
       current_metadata.first_tracked < merged_metadata.first_tracked then
      merged_metadata.first_tracked = current_metadata.first_tracked
    end
  end

  -- Recalculate total
  merged_metadata.total_actions = 0
  for _, count in pairs(merged_actions) do
    merged_metadata.total_actions = merged_metadata.total_actions + count
  end

  config.debug("Storage: merged %d total actions", merged_metadata.total_actions)
  return merged_actions, merged_metadata
end

return M
