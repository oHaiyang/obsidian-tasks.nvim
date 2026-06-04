#!/usr/bin/env sh
set -eu

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SMOKE_LUA="$(mktemp)"
trap 'rm -f "$SMOKE_LUA"' EXIT

cat > "$SMOKE_LUA" <<'LUA'
local root = vim.fn.tempname()
local outside = vim.fn.tempname()
vim.fn.mkdir(root .. "/Projects", "p")
vim.fn.mkdir(outside, "p")
local uv = vim.uv or vim.loop
root = uv.fs_realpath(root) or root
outside = uv.fs_realpath(outside) or outside

local board_path = root .. "/Projects/Board.md"
local tasks_path = root .. "/Projects/Tasks.md"
local non_md_path = root .. "/Projects/Board.txt"
local outside_board_path = outside .. "/Outside.md"
local symlink_board_path = root .. "/Projects/Symlink.md"
local collision_a_path = root .. "/Projects/A B.md"
local collision_b_path = root .. "/Projects/A_B.md"

vim.fn.writefile({
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
  "description includes #task",
  "```",
  "",
  "Middle paragraph stays markdown.",
  "",
  "```tasks",
  "# name: Broken Query",
  "definitely unsupported",
  "```",
  "",
  "Closing paragraph stays markdown.",
}, board_path)

vim.fn.writefile({
  "# Project Tasks",
  "- [ ] #task Alpha",
  "- [ ] #task Beta",
  "- [x] #task Done",
}, tasks_path)

vim.fn.writefile({ "# Not markdown" }, non_md_path)
vim.fn.writefile({
  "# Outside Board",
  "",
  "```tasks",
  "not done",
  "```",
}, outside_board_path)
assert(uv.fs_symlink(outside_board_path, symlink_board_path) == true, "failed to create symlink board")

for _, path in ipairs({ collision_a_path, collision_b_path }) do
  vim.fn.writefile({
    "# Collision Board",
    "",
    "```tasks",
    "description includes Alpha",
    "```",
  }, path)
end

local tasks = require("obsidian-tasks")
tasks.setup({
  vault_path = root,
  global_filter = "#task",
  cache = { enabled = false },
})

local board = require("obsidian-tasks.board")
local core = require("obsidian-tasks.core")

local function lines(buf)
  return vim.api.nvim_buf_get_lines(buf or 0, 0, -1, false)
end

local function text(buf)
  return table.concat(lines(buf), "\n")
end

local function assert_contains(haystack, needle)
  assert(haystack:find(needle, 1, true), "missing: " .. needle .. "\n" .. haystack)
end

local function assert_not_contains(haystack, needle)
  assert(not haystack:find(needle, 1, true), "unexpected: " .. needle .. "\n" .. haystack)
end

local function file_text(path)
  return table.concat(vim.fn.readfile(path), "\n")
end

local source_before = file_text(tasks_path)
local buf = board.open_path(board_path)
assert(buf and vim.api.nvim_buf_is_valid(buf), "board.open_path did not open a buffer")
assert(vim.api.nvim_get_current_buf() == buf, "opened board is not current")
assert(board.is_board_buffer(buf) == true, "board.is_board_buffer(buf) must be true")

