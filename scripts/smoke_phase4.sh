#!/usr/bin/env sh
set -eu

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SMOKE_LUA="$(mktemp)"
trap 'rm -f "$SMOKE_LUA"' EXIT

cat > "$SMOKE_LUA" <<'LUA'
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/Projects", "p")

local tasks_file = root .. "/Projects/Phase4.md"
vim.fn.writefile({
  "# Phase 4",
  "- [ ] #task Todo item 📅 2026-05-15",
  "- [ ] #task Recurring daily 🔁 every day 📅 2026-05-15",
  "- [ ] #task Parent task 🆔 parent",
  "- [ ] #task Child task ⛔ parent",
  "- [x] #task Done parent 🆔 done-parent",
  "- [ ] #task Free child ⛔ done-parent",
  "- [ ] #task Scheduled only ⏳ 2026-05-18",
}, tasks_file)

local tasks = require("obsidian-tasks")
tasks.setup({
  vault_path = root,
  global_filter = "#task",
  set_done_date = true,
  set_cancelled_date = true,
  recurrence_on_next_line = true,
  queries = {
    blocked = "is blocked",
    blocking = "is blocking",
    progress = "status.type is IN_PROGRESS",
  },
})

assert(vim.api.nvim_get_commands({}).ObsidianTasksToggle)
assert(vim.api.nvim_get_commands({}).ObsidianTasksChangeStatus)
assert(vim.api.nvim_get_commands({}).ObsidianTasksPostpone)
assert(vim.api.nvim_get_commands({}).ObsidianTasksStatusDone)
assert(vim.api.nvim_get_commands({}).ObsidianTasksStatusInProgress)
assert(vim.api.nvim_get_commands({}).ObsidianTasksStatusCancelled)

local status = require("obsidian-tasks.status")
assert(status.type(" ") == "TODO")
assert(status.type("x") == "DONE")
assert(status.type("/") == "IN_PROGRESS")
assert(status.type("-") == "CANCELLED")
assert(status.next_symbol("/") == "x")
assert(status.resolve_symbol("In Progress") == "/")

local mutation = require("obsidian-tasks.mutation")

local ok, changed = mutation.apply_status_change_to_lines({
  "- [ ] #task Finish me 📅 2026-05-15",
}, 1, "x", {
  today = "2026-05-15",
  set_done_date = true,
})
assert(ok, changed)
assert(changed[1]:find("%[x%]"), changed[1])
assert(changed[1]:find("✅ 2026%-05%-15"), changed[1])

ok, changed = mutation.apply_status_change_to_lines(changed, 1, " ", {})
assert(ok, changed)
assert(changed[1]:find("%[ %]"), changed[1])
assert(not changed[1]:find("✅", 1, true), changed[1])

ok, changed = mutation.apply_status_change_to_lines({
  "- [ ] #task Cancel me",
}, 1, "-", {
  today = "2026-05-15",
  set_cancelled_date = true,
})
assert(ok, changed)
assert(changed[1]:find("%[%-%]"), changed[1])
assert(changed[1]:find("❌ 2026%-05%-15"), changed[1])

ok, changed = mutation.apply_status_change_to_lines({
  "- [ ] #task Recurring daily 🔁 every day 📅 2026-05-15",
}, 1, "x", {
  today = "2026-05-15",
  set_done_date = true,
  recurrence_on_next_line = true,
})
assert(ok, changed)
assert(#changed == 2, vim.inspect(changed))
assert(changed[1]:find("%[x%]"), changed[1])
assert(changed[1]:find("✅ 2026%-05%-15"), changed[1])
assert(changed[2]:find("%[ %]"), changed[2])
assert(changed[2]:find("📅 2026%-05%-16"), changed[2])
assert(not changed[2]:find("✅", 1, true), changed[2])

local field
local target
ok, changed, _, field, target = mutation.apply_postpone_to_lines({
  "- [ ] #task Postpone due ⏳ 2026-05-18 📅 2026-05-10",
}, 1, "", {
  today = "2026-05-09",
})
assert(ok, changed)
assert(field == "due", field)
assert(target == "2026-05-11", target)
assert(changed[1]:find("📅 2026%-05%-11"), changed[1])

ok, changed, _, field, target = mutation.apply_postpone_to_lines({
  "- [ ] #task Postpone scheduled ⏳ 2026-05-18",
}, 1, "+2", {})
assert(ok, changed)
assert(field == "scheduled", field)
assert(target == "2026-05-20", target)
assert(changed[1]:find("⏳ 2026%-05%-20"), changed[1])

local scanner = require("obsidian-tasks.scanner")
local query = require("obsidian-tasks.query")
local scanned = scanner.scan_vault({
  vault_path = root,
  global_filter = "#task",
})

local forwarded_query = query.parse("status.name does not include forwarded")
local forwarded_tasks = {
  { description = "Forwarded item", status_symbol = ">", status = "[>]" },
  { description = "Todo item", status_symbol = " ", status = "[ ]" },
}
local upstream_status_config = {
  statusSettings = {
    customStatuses = {
      { symbol = ">", name = "forwarded", nextStatusSymbol = "x", type = "TODO" },
    },
  },
}
assert(
  not query.matches(forwarded_tasks[1], forwarded_query, { tasks = forwarded_tasks, status_config = upstream_status_config }),
  "forwarded status should be filtered by upstream statusSettings"
)
assert(
  query.matches(forwarded_tasks[2], forwarded_query, { tasks = forwarded_tasks, status_config = upstream_status_config }),
  "todo status should remain when filtering forwarded status"
)

local tuple_status_config = {
  statusSettings = {
    customStatuses = {
      { ">", "forwarded", "x", "TODO" },
    },
  },
}
assert(
  not query.matches(forwarded_tasks[1], forwarded_query, { tasks = forwarded_tasks, status_config = tuple_status_config }),
  "forwarded status should be filtered by imported status tuples"
)

local blocked = query.filter_tasks(scanned, query.parse("is blocked"))
assert(#blocked == 1, vim.inspect(blocked))
assert(blocked[1].description:find("Child task", 1, true), blocked[1].description)

local blocking = query.filter_tasks(scanned, query.parse("is blocking"))
assert(#blocking == 1, vim.inspect(blocking))
assert(blocking[1].description:find("Parent task", 1, true), blocking[1].description)

vim.cmd("edit " .. vim.fn.fnameescape(tasks_file))
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.cmd("ObsidianTasksChangeStatus In Progress")
local line = vim.api.nvim_buf_get_lines(0, 1, 2, false)[1]
assert(line:find("%[/%]"), line)
assert(not line:find("✅", 1, true), line)
assert(not line:find("❌", 1, true), line)
assert(not line:find("🛫", 1, true), line)

vim.cmd("ObsidianTasksPostpone 2026-05-20")
line = vim.api.nvim_buf_get_lines(0, 1, 2, false)[1]
assert(line:find("📅 2026%-05%-20"), line)
LUA

nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
