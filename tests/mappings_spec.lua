-- Mappings resolver spec
-- Run: nvim --headless -u tests/minimal_init.lua -c "luafile tests/mappings_spec.lua"

package.path = "tests/?.lua;" .. package.path
local h = require("harness")
local describe, it, eq, is_nil = h.describe, h.it, h.eq, h.is_nil

require("track-action.config").setup({})
local mappings = require("track-action.mappings")

-- =========================================================================
-- resolve_rhs: the function that turns a mapping into a tracked action name
-- =========================================================================

describe("resolve_rhs", function()
  describe("native command pass-through", function()
    it("empty rhs + single-char lhs returns nil (let parser handle)", function()
      is_nil(mappings.resolve_rhs("", nil, "j"))
    end)

    it("rhs == lhs returns nil", function()
      is_nil(mappings.resolve_rhs("j", nil, "j"))
    end)

    it("lazyvim count expr mapping returns nil", function()
      is_nil(mappings.resolve_rhs("v:count == 0 ? 'gj' : 'j'", nil, "j"))
    end)
  end)

  describe("ex commands", function()
    for _, c in ipairs({
      { "<cmd>w<cr>",        "ex:write"         },
      { "<cmd>q<cr>",        "ex:quit"          },
      { "<cmd>wq<cr>",       "ex:write_quit"    },
      { "<cmd>bd<cr>",       "ex:buffer_delete"  },
      { "<Cmd>bn<CR>",       "ex:buffer_next"   },
      { "<cmd>bp<cr>",       "ex:buffer_previous" },
      { "<cmd>vs<cr>",       "ex:vsplit"        },
      { "<cmd>sp<cr>",       "ex:split"         },
      { ":w<CR>",            "ex:write"         },
      { ":q<CR>",            "ex:quit"          },
    }) do
      local rhs, expected = c[1], c[2]
      it(rhs .. " -> " .. expected, function()
        eq(expected, mappings.resolve_rhs(rhs, nil, nil))
      end)
    end
  end)

  describe("short vim command sequences", function()
    it("dd recognized as standalone", function()
      eq("dd", mappings.resolve_rhs("dd", nil, nil))
    end)

    it("dw recognized as operator+motion", function()
      eq("dw", mappings.resolve_rhs("dw", nil, nil))
    end)
  end)

  describe("custom keybinds show lhs keys", function()
    it("mapping with description uses lhs, not custom:desc", function()
      local result = mappings.resolve_rhs("<cmd>vsplit<cr>", "Vertical Split", "<leader>sv")
      eq("ex:vsplit", result)
    end)

    it("lua callback mapping (empty rhs, multi-char lhs) with desc uses lhs", function()
      -- Lua mappings have empty rhs but a description. Multi-char lhs means
      -- it's not a native single-key command.
      local result = mappings.resolve_rhs("", "Do Something", "<leader>ds")
      eq("<leader>ds", result)
    end)

    it("lua callback mapping without desc uses lhs", function()
      local result = mappings.resolve_rhs("", nil, "<leader>ds")
      eq("<leader>ds", result)
    end)

    it("unrecognized rhs uses lhs", function()
      local result = mappings.resolve_rhs("some_complex_thing()", nil, "<leader>x")
      eq("<leader>x", result)
    end)

    it("unrecognized rhs with desc still uses lhs when rhs isn't classifiable", function()
      local result = mappings.resolve_rhs("some_complex_thing()", "Do Stuff", "<leader>x")
      eq("<leader>x", result)
    end)

    it("long description does not become custom:long_name", function()
      local result = mappings.resolve_rhs("", "Toggle the file explorer panel", "<leader>e")
      eq("<leader>e", result)
    end)

    it("plugin command via <cmd> still classifies as ex:", function()
      -- Even with a desc, if the rhs is a classifiable ex command, use that
      local result = mappings.resolve_rhs("<cmd>Lazy<cr>", "Open Lazy", "<leader>l")
      eq("ex:Lazy", result)
    end)
  end)

  describe("leader normalization", function()
    local saved_leader

    local function set_leader(key)
      saved_leader = vim.g.mapleader
      vim.g.mapleader = key
    end

    local function restore_leader()
      vim.g.mapleader = saved_leader
    end

    it("space prefix in lhs is normalized to <leader>", function()
      set_leader(" ")
      local result = mappings.resolve_rhs("", "Vertical Split", " sv")
      restore_leader()
      eq("<leader>sv", result)
    end)

    it("space prefix in lhs fallback for unresolvable rhs", function()
      set_leader(" ")
      local result = mappings.resolve_rhs("some_lua_func()", nil, " x")
      restore_leader()
      eq("<leader>x", result)
    end)

    it("space pipe: ' |' becomes <leader>|", function()
      set_leader(" ")
      local result = mappings.resolve_rhs("<cmd>vsplit<cr>", "Split Vertical", " |")
      restore_leader()
      -- rhs classifies as ex:vsplit, so lhs normalization doesn't apply here
      eq("ex:vsplit", result)
    end)

    it("non-leader space is not normalized", function()
      set_leader(" ")
      -- A mapping on literal space itself (single char) returns nil (native pass-through)
      is_nil(mappings.resolve_rhs("", nil, " "))
      restore_leader()
    end)

    it("works with non-space leader like comma", function()
      set_leader(",")
      local result = mappings.resolve_rhs("", "Find Files", ",ff")
      restore_leader()
      eq("<leader>ff", result)
    end)
  end)
end)

