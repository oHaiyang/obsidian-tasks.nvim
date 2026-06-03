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
  return table.concat(vim.api.nvim_buf_get_lines(buf or 0, 0, -1, false), "\n")
end

cache.refresh()
assert(cache.stats().task_count == 2, vim.inspect(cache.stats()))

tasks.open_query("all")
local active_buf = vim.api.nvim_get_current_buf()
local active_initial = buffer_text(active_buf)
assert(active_initial:find("Alpha", 1, true), active_initial)
assert(active_initial:find("Beta", 1, true), active_initial)
assert(not active_initial:find("Gamma", 1, true), active_initial)

tasks.open_query("beta", { pinned = true })
local pinned_buf = vim.api.nvim_get_current_buf()
local pinned_initial = buffer_text(pinned_buf)
assert(pinned_buf ~= active_buf, tostring(pinned_buf) .. " == " .. tostring(active_buf))
assert(not pinned_initial:find("Alpha", 1, true), pinned_initial)
assert(pinned_initial:find("Beta", 1, true), pinned_initial)
assert(not pinned_initial:find("Gamma", 1, true), pinned_initial)

vim.fn.writefile({
  "# A",
  "",
  "- [ ] #task Alpha 🆔 alpha-id",
  "- [ ] #task Gamma 🆔 gamma-id",
}, a)

assert(display.refresh_tasks_view({ buffer = active_buf, notify = false }))
local stale_active = buffer_text(active_buf)
assert(stale_active:find("Alpha", 1, true), stale_active)
assert(stale_active:find("Beta", 1, true), stale_active)
assert(not stale_active:find("Gamma", 1, true), stale_active)

cache.update_file(a)
assert(display.refresh_tasks_view({ buffer = active_buf, notify = false }))
local refreshed_active = buffer_text(active_buf)
assert(refreshed_active:find("Alpha", 1, true), refreshed_active)
assert(refreshed_active:find("Beta", 1, true), refreshed_active)
assert(refreshed_active:find("Gamma", 1, true), refreshed_active)

assert(display.refresh_tasks_view({ buffer = pinned_buf, notify = false }))
local refreshed_pinned = buffer_text(pinned_buf)
assert(not refreshed_pinned:find("Alpha", 1, true), refreshed_pinned)
assert(refreshed_pinned:find("Beta", 1, true), refreshed_pinned)
assert(not refreshed_pinned:find("Gamma", 1, true), refreshed_pinned)

assert(vim.fn.exists(":ObsidianTasksRefresh") == 2)

vim.api.nvim_set_current_buf(active_buf)
vim.fn.writefile({
  "# B",
  "",
  "- [ ] #task Beta 🆔 beta-id",
  "- [ ] #task Delta 🆔 delta-id",
}, b)
assert(not buffer_text(active_buf):find("Delta", 1, true), buffer_text(active_buf))
vim.cmd("ObsidianTasksRefreshCache!")
local cache_refreshed_active = buffer_text(active_buf)
assert(cache_refreshed_active:find("Delta", 1, true), cache_refreshed_active)

local line_count = vim.api.nvim_buf_line_count(active_buf)
vim.api.nvim_buf_set_lines(active_buf, line_count, line_count, false, { "local unsaved edit" })
assert(vim.api.nvim_get_option_value("modified", { buf = active_buf }))
assert(display.refresh_tasks_view({ buffer = active_buf, notify = false }) == false)
assert(buffer_text(active_buf):find("local unsaved edit", 1, true), buffer_text(active_buf))
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase7-3.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
