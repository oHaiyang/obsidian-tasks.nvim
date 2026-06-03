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
  },
  queries = {
    all = "not done",
  },
})

assert(vim.fn.exists(":ObsidianTasksRefreshCache") == 2)
assert(vim.fn.exists(":ObsidianTasksClearCache") == 2)
assert(vim.fn.exists(":ObsidianTasksCacheInfo") == 2)

local cache = require("obsidian-tasks.cache")
local task_search = require("obsidian-tasks.task_search")
local completion = require("obsidian-tasks.completion")

local function buffer_text()
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end

local function has_word(items, word)
  for _, item in ipairs(items) do
    if item.word == word then
      return true
    end
  end
  return false
end

local stats = cache.stats()
assert(stats.status == "cold", vim.inspect(stats))

local cached = cache.tasks({})
assert(#cached == 2, vim.inspect(cached))
stats = cache.stats()
assert(stats.status == "warm", vim.inspect(stats))
assert(stats.file_count == 2, vim.inspect(stats))
assert(stats.task_count == 2, vim.inspect(stats))

tasks.open_query("all")
local initial_text = buffer_text()
assert(initial_text:find("Alpha", 1, true), initial_text)
assert(initial_text:find("Beta", 1, true), initial_text)
assert(not initial_text:find("Gamma", 1, true), initial_text)

vim.fn.writefile({
  "# A",
  "",
  "- [ ] #task Alpha 🆔 alpha-id",
  "- [ ] #task Gamma 🆔 gamma-id",
}, a)

local still_cached = cache.tasks({})
assert(#still_cached == 2, vim.inspect(still_cached))

tasks.open_query("all")
local stale_text = buffer_text()
assert(stale_text:find("Alpha", 1, true), stale_text)
assert(stale_text:find("Beta", 1, true), stale_text)
assert(not stale_text:find("Gamma", 1, true), stale_text)

local updated = cache.update_file(a)
assert(#updated == 2, vim.inspect(updated))
local refreshed = cache.tasks({})
assert(#refreshed == 3, vim.inspect(refreshed))

tasks.open_query("all")
local refreshed_text = buffer_text()
assert(refreshed_text:find("Alpha", 1, true), refreshed_text)
assert(refreshed_text:find("Beta", 1, true), refreshed_text)
assert(refreshed_text:find("Gamma", 1, true), refreshed_text)

local candidates = task_search.candidate_tasks({ vault_path = root })
assert(#candidates == 3, vim.inspect(candidates))

local id_items = completion.task_id_items({ vault_path = root })
assert(has_word(id_items, "alpha-id"), vim.inspect(id_items))
assert(has_word(id_items, "beta-id"), vim.inspect(id_items))
assert(has_word(id_items, "gamma-id"), vim.inspect(id_items))

cache.clear()
stats = cache.stats()
assert(stats.status == "cold", vim.inspect(stats))
assert(stats.file_count == 0, vim.inspect(stats))
assert(stats.task_count == 0, vim.inspect(stats))

local rewarmed = cache.tasks({})
assert(#rewarmed == 3, vim.inspect(rewarmed))

vim.fn.writefile({
  "# B",
  "",
  "- [ ] #task Beta 🆔 beta-id",
  "- [ ] #task Delta 🆔 delta-id",
}, b)

local direct_scan = cache.tasks({
  vault_path = root,
  global_filter = "#task",
  use_cache = false,
})
assert(#direct_scan == 4, vim.inspect(direct_scan))

local cached_after_direct_scan = cache.tasks({})
assert(#cached_after_direct_scan == 3, vim.inspect(cached_after_direct_scan))

cache.refresh()
assert(cache.stats().task_count == 4, vim.inspect(cache.stats()))
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase7-1.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
