-- Command classification tables
-- Based on Neovim's nv_cmds array and normal mode command structure

local M = {}

-- Operators that trigger operator-pending mode
M.operators = {
  d = true,  -- delete
  y = true,  -- yank
  c = true,  -- change
  ["<"] = true,  -- indent left
  [">"] = true,  -- indent right
  ["!"] = true,  -- filter
  ["="] = true,  -- format
  ["~"] = true,  -- swap case (can be motion or operator depending on 'tildeop')
}

-- Prefix commands that change operator behavior
M.operator_modifiers = {
  g = {
    ["~"] = "swap_case",  -- g~ - swap case operator
    u = "lowercase",      -- gu - lowercase operator
    U = "uppercase",      -- gU - uppercase operator
    q = "format",         -- gq - format operator
    w = "format_no_break", -- gw - format without breaking
    ["@"] = "rot13",      -- g@ - call 'operatorfunc'
  },
  z = {
    f = "create_fold",    -- zf - create fold operator
    d = "delete_fold",    -- zd - delete fold operator
    F = "create_fold_recursive",  -- zF
    D = "delete_fold_recursive",  -- zD
  },
}

-- Motions (complete operators or standalone movements)
M.motions = {
  -- Character movements
  h = "left",
  l = "right",

  -- Line movements
  j = "down",
  k = "up",
  ["+"] = "line_down_first_char",
  ["-"] = "line_up_first_char",
  _ = "line_down_first_nonblank",

  -- Word movements
  w = "word_forward",
  W = "WORD_forward",
  b = "word_backward",
  B = "WORD_backward",
  e = "word_end",
  E = "WORD_end",
  ge = "word_end_backward",
  gE = "WORD_end_backward",

  -- Line position
  ["0"] = "line_start",
  ["^"] = "line_first_nonblank",
  ["$"] = "line_end",
  g_ = "line_last_nonblank",

  -- Screen movements
  H = "screen_top",
  M = "screen_middle",
  L = "screen_bottom",

  -- Paragraph/section movements
  ["{"] = "paragraph_backward",
  ["}"] = "paragraph_forward",
  ["("] = "sentence_backward",
  [")"] = "sentence_forward",
  ["[["] = "section_backward",
  ["]]"] = "section_forward",

  -- Jump to line
  G = "goto_line",
  gg = "goto_first_line",

  -- Percentage
  ["%"] = "matching_bracket",

  -- g-prefixed motions
  g = {
    g = "goto_first_line",
    e = "word_end_backward",
    E = "WORD_end_backward",
    j = "display_line_down",
    k = "display_line_up",
    ["0"] = "display_line_start",
    ["^"] = "display_line_first_nonblank",
    ["$"] = "display_line_end",
    m = "display_middle",
  },
}

-- Motions that require an additional character
M.motion_with_char = {
  f = "find_char_forward",       -- f{char}
  F = "find_char_backward",      -- F{char}
  t = "till_char_forward",       -- t{char}
  T = "till_char_backward",      -- T{char}
  [";"] = "repeat_find_forward",
  [","] = "repeat_find_backward",
}