-- =========================================================================
-- resolve_rhs: native equivalent (second return value)
-- =========================================================================

describe("resolve_rhs native equivalent", function()
  describe("ex commands return native equivalent when known", function()
    for _, c in ipairs({
      { "<cmd>vs<cr>",       " |",  "<C-w>v" },
      { "<cmd>vsplit<cr>",   " |",  "<C-w>v" },
      { "<cmd>sp<cr>",       " -",  "<C-w>s" },
      { "<cmd>split<cr>",    " -",  "<C-w>s" },
      { "<cmd>wincmd h<cr>", " h",  "<C-w>h" },
      { "<cmd>wincmd j<cr>", " j",  "<C-w>j" },
      { "<cmd>wincmd k<cr>", " k",  "<C-w>k" },
      { "<cmd>wincmd l<cr>", " l",  "<C-w>l" },
      { "<cmd>wincmd w<cr>", " w",  "<C-w>w" },
    }) do
      local rhs, lhs, expected_native = c[1], c[2], c[3]
      it(rhs .. " -> native " .. expected_native, function()
        local _, native = mappings.resolve_rhs(rhs, nil, lhs)
        eq(expected_native, native)
      end)
    end
  end)

  describe("ex commands without native equivalent return nil", function()
    for _, c in ipairs({
      { "<cmd>w<cr>",  " w"  },
      { "<cmd>q<cr>",  " q"  },
      { "<cmd>bd<cr>", " bd" },
      { "<cmd>Lazy<cr>", " l" },
    }) do
      local rhs, lhs = c[1], c[2]
      it(rhs .. " -> native nil", function()
        local _, native = mappings.resolve_rhs(rhs, nil, lhs)
        is_nil(native)
      end)
    end
  end)

  describe("native commands pass through with native = nil", function()
    it("native single-char returns nil, nil", function()
      local action, native = mappings.resolve_rhs("", nil, "j")
      is_nil(action)
      is_nil(native)
    end)

    it("rhs == lhs returns nil, nil", function()
      local action, native = mappings.resolve_rhs("j", nil, "j")
      is_nil(action)
      is_nil(native)
    end)
  end)

  describe("short vim commands have native = rhs", function()
    it("standalone dd", function()
      local action, native = mappings.resolve_rhs("dd", nil, "<leader>x")
      eq("dd", native)
    end)

    it("operator+motion dw", function()
      local action, native = mappings.resolve_rhs("dw", nil, "<leader>x")
      eq("dw", native)
    end)
  end)

  describe("parser-handled actions: native is the action itself", function()
    it("fallback mapping has no native", function()
      local _, native = mappings.resolve_rhs("some_complex_thing()", nil, "<leader>x")
      is_nil(native)
    end)
  end)
end)

-- =========================================================================
-- ex_to_native table in commands module
-- =========================================================================

local commands = require("track-action.commands")

describe("ex_to_native", function()
  it("has entries for vsplit variants", function()
    eq("<C-w>v", commands.ex_to_native["vsplit"])
    eq("<C-w>v", commands.ex_to_native["vs"])
  end)

  it("has entries for split variants", function()
    eq("<C-w>s", commands.ex_to_native["split"])
    eq("<C-w>s", commands.ex_to_native["sp"])
  end)

  it("has entries for wincmd motions", function()
    eq("<C-w>h", commands.ex_to_native["wincmd h"])
    eq("<C-w>j", commands.ex_to_native["wincmd j"])
    eq("<C-w>k", commands.ex_to_native["wincmd k"])
    eq("<C-w>l", commands.ex_to_native["wincmd l"])
    eq("<C-w>w", commands.ex_to_native["wincmd w"])
  end)

  it("returns nil for commands without native equivalent", function()
    is_nil(commands.ex_to_native["write"])
    is_nil(commands.ex_to_native["quit"])
  end)
end)

-- =========================================================================
h.summary()
