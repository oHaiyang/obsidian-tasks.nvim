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

local tasks_file = root .. "/NativeComplete.md"
vim.fn.writefile({
  "# Native Complete",
  "- [ ] #task Existing dependency 🆔 alpha-id",
  "- [ ] #task Another dependency 🆔 beta-id",
  "- [ ] #task Due field 📅 tom",
  "- [ ] #task Recurring field 🔁 every w",
  "- [ ] #task Depends field ⛔ alpha-id, b",
  "- [ ] #task Priority field h",
  "- [ ] #task Already priority ⏫ h",
  "- [ ] #task Priority after due value 📅 2026-05-23 h",
  "- [ ] #task Metadata value position 📅 h",
  "- [ ] #task Due keyword due",
  "- [ ] #task Scheduled keyword schduled",
  "- [ ] #task Scheduled after due value 📅 2026-05-23 scheduled",
  "- [ ] #task Date keyword as metadata value 📅 due",
  "- [ ] #task Due value after emoji 📅 t",
  "- [ ] #task Scheduled value after emoji ⏳ next w",
  "- [ ] #task Due weekday 📅 Fri",
  "- [ ] #task Due next weekday 📅 next fri",
  "- [ ] #task Due abbreviation 📅 tm",
  "- [ ] #task Due this week abbreviation 📅 tw",
  "- [ ] #task Due weekend 📅 weekend",
  "- [ ] #task Due next year 📅 next y",
  "Plain paragraph h",
}, tasks_file)

local tasks = require("obsidian-tasks")
tasks.setup({
  vault_path = root,
  global_filter = "#task",
  today = "2026-05-22",
  completion = {
    native = {
      enabled = true,
      completefunc = true,
      keymap = "<M-Space>",
      auto_trigger = {
        enabled = true,
        metadata_symbols = true,
        priority_prefix = true,
        date_values = true,
      },
    },
  },
})

local completion = require("obsidian-tasks.completion")
local native = require("obsidian-tasks.completion.native")

