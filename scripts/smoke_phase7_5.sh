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

local tasks_file = root .. "/Tasks.md"
vim.fn.writefile({
  "# Tasks",
  "",
  "- [ ] #task Alpha 🆔 alpha-id",
  "- [ ] #task Beta",
}, tasks_file)

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
  },
})

local core = require("obsidian-tasks.core")
local mutation = require("obsidian-tasks.mutation")
local scanner = require("obsidian-tasks.scanner")
local source = require("obsidian-tasks.source")

local function read_source()
  return vim.fn.readfile(tasks_file)
end

local function source_text()
  return table.concat(read_source(), "\n")
end

local function find_result_line(pattern)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for index, line in ipairs(lines) do
    if line:find(pattern, 1, true) then
      return index, line
    end
  end
  return nil, nil
end

tasks.open_query("all")
local result_buf = vim.api.nvim_get_current_buf()
local alpha_row = assert(find_result_line("Alpha"))

vim.fn.writefile({
  "# Tasks",
  "",
  "- [ ] #task Inserted",
  "- [ ] #task Alpha 🆔 alpha-id",
  "- [ ] #task Beta",
}, tasks_file)

vim.api.nvim_set_current_buf(result_buf)
vim.api.nvim_win_set_cursor(0, { alpha_row, 0 })
assert(tasks.toggle_task_at_cursor())
assert(tasks.save_current_tasks())
local after_result_save = source_text()
assert(after_result_save:find("%- %[ %] #task Inserted"), after_result_save)
assert(after_result_save:find("%- %[x%] #task Alpha 🆔 alpha%-id"), after_result_save)

local alpha_task
local beta_task
for _, task in ipairs(scanner.scan_file(tasks_file, { global_filter = "#task" })) do
  if task.description:find("Alpha", 1, true) then
    alpha_task = task
  elseif task.description:find("Beta", 1, true) then
    beta_task = task
  end
end
assert(alpha_task and beta_task, vim.inspect(scanner.scan_file(tasks_file, { global_filter = "#task" })))

vim.fn.writefile({
  "# Tasks",
  "",
  "- [ ] #task Header",
  "- [ ] #task Alpha renamed 🆔 alpha-id",
  "- [ ] #task Beta",
}, tasks_file)
local renamed_lines = read_source()
local ok, updated_lines = mutation.apply_status_change_to_lines(renamed_lines, alpha_task.line_number, "x", {
  file_path = tasks_file,
  source_task = alpha_task,
})
assert(ok, updated_lines)
assert(table.concat(updated_lines, "\n"):find("%- %[x%] #task Alpha renamed 🆔 alpha%-id"), table.concat(updated_lines, "\n"))

vim.fn.writefile({
  "# Tasks",
  "",
  "- [ ] #task Inserted",
  "- [ ] #task Spacer",
  "- [ ] #task Alpha one 🆔 alpha-id",
  "- [ ] #task Alpha two 🆔 alpha-id",
  "- [ ] #task Beta",
}, tasks_file)
local duplicate_ok, duplicate_err = mutation.apply_status_change_to_lines(read_source(), alpha_task.line_number, "x", {
  file_path = tasks_file,
  source_task = alpha_task,
})
assert(not duplicate_ok, tostring(duplicate_err))
assert(tostring(duplicate_err):find("Multiple tasks have id", 1, true), tostring(duplicate_err))

vim.fn.writefile({
  "# Tasks",
  "",
  "- [ ] #task Alpha 🆔 alpha-id",
  "- [ ] #task Beta renamed",
}, tasks_file)
local beta_ok, beta_err = mutation.apply_status_change_to_lines(read_source(), beta_task.line_number, "x", {
  file_path = tasks_file,
  source_task = beta_task,
})
assert(not beta_ok, tostring(beta_err))
assert(tostring(beta_err):find("Task source line changed", 1, true), tostring(beta_err))

vim.fn.writefile({
  "# Tasks",
  "",
  "- [ ] #task Inserted",
  "- [ ] #task Beta",
}, tasks_file)
local beta_line, locate_reason = source.locate_in_file(beta_task)
assert(beta_line == 4, tostring(beta_line) .. " " .. tostring(locate_reason))
assert(locate_reason == "original markdown", tostring(locate_reason))
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase7-5.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
