-- Parser spec
-- Run: nvim --headless -u tests/minimal_init.lua -c "luafile tests/parser_spec.lua"

package.path = "tests/?.lua;" .. package.path
local h = require("harness")
local describe, it, eq, is_nil = h.describe, h.it, h.eq, h.is_nil

require("track-action.config").setup({})
local parser_mod = require("track-action.parser")

--- Feed a list of keys to a fresh parser, return the last non-nil action.
--- Keys can be single chars or special-key strings like "<C-w>".
---@param keys string[]
---@return string|nil
local function parse(keys)
  local p = parser_mod.new()
  local action
  for _, key in ipairs(keys) do
    local result = p:feed_key(key)
    if result then action = result end
  end
  return action
end

--- Split a simple string into single-char key list.
--- For sequences containing special keys, use parse() directly.
---@param str string
---@return string[]
local function keys(str)
  local t = {}
  for c in str:gmatch(".") do
    t[#t + 1] = c
  end
  return t
end

-- =========================================================================
-- Motions
-- =========================================================================
describe("motions", function()
  for _, c in ipairs({
    -- basic
    { keys("h"),  "h"  },
    { keys("j"),  "j"  },
    { keys("k"),  "k"  },
    { keys("l"),  "l"  },
    -- word
    { keys("w"),  "w"  },
    { keys("W"),  "W"  },
    { keys("b"),  "b"  },
    { keys("B"),  "B"  },
    { keys("e"),  "e"  },
    { keys("E"),  "E"  },
    -- line position
    { keys("0"),  "0"  },
    { keys("^"),  "^"  },
    { keys("$"),  "$"  },
    -- screen
    { keys("H"),  "H"  },
    { keys("M"),  "M"  },
    { keys("L"),  "L"  },
    -- paragraph / sentence
    { keys("{"),  "{"  },
    { keys("}"),  "}"  },
    { keys("("),  "("  },
    { keys(")"),  ")"  },
    -- goto
    { keys("G"),  "G"  },
    { keys("gg"), "gg" },
    -- misc
    { keys("%"),  "%"  },
  }) do
    local input, expected = c[1], c[2]
    it(expected, function()
      eq(expected, parse(input))
    end)
  end
end)

-- =========================================================================
-- Motions with [count]
-- =========================================================================
describe("motions with [count]", function()
  for _, c in ipairs({
    { keys("5j"),   "[count]j"  },
    { keys("3w"),   "[count]w"  },
    { keys("10G"),  "[count]G"  },
    { keys("25j"),  "[count]j"  },
    { keys("2b"),   "[count]b"  },
    { keys("5gg"),  "[count]gg" },
  }) do
    local input, expected = c[1], c[2]
    it(table.concat(input) .. " -> " .. expected, function()
      eq(expected, parse(input))
    end)
  end
end)

-- =========================================================================
-- Operators (doubled, line-wise)
-- =========================================================================
describe("doubled operators", function()
  for _, c in ipairs({
    { keys("dd"), "dd" },
    { keys("yy"), "yy" },
    { keys("cc"), "cc" },
    { keys(">>"), ">>" },
    { keys("<<"), "<<" },
  }) do
    local input, expected = c[1], c[2]
    it(expected, function()
      eq(expected, parse(input))
    end)
  end

  describe("with [count]", function()
    for _, c in ipairs({
      { keys("3dd"), "[count]dd" },
      { keys("5yy"), "[count]yy" },
      { keys("2cc"), "[count]cc" },
      { keys("4>>"), "[count]>>" },
    }) do
      local input, expected = c[1], c[2]
      it(table.concat(input) .. " -> " .. expected, function()
        eq(expected, parse(input))
      end)
    end
  end)
end)

-- =========================================================================
-- Operator + motion
-- =========================================================================
describe("operator + motion", function()
  for _, c in ipairs({
    { keys("dw"),  "dw"  },
    { keys("yw"),  "yw"  },
    { keys("cw"),  "cw"  },
    { keys("dj"),  "dj"  },
    { keys("yG"),  "yG"  },
    { keys("d$"),  "d$"  },
    { keys("d0"),  "d0"  },
    { keys("cb"),  "cb"  },
    { keys("d}"),  "d}"  },
    { keys(">j"),  ">j"  },
    { keys("<k"),  "<k"  },
    { keys("=j"),  "=j"  },
  }) do
    local input, expected = c[1], c[2]
    it(expected, function()
      eq(expected, parse(input))
    end)
  end

  describe("with [count] before operator", function()
    for _, c in ipairs({
      { keys("2dw"), "[count]dw" },
      { keys("3yj"), "[count]yj" },
    }) do
      local input, expected = c[1], c[2]
      it(table.concat(input) .. " -> " .. expected, function()
        eq(expected, parse(input))
      end)
    end
  end)

  describe("with [count] after operator", function()
    for _, c in ipairs({
      { keys("d2w"),  "[count]dw" },
      { keys("y3j"),  "[count]yj" },
    }) do
      local input, expected = c[1], c[2]
      it(table.concat(input) .. " -> " .. expected, function()
        eq(expected, parse(input))
      end)
    end
  end)

  describe("with [count] in both positions", function()
    it("2d3w -> [count]dw", function()
      eq("[count]dw", parse(keys("2d3w")))
    end)
  end)
end)

-- =========================================================================
-- Operator + f/F/t/T (needs_char motions)
-- =========================================================================
describe("operator + find/till", function()
  for _, c in ipairs({
    { keys("dfa"), "dfa" },
    { keys("dFx"), "dFx" },
    { keys("ct;"), "ct;" },
    { keys("yTa"), "yTa" },
  }) do
    local input, expected = c[1], c[2]
    it(expected, function()
      eq(expected, parse(input))
    end)
  end

  it("3dfa -> [count]dfa", function()
    eq("[count]dfa", parse(keys("3dfa")))
  end)
end)

-- =========================================================================
-- Text objects
-- =========================================================================
describe("text objects", function()
  for _, c in ipairs({
    -- inner
    { keys("diw"), "diw" },
    { keys("ciw"), "ciw" },
    { keys("yiw"), "yiw" },
    { keys("dis"), "dis" },
    { keys("dip"), "dip" },
    -- around
    { keys("daw"), "daw" },
    { keys("cas"), "cas" },
    { keys("yap"), "yap" },
    -- bracket/paren/brace pairs
    { "di(", keys("di(") },
    { "da[", keys("da[") },
    { "ci{", keys("ci{") },
    -- quote pairs
    { 'di"', keys('di"') },
    { "ci'", keys("ci'") },
    { "di`", keys("di`") },
    -- tag
    { "dit", keys("dit") },
    { "dat", keys("dat") },
  }) do
    local expected, input
    if type(c[1]) == "string" and type(c[2]) == "table" then
      expected, input = c[1], c[2]
    else
      input, expected = c[1], c[2]
    end
    it(expected, function()
      eq(expected, parse(input))
    end)
  end

  it("2diw -> [count]diw", function()
    eq("[count]diw", parse(keys("2diw")))
  end)
end)

-- =========================================================================
-- Standalone commands
-- =========================================================================
describe("standalone commands", function()
  for _, c in ipairs({
    -- char ops
    { keys("x"), "x" },
    { keys("X"), "X" },
    { keys("s"), "s" },
    -- line ops
    { keys("D"), "D" },
    { keys("C"), "C" },
    { keys("S"), "S" },
    { keys("Y"), "Y" },
    -- insert
    { keys("i"), "i" },
    { keys("I"), "I" },
    { keys("a"), "a" },
    { keys("A"), "A" },
    { keys("o"), "o" },
    { keys("O"), "O" },
    -- put
    { keys("p"), "p" },
    { keys("P"), "P" },
    -- undo/redo
    { keys("u"), "u" },
    -- repeat
    { keys("."), "." },
    -- search
    { keys("n"), "n" },
    { keys("N"), "N" },
    { keys("*"), "*" },
    { keys("#"), "#" },
    -- join
    { keys("J"), "J" },
    -- visual
    { keys("v"), "v" },
    { keys("V"), "V" },
  }) do
    local input, expected = c[1], c[2]
    it(expected, function()
      eq(expected, parse(input))
    end)
  end

  describe("ctrl standalones", function()
    for _, c in ipairs({
      { { "<C-r>" }, "<C-r>" },
      { { "<C-f>" }, "<C-f>" },
      { { "<C-b>" }, "<C-b>" },
      { { "<C-d>" }, "<C-d>" },
      { { "<C-u>" }, "<C-u>" },
      { { "<C-o>" }, "<C-o>" },
      { { "<C-a>" }, "<C-a>" },
      { { "<C-x>" }, "<C-x>" },
    }) do
      local input, expected = c[1], c[2]
      it(expected, function()
        eq(expected, parse(input))
      end)
    end
  end)

  describe("with [count]", function()
    for _, c in ipairs({
      { keys("3x"),  "[count]x"  },
      { keys("5p"),  "[count]p"  },
      { keys("2J"),  "[count]J"  },
      { keys("3u"),  "[count]u"  },
    }) do
      local input, expected = c[1], c[2]
      it(table.concat(input) .. " -> " .. expected, function()
        eq(expected, parse(input))
      end)
    end
  end)
end)

-- =========================================================================
-- needs_char commands (f/F/t/T, r, m, marks, macros)
-- =========================================================================
describe("needs_char commands", function()
  for _, c in ipairs({
    -- find/till
    { keys("fa"), "fa" },
    { keys("Fz"), "Fz" },
    { keys("ta"), "ta" },
    { keys("T."), "T." },
    -- replace
    { keys("rx"), "rx" },
    { keys("rA"), "rA" },
    -- marks
    { keys("ma"), "ma" },
    { keys("'a"), "'a" },
    { keys("`z"), "`z" },
    -- macros
    { keys("qa"), "qa" },
    { keys("@a"), "@a" },
  }) do
    local input, expected = c[1], c[2]
    it(expected, function()
      eq(expected, parse(input))
    end)
  end

  describe("repeat find", function()
    it(";", function() eq(";", parse(keys(";"))) end)
    it(",", function() eq(",", parse(keys(","))) end)
  end)

  describe("with [count]", function()
    for _, c in ipairs({
      { keys("3fa"), "[count]fa" },
      { keys("2rx"), "[count]rx" },
    }) do
      local input, expected = c[1], c[2]
      it(table.concat(input) .. " -> " .. expected, function()
        eq(expected, parse(input))
      end)
    end
  end)
end)

-- =========================================================================
-- g-prefix
-- =========================================================================
describe("g-prefix", function()
  describe("motions", function()
    for _, c in ipairs({
      { keys("gg"), "gg" },
      { keys("gj"), "gj" },
      { keys("gk"), "gk" },
      { keys("ge"), "ge" },
      { keys("gE"), "gE" },
    }) do
      local input, expected = c[1], c[2]
      it(expected, function()
        eq(expected, parse(input))
      end)
    end
  end)

  describe("operators + motion", function()
    for _, c in ipairs({
      { keys("guw"), "guw" },
      { keys("gUw"), "gUw" },
      { keys("gqj"), "gqj" },
    }) do
      local input, expected = c[1], c[2]
      it(expected, function()
        eq(expected, parse(input))
      end)
    end
  end)

  describe("operator + text object", function()
    it("guiw", function()
      eq("guiw", parse(keys("guiw")))
    end)
  end)

  describe("with [count]", function()
    it("5gg -> [count]gg", function()
      eq("[count]gg", parse(keys("5gg")))
    end)
    it("3gj -> [count]gj", function()
      eq("[count]gj", parse(keys("3gj")))
    end)
  end)
end)

-- =========================================================================
-- z-prefix
-- =========================================================================
describe("z-prefix", function()
  describe("standalone", function()
    for _, c in ipairs({
      { keys("zo"), "zo" },
      { keys("zc"), "zc" },
      { keys("za"), "za" },
      { keys("zR"), "zR" },
      { keys("zM"), "zM" },
    }) do
      local input, expected = c[1], c[2]
      it(expected, function()
        eq(expected, parse(input))
      end)
    end
  end)

  describe("fold operator + motion", function()
    it("zfj", function()
      eq("zfj", parse(keys("zfj")))
    end)
  end)
end)

-- =========================================================================
-- <C-w> window commands
-- =========================================================================
describe("<C-w> window commands", function()
  for _, c in ipairs({
    { { "<C-w>", "j" }, "<C-w>j" },
    { { "<C-w>", "k" }, "<C-w>k" },
    { { "<C-w>", "h" }, "<C-w>h" },
    { { "<C-w>", "l" }, "<C-w>l" },
    { { "<C-w>", "s" }, "<C-w>s" },
    { { "<C-w>", "v" }, "<C-w>v" },
    { { "<C-w>", "c" }, "<C-w>c" },
    { { "<C-w>", "o" }, "<C-w>o" },
    { { "<C-w>", "w" }, "<C-w>w" },
    { { "<C-w>", "q" }, "<C-w>q" },
    { { "<C-w>", "T" }, "<C-w>T" },
    { { "<C-w>", "r" }, "<C-w>r" },
    { { "<C-w>", "x" }, "<C-w>x" },
    { { "<C-w>", "=" }, "<C-w>=" },
  }) do
    local input, expected = c[1], c[2]
    it(expected, function()
      eq(expected, parse(input))
    end)
  end

  it("3<C-w>j -> [count]<C-w>j", function()
    eq("[count]<C-w>j", parse({ "3", "<C-w>", "j" }))
  end)
end)

-- =========================================================================
-- Register prefix
-- =========================================================================
describe("register prefix", function()
  it('"add -> dd', function()
    eq("dd", parse({ '"', "a", "d", "d" }))
  end)
  it('"ayy -> yy', function()
    eq("yy", parse({ '"', "a", "y", "y" }))
  end)
  it('"adw -> dw', function()
    eq("dw", parse({ '"', "a", "d", "w" }))
  end)
  it('"a3dd -> [count]dd', function()
    eq("[count]dd", parse({ '"', "a", "3", "d", "d" }))
  end)
end)

-- =========================================================================
-- Visual mode
-- =========================================================================
describe("visual mode", function()
  local function parse_visual(input, visual_mode)
    visual_mode = visual_mode or "v"
    local p = parser_mod.new()
    local action
    for _, key in ipairs(input) do
      action = p:feed_key(key, visual_mode)
    end
    return action
  end

  describe("operators complete immediately", function()
    for _, c in ipairs({
      { { "d" }, "v",    "d"  },
      { { "y" }, "v",    "y"  },
      { { "c" }, "v",    "c"  },
      { { ">" }, "v",    ">"  },
      { { "<" }, "v",    "<"  },
      { { "d" }, "V",    "d"  },
      { { "d" }, "\22",  "d"  },  -- <C-v> visual block
    }) do
      local input, mode, expected = c[1], c[2], c[3]
      it(expected .. " (mode=" .. vim.inspect(mode) .. ")", function()
        eq(expected, parse_visual(input, mode))
      end)
    end
  end)

  it("2d -> [count]d", function()
    eq("[count]d", parse_visual({ "2", "d" }))
  end)
end)

-- =========================================================================
-- Escape / cancel
-- =========================================================================
describe("escape and cancel", function()
  it("<Esc> returns escape", function()
    eq("escape", parse({ "<Esc>" }))
  end)

  it("<C-c> returns escape", function()
    eq("escape", parse({ "<C-c>" }))
  end)

  it("<Esc> mid-operator resets, next key starts fresh", function()
    local p = parser_mod.new()
    p:feed_key("d")
    eq("escape", p:feed_key("<Esc>"))
    eq("w", p:feed_key("w"))
  end)

  it("<Esc> mid-count resets", function()
    local p = parser_mod.new()
    p:feed_key("3")
    eq("escape", p:feed_key("<Esc>"))
    eq("j", p:feed_key("j"))
  end)
end)

-- =========================================================================
-- Edge cases
-- =========================================================================
describe("edge cases", function()
  it("0 at start is motion (line_start), not count", function()
    eq("0", parse(keys("0")))
  end)

  it("10 is count (0 after 1)", function()
    eq("[count]j", parse(keys("10j")))
  end)

  it("d0 -> delete to line start", function()
    eq("d0", parse(keys("d0")))
  end)

  it("unknown key resets parser", function()
    local p = parser_mod.new()
    -- Z (capital) is not a recognized standalone or prefix
    is_nil(p:feed_key("Z"))
    -- parser should be reset, next key works normally
    eq("j", p:feed_key("j"))
  end)

  it("multiple actions on same parser instance", function()
    local p = parser_mod.new()
    eq("j", p:feed_key("j"))
    eq("w", p:feed_key("w"))
    eq("dd", (function()
      p:feed_key("d")
      return p:feed_key("d")
    end)())
    eq("[count]k", (function()
      p:feed_key("5")
      return p:feed_key("k")
    end)())
  end)

  it("operator then escape then new action", function()
    local p = parser_mod.new()
    p:feed_key("c")
    p:feed_key("<Esc>")
    eq("w", p:feed_key("w"))
  end)
end)

-- =========================================================================
h.summary()
