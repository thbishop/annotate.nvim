-- Public API for annotate.nvim

local core = require("annotate.core")
local input = require("annotate.input")
local persistence = require("annotate.persistence")
local render = require("annotate.render")

local M = {}

-- Forward declaration for refresh function
local refresh_trouble_if_open

---Prompt for annotation input using a floating window
---@param end_line number 1-indexed line to anchor the input window below
---@param callback fun(text: string|nil)
---@param initial_text string|nil
local function prompt_annotation_input(end_line, callback, initial_text)
  input.open(end_line, callback, initial_text)
end

---Add a new annotation
---@param start_line number 1-indexed
---@param end_line number 1-indexed
function M.add(start_line, end_line)
  core.init()

  local bufnr = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(bufnr)
  local original_content = core.get_buffer_lines(bufnr, start_line, end_line)

  prompt_annotation_input(end_line, function(comment)
    if not comment then
      return
    end

    ---@type Annotation
    local annotation = {
      id = core.next_id,
      bufnr = bufnr,
      file = file,
      start_line = start_line,
      end_line = end_line,
      original_content = original_content,
      comment = comment,
      created_at = os.time(),
      extmark_id = nil,
      sign_ids = {},
      line_hl_ids = {},
      drifted = false,
    }

    core.annotations[core.next_id] = annotation
    core.next_id = core.next_id + 1

    render.render_annotation(annotation)
    persistence.save_to_disk()
    refresh_trouble_if_open()
  end)
end

---Add annotation from visual mode
function M.add_visual()
  local start_line = vim.fn.line("v")
  local end_line = vim.fn.line(".")

  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)

  vim.schedule(function()
    M.add(start_line, end_line)
  end)
end

---Delete an annotation
---@param annotation Annotation
function M.delete(annotation)
  core.redo_stack = {}

  table.insert(core.undo_stack, { annotation })
  if #core.undo_stack > core.max_undo then
    table.remove(core.undo_stack, 1)
  end

  render.clear_annotation_rendering(annotation)
  core.annotations[annotation.id] = nil
  persistence.save_to_disk()
  refresh_trouble_if_open()
end

---Delete annotation under cursor
function M.delete_under_cursor()
  local annotation = core.get_under_cursor()
  if annotation then
    M.delete(annotation)
    vim.notify("Annotation deleted", vim.log.levels.INFO)
  else
    vim.notify("No annotation under cursor", vim.log.levels.WARN)
  end
end

---Edit annotation under cursor
function M.edit_under_cursor()
  local annotation = core.get_under_cursor()
  if not annotation then
    vim.notify("No annotation under cursor", vim.log.levels.WARN)
    return
  end

  prompt_annotation_input(annotation.end_line, function(comment)
    if not comment then
      return
    end

    annotation.comment = comment
    render.render_annotation(annotation)
    persistence.save_to_disk()
    refresh_trouble_if_open()
  end, annotation.comment)
end

---Delete all annotations
function M.delete_all()
  local count = vim.tbl_count(core.annotations)
  if count == 0 then
    vim.notify("No annotations to delete", vim.log.levels.INFO)
    return
  end

  core.redo_stack = {}

  local annotation_list = {}
  for _, annotation in pairs(core.annotations) do
    table.insert(annotation_list, annotation)
    render.clear_annotation_rendering(annotation)
  end

  table.insert(core.undo_stack, annotation_list)
  if #core.undo_stack > core.max_undo then
    table.remove(core.undo_stack, 1)
  end

  core.annotations = {}
  persistence.save_to_disk()
  refresh_trouble_if_open()
  vim.notify(string.format("%d annotations deleted (undo to restore)", count), vim.log.levels.INFO)
end

