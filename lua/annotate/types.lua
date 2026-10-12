-- Type definitions for annotate.nvim

---@class Annotation
---@field id number Unique identifier
---@field bufnr number Buffer number
---@field file string Absolute file path
---@field start_line number 1-indexed start line
---@field end_line number 1-indexed end line
---@field original_content string[] Original lines (for yank/export)
---@field comment string The annotation text
---@field created_at number Timestamp
---@field extmark_id number|nil Extmark ID for virtual text tracking
---@field sign_ids number[] Sign IDs for the range
---@field line_hl_ids number[] Extmark IDs for line background highlights

return {}
