-- State machine parser for Vim command sequences
-- Based on Neovim's normal.c command parsing logic

local commands = require("track-action.commands")
local config = require("track-action.config")

local M = {}

--- Parser state machine
---@class Parser
---@field state string Current parser state
---@field count1 number|nil Count before operator
---@field operator string|nil Pending operator
---@field count2 number|nil Count after operator
---@field motion string|nil Motion command
---@field register string|nil Selected register
---@field buffer string Accumulated key buffer
---@field prefix string|nil Prefix character (g, z, etc.)
---@field text_object_prefix string|nil Text object prefix (i, a)
local Parser = {}
Parser.__index = Parser

--- Create a new parser instance
---@return Parser
function Parser:new()
  local parser = setmetatable({
    state = "idle",
    count1 = nil,
    operator = nil,
    count2 = nil,
    motion = nil,
    register = nil,
    buffer = "",
    prefix = nil,
    text_object_prefix = nil,
  }, self)
  return parser
end

--- Feed a single keystroke to the parser
---@param key string The keystroke to process
---@return string|nil Semantic action if command is complete, nil otherwise
function Parser:feed_key(key)
  config.debug("Parser: feed_key(%s) state=%s buffer='%s'", key, self.state, self.buffer)

  -- Handle escape - reset everything
  if key == "<Esc>" or key == "<C-c>" then
    config.debug("Parser: escape detected, resetting")
    self:reset()
    return "escape"
  end

  -- State: waiting for register name
  if self.state == "register" then
    self.register = key
    self.state = "idle"
    config.debug("Parser: register selected: %s", key)
    return nil
  end

  -- State: waiting for character after f, t, F, T, r, m, etc.
  if self.state == "needs_char" then
    self.buffer = self.buffer .. key
    config.debug("Parser: got additional char: %s", key)
    return self:complete_action()
  end

  -- State: waiting for second character of g-prefixed command
  if self.state == "g_prefix" then
    return self:handle_g_prefix(key)
  end

  -- State: waiting for second character of z-prefixed command
  if self.state == "z_prefix" then
    return self:handle_z_prefix(key)
  end

  -- State: text object prefix (i or a)
  if self.state == "text_object" then
    return self:handle_text_object(key)
  end

  -- Handle digit (count accumulation)
  if self:is_count_digit(key) then
    return self:handle_count(key)
  end

  -- Handle register selection (")
  if key == '"' and self.state == "idle" then
    self.state = "register"
    config.debug("Parser: entering register state")
    return nil
  end

  -- Handle operators
  if commands.is_operator(key) then
    return self:handle_operator(key)
  end

  -- Handle prefix keys (g, z)
  if commands.is_prefix(key) then
    return self:handle_prefix(key)
  end

  -- Handle text object prefixes (i, a) when operator is pending
  if (key == "i" or key == "a") and self.operator then
    self.text_object_prefix = key
    self.buffer = self.buffer .. key
    self.state = "text_object"
    config.debug("Parser: entering text_object state with prefix: %s", key)
    return nil
  end

  -- Handle motions
  local motion_name = commands.is_motion(key)
  if motion_name then
    return self:handle_motion(key, motion_name)
  end

  -- Handle standalone commands
  local standalone_name = commands.is_standalone(key)
  if standalone_name then
    return self:handle_standalone(key, standalone_name)
  end

  -- Handle commands that need additional character
  if commands.needs_additional_char(key) then
    self.buffer = self.buffer .. key
    self.state = "needs_char"
    config.debug("Parser: command needs additional char")
    return nil
  end

  -- Unknown key - reset and ignore
  config.debug("Parser: unknown key, resetting")
  self:reset()
  return nil
end

--- Check if a key is a count digit
---@param key string
---@return boolean
function Parser:is_count_digit(key)
  local digit = tonumber(key)
  if not digit then
    return false
  end

  -- '0' is only a count if we already have a count started
  if digit == 0 then
    return (self.state == "count" or self.state == "operator_count")
  end

  return digit >= 1 and digit <= 9
end

--- Handle count accumulation
---@param key string
---@return nil
function Parser:handle_count(key)
  local digit = tonumber(key)

  if self.state == "idle" or self.state == "count" then
    -- Count before operator
    self.count1 = (self.count1 or 0) * 10 + digit
    self.state = "count"
    self.buffer = self.buffer .. key
    config.debug("Parser: count1 = %d", self.count1)
  elseif self.state == "operator" or self.state == "operator_count" then
    -- Count after operator
    self.count2 = (self.count2 or 0) * 10 + digit
    self.state = "operator_count"
    self.buffer = self.buffer .. key
    config.debug("Parser: count2 = %d", self.count2)
  end

  return nil
end

--- Handle operator
---@param key string
---@return string|nil
function Parser:handle_operator(key)
  if self.operator == key then
    -- Doubled operator (dd, yy, cc)
    self.buffer = self.buffer .. key
    config.debug("Parser: doubled operator: %s", key .. key)
    return self:complete_action(key .. key)
  else
    -- New operator
    self.operator = key
    self.buffer = self.buffer .. key
    self.state = "operator"
    config.debug("Parser: operator: %s", key)
    return nil
  end
end

--- Handle prefix keys (g, z)
---@param key string
---@return nil
function Parser:handle_prefix(key)
  self.prefix = key
  self.buffer = self.buffer .. key

  if key == "g" then
    self.state = "g_prefix"
    config.debug("Parser: entering g_prefix state")
  elseif key == "z" then
    self.state = "z_prefix"
    config.debug("Parser: entering z_prefix state")
  end

  return nil
end

--- Handle g-prefixed commands
---@param next_key string
---@return string|nil
function Parser:handle_g_prefix(next_key)
  self.buffer = self.buffer .. next_key

  -- Check if it's a g-operator (gu, gU, gq, etc.)
  local g_operator = commands.get_g_operator(next_key)
  if g_operator and not self.operator then
    self.operator = "g" .. next_key
    self.state = "operator"
    config.debug("Parser: g-operator: %s", self.operator)
    return nil
  end

  -- Check if it's a g-motion (gg, gj, gk, etc.)
  local g_motion = commands.get_g_motion(next_key)
  if g_motion then
    config.debug("Parser: g-motion: %s -> %s", next_key, g_motion)
    return self:complete_action("g" .. next_key)
  end

  -- Check for two-char g sequences
  if next_key == "g" then
    -- gg = goto first line
    return self:complete_action("gg")
  end

  -- Unknown g-command, reset
  config.debug("Parser: unknown g-command: g%s", next_key)
  self:reset()
  return nil
end

--- Handle z-prefixed commands
---@param next_key string
---@return string|nil
function Parser:handle_z_prefix(next_key)
  self.buffer = self.buffer .. next_key

  -- Check for z-operators (zf, zd, etc.)
  if commands.operator_modifiers.z and commands.operator_modifiers.z[next_key] then
    self.operator = "z" .. next_key
    self.state = "operator"
    config.debug("Parser: z-operator: %s", self.operator)
    return nil
  end

  -- Check for standalone z-commands (zo, zc, za, etc.)
  local z_cmd = "z" .. next_key
  if commands.is_standalone(z_cmd) then
    return self:complete_action(z_cmd)
  end

  -- Unknown z-command, reset
  config.debug("Parser: unknown z-command: z%s", next_key)
  self:reset()
  return nil
end

--- Handle text object (after i/a)
---@param obj_key string
---@return string|nil
function Parser:handle_text_object(obj_key)
  local text_obj = commands.get_text_object(self.text_object_prefix, obj_key)
  if text_obj then
    self.buffer = self.buffer .. obj_key
    config.debug("Parser: text object: %s%s -> %s", self.text_object_prefix, obj_key, text_obj)
    return self:complete_action()
  else
    -- Unknown text object, reset
    config.debug("Parser: unknown text object: %s%s", self.text_object_prefix, obj_key)
    self:reset()
    return nil
  end
end

--- Handle motion
---@param key string
---@param motion_name string
---@return string|nil
function Parser:handle_motion(key, motion_name)
  self.motion = key
  self.buffer = self.buffer .. key
  config.debug("Parser: motion: %s -> %s", key, motion_name)
  return self:complete_action()
end

--- Handle standalone command
---@param key string
---@param cmd_name string
---@return string|nil
function Parser:handle_standalone(key, cmd_name)
  self.buffer = self.buffer .. key
  config.debug("Parser: standalone: %s -> %s", key, cmd_name)
  return self:complete_action()
end

--- Complete the current action and return semantic name
---@param explicit_action string|nil Override buffer with explicit action
---@return string Semantic action name
function Parser:complete_action(explicit_action)
  local action = explicit_action or self.buffer

  -- Normalize: strip leading digits (counts)
  local normalized = action:gsub("^%d+", "")

  -- Strip register prefix if present
  normalized = normalized:gsub('^"[a-zA-Z0-9]', "")

  config.debug("Parser: complete_action: buffer='%s' normalized='%s'", action, normalized)

  -- Reset state
  local result = normalized
  self:reset()

  return result
end

--- Reset parser state
function Parser:reset()
  config.debug("Parser: reset")
  self.state = "idle"
  self.count1 = nil
  self.operator = nil
  self.count2 = nil
  self.motion = nil
  self.register = nil
  self.buffer = ""
  self.prefix = nil
  self.text_object_prefix = nil
end

--- Create a new parser instance
---@return Parser
function M.new()
  return Parser:new()
end

return M
