#!/usr/bin/env sh
set -eu

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SMOKE_LUA="$(mktemp)"
trap 'rm -f "$SMOKE_LUA"' EXIT

cat > "$SMOKE_LUA" <<'LUA'
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")

local tasks_file = root .. "/Boolean.md"
vim.fn.writefile({
  "# Boolean",
  "- [ ] #task Alpha work item 📅 2026-05-20",
  "- [ ] #task Beta home item 📅 2026-05-21",
  "- [ ] #task Later someday item 📅 2026-06-01",
  "- [ ] #task Recurring routine item 🔁 every day 📅 2026-06-01",
  "- [ ] #task Happens today item 🛫 2026-05-22",
  "- [ ] #task Due in three days item 📅 2026-05-25",
  "- [ ] #task Due after window item 📅 2026-05-26",
  "- [x] #task Done archive item ✅ 2026-05-10",
}, tasks_file)

local tasks = require("obsidian-tasks")
tasks.setup({
  vault_path = root,
  global_filter = "#task",
  enable_lua_filters = true,
})

local scanner = require("obsidian-tasks.scanner")
local query = require("obsidian-tasks.query")
local scanned = scanner.scan_vault({
  vault_path = root,
  global_filter = "#task",
})

local function descriptions(results)
  local values = {}
  for _, task in ipairs(results) do
    table.insert(values, task.description)
  end
  table.sort(values)
  return table.concat(values, "\n")
end

local nested_plan = query.parse("(not done) AND ((description includes Alpha) OR (description includes Beta))")
assert(#nested_plan.errors == 0, vim.inspect(nested_plan.errors))
local nested = query.filter_tasks(scanned, nested_plan)
assert(#nested == 2, descriptions(nested))
assert(descriptions(nested):find("Alpha work item", 1, true), descriptions(nested))
assert(descriptions(nested):find("Beta home item", 1, true), descriptions(nested))

local not_plan = query.parse("(not done) AND NOT (description includes someday)")
assert(#not_plan.errors == 0, vim.inspect(not_plan.errors))
local and_not = query.filter_tasks(scanned, not_plan)
assert(#and_not == 6, descriptions(and_not))

local mixed_plan = query.parse([[
not done
(description includes Alpha) OR (description includes Beta)
]])
assert(#mixed_plan.errors == 0, vim.inspect(mixed_plan.errors))
local mixed = query.filter_tasks(scanned, mixed_plan)
assert(#mixed == 2, descriptions(mixed))

local done_or_someday = query.filter_tasks(scanned, query.parse("(done) OR (description includes someday)"))
assert(#done_or_someday == 2, descriptions(done_or_someday))
assert(descriptions(done_or_someday):find("Done archive item", 1, true), descriptions(done_or_someday))
assert(descriptions(done_or_someday):find("Later someday item", 1, true), descriptions(done_or_someday))

local regex_boolean = query.filter_tasks(scanned, query.parse("(description regex matches /Alpha|Beta/) AND (not done)"))
assert(#regex_boolean == 2, descriptions(regex_boolean))

local recurring_happens_due_plan = query.parse("(is recurring) OR (happens on today) OR (due in 3days)", { today = "2026-05-22" })
assert(#recurring_happens_due_plan.errors == 0, vim.inspect(recurring_happens_due_plan.errors))
local recurring_happens_due = query.filter_tasks(scanned, recurring_happens_due_plan)
local recurring_happens_due_descriptions = descriptions(recurring_happens_due)
assert(#recurring_happens_due == 3, recurring_happens_due_descriptions)
assert(recurring_happens_due_descriptions:find("Recurring routine item", 1, true), recurring_happens_due_descriptions)
assert(recurring_happens_due_descriptions:find("Happens today item", 1, true), recurring_happens_due_descriptions)
assert(recurring_happens_due_descriptions:find("Due in three days item", 1, true), recurring_happens_due_descriptions)
assert(not recurring_happens_due_descriptions:find("Due after window item", 1, true), recurring_happens_due_descriptions)

local function_boolean = query.filter_tasks(scanned, query.parse(
  "(filter by function task.description:find(\"Alpha\", 1, true) ~= nil) OR (done)",
  { config = tasks.config, enable_lua_filters = true }
))
assert(#function_boolean == 2, descriptions(function_boolean))

local invalid_missing_side = query.parse("(not done) AND")
assert(#invalid_missing_side.errors == 1, vim.inspect(invalid_missing_side.errors))
assert(invalid_missing_side.errors[1].message:find("Boolean", 1, true), invalid_missing_side.errors[1].message)

local invalid_paren = query.parse("(not done")
assert(#invalid_paren.errors == 1, vim.inspect(invalid_paren.errors))
assert(invalid_paren.errors[1].message:find("parenthesis", 1, true), invalid_paren.errors[1].message)
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase5-1.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
