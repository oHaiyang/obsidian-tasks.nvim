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

local tasks_file = root .. "/Calendar.md"
vim.fn.writefile({
  "# Calendar",
  "- [ ] #task Date task 📅 2026-05-20",
  "- [ ] #task Scheduled task",
}, tasks_file)

local tasks = require("obsidian-tasks")
tasks.setup({
  vault_path = root,
  global_filter = "#task",
  today = "2026-05-22",
})

local date_picker = require("obsidian-tasks.date_picker")
local edit = require("obsidian-tasks.edit")

local function has_line(lines, expected)
  for _, line in ipairs(lines or {}) do
    if line == expected then
      return true
    end
  end
  return false
end

local function field_value(buf, key)
  for _, form_line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local value = form_line:match("^" .. key .. ":%s*(.*)$")
    if value ~= nil then
      return value
    end
  end
  error("field not found: " .. key)
end

assert(vim.fn.exists(":ObsidianTasksPickDate") == 2)
local command_info = vim.api.nvim_get_commands({})["ObsidianTasksPickDate"]
assert(command_info and command_info.bang == true, vim.inspect(command_info))

local choices = date_picker.choices({ current_value = "2026-05-20" })
assert(has_line(vim.tbl_map(function(item) return item.label end, choices), "Advance 1 day"), vim.inspect(choices))
assert(has_line(vim.tbl_map(function(item) return item.label end, choices), "Postpone 1 day"), vim.inspect(choices))
assert(has_line(vim.tbl_map(function(item) return item.label end, choices), "Calendar..."), vim.inspect(choices))

local grid = date_picker.month_grid("2026-05-22")
assert(#grid == 5, vim.inspect(grid))
assert(grid[1][5].day == 1, vim.inspect(grid[1]))
assert(grid[4][5].date == "2026-05-22", vim.inspect(grid[4]))

local state = date_picker.calendar_state({
  field = "due",
  selected_date = "2026-05-22",
  current_value = "2026-05-20",
})
local lines = date_picker.calendar_lines(state)
assert(lines[1] == "May 2026        field: due", vim.inspect(lines))
assert(has_line(lines, "Current: 2026-05-20"), vim.inspect(lines))
assert(table.concat(lines, "\n"):find("%[22%]"), vim.inspect(lines))

date_picker.move_calendar_state(state, 1)
assert(state.selected_date == "2026-05-23", state.selected_date)
date_picker.move_calendar_state(state, -7)
assert(state.selected_date == "2026-05-16", state.selected_date)
date_picker.move_calendar_month_state(state, 1)
assert(state.selected_date == "2026-06-16", state.selected_date)

vim.cmd("edit " .. vim.fn.fnameescape(tasks_file))
vim.api.nvim_win_set_cursor(0, { 2, 0 })
assert(date_picker.date_in_line(vim.api.nvim_get_current_line(), "due") == "2026-05-20")
assert(date_picker.set_date_at_cursor("due", "2026-05-23"))
assert((vim.api.nvim_get_current_line()):find("📅 2026%-05%-23"), vim.api.nvim_get_current_line())
assert(date_picker.set_date_at_cursor("due", ""))
assert(not (vim.api.nvim_get_current_line()):find("📅", 1, true), vim.api.nvim_get_current_line())
assert(date_picker.set_date_in_line("- [ ] #task Alt due 📆 2026-05-20", "due", "2026-05-24")
  == "- [ ] #task Alt due 📆 2026-05-24")
assert(date_picker.set_date_in_line("- [ ] #task Alt due 🗓 2026-05-20", "due", "")
  == "- [ ] #task Alt due")

local selected
local calendar_state = date_picker.open_calendar({
  field = "scheduled",
  selected_date = "2026-05-22",
}, function(value)
  selected = value
end)
assert(calendar_state.buf and vim.api.nvim_buf_is_valid(calendar_state.buf))
assert(calendar_state.win and vim.api.nvim_win_is_valid(calendar_state.win))
vim.api.nvim_set_current_win(calendar_state.win)
vim.cmd("normal! l")
date_picker.move_calendar_state(calendar_state, 1)
assert(calendar_state.selected_date == "2026-05-23", calendar_state.selected_date)
vim.cmd("normal c")
assert(selected == "", tostring(selected))

vim.api.nvim_win_set_cursor(0, { 2, 0 })
local form_buf = edit.edit_current_task()
assert(form_buf and vim.api.nvim_buf_is_valid(form_buf))
local picked
date_picker.pick_for_form(form_buf, "due", {
  style = "calendar",
  current_value = "2026-05-22",
  on_select = function(value)
    picked = value
  end,
})
local picker_buf = vim.api.nvim_get_current_buf()
assert(vim.bo[picker_buf].filetype == "obstasks-date-picker", vim.bo[picker_buf].filetype)
date_picker.move_calendar_state({
  selected_date = "2026-05-22",
}, 1)
assert(picked == nil)
pcall(vim.api.nvim_buf_delete, picker_buf, { force = true })
pcall(vim.api.nvim_buf_delete, form_buf, { force = true })
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase6-5.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
