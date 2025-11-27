# track-action.nvim

A Neovim plugin that tracks and analyzes your Vim actions to help you understand your usage patterns and improve your proficiency.

## Features

- 📊 **Action Tracking**: Tracks all your Vim normal mode actions (motions, operators, commands)
- 🔍 **Smart Parsing**: Uses a state machine based on Neovim's internal parser
- 🗺️ **Custom Mapping Support**: Resolves custom keymappings to semantic actions (hybrid approach)
- 💾 **Persistent Storage**: Saves statistics across sessions
- ⚡ **Performance**: Efficient caching and async I/O
- 🎯 **LazyVim Compatible**: Works seamlessly with LazyVim and its custom mappings

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim) (LazyVim)

```lua
-- In ~/.config/nvim/lua/plugins/track_action.lua
return {
  "yourusername/track-action.nvim",
  event = "VeryLazy",
  opts = {
    auto_save_interval = 60000,  -- Auto-save every 60 seconds
    resolve_mappings = true,     -- Resolve custom mappings
  },
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "yourusername/track-action.nvim",
  config = function()
    require("track-action").setup({
      auto_save_interval = 60000,
    })
  end
}
```

## Configuration

Default configuration:

```lua
require("track-action").setup({
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

  -- Debug mode (verbose logging)
  debug = false,

  -- Keybind to show stats window (set to false to disable)
  keybind = "<leader>ta",
})
```

## Keybinds

By default, the plugin sets up the following keybind:

- `<leader>ta` - Toggle live statistics window

The stats window:
- 📍 **Floats on the right side** of the screen (non-intrusive)
- 🔄 **Updates live** as you use Vim (real-time tracking)
- 👻 **Doesn't steal focus** - keeps you in your current buffer
- 📊 Shows **top 20 actions** sorted by count
- 🎯 **Minimal design** - just action names and counts

You can customize or disable the keybind in your configuration:

```lua
require("track-action").setup({
  keybind = "<leader>s",  -- Change to your preferred keybind
  -- or
  keybind = false,        -- Disable the keybind
})
```

## Commands

- `:TrackActionStart` - Start tracking actions
- `:TrackActionStop` - Stop tracking actions
- `:TrackActionSave` - Manually save statistics to file
- `:TrackActionStats` - Toggle the live statistics window
- `:TrackActionReset` - Reset all statistics (with confirmation)
- `:TrackActionTop [N]` - Show top N actions (default: 10)

## API

```lua
local track_action = require("track-action")

-- Start/stop tracking
track_action.start()
track_action.stop()

-- Get statistics
local actions, metadata = track_action.get_stats()

-- Get top N actions
local top_10 = track_action.top(10)
-- Returns: { { action = "w", count = 1523 }, ... }

-- Save statistics
track_action.save()

-- Reset statistics
track_action.reset()

-- Window controls
track_action.toggle_stats()  -- Toggle stats window on/off
track_action.show_stats()    -- Show stats window
track_action.hide_stats()    -- Hide stats window
track_action.is_stats_visible()  -- Check if window is visible
```

## How It Works

### Hybrid Approach

track-action.nvim uses a **hybrid approach** combining:

1. **State Machine Parser**: Parses standard Vim commands (based on Neovim's internal parser)
2. **Mapping Resolution**: Detects and resolves custom keymappings
3. **Semantic Classification**: Groups actions by semantic meaning

### Example

```vim
" User types: <leader>bd (LazyVim buffer delete mapping)
"
" track-action.nvim:
" 1. Detects '<leader>bd' matches a custom mapping
" 2. Resolves to: '<cmd>bd<cr>'
" 3. Classifies as: 'ex:buffer_delete'
" 4. Tracks: "ex:buffer_delete"
```

### Standard Vim Commands

For standard Vim commands, the plugin tracks semantic actions:

- `2w` → tracks as `w` (word forward)
- `3dd` → tracks as `dd` (delete line)
- `dw` → tracks as `dw` (delete word)
- `ciw` → tracks as `ciw` (change inner word)

### Custom Mappings

For custom mappings, the plugin:
- Uses mapping descriptions if available
- Classifies common Ex commands (`:w`, `:bd`, `:q`)
- Falls back to tracking as "custom:mapping_name"

## Statistics

Statistics are stored in JSON format at `~/.local/share/nvim/track_action_stats.json`:

```json
{
  "version": 1,
  "actions": {
    "w": 1523,
    "j": 8921,
    "k": 7654,
    "dd": 234,
    "dw": 456,
    "ex:buffer_delete": 89
  },
  "metadata": {
    "first_tracked": 1706356800,
    "last_updated": 1706443200,
    "total_actions": 18877
  }
}
```

## Use Cases

- **Track improvement**: See how your Vim usage evolves over time
- **Identify patterns**: Discover which actions you use most
- **Find inefficiencies**: Spot opportunities to learn more efficient commands
- **Compare workflows**: See how different projects affect your usage patterns

## Documentation

For detailed technical documentation, see:
- [PLAN.md](PLAN.md) - Implementation plan and architecture
- [NEOVIM_MAPPING_RESOLUTION.md](NEOVIM_MAPPING_RESOLUTION.md) - How Neovim resolves mappings

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

MIT License - see LICENSE file for details

## Credits

- Inspired by Vim's command parsing and Neovim's architecture
- Built with insights from [which-key.nvim](https://github.com/folke/which-key.nvim)
- Created for the Vim/Neovim community

## Roadmap

### Phase 1 (Current)
- ✅ Core action tracking
- ✅ State machine parser
- ✅ Mapping resolution (hybrid approach)
- ✅ Persistent storage

### Phase 2 (Planned)
- [ ] Enhanced visualization
- [ ] Action sequence analysis
- [ ] Suggestions for optimization

### Phase 3 (Future)
- [ ] Time-based analytics
- [ ] Project-specific tracking
- [ ] Export to various formats
- [ ] Integration with learning resources