---Undo last delete
function M.undo_delete()
  if #core.undo_stack == 0 then
    vim.notify("Nothing to undo", vim.log.levels.WARN)
    return
  end

  local entry = table.remove(core.undo_stack)

  table.insert(core.redo_stack, entry)
  if #core.redo_stack > core.max_undo then
    table.remove(core.redo_stack, 1)
  end

  for _, annotation in ipairs(entry) do
    core.annotations[annotation.id] = annotation
    render.render_annotation(annotation)
  end

  persistence.save_to_disk()
  refresh_trouble_if_open()

  local count = #entry
  if count == 1 then
    vim.notify("Annotation restored", vim.log.levels.INFO)
  else
    vim.notify(string.format("%d annotations restored", count), vim.log.levels.INFO)
  end
end

---Redo last undo
function M.redo_delete()
  if #core.redo_stack == 0 then
    vim.notify("Nothing to redo", vim.log.levels.WARN)
    return
  end

  local entry = table.remove(core.redo_stack)

  table.insert(core.undo_stack, entry)
  if #core.undo_stack > core.max_undo then
    table.remove(core.undo_stack, 1)
  end

  for _, annotation in ipairs(entry) do
    render.clear_annotation_rendering(annotation)
    core.annotations[annotation.id] = nil
  end

  persistence.save_to_disk()
  refresh_trouble_if_open()

  local count = #entry
  if count == 1 then
    vim.notify("Annotation re-deleted", vim.log.levels.INFO)
  else
    vim.notify(string.format("%d annotations re-deleted", count), vim.log.levels.INFO)
  end
end

---Copy all annotations to clipboard and delete them
function M.yank_and_delete_all()
  if vim.tbl_isempty(core.annotations) then
    vim.notify("No annotations to cut", vim.log.levels.WARN)
    return
  end

  M.yank_all()
  M.delete_all()
end

---Copy all annotations to clipboard
function M.yank_all()
  local grouped = {} ---@type table<string, Annotation[]>

  for _, annotation in pairs(core.annotations) do
    local file = annotation.file ~= "" and annotation.file or "[unsaved buffer]"
    grouped[file] = grouped[file] or {}
    table.insert(grouped[file], annotation)
  end

  if vim.tbl_isempty(grouped) then
    vim.notify("No annotations to copy", vim.log.levels.WARN)
    return
  end

  local lines = {}
  for file, file_annotations in pairs(grouped) do
    table.sort(file_annotations, function(a, b)
      return a.start_line < b.start_line
    end)

    for _, annotation in ipairs(file_annotations) do
      table.insert(lines, string.format("File: %sL%d:L%d", file, annotation.start_line, annotation.end_line))

      local ext = file:match("%.([^%.]+)$") or ""
      table.insert(lines, "```" .. ext)
      for _, content_line in ipairs(annotation.original_content) do
        table.insert(lines, content_line)
      end
      table.insert(lines, "```")
      table.insert(lines, "Comment: " .. annotation.comment)
      table.insert(lines, "")
      table.insert(lines, "---")
      table.insert(lines, "")
    end
  end

  if #lines >= 2 then
    table.remove(lines)
    table.remove(lines)
  end

  local text = table.concat(lines, "\n")
  vim.fn.setreg("+", text)
  vim.notify(string.format("Copied %d annotations to clipboard", vim.tbl_count(core.annotations)), vim.log.levels.INFO)
end

---Write annotations to markdown file
function M.write_to_file()
  local content, count = persistence.generate_markdown_content()

  if not content then
    vim.notify("No annotations to export", vim.log.levels.WARN)
    return
  end

  local default_dir = vim.fn.getcwd()
  for _, annotation in pairs(core.annotations) do
    if annotation.file ~= "" then
      default_dir = vim.fn.fnamemodify(annotation.file, ":h")
      break
    end
  end
  local default_filename = default_dir .. "/annotations.md"

  vim.ui.input({ prompt = "Save annotations to: ", default = default_filename }, function(filename)
    if not filename or filename == "" then
      vim.notify("Export cancelled", vim.log.levels.INFO)
      return
    end

    filename = vim.fn.expand(filename)

    local file = io.open(filename, "w")
    if not file then
      vim.notify("Failed to open file: " .. filename, vim.log.levels.ERROR)
      return
    end

    file:write(content)
    file:close()

    vim.notify(string.format("Exported %d annotations to %s", count, filename), vim.log.levels.INFO)
  end)