local name = vim.api.nvim_buf_get_name(buf)
assert(name:sub(1, #"obsidian-tasks://board/") == "obsidian-tasks://board/", name)
assert(vim.bo[buf].filetype == "markdown", vim.bo[buf].filetype)
assert(vim.bo[buf].readonly == true, "board buffer must be readonly")
assert(vim.bo[buf].modifiable == false, "board buffer must be nonmodifiable")

local rendered = text(buf)
assert_contains(rendered, "# Board")
assert_contains(rendered, "Intro paragraph stays markdown.")
assert_contains(rendered, "Middle paragraph stays markdown.")
assert_contains(rendered, "Closing paragraph stays markdown.")
assert_contains(rendered, "```lua")
assert_contains(rendered, "print('keep me')")
assert_not_contains(rendered, "```tasks")
assert_not_contains(rendered, "not done")
assert_not_contains(rendered, "description includes #task")
assert_contains(rendered, "## Project Open")
assert_contains(rendered, "1. [ ] #task Alpha")
assert_contains(rendered, "2. [ ] #task Beta")
assert_not_contains(rendered, "3. [x] #task Done")
assert_contains(rendered, "## Broken Query")
assert_contains(rendered, "Query errors:")

local index_map = core.task_index_map[buf]
assert(type(index_map) == "table", "board task index map missing")
assert(index_map[1] and index_map[1].description:find("Alpha", 1, true), vim.inspect(index_map))
assert(index_map[2] and index_map[2].description:find("Beta", 1, true), vim.inspect(index_map))

local alpha_row
for row, line in ipairs(lines(buf)) do
  if line:find("Alpha", 1, true) then
    alpha_row = row
    break
  end
end
assert(alpha_row, rendered)
vim.api.nvim_win_set_cursor(0, { alpha_row, 0 })

assert(tasks.toggle_task_at_cursor() == false, "toggle_task_at_cursor should reject board buffers")
assert(tasks.change_task_status_at_cursor("x") == false, "change_task_status_at_cursor should reject board buffers")
assert(tasks.postpone_task_at_cursor("+1 day") == false, "postpone_task_at_cursor should reject board buffers")
assert(core.save_tasks_changes(buf, { index_map[1], index_map[2] }) == false, "save_tasks_changes should reject board buffers")
local non_board_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(non_board_buf, 0, -1, false, { "1. [ ] #task Alpha [[" .. tasks_path .. "#L2]]" })
core.task_index_map[non_board_buf] = { [1] = index_map[1] }
assert(board.is_board_buffer(non_board_buf) == false, "regression fixture must use a non-board task buffer")
assert(vim.api.nvim_get_current_buf() == buf, "regression fixture must remain focused in the board buffer")
assert(
  core.save_tasks_changes(non_board_buf, { index_map[1] }) == false,
  "save_tasks_changes should reject non-board buffers while focused in a board buffer"
)
assert(core.apply_task_changes(index_map[1], vim.tbl_extend("force", index_map[1], { status = "[x]", status_symbol = "x" })) == false, "apply_task_changes should reject board buffers")
assert(core.apply_postpone_changes(index_map[1], "+1 day") == false, "apply_postpone_changes should reject board buffers")
assert(file_text(tasks_path) == source_before, "board actions mutated source file")
assert(vim.bo[buf].readonly == true, "board buffer lost readonly")
assert(vim.bo[buf].modifiable == false, "board buffer lost nonmodifiable")

local collision_a_buf = board.open_path(collision_a_path)
local collision_b_buf = board.open_path(collision_b_path)
assert(collision_a_buf ~= collision_b_buf, "colliding board paths reused one buffer")
assert(
  vim.api.nvim_buf_get_name(collision_a_buf) ~= vim.api.nvim_buf_get_name(collision_b_buf),
  "colliding board paths produced the same buffer name"
)

vim.api.nvim_set_current_buf(buf)
assert(board.open_path(non_md_path) == nil, "non-markdown board path should reject")
assert(vim.api.nvim_get_current_buf() == buf, "non-markdown rejection changed current buffer")
assert(board.open_path(outside_board_path) == nil, "outside-vault markdown board path should reject")
assert(vim.api.nvim_get_current_buf() == buf, "outside-vault rejection changed current buffer")

local select_items
local selected_rejected = false
local original_select = vim.ui.select
vim.ui.select = function(items, _, callback)
  select_items = items
  callback(symlink_board_path)
  selected_rejected = vim.api.nvim_get_current_buf() == buf
end
board.open({})
vim.ui.select = original_select
assert(type(select_items) == "table" and #select_items > 0, "picker was not opened")
for _, item in ipairs(select_items) do
  assert(item ~= symlink_board_path, "symlinked outside-vault markdown file was offered by picker")
end
assert(selected_rejected, "picker callback opened symlinked outside-vault markdown file")
assert(vim.api.nvim_get_current_buf() == buf, "picker symlink rejection changed current buffer")

print("PASS smoke_board_module")
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-${TMPDIR:-/tmp}/obsidian-tasks-nvim-board-module.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "lua local ok, err = pcall(dofile, [[$SMOKE_LUA]]); if not ok then vim.api.nvim_err_writeln(tostring(err)); vim.cmd('cquit') end" \
  -c "qa!"
