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

local tasks_file = root .. "/Deps.md"
vim.fn.writefile({
  "# Dependencies",
  "- [ ] #task Current task",
  "- [ ] #task Needs generated id",
  "- [ ] #task Existing id 🆔 existing-id",
  "- [ ] #task Date task",
}, tasks_file)

local tasks = require("obsidian-tasks")
tasks.setup({
  vault_path = root,
  global_filter = "#task",
  today = "2026-05-16",
})

local dependency_editor = require("obsidian-tasks.dependency_editor")
local date_picker = require("obsidian-tasks.date_picker")
local edit = require("obsidian-tasks.edit")
local scanner = require("obsidian-tasks.scanner")

local function line(row)
  return vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
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

vim.cmd("edit " .. vim.fn.fnameescape(tasks_file))
assert(vim.fn.exists(":ObsidianTasksAddDependency") == 2)
assert(vim.fn.exists(":ObsidianTasksPickDate") == 2)
assert(vim.fn.maparg("<Plug>(ObsidianTasksAddDependency)", "n") ~= "")
assert(vim.fn.maparg("<Plug>(ObsidianTasksPickDate)", "n") ~= "")

local scanned = scanner.scan_file(tasks_file, { global_filter = "#task" })
local current = scanned[1]
local generated_target = scanned[2]
local existing_target = scanned[3]

vim.api.nvim_win_set_cursor(0, { 2, 0 })
assert(dependency_editor.add_dependency_at_cursor({
  target_task = generated_target,
  today = "2026-05-16",
  vault_path = root,
}))
assert(line(3):find("🆔 task%-20260516%-3"), line(3))
assert(line(2):find("⛔ task%-20260516%-3"), line(2))

assert(dependency_editor.add_dependency_at_cursor({
  target_task = existing_target,
  today = "2026-05-16",
  vault_path = root,
}))
assert(line(2):find("task%-20260516%-3, existing%-id"), line(2))

assert(dependency_editor.add_dependency_at_cursor({
  target_task = existing_target,
  today = "2026-05-16",
  vault_path = root,
}))
local _, duplicate_count = line(2):gsub("existing%-id", "")
assert(duplicate_count == 1, line(2))

local added = dependency_editor.add_id_to_csv("alpha-id", "beta-id")
assert(added == "alpha-id, beta-id", added)
assert(dependency_editor.add_id_to_csv(added, "beta-id") == added)

vim.api.nvim_win_set_cursor(0, { 2, 0 })
local form_buf = tasks.edit_current_task()
assert(form_buf and vim.api.nvim_buf_is_valid(form_buf))
assert(edit.pick_dependency(form_buf, existing_target))
assert(field_value(form_buf, "depends_on"):find("existing%-id"), field_value(form_buf, "depends_on"))
pcall(vim.api.nvim_buf_delete, form_buf, { force = true })

local date_line = "- [ ] #task Date task"
local updated = assert(date_picker.set_date_in_line(date_line, "due", "2026-05-17"))
assert(updated:find("📅 2026%-05%-17"), updated)
updated = assert(date_picker.set_date_in_line(updated, "due", "2026-05-18"))
assert(updated:find("📅 2026%-05%-18"), updated)
updated = assert(date_picker.set_date_in_line(updated, "due", ""))
assert(not updated:find("📅", 1, true), updated)
assert(date_picker.resolve_expr("next week", { today = "2026-05-16" }) == "2026-05-23")

vim.api.nvim_win_set_cursor(0, { 5, 0 })
assert(date_picker.set_date_at_cursor("scheduled", "2026-05-20"))
assert(line(5):find("⏳ 2026%-05%-20"), line(5))
assert(date_picker.set_date_at_cursor("scheduled", ""))
assert(not line(5):find("⏳", 1, true), line(5))
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase5-9.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
