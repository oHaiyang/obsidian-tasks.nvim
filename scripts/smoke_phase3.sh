#!/usr/bin/env sh
set -eu

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SMOKE_LUA="$(mktemp)"
trap 'rm -f "$SMOKE_LUA"' EXIT

cat > "$SMOKE_LUA" <<'LUA'
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/Projects", "p")

local dashboard = root .. "/Dashboard.md"
local tasks_file = root .. "/Projects/Tasks.md"

vim.fn.writefile({
  "# Dashboard",
  "",
  "~~~tasks",
  "# name: Due soon",
  "# id: due-soon",
  "not done",
  "due on or before 2026-05-20",
  "sort by due",
  "~~~",
  "",
  "~~~tasks",
  "# name: No ID Query",
  "not done",
  "~~~",
}, dashboard)

vim.fn.writefile({
  "# Tasks",
  "- [ ] #task Earlier 📅 2026-05-15",
  "- [ ] #task Later 📅 2026-05-30",
  "- [x] #task Done 📅 2026-05-14",
}, tasks_file)

local query_block = require("obsidian-tasks.query_block")
local block_sources = query_block.scan_file(dashboard)
assert(#block_sources == 2, vim.inspect(block_sources))
assert(block_sources[1].id == "due-soon", vim.inspect(block_sources[1]))
assert(block_sources[1].name == "Due soon", vim.inspect(block_sources[1]))
assert(block_sources[1].source_line == 3, vim.inspect(block_sources[1]))
assert(block_sources[2].id == "no-id-query", vim.inspect(block_sources[2]))

local tasks = require("obsidian-tasks")
tasks.setup({
  vault_path = root,
  global_filter = "#task",
  default_query = "due-soon",
  queries = {
    inbox = [[
not done
sort by due
]],
  },
})

local registry = require("obsidian-tasks.query_registry")
local sources = registry.get_sources({ refresh = true })
local seen = {}
for _, source in ipairs(sources) do
  seen[source.source_type .. ":" .. source.id] = true
end
assert(seen["config:inbox"], vim.inspect(sources))
assert(seen["block:due-soon"], vim.inspect(sources))
assert(seen["block:no-id-query"], vim.inspect(sources))

tasks.open()
local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(text:find("Tasks: Due soon", 1, true), text)
assert(text:find("Earlier", 1, true), text)
assert(not text:find("Later", 1, true), text)
assert(not text:find("Done", 1, true), text)

require("obsidian-tasks.panel").go_to_query_source()
assert(vim.api.nvim_buf_get_name(0):match("Dashboard%.md$"), vim.api.nvim_buf_get_name(0))
assert(vim.api.nvim_win_get_cursor(0)[1] == 3, vim.inspect(vim.api.nvim_win_get_cursor(0)))

vim.api.nvim_win_set_cursor(0, { 6, 0 })
tasks.run_query_at_cursor()
text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(text:find("Tasks: Due soon", 1, true), text)
assert(text:find("Earlier", 1, true), text)

vim.cmd("edit " .. vim.fn.fnameescape(dashboard))
require("obsidian-tasks.preview").refresh_buffer()
local marks = vim.api.nvim_buf_get_extmarks(
  0,
  require("obsidian-tasks.preview").namespace,
  0,
  -1,
  { details = true }
)
assert(#marks == 2, vim.inspect(marks))
assert(vim.inspect(marks):find("Tasks preview", 1, true), vim.inspect(marks))

assert(vim.api.nvim_get_commands({}).ObsidianTasksRefreshQueries)
assert(vim.api.nvim_get_commands({}).ObsidianTasksRunBlock)
assert(vim.api.nvim_get_commands({}).ObsidianTasksPreviewToggle)
assert(vim.api.nvim_get_commands({}).ObsidianTasksPreviewRefresh)
LUA

nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
