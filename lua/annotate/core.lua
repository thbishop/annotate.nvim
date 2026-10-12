-- Core state and operations for annotate.nvim

local config = require("annotate.config")

local M = {}

-- State
---@type table<number, Annotation>
M.annotations = {}
M.next_id = 1
---@type Annotation[][] Each entry is a list of annotations from one operation
M.undo_stack = {}
---@type Annotation[][] Each entry is a list of annotations from one operation
M.redo_stack = {}
M.max_undo = 1000
---@type number|nil
M.namespace = nil

-- Track whether we've loaded from disk for current cwd
M.loaded_for_cwd = nil

---Initialize namespace and signs
function M.init()
  if M.namespace then
    return
  end
  M.namespace = vim.api.nvim_create_namespace("annotate")

  -- Re-apply highlights when colorscheme changes
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("AnnotateHighlights", { clear = true }),
    callback = function()
      config.setup_highlights()
    end,
  })

  local cfg = config.get()

  -- Define signs with number column highlighting
  vim.fn.sign_define("AnnotateSign", {
    text = cfg.sign.text,
    texthl = cfg.highlights.sign,
    numhl = cfg.highlights.sign,
  })
end

---Get buffer lines
---@param bufnr number
---@param start_line number 1-indexed
---@param end_line number 1-indexed
---@return string[]
function M.get_buffer_lines(bufnr, start_line, end_line)
  return vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
end

---Update extmark position from buffer
---@param annotation Annotation
function M.update_position_from_extmark(annotation)
  if not annotation.extmark_id or not vim.api.nvim_buf_is_valid(annotation.bufnr) then
    return
  end

  local mark = vim.api.nvim_buf_get_extmark_by_id(annotation.bufnr, M.namespace, annotation.extmark_id, {})
  if mark and #mark >= 2 then
    local new_end = mark[1] + 1 -- Convert 0-indexed to 1-indexed
    local line_diff = new_end - annotation.end_line
    annotation.start_line = annotation.start_line + line_diff
    annotation.end_line = new_end
  end
end

---Get annotation under cursor
---@return Annotation|nil
function M.get_under_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

  for _, annotation in pairs(M.annotations) do
    if annotation.bufnr == bufnr then
      M.update_position_from_extmark(annotation)
      if cursor_line >= annotation.start_line and cursor_line <= annotation.end_line then
        return annotation
      end
    end
  end

  return nil
end

---Get all annotations
---@return Annotation[]
function M.get_all()
  local result = {}
  for _, annotation in pairs(M.annotations) do
    M.update_position_from_extmark(annotation)
    table.insert(result, annotation)
  end
  return result
end

---Get sorted annotations for current buffer
---@return Annotation[]
function M.get_buffer_annotations_sorted()
  local bufnr = vim.api.nvim_get_current_buf()
  local result = {}

  for _, annotation in pairs(M.annotations) do
    if annotation.bufnr == bufnr then
      M.update_position_from_extmark(annotation)
      table.insert(result, annotation)
    end
  end

  table.sort(result, function(a, b)
    return a.start_line < b.start_line
  end)

  return result
end

---Format line range string
---@param start_line number
---@param end_line number
---@return string
function M.format_line_range(start_line, end_line)
  if start_line == end_line then
    return string.format("L%d", start_line)
  end
  return string.format("L%d-L%d", start_line, end_line)
end

---Truncate text for display
---@param text string
---@param max_len number
---@return string
function M.truncate(text, max_len)
  if #text <= max_len then
    return text
  end
  return text:sub(1, max_len - 3) .. "..."
end

return M