end

---Import annotations from markdown file
function M.import_from_file()
  local default_dir = vim.fn.getcwd()
  local default_filename = default_dir .. "/annotations.md"

  vim.ui.input(
    { prompt = "Import annotations from: ", default = default_filename, completion = "file" },
    function(filename)
      if not filename or filename == "" then
        vim.notify("Import cancelled", vim.log.levels.INFO)
        return
      end

      filename = vim.fn.expand(filename)

      if vim.fn.filereadable(filename) ~= 1 then
        vim.notify("File not found: " .. filename, vim.log.levels.ERROR)
        return
      end

      local file = io.open(filename, "r")
      if not file then
        vim.notify("Failed to open file: " .. filename, vim.log.levels.ERROR)
        return
      end

      local content = file:read("*a")
      file:close()

      local parsed = persistence.parse_markdown_annotations(content)

      if #parsed == 0 then
        vim.notify("No annotations found in file", vim.log.levels.WARN)
        return
      end

      local imported = 0
      local skipped = 0

      for _, ann in ipairs(parsed) do
        if vim.fn.filereadable(ann.file) ~= 1 then
          skipped = skipped + 1
        else
          local bufnr = vim.fn.bufadd(ann.file)
          vim.fn.bufload(bufnr)

          ---@type Annotation
          local annotation = {
            id = core.next_id,
            bufnr = bufnr,
            file = ann.file,
            start_line = ann.start_line,
            end_line = ann.end_line,
            original_content = ann.original_content,
            comment = ann.comment,
            created_at = os.time(),
            extmark_id = nil,
            sign_ids = {},
            line_hl_ids = {},
            drifted = false,
          }

          core.annotations[core.next_id] = annotation
          core.next_id = core.next_id + 1
          imported = imported + 1

          annotation.drifted = core.check_drift(annotation)

          if vim.api.nvim_buf_is_valid(bufnr) then
            render.render_annotation(annotation)
          end
        end
      end

      local msg = string.format("Imported %d annotations", imported)
      if skipped > 0 then
        msg = msg .. string.format(" (%d skipped - files not found)", skipped)
      end
      vim.notify(msg, vim.log.levels.INFO)
    end
  )
end

---Jump to next annotation in current buffer
function M.next_annotation()
  local buffer_annotations = core.get_buffer_annotations_sorted()

  if #buffer_annotations == 0 then
    vim.notify("No annotations in current buffer", vim.log.levels.INFO)
    return
  end

  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

  for _, annotation in ipairs(buffer_annotations) do
    if annotation.start_line > cursor_line then
      vim.api.nvim_win_set_cursor(0, { annotation.start_line, 0 })
      vim.notify(core.truncate(annotation.comment, 50), vim.log.levels.INFO)
      return
    end
  end

  local first = buffer_annotations[1]
  vim.api.nvim_win_set_cursor(0, { first.start_line, 0 })
  vim.notify("[wrap] " .. core.truncate(first.comment, 45), vim.log.levels.INFO)
end

