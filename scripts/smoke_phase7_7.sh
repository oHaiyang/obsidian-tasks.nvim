#!/usr/bin/env sh
set -eu

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SMOKE_LUA="$(mktemp)"
trap 'rm -f "$SMOKE_LUA"' EXIT

cat > "$SMOKE_LUA" <<'LUA'
local recurrence = require("obsidian-tasks.recurrence")
local task_model = require("obsidian-tasks.task")
local mutation = require("obsidian-tasks.mutation")

local function parse(line)
  local task = task_model.parse_line({
    line = line,
    file_path = "/tmp/recurrence.md",
    line_number = 1,
  })
  assert(task, line)
  return task
end

local function next_due(line, opts)
  local next_task = recurrence.next_task(parse(line), opts or {})
  assert(next_task, line)
  return next_task.due_date or next_task.body:match("📅%s*(%d%d%d%d%-%d%d%-%d%d)")
end

local rule = recurrence.parse_rule("every weekday")
assert(rule.kind == "weekday_set", vim.inspect(rule))
assert(rule.when_done == false, vim.inspect(rule))

rule = recurrence.parse_rule("every! monday when done")
assert(rule.kind == "weekday", vim.inspect(rule))
assert(rule.weekday == 1, vim.inspect(rule))
assert(rule.strict == true, vim.inspect(rule))
assert(rule.when_done == true, vim.inspect(rule))

rule = recurrence.parse_rule("every 2 weeks on friday")
assert(rule.kind == "weekday", vim.inspect(rule))
assert(rule.weekday == 5, vim.inspect(rule))
assert(rule.count == 2, vim.inspect(rule))

rule = recurrence.parse_rule("every month on the 15th")
assert(rule.kind == "monthday", vim.inspect(rule))
assert(rule.day == 15, vim.inspect(rule))

assert(next_due("- [ ] #task Weekday 🔁 every weekday 📅 2026-06-05") == "2026-06-08")
assert(next_due("- [ ] #task Weekend 🔁 every weekend 📅 2026-06-06") == "2026-06-07")
assert(next_due("- [ ] #task Monday 🔁 every monday 📅 2026-06-01") == "2026-06-08")
assert(next_due("- [ ] #task Biweekly Friday 🔁 every 2 weeks on friday 📅 2026-06-05") == "2026-06-19")
assert(next_due("- [ ] #task Monthday soon 🔁 every month on the 15th 📅 2026-06-10") == "2026-06-15")
assert(next_due("- [ ] #task Monthday next 🔁 every month on 15th 📅 2026-06-20") == "2026-07-15")
assert(next_due("- [ ] #task Leap clamp 🔁 every month on the 31st 📅 2026-01-31") == "2026-02-28")
assert(next_due("- [ ] #task Done based 🔁 every weekday when done 📅 2026-06-01", {
  today = "2026-06-05",
}) == "2026-06-08")

local ok, changed = mutation.apply_status_change_to_lines({
  "- [ ] #task Complete weekday 🔁 every weekday 📅 2026-06-05",
}, 1, "x", {
  today = "2026-06-05",
  set_done_date = true,
  recurrence_on_next_line = true,
})
assert(ok, changed)
assert(#changed == 2, vim.inspect(changed))
assert(changed[1]:find("%[x%]"), changed[1])
assert(changed[1]:find("✅ 2026%-06%-05"), changed[1])
assert(changed[2]:find("%[ %]"), changed[2])
assert(changed[2]:find("📅 2026%-06%-08"), changed[2])
assert(not changed[2]:find("✅", 1, true), changed[2])

local dataview_task = task_model.parse_line({
  line = "- [ ] #task Dataview recurrence [repeat:: every monday] [due:: 2026-06-01]",
  task_format = "dataview",
})
assert(dataview_task and dataview_task.is_recurring, vim.inspect(dataview_task))
local dataview_next = recurrence.next_task(dataview_task, {
  today = "2026-06-01",
})
assert(dataview_next, vim.inspect(dataview_task))
assert(dataview_next.body:find("%[due:: 2026%-06%-08%]"), dataview_next.body)
assert(dataview_next.body:find("%[repeat:: every monday%]"), dataview_next.body)
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase7-7.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
