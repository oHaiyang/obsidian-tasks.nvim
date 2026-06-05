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
local explicit_task_path = outside .. "/Explicit.md"
local non_md_path = root .. "/Projects/Board.txt"
local outside_board_path = outside .. "/Outside.md"
local symlink_board_path = root .. "/Projects/Symlink.md"
local collision_a_path = root .. "/Projects/A B.md"
local collision_b_path = root .. "/Projects/A_B.md"

vim.fn.writefile({
  "# Board",
  "",
  "Intro paragraph stays markdown.",
  "- [ ] Plain markdown task stays readonly.",
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
vim.fn.writefile({ "- [ ] #task Explicit non-board file" }, explicit_task_path)

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
  queries = { legacy = "not done" },
  default_query = "legacy",
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

local function find_row(buf, needle)
  for row, line in ipairs(lines(buf)) do
    if line:find(needle, 1, true) then
      return row
    end
  end
  return nil
end

local function set_field_line(buf, key, value)
  for row, line in ipairs(lines(buf)) do
    if line:match("^" .. key .. ":") then
      vim.api.nvim_buf_set_lines(buf, row - 1, row, false, { key .. ": " .. value })
      return true
    end
  end
  return false
end

local source_before = file_text(tasks_path)
local board_source_before = file_text(board_path)
local buf = board.open_path(board_path)
assert(buf and vim.api.nvim_buf_is_valid(buf), "board.open_path did not open a buffer")
assert(vim.api.nvim_get_current_buf() == buf, "opened board is not current")
assert(board.is_board_buffer(buf) == true, "board.is_board_buffer(buf) must be true")

local before_legacy_open_query = vim.api.nvim_get_current_buf()
assert(tasks.open_query("legacy") == nil, "open_query should not open Lua-config named queries")
assert(vim.api.nvim_get_current_buf() == before_legacy_open_query, "open_query changed current buffer for a Lua-config named query")
for _, source in ipairs(require("obsidian-tasks.query_registry").get_sources({ refresh = true })) do
  assert(source.source_type ~= "config", "query_registry should ignore Lua-config queries: " .. vim.inspect(source))
end

local name = vim.api.nvim_buf_get_name(buf)
assert(name:sub(1, #"obsidian-tasks://board/") == "obsidian-tasks://board/", name)
assert(vim.bo[buf].filetype == "markdown", vim.bo[buf].filetype)
assert(vim.bo[buf].readonly == true, "board buffer must be readonly")
assert(vim.bo[buf].modifiable == false, "board buffer must be nonmodifiable")

local rendered = text(buf)
assert_contains(rendered, "# Board")
assert_contains(rendered, "Intro paragraph stays markdown.")
assert_contains(rendered, "- [ ] Plain markdown task stays readonly.")
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

local alpha_row = find_row(buf, "Alpha")
assert(alpha_row, rendered)
vim.api.nvim_win_set_cursor(0, { alpha_row, 0 })

local function assert_board_unchanged(label)
  assert(file_text(tasks_path) == source_before, label .. " mutated source file")
  assert(text(buf) == rendered, label .. " mutated board buffer")
  assert(vim.bo[buf].readonly == true, label .. " changed board readonly")
  assert(vim.bo[buf].modifiable == false, label .. " changed board modifiable")
  assert(vim.api.nvim_get_current_buf() == buf, label .. " changed current buffer")
end

local dependency_editor = require("obsidian-tasks.dependency_editor")
local ensured_id, ensure_err = dependency_editor.ensure_task_id(index_map[1], { id = "board-guard-smoke-id" })
assert(ensured_id == nil, "dependency_editor.ensure_task_id should reject board buffers")
assert(ensure_err == "board task action is not supported here", "unexpected ensure_task_id error: " .. tostring(ensure_err))
assert_board_unchanged("dependency_editor.ensure_task_id")

local added_dependency, add_err = dependency_editor.add_dependency_to_task(index_map[1], "board-guard-dependency")
assert(added_dependency == false, "dependency_editor.add_dependency_to_task should reject board buffers")
assert(add_err == "board task action is not supported here", "unexpected add_dependency_to_task error: " .. tostring(add_err))
assert_board_unchanged("dependency_editor.add_dependency_to_task")

assert(core.save_tasks_changes(buf, { index_map[1], index_map[2] }) == false, "save_tasks_changes should reject board buffers")
assert(require("obsidian-tasks.edit").create_task({ file_path = tasks_path }) == false, "edit.create_task should reject board buffers")
assert(require("obsidian-tasks").create_task({ file_path = tasks_path }) == false, "public create_task should reject board buffers")
assert(
  require("obsidian-tasks.dependency_editor").add_dependency_at_cursor({}) == false,
  "dependency_editor.add_dependency_at_cursor should reject board buffers"
)
assert(
  require("obsidian-tasks").add_dependency_at_cursor({}) == false,
  "public add_dependency_at_cursor should reject board buffers"
)
assert(
  require("obsidian-tasks.date_picker").set_date_at_cursor("due", "2026-06-05", {}) == false,
  "date_picker.set_date_at_cursor should reject board buffers"
)
assert(
  require("obsidian-tasks.date_picker").pick_at_cursor({}) == false,
  "date_picker.pick_at_cursor should reject board buffers"
)
assert(
  require("obsidian-tasks").pick_date_at_cursor({}) == false,
  "public pick_date_at_cursor should reject board buffers"
)
local edit = require("obsidian-tasks.edit")
local form_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(form_buf, 0, -1, false, {
  "description: Board bypass edited #task",
  "status: Todo",
  "priority:",
  "created:",
  "start:",
  "scheduled:",
  "due:",
  "done:",
  "cancelled:",
  "recurrence:",
  "id:",
  "depends_on:",
  "on_completion:",
})
edit.form_state[form_buf] = {
  mode = "edit",
  file_path = tasks_path,
  line_number = 2,
  indentation = "",
  list_marker = "-",
  source_buf = buf,
}
assert(board.is_board_buffer(form_buf) == false, "board form save regression fixture must use a non-board form buffer")
assert(vim.api.nvim_get_current_buf() == buf, "form save regression fixture must remain focused in the board buffer")
assert(edit.save_form(form_buf) == false, "edit.save_form should reject when source buffer is a board")
assert(vim.api.nvim_buf_is_valid(form_buf), "rejected save_form should leave form buffer valid")
assert_board_unchanged("edit.save_form source_buf board guard")

local source_task_form_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(source_task_form_buf, 0, -1, false, {
  "description: Board source task bypass edited #task",
  "status: Todo",
  "priority:",
  "created:",
  "start:",
  "scheduled:",
  "due:",
  "done:",
  "cancelled:",
  "recurrence:",
  "id:",
  "depends_on:",
  "on_completion:",
})
edit.form_state[source_task_form_buf] = {
  mode = "edit",
  file_path = tasks_path,
  line_number = 2,
  indentation = "",
  list_marker = "-",
  source_buf = nil,
  source_task = index_map[1],
}
assert(board.is_board_buffer(source_task_form_buf) == false, "source task form save regression fixture must use a non-board form buffer")
vim.api.nvim_set_current_buf(buf)
assert(vim.api.nvim_get_current_buf() == buf, "source task form save regression fixture must remain focused in the board buffer")
assert(edit.save_form(source_task_form_buf) == false, "edit.save_form should reject indexed board source task objects")
assert(vim.api.nvim_buf_is_valid(source_task_form_buf), "rejected source task save_form should leave form buffer valid")
assert_board_unchanged("edit.save_form source_task board guard")

local normal_source_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(normal_source_buf, root .. "/Projects/FormSource.md")
vim.api.nvim_buf_set_lines(normal_source_buf, 0, -1, false, { "- [ ] #task Form source" })
local normal_form_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(normal_form_buf, 0, -1, false, {
  "description: Form source #task",
  "status: Todo",
  "priority:",
  "created:",
  "start:",
  "scheduled:",
  "due:",
  "done:",
  "cancelled:",
  "recurrence:",
  "id:",
  "depends_on:",
  "on_completion:",
})
edit.form_state[normal_form_buf] = {
  mode = "edit",
  file_path = vim.api.nvim_buf_get_name(normal_source_buf),
  line_number = 1,
  indentation = "",
  list_marker = "-",
  source_buf = normal_source_buf,
}
assert(board.is_board_buffer(normal_source_buf) == false, "normal form source must be non-board")
assert(vim.api.nvim_get_current_buf() == buf, "normal form save fixture must remain focused in the board buffer")
assert(edit.save_form(normal_form_buf) == true, "edit.save_form should allow explicit non-board source buffers")
assert(not vim.api.nvim_buf_is_valid(normal_form_buf), "successful save_form should close normal form buffer")
assert_board_unchanged("direct public board mutation guards")

local non_board_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(non_board_buf, 0, -1, false, { "- [ ] #task Explicit non-board" })
assert(board.is_board_buffer(non_board_buf) == false, "regression fixture must use a non-board task buffer")
assert(vim.api.nvim_get_current_buf() == buf, "regression fixture must remain focused in the board buffer")
assert(
  require("obsidian-tasks.date_picker").set_date_at_cursor("due", "2026-06-05", { buf = non_board_buf, row = 1 }) == true,
  "date_picker.set_date_at_cursor should allow explicit non-board buffers while focused in a board buffer"
)
assert(
  vim.api.nvim_buf_get_lines(non_board_buf, 0, 1, false)[1]:find("📅 2026%-06%-05") ~= nil,
  "explicit non-board date update did not apply"
)
assert(core.save_tasks_changes(non_board_buf, {}) == true, "save_tasks_changes should allow explicit non-board buffers while focused in a board buffer")
local task_model = require("obsidian-tasks.task")
local non_board_task = task_model.parse_line({
  line = "- [ ] #task Explicit non-board file",
  file_path = explicit_task_path,
  line_number = 1,
  global_filter = "#task",
})
assert(non_board_task, "explicit non-board task fixture did not parse")
local updated_non_board_task = vim.tbl_extend("force", non_board_task, { status = "[x]", status_symbol = "x" })
assert(vim.api.nvim_get_current_buf() == buf, "explicit non-board task mutation fixture must remain focused in the board buffer")
assert(
  core.apply_task_changes(non_board_task, updated_non_board_task) == true,
  "apply_task_changes should allow explicit non-board task objects while focused in a board buffer"
)
assert(
  file_text(explicit_task_path):find("%- %[x%] #task Explicit non%-board file") ~= nil,
  "explicit non-board task object update did not mutate its temp markdown file"
)
vim.api.nvim_set_current_buf(buf)
local current_index_map = core.task_index_map[buf]
local board_task = current_index_map and current_index_map[1]
assert(board_task, "board task object guard fixture requires current board index map")
local updated_board_task = vim.tbl_extend("force", board_task, { status = "[x]", status_symbol = "x" })
vim.api.nvim_set_current_buf(non_board_buf)
assert(board.is_board_buffer(vim.api.nvim_get_current_buf()) == false, "board task object guard fixture must focus a non-board buffer")
assert(core.apply_task_changes(board_task, updated_board_task) == false, "apply_task_changes should reject indexed board task objects")
assert(file_text(tasks_path) == source_before, "apply_task_changes mutated source file")
assert(core.apply_task_changes_to_source(board_task, updated_board_task) == false, "apply_task_changes_to_source should reject indexed board task objects")
assert(file_text(tasks_path) == source_before, "apply_task_changes_to_source mutated source file")
assert(core.apply_postpone_changes(board_task, "+1 day") == false, "apply_postpone_changes should reject indexed board task objects")
assert(file_text(tasks_path) == source_before, "apply_postpone_changes mutated source file")
local off_board_ensured_id, off_board_ensure_err = dependency_editor.ensure_task_id(board_task, { id = "board-off-focus-guard-smoke-id" })
assert(off_board_ensured_id == nil, "dependency_editor.ensure_task_id should reject indexed board task objects off board focus")
assert(off_board_ensure_err == "board task action is not supported here", "unexpected off-board ensure_task_id error: " .. tostring(off_board_ensure_err))
assert(file_text(tasks_path) == source_before, "dependency_editor.ensure_task_id off board focus mutated source file")
vim.api.nvim_set_current_buf(buf)
assert_board_unchanged("direct board task object mutation guards")

tasks.config.cache.enabled = true
local cache = require("obsidian-tasks.cache")
cache.clear()
local cached_tasks = cache.tasks({
  vault_path = root,
  global_filter = "#task",
  use_cache = true,
})
local cached_alpha
for _, task in ipairs(cached_tasks) do
  if task.file_path == tasks_path and task.description:find("Alpha", 1, true) then
    cached_alpha = task
    break
  end
end
assert(cached_alpha, "cache-enabled regression fixture did not find Alpha task")

local cache_board_buf = board.open_path(board_path)
local cache_board_index_map = core.task_index_map[cache_board_buf]
local cache_board_alpha = cache_board_index_map and cache_board_index_map[1]
assert(cache_board_alpha, "cache-enabled board index map missing Alpha task")
assert(cached_alpha ~= cache_board_alpha, "board index map reused cache task object identity")

local cache_mutation_before = file_text(tasks_path)
local updated_cached_alpha = vim.tbl_extend("force", cached_alpha, { status = "[x]", status_symbol = "x" })
assert(
  core.apply_task_changes(cached_alpha, updated_cached_alpha) == true,
  "apply_task_changes should allow cache task objects while a board over the same source exists"
)
assert(
  file_text(tasks_path):find("%- %[x%] #task Alpha") ~= nil,
  "cache task object update did not mutate its temp markdown file"
)
vim.fn.writefile(vim.split(cache_mutation_before, "\n", { plain = true }), tasks_path)
cache.clear()

local updated_cache_board_alpha = vim.tbl_extend("force", cache_board_alpha, { status = "[x]", status_symbol = "x" })
assert(core.apply_task_changes(cache_board_alpha, updated_cache_board_alpha) == false, "apply_task_changes should still reject board-owned task objects")
assert(file_text(tasks_path) == cache_mutation_before, "board-owned cache regression task mutated source file")
vim.api.nvim_set_current_buf(buf)
assert_board_unchanged("cache-enabled board task object isolation")
tasks.config.cache.enabled = false

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

vim.api.nvim_set_current_buf(buf)
assert(board.refresh({ buffer = buf }) == true, "board refresh failed before controlled cursor action test")
local plain_task_row = find_row(buf, "Plain markdown task")
assert(plain_task_row, text(buf))
local before_plain_task_action = text(buf)
vim.api.nvim_win_set_cursor(0, { plain_task_row, 0 })
assert(tasks.toggle_task_at_cursor() == false, "plain markdown task lines in board files should stay readonly")
assert(file_text(board_path) == board_source_before, "plain markdown task action mutated board source markdown")
assert(text(buf) == before_plain_task_action, "plain markdown task action mutated board buffer")

local controlled_alpha_row = find_row(buf, "Alpha")
assert(controlled_alpha_row, text(buf))
vim.api.nvim_win_set_cursor(0, { controlled_alpha_row, 0 })
assert(tasks.toggle_task_at_cursor() == true, "toggle_task_at_cursor should write through board task actions")
assert(file_text(tasks_path):find("%- %[x%] #task Alpha") ~= nil, "board toggle did not update source file")
assert(vim.api.nvim_get_current_buf() == buf, "board toggle changed current buffer")
assert(vim.bo[buf].readonly == true, "board toggle changed board readonly")
assert(vim.bo[buf].modifiable == false, "board toggle changed board modifiable")
local after_toggle = text(buf)
assert_not_contains(after_toggle, "#task Alpha")
assert_contains(after_toggle, "#task Beta")

local edit_module = require("obsidian-tasks.edit")
local beta_row = find_row(buf, "Beta")
assert(beta_row, after_toggle)
vim.api.nvim_win_set_cursor(0, { beta_row, 0 })
local board_edit_form_buf = edit_module.edit_current_task()
assert(board_edit_form_buf and vim.api.nvim_buf_is_valid(board_edit_form_buf), "edit_current_task should open a form from board task rows")
assert(vim.api.nvim_get_current_buf() == board_edit_form_buf, "board edit form should become current")
assert(set_field_line(board_edit_form_buf, "description", "#task Beta Edited"), "board edit form description field missing")
assert(edit_module.save_form(board_edit_form_buf) == true, "save_form should save board-origin edit forms")
assert(not vim.api.nvim_buf_is_valid(board_edit_form_buf), "successful board-origin save_form should close the form buffer")
assert(file_text(tasks_path):find("%- %[ %] #task Beta Edited") ~= nil, "board edit form did not update source file")
assert(vim.bo[buf].readonly == true, "board edit changed board readonly")
assert(vim.bo[buf].modifiable == false, "board edit changed board modifiable")
local after_edit = text(buf)
assert_contains(after_edit, "#task Beta Edited")
assert_not_contains(after_edit, "#task Beta\n")

vim.api.nvim_set_current_buf(buf)
local beta_edited_row = find_row(buf, "Beta Edited")
assert(beta_edited_row, text(buf))
vim.api.nvim_win_set_cursor(0, { beta_edited_row, 0 })
assert(tasks.change_task_status_at_cursor("x") == true, "change_task_status_at_cursor should write through board task actions")
assert(file_text(tasks_path):find("%- %[x%] #task Beta Edited") ~= nil, "board status change did not update source file")
assert_not_contains(text(buf), "#task Beta Edited")
assert(vim.bo[buf].readonly == true, "board status change changed board readonly")
assert(vim.bo[buf].modifiable == false, "board status change changed board modifiable")

print("PASS smoke_board_module")
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-${TMPDIR:-/tmp}/obsidian-tasks-nvim-board-module.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "lua local ok, err = pcall(dofile, [[$SMOKE_LUA]]); if not ok then vim.api.nvim_err_writeln(tostring(err)); vim.cmd('cquit') end" \
  -c "qa!"