-- Text objects (used with operators: inner/around)
M.text_objects = {
  i = {
    w = "inner_word",
    W = "inner_WORD",
    s = "inner_sentence",
    p = "inner_paragraph",
    ["["] = "inner_bracket",
    ["]"] = "inner_bracket",
    ["("] = "inner_paren",
    [")"] = "inner_paren",
    b = "inner_paren",  -- alias for (
    ["{"] = "inner_brace",
    ["}"] = "inner_brace",
    B = "inner_brace",  -- alias for {
    ["<"] = "inner_angle",
    [">"] = "inner_angle",
    t = "inner_tag",
    ['"'] = "inner_double_quote",
    ["'"] = "inner_single_quote",
    ["`"] = "inner_backtick",
  },
  a = {
    w = "around_word",
    W = "around_WORD",
    s = "around_sentence",
    p = "around_paragraph",
    ["["] = "around_bracket",
    ["]"] = "around_bracket",
    ["("] = "around_paren",
    [")"] = "around_paren",
    b = "around_paren",
    ["{"] = "around_brace",
    ["}"] = "around_brace",
    B = "around_brace",
    ["<"] = "around_angle",
    [">"] = "around_angle",
    t = "around_tag",
    ['"'] = "around_double_quote",
    ["'"] = "around_single_quote",
    ["`"] = "around_backtick",
  },
}

-- Standalone commands (complete on their own)
M.standalone = {
  -- Character operations
  x = "delete_char",
  X = "delete_char_backward",
  s = "substitute_char",
  r = "replace_char",  -- requires additional char

  -- Line operations
  D = "delete_to_eol",
  C = "change_to_eol",
  S = "substitute_line",
  Y = "yank_line",

  -- Insert mode
  i = "insert",
  I = "insert_line_start",
  a = "append",
  A = "append_line_end",
  o = "open_below",
  O = "open_above",

  -- Delete/put
  dd = "delete_line",
  yy = "yank_line",
  cc = "change_line",
  p = "put_after",
  P = "put_before",

  -- Undo/redo
  u = "undo",
  U = "undo_line",
  ["<C-r>"] = "redo",

  -- Repeat/macros
  ["."] = "repeat",
  ["@"] = "execute_macro",  -- requires additional char
  ["@@"] = "repeat_macro",
  q = "record_macro",  -- requires additional char

  -- Case
  ["~"] = "swap_case_char",

  -- Scroll
  ["<C-f>"] = "page_forward",
  ["<C-b>"] = "page_backward",
  ["<C-d>"] = "half_page_down",
  ["<C-u>"] = "half_page_up",
  ["<C-e>"] = "scroll_down",
  ["<C-y>"] = "scroll_up",

  -- Visual mode
  v = "visual_char",
  V = "visual_line",
  ["<C-v>"] = "visual_block",
  gv = "reselect_visual",

  -- Search
  ["*"] = "search_word_forward",
  ["#"] = "search_word_backward",
  n = "search_next",
  N = "search_previous",
  gd = "goto_definition",
  gD = "goto_definition_global",

  -- Marks
  m = "set_mark",  -- requires additional char
  ["'"] = "goto_mark_line",  -- requires additional char
  ["`"] = "goto_mark",  -- requires additional char

  -- Joining
  J = "join_lines",
  gJ = "join_lines_no_space",

  -- Increment/decrement
  ["<C-a>"] = "increment",
  ["<C-x>"] = "decrement",

  -- Indenting (visual mode or motion)
  [">>"] = "indent_line",
  ["<<"] = "unindent_line",

  -- Folding
  zo = "open_fold",
  zc = "close_fold",
  za = "toggle_fold",
  zR = "open_all_folds",
  zM = "close_all_folds",

  -- Window commands (start with <C-w>)
  ["<C-w>"] = "window_prefix",  -- requires additional char

  -- Ex commands
  [":"] = "ex_command",

  -- Escape/cancel
  ["<Esc>"] = "escape",
  ["<C-c>"] = "cancel",
}

-- Commands that need an additional character
M.needs_char = {
  f = true,
  F = true,
  t = true,
  T = true,
  r = true,  -- replace char
  m = true,  -- set mark
  ["'"] = true,  -- goto mark line
  ["`"] = true,  -- goto mark
  ["@"] = true,  -- execute macro
  q = true,  -- record macro (or stop recording)
  ['"'] = true,  -- register selection
}

-- Prefix keys that introduce multi-char sequences
M.prefix_keys = {
  g = true,
  z = true,
  ["<C-w>"] = true,
  ['"'] = "register",
}

--- Check if a key is an operator
---@param key string
---@return boolean
function M.is_operator(key)
  return M.operators[key] == true
end

--- Check if a key is a motion
---@param key string
---@return boolean|string False if not a motion, semantic name if it is
function M.is_motion(key)
  return M.motions[key] or false
end

--- Check if a key is a standalone command
---@param key string
---@return boolean|string False if not standalone, semantic name if it is
function M.is_standalone(key)
  return M.standalone[key] or false
end

--- Check if a command needs an additional character
---@param key string
---@return boolean
function M.needs_additional_char(key)
  return M.needs_char[key] == true
end

--- Check if a key is a prefix key
---@param key string
---@return boolean|string False if not a prefix, type if it is
function M.is_prefix(key)
  return M.prefix_keys[key] or false
end

--- Get semantic name for a text object
---@param prefix string "i" or "a"
---@param obj string The text object character
---@return string|nil Semantic name or nil
function M.get_text_object(prefix, obj)
  if M.text_objects[prefix] then
    return M.text_objects[prefix][obj]
  end
  return nil
end

--- Get semantic name for a g-prefixed motion
---@param next_char string Character after 'g'
---@return string|nil Semantic name or nil
function M.get_g_motion(next_char)
  if M.motions.g and M.motions.g[next_char] then
    return M.motions.g[next_char]
  end
  return nil
end

--- Get semantic name for a g-prefixed operator
---@param next_char string Character after 'g'
---@return string|nil Semantic name or nil
function M.get_g_operator(next_char)
  if M.operator_modifiers.g and M.operator_modifiers.g[next_char] then
    return M.operator_modifiers.g[next_char]
  end
  return nil
end

return M
