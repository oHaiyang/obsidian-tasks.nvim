#!/usr/bin/env sh
set -eu

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SMOKE_LUA="$(mktemp)"
trap 'rm -f "$SMOKE_LUA"' EXIT

cat > "$SMOKE_LUA" <<'LUA'
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/Projects", "p")
vim.fn.mkdir(root .. "/Other", "p")
local uv = vim.uv or vim.loop
root = uv.fs_realpath(root) or root

local board = root .. "/Projects/Board.md"
local tasks_file = root .. "/Projects/Tasks.md"
local other_file = root .. "/Other/Tasks.md"

vim.fn.writefile({
  "---",
  "TQ_extra_instructions: |-",
  "  folder includes {{query.file.folder}}",
  "TQ_show_task_count: true",
  "---",
  "# Board",
  "",
  "Intro paragraph stays markdown.",
  "",
  "```lua",
  "print('keep me')",
  "```",
  "",
  "```tasks",
  "# name: Project Open",
  "not done",
  "sort by due",
  "```",
  "",
  "Middle paragraph stays markdown.",
  "",
  "```tasks",
  "# name: Broken Query",
  "definitely unsupported",
  "```",
}, board)

vim.fn.writefile({
  "# Project Tasks",
  "- [ ] #task Alpha 📅 2026-06-05",
  "- [ ] #task Beta 📅 2026-06-06",
  "- [x] #task Done 📅 2026-06-04",
}, tasks_file)

vim.fn.writefile({
  "# Other Tasks",
  "- [ ] #task Gamma 📅 2026-06-05",
}, other_file)

local tasks = require("obsidian-tasks")
tasks.setup({
  vault_path = root,
  global_filter = "#task",
})

local function text()
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end

local function assert_contains(haystack, needle)
  assert(haystack:find(needle, 1, true), haystack .. "\nmissing: " .. needle)
end

local function assert_not_contains(haystack, needle)
  assert(not haystack:find(needle, 1, true), haystack .. "\nunexpected: " .. needle)
end

vim.cmd("ObsidianTasks " .. vim.fn.fnameescape(board))
local buf = vim.api.nvim_get_current_buf()
assert(vim.api.nvim_buf_get_name(buf):find("obsidian%-tasks://board/"), vim.api.nvim_buf_get_name(buf))
assert(vim.bo[buf].filetype == "markdown", vim.bo[buf].filetype)
assert(vim.bo[buf].readonly == true, "board buffer must be readonly")
assert(vim.bo[buf].modifiable == false, "board buffer must be nonmodifiable")
assert(vim.b[buf].obsidian_tasks_board == true, "board marker missing")

local rendered = text()
assert_contains(rendered, "# Board")
assert_contains(rendered, "Intro paragraph stays markdown.")
assert_contains(rendered, "```lua")
assert_contains(rendered, "print('keep me')")
assert_contains(rendered, "## Project Open")
assert_contains(rendered, "Alpha")
assert_contains(rendered, "Beta")
assert_not_contains(rendered, "Gamma")
assert_not_contains(rendered, "sort by due")
assert_not_contains(rendered, "definitely unsupported\n```")
assert_contains(rendered, "## Broken Query")
assert_contains(rendered, "Query errors:")
assert_contains(rendered, "Unsupported query instruction")

local alpha_row
for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
  if line:find("Alpha", 1, true) then
    alpha_row = row
    break
  end
end
assert(alpha_row, rendered)
vim.api.nvim_win_set_cursor(0, { alpha_row, 0 })
assert(tasks.toggle_task_at_cursor())

local source_after_toggle = table.concat(vim.fn.readfile(tasks_file), "\n")
assert_contains(source_after_toggle, "- [x] #task Alpha")
assert(vim.bo[buf].readonly == true, "board buffer lost readonly after toggle")
assert(vim.bo[buf].modifiable == false, "board buffer lost nonmodifiable after toggle")
assert_contains(text(), "1. [x]")

vim.cmd("edit " .. vim.fn.fnameescape(board))
vim.cmd("ObsidianTasks")
local current_text = text()
assert(vim.api.nvim_buf_get_name(0):find("obsidian%-tasks://board/"), vim.api.nvim_buf_get_name(0))
assert_contains(current_text, "Middle paragraph stays markdown.")
assert_contains(current_text, "Project Open")

local no_query_file = root .. "/Projects/NoQueries.md"
vim.fn.writefile({
  "# No Queries",
  "",
  "This file has no task query blocks.",
}, no_query_file)
vim.cmd("ObsidianTasks " .. vim.fn.fnameescape(no_query_file))
assert_contains(text(), "No tasks query blocks found")
assert(vim.bo[0].filetype == "markdown", vim.bo[0].filetype)
LUA

nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "lua local ok, err = pcall(dofile, [[$SMOKE_LUA]]); if not ok then vim.api.nvim_err_writeln(tostring(err)); vim.cmd('cquit') end" \
  -c "qa!"
