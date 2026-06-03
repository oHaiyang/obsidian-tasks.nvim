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

local tasks_file = root .. "/Dataview.md"
vim.fn.writefile({
  "# Dataview",
  "- [ ] #task High dataview  [priority:: high]  [due:: 2026-05-20]  [id:: alpha-id]",
  "- [ ] #task Beta target  [id:: beta-id]",
  "- [ ] #task Current depends  [dependsOn:: alpha-id]",
  "- [ ] #task Form source  [due:: 2026-05-20]",
  "- [ ] #task Recurring source  [repeat:: every week]  [due:: 2026-05-20]  [id:: recur-id]  [dependsOn:: alpha-id]",
}, tasks_file)

local tasks = require("obsidian-tasks")
tasks.setup({
  vault_path = root,
  global_filter = "#task",
  today = "2026-05-22",
  task_format = "dataview",
  set_done_date = true,
  set_created_date = true,
})

local task_model = require("obsidian-tasks.task")
local scanner = require("obsidian-tasks.scanner")
local query = require("obsidian-tasks.query")
local mutation = require("obsidian-tasks.mutation")
local date_picker = require("obsidian-tasks.date_picker")
local dependency_editor = require("obsidian-tasks.dependency_editor")
local edit = require("obsidian-tasks.edit")
local completion = require("obsidian-tasks.completion")

local function has(text, needle)
  assert(text:find(needle, 1, true), text .. "\nmissing: " .. needle)
end

