-- Floating window input for annotate.nvim

local M = {}

---Open a floating window input anchored below end_line, or above start_line if not enough space
---@param start_line number 1-indexed buffer line for the start of the selection
---@param end_line number 1-indexed buffer line to anchor the window below
---@param callback fun(text: string|nil)
---@param initial_text string|nil
function M.open(start_line, end_line, callback, initial_text)
  local source_win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)

  -- Prepare initial content; split on newlines and pad to min 4 lines
  local initial_lines = {}
  if initial_text and initial_text ~= "" then
    initial_lines = vim.split(initial_text, "\n", { plain = true })
  end
  while #initial_lines < 4 do
    table.insert(initial_lines, "")
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_lines)

  -- Calculate position: below end_line, or above start_line if not enough space
  local win_width = vim.api.nvim_win_get_width(source_win)
  local win_height = vim.api.nvim_win_get_height(source_win)
  local win_pos = vim.api.nvim_win_get_position(source_win)

  local screen_row_end = vim.fn.screenpos(source_win, end_line, 1).row
  local float_row_below
  if screen_row_end == 0 then
    float_row_below = win_height - 6
  else
    float_row_below = screen_row_end - win_pos[1]
  end

  local max_width = 80
  local float_width = math.min(win_width - 4, max_width)
  local desired_height = 4

  local space_below = win_height - float_row_below - 2 -- rows available below end_line

  local float_row, float_height
  if space_below >= desired_height then
    -- Enough room below: use default placement
    float_row = float_row_below
    float_height = desired_height
  else
    -- Not enough room below: try placing above start_line
    local screen_row_start = vim.fn.screenpos(source_win, start_line, 1).row
    local float_row_above_bottom -- window-relative row of the start of the selection
    if screen_row_start == 0 then
      float_row_above_bottom = 0
    else
      float_row_above_bottom = screen_row_start - win_pos[1] - 1
    end

    -- The float window placed "above" should have its bottom border just above start_line.
    -- With a rounded border, the window occupies rows [row .. row + height + 1] (border lines).
    -- We want: row + height + 2 <= float_row_above_bottom
    -- => row = float_row_above_bottom - desired_height - 2
    local space_above = float_row_above_bottom - 2 -- rows available above start_line
    if space_above >= desired_height then
      float_height = desired_height
      float_row = float_row_above_bottom - desired_height - 2
    else
      -- Use whichever side has more space; fall back to below with clamped height
      if space_above > space_below then
        float_height = math.max(1, space_above)
        float_row = math.max(0, float_row_above_bottom - float_height - 2)
      else
        float_height = math.max(1, space_below)
        float_row = float_row_below
      end
    end
  end

  local float_win = vim.api.nvim_open_win(buf, true, {
    relative = "win",
    win = source_win,
    row = float_row,
    col = 2,
    width = float_width,
    height = float_height,
    style = "minimal",
    border = "rounded",
    title = " Annotation (Ctrl-s: save, q: cancel) ",
    title_pos = "center",
  })

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.wo[float_win].wrap = true
  vim.wo[float_win].linebreak = true

  -- For edits, place cursor after existing content; otherwise start at top
  local last_content_line = 0
  for i = #initial_lines, 1, -1 do
    if initial_lines[i] ~= "" then
      last_content_line = i
      break
    end
  end
  if last_content_line > 0 then
    vim.api.nvim_win_set_cursor(float_win, { last_content_line, #initial_lines[last_content_line] })
  end
  vim.cmd("startinsert!")

  -- Guard so callback is only called once
  local done = false

  local function finish(text)
    if done then
      return
    end
    done = true
    if vim.api.nvim_win_is_valid(float_win) then
      vim.api.nvim_win_close(float_win, true)
    end
    vim.schedule(function()
      vim.cmd("stopinsert")
      if vim.api.nvim_win_is_valid(source_win) then
        vim.api.nvim_set_current_win(source_win)
      end
      callback(text)
    end)
  end

  local function confirm()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    -- Strip trailing blank lines
    while #lines > 0 and vim.trim(lines[#lines]) == "" do
      table.remove(lines)
    end
    local text = table.concat(lines, "\n")
    finish(vim.trim(text) ~= "" and text or nil)
  end

  local function cancel()
    finish(nil)
  end

  -- Handle the window being closed externally (e.g. :q)
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(float_win),
    once = true,
    callback = function()
      finish(nil)
    end,
  })

  local opts = { buffer = buf, noremap = true, silent = true }
  vim.keymap.set("i", "<C-s>", confirm, opts)
  vim.keymap.set("n", "<C-s>", confirm, opts)
  vim.keymap.set("n", "q", cancel, opts)
  vim.keymap.set("n", "<Esc>", cancel, opts)
end

return M
