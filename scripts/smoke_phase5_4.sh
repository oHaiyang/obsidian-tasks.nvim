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

local tasks_file = root .. "/Layout.md"
vim.fn.writefile({
  "# Layout",
  "```tasks",
  "# name: Preview Compact",
  "# id: preview-compact",
  "hide task count",
  "hide backlink",
  "hide tags",
  "description includes Preview",
  "```",
  "",
  "- [ ] #task Alpha #work ⏫ 📅 2026-05-20 🆔 alpha",
  "- [ ] #task Beta #home 🔼 📅 2026-05-21 🆔 beta",
  "- [ ] #task Preview #preview 📅 2026-05-22",
}, tasks_file)

local tasks = require("obsidian-tasks")
tasks.setup({
  vault_path = root,
  global_filter = "#task",
})

local function current_lines()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

local function find_line(pattern)
  for index, line in ipairs(current_lines()) do
    if line:find(pattern) then
      return index, line
    end
  end
  return nil, nil
end

tasks.run_query([[
description includes Alpha
hide task count
hide backlink
hide priority
hide tags
hide due date
hide id
]], { name = "compact" })
local compact_text = table.concat(current_lines(), "\n")
assert(not compact_text:find("Showing", 1, true), compact_text)
local alpha_row, alpha_line = find_line("Alpha")
assert(alpha_row and alpha_line, compact_text)
assert(not alpha_line:find("%[%["), alpha_line)
assert(not alpha_line:find("%[HIGH%]"), alpha_line)
assert(not alpha_line:find("⏫", 1, true), alpha_line)
assert(not alpha_line:find("📅", 1, true), alpha_line)
assert(not alpha_line:find("2026-05-20", 1, true), alpha_line)
assert(not alpha_line:find("#work", 1, true), alpha_line)
assert(not alpha_line:find("#task", 1, true), alpha_line)
assert(not alpha_line:find("🆔", 1, true), alpha_line)
assert(not alpha_line:find(" alpha", 1, true), alpha_line)

vim.api.nvim_win_set_cursor(0, { alpha_row, 0 })
assert(tasks.toggle_task_at_cursor())
local toggled = vim.api.nvim_buf_get_lines(0, alpha_row - 1, alpha_row, false)[1]
assert(toggled:match("^1%. %[x%]"), toggled)
assert(not toggled:find("%[%["), toggled)
assert(tasks.save_current_tasks())
local source = table.concat(vim.fn.readfile(tasks_file), "\n")
assert(source:find("%- %[x%] #task Alpha", 1, false), source)

tasks.run_query([[
description includes Beta
show task count
show backlink
show priority
show tags
show due date
show id
]], { name = "visible" })
local visible_text = table.concat(current_lines(), "\n")
assert(visible_text:find("Showing 1 tasks", 1, true), visible_text)
local _, beta_line = find_line("Beta")
assert(beta_line, visible_text)
assert(beta_line:find("%[%["), beta_line)
assert(beta_line:find("🔼", 1, true), beta_line)
assert(not beta_line:find("%[MEDIUM%]"), beta_line)
assert(beta_line:find("#home", 1, true), beta_line)
assert(beta_line:find("#task", 1, true), beta_line)
assert(beta_line:find("📅 2026-05-21", 1, true), beta_line)
assert(beta_line:find("🆔 beta", 1, true), beta_line)

vim.cmd("edit " .. vim.fn.fnameescape(tasks_file))
require("obsidian-tasks.preview").refresh_buffer(0, { limit = 5 })
local marks = vim.api.nvim_buf_get_extmarks(0, require("obsidian-tasks.preview").namespace, 0, -1, { details = true })
assert(#marks == 1, vim.inspect(marks))
local preview = vim.inspect(marks[1][4].virt_lines)
assert(not preview:find("Showing", 1, true), preview)
assert(not preview:find("#L", 1, true), preview)
assert(not preview:find("#task", 1, true), preview)
assert(not preview:find("#preview", 1, true), preview)
assert(preview:find("Preview", 1, true), preview)
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase5-4.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
