-- Rendering module for annotate.nvim

local config = require("annotate.config")
local core = require("annotate.core")

local M = {}

---Wrap text at specified column
---@param text string
---@param wrap_at number
---@param prefix string
---@param hl string
---@return string[][]
local function wrap_text(text, wrap_at, prefix, hl)
  local lines = {}
  local remaining = text

  while #remaining > 0 do
    local available_width = wrap_at - #prefix

    if available_width <= 0 then
      available_width = 40
    end

    if #remaining <= available_width then
      table.insert(lines, { { prefix .. remaining, hl } })
      break
    end

    local break_at = available_width
    local space_pos = remaining:sub(1, available_width):match(".*()%s")
    if space_pos and space_pos > available_width / 2 then
      break_at = space_pos - 1
    end

    local line_text = remaining:sub(1, break_at)
    remaining = remaining:sub(break_at + 1):gsub("^%s+", "")

    table.insert(lines, { { prefix .. line_text, hl } })
  end

  return lines
end

---Render virtual text for an annotation
---@param annotation Annotation
function M.render_virtual_text(annotation)
  if not vim.api.nvim_buf_is_valid(annotation.bufnr) then
    return
  end

  local cfg = config.get()
  local hl = annotation.drifted and cfg.highlights.virtual_text_drifted or cfg.highlights.virtual_text
  local wrap_at = cfg.virtual_text.wrap_at or 80

  local prefix = cfg.virtual_text.prefix or "> "
  local virt_lines = {}

  local paragraphs = vim.split(annotation.comment, "\n", { plain = true })
  for _, paragraph in ipairs(paragraphs) do
    if #paragraph == 0 then
      table.insert(virt_lines, { { prefix, hl } })
    elseif wrap_at > 0 and #paragraph + #prefix > wrap_at then
      local wrapped = wrap_text(paragraph, wrap_at, prefix, hl)
      for _, line in ipairs(wrapped) do
        table.insert(virt_lines, line)
      end
    else
      table.insert(virt_lines, { { prefix .. paragraph, hl } })
    end
  end

  -- Update extmark in-place when possible (avoids a delete + create round-trip)
  local opts = {
    virt_lines = virt_lines,
    virt_lines_above = false,
    right_gravity = false,
  }
  if annotation.extmark_id then
    opts.id = annotation.extmark_id
  end
  annotation.extmark_id =
    vim.api.nvim_buf_set_extmark(annotation.bufnr, core.namespace, annotation.end_line - 1, 0, opts)
end

---Render signs for an annotation
---@param annotation Annotation
function M.render_signs(annotation)
  if not vim.api.nvim_buf_is_valid(annotation.bufnr) then
    return
  end

  -- Remove existing signs
  for _, sign_id in ipairs(annotation.sign_ids or {}) do
    pcall(vim.fn.sign_unplace, "annotate", { buffer = annotation.bufnr, id = sign_id })
  end
  annotation.sign_ids = {}

  local sign_name = annotation.drifted and "AnnotateSignDrifted" or "AnnotateSign"

  for line = annotation.start_line, annotation.end_line do
    local sign_id = vim.fn.sign_place(0, "annotate", sign_name, annotation.bufnr, { lnum = line, priority = 10 })
    table.insert(annotation.sign_ids, sign_id)
  end
end

---Render line background highlights for an annotation
---@param annotation Annotation
function M.render_line_highlights(annotation)
  if not vim.api.nvim_buf_is_valid(annotation.bufnr) then
    return
  end

  local cfg = config.get()
  local line_hl = annotation.drifted and cfg.highlights.line_drifted or cfg.highlights.line
  if not line_hl then
    return
  end

  -- Remove existing line highlight extmarks
  for _, hl_id in ipairs(annotation.line_hl_ids or {}) do
    pcall(vim.api.nvim_buf_del_extmark, annotation.bufnr, core.namespace, hl_id)
  end
  annotation.line_hl_ids = {}

  for line = annotation.start_line, annotation.end_line do
    local hl_id = vim.api.nvim_buf_set_extmark(annotation.bufnr, core.namespace, line - 1, 0, {
      line_hl_group = line_hl,
      priority = 50,
    })
    table.insert(annotation.line_hl_ids, hl_id)
  end
end

---Render a single annotation
---@param annotation Annotation
function M.render_annotation(annotation)
  annotation.drifted = core.check_drift(annotation)
  M.render_virtual_text(annotation)
  M.render_signs(annotation)
  M.render_line_highlights(annotation)
end

---Render all annotations for a buffer.
---Called from the TextChanged autocmd; skips sign/highlight re-rendering when
---neither the line range nor the drift status has changed, avoiding redundant
---Neovim API calls on every keystroke.
---@param bufnr number
function M.render_buffer_annotations(bufnr)
  for _, annotation in pairs(core.annotations) do
    if annotation.bufnr == bufnr then
      local old_start = annotation.start_line
      local old_end = annotation.end_line
      local old_drifted = annotation.drifted

      core.update_position_from_extmark(annotation)
      annotation.drifted = core.check_drift(annotation)

      local position_changed = annotation.start_line ~= old_start or annotation.end_line ~= old_end
      local drift_changed = annotation.drifted ~= old_drifted

      -- Always update virtual text (extmark updates in-place, cheap)
      M.render_virtual_text(annotation)

      -- Signs and line highlights are only re-placed when necessary
      if position_changed or drift_changed then
        M.render_signs(annotation)
        M.render_line_highlights(annotation)
      end
    end
  end
end

---Clear rendering for an annotation
---@param annotation Annotation
function M.clear_annotation_rendering(annotation)
  if annotation.extmark_id and vim.api.nvim_buf_is_valid(annotation.bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, annotation.bufnr, core.namespace, annotation.extmark_id)
  end

  for _, sign_id in ipairs(annotation.sign_ids or {}) do
    pcall(vim.fn.sign_unplace, "annotate", { buffer = annotation.bufnr, id = sign_id })
  end

  for _, hl_id in ipairs(annotation.line_hl_ids or {}) do
    if vim.api.nvim_buf_is_valid(annotation.bufnr) then
      pcall(vim.api.nvim_buf_del_extmark, annotation.bufnr, core.namespace, hl_id)
    end
  end
end

---Re-attach annotations to a buffer by filepath
---@param bufnr number
---@param filepath string
---@return number reattached_count
function M.reattach_annotations_to_buffer(bufnr, filepath)
  local reattached = 0
  for _, annotation in pairs(core.annotations) do
    if annotation.file == filepath and annotation.bufnr ~= bufnr then
      annotation.bufnr = bufnr
      annotation.extmark_id = nil
      annotation.sign_ids = {}
      M.render_annotation(annotation)
      reattached = reattached + 1
    end
  end
  return reattached
end

---Handle buffer being deleted
---@param bufnr number
function M.on_buffer_delete(bufnr)
  for _, annotation in pairs(core.annotations) do
    if annotation.bufnr == bufnr then
      annotation.extmark_id = nil
      annotation.sign_ids = {}
      annotation.line_hl_ids = {}
    end
  end
end

return M
