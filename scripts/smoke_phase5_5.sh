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

local tasks_file = root .. "/Form.md"
vim.fn.writefile({
  "# Form",
  "- [ ] #task Alpha 📅 2026-05-20",
}, tasks_file)

local tasks = require("obsidian-tasks")
tasks.setup({
  vault_path = root,
  global_filter = "#task",
  today = "2026-05-16",
  set_created_date = true,
})

local function set_field(buf, key, value)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local replaced = false
  for index, line in ipairs(lines) do
    if line:match("^" .. key .. ":") then
      lines[index] = key .. ": " .. value
      replaced = true
      break
    end
  end
  assert(replaced, key)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

vim.cmd("edit " .. vim.fn.fnameescape(tasks_file))
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local edit_buf = tasks.edit_current_task()
assert(edit_buf and vim.api.nvim_buf_is_valid(edit_buf))
set_field(edit_buf, "status", "In Progress")
set_field(edit_buf, "priority", "medium")
set_field(edit_buf, "created", "6 oct")
set_field(edit_buf, "start", "2 weeks")
set_field(edit_buf, "scheduled", "+3")
set_field(edit_buf, "due", "tomorrow")
assert(require("obsidian-tasks.edit").save_form(edit_buf))

local edited = vim.api.nvim_buf_get_lines(0, 1, 2, false)[1]
assert(edited:find("%[/%]"), edited)
assert(edited:find("🔼", 1, true), edited)
assert(edited:find("➕ 2026-10-06", 1, true), edited)
assert(edited:find("🛫 2026-05-30", 1, true), edited)
assert(edited:find("⏳ 2026-05-19", 1, true), edited)
assert(edited:find("📅 2026-05-17", 1, true), edited)

vim.api.nvim_win_set_cursor(0, { 2, 0 })
local create_buf = tasks.create_task({ today = "2026-05-16" })
assert(create_buf and vim.api.nvim_buf_is_valid(create_buf))
local create_lines = table.concat(vim.api.nvim_buf_get_lines(create_buf, 0, -1, false), "\n")
assert(create_lines:find("created: 2026-05-16", 1, true), create_lines)
set_field(create_buf, "description", "Created with natural date #task")
set_field(create_buf, "due", "not-a-date")
assert(require("obsidian-tasks.edit").save_form(create_buf) == false)
assert(vim.api.nvim_buf_is_valid(create_buf))
set_field(create_buf, "due", "oct 7")
assert(require("obsidian-tasks.edit").save_form(create_buf))

local all = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(all:find("Created with natural date #task", 1, true), all)
assert(all:find("➕ 2026-05-16", 1, true), all)
assert(all:find("📅 2026-10-07", 1, true), all)

local date = require("obsidian-tasks.date")
assert(date.parse_date_expr("in 1 month", { today = "2026-05-16" }) == "2026-06-16")
assert(date.parse_date_expr("last week", { today = "2026-05-16" }) == "2026-05-09")
assert(date.parse_date_expr("-2", { today = "2026-05-16" }) == "2026-05-14")
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase5-5.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
