# annotate.nvim

Code review annotations with virtual text display for Neovim.

![Neovim](https://img.shields.io/badge/Neovim-0.9+-blueviolet.svg?style=flat&logo=Neovim&logoColor=white)

## Features

- **Add annotations** to selected code ranges with visual text display
- **Drift detection** - highlights when annotated code has changed
- **Virtual text** displayed below annotated hunks with word-wrap
- **Copy to clipboard** and use in your coding agent of choice
- **Sign column** indicators for annotated lines
- **Line highlighting** with customizable background colors
- **Trouble.nvim integration** for browsing annotations
- **Telescope picker** for fuzzy searching annotations
- **Persistence** - optionally save/load annotations to JSON
- **Import/Export** to markdown format
- **Undo/Redo** support for deletions

https://github.com/user-attachments/assets/d6a69abc-c822-4e5d-8935-6de3bae867d7

## Requirements

- Neovim >= 0.9

### Optional

- [trouble.nvim](https://github.com/folke/trouble.nvim) - Enhanced annotation list
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) - Fuzzy search annotations

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

**Basic setup (no keymaps):**

```lua
{
  "hugooliveirad/annotate.nvim",
  opts = {},
  cmd = { "Annotate", "AnnotateAdd", "AnnotateList" },
}
```

**With default keymaps:**

```lua
{
  "hugooliveirad/annotate.nvim",
  opts = {},
  config = function(_, opts)
    require("annotate").setup(opts)
    require("annotate").set_keymaps()  -- Enable default keymaps
  end,
  cmd = { "Annotate", "AnnotateAdd", "AnnotateList" },
}
```

**With lazy.nvim keys (recommended for lazy-loading):**

```lua
{
  "hugooliveirad/annotate.nvim",
  opts = {},
  keys = {
    { "<leader>aa", mode = "v", function() require("annotate").add_visual() end, desc = "Add annotation" },
    { "<leader>al", function() require("annotate").open_list() end, desc = "List annotations" },
    { "<leader>as", function() require("annotate").open_telescope() end, desc = "Search annotations (Telescope)" },
    { "<leader>ad", function() require("annotate").delete_under_cursor() end, desc = "Delete annotation" },
    { "<leader>ae", function() require("annotate").edit_under_cursor() end, desc = "Edit annotation" },
    { "]a", function() require("annotate").next_annotation() end, desc = "Next annotation" },
    { "[a", function() require("annotate").prev_annotation() end, desc = "Previous annotation" },
  },
  cmd = { "Annotate", "AnnotateAdd", "AnnotateList" },
}
```

## Configuration

<details>
<summary>Default configuration</summary>

```lua
{
  -- Keymaps used by set_keymaps()
  keymaps = {
    add = "<leader>aa",           -- Visual mode: add annotation
    list = "<leader>al",          -- Open Trouble list
    telescope = "<leader>as",     -- Open Telescope picker
    yank = "<leader>ay",          -- Yank all annotations to clipboard
    delete = "<leader>ad",        -- Delete annotation under cursor
    edit = "<leader>ae",          -- Edit annotation under cursor
    delete_all = "<leader>aD",    -- Delete all annotations
    undo = "<leader>au",          -- Undo last delete
    redo = "<leader>aU",          -- Redo last undo
    write = "<leader>aw",         -- Export to markdown file
    import = "<leader>ai",        -- Import from markdown file
    next_annotation = "]a",       -- Jump to next annotation
    prev_annotation = "[a",       -- Jump to previous annotation
  },
  virtual_text = {
    wrap_at = 80,                 -- Wrap long comments (0 to disable)
    prefix = "> ",                -- Prefix prepended to each virtual text line
  },
  sign = {
    text = "",                   -- Sign column text
    hl = "DiagnosticSignInfo",    -- Sign highlight
  },
  highlights = {
    virtual_text = "Comment",
    virtual_text_drifted = "DiagnosticWarn",
    sign = "DiagnosticSignInfo",
    sign_drifted = "DiagnosticSignWarn",
    line = "AnnotateLine",        -- Line background (false to disable)
    line_drifted = "AnnotateLineDrifted",
  },
  persist = {
    enabled = false,              -- Auto-save/load annotations
    path = ".annotations.json",   -- Path relative to cwd or absolute
  },
}
```

</details>

## Usage

### Adding Annotations

1. Visual select the lines you want to annotate
2. Press `<leader>aa` (or your configured keymap)
3. Type your annotation comment
4. Press `Enter` to save

### Commands

| Command | Description |
|---------|-------------|
| `:Annotate` | Open annotation list (default) |
| `:Annotate add` | Add annotation on current line |
| `:Annotate list` | Open Trouble list |
| `:Annotate telescope` | Open Telescope picker |
| `:Annotate delete` | Delete annotation under cursor |
| `:Annotate edit` | Edit annotation under cursor |
| `:Annotate yank` | Copy all annotations to clipboard |
| `:Annotate write` | Export to markdown file |
| `:Annotate import` | Import from markdown file |
| `:Annotate undo` | Undo last delete |
| `:Annotate redo` | Redo last undo |
| `:Annotate clear` | Delete all annotations |
| `:Annotate next/prev` | Jump to next/prev annotation |
| `:Annotate help` | Show help |

Shortcuts: `:AnnotateAdd`, `:AnnotateList`, `:AnnotateTelescope`, `:AnnotateDelete`, `:AnnotateEdit`

### Suggested Keymaps

Enable default keymaps with `require('annotate').set_keymaps()`.

| Key | Mode | Action |
|-----|------|--------|
| `<leader>aa` | v | Add annotation to selection |
| `<leader>al` | n | Open annotation list |
| `<leader>as` | n | Search with Telescope |
| `<leader>ay` | n | Yank all to clipboard |
| `<leader>ad` | n | Delete under cursor |
| `<leader>ae` | n | Edit under cursor |
| `<leader>aD` | n | Delete all |
| `<leader>au` | n | Undo delete |
| `<leader>aU` | n | Redo delete |
| `<leader>aw` | n | Export to file |
| `<leader>ai` | n | Import from file |
| `]a` | n | Next annotation |
| `[a` | n | Previous annotation |

### Telescope Actions

| Key | Action |
|-----|--------|
| `<CR>` | Jump to annotation |
| `d` | Delete annotation |
| `e` | Edit annotation |
| `D` | Filter drifted only |

## Highlights

The plugin defines these highlight groups (with defaults):

| Group | Default | Description |
|-------|---------|-------------|
| `AnnotateLine` | `#3d3d00` bg | Background for annotated lines |
| `AnnotateLineDrifted` | `#4d2626` bg | Background for drifted lines |

Override in your config:

```lua
vim.api.nvim_set_hl(0, "AnnotateLine", { bg = "#2d2d00" })
vim.api.nvim_set_hl(0, "AnnotateLineDrifted", { bg = "#3d1616" })
```

## Health Check

Run `:checkhealth annotate` to verify installation.

## License

Apache-2.0