local function move_to_end(row)
  local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
  vim.api.nvim_win_set_cursor(0, { row, #line })
  return line
end

local function has_word(items, word)
  for _, item in ipairs(items or {}) do
    if item.word == word then
      return true
    end
  end
  return false
end

local function context_at(row)
  local line = move_to_end(row)
  local ctx = completion.markdown_context({ buf = 0 })
  assert(ctx, line)
  return ctx, line
end

vim.cmd("edit " .. vim.fn.fnameescape(tasks_file))
vim.cmd("setfiletype markdown")
native.attach(0, {
  enabled = true,
  completefunc = true,
  keymap = "<M-Space>",
  auto_trigger = {
    enabled = true,
    metadata_symbols = true,
    priority_prefix = true,
    date_values = true,
  },
})

assert(vim.bo.completefunc == "v:lua.obsidian_tasks_native_complete", vim.bo.completefunc)
assert(vim.fn.maparg("<M-Space>", "i") ~= "")
assert(native.is_metadata_trigger("📅"))
assert(native.is_metadata_trigger("🔁"))
assert(not native.is_metadata_trigger("h"))

local ctx = context_at(4)
assert(ctx.field == "due", ctx.field)
assert(ctx.base == "tom", ctx.base)
local start_col = native.complete(1, "")
assert(start_col == ctx.completefunc_start_col, tostring(start_col) .. " != " .. tostring(ctx.completefunc_start_col))
local due_items = native.complete(0, "tom")
assert(has_word(due_items, "2026-05-23"), vim.inspect(due_items))
assert(native.should_auto_trigger_date_value(ctx, {
  auto_trigger = { date_values = true },
}))

ctx = context_at(5)
assert(ctx.field == "recurrence", ctx.field)
assert(has_word(native.complete(0, "every w"), "every week"))

ctx = context_at(6)
assert(ctx.field == "depends_on", ctx.field)
assert(ctx.base == "b", ctx.base)
assert(has_word(native.complete(0, "b"), "beta-id"))

ctx = context_at(7)
assert(ctx.field == "markdown_priority", ctx.field)
assert(ctx.base == "h", ctx.base)
assert(native.should_auto_trigger_priority(ctx, vim.api.nvim_get_current_line(), {
  auto_trigger = { priority_prefix = true },
}))
local priority_items = native.complete(0, "h")
assert(has_word(priority_items, "⏫"), vim.inspect(priority_items))

ctx = context_at(8)
assert(ctx.field == "markdown_priority", ctx.field)
assert(not native.should_auto_trigger_priority(ctx, vim.api.nvim_get_current_line(), {
  auto_trigger = { priority_prefix = true },
}))

ctx = context_at(9)
assert(ctx.field == "due", ctx.field)
assert(ctx.base == "2026-05-23 h", ctx.base)
assert(native.should_auto_trigger_priority(ctx, vim.api.nvim_get_current_line(), {
  auto_trigger = { priority_prefix = true },
}))
assert(has_word(native.complete(0, "h"), "⏫"), vim.inspect(native.complete(0, "h")))

ctx = context_at(10)
assert(ctx.field == "due", ctx.field)
assert(ctx.base == "h", ctx.base)
assert(not native.should_auto_trigger_priority(ctx, vim.api.nvim_get_current_line(), {
  auto_trigger = { priority_prefix = true },
}))
assert(not has_word(native.complete(0, "h"), "⏫"), vim.inspect(native.complete(0, "h")))

ctx = context_at(11)
assert(ctx.field == "markdown_priority", ctx.field)
assert(ctx.base == "due", ctx.base)
assert(native.should_auto_trigger_date_keyword(ctx, vim.api.nvim_get_current_line(), {
  auto_trigger = { date_keywords = true },
}))
assert(has_word(native.complete(0, "due"), "📅 "), vim.inspect(native.complete(0, "due")))

ctx = context_at(12)
assert(ctx.field == "markdown_priority", ctx.field)
assert(ctx.base == "schduled", ctx.base)
assert(native.should_auto_trigger_date_keyword(ctx, vim.api.nvim_get_current_line(), {
  auto_trigger = { date_keywords = true },
}))
assert(has_word(native.complete(0, "schduled"), "⏳ "), vim.inspect(native.complete(0, "schduled")))

ctx = context_at(13)
assert(ctx.field == "due", ctx.field)
assert(ctx.base == "2026-05-23 scheduled", ctx.base)
assert(native.should_auto_trigger_date_keyword(ctx, vim.api.nvim_get_current_line(), {
  auto_trigger = { date_keywords = true },
}))
assert(has_word(native.complete(0, "scheduled"), "⏳ "), vim.inspect(native.complete(0, "scheduled")))

ctx = context_at(14)
assert(ctx.field == "due", ctx.field)
assert(ctx.base == "due", ctx.base)
assert(not native.should_auto_trigger_date_keyword(ctx, vim.api.nvim_get_current_line(), {
  auto_trigger = { date_keywords = true },
}))
assert(not has_word(native.complete(0, "due"), "📅 "), vim.inspect(native.complete(0, "due")))

ctx = context_at(15)
assert(ctx.field == "due", ctx.field)
assert(ctx.base == "t", ctx.base)
assert(native.should_auto_trigger_date_value(ctx, {
  auto_trigger = { date_values = true },
}))
assert(has_word(native.complete(0, "t"), "2026-05-22"), vim.inspect(native.complete(0, "t")))

ctx = context_at(16)
assert(ctx.field == "scheduled", ctx.field)
assert(ctx.base == "next w", ctx.base)
assert(native.should_auto_trigger_date_value(ctx, {
  auto_trigger = { date_values = true },
}))
local next_week_items = native.complete(0, "next w")
assert(has_word(next_week_items, "2026-05-29"), vim.inspect(next_week_items))

ctx = context_at(17)
assert(ctx.field == "due", ctx.field)
assert(ctx.base == "Fri", ctx.base)
assert(native.should_auto_trigger_date_value(ctx, {
  auto_trigger = { date_values = true },
}))
local friday_items = native.complete(0, "Fri")
assert(has_word(friday_items, "2026-05-22"), vim.inspect(friday_items))

ctx = context_at(18)
assert(ctx.field == "due", ctx.field)
assert(ctx.base == "next fri", ctx.base)
local next_friday_items = native.complete(0, "next fri")
assert(has_word(next_friday_items, "2026-05-29"), vim.inspect(next_friday_items))

ctx = context_at(19)
assert(ctx.field == "due", ctx.field)
assert(ctx.base == "tm", ctx.base)
local tm_items = native.complete(0, "tm")
assert(has_word(tm_items, "2026-05-23"), vim.inspect(tm_items))

ctx = context_at(20)
assert(ctx.field == "due", ctx.field)
assert(ctx.base == "tw", ctx.base)
local tw_items = native.complete(0, "tw")
assert(has_word(tw_items, "2026-05-22"), vim.inspect(tw_items))

ctx = context_at(21)
assert(ctx.field == "due", ctx.field)
assert(ctx.base == "weekend", ctx.base)
local weekend_items = native.complete(0, "weekend")
assert(has_word(weekend_items, "2026-05-23"), vim.inspect(weekend_items))

ctx = context_at(22)
assert(ctx.field == "due", ctx.field)
assert(ctx.base == "next y", ctx.base)
local next_year_items = native.complete(0, "next y")
assert(has_word(next_year_items, "2027-05-22"), vim.inspect(next_year_items))

move_to_end(23)
assert(completion.markdown_context({ buf = 0 }) == nil)
assert(native.complete(1, "") == -2)
assert(vim.b.obsidian_tasks_native_completion == true)
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase6-native-completion.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
