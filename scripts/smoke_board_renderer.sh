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
  "## Nested Section",
  "",
  "```tasks",
  "not done",
  "group by priority",
  "```",
  "",
  "> [!danger] Overdue",
  "> ```tasks",
  "> # name: Callout Open",
  "> not done",
  "> description includes Beta",
  "> ```",
  "",
  "```tasks",
  "description includes Done",
  "```",
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
local board_module = require("obsidian-tasks.board")

local function text()
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end

local function assert_contains(haystack, needle)
  assert(haystack:find(needle, 1, true), haystack .. "\nmissing: " .. needle)
end

local function assert_not_contains(haystack, needle)
  assert(not haystack:find(needle, 1, true), haystack .. "\nunexpected: " .. needle)
end

local function find_row(buf, needle)
  for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:find(needle, 1, true) then
      return row
    end
  end
  return nil
end

local function find_quoted_row(buf, needle)
  for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:sub(1, 1) == ">" and line:find(needle, 1, true) then
      return row
    end
  end
  return nil
end

local function first_float_text()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative ~= "" then
      local float_buf = vim.api.nvim_win_get_buf(win)
      return table.concat(vim.api.nvim_buf_get_lines(float_buf, 0, -1, false), "\n"), win, float_buf
    end
  end
  return nil
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
assert_contains(rendered, "Middle paragraph stays markdown.")
assert_contains(rendered, "## Nested Section")
assert_contains(rendered, "### Normal")
assert_not_contains(rendered, "\n## Normal\n")
assert_contains(rendered, "> [!danger] Overdue")
assert_contains(rendered, "> ### Callout Open")
assert_contains(rendered, "> 5. [ ] #task Beta")
assert_contains(rendered, "```lua")
assert_contains(rendered, "print('keep me')")
assert_contains(rendered, "## Project Open")
assert_contains(rendered, "Alpha")
assert_contains(rendered, "Beta")
assert_contains(rendered, "Done")
assert_not_contains(rendered, "Tasks query at")
assert_not_contains(rendered, "Gamma")
assert_contains(rendered, "Showing 2 tasks")
assert_not_contains(rendered, "sort by due")
assert_not_contains(rendered, "```tasks")
assert_not_contains(rendered, "definitely unsupported\n```")
assert_contains(rendered, "### Broken Query")
assert_contains(rendered, "Query errors:")
assert_contains(rendered, "Unsupported query instruction")

assert_contains(rendered, "Board keys:")
local help_kmap = vim.fn.maparg("?", "n", false, true)
assert(type(help_kmap) == "table" and help_kmap.callback ~= nil, "board ? mapping missing")
help_kmap.callback()
local help_text, help_win = first_float_text()
assert(help_win, "board help did not open")
assert_contains(help_text, "Tasks board keymaps")
assert_contains(help_text, "<Space>")
assert_contains(help_text, "Toggle task status")
assert_contains(help_text, "]t")
assert_contains(help_text, "[t")
help_kmap.callback()
assert(first_float_text() == nil, "board help should close when ? is pressed again")

local next_task_kmap = vim.fn.maparg("]t", "n", false, true)
local previous_task_kmap = vim.fn.maparg("[t", "n", false, true)
assert(type(next_task_kmap) == "table" and next_task_kmap.callback ~= nil, "board ]t mapping missing")
assert(type(previous_task_kmap) == "table" and previous_task_kmap.callback ~= nil, "board [t mapping missing")
local jump_start_row = find_row(buf, "Intro paragraph")
assert(jump_start_row, rendered)
vim.api.nvim_win_set_cursor(0, { jump_start_row, 0 })
next_task_kmap.callback()
local jumped_next = vim.api.nvim_get_current_line()
assert(jumped_next:find("Alpha", 1, true), jumped_next)
next_task_kmap.callback()
local jumped_next_again = vim.api.nvim_get_current_line()
assert(jumped_next_again:find("Beta", 1, true), jumped_next_again)
previous_task_kmap.callback()
local jumped_previous = vim.api.nvim_get_current_line()
assert(jumped_previous:find("Alpha", 1, true), jumped_previous)

