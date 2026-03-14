#!/usr/bin/env -S nvim -l
-- Minimal init for running tests

-- Set up runtime path
vim.opt.rtp:prepend(vim.fn.getcwd())

-- Bootstrap lazy.nvim for test dependencies (optional)
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Setup with test spec
require("lazy").setup({
  { dir = vim.fn.getcwd(), opts = {} },
}, {
  install = { missing = false },
  change_detection = { enabled = false },
})

-- Run tests
local function run_tests()
  print("\n=== annotate.nvim tests ===\n")

  local passed = 0
  local failed = 0

  local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
      print("✓ " .. name)
      passed = passed + 1
    else
      print("✗ " .. name .. ": " .. tostring(err))
      failed = failed + 1
    end
  end

  -- Test: Module loads
  test("Module loads without error", function()
    local ok, annotate = pcall(require, "annotate")
    assert(ok, "Failed to load module: " .. tostring(annotate))
    assert(annotate ~= nil, "Module is nil")
  end)

  -- Test: Setup function exists
  test("Setup function exists", function()
    local annotate = require("annotate")
    assert(type(annotate.setup) == "function", "setup is not a function")
  end)

  -- Test: API functions exist
  test("API functions are accessible", function()
    local annotate = require("annotate")
    assert(type(annotate.add) == "function", "add is not a function")
    assert(type(annotate.delete_under_cursor) == "function", "delete_under_cursor is not a function")
    assert(type(annotate.get_all) == "function", "get_all is not a function")
  end)

  -- Test: Config module
  test("Config module loads", function()
    local ok, config = pcall(require, "annotate.config")
    assert(ok, "Failed to load config: " .. tostring(config))
    assert(type(config.get) == "function", "get is not a function")
    assert(type(config.setup) == "function", "setup is not a function")
  end)

  -- Test: Core module
  test("Core module loads", function()
    local ok, core = pcall(require, "annotate.core")
    assert(ok, "Failed to load core: " .. tostring(core))
    assert(type(core.annotations) == "table", "annotations is not a table")
    assert(type(core.init) == "function", "init is not a function")
  end)

  -- Test: Health module
  test("Health module loads", function()
    local ok, health = pcall(require, "annotate.health")
    assert(ok, "Failed to load health: " .. tostring(health))
    assert(type(health.check) == "function", "check is not a function")
  end)

  -- Test: Commands registered after setup
  test("Commands are registered", function()
    require("annotate").setup({})
    local cmds = vim.api.nvim_get_commands({})
    assert(cmds["Annotate"] ~= nil, "Annotate command not registered")
    assert(cmds["AnnotateAdd"] ~= nil, "AnnotateAdd command not registered")
  end)

  -- Test: get_all returns empty initially
  test("get_all returns empty list initially", function()
    local core = require("annotate.core")
    -- Clear any existing annotations
    core.annotations = {}
    local all = require("annotate").get_all()
    assert(type(all) == "table", "get_all should return a table")
    assert(#all == 0, "Should have no annotations initially")
  end)

  -- Test: default virtual_text prefix is "> "
  test("virtual_text.prefix defaults to '> '", function()
    local config = require("annotate.config")
    config.setup({})
    local cfg = config.get()
    assert(cfg.virtual_text ~= nil, "virtual_text config should exist")
    assert(cfg.virtual_text.prefix == "> ", "default prefix should be '> ', got: " .. tostring(cfg.virtual_text.prefix))
  end)

  -- Test: virtual_text prefix is configurable
  test("virtual_text.prefix can be customized", function()
    local config = require("annotate.config")
    config.setup({ virtual_text = { prefix = "// " } })
    local cfg = config.get()
    assert(cfg.virtual_text.prefix == "// ", "prefix should be '// ', got: " .. tostring(cfg.virtual_text.prefix))
    -- Reset to defaults
    config.setup({})
  end)

  -- Test: virtual_text prefix is a string
  test("virtual_text.prefix is a string", function()
    local config = require("annotate.config")
    config.setup({})
    local cfg = config.get()
    assert(type(cfg.virtual_text.prefix) == "string", "prefix should be a string")
  end)

  -- Test: wrap_at config preserved alongside prefix
  test("virtual_text wrap_at preserved when prefix configured", function()
    local config = require("annotate.config")
    config.setup({ virtual_text = { prefix = "* " } })
    local cfg = config.get()
    assert(cfg.virtual_text.wrap_at == 80, "wrap_at should still default to 80")
    assert(cfg.virtual_text.prefix == "* ", "prefix should be '* '")
    -- Reset to defaults
    config.setup({})
  end)

  print("\n=== Results: " .. passed .. " passed, " .. failed .. " failed ===\n")

  if failed > 0 then
    os.exit(1)
  end
end

run_tests()
