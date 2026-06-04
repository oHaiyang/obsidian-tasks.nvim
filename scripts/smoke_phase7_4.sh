#!/usr/bin/env sh
set -eu

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SMOKE_LUA="$(mktemp)"
trap 'rm -f "$SMOKE_LUA"' EXIT

cat > "$SMOKE_LUA" <<'LUA'
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/Nested", "p")
local uv = vim.uv or vim.loop
root = uv.fs_realpath(root) or root

local function write(path, lines)
  vim.fn.writefile(lines, path)
end

local function descriptions()
  local items = {}
  for _, task in ipairs(require("obsidian-tasks.cache").tasks({
    config = require("obsidian-tasks").config,
    use_cache = true,
  })) do
    items[task.description] = true
  end
  return items
end

local function has(description)
  return descriptions()[description] == true
end

local a = root .. "/A.md"
local b = root .. "/B.md"
local c = root .. "/Nested/C.md"
local d = root .. "/Nested/D.md"
local e = root .. "/E.md"

write(a, {
  "- [ ] #task Alpha",
})

local tasks = require("obsidian-tasks")
tasks.setup({
  vault_path = root,
  global_filter = "#task",
  cache = {
    enabled = true,
    watch = true,
    watch_debounce_ms = 0,
  },
})

assert(vim.api.nvim_get_commands({}).ObsidianTasksStartCacheWatcher)
assert(vim.api.nvim_get_commands({}).ObsidianTasksStopCacheWatcher)

local cache = require("obsidian-tasks.cache")
cache.refresh({ config = tasks.config })
assert(has("#task Alpha"), vim.inspect(descriptions()))

write(b, {
  "- [ ] #task Beta",
})
assert(cache.on_fs_event("B.md", { rename = true }, { config = tasks.config }) == true)
assert(has("#task Beta"), vim.inspect(descriptions()))

write(b, {
  "- [ ] #task Beta updated",
})
assert(cache.on_fs_event("B.md", { change = true }, { config = tasks.config }) == true)
assert(has("#task Beta updated"), vim.inspect(descriptions()))
assert(not has("#task Beta"), vim.inspect(descriptions()))

write(c, {
  "- [ ] #task Nested",
})
assert(cache.on_fs_event("Nested/C.md", { rename = true }, { config = tasks.config }) == true)
assert(has("#task Nested"), vim.inspect(descriptions()))

vim.fn.delete(a)
assert(cache.on_fs_event("A.md", { rename = true }, { config = tasks.config }) == true)
assert(not has("#task Alpha"), vim.inspect(descriptions()))

tasks.config.cache.watch_debounce_ms = 20
write(d, {
  "- [ ] #task Debounced",
})
assert(cache.on_fs_event("Nested/D.md", { change = true }, { config = tasks.config }) == true)
assert(not has("#task Debounced"), vim.inspect(descriptions()))
assert(vim.wait(200, function()
  return has("#task Debounced")
end), vim.inspect(descriptions()))

cache.stop_watcher()
local stats = cache.stats()
assert(stats.watcher.status == "stopped", vim.inspect(stats.watcher))

cache.clear()
write(e, {
  "- [ ] #task Cold event",
})
tasks.config.cache.watch_debounce_ms = 0
assert(cache.on_fs_event("E.md", { rename = true }, { config = tasks.config }) == true)
stats = cache.stats()
assert(stats.status == "cold", vim.inspect(stats))
assert(stats.task_count == 0, vim.inspect(stats))
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase7-4.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