local kmap = vim.fn.maparg("K", "n", false, true)
assert(type(kmap) == "table" and kmap.callback ~= nil, "board K mapping missing")
local project_row = find_row(buf, "Project Open")
assert(project_row, rendered)
vim.api.nvim_win_set_cursor(0, { project_row, 0 })
vim.cmd("ObsidianTasksQuery")
local query_text, query_win = first_float_text()
assert(query_win, "query hover did not open")
assert_contains(query_text, "Tasks query")
assert_contains(query_text, "Projects/Board.md:")
assert_contains(query_text, "```tasks")
assert_contains(query_text, "# name: Project Open")
assert_contains(query_text, "not done")
assert_contains(query_text, "sort by due")
vim.cmd("normal! j")
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
assert(not vim.api.nvim_win_is_valid(query_win), "query hover should close on cursor move")
assert(first_float_text() == nil, "query hover should not remain after cursor move")

local intro_row = find_row(buf, "Intro paragraph")
assert(intro_row, rendered)
vim.api.nvim_win_set_cursor(0, { intro_row, 0 })
assert(board_module.show_query({ buffer = buf }) == nil, "ordinary markdown should not show a query hover")
assert(first_float_text() == nil, "ordinary markdown should not leave a query hover open")

local alpha_row = find_row(buf, "Alpha")
assert(alpha_row, rendered)
vim.api.nvim_win_set_cursor(0, { alpha_row, 0 })
assert(tasks.toggle_task_at_cursor())

local source_after_toggle = table.concat(vim.fn.readfile(tasks_file), "\n")
assert_contains(source_after_toggle, "- [x] #task Alpha")
local refreshed_buf = vim.api.nvim_get_current_buf()
assert(vim.api.nvim_buf_get_name(refreshed_buf):find("obsidian%-tasks://board/"), vim.api.nvim_buf_get_name(refreshed_buf))
assert(vim.b[refreshed_buf].obsidian_tasks_board == true, "refreshed board marker missing")
assert(vim.bo[refreshed_buf].readonly == true, "board buffer lost readonly after toggle")
assert(vim.bo[refreshed_buf].modifiable == false, "board buffer lost nonmodifiable after toggle")
local after_toggle_text = text()
assert_not_contains(after_toggle_text, "Alpha")
assert_contains(after_toggle_text, "Beta")

local beta_row = find_row(refreshed_buf, "Beta")
assert(beta_row, after_toggle_text)
vim.api.nvim_win_set_cursor(0, { beta_row, 0 })
assert(tasks.postpone_task_at_cursor("2026-06-07"))

local source_after_postpone = table.concat(vim.fn.readfile(tasks_file), "\n")
assert_contains(source_after_postpone, "- [ ] #task Beta 📅 2026-06-07")
local after_postpone_buf = vim.api.nvim_get_current_buf()
assert(vim.api.nvim_buf_get_name(after_postpone_buf):find("obsidian%-tasks://board/"), vim.api.nvim_buf_get_name(after_postpone_buf))
assert(vim.b[after_postpone_buf].obsidian_tasks_board == true, "postponed board marker missing")
assert(vim.bo[after_postpone_buf].readonly == true, "board buffer lost readonly after postpone")
assert(vim.bo[after_postpone_buf].modifiable == false, "board buffer lost nonmodifiable after postpone")
local after_postpone_text = text()
assert_contains(after_postpone_text, "Beta")
assert_contains(after_postpone_text, "2026-06-07")
local quoted_beta_row = find_quoted_row(after_postpone_buf, "Beta")
assert(quoted_beta_row, after_postpone_text)
vim.api.nvim_win_set_cursor(0, { quoted_beta_row, 0 })
assert(tasks.change_task_status_at_cursor("x"))

local source_after_quoted_status = table.concat(vim.fn.readfile(tasks_file), "\n")
assert_contains(source_after_quoted_status, "- [x] #task Beta 📅 2026-06-07")
assert_not_contains(text(), "#task Beta")

