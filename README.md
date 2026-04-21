# 📈 track-action.nvim

A Neovim plugin that tracks your keystrokes and ex commands in real time,
parses them through Vim's command grammar, and emits normalized semantic actions.
See exactly how you use Neovim — which motions, operators, and commands you reach
for most — so you can close the gaps in your muscle memory.

## ✨ Features

- ⌨️ **Real-time tracking** via `vim.on_key()` — zero perceptible overhead
- 🧠 **Grammar-aware parser** — understands `[count][register][operator][count][motion/text-object]` and emits the semantic action, not raw keys
- 🗺️ **Custom mapping resolution** — your `<leader>` bindings are resolved to their canonical names through a cached mapping layer
- 📊 **Live stats window** — a floating panel (bottom-right, which-key style) that updates as you type
- 💾 **Persistent storage** — JSON stats survive restarts, auto-saved on a configurable interval and on exit
- 🔌 **Pluggable API** — register callbacks or listen to `User` autocmds; separate channels for keybind and ex-command actions
- 🧪 **Tested** — 267 specs covering the parser, mapping resolution, and tracker

## ⚡️ Requirements

- Neovim >= 0.9.0

No external dependencies.

## 📦 Installation

Install the plugin with your preferred package manager:

```lua
-- lazy.nvim
{
  "17xande/track-action.nvim",
  event = "VeryLazy",
  opts = {},
}
```

<details><summary>packer.nvim</summary>

```lua
use {
  "17xande/track-action.nvim",
  config = function()
    require("track-action").setup()
  end,
}
```

</details>

## ⚙️ Configuration

**track-action.nvim** comes with the following defaults:

```lua
require("track-action").setup({
  -- start tracking immediately on setup
  enabled = true,

  -- auto-save interval in milliseconds; 0 to disable
  auto_save_interval = 60000,

  -- where stats are persisted
  stats_file = vim.fn.stdpath("data") .. "/track_action_stats.json",

  -- track keystrokes while in insert mode
  track_insert_mode = false,

  -- track keystrokes while in visual mode
  track_visual_mode = true,

  -- actions to silently drop
  exclude_actions = { "<Esc>", "<C-c>" },

  -- resolve custom keybindings to their semantic names
  resolve_mappings = true,

  -- cache mapping lookups for performance
  cache_mappings = true,

  -- verbose debug logging
  debug = false,

  -- write debug output to a file instead of vim.notify (e.g. "/tmp/track-action.log")
  log_file = nil,

  -- keybind to toggle the stats window; set to false to disable
  keybind = "<leader>ta",
})
```

## 🚀 Usage

| Command | Description |
| --- | --- |
| `:TrackActionStart` | Start tracking |
| `:TrackActionStop` | Stop tracking |
| `:TrackActionStats` | Toggle the live stats window |
| `:TrackActionTop [N]` | Print top N actions to the command line (default: 10) |
| `:TrackActionSave` | Manually flush stats to disk |
| `:TrackActionReset` | Reset all statistics (asks for confirmation) |

The stats window floats at the bottom-right of the editor, never steals focus,
and updates in real time after every tracked action. Press `q` or `<Esc>` to close it.

## 🔌 API

### Callback registration

Two separate channels let you subscribe only to what you care about:

```lua
local track_action = require("track-action")

-- fired for normal-mode keybind actions
track_action.on_key_action(function(action, data)
  -- action  "dw", "[count]j", "<C-w>s", "ciw", …
  -- data.count    times this action has been seen
  -- data.total    total actions tracked across all types
  -- data.native   native key equivalent or nil
  -- data.category "key"
end)
track_action.off_key_action(fn)

-- fired for ex commands typed after :
track_action.on_cmd_action(function(action, data)
  -- action  "ex:write", "ex:vsplit", "ex:Lazy", …
  -- data.native   native key equivalent or nil (e.g. "<C-w>v" for :vsplit)
  -- data.category "cmd"
end)
track_action.off_cmd_action(fn)
```

Callbacks fire synchronously inside `vim.on_key()` (pcall-wrapped). For anything
that calls Neovim API functions that cannot run in that context, wrap with `vim.schedule()`.

You can also register directly on the tracker module:

```lua
require("track-action.tracker").on_key_action(fn)
require("track-action.tracker").on_cmd_action(fn)
```

### Autocmds

For loose coupling, listen to `User` autocmds instead:

```lua
-- keybind actions
vim.api.nvim_create_autocmd("User", {
  pattern = "TrackActionKey",
  callback = function(ev)
    local action   = ev.data.action   -- "dw", "[count]j", …
    local count    = ev.data.count    -- times this action has been seen
    local total    = ev.data.total    -- total actions tracked
    local category = ev.data.category -- "key"
  end,
})

-- ex-command actions
vim.api.nvim_create_autocmd("User", {
  pattern = "TrackActionCmd",
  callback = function(ev)
    local action   = ev.data.action   -- "ex:write", "ex:vsplit", …
    local count    = ev.data.count
    local total    = ev.data.total
    local category = ev.data.category -- "cmd"
  end,
})
```

Autocmds fire via `vim.schedule()` after callbacks and are safe for any Neovim API call.

### Querying stats

```lua
local track_action = require("track-action")

-- all stats
-- actions:  { ["j"] = 500, ["dw"] = 42, ["[count]j"] = 120, … }
-- metadata: { first_tracked, last_updated, total_actions, session_start }
local actions, metadata = track_action.get_stats()

-- top N actions sorted by count
-- returns: { { action = "j", count = 500 }, … }
local top = track_action.top(10)
```

### Parser

If you need to parse keys yourself:

```lua
local parser = require("track-action.parser").new()

parser:feed_key("d")   -- nil  (operator pending)
parser:feed_key("i")   -- nil  (text-object prefix)
parser:feed_key("w")   -- "diw"

parser:feed_key("3")   -- nil
parser:feed_key("j")   -- "[count]j"

parser:reset()
```

## 🗂️ Action format

| User types | Action string |
| --- | --- |
| `j` | `j` |
| `5j` | `[count]j` |
| `dd` | `dd` |
| `3dd` | `[count]dd` |
| `dw` | `dw` |
| `d2w` | `[count]dw` |
| `diw` | `diw` |
| `ciw` | `ciw` |
| `fa` | `fa` |
| `dfa` | `dfa` |
| `gg` | `gg` |
| `guw` | `guw` |
| `<C-w>s` | `<C-w>s` |
| `rx` | `rx` |
| `"add` | `dd` |
| `"a3dd` | `[count]dd` |
| `:w<CR>` | `ex:write` |
| `:vsplit<CR>` | `ex:vsplit` |

Counts and registers are always stripped. `[count]` is a literal prefix string,
not the actual number.

## 💾 Storage

Stats are persisted as JSON at `~/.local/share/nvim/track_action_stats.json`:

```json
{
  "version": 1,
  "actions": {
    "j": 8921,
    "k": 7654,
    "w": 1523,
    "dw": 456,
    "dd": 234,
    "ex:write": 89
  },
  "metadata": {
    "first_tracked": 1706356800,
    "last_updated": 1706443200,
    "total_actions": 18877
  }
}
```

## 📄 License

Licensed under the [MIT License](LICENSE).
