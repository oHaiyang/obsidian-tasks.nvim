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

local tasks_file = root .. "/Complete.md"
vim.fn.writefile({
  "# Complete",
  "- [ ] #task Existing dependency 🆔 alpha-id",
  "- [ ] #task Another dependency 🆔 beta-id",
  "- [ ] #task Due field 📅 tom",
  "- [ ] #task Recurring field 🔁 every w",
  "- [ ] #task Depends field ⛔ alpha-id, b",
  "- [ ] #task Id field 🆔 ",
  "- [ ] #task Priority field h",
  "Plain paragraph 📅 tom",
}, tasks_file)

local tasks = require("obsidian-tasks")
tasks.setup({
  vault_path = root,
  global_filter = "#task",
  today = "2026-05-16",
})

local completion = require("obsidian-tasks.completion")

local function has_word(items, word)
  for _, item in ipairs(items) do
    if item.word == word then
      return true
    end
  end
  return false
end

local function move_to_end(row)
  local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
  vim.api.nvim_win_set_cursor(0, { row, #line })
  return line
end

local function suggest_at(row)
  local line = move_to_end(row)
  local ctx = completion.markdown_context({ buf = 0 })
  assert(ctx, line)
  return ctx, completion.suggest({
    context = "markdown",
    field = ctx.field,
    base = ctx.base,
  })
end

vim.cmd("edit " .. vim.fn.fnameescape(tasks_file))
assert(vim.fn.exists(":ObsidianTasksComplete") == 2)
assert(vim.fn.maparg("<Plug>(ObsidianTasksComplete)", "i") ~= "")

local ctx, items = suggest_at(4)
assert(ctx.field == "due", ctx.field)
assert(ctx.base == "tom", ctx.base)
assert(has_word(items, "2026-05-17"))
assert(completion.apply_completion({ word = "2026-05-17" }, ctx, 0))
local due_line = vim.api.nvim_buf_get_lines(0, 3, 4, false)[1]
assert(due_line:find("📅 2026-05-17", 1, true), due_line)

ctx, items = suggest_at(5)
assert(ctx.field == "recurrence", ctx.field)
assert(ctx.base == "every w", ctx.base)
assert(has_word(items, "every week"))
assert(completion.apply_completion({ word = "every week" }, ctx, 0))
local recurrence_line = vim.api.nvim_buf_get_lines(0, 4, 5, false)[1]
assert(recurrence_line:find("🔁 every week", 1, true), recurrence_line)

ctx, items = suggest_at(6)
assert(ctx.field == "depends_on", ctx.field)
assert(ctx.base == "b", ctx.base)
assert(has_word(items, "beta-id"))
assert(completion.apply_completion({ word = "beta-id" }, ctx, 0))
local depends_line = vim.api.nvim_buf_get_lines(0, 5, 6, false)[1]
assert(depends_line:find("⛔ alpha-id, beta-id", 1, true), depends_line)

ctx, items = suggest_at(7)
assert(ctx.field == "id", ctx.field)
assert(ctx.base == "", ctx.base)
assert(has_word(items, "task-20260516"))

ctx, items = suggest_at(8)
assert(ctx.field == "markdown_priority", ctx.field)
assert(ctx.base == "h", ctx.base)
assert(has_word(items, "⏫"))
assert(completion.apply_completion({ word = "⏫" }, ctx, 0))
local priority_line = vim.api.nvim_buf_get_lines(0, 7, 8, false)[1]
assert(priority_line:find("Priority field ⏫", 1, true), priority_line)

move_to_end(9)
assert(completion.markdown_context({ buf = 0 }) == nil)
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase5-7.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