local current_board = root .. "/Projects/Current.md"
vim.fn.writefile({
  "# Current Board",
  "",
  "```tasks",
  "# name: Current Query",
  "description includes Beta",
  "```",
}, current_board)

vim.cmd("edit " .. vim.fn.fnameescape(current_board))
vim.cmd("ObsidianTasks")
local current_text = text()
assert(vim.api.nvim_buf_get_name(0):find("obsidian%-tasks://board/"), vim.api.nvim_buf_get_name(0))
assert_contains(current_text, "# Current Board")
assert_contains(current_text, "## Current Query")
assert_contains(current_text, "Beta")
assert_not_contains(current_text, "Project Open")

local custom_board = root .. "/Projects/CustomKeys.md"
vim.fn.writefile({
  "# Custom Keys",
  "",
  "```tasks",
  "not done",
  "```",
}, custom_board)
tasks.setup({
  vault_path = root,
  global_filter = "#task",
  board = {
    mappings = {
      help = "H",
      next_task = "}",
      previous_task = "{",
      toggle = false,
    },
  },
})
vim.cmd("ObsidianTasks " .. vim.fn.fnameescape(custom_board))
local custom_buf = vim.api.nvim_get_current_buf()
local custom_text = text()
assert_contains(custom_text, "H help")
assert_contains(custom_text, "} next task")
local custom_help = vim.fn.maparg("H", "n", false, true)
assert(type(custom_help) == "table" and custom_help.callback ~= nil, "custom H help mapping missing")
local old_help = vim.fn.maparg("?", "n", false, true)
assert(type(old_help) ~= "table" or old_help.callback == nil, "default ? help mapping should not be installed")
local disabled_toggle = vim.fn.maparg("<Space>", "n", false, true)
assert(type(disabled_toggle) ~= "table" or disabled_toggle.callback == nil, "disabled <Space> mapping should not be installed")
local custom_next = vim.fn.maparg("}", "n", false, true)
local custom_previous = vim.fn.maparg("{", "n", false, true)
assert(type(custom_next) == "table" and custom_next.callback ~= nil, "custom next task mapping missing")
assert(type(custom_previous) == "table" and custom_previous.callback ~= nil, "custom previous task mapping missing")
local custom_start = find_row(custom_buf, "Custom Keys")
assert(custom_start, custom_text)
vim.api.nvim_win_set_cursor(0, { custom_start, 0 })
custom_next.callback()
assert(vim.api.nvim_get_current_line():find("#task", 1, true), vim.api.nvim_get_current_line())
custom_previous.callback()
assert(vim.api.nvim_get_current_line():find("#task", 1, true), vim.api.nvim_get_current_line())

local no_query_file = root .. "/Projects/NoQueries.md"
vim.fn.writefile({
  "# No Queries",
  "",
  "This file has no task query blocks.",
}, no_query_file)
vim.cmd("ObsidianTasks " .. vim.fn.fnameescape(no_query_file))
local no_query_buf = vim.api.nvim_get_current_buf()
assert(vim.api.nvim_buf_get_name(no_query_buf):find("obsidian%-tasks://board/"), vim.api.nvim_buf_get_name(no_query_buf))
assert(vim.b[no_query_buf].obsidian_tasks_board == true, "no-query board marker missing")
assert(vim.bo[no_query_buf].readonly == true, "no-query board must be readonly")
assert(vim.bo[no_query_buf].modifiable == false, "no-query board must be nonmodifiable")
assert_contains(text(), "No tasks query blocks found")
assert(vim.bo[no_query_buf].filetype == "markdown", vim.bo[no_query_buf].filetype)
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-${TMPDIR:-/tmp}/obsidian-tasks-nvim-board-renderer.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "lua local ok, err = pcall(dofile, [[$SMOKE_LUA]]); if not ok then vim.api.nvim_err_writeln(tostring(err)); vim.cmd('cquit') end" \
  -c "qa!"
