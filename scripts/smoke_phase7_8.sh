#!/usr/bin/env sh
set -eu

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SMOKE_LUA="$(mktemp)"
trap 'rm -f "$SMOKE_LUA"' EXIT

cat > "$SMOKE_LUA" <<'LUA'
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local uv = vim.uv or vim.loop
root = uv.fs_realpath(root) or root

local a = root .. "/A.md"
local b = root .. "/B.md"

vim.fn.writefile({
  "# A",
  "",
  "- [ ] #task Alpha 🆔 alpha-id",
}, a)

vim.fn.writefile({
  "# B",
  "",
  "- [ ] #task Beta 🆔 beta-id",
}, b)

local tasks = require("obsidian-tasks")
tasks.setup({
  vault_path = root,
  global_filter = "#task",
  cache = {
    enabled = true,
    auto_update_on_write = false,
    auto_refresh_results = true,
    refresh_results_debounce_ms = 0,
  },
  queries = {
    all = [[
not done
sort by description
]],
    beta = [[
description includes Beta
sort by description
]],
  },
})

local cache = require("obsidian-tasks.cache")
local display = require("obsidian-tasks.display")

local function buffer_text(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end

cache.refresh({ config = tasks.config })

tasks.open_query("all")
local all_buf = vim.api.nvim_get_current_buf()
local all_initial = buffer_text(all_buf)
assert(all_initial:find("Alpha", 1, true), all_initial)
assert(all_initial:find("Beta", 1, true), all_initial)
assert(not all_initial:find("Gamma", 1, true), all_initial)

tasks.open_query("beta", { pinned = true })
local beta_buf = vim.api.nvim_get_current_buf()
assert(beta_buf ~= all_buf, tostring(beta_buf) .. " == " .. tostring(all_buf))
local beta_initial = buffer_text(beta_buf)
assert(not beta_initial:find("Alpha", 1, true), beta_initial)
assert(beta_initial:find("Beta", 1, true), beta_initial)

local scratch = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(scratch)

vim.fn.writefile({
  "# A",
  "",
  "- [ ] #task Alpha 🆔 alpha-id",
  "- [ ] #task Gamma 🆔 gamma-id",
}, a)

cache.update_file(a, { config = tasks.config })
assert(vim.api.nvim_get_current_buf() == scratch, "current buffer changed")

local all_refreshed = buffer_text(all_buf)
assert(all_refreshed:find("Alpha", 1, true), all_refreshed)
assert(all_refreshed:find("Beta", 1, true), all_refreshed)
assert(all_refreshed:find("Gamma", 1, true), all_refreshed)

local beta_refreshed = buffer_text(beta_buf)
assert(not beta_refreshed:find("Alpha", 1, true), beta_refreshed)
assert(beta_refreshed:find("Beta", 1, true), beta_refreshed)
assert(not beta_refreshed:find("Gamma", 1, true), beta_refreshed)

vim.api.nvim_buf_set_lines(all_buf, -1, -1, false, { "local unsaved edit" })
assert(vim.api.nvim_get_option_value("modified", { buf = all_buf }))

vim.fn.writefile({
  "# B",
  "",
  "- [ ] #task Beta 🆔 beta-id",
  "- [ ] #task Delta 🆔 delta-id",
}, b)
cache.update_file(b, { config = tasks.config })

local all_modified = buffer_text(all_buf)
assert(all_modified:find("local unsaved edit", 1, true), all_modified)
assert(not all_modified:find("Delta", 1, true), all_modified)

local beta_after_delta = buffer_text(beta_buf)
assert(beta_after_delta:find("Beta", 1, true), beta_after_delta)
assert(not beta_after_delta:find("Delta", 1, true), beta_after_delta)

local stats = cache.stats()
assert(stats.auto_refresh_results == true, vim.inspect(stats))

tasks.config.cache.refresh_results_debounce_ms = 20
vim.api.nvim_set_option_value("modified", false, { buf = all_buf })
vim.fn.writefile({
  "# A",
  "",
  "- [ ] #task Alpha 🆔 alpha-id",
  "- [ ] #task Gamma 🆔 gamma-id",
  "- [ ] #task Epsilon 🆔 epsilon-id",
}, a)
cache.update_file(a, { config = tasks.config })
assert(not buffer_text(all_buf):find("Epsilon", 1, true), buffer_text(all_buf))
assert(vim.wait(200, function()
  return buffer_text(all_buf):find("Epsilon", 1, true) ~= nil
end), buffer_text(all_buf))

local summary = display.refresh_all_task_views({ notify = false })
assert(summary.refreshed >= 2, vim.inspect(summary))
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase7-8.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