local parsed = assert(task_model.parse_line({
  line = "- [ ] #task Demo  [priority:: high]  [created:: 2026-05-18]  [scheduled:: 2026-05-19]  [start:: 2026-05-19]  [due:: 2026-05-20]  [completion:: 2026-05-21]  [cancelled:: 2026-05-22]  [repeat:: every week]  [onCompletion:: delete]  [id:: abc]  [dependsOn:: x,y]",
}))
assert(parsed.task_format == "dataview", parsed.task_format)
assert(parsed.description == "#task Demo", parsed.description)
assert(parsed.priority == "high", parsed.priority)
assert(parsed.created_date == "2026-05-18", vim.inspect(parsed))
assert(parsed.scheduled_date == "2026-05-19", vim.inspect(parsed))
assert(parsed.start_date == "2026-05-19", vim.inspect(parsed))
assert(parsed.due_date == "2026-05-20", vim.inspect(parsed))
assert(parsed.done_date == "2026-05-21", vim.inspect(parsed))
assert(parsed.cancelled_date == "2026-05-22", vim.inspect(parsed))
assert(parsed.recurrence_rule == "every week", parsed.recurrence_rule)
assert(parsed.on_completion == "delete", parsed.on_completion)
assert(parsed.id == "abc", parsed.id)
assert(#parsed.depends_on == 2, vim.inspect(parsed.depends_on))

local scanned = scanner.scan_vault({
  vault_path = root,
  global_filter = "#task",
  today = "2026-05-22",
})
assert(#scanned == 5, vim.inspect(scanned))
local plan = query.parse("not done\ndue before 2026-05-22\npriority is high\nhas id", { config = tasks.config })
assert(#plan.errors == 0, vim.inspect(plan.errors))
local results = query.filter_tasks(scanned, plan)
assert(#results == 1, vim.inspect(results))
assert(results[1].description == "#task High dataview", results[1].description)

local function complete_line(line)
  local ctx = completion.markdown_context({
    buf = 0,
    line = line,
    row = 1,
    cursor_col = #line,
  })
  assert(ctx, line)
  return ctx, completion.suggest({
    context = "markdown",
    field = ctx.field,
    base = ctx.base,
    current_task = ctx.current_task,
  })
end

local function has_word(items, word)
  for _, item in ipairs(items) do
    if item.word == word then
      return true
    end
  end
  return false
end

local ctx, items = complete_line("- [ ] #task Priority h")
assert(ctx.field == "markdown_priority", vim.inspect(ctx))
assert(has_word(items, "[priority:: high]"), vim.inspect(items))
assert(not has_word(items, "⏫"), vim.inspect(items))

ctx, items = complete_line("- [ ] #task Inline due  [due:: tom")
assert(ctx.field == "due", vim.inspect(ctx))
assert(ctx.base == "tom", ctx.base)
assert(has_word(items, "2026-05-23"), vim.inspect(items))

ctx, items = complete_line("- [ ] #task Current  [id:: current-id]  [dependsOn:: b")
assert(ctx.field == "depends_on", vim.inspect(ctx))
assert(has_word(items, "beta-id"), vim.inspect(items))
assert(not has_word(items, "current-id"), vim.inspect(items))

local updated = assert(date_picker.set_date_in_line("- [ ] #task Date  [due:: 2026-05-20]", "due", "2026-05-23"))
has(updated, "[due:: 2026-05-23]")
assert(not updated:find("📅", 1, true), updated)
updated = assert(date_picker.set_date_in_line(updated, "due", ""))
assert(not updated:find("[due::", 1, true), updated)
updated = assert(date_picker.set_date_in_line("- [ ] #task Empty", "scheduled", "2026-05-24"))
has(updated, "[scheduled:: 2026-05-24]")
assert(date_picker.date_in_line(updated, "scheduled") == "2026-05-24", updated)

local depends_line = assert(dependency_editor.add_dependency_to_line(
  "- [ ] #task Current  [dependsOn:: alpha-id]",
  "beta-id"
))
has(depends_line, "[dependsOn:: alpha-id, beta-id]")
assert(not depends_line:find("⛔", 1, true), depends_line)
local id_line = dependency_editor.add_id_to_line("- [ ] #task Needs id", "new-id")
has(id_line, "[id:: new-id]")
assert(not id_line:find("🆔", 1, true), id_line)

local ok, changed = mutation.apply_status_change_to_lines({
  "- [ ] #task Done target  [due:: 2026-05-20]",
}, 1, "x", {
  today = "2026-05-22",
  set_done_date = true,
})
assert(ok, vim.inspect(changed))
has(changed[1], "[completion:: 2026-05-22]")
assert(not changed[1]:find("✅", 1, true), changed[1])

ok, changed = mutation.apply_postpone_to_lines({
  "- [ ] #task Postpone target  [due:: 2026-05-20]",
}, 1, "2026-05-25", {})
assert(ok, vim.inspect(changed))
has(changed[1], "[due:: 2026-05-25]")

ok, changed = mutation.apply_status_change_to_lines({
  "- [ ] #task Recurring  [repeat:: every week]  [due:: 2026-05-20]  [id:: recur-id]  [dependsOn:: alpha-id]",
}, 1, "x", {
  today = "2026-05-22",
  set_done_date = true,
  set_created_date = true,
})
assert(ok, vim.inspect(changed))
assert(#changed == 2, vim.inspect(changed))
has(changed[1], "[repeat:: every week]")
has(changed[1], "[due:: 2026-05-27]")
has(changed[1], "[created:: 2026-05-22]")
assert(not changed[1]:find("[id::", 1, true), changed[1])
assert(not changed[1]:find("[dependsOn::", 1, true), changed[1])
has(changed[2], "[completion:: 2026-05-22]")

vim.cmd("edit " .. vim.fn.fnameescape(tasks_file))
vim.api.nvim_win_set_cursor(0, { 5, 0 })
local form_buf = tasks.edit_current_task()
assert(form_buf and vim.api.nvim_buf_is_valid(form_buf))
local lines = vim.api.nvim_buf_get_lines(form_buf, 0, -1, false)
for index, line in ipairs(lines) do
  if line:match("^priority:") then
    lines[index] = "priority: high"
  elseif line:match("^due:") then
    lines[index] = "due: tomorrow"
  elseif line:match("^depends_on:") then
    lines[index] = "depends_on: beta-id"
  elseif line:match("^id:") then
    lines[index] = "id: form-id"
  end
end
vim.api.nvim_buf_set_lines(form_buf, 0, -1, false, lines)
assert(edit.save_form(form_buf))
local saved = vim.api.nvim_buf_get_lines(0, 4, 5, false)[1]
has(saved, "[priority:: high]")
has(saved, "[due:: 2026-05-23]")
has(saved, "[id:: form-id]")
has(saved, "[dependsOn:: beta-id]")
assert(not saved:find("📅", 1, true), saved)
assert(not saved:find("⛔", 1, true), saved)
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase6-7.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
