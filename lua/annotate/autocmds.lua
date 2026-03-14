-- Autocommands for annotate.nvim

local config = require("annotate.config")
local core = require("annotate.core")
local persistence = require("annotate.persistence")
local render = require("annotate.render")

local M = {}

-- Pending debounce timers keyed by bufnr
local pending_timers = {}

---Cancel and close a pending render timer for a buffer, if any
---@param bufnr number
local function cancel_pending_timer(bufnr)
  local timer = pending_timers[bufnr]
  if timer and not timer:is_closing() then
    timer:stop()
    timer:close()
  end
  pending_timers[bufnr] = nil
end

function M.setup()
  local group = vim.api.nvim_create_augroup("Annotate", { clear = true })

  -- Handle text changes - debounced to avoid re-rendering on every keystroke
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    callback = function(args)
      local bufnr = args.buf
      cancel_pending_timer(bufnr)

      local uv = vim.uv or vim.loop
      local timer = uv.new_timer()
      pending_timers[bufnr] = timer
      timer:start(
        150,
        0,
        vim.schedule_wrap(function()
          pending_timers[bufnr] = nil
          if not timer:is_closing() then
            timer:close()
          end
          if vim.api.nvim_buf_is_valid(bufnr) then
            render.render_buffer_annotations(bufnr)
          end
        end)
      )
    end,
  })

  -- Handle buffer enter - load from disk if needed, re-attach annotations
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(args)
      local bufnr = args.buf
      local filepath = vim.api.nvim_buf_get_name(bufnr)

      if filepath == "" then
        return
      end

      local cfg = config.get()
      local cwd = vim.fn.getcwd()
      if cfg.persist.enabled and core.loaded_for_cwd ~= cwd then
        core.loaded_for_cwd = cwd
        persistence.load_from_disk()
      end

      local has_annotations_for_file = false
      for _, annotation in pairs(core.annotations) do
        if annotation.file == filepath then
          has_annotations_for_file = true
          if annotation.bufnr ~= bufnr or not annotation.extmark_id then
            render.reattach_annotations_to_buffer(bufnr, filepath)
            return
          end
        end
      end

      if has_annotations_for_file then
        render.render_buffer_annotations(bufnr)
      end
    end,
  })

  -- Handle buffer delete/wipe - cancel pending timers and clear rendering references
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    callback = function(args)
      cancel_pending_timer(args.buf)
      render.on_buffer_delete(args.buf)
    end,
  })
end

return M
