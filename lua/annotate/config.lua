-- Configuration module for annotate.nvim

---@class annotate.Config
---@field keymaps annotate.Config.Keymaps
---@field virtual_text annotate.Config.VirtualText
---@field sign annotate.Config.Sign
---@field highlights annotate.Config.Highlights
---@field persist annotate.Config.Persist

---@class annotate.Config.Keymaps
---@field add string|false Visual mode: add annotation
---@field list string|false Normal mode: open list
---@field telescope string|false Normal mode: telescope picker
---@field yank string|false Normal mode: yank all annotations
---@field yank_delete string|false Normal mode: yank all and delete
---@field delete string|false Normal mode: delete under cursor
---@field edit string|false Normal mode: edit under cursor
---@field delete_all string|false Normal mode: delete all
---@field undo string|false Normal mode: undo delete
---@field redo string|false Normal mode: redo delete
---@field write string|false Normal mode: export to file
---@field import string|false Normal mode: import from file
---@field next_annotation string|false Normal mode: jump to next
---@field prev_annotation string|false Normal mode: jump to prev

---@class annotate.Config.VirtualText
---@field wrap_at number Wrap long comments at this column (0 to disable)
---@field prefix string Prefix string prepended to each line of virtual text

---@class annotate.Config.Sign
---@field text string Sign text
---@field hl string Highlight group for sign

---@class annotate.Config.Highlights
---@field virtual_text string Highlight for virtual text
---@field virtual_text_drifted string Highlight for drifted virtual text
---@field sign string Sign highlight
---@field sign_drifted string Drifted sign highlight
---@field line string|false Line background highlight (false to disable)
---@field line_drifted string|false Drifted line background highlight

---@class annotate.Config.Persist
---@field enabled boolean Auto-save/load annotations
---@field path string Path relative to cwd or absolute

local M = {}

---@type annotate.Config
local defaults = {
  keymaps = {
    add = "<leader>aa",
    list = "<leader>al",
    telescope = "<leader>as",
    yank = "<leader>ay",
    yank_delete = "<leader>aY",
    delete = "<leader>ad",
    edit = "<leader>ae",
    delete_all = "<leader>aD",
    undo = "<leader>au",
    redo = "<leader>aU",
    write = "<leader>aw",
    import = "<leader>ai",
    next_annotation = "]a",
    prev_annotation = "[a",
  },
  virtual_text = {
    wrap_at = 80,
    prefix = "> ",
  },
  sign = {
    text = "",
    hl = "DiagnosticSignInfo",
  },
  highlights = {
    virtual_text = "Comment",
    virtual_text_drifted = "DiagnosticWarn",
    sign = "DiagnosticSignInfo",
    sign_drifted = "DiagnosticSignWarn",
    line = "AnnotateLine",
    line_drifted = "AnnotateLineDrifted",
  },
  persist = {
    enabled = false,
    path = ".annotations.json",
  },
}

---@type annotate.Config
local options

---Setup configuration
---@param opts? annotate.Config
function M.setup(opts)
  -- Version check
  if vim.fn.has("nvim-0.9") == 0 then
    vim.notify_once("annotate.nvim requires Neovim >= 0.9", vim.log.levels.ERROR)
    return
  end

  options = vim.tbl_deep_extend("force", {}, defaults, opts or {})
  M.setup_highlights()
  -- Note: keymaps are NOT set by default. Call require('annotate').set_keymaps() to enable.
end

---Get configuration
---@return annotate.Config
function M.get()
  if not options then
    M.setup()
  end
  return options
end

---Setup custom highlight groups
function M.setup_highlights()
  -- Dim yellow background for annotated lines
  vim.api.nvim_set_hl(0, "AnnotateLine", { bg = "#3d3d00", default = true })
  -- Dim red background for drifted annotated lines
  vim.api.nvim_set_hl(0, "AnnotateLineDrifted", { bg = "#4d2626", default = true })
end

---Setup keymaps (call require('annotate').set_keymaps() to enable)
function M.setup_keymaps()
  local api = require("annotate.api")
  local km = options.keymaps

  if km.add then
    vim.keymap.set("v", km.add, api.add_visual, { desc = "[A]nnotate: [A]dd annotation" })
  end

  if km.list then
    vim.keymap.set("n", km.list, api.open_list, { desc = "[A]nnotate: [L]ist annotations" })
  end

  if km.telescope then
    vim.keymap.set("n", km.telescope, api.open_telescope, { desc = "[A]nnotate: [S]earch annotations (telescope)" })
  end

  if km.yank then
    vim.keymap.set("n", km.yank, api.yank_all, { desc = "[A]nnotate: [Y]ank all annotations" })
  end

  if km.yank_delete then
    vim.keymap.set("n", km.yank_delete, api.yank_and_delete_all, { desc = "[A]nnotate: [Y]ank all and delete" })
  end

  if km.delete then
    vim.keymap.set("n", km.delete, api.delete_under_cursor, { desc = "[A]nnotate: [D]elete annotation" })
  end

  if km.edit then
    vim.keymap.set("n", km.edit, api.edit_under_cursor, { desc = "[A]nnotate: [E]dit annotation" })
  end

  if km.delete_all then
    vim.keymap.set("n", km.delete_all, api.delete_all, { desc = "[A]nnotate: [D]elete all annotations" })
  end

  if km.undo then
    vim.keymap.set("n", km.undo, api.undo_delete, { desc = "[A]nnotate: [U]ndo delete" })
  end

  if km.redo then
    vim.keymap.set("n", km.redo, api.redo_delete, { desc = "[A]nnotate: Redo delete" })
  end

  if km.write then
    vim.keymap.set("n", km.write, api.write_to_file, { desc = "[A]nnotate: [W]rite to file" })
  end

  if km.import then
    vim.keymap.set("n", km.import, api.import_from_file, { desc = "[A]nnotate: [I]mport from file" })
  end

  if km.next_annotation then
    vim.keymap.set("n", km.next_annotation, api.next_annotation, { desc = "Next annotation" })
  end

  if km.prev_annotation then
    vim.keymap.set("n", km.prev_annotation, api.prev_annotation, { desc = "Previous annotation" })
  end
end

return M
