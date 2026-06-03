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
local outside = vim.fn.tempname() .. ".md"

vim.fn.writefile({
  "# A",
  "",
  "- [ ] #task Alpha 🆔 alpha-id",
}, a)

vim.fn.writefile({
  "# B",
  "",
  "- [ ] #task Beta 🆔 beta-id 📅 2026-06-03",
}, b)

vim.fn.writefile({
  "# Outside",
  "",
  "- [ ] #task Outside",
}, outside)

local tasks = require("obsidian-tasks")
tasks.setup({
  vault_path = root,
  global_filter = "#task",
  cache = {
    enabled = true,
    auto_update_on_write = true,
    debounce_ms = 0,
  },
  queries = {
    all = "not done",
  },
})

local cache = require("obsidian-tasks.cache")
local core = require("obsidian-tasks.core")

local function buffer_text()
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end

local function find_task(description)
  for _, task in ipairs(cache.tasks({})) do
    if (task.description or ""):find(description, 1, true) then
      return task
    end
  end
  return nil
end

assert(cache.is_path_in_vault(a, root))
assert(not cache.is_path_in_vault(outside, root))

cache.refresh()
assert(cache.stats().status == "warm", vim.inspect(cache.stats()))
assert(cache.stats().task_count == 2, vim.inspect(cache.stats()))

tasks.open_query("all")
local initial_text = buffer_text()
assert(initial_text:find("Alpha", 1, true), initial_text)
assert(initial_text:find("Beta", 1, true), initial_text)
assert(not initial_text:find("Gamma", 1, true), initial_text)

vim.cmd("edit " .. vim.fn.fnameescape(a))
vim.api.nvim_buf_set_lines(0, 3, 3, false, { "- [ ] #task Gamma 🆔 gamma-id" })
vim.cmd("write")

assert(cache.stats().task_count == 3, vim.inspect(cache.stats()))
tasks.open_query("all")
local refreshed_text = buffer_text()
assert(refreshed_text:find("Alpha", 1, true), refreshed_text)
assert(refreshed_text:find("Beta", 1, true), refreshed_text)
assert(refreshed_text:find("Gamma", 1, true), refreshed_text)

vim.cmd("edit " .. vim.fn.fnameescape(outside))
vim.api.nvim_buf_set_lines(0, 3, 3, false, { "- [ ] #task Outside Two" })
vim.cmd("write")
assert(cache.stats().task_count == 3, vim.inspect(cache.stats()))

local beta = find_task("Beta")
assert(beta, vim.inspect(cache.tasks({})))
assert(beta.due_date == "2026-06-03", vim.inspect(beta))
assert(core.apply_postpone_changes(beta, "+1"))
local postponed = find_task("Beta")
assert(postponed and postponed.due_date == "2026-06-04", vim.inspect(postponed))

cache.clear()
assert(cache.stats().status == "cold", vim.inspect(cache.stats()))
vim.cmd("edit " .. vim.fn.fnameescape(a))
vim.api.nvim_buf_set_lines(0, 4, 4, false, { "- [ ] #task Delta 🆔 delta-id" })
vim.cmd("write")
assert(cache.stats().status == "cold", vim.inspect(cache.stats()))
assert(cache.stats().task_count == 0, vim.inspect(cache.stats()))

tasks.open_query("all")
local rewarmed_text = buffer_text()
assert(rewarmed_text:find("Delta", 1, true), rewarmed_text)
assert(cache.stats().status == "warm", vim.inspect(cache.stats()))

tasks.setup({
  vault_path = root,
  global_filter = "#task",
  cache = {
    enabled = true,
    auto_update_on_write = false,
  },
  queries = {
    all = "not done",
  },
})
cache.refresh()
local before_disabled_write = cache.stats().task_count
vim.cmd("edit " .. vim.fn.fnameescape(a))
vim.api.nvim_buf_set_lines(0, 5, 5, false, { "- [ ] #task Epsilon 🆔 epsilon-id" })
vim.cmd("write")
assert(cache.stats().task_count == before_disabled_write, vim.inspect(cache.stats()))
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase7-2.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
