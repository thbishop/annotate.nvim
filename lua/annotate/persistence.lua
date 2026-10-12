-- Persistence module for annotate.nvim

local config = require("annotate.config")
local core = require("annotate.core")

local M = {}

---Get the persistence file path
---@return string
function M.get_persist_path()
  local cfg = config.get()
  local path = cfg.persist.path
  if not vim.startswith(path, "/") then
    path = vim.fn.getcwd() .. "/" .. path
  end
  return path
end

---Serialize annotations to JSON-compatible format
---@return table
function M.serialize_annotations()
  local data = {
    version = 1,
    next_id = core.next_id,
    annotations = {},
  }

  for _, annotation in pairs(core.annotations) do
    table.insert(data.annotations, {
      id = annotation.id,
      file = annotation.file,
      start_line = annotation.start_line,
      end_line = annotation.end_line,
      original_content = annotation.original_content,
      comment = annotation.comment,
      created_at = annotation.created_at,
    })
  end

  return data
end

---Deserialize annotations from JSON data
---@param data table
---@return boolean success
function M.deserialize_annotations(data)
  if not data or data.version ~= 1 then
    return false
  end

  if data.next_id and data.next_id > core.next_id then
    core.next_id = data.next_id
  end

  for _, ann_data in ipairs(data.annotations or {}) do
    if not core.annotations[ann_data.id] then
      ---@type Annotation
      local annotation = {
        id = ann_data.id,
        bufnr = -1,
        file = ann_data.file,
        start_line = ann_data.start_line,
        end_line = ann_data.end_line,
        original_content = ann_data.original_content,
        comment = ann_data.comment,
        created_at = ann_data.created_at,
        extmark_id = nil,
        sign_ids = {},
        line_hl_ids = {},
      }
      core.annotations[ann_data.id] = annotation

      if annotation.id >= core.next_id then
        core.next_id = annotation.id + 1
      end
    end
  end

  return true
end

---Save annotations to disk
function M.save_to_disk()
  local cfg = config.get()
  if not cfg.persist.enabled then
    return
  end

  local path = M.get_persist_path()
  local data = M.serialize_annotations()

  if #data.annotations == 0 then
    if vim.fn.filereadable(path) == 1 then
      pcall(os.remove, path)
    end
    return
  end

  local ok, json = pcall(vim.fn.json_encode, data)
  if not ok then
    vim.notify("Failed to encode annotations: " .. tostring(json), vim.log.levels.ERROR)
    return
  end

  local file = io.open(path, "w")
  if not file then
    vim.notify("Failed to open " .. path .. " for writing", vim.log.levels.ERROR)
    return
  end

  file:write(json)
  file:close()
end

---Load annotations from disk
---@return boolean loaded
function M.load_from_disk()
  local cfg = config.get()
  if not cfg.persist.enabled then
    return false
  end

  local path = M.get_persist_path()
  if vim.fn.filereadable(path) ~= 1 then
    return false
  end

  local file = io.open(path, "r")
  if not file then
    return false
  end

  local content = file:read("*a")
  file:close()

  if not content or content == "" then
    return false
  end

  local ok, data = pcall(vim.fn.json_decode, content)
  if not ok then
    vim.notify("Failed to decode annotations file: " .. tostring(data), vim.log.levels.WARN)
    return false
  end

  return M.deserialize_annotations(data)
end

---Generate markdown content for annotations
---@return string|nil content
---@return number count
function M.generate_markdown_content()
  local grouped = {} ---@type table<string, Annotation[]>

  for _, annotation in pairs(core.annotations) do
    local file = annotation.file ~= "" and annotation.file or "[unsaved buffer]"
    grouped[file] = grouped[file] or {}
    table.insert(grouped[file], annotation)
  end

  if vim.tbl_isempty(grouped) then
    return nil, 0
  end

  local lines = { "# Code Review Annotations", "" }
  local count = 0

  for file, file_annotations in pairs(grouped) do
    table.sort(file_annotations, function(a, b)
      return a.start_line < b.start_line
    end)

    for _, annotation in ipairs(file_annotations) do
      count = count + 1
      table.insert(lines, string.format("## File: %sL%d:L%d", file, annotation.start_line, annotation.end_line))
      table.insert(lines, "")

      local ext = file:match("%.([^%.]+)$") or ""
      table.insert(lines, "```" .. ext)
      for _, content_line in ipairs(annotation.original_content) do
        table.insert(lines, content_line)
      end
      table.insert(lines, "```")
      table.insert(lines, "")
      table.insert(lines, "**Comment:** " .. annotation.comment)
      table.insert(lines, "")
      table.insert(lines, "---")
      table.insert(lines, "")
    end
  end

  if #lines >= 2 then
    table.remove(lines)
    table.remove(lines)
  end

  return table.concat(lines, "\n"), count
end

---Parse markdown file and extract annotations
---@param content string
---@return table[]
function M.parse_markdown_annotations(content)
  local result = {}
  local lines = vim.split(content, "\n")

  local current = nil
  local in_code_block = false
  local code_lines = {}

  for _, line in ipairs(lines) do
    local file, start_l, end_l = line:match("^## File: (.+)L(%d+):L(%d+)")
    if file and start_l and end_l then
      if current then
        current.original_content = code_lines
        table.insert(result, current)
      end
      current = {
        file = file,
        start_line = tonumber(start_l),
        end_line = tonumber(end_l),
        original_content = {},
        comment = "",
      }
      code_lines = {}
      in_code_block = false
    elseif current then
      if line:match("^```") then
        in_code_block = not in_code_block
      elseif in_code_block then
        table.insert(code_lines, line)
      elseif line:match("^%*%*Comment:%*%*") then
        current.comment = line:gsub("^%*%*Comment:%*%* ", "")
        current.original_content = code_lines
        table.insert(result, current)
        current = nil
        code_lines = {}
      end
    end
  end

  if current and current.comment ~= "" then
    current.original_content = code_lines
    table.insert(result, current)
  end

  return result
end

return M