---Jump to previous annotation in current buffer
function M.prev_annotation()
  local buffer_annotations = core.get_buffer_annotations_sorted()

  if #buffer_annotations == 0 then
    vim.notify("No annotations in current buffer", vim.log.levels.INFO)
    return
  end

  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

  for i = #buffer_annotations, 1, -1 do
    local annotation = buffer_annotations[i]
    if annotation.start_line < cursor_line then
      vim.api.nvim_win_set_cursor(0, { annotation.start_line, 0 })
      vim.notify(core.truncate(annotation.comment, 50), vim.log.levels.INFO)
      return
    end
  end

  local last = buffer_annotations[#buffer_annotations]
  vim.api.nvim_win_set_cursor(0, { last.start_line, 0 })
  vim.notify("[wrap] " .. core.truncate(last.comment, 45), vim.log.levels.INFO)
end

---Get annotation under cursor (exposed for external use)
function M.get_under_cursor()
  return core.get_under_cursor()
end

---Get all annotations (exposed for external use)
function M.get_all()
  return core.get_all()
end

---Delete annotation by ID
---@param id number
---@return boolean success
function M.delete_by_id(id)
  local annotation = core.annotations[id]
  if not annotation then
    return false
  end

  M.delete(annotation)
  return true
end

---Edit annotation by ID
---@param id number
---@return boolean success
function M.edit_by_id(id)
  local annotation = core.annotations[id]
  if not annotation then
    return false
  end

  if vim.api.nvim_buf_is_valid(annotation.bufnr) then
    vim.api.nvim_set_current_buf(annotation.bufnr)
    vim.api.nvim_win_set_cursor(0, { annotation.start_line, 0 })
  end

  prompt_annotation_input(annotation.end_line, function(comment)
    if not comment then
      return
    end

    annotation.comment = comment
    render.render_annotation(annotation)
    persistence.save_to_disk()
    refresh_trouble_if_open()
  end, annotation.comment)

  return true
end

-- ============================================================================
-- Trouble Integration
-- ============================================================================

---Update quickfix list with current annotations
local function update_quickfix_list()
  local items = {}
  for _, annotation in pairs(core.annotations) do
    core.update_position_from_extmark(annotation)
    local line_range = core.format_line_range(annotation.start_line, annotation.end_line)
    local prefix = annotation.drifted and "⚠ " or "● "
    table.insert(items, {
      bufnr = annotation.bufnr,
      filename = annotation.file,
      lnum = annotation.start_line,
      end_lnum = annotation.end_line,
      col = 1,
      text = prefix .. "[" .. line_range .. "] " .. annotation.comment,
      type = annotation.drifted and "W" or "I",
      user_data = { annotation_id = annotation.id },
    })
  end

  table.sort(items, function(a, b)
    if a.filename ~= b.filename then
      return (a.filename or "") < (b.filename or "")
    end
    return a.lnum < b.lnum
  end)

  vim.fn.setqflist({}, "r", {
    title = "Annotations",
    items = items,
  })
end

---Refresh Trouble list if open
refresh_trouble_if_open = function()
  local ok, trouble = pcall(require, "trouble")
  if ok and trouble.is_open("qflist") then
    update_quickfix_list()
    trouble.refresh()
  end
end

---Open annotation list
function M.open_list()
  if vim.tbl_isempty(core.annotations) then
    vim.notify("No annotations", vim.log.levels.INFO)
    return
  end

  update_quickfix_list()

  local ok, trouble = pcall(require, "trouble")
  if ok then
    trouble.open({ mode = "qflist", focus = true })
  else
    vim.cmd("copen")
  end
end

-- ============================================================================
-- Telescope Integration
-- ============================================================================

---Telescope picker for annotations
function M.telescope_picker(opts)
  opts = opts or {}
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")
  local entry_display = require("telescope.pickers.entry_display")

  if vim.tbl_isempty(core.annotations) then
    vim.notify("No annotations", vim.log.levels.INFO)
    return
  end

  local annotation_list = {}
  for _, annotation in pairs(core.annotations) do
    core.update_position_from_extmark(annotation)
    table.insert(annotation_list, annotation)
  end

  table.sort(annotation_list, function(a, b)
    if a.file ~= b.file then
      return a.file < b.file
    end
    return a.start_line < b.start_line
  end)

  local displayer = entry_display.create({
    separator = " ",
    items = {
      { width = 4 },
      { width = 30 },
      { width = 10 },
      { remaining = true },
    },
  })

  local make_display = function(entry)
    local ann = entry.annotation
    local icon = ann.drifted and "⚠" or "●"
    local icon_hl = ann.drifted and "DiagnosticWarn" or "DiagnosticInfo"
    local filename = vim.fn.fnamemodify(ann.file, ":t")
    local line_range = ann.start_line == ann.end_line and string.format("L%d", ann.start_line)
      or string.format("L%d-%d", ann.start_line, ann.end_line)

    return displayer({
      { icon, icon_hl },
      { filename, "TelescopeResultsIdentifier" },
      { line_range, "TelescopeResultsNumber" },
      { ann.comment, "TelescopeResultsComment" },
    })
  end

  local entry_maker = function(ann)
    return {
      value = ann,
      annotation = ann,
      display = make_display,
      ordinal = ann.file .. " " .. ann.comment,
      filename = ann.file,
      lnum = ann.start_line,
      col = 1,
    }
  end

  local previewer = previewers.new_buffer_previewer({
    title = "Annotation Preview",
    define_preview = function(self, entry)
      local ann = entry.annotation

      local lines = {
        "# " .. vim.fn.fnamemodify(ann.file, ":~:."),
        string.format("Lines %d-%d%s", ann.start_line, ann.end_line, ann.drifted and " (DRIFTED)" or ""),
        "",
        "## Comment:",
        ann.comment,
        "",
        "## Original Code:",
      }

      for _, line in ipairs(ann.original_content) do
        table.insert(lines, line)
      end

      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", "markdown")
    end,
  })

  pickers
    .new(opts, {
      prompt_title = "Annotations",
      finder = finders.new_table({
        results = annotation_list,
        entry_maker = entry_maker,
      }),
      sorter = conf.generic_sorter(opts),
      previewer = previewer,
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)

          if selection and selection.annotation then
            local ann = selection.annotation
            if ann.file ~= "" then
              vim.cmd("edit " .. vim.fn.fnameescape(ann.file))
            end
            vim.api.nvim_win_set_cursor(0, { ann.start_line, 0 })
          end
        end)

        map("n", "d", function()
          local selection = action_state.get_selected_entry()
          if selection and selection.annotation then
            M.delete(selection.annotation)
            vim.notify("Annotation deleted", vim.log.levels.INFO)
            local current_picker = action_state.get_current_picker(prompt_bufnr)
            local new_list = {}
            for _, ann in pairs(core.annotations) do
              core.update_position_from_extmark(ann)
              table.insert(new_list, ann)
            end
            table.sort(new_list, function(a, b)
              if a.file ~= b.file then
                return a.file < b.file
              end
              return a.start_line < b.start_line
            end)
            current_picker:refresh(
              finders.new_table({
                results = new_list,
                entry_maker = entry_maker,
              }),
              { reset_prompt = false }
            )
          end
        end)

        map("n", "e", function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)

          if selection and selection.annotation then
            local ann = selection.annotation
            if ann.file ~= "" then
              vim.cmd("edit " .. vim.fn.fnameescape(ann.file))
            end
            vim.api.nvim_win_set_cursor(0, { ann.start_line, 0 })
            M.edit_by_id(ann.id)
          end
        end)

        map("n", "D", function()
          local current_picker = action_state.get_current_picker(prompt_bufnr)
          local new_list = {}
          for _, ann in pairs(core.annotations) do
            if ann.drifted then
              core.update_position_from_extmark(ann)
              table.insert(new_list, ann)
            end
          end
          if #new_list == 0 then
            vim.notify("No drifted annotations", vim.log.levels.INFO)
            return
          end
          current_picker:refresh(
            finders.new_table({
              results = new_list,
              entry_maker = entry_maker,
            }),
            { reset_prompt = true }
          )
        end)

        return true
      end,
    })
    :find()
end

---Open Telescope picker
function M.open_telescope()
  local ok = pcall(require, "telescope")
  if not ok then
    vim.notify("Telescope not found", vim.log.levels.ERROR)
    return
  end

  M.telescope_picker(require("telescope.themes").get_dropdown({}))
end

-- ============================================================================
-- Keymap Setup
-- ============================================================================

---Enable default keymaps
---Call this function to set up all default keymaps.
---Keymaps are NOT set automatically - you must call this explicitly.
---@example
---  require('annotate').setup({})
---  require('annotate').set_keymaps()
function M.set_keymaps()
  require("annotate.config").setup_keymaps()
end

return M
