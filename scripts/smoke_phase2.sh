#!/usr/bin/env sh
set -eu

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SMOKE_LUA="$(mktemp)"
trap 'rm -f "$SMOKE_LUA"' EXIT

cat > "$SMOKE_LUA" <<'LUA'
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/Daily", "p")

local daily = root .. "/Daily/2026-05-14.md"
vim.fn.writefile({
  "# Daily",
  "- [ ] #task Later 📅 2026-05-20",
  "- [ ] #task Earlier 📅 2026-05-15",
  "- [ ] #task Middle 📅 2026-05-18",
  "- [x] #task Done 📅 2026-05-16",
  "- [ ] No global 📅 2026-05-14",
}, daily)

local date = require("obsidian-tasks.date")
assert(date.is_valid("2026-02-28"))
assert(not date.is_valid("2026-02-30"))
assert(date.parse_date_expr("tomorrow", { today = "2026-05-14" }) == "2026-05-15")

local query = require("obsidian-tasks.query")
local plan = query.parse([[
not done
due on or before today
priority is above low
sort by due
group by filename
limit 20
]], { today = "2026-05-20" })
assert(#plan.errors == 0, vim.inspect(plan.errors))
assert(#plan.filters == 3)
assert(#plan.sorts == 1)
assert(plan.group_by[1] == "filename")
assert(plan.limit == 20)

local tasks = require("obsidian-tasks")
tasks.setup({
  vault_path = root,
  global_filter = "#task",
  default_query = "due_soon",
  queries = {
    due_soon = [[
not done
due on or before 2026-05-20
sort by due
group by filename
limit 2
]],
    inbox = [[
not done
sort by due
]],
  },
})

tasks.open()
local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
local text = table.concat(lines, "\n")
assert(text:find("Tasks: due_soon", 1, true), text)
assert(text:find("Showing 2 of 3 tasks", 1, true), text)
assert(text:find("Earlier", 1, true), text)
assert(text:find("Middle", 1, true), text)
assert(not text:find("Later", 1, true), text)
assert(not text:find("Done", 1, true), text)
assert(not text:find("No global", 1, true), text)

vim.cmd("ObsidianTasks! inbox")
text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(text:find("Tasks: inbox", 1, true), text)
assert(vim.api.nvim_buf_get_name(0):find("obsidian%-tasks", 1, false), vim.api.nvim_buf_get_name(0))

tasks.run_query("unknown command")
text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(text:find("Query errors:", 1, true), text)
assert(text:find("Unsupported query instruction", 1, true), text)

tasks.open_query("inbox")
lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
local target
for index, line in ipairs(lines) do
  if line:find("Earlier", 1, true) then
    target = index
  end
end
assert(target, table.concat(lines, "\n"))
vim.api.nvim_win_set_cursor(0, { target, 0 })
tasks.toggle_task_at_cursor()
tasks.save_current_tasks()
local source = table.concat(vim.fn.readfile(daily), "\n")
assert(source:find("%- %[x%] #task Earlier"), source)
assert(source:find("%- %[ %] #task Later"), source)
LUA

nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
